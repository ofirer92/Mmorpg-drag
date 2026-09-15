// T-2.2/T-2.4: one authoritative room. Fixed-step 20 Hz simulation (server/src/index.ts drives the real
// clock via setInterval(TICK_MS) and calls zone.step(dt) — Zone itself has no timers/sockets/DB, so
// it is directly testable: `zone.step(dtSeconds)` + `zone.snapshotFor(playerId)`).
//
// T-2.4 combat: `step()` returns every attack/damage/died fact that happened this tick (in order);
// net/server.ts just broadcasts them. Zone is the ONLY place on the server allowed to call
// shared-rules combat/loot/status/progression functions (CLAUDE.md — the client never computes
// damage; here that becomes "no handler in net/ computes damage either").
import {
  balance,
  damage,
  apply_damage,
  is_dead,
  roll_loot,
  roll_money,
  skill_unlocked,
  skill_ready,
  skill_crash_hits,
  next_consecutive_hits,
  crash_triggers,
  crash_duration_s,
  damage_taken,
  hp_at_level,
  attack_at_level,
  defense_at_level,
  level_for_xp,
  group_xp_share,
  PICKUP_RADIUS_PX,
  DROP_LIFETIME_TICKS,
  MAX_TARGETS_PER_ATTACK,
  CRIT_CHANCE,
  type PlayerState,
  type MonsterState,
  type DropState,
  type Snapshot,
  type AttackMessage,
  type DamageMessage,
  type DiedMessage,
} from "@hamirpaa/shared-rules";
import { createPlayerState, stepPlayer, type PlayerInput, type PlayerSimState } from "./player_sim.js";
import {
  createMonsterState,
  stepMonster,
  MONSTER_WIDTH_PX,
  MONSTER_HEIGHT_PX,
  MONSTER_ATTACK_POWER,
  type MonsterSimState,
  type MonsterAiParams,
  type MonsterTarget,
} from "./monster_sim.js";
import { targetsInRange, type AttackCandidate } from "./combat_targets.js";
import { createRng, type Rng } from "./rng.js";
import type { MapDef, Vec2 } from "./tilemap.js";

export const MAX_PLAYERS_PER_ZONE = 4;
export const DEFAULT_ZONE_ID = "clinic_lobby";

/** clinic_lobby.gd's RESPAWN_DELAY_S: a phase-0 documented default (full hp, no penalty), not a
 * balance number — see that file's doc comment. Kept here rather than in YAML for the same reason
 * player_sim.ts's PLAYER_WIDTH_PX stays local: it's pacing/UX, not a gameplay-tuning number. */
const PLAYER_RESPAWN_DELAY_S = 2;

type PlayerArchetype = "stim";
/** Phase 2 only ever spawns the "stim" archetype (archetype select is Phase 1, blocked on Q1) — a
 * literal type here, rather than a dynamic `string` lookup into balance.CLASSES.archetypes, avoids
 * needing the ADR-012 Record<string,...> treatment for CLASSES until more archetypes are playable. */
const DEFAULT_ARCHETYPE: PlayerArchetype = "stim";

type CombatEvent = AttackMessage | DamageMessage | DiedMessage;

interface ZonePlayer {
  id: string;
  name: string;
  archetype: PlayerArchetype;
  sim: PlayerSimState;
  lastSeq: number;
  pendingInput: PlayerInput | null;
  hp: number;
  maxHp: number;
  attack: number;
  defense: number;
  level: number;
  xp: number;
  alive: boolean;
  deadElapsed: number;
  consecutiveHits: number;
  crashActive: boolean;
  crashRemaining: number;
  /** skill id → the zone clock (`elapsedS`) value it was last used at. */
  skillLastUse: Map<string, number>;
}

interface ZoneMonster {
  id: string;
  kind: string;
  level: number;
  hp: number;
  maxHp: number;
  attack: number;
  defense: number;
  xpReward: number;
  lootTable: string;
  moneyMin: number;
  moneyMax: number;
  attackSpeed: number;
  aiParams: MonsterAiParams;
  sim: MonsterSimState;
  alive: boolean;
  deadElapsed: number;
  spawnPos: Vec2;
  /** Player ids that landed at least one hit since the last spawn/respawn — T-2.5/T-2.6 eligibility. */
  damagedBy: Set<string>;
}

interface ZoneDrop {
  id: string;
  ownerId: string;
  pos: Vec2;
  itemId: string | null;
  money: number;
  expiresTick: number;
}

export interface PickupResult {
  itemId: string | null;
  money: number;
  added: boolean;
}

function neutralInput(): PlayerInput {
  return { seq: -1, dir: 0, jump: false, attack: false };
}

function animFor(sim: PlayerSimState): string {
  if (!sim.onFloor) return "jump";
  return sim.vel.x !== 0 ? "run" : "idle";
}

function monsterAnimFor(sim: MonsterSimState): string {
  if (sim.aiState === "dead") return "dead";
  if (sim.aiState === "hurt") return "hurt";
  if (sim.aiState === "attack") return "attack";
  return sim.vel.x !== 0 ? "run" : "idle";
}

function cellCenter(cell: [number, number], tileSize: number): Vec2 {
  return { x: cell[0] * tileSize + tileSize / 2, y: cell[1] * tileSize + tileSize / 2 };
}

function distance(a: Vec2, b: Vec2): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.sqrt(dx * dx + dy * dy);
}

/** {attack, defense, level, hp} view shared-rules' damage()/is_dead() expect — works for both players and monsters. */
interface CombatView {
  attack: number;
  defense: number;
  level: number;
  hp: number;
}

function recomputePlayerStats(p: ZonePlayer): void {
  const base = balance.CLASSES.archetypes[p.archetype];
  p.maxHp = hp_at_level(base, base.growth, p.level);
  p.attack = attack_at_level(base, base.growth, p.level);
  p.defense = defense_at_level(base, base.growth, p.level);
}

/** One room, up to MAX_PLAYERS_PER_ZONE players, monsters spawned from `map.monster_spawns`. */
export class Zone {
  readonly id: string;
  readonly map: MapDef;
  private tickNo = 0;
  /** Seconds of simulated time since the zone was created — the server clock skill cooldowns are timestamped against (mirrors LocalServer's `_time`). */
  private elapsedS = 0;
  private readonly players = new Map<string, ZonePlayer>();
  private readonly monsters = new Map<string, ZoneMonster>();
  private readonly drops = new Map<string, ZoneDrop>();
  private nextDropId = 1;
  private readonly rng: Rng;

  constructor(id: string, map: MapDef, opts: { seed?: number } = {}) {
    this.id = id;
    this.map = map;
    this.rng = createRng(opts.seed ?? Date.now());
    this.spawnMonsters();
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

  private spawnMonsters(): void {
    let idx = 0;
    for (const spawn of this.map.monster_spawns) {
      idx += 1;
      const def = balance.MONSTERS.monsters[spawn.id];
      if (def === undefined) continue; // unknown monster kind in map data — validate_balance.py catches this; never crash at runtime either
      const pos = cellCenter(spawn.cell, this.map.tile_size);
      const id = `m_${idx}`;
      this.monsters.set(id, {
        id,
        kind: spawn.id,
        level: def.level,
        hp: def.hp,
        maxHp: def.hp,
        attack: def.attack,
        defense: def.defense,
        xpReward: def.xp,
        lootTable: def.loot_table,
        moneyMin: def.money.min,
        moneyMax: def.money.max,
        attackSpeed: def.attack_speed,
        aiParams: def.ai_params,
        sim: createMonsterState(pos),
        alive: true,
        deadElapsed: 0,
        spawnPos: pos,
        damagedBy: new Set(),
      });
    }
  }

  /** Spawns a new player at the map's spawn point. No-op if the id is already in the zone. */
  addPlayer(id: string, name: string): void {
    if (this.players.has(id)) return;
    const p: ZonePlayer = {
      id,
      name,
      archetype: DEFAULT_ARCHETYPE,
      sim: createPlayerState({ x: this.map.spawn.x, y: this.map.spawn.y }),
      lastSeq: 0,
      pendingInput: null,
      hp: 0,
      maxHp: 0,
      attack: 0,
      defense: 0,
      level: 1,
      xp: 0,
      alive: true,
      deadElapsed: 0,
      consecutiveHits: 0,
      crashActive: false,
      crashRemaining: 0,
      skillLastUse: new Map(),
    };
    recomputePlayerStats(p);
    p.hp = p.maxHp;
    this.players.set(id, p);
  }

  removePlayer(id: string): boolean {
    return this.players.delete(id);
  }

  /**
   * Queue the latest input for a player, applied on the next step(). Silently ignored (per
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

  /** Test-only hook: force a player's level (and recompute derived stats) without granting real xp,
   * for tests that need a level-gated skill (e.g. cooldown gating on a level-3+ skill) without
   * grinding kills. Never called by net/server.ts. No-op for an unknown id. */
  setPlayerLevelForTest(id: string, level: number): void {
    const p = this.players.get(id);
    if (p === undefined) return;
    p.level = level;
    recomputePlayerStats(p);
    p.hp = p.maxHp;
  }

  /** Test-only hook: force a player's current hp (clamped to [0, maxHp]) so a test can put them one
   * hit from death without simulating dozens of real combat ticks. Never called by net/server.ts. */
  setPlayerHpForTest(id: string, hp: number): void {
    const p = this.players.get(id);
    if (p === undefined) return;
    p.hp = Math.max(0, Math.min(p.maxHp, hp));
  }

  /**
   * Advance the simulation by one fixed step: movement, then player attacks, then monster AI/attacks,
   * then drop expiry. Returns every attack/damage/died fact that happened this tick, in order — the
   * caller (net/server.ts) broadcasts them and then sends everyone their own `state`. No `await`, no
   * DB: safe to call from a `setInterval` tick loop.
   */
  step(dt: number): CombatEvent[] {
    this.tickNo += 1;
    this.elapsedS += dt;
    const events: CombatEvent[] = [];

    const pendingAttacks: Array<{ player: ZonePlayer; skillId: string | undefined }> = [];
    for (const p of this.players.values()) {
      if (!p.alive) {
        this.tickPlayerRespawn(p, dt);
        continue;
      }
      const input = p.pendingInput ?? neutralInput();
      if (p.pendingInput !== null) {
        p.lastSeq = p.pendingInput.seq;
        p.pendingInput = null;
      }
      p.sim = stepPlayer(p.sim, input, dt, this.map);
      if (p.crashActive) {
        p.crashRemaining -= dt;
        if (p.crashRemaining <= 0) {
          p.crashActive = false;
          p.crashRemaining = 0;
        }
      }
      if (input.attack) pendingAttacks.push({ player: p, skillId: input.skill_id });
    }
    for (const { player, skillId } of pendingAttacks) {
      events.push(...this.resolvePlayerAttack(player, skillId));
    }
    for (const m of this.monsters.values()) {
      if (!m.alive) {
        this.tickMonsterRespawn(m, dt);
        continue;
      }
      events.push(...this.stepMonsterAndMaybeAttack(m, dt));
    }
    this.expireDrops();
    return events;
  }

  private tickPlayerRespawn(p: ZonePlayer, dt: number): void {
    p.deadElapsed += dt;
    if (p.deadElapsed < PLAYER_RESPAWN_DELAY_S) return;
    p.alive = true;
    p.deadElapsed = 0;
    p.sim = createPlayerState({ x: this.map.spawn.x, y: this.map.spawn.y });
    p.hp = p.maxHp;
    p.consecutiveHits = 0;
    p.crashActive = false;
    p.crashRemaining = 0;
  }

  private tickMonsterRespawn(m: ZoneMonster, dt: number): void {
    m.deadElapsed += dt;
    if (m.deadElapsed < balance.MONSTERS.respawn_delay_s) return;
    m.hp = m.maxHp;
    m.alive = true;
    m.deadElapsed = 0;
    m.sim = createMonsterState(m.spawnPos);
    m.damagedBy.clear();
  }

  private expireDrops(): void {
    for (const [id, d] of this.drops) {
      if (this.tickNo >= d.expiresTick) this.drops.delete(id);
    }
  }

  private combatViewPlayer(p: ZonePlayer): CombatView {
    return { attack: p.attack, defense: p.defense, level: p.level, hp: p.hp };
  }

  private combatViewMonster(m: ZoneMonster): CombatView {
    return { attack: m.attack, defense: m.defense, level: m.level, hp: m.hp };
  }

  private registerLandedHit(p: ZonePlayer): void {
    p.consecutiveHits = next_consecutive_hits(p.consecutiveHits, true);
    if (crash_triggers(p.consecutiveHits)) {
      p.consecutiveHits = 0;
      p.crashActive = true;
      p.crashRemaining = crash_duration_s();
    }
  }

  /** input.attack + optional input.skill_id → a resolved attack this tick, server-side hit detection
   * only (docs/protocol.md § Attack → damage → death). Unknown/locked/on-cooldown skills are
   * silently rejected (no `attack` fact, no `error` — this rides inside the 20Hz `input`, see
   * "Amplification" in docs/protocol.md). An accepted attack against zero targets still fires
   * `attack` and still consumes the cooldown (a "whiff"), mirroring LocalServer.request_skill. */
  private resolvePlayerAttack(p: ZonePlayer, skillIdInput: string | undefined): CombatEvent[] {
    const events: CombatEvent[] = [];
    const skills = balance.CLASSES.archetypes[p.archetype].skills;
    const firstSkill = skills[0];
    if (firstSkill === undefined) return events; // no skills defined for this archetype at all
    const effectiveId = skillIdInput ?? firstSkill.id;
    const skill = skills.find((s) => s.id === effectiveId);
    if (skill === undefined) return events;
    if (!skill_unlocked(skill.level, p.level)) return events;
    const lastUse = p.skillLastUse.get(effectiveId) ?? -Infinity;
    if (!skill_ready(this.elapsedS - lastUse, skill.cooldown)) return events;
    p.skillLastUse.set(effectiveId, this.elapsedS);

    const candidates: AttackCandidate[] = [];
    for (const m of this.monsters.values()) {
      if (!m.alive) continue;
      candidates.push({
        id: m.id,
        pos: m.sim.pos,
        halfWidth: MONSTER_WIDTH_PX / 2,
        halfHeight: MONSTER_HEIGHT_PX / 2,
      });
    }
    const targetIds = targetsInRange(
      p.sim.pos,
      p.sim.facing,
      skill.range_px,
      candidates,
      MAX_TARGETS_PER_ATTACK,
    );
    events.push({ t: "attack", attacker_id: p.id, skill_id: skillIdInput ?? null, target_ids: targetIds });

    for (const targetId of targetIds) {
      const monster = this.monsters.get(targetId);
      if (monster === undefined) continue;
      for (let i = 0; i < skill.hits; i++) {
        if (!monster.alive) break;
        const roll = this.rng();
        const dmg = damage(this.combatViewPlayer(p), this.combatViewMonster(monster), skill.power, roll);
        const newHp = apply_damage(monster.hp, dmg);
        monster.hp = newHp;
        monster.damagedBy.add(p.id);
        events.push({
          t: "damage",
          target_id: monster.id,
          attacker_id: p.id,
          amount: dmg,
          new_hp: newHp,
          crit: roll < CRIT_CHANCE,
        });
        this.registerLandedHit(p);
        if (is_dead(newHp)) {
          events.push(this.resolveMonsterDeath(monster, p.id));
        } else {
          monster.sim = { ...monster.sim, aiState: "hurt", hurtElapsed: 0 };
        }
      }
    }
    const extraCrashHits = skill_crash_hits(skill);
    for (let i = 0; i < extraCrashHits; i++) this.registerLandedHit(p);
    return events;
  }

  /** xp (via shared-rules party.ts group_xp_share, split among every player who landed a hit) + a
   * PRIVATE, independently-rolled item drop per eligible player (T-2.5) + money to the killer only
   * (T-2.4 kept the existing single-recipient economy behaviour — see ADR-017). */
  private resolveMonsterDeath(monster: ZoneMonster, killerId: string): DiedMessage {
    monster.alive = false;
    monster.sim = { ...monster.sim, aiState: "dead" };
    monster.deadElapsed = 0;
    const eligible = [...monster.damagedBy];
    const totalXp = monster.xpReward;

    for (const pid of eligible) {
      const p = this.players.get(pid);
      if (p === undefined) continue; // damaged it, then left the zone before it died
      this.grantXp(p, group_xp_share(totalXp, eligible.length));
    }

    let killerDropId: string | null = null;
    let killerItemId: string | null = null;
    for (const pid of eligible) {
      const p = this.players.get(pid);
      if (p === undefined) continue;
      const roll = this.rng();
      const itemId = roll_loot(monster.lootTable, roll);
      if (itemId === "") continue;
      const drop = this.spawnDrop(pid, monster.sim.pos, itemId);
      if (pid === killerId) {
        killerDropId = drop.id;
        killerItemId = itemId;
      }
    }

    const money = monster.moneyMax > 0 ? roll_money(monster.moneyMin, monster.moneyMax, this.rng()) : 0;
    const killerShare = eligible.length > 0 ? group_xp_share(totalXp, eligible.length) : 0;
    monster.damagedBy.clear();
    return {
      t: "died",
      id: monster.id,
      killer_id: killerId,
      xp: killerShare,
      drop_id: killerDropId,
      item_id: killerItemId,
      money,
    };
  }

  private grantXp(p: ZonePlayer, amount: number): void {
    p.xp += amount;
    const newLevel = level_for_xp(p.xp);
    if (newLevel > p.level) {
      p.level = newLevel;
      recomputePlayerStats(p);
      p.hp = p.maxHp; // phase-0 default: level-up heals to full, same as LocalServer's _grant_xp_to_killer
    }
  }

  private spawnDrop(ownerId: string, pos: Vec2, itemId: string): ZoneDrop {
    const id = `d_${this.nextDropId++}`;
    const drop: ZoneDrop = {
      id,
      ownerId,
      pos: { x: pos.x, y: pos.y },
      itemId,
      money: 0,
      expiresTick: this.tickNo + DROP_LIFETIME_TICKS,
    };
    this.drops.set(id, drop);
    return drop;
  }

  private stepMonsterAndMaybeAttack(m: ZoneMonster, dt: number): CombatEvent[] {
    const events: CombatEvent[] = [];
    const aliveTargets: MonsterTarget[] = [];
    for (const p of this.players.values()) {
      if (p.alive) aliveTargets.push({ id: p.id, pos: p.sim.pos });
    }
    const result = stepMonster(m.sim, aliveTargets, dt, this.map, m.aiParams, m.attackSpeed);
    m.sim = result.state;
    if (result.attackTargetId === null) return events;
    const target = this.players.get(result.attackTargetId);
    if (target === undefined || !target.alive) return events;

    events.push({ t: "attack", attacker_id: m.id, skill_id: null, target_ids: [target.id] });
    const roll = this.rng();
    const rawDmg = damage(
      this.combatViewMonster(m),
      this.combatViewPlayer(target),
      MONSTER_ATTACK_POWER,
      roll,
    );
    const dmg = damage_taken(rawDmg, target.crashActive);
    const newHp = apply_damage(target.hp, dmg);
    target.hp = newHp;
    events.push({
      t: "damage",
      target_id: target.id,
      attacker_id: m.id,
      amount: dmg,
      new_hp: newHp,
      crit: roll < CRIT_CHANCE,
    });
    if (is_dead(newHp)) {
      target.alive = false;
      target.deadElapsed = 0;
      // Respawn is entirely server-driven (docs/protocol.md: "There is no 'respawn' intent in v1") —
      // tickPlayerRespawn() above brings them back after PLAYER_RESPAWN_DELAY_S, full hp, at map.spawn.
      events.push({
        t: "died",
        id: target.id,
        killer_id: m.id,
        xp: 0,
        drop_id: null,
        item_id: null,
        money: 0,
      });
    }
    return events;
  }

  /** docs/protocol.md § Loot: owner-only, within PICKUP_RADIUS_PX, drop still unclaimed. "inventory
   * has room" always passes for now — the server doesn't own a player inventory yet (Phase 0's bag is
   * client-only); a later task adds one. */
  pickup(playerId: string, dropId: string): PickupResult {
    const drop = this.drops.get(dropId);
    if (drop === undefined || drop.ownerId !== playerId) return { itemId: null, money: 0, added: false };
    const player = this.players.get(playerId);
    if (player === undefined || !player.alive) return { itemId: null, money: 0, added: false };
    if (distance(player.sim.pos, drop.pos) > PICKUP_RADIUS_PX)
      return { itemId: null, money: 0, added: false };
    this.drops.delete(dropId);
    return { itemId: drop.itemId, money: drop.money, added: true };
  }

  /** The parts of `state` identical for every player this tick — computed once per call so
   * net/server.ts's per-player broadcast loop doesn't redo player/monster serialization per socket. */
  sharedSnapshot(): {
    tick: number;
    last_seq: Record<string, number>;
    players: PlayerState[];
    monsters: MonsterState[];
  } {
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
    const monsters: MonsterState[] = [];
    for (const m of this.monsters.values()) {
      monsters.push({
        id: m.id,
        kind: m.kind,
        pos: { x: m.sim.pos.x, y: m.sim.pos.y },
        vel: { x: m.sim.vel.x, y: m.sim.vel.y },
        hp: m.hp,
        max_hp: m.maxHp,
        level: m.level,
        facing: m.sim.facing,
        anim: monsterAnimFor(m.sim),
        alive: m.alive,
      });
    }
    return { tick: this.tickNo, last_seq, players, monsters };
  }

  /** T-2.5: drops are private — only `playerId`'s own drops, wire-shaped. */
  dropsFor(playerId: string): DropState[] {
    const result: DropState[] = [];
    for (const d of this.drops.values()) {
      if (d.ownerId !== playerId) continue;
      result.push({
        id: d.id,
        pos: { x: d.pos.x, y: d.pos.y },
        item_id: d.itemId,
        money: d.money,
        expires_tick: d.expiresTick,
      });
    }
    return result;
  }

  /** The wire-accurate snapshot for exactly one player (their own drops only) — used for the `joined` reply and by tests. net/server.ts's per-tick broadcast instead calls sharedSnapshot() once and dropsFor() per session, to avoid rebuilding the shared arrays per socket. */
  snapshotFor(playerId: string): Snapshot {
    return { ...this.sharedSnapshot(), drops: this.dropsFor(playerId) };
  }

  /** Every drop from every owner — NOT wire-accurate (a real client only ever gets its own via
   * snapshotFor/dropsFor); this exists for tests/tooling that want a god's-eye view. */
  snapshot(): Snapshot {
    const drops: DropState[] = [];
    for (const d of this.drops.values()) {
      drops.push({
        id: d.id,
        pos: { x: d.pos.x, y: d.pos.y },
        item_id: d.itemId,
        money: d.money,
        expires_tick: d.expiresTick,
      });
    }
    return { ...this.sharedSnapshot(), drops };
  }
}

export function createDefaultZone(opts: { seed?: number } = {}): Zone {
  const map = balance.MAPS[DEFAULT_ZONE_ID];
  if (map === undefined) {
    throw new Error(`map not found in balance.MAPS: ${DEFAULT_ZONE_ID}`);
  }
  return new Zone(DEFAULT_ZONE_ID, map, opts);
}
