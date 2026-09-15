// T-2.4: monster AI, mirroring client/scripts/monsters/monster.gd's Patrol/Chase/Attack/Hurt/Dead
// state machine — but authoritative and aware of every player in the zone (the client version only
// ever has ONE hardcoded player target; the server re-picks the nearest ALIVE player every tick).
// Every distance/speed number comes from `ai_params`/`attackSpeed` (docs/balance/monsters.yaml via
// balance.MONSTERS) passed in by world/zone.ts — this file supplies no literal of its own beyond
// world geometry (collision box size) and the client's own non-balance animation-pacing constant.
//
// Same split as player_sim.ts vs zone.ts: this module owns ONLY ai-state + movement. hp/alive/
// death/respawn belong to zone.ts, which assigns `aiState` directly ("hurt" on taking damage, "dead"
// on hp 0) — stepMonster just reacts to whatever aiState it's handed next tick. The only thing this
// file ever proposes doing to another entity is `attackTargetId`, an INTENT; zone.ts resolves the
// actual hit through shared-rules damage(), exactly like it does for player attacks. This file never
// calls a combat rule.
import { step_vertical } from "@hamirpaa/shared-rules";
import { isSolid, moveAndCollide, type MapDef, type Vec2 } from "./tilemap.js";

/** Matches client/scenes/monsters/monster.tscn's CollisionShape2D RectangleShape2D (22×28), centered
 * on `pos` — world geometry, not balance (see player_sim.ts's PLAYER_WIDTH_PX doc comment). */
export const MONSTER_WIDTH_PX = 22;
export const MONSTER_HEIGHT_PX = 28;

/** monster.gd's HURT_DURATION_S: "Visual-only timers (not balance numbers)" per its own doc comment —
 * how long a monster is stunned (can't move/attack) after being hit. Kept here so the server's hit
 * reaction timing matches what the client shows. */
const HURT_DURATION_S = 0.25;

/** monster.gd's ATTACK_POWER: "a structural default, not a tunable balance number" — monsters have no
 * skills, so their `attack` stat IS the base attack input to shared-rules damage(), unscaled. */
export const MONSTER_ATTACK_POWER = 1;

export type MonsterAiState = "patrol" | "chase" | "attack" | "hurt" | "dead";

export interface MonsterAiParams {
  patrol_speed: number;
  chase_speed: number;
  aggro_radius: number;
  attack_range: number;
  leash_radius: number;
  patrol_distance: number;
}

export interface MonsterSimState {
  pos: Vec2; // center of the collision box
  vel: Vec2;
  facing: -1 | 1;
  aiState: MonsterAiState;
  spawnX: number;
  /** Seconds until the next swing is allowed while in the ATTACK state (mirrors monster.gd's `_attack_cooldown_remaining`; starts at 0 so the first swing on entering range is immediate, same as the client). */
  attackCooldownRemaining: number;
  /** Seconds since entering HURT (mirrors monster.gd's `_hurt_elapsed`). */
  hurtElapsed: number;
}

export function createMonsterState(spawn: Vec2): MonsterSimState {
  return {
    pos: { x: spawn.x, y: spawn.y },
    vel: { x: 0, y: 0 },
    facing: 1,
    aiState: "patrol",
    spawnX: spawn.x,
    attackCooldownRemaining: 0,
    hurtElapsed: 0,
  };
}

/** A candidate chase/attack target — always an ALIVE player (zone.ts filters before calling). */
export interface MonsterTarget {
  id: string;
  pos: Vec2;
}

export interface StepMonsterResult {
  state: MonsterSimState;
  /** Set exactly on the tick a queued swing lands; null otherwise. zone.ts resolves it via shared-rules damage(). */
  attackTargetId: string | null;
}

function aabbFromCenter(pos: Vec2): { x: number; y: number; w: number; h: number } {
  return {
    x: pos.x - MONSTER_WIDTH_PX / 2,
    y: pos.y - MONSTER_HEIGHT_PX / 2,
    w: MONSTER_WIDTH_PX,
    h: MONSTER_HEIGHT_PX,
  };
}

function centerFromAabb(pos: Vec2): Vec2 {
  return { x: pos.x + MONSTER_WIDTH_PX / 2, y: pos.y + MONSTER_HEIGHT_PX / 2 };
}

function distance(a: Vec2, b: Vec2): number {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.sqrt(dx * dx + dy * dy);
}

/** Nearest target, or null if `targets` is empty — recomputed every tick (see the module doc comment: this is the server's generalization of the client's single hardcoded target). */
function nearestTarget(pos: Vec2, targets: MonsterTarget[]): MonsterTarget | null {
  let best: MonsterTarget | null = null;
  let bestDist = Infinity;
  for (const t of targets) {
    const d = distance(pos, t.pos);
    if (d < bestDist) {
      bestDist = d;
      best = t;
    }
  }
  return best;
}

/** Is there solid ground at the leading foot of `aabb` moving in `dir`? A tile-probe stand-in for
 * monster.gd's GroundAhead RayCast2D (ledge detection during patrol). */
function groundAheadIsSolid(
  map: MapDef,
  aabb: { x: number; y: number; w: number; h: number },
  dir: -1 | 1,
): boolean {
  const probeX = dir > 0 ? aabb.x + aabb.w + 1 : aabb.x - 1;
  const probeY = aabb.y + aabb.h + 1;
  const ts = map.tile_size;
  return isSolid(map, Math.floor(probeX / ts), Math.floor(probeY / ts));
}

function fallOnly(state: MonsterSimState, dt: number, map: MapDef): { pos: Vec2; vel: Vec2 } {
  const vy = step_vertical(state.vel.y, dt);
  const aabb = aabbFromCenter(state.pos);
  const moved = moveAndCollide(map, aabb, { x: 0, y: vy }, dt);
  return { pos: centerFromAabb(moved.pos), vel: moved.vel };
}

function stepPatrol(
  state: MonsterSimState,
  target: MonsterTarget | null,
  distToTarget: number,
  dt: number,
  map: MapDef,
  aiParams: MonsterAiParams,
): StepMonsterResult {
  let facing = state.facing;
  const aabbBefore = aabbFromCenter(state.pos);
  const offset = state.pos.x - state.spawnX;
  const pastLimit =
    (facing > 0 && offset >= aiParams.patrol_distance) || (facing < 0 && -offset >= aiParams.patrol_distance);
  if (pastLimit || !groundAheadIsSolid(map, aabbBefore, facing)) {
    facing = facing > 0 ? -1 : 1;
  }
  const vx = aiParams.patrol_speed * facing;
  const vy = step_vertical(state.vel.y, dt);
  const moved = moveAndCollide(map, aabbBefore, { x: vx, y: vy }, dt);
  if (moved.vel.x === 0 && vx !== 0) {
    // Hit a wall this tick: also flip for next tick (mirrors monster.gd's is_on_wall() branch).
    facing = facing > 0 ? -1 : 1;
  }
  const nextAiState: MonsterAiState =
    target !== null && distToTarget <= aiParams.aggro_radius ? "chase" : "patrol";
  return {
    state: {
      ...state,
      pos: centerFromAabb(moved.pos),
      vel: moved.vel,
      facing,
      aiState: nextAiState,
      hurtElapsed: 0,
    },
    attackTargetId: null,
  };
}

function stepChase(
  state: MonsterSimState,
  target: MonsterTarget | null,
  distToTarget: number,
  dt: number,
  map: MapDef,
  aiParams: MonsterAiParams,
): StepMonsterResult {
  if (target === null || distToTarget > aiParams.leash_radius) {
    const moved = fallOnly(state, dt, map);
    return { state: { ...state, ...moved, aiState: "patrol", hurtElapsed: 0 }, attackTargetId: null };
  }
  if (distToTarget <= aiParams.attack_range) {
    const moved = fallOnly(state, dt, map);
    return { state: { ...state, ...moved, aiState: "attack", hurtElapsed: 0 }, attackTargetId: null };
  }
  const diff = target.pos.x - state.pos.x;
  const dir: -1 | 1 | 0 = diff > 0 ? 1 : diff < 0 ? -1 : 0;
  const facing = dir === 0 ? state.facing : dir;
  const vx = aiParams.chase_speed * dir;
  const vy = step_vertical(state.vel.y, dt);
  const aabb = aabbFromCenter(state.pos);
  const moved = moveAndCollide(map, aabb, { x: vx, y: vy }, dt);
  return {
    state: {
      ...state,
      pos: centerFromAabb(moved.pos),
      vel: moved.vel,
      facing,
      aiState: "chase",
      hurtElapsed: 0,
    },
    attackTargetId: null,
  };
}

function stepAttack(
  state: MonsterSimState,
  target: MonsterTarget | null,
  distToTarget: number,
  dt: number,
  map: MapDef,
  aiParams: MonsterAiParams,
  attackSpeed: number,
): StepMonsterResult {
  const moved = fallOnly(state, dt, map);
  if (target === null) {
    return { state: { ...state, ...moved, aiState: "patrol", hurtElapsed: 0 }, attackTargetId: null };
  }
  if (distToTarget > aiParams.attack_range) {
    return { state: { ...state, ...moved, aiState: "chase", hurtElapsed: 0 }, attackTargetId: null };
  }
  const cooldownRemaining = state.attackCooldownRemaining - dt;
  if (cooldownRemaining <= 0) {
    const speed = Math.max(attackSpeed, 0.01);
    return {
      state: { ...state, ...moved, aiState: "attack", attackCooldownRemaining: 1 / speed, hurtElapsed: 0 },
      attackTargetId: target.id,
    };
  }
  return {
    state: {
      ...state,
      ...moved,
      aiState: "attack",
      attackCooldownRemaining: cooldownRemaining,
      hurtElapsed: 0,
    },
    attackTargetId: null,
  };
}

function stepHurt(state: MonsterSimState, dt: number, map: MapDef): StepMonsterResult {
  const moved = fallOnly(state, dt, map);
  const hurtElapsed = state.hurtElapsed + dt;
  const nextAiState: MonsterAiState = hurtElapsed >= HURT_DURATION_S ? "patrol" : "hurt";
  return {
    state: {
      ...state,
      ...moved,
      aiState: nextAiState,
      hurtElapsed: nextAiState === "hurt" ? hurtElapsed : 0,
    },
    attackTargetId: null,
  };
}

/**
 * One AI + movement tick for one monster. `targets` = every currently ALIVE player in the zone
 * (zone.ts filters). Deterministic: same (state, targets, dt, map, aiParams, attackSpeed) always
 * produces the same result — no RNG, no side effects.
 */
export function stepMonster(
  state: MonsterSimState,
  targets: MonsterTarget[],
  dt: number,
  map: MapDef,
  aiParams: MonsterAiParams,
  attackSpeed: number,
): StepMonsterResult {
  if (state.aiState === "dead") {
    return { state: { ...state, vel: { x: 0, y: 0 } }, attackTargetId: null };
  }
  if (state.aiState === "hurt") {
    return stepHurt(state, dt, map);
  }
  const target = nearestTarget(state.pos, targets);
  const distToTarget = target === null ? Infinity : distance(state.pos, target.pos);
  if (state.aiState === "chase") {
    return stepChase(state, target, distToTarget, dt, map, aiParams);
  }
  if (state.aiState === "attack") {
    return stepAttack(state, target, distToTarget, dt, map, aiParams, attackSpeed);
  }
  return stepPatrol(state, target, distToTarget, dt, map, aiParams);
}
