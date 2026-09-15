// T-2.2: authoritative per-tick player movement. Uses ONLY shared-rules movement functions
// (step_horizontal/step_vertical/can_jump/jump_buffered/jump_cut + constants) for every number —
// this file supplies no speed/gravity/jump literal of its own — plus world/tilemap.ts for collision.
// Mirrors client/scripts/player/player.gd's _step_physics() tick-for-tick (coyote time, jump buffer,
// jump cut), but against a simplified server AABB sim instead of CharacterBody2D.move_and_slide()
// (ADR-016 — divergence tolerance is the client's job).
import {
  can_jump,
  jump_buffered,
  jump_cut,
  step_horizontal,
  step_vertical,
  JUMP_VELOCITY_PX,
  COYOTE_TIME_S,
} from "@hamirpaa/shared-rules";
import { moveAndCollide, type MapDef, type Vec2 } from "./tilemap.js";

/**
 * The player's collision box, px — matches client/scenes/player/player.tscn's CollisionShape2D
 * RectangleShape2D (20×30), centered on `pos`. Not a balance number (docs/balance/*.yaml governs
 * gameplay tuning); it is world geometry, same as MAPS' tile_size, so it stays a local constant here.
 */
export const PLAYER_WIDTH_PX = 20;
export const PLAYER_HEIGHT_PX = 30;

export interface PlayerInput {
  seq: number;
  dir: -1 | 0 | 1;
  jump: boolean; // held state, sampled every tick (docs/protocol.md `input.jump`)
  attack: boolean;
  skill_id?: string;
}

export interface PlayerSimState {
  pos: Vec2; // center of the collision box
  vel: Vec2;
  onFloor: boolean;
  /** Seconds since the box was last resting on a floor tile (coyote time window). */
  timeSinceFloor: number;
  /** Seconds since jump was last pressed; -1 = no buffered press (jump buffer window). */
  timeSinceJumpPress: number;
  /** `input.jump` from the previous tick — used to detect the press/release edges. */
  jumpHeldPrev: boolean;
  facing: -1 | 1;
}

export function createPlayerState(spawn: Vec2): PlayerSimState {
  return {
    pos: { x: spawn.x, y: spawn.y },
    vel: { x: 0, y: 0 },
    onFloor: false,
    timeSinceFloor: 999,
    timeSinceJumpPress: -1,
    jumpHeldPrev: false,
    facing: 1,
  };
}

function aabbFromCenter(pos: Vec2): { x: number; y: number; w: number; h: number } {
  return {
    x: pos.x - PLAYER_WIDTH_PX / 2,
    y: pos.y - PLAYER_HEIGHT_PX / 2,
    w: PLAYER_WIDTH_PX,
    h: PLAYER_HEIGHT_PX,
  };
}

function centerFromAabb(pos: Vec2): Vec2 {
  return { x: pos.x + PLAYER_WIDTH_PX / 2, y: pos.y + PLAYER_HEIGHT_PX / 2 };
}

/** One authoritative physics tick for one player. Deterministic: same (state, input, dt, map) always produces the same result. */
export function stepPlayer(
  state: PlayerSimState,
  input: PlayerInput,
  dt: number,
  map: MapDef,
): PlayerSimState {
  let facing = state.facing;
  if (input.dir !== 0) facing = input.dir > 0 ? 1 : -1;

  const vx = step_horizontal(state.vel.x, input.dir, dt);

  // Ground state carried over from the end of the PREVIOUS tick (mirrors the client reading
  // is_on_floor() at the top of _physics_process, before this tick's move happens).
  const onFloorBefore = state.onFloor;
  const timeSinceFloor = onFloorBefore ? 0 : state.timeSinceFloor + dt;

  let timeSinceJumpPress = state.timeSinceJumpPress;
  const jumpPressedEdge = input.jump && !state.jumpHeldPrev;
  if (jumpPressedEdge) {
    timeSinceJumpPress = 0;
  } else if (timeSinceJumpPress >= 0) {
    timeSinceJumpPress += dt;
    if (!jump_buffered(timeSinceJumpPress)) timeSinceJumpPress = -1;
  }

  const wantsJump = timeSinceJumpPress >= 0 && jump_buffered(timeSinceJumpPress);
  let vy: number;
  let timeSinceFloorAfterJump = timeSinceFloor;
  if (wantsJump && can_jump(onFloorBefore, timeSinceFloor)) {
    vy = JUMP_VELOCITY_PX;
    timeSinceJumpPress = -1;
    timeSinceFloorAfterJump = COYOTE_TIME_S + 1; // consumed the coyote window, like the client does
  } else {
    vy = step_vertical(state.vel.y, dt);
  }

  // Jump cut: released jump while still moving upward.
  if (state.jumpHeldPrev && !input.jump && vy < 0) {
    vy = jump_cut(vy);
  }

  const aabb = aabbFromCenter(state.pos);
  const result = moveAndCollide(map, aabb, { x: vx, y: vy }, dt);

  return {
    pos: centerFromAabb(result.pos),
    vel: result.vel,
    onFloor: result.onFloor,
    timeSinceFloor: timeSinceFloorAfterJump,
    timeSinceJumpPress,
    jumpHeldPrev: input.jump,
    facing,
  };
}
