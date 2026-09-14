// Player movement constants + helpers. RulesScript subset. Numbers here are the ONLY source for
// client/scripts/rules/movement.gd — the client never types a speed or gravity literal.
export const MOVE_SPEED_PX: number = 220;
export const ACCEL_PX: number = 1800;
export const FRICTION_PX: number = 2200;
export const GRAVITY_PX: number = 1800;
export const FALL_GRAVITY_MULT: number = 1.6;
export const JUMP_VELOCITY_PX: number = -520;
export const JUMP_CUT_MULT: number = 0.45;
export const MAX_FALL_SPEED_PX: number = 900;
export const COYOTE_TIME_S: number = 0.1;
export const JUMP_BUFFER_S: number = 0.12;

// Horizontal velocity after one physics step given input direction (-1..1).
export function step_horizontal(vx: number, dir: number, delta: number): number {
  const target: number = dir * MOVE_SPEED_PX;
  if (dir == 0) {
    if (vx > 0) {
      return Math.max(0, vx - FRICTION_PX * delta);
    }
    return Math.min(0, vx + FRICTION_PX * delta);
  }
  if (vx < target) {
    return Math.min(target, vx + ACCEL_PX * delta);
  }
  return Math.max(target, vx - ACCEL_PX * delta);
}

// Vertical velocity after one physics step. Falling uses stronger gravity for a snappier arc.
export function step_vertical(vy: number, delta: number): number {
  let g: number = GRAVITY_PX;
  if (vy > 0) {
    g = GRAVITY_PX * FALL_GRAVITY_MULT;
  }
  return Math.min(MAX_FALL_SPEED_PX, vy + g * delta);
}

// A jump is allowed if grounded now, or left the ground less than COYOTE_TIME_S ago.
export function can_jump(on_floor: boolean, time_since_floor: number): boolean {
  if (on_floor) {
    return true;
  }
  return time_since_floor <= COYOTE_TIME_S;
}

// A jump press is still "buffered" if it happened less than JUMP_BUFFER_S ago.
export function jump_buffered(time_since_press: number): boolean {
  return time_since_press >= 0 && time_since_press <= JUMP_BUFFER_S;
}

// Releasing jump early cuts upward velocity.
export function jump_cut(vy: number): number {
  if (vy < 0) {
    return vy * JUMP_CUT_MULT;
  }
  return vy;
}
