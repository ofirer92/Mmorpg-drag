// T-2.2: one authoritative room. Fixed-step 20 Hz simulation (server/src/index.ts drives the real
// clock via setInterval(TICK_MS) and calls zone.tick(dt) — Zone itself has no timers/sockets/DB, so
// it is directly testable: `zone.tick(dtSeconds)` + `zone.snapshot()`).
import { balance, type PlayerState, type Snapshot } from "@hamirpaa/shared-rules";
import { createPlayerState, stepPlayer, type PlayerInput, type PlayerSimState } from "./player_sim.js";
import type { MapDef } from "./tilemap.js";

export const MAX_PLAYERS_PER_ZONE = 4;
export const DEFAULT_ZONE_ID = "clinic_lobby";

interface ZonePlayer {
  id: string;
  name: string;
  sim: PlayerSimState;
  lastSeq: number;
  pendingInput: PlayerInput | null;
  hp: number;
  maxHp: number;
  level: number;
  xp: number;
  alive: boolean;
}

function neutralInput(): PlayerInput {
  return { seq: -1, dir: 0, jump: false, attack: false };
}

function animFor(sim: PlayerSimState): string {
  if (!sim.onFloor) return "jump";
  return sim.vel.x !== 0 ? "run" : "idle";
}

/** One room, up to MAX_PLAYERS_PER_ZONE players. Movement-only for T-2.2 (combat/loot are later tasks; monsters/drops are always empty here). */
export class Zone {
  readonly id: string;
  readonly map: MapDef;
  private tickNo = 0;
  private readonly players = new Map<string, ZonePlayer>();

  constructor(id: string, map: MapDef) {
    this.id = id;
    this.map = map;
  }

  get tick(): number {
    return this.tickNo;
  }

  get playerCount(): number {
    return this.players.size;
  }

  isFull(): boolean {
    return this.players.size >= MAX_PLAYERS_PER_ZONE;
  }

  hasPlayer(id: string): boolean {
    return this.players.has(id);
  }

  isAlive(id: string): boolean {
    return this.players.get(id)?.alive ?? false;
  }

  lastSeqOf(id: string): number {
    return this.players.get(id)?.lastSeq ?? 0;
  }

  /** Spawns a new player at the map's spawn point. No-op if the id is already in the zone. */
  addPlayer(id: string, name: string): void {
    if (this.players.has(id)) return;
    const baseHp = balance.CLASSES.archetypes.stim.base_hp;
    this.players.set(id, {
      id,
      name,
      sim: createPlayerState({ x: this.map.spawn.x, y: this.map.spawn.y }),
      lastSeq: 0,
      pendingInput: null,
      hp: baseHp,
      maxHp: baseHp,
      level: 1,
      xp: 0,
      alive: true,
    });
  }

  removePlayer(id: string): boolean {
    return this.players.delete(id);
  }

  /**
   * Queue the latest input for a player, applied on the next tick(). Silently ignored (per
   * docs/protocol.md `input` row) if the player isn't in the zone, is dead, or `seq` is not strictly
   * greater than the last applied seq (duplicate/replay) — the caller (net/server.ts) does the same
   * check before calling this, this is the authoritative second gate.
   */
  queueInput(id: string, input: PlayerInput): void {
    const p = this.players.get(id);
    if (p === undefined || !p.alive) return;
    if (input.seq <= p.lastSeq) return;
    p.pendingInput = input;
  }

  /**
   * Advance the simulation by one fixed step. Applies the latest queued input per player (a neutral
   * idle input if none arrived this tick — packet loss, not a crash) via world/player_sim.ts only.
   * No `await`, no DB: safe to call from a `setInterval` tick loop.
   */
  step(dt: number): void {
    this.tickNo += 1;
    for (const p of this.players.values()) {
      if (!p.alive) continue;
      const input = p.pendingInput ?? neutralInput();
      if (p.pendingInput !== null) {
        p.lastSeq = p.pendingInput.seq;
        p.pendingInput = null;
      }
      p.sim = stepPlayer(p.sim, input, dt, this.map);
    }
  }

  snapshot(): Snapshot {
    const last_seq: Record<string, number> = {};
    const players: PlayerState[] = [];
    for (const p of this.players.values()) {
      last_seq[p.id] = p.lastSeq;
      players.push({
        id: p.id,
        name: p.name,
        pos: { x: p.sim.pos.x, y: p.sim.pos.y },
        vel: { x: p.sim.vel.x, y: p.sim.vel.y },
        hp: p.hp,
        max_hp: p.maxHp,
        level: p.level,
        xp: p.xp,
        facing: p.sim.facing,
        anim: animFor(p.sim),
        alive: p.alive,
      });
    }
    return { tick: this.tickNo, last_seq, players, monsters: [], drops: [] };
  }
}

export function createDefaultZone(): Zone {
  const map = balance.MAPS[DEFAULT_ZONE_ID];
  if (map === undefined) {
    throw new Error(`map not found in balance.MAPS: ${DEFAULT_ZONE_ID}`);
  }
  return new Zone(DEFAULT_ZONE_ID, map);
}
