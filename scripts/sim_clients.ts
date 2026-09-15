#!/usr/bin/env -S pnpm exec tsx
/**
 * T-2.2: protocol v1 integration sim. Each of N clients joins (`join`) the one shared room, then
 * sends `input` at 20 Hz (TICK_MS) with an increasing seq and a walking pattern, recording every
 * `state`. Verifies:
 *   (a) its own player's `last_seq` is monotonic and never exceeds the highest seq it has sent,
 *   (b) all clients converge on the same player count once everyone has joined,
 *   (c) every position in every `state` stays within the zone's map bounds (docs/maps/*.yaml via
 *       balance.MAPS — never a hardcoded bound here).
 * Also pings once a second (within docs/protocol.md's ping budget) to report p95/mean RTT.
 * Usage: pnpm sim -- --clients 4 --seconds 10 --url ws://localhost:8080
 */
import WebSocket from "ws";
import {
  balance,
  PROTOCOL_VERSION,
  TICK_MS,
  parseServerMessage,
  type StateMessage,
} from "../packages/shared-rules/src/index.js";

const arg = (k: string, d: string): string => {
  const i = process.argv.indexOf(`--${k}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : d;
};
const N = Number(arg("clients", "4"));
const SECONDS = Number(arg("seconds", "10"));
const URL = arg("url", "ws://localhost:8080");
const ZONE_ID = "clinic_lobby";

const map = balance.MAPS[ZONE_ID];
if (map === undefined) {
  console.error(`sim_clients: unknown zone "${ZONE_ID}" in balance.MAPS`);
  process.exit(1);
}
const boundsW = map.cols * map.tile_size;
const boundsH = map.rows * map.tile_size;

interface ClientResult {
  id: number;
  playerId: string | null;
  sentSeqs: number;
  lastSeqSeen: number;
  seqViolations: string[];
  boundsViolations: string[];
  finalPlayerCount: number;
  errors: string[];
}

const rtts: number[] = [];

/** Walk right for 2s, left for 2s (20 Hz × 40 ticks), jumping every 1.5s — enough motion to exercise walls/platforms/gravity without needing a smarter AI. */
function walkingInput(tickIndex: number): { dir: -1 | 0 | 1; jump: boolean } {
  const phase = Math.floor(tickIndex / 40) % 2;
  const dir: -1 | 0 | 1 = phase === 0 ? 1 : -1;
  const jump = tickIndex % 30 === 0;
  return { dir, jump };
}

function runClient(id: number): Promise<ClientResult> {
  return new Promise((resolve) => {
    const result: ClientResult = {
      id,
      playerId: null,
      sentSeqs: 0,
      lastSeqSeen: 0,
      seqViolations: [],
      boundsViolations: [],
      finalPlayerCount: 0,
      errors: [],
    };
    const ws = new WebSocket(URL);
    let seq = 0;
    let serverTick = 0;
    let tickIndex = 0;
    let inputTimer: ReturnType<typeof setInterval> | null = null;
    let pingTimer: ReturnType<typeof setInterval> | null = null;

    function onState(msg: StateMessage): void {
      serverTick = msg.tick;
      result.finalPlayerCount = msg.players.length;
      const pid = result.playerId;
      if (pid !== null) {
        const mine = msg.last_seq[pid];
        if (mine !== undefined) {
          if (mine < result.lastSeqSeen) {
            result.seqViolations.push(`last_seq went backwards: ${mine} < ${result.lastSeqSeen}`);
          }
          if (mine > result.sentSeqs) {
            result.seqViolations.push(
              `server applied seq ${mine} we never sent (sent up to ${result.sentSeqs})`,
            );
          }
          result.lastSeqSeen = mine;
        }
      }
      for (const p of msg.players) {
        if (p.pos.x < 0 || p.pos.x > boundsW || p.pos.y < 0 || p.pos.y > boundsH) {
          result.boundsViolations.push(`${p.id} out of bounds: (${p.pos.x}, ${p.pos.y})`);
        }
      }
    }

    function stopTimers(): void {
      if (inputTimer !== null) clearInterval(inputTimer);
      if (pingTimer !== null) clearInterval(pingTimer);
      inputTimer = null;
      pingTimer = null;
    }

    ws.on("open", () => {
      ws.send(
        JSON.stringify({ t: "join", protocol: PROTOCOL_VERSION, token: "sim", character_id: `sim_${id}` }),
      );
    });

    ws.on("message", (raw) => {
      const msg = parseServerMessage(String(raw));
      if (msg === null) {
        result.errors.push("unparseable server message");
        return;
      }
      switch (msg.t) {
        case "error":
          result.errors.push(`${msg.code}: ${msg.msg_key}`);
          return;
        case "joined":
          result.playerId = msg.player_id;
          serverTick = msg.tick;
          tickIndex = 0;
          inputTimer = setInterval(() => {
            const w = walkingInput(tickIndex++);
            seq += 1;
            result.sentSeqs = seq;
            ws.send(
              JSON.stringify({ t: "input", seq, tick: serverTick, dir: w.dir, jump: w.jump, attack: false }),
            );
          }, TICK_MS);
          pingTimer = setInterval(() => {
            ws.send(JSON.stringify({ t: "ping", ts: Date.now() }));
          }, 1000);
          return;
        case "pong":
          rtts.push(Date.now() - msg.ts);
          return;
        case "state":
          onState(msg);
          return;
        default:
          return;
      }
    });

    ws.on("error", (e) => {
      result.errors.push(e.message);
    });
    ws.on("close", stopTimers);

    setTimeout(() => {
      stopTimers();
      ws.close();
      resolve(result);
    }, SECONDS * 1000);
  });
}

(async () => {
  console.log(
    `sim_clients: ${N} clients × ${SECONDS}s → ${URL} (protocol ${PROTOCOL_VERSION}, zone ${ZONE_ID})`,
  );
  const results = await Promise.all(Array.from({ length: N }, (_, i) => runClient(i)));

  let violations = 0;
  for (const r of results) {
    if (r.playerId === null) {
      console.error(`client ${r.id}: never joined`);
      violations++;
    }
    for (const v of [...r.seqViolations, ...r.boundsViolations, ...r.errors]) {
      console.error(`client ${r.id}: ${v}`);
      violations++;
    }
  }
  const counts = new Set(results.map((r) => r.finalPlayerCount));
  if (counts.size > 1) {
    console.error(`clients disagree on player count: ${[...counts].join(", ")}`);
    violations++;
  }

  rtts.sort((a, b) => a - b);
  const p95 = rtts.length > 0 ? (rtts[Math.floor(rtts.length * 0.95)] ?? NaN) : NaN;
  const mean = rtts.length > 0 ? rtts.reduce((a, b) => a + b, 0) / rtts.length : NaN;
  console.log(
    JSON.stringify({
      clients: N,
      joined: results.filter((r) => r.playerId !== null).length,
      final_player_count: [...counts][0] ?? 0,
      violations,
      p95_rtt_ms: p95,
      mean_rtt_ms: mean,
    }),
  );
  process.exit(violations === 0 ? 0 : 1);
})();
