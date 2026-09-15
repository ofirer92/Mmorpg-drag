// T-2.4: server-side melee hit detection. `input.attack`/`input.skill_id` are only an INTENT — the
// client never sends (and the server never trusts) a target list; this module finds who is actually
// in range, in front of the attacker, from the server's own authoritative positions every tick.
// Mirrors client/scripts/player/player.gd's HitBox (an Area2D grown to the skill's range_px, offset
// in front of the attacker — see _grow_hit_box) as a plain AABB overlap test, since the server has no
// physics engine to ask.
import type { Vec2 } from "./tilemap.js";

/**
 * Matches client/scenes/player/player.tscn's HitBox RectangleShape2D height (24×28 default, only the
 * height survives the resize to range_px — see player.gd's _grow_hit_box). World geometry, not a
 * balance number (same category as player_sim.ts's PLAYER_WIDTH_PX).
 */
export const ATTACK_HITBOX_HEIGHT_PX = 28;

export interface Aabb {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface AttackCandidate {
  id: string;
  pos: Vec2;
  halfWidth: number;
  halfHeight: number;
}

/**
 * The attacker's melee hitbox: `rangePx` wide, ATTACK_HITBOX_HEIGHT_PX tall, centered on the
 * attacker and extending `rangePx` in the direction they're facing (mirrors player.gd's
 * `hit_box.position.x = (range_px * 0.5) * facing`, a box that starts at the attacker's center).
 */
function hitboxFor(attackerPos: Vec2, facing: -1 | 1, rangePx: number): Aabb {
  const centerX = attackerPos.x + facing * (rangePx / 2);
  return {
    x: centerX - rangePx / 2,
    y: attackerPos.y - ATTACK_HITBOX_HEIGHT_PX / 2,
    w: rangePx,
    h: ATTACK_HITBOX_HEIGHT_PX,
  };
}

function overlaps(box: Aabb, pos: Vec2, halfWidth: number, halfHeight: number): boolean {
  const left = pos.x - halfWidth;
  const right = pos.x + halfWidth;
  const top = pos.y - halfHeight;
  const bottom = pos.y + halfHeight;
  return left < box.x + box.w && right > box.x && top < box.y + box.h && bottom > box.y;
}

/**
 * Every candidate whose AABB overlaps the attacker's melee hitbox, nearest-first, capped to
 * `maxTargets`. Pure and side-effect free — callers (world/zone.ts) own applying any damage.
 */
export function targetsInRange(
  attackerPos: Vec2,
  facing: -1 | 1,
  rangePx: number,
  candidates: AttackCandidate[],
  maxTargets: number,
): string[] {
  const box = hitboxFor(attackerPos, facing, rangePx);
  const hits = candidates.filter((c) => overlaps(box, c.pos, c.halfWidth, c.halfHeight));
  hits.sort((a, b) => Math.abs(a.pos.x - attackerPos.x) - Math.abs(b.pos.x - attackerPos.x));
  return hits.slice(0, Math.max(0, maxTargets)).map((c) => c.id);
}
