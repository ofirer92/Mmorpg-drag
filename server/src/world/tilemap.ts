// T-2.2: pure AABB-vs-tile collision over a shared MapDef (docs/maps/*.yaml → balance.MAPS, see
// scripts/gen_rules.py gen_maps_ts). No sockets, no ticks, no DB — just geometry, so it is trivially
// unit-testable and reusable from world/player_sim.ts. ADR-016: this is a simplified server physics
// sim (axis-separated AABB sweep), not the client's CharacterBody2D/move_and_slide; the client owns
// reconciliation against any divergence.
import type { balance } from "@hamirpaa/shared-rules";

/** The shape gen_maps_ts() gives docs/maps/*.yaml entries in balance.MAPS. */
export type MapDef = (typeof balance)["MAPS"][string];

export interface Vec2 {
  x: number;
  y: number;
}

export interface AABB {
  x: number; // top-left corner, px
  y: number;
  w: number;
  h: number;
}

export interface MoveResult {
  pos: Vec2;
  vel: Vec2;
  onFloor: boolean;
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, v));
}

/**
 * Is grid cell (cellX, cellY) solid? Cells outside the grid are NOT solid here — this stays a pure
 * lookup; moveAndCollide is the one place that clamps a moving body to the map's pixel bounds.
 */
export function isSolid(map: MapDef, cellX: number, cellY: number): boolean {
  if (cellY < 0 || cellY >= map.rows || cellX < 0 || cellX >= map.cols) return false;
  const row = map.layout[cellY];
  if (row === undefined) return false;
  const ch = row[cellX];
  if (ch === undefined) return false;
  return map.solid_chars.includes(ch);
}

/** Does any solid tile overlap this pixel rect? */
function rectOverlapsSolid(map: MapDef, rect: AABB): boolean {
  const ts = map.tile_size;
  const EPS = 1e-6; // a rect flush against a tile boundary must not claim the next tile too
  const colLo = Math.floor(rect.x / ts);
  const colHi = Math.floor((rect.x + rect.w - EPS) / ts);
  const rowLo = Math.floor(rect.y / ts);
  const rowHi = Math.floor((rect.y + rect.h - EPS) / ts);
  for (let row = rowLo; row <= rowHi; row++) {
    for (let col = colLo; col <= colHi; col++) {
      if (isSolid(map, col, row)) return true;
    }
  }
  return false;
}

/**
 * Move `base` from `from` to `to` along one axis, one pixel at a time, stopping the instant the
 * next pixel would overlap a solid tile. A 1px step is cheap at 20 Hz tick deltas (≤ ~45 iterations
 * even at MAX_FALL_SPEED_PX) and — unlike a single big jump — can never tunnel through a thin tile.
 */
function sweepAxis(
  map: MapDef,
  axis: "x" | "y",
  base: AABB,
  from: number,
  to: number,
): { pos: number; hit: boolean } {
  if (to === from) return { pos: from, hit: false };
  const dir = to > from ? 1 : -1;
  let pos = from;
  let remaining = Math.abs(to - from);
  let hit = false;
  while (remaining > 0) {
    const step = Math.min(1, remaining);
    const next = pos + dir * step;
    const rect: AABB = axis === "x" ? { ...base, x: next } : { ...base, y: next };
    if (rectOverlapsSolid(map, rect)) {
      hit = true;
      break;
    }
    pos = next;
    remaining -= step;
  }
  return { pos, hit };
}

/**
 * Axis-separated AABB-vs-tile sweep: move `aabb` by `velocity * dt`, X then Y, zeroing the velocity
 * on the axis that hit a solid tile, and clamping the final position to the map's pixel bounds.
 * `onFloor` is true when the Y sweep stopped on a downward move, OR (a stationary/near-zero-dy body)
 * a 0.5px probe below the feet finds a solid tile — so a resting player reports onFloor every tick,
 * not just the tick it landed on.
 */
export function moveAndCollide(map: MapDef, aabb: AABB, velocity: Vec2, dt: number): MoveResult {
  const ts = map.tile_size;
  const boundsW = map.cols * ts;
  const boundsH = map.rows * ts;

  let vx = velocity.x;
  let vy = velocity.y;

  const dx = vx * dt;
  const sweepX = sweepAxis(map, "x", aabb, aabb.x, aabb.x + dx);
  const x = clamp(sweepX.pos, 0, Math.max(0, boundsW - aabb.w));
  if (sweepX.hit) vx = 0;

  const afterX: AABB = { ...aabb, x };
  const dy = vy * dt;
  const sweepY = sweepAxis(map, "y", afterX, afterX.y, afterX.y + dy);
  const y = clamp(sweepY.pos, 0, Math.max(0, boundsH - aabb.h));
  let onFloor = false;
  if (sweepY.hit) {
    if (dy > 0) onFloor = true;
    vy = 0;
  }
  if (!onFloor && rectOverlapsSolid(map, { x, y: y + 0.5, w: aabb.w, h: aabb.h })) {
    onFloor = true;
  }

  return { pos: { x, y }, vel: { x: vx, y: vy }, onFloor };
}
