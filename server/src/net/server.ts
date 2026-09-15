import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { performance } from "node:perf_hooks";
import { WebSocketServer, WebSocket } from "ws";
import pino from "pino";
import {
  PROTOCOL_VERSION,
  TICK_MS,
  parseClientMessage,
  type ClientMessage,
  type InputMessage,
  type JoinMessage,
  type ChatMessage,
  type LootPickupMessage,
  type LootMessage,
  type ServerMessage,
} from "@hamirpaa/shared-rules";
import { healthPayload } from "../health.js";
import { newBucket, take, type Bucket } from "./ratelimit.js";
import { createDefaultZone, Zone } from "../world/zone.js";
import type { PlayerInput } from "../world/player_sim.js";

export interface GameServerOptions {
  host?: string;
  port?: number; // 0 = random (tests)
  logLevel?: string;
  rate?: { perSec: number; burst: number };
  maxInvalid?: number;
  /** T-2.4: seeds the zone's combat/loot rng (server/src/world/rng.ts). Tests pass a fixed seed for reproducible rolls; production defaults to Date.now(). */
  seed?: number;
  /** Test-only: use this pre-built Zone (e.g. a small custom map with a monster spawn right next to
   * the player spawn, for deterministic combat tests) instead of the default clinic_lobby room.
   * Never set by server/src/index.ts. */
  zone?: Zone;
}

/** Per-message-type rate limits from docs/protocol.md's message table (column "Server validation"). Types not listed here (join is gated by "one join per socket" instead) fall back to the connection-wide bucket only. */
const TYPE_RATE: Partial<Record<ClientMessage["t"], { perSec: number; burst: number }>> = {
  ping: { perSec: 1, burst: 4 },
  leave: { perSec: 1, burst: 2 },
  input: { perSec: 25, burst: 50 },
  loot_pickup: { perSec: 5, burst: 10 },
  chat: { perSec: 1, burst: 3 },
};

/** docs/protocol.md `input` row: "`tick` within ±40 ticks (±2 s) of the server tick" — a replay/clock-skew bound, not gameplay balance, so (like MAX_CLIENT_MESSAGE_BYTES in protocol.ts) it lives here as a plain constant. */
const INPUT_TICK_TOLERANCE = 40;

/** Keep only enough recent tick-duration samples to make a p95 meaningful without growing forever. */
const TICK_SAMPLE_WINDOW = 200;

interface Session {
  ws: WebSocket;
  bucket: Bucket;
  typeBuckets: Map<ClientMessage["t"], Bucket>;
  invalid: number;
  invalidSince: number;
  /** Set once, the first time `join` is accepted; never cleared, so a `leave`d socket still can't re-join (protocol.md: "second `join` on the same socket → invalid_message"). */
  playerId: string | null;
}

/**
 * Minimal authoritative server: HTTP /health + WebSocket, hosting ONE room (Zone) for up to
 * MAX_PLAYERS_PER_ZONE players. validate → rate-limit → handler; the 20 Hz simulation tick itself is
 * driven from the outside (server/src/index.ts's setInterval) via `step()`, per
 * .claude/skills/server-architecture — GameServer never sets its own timer, and never touches a DB.
 */
export class GameServer {
  private readonly http: Server;
  private readonly wss: WebSocketServer;
  private readonly sessions = new Set<Session>();
  private readonly log: pino.Logger;
  private readonly rate: { perSec: number; burst: number };
  private readonly maxInvalid: number;
  private readonly opts: GameServerOptions;
  private readonly zone: Zone;
  private nextPlayerId = 1;
  private readonly tickDurationsMs: number[] = [];

  constructor(opts: GameServerOptions = {}) {
    this.opts = opts;
    this.log = pino({ level: opts.logLevel ?? "info" });
    this.rate = opts.rate ?? { perSec: 20, burst: 40 };
    this.maxInvalid = opts.maxInvalid ?? 3;
    this.zone = opts.zone ?? createDefaultZone(opts.seed !== undefined ? { seed: opts.seed } : {});
    this.http = createServer((req, res) => this.onHttp(req, res));
    this.wss = new WebSocketServer({ server: this.http });
    this.wss.on("connection", (ws) => this.onConnection(ws));
  }

  /** Open socket count — a liveness figure for /health, not the zone's joined-player count. */
  get players(): number {
    return this.sessions.size;
  }

  listen(): Promise<{ port: number; host: string }> {
    return new Promise((resolve) => {
      const host = this.opts.host ?? "127.0.0.1";
      this.http.listen(this.opts.port ?? 0, host, () => {
        const addr = this.http.address() as AddressInfo;
        this.log.info({ port: addr.port, host }, "listening");
        resolve({ port: addr.port, host });
      });
    });
  }

  close(): Promise<void> {
    for (const s of this.sessions) s.ws.terminate();
    return new Promise((resolve) => this.wss.close(() => this.http.close(() => resolve())));
  }

  /**
   * One fixed simulation step + broadcast, called by the tick loop (server/src/index.ts) or directly
   * by tests. No `await`, no DB access — .claude/skills/server-architecture's tick-loop rule.
   */
  step(dt: number): void {
    const start = performance.now();
    const events = this.zone.step(dt);
    for (const ev of events) this.broadcastToZone(ev);
    // T-2.5: drops are private, so `state` can't be one shared broadcast anymore — the players/
    // monsters/last_seq parts ARE identical for everyone (built once here), only `drops` differs
    // per socket (Zone.dropsFor, a cheap per-owner filter).
    const shared = this.zone.sharedSnapshot();
    for (const s of this.sessions) {
      if (s.playerId !== null && this.zone.hasPlayer(s.playerId)) {
        this.send(s, { t: "state", ...shared, drops: this.zone.dropsFor(s.playerId) });
      }
    }
    this.recordTickDuration(performance.now() - start);
  }

  /** Test-only passthrough to Zone.setPlayerLevelForTest — lets tests reach a level-gated skill
   * (e.g. cooldown testing) without grinding real kills. Never called by production code paths. */
  debugSetPlayerLevel(playerId: string, level: number): void {
    this.zone.setPlayerLevelForTest(playerId, level);
  }

  /** Test-only passthrough to Zone.setPlayerHpForTest — lets a test put a player one hit from death. */
  debugSetPlayerHp(playerId: string, hp: number): void {
    this.zone.setPlayerHpForTest(playerId, hp);
  }

  private recordTickDuration(ms: number): void {
    this.tickDurationsMs.push(ms);
    if (this.tickDurationsMs.length > TICK_SAMPLE_WINDOW) this.tickDurationsMs.shift();
  }

  private tickP95Ms(): number {
    if (this.tickDurationsMs.length === 0) return 0;
    const sorted = [...this.tickDurationsMs].sort((a, b) => a - b);
    const idx = Math.min(sorted.length - 1, Math.floor(sorted.length * 0.95));
    return sorted[idx] ?? 0;
  }

  private onHttp(req: IncomingMessage, res: ServerResponse): void {
    if (req.url === "/health") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify(healthPayload(this.players, { tickP95Ms: this.tickP95Ms() })));
      return;
    }
    res.writeHead(404);
    res.end();
  }

  private onConnection(ws: WebSocket): void {
    const session: Session = {
      ws,
      bucket: newBucket(this.rate.burst, Date.now()),
      typeBuckets: new Map(),
      invalid: 0,
      invalidSince: Date.now(),
      playerId: null,
    };
    this.sessions.add(session);
    ws.on("message", (raw) => this.onMessage(session, String(raw)));
    ws.on("close", () => this.onClose(session));
    ws.on("error", (err) => this.log.warn({ err }, "ws error"));
  }

  private onClose(session: Session): void {
    this.sessions.delete(session);
    if (session.playerId !== null && this.zone.hasPlayer(session.playerId)) {
      this.zone.removePlayer(session.playerId);
      this.broadcastToZone({ t: "left", player_id: session.playerId });
    }
  }

  private onMessage(session: Session, raw: string): void {
    const now = Date.now();
    if (!take(session.bucket, this.rate.perSec, this.rate.burst, now)) {
      this.send(session, { t: "error", code: "rate_limited", msg_key: "error.rate_limited" });
      return;
    }
    const msg = parseClientMessage(raw);
    if (msg === null) {
      this.log.warn({ len: raw.length }, "invalid message dropped");
      this.rejectInvalid(session, now);
      return;
    }
    if (!this.takeTypeRate(session, msg.t, now)) {
      this.send(session, { t: "error", code: "rate_limited", msg_key: "error.rate_limited" });
      return;
    }
    this.handle(session, msg, now);
  }

  private takeTypeRate(session: Session, t: ClientMessage["t"], now: number): boolean {
    const cfg = TYPE_RATE[t];
    if (cfg === undefined) return true;
    let bucket = session.typeBuckets.get(t);
    if (bucket === undefined) {
      bucket = newBucket(cfg.burst, now);
      session.typeBuckets.set(t, bucket);
    }
    return take(bucket, cfg.perSec, cfg.burst, now);
  }

  /** Shared "log + drop + error(invalid_message)" path; 3 in 10 s closes the socket (1008). Used for schema failures AND handler-level state violations (second `join`, `chat` while not joined) — both are the same class of misbehaviour. */
  private rejectInvalid(session: Session, now: number): void {
    if (now - session.invalidSince > 10_000) {
      session.invalid = 0;
      session.invalidSince = now;
    }
    session.invalid += 1;
    this.send(session, { t: "error", code: "invalid_message", msg_key: "error.invalid_message" });
    if (session.invalid >= this.maxInvalid) session.ws.close(1008, "too many invalid messages");
  }

  private handle(session: Session, msg: ClientMessage, now: number): void {
    switch (msg.t) {
      case "ping":
        this.send(session, { t: "pong", ts: msg.ts, server_ts: now });
        return;
      case "join":
        this.handleJoin(session, msg);
        return;
      case "leave":
        this.handleLeave(session);
        return;
      case "input":
        this.handleInput(session, msg);
        return;
      case "chat":
        this.handleChat(session, msg, now);
        return;
      case "loot_pickup":
        this.handleLootPickup(session, msg);
        return;
    }
  }

  private handleJoin(session: Session, msg: JoinMessage): void {
    if (session.playerId !== null) {
      this.rejectInvalid(session, Date.now()); // second `join` on the same socket
      return;
    }
    if (msg.protocol !== PROTOCOL_VERSION) {
      this.send(session, { t: "error", code: "protocol_mismatch", msg_key: "error.protocol_mismatch" });
      session.ws.close(1008, "protocol_mismatch");
      return;
    }
    // Token → session/character resolution is T-3.2; for now any non-empty token is accepted (the
    // schema already enforces min(1)) and `character_id` doubles as the display name.
    if (this.zone.isFull()) {
      this.send(session, { t: "error", code: "zone_full", msg_key: "error.zone_full" });
      session.ws.close(1008, "zone_full");
      return;
    }
    const playerId = `p_${this.nextPlayerId++}`;
    session.playerId = playerId;
    this.zone.addPlayer(playerId, msg.character_id);
    this.send(session, {
      t: "joined",
      player_id: playerId,
      zone_id: this.zone.id,
      tick: this.zone.tick,
      tick_ms: TICK_MS,
      state: this.zone.snapshotFor(playerId),
    });
    // Peers are NOT sent a `joined` — the new player simply appears in their next `state`
    // (docs/protocol.md § Join handshake).
  }

  private handleLeave(session: Session): void {
    // "must be joined" (docs/protocol.md `leave` row); on failure the row says "drop", not an error.
    if (session.playerId === null || !this.zone.hasPlayer(session.playerId)) return;
    this.zone.removePlayer(session.playerId);
    this.broadcastToZone({ t: "left", player_id: session.playerId });
  }

  private handleInput(session: Session, msg: InputMessage): void {
    // "must be joined and alive" / seq monotonic / tick skew — every failure here is a SILENT drop
    // (docs/protocol.md "Amplification": replying to a 20 Hz intent would be a broadcast-storm risk).
    if (session.playerId === null || !this.zone.hasPlayer(session.playerId)) return;
    if (!this.zone.isAlive(session.playerId)) return;
    if (Math.abs(msg.tick - this.zone.tick) > INPUT_TICK_TOLERANCE) return;
    const input: PlayerInput = {
      seq: msg.seq,
      dir: msg.dir,
      jump: msg.jump,
      attack: msg.attack,
      ...(msg.skill_id !== undefined ? { skill_id: msg.skill_id } : {}),
    };
    this.zone.queueInput(session.playerId, input);
  }

  private handleChat(session: Session, msg: ChatMessage, now: number): void {
    if (session.playerId === null || !this.zone.hasPlayer(session.playerId)) {
      this.rejectInvalid(session, now); // low-frequency intent in the wrong state → an error, not a silent drop
      return;
    }
    if (msg.channel === "party") {
      // Parties don't exist yet (future task): no player is ever a party member, so every `party`
      // chat currently fails "party requires party membership".
      this.rejectInvalid(session, now);
      return;
    }
    this.broadcastToZone({
      t: "chat_msg",
      player_id: session.playerId,
      channel: msg.channel,
      text: msg.text,
      ts: now,
    });
  }

  /** docs/protocol.md § Loot: "must be joined and alive; drop exists, unclaimed, within
   * PICKUP_RADIUS_PX of the player; inventory has room" — dead → `error.not_alive`; every other
   * failure (not joined, unknown drop, someone else's drop, out of range) → `loot {added:false}` to
   * the requester only, never a broadcast; success → `loot {added:true}` broadcast to the zone. */
  private handleLootPickup(session: Session, msg: LootPickupMessage): void {
    if (session.playerId === null || !this.zone.hasPlayer(session.playerId)) {
      this.rejectInvalid(session, Date.now()); // low-frequency intent in the wrong state → an error, not a silent drop
      return;
    }
    if (!this.zone.isAlive(session.playerId)) {
      this.send(session, { t: "error", code: "not_alive", msg_key: "error.not_alive" });
      return;
    }
    const result = this.zone.pickup(session.playerId, msg.drop_id);
    const lootMsg: LootMessage = {
      t: "loot",
      player_id: session.playerId,
      drop_id: msg.drop_id,
      item_id: result.itemId,
      money: result.money,
      added: result.added,
    };
    if (result.added) {
      this.broadcastToZone(lootMsg);
    } else {
      this.send(session, lootMsg);
    }
  }

  /** Every session whose player is currently in the zone — `state`/`left`/`chat_msg` all go here. */
  private broadcastToZone(msg: ServerMessage): void {
    for (const s of this.sessions) {
      if (s.playerId !== null && this.zone.hasPlayer(s.playerId)) this.send(s, msg);
    }
  }

  private send(session: Session, msg: ServerMessage): void {
    if (session.ws.readyState === WebSocket.OPEN) session.ws.send(JSON.stringify(msg));
  }
}
