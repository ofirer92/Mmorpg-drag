import { describe, expect, it } from "vitest";
import {
  ACCEL_PX,
  COYOTE_TIME_S,
  FRICTION_PX,
  GRAVITY_PX,
  JUMP_BUFFER_S,
  JUMP_VELOCITY_PX,
  MAX_FALL_SPEED_PX,
  MOVE_SPEED_PX,
  can_jump,
  jump_buffered,
  jump_cut,
  step_horizontal,
  step_vertical,
} from "../src/movement.js";

describe("step_horizontal", () => {
  it("accelerates towards MOVE_SPEED_PX and reaches it after enough time", () => {
    let vx = 0;
    for (let i = 0; i < 100; i++) vx = step_horizontal(vx, 1, 1 / 20);
    expect(vx).toBe(MOVE_SPEED_PX);
  });

  it("accelerates in the negative direction symmetrically", () => {
    let vx = 0;
    for (let i = 0; i < 100; i++) vx = step_horizontal(vx, -1, 1 / 20);
    expect(vx).toBe(-MOVE_SPEED_PX);
  });

  it("never overshoots the target speed in a single large step", () => {
    expect(step_horizontal(0, 1, 10)).toBe(MOVE_SPEED_PX);
  });

  it("friction brings velocity to exactly 0, not past it, when no input", () => {
    let vx = 50;
    for (let i = 0; i < 100; i++) vx = step_horizontal(vx, 0, 1 / 20);
    expect(vx).toBe(0);
  });

  it("friction stops a leftward drift at 0 too", () => {
    let vx = -50;
    for (let i = 0; i < 100; i++) vx = step_horizontal(vx, 0, 1 / 20);
    expect(vx).toBe(0);
  });

  it("friction does not overshoot past 0 in a single large step", () => {
    expect(step_horizontal(50, 0, 10)).toBe(0);
    expect(step_horizontal(-50, 0, 10)).toBe(0);
  });
});

describe("step_vertical", () => {
  it("gravity increases downward (positive) velocity over time", () => {
    const v1 = step_vertical(0, 1 / 20);
    expect(v1).toBeGreaterThan(0);
  });

  it("falling uses stronger gravity than rising", () => {
    const rising = step_vertical(-100, 1 / 20) - -100;
    const falling = step_vertical(100, 1 / 20) - 100;
    expect(falling).toBeGreaterThan(rising);
  });

  it("clamps to MAX_FALL_SPEED_PX and never exceeds it", () => {
    let vy = 0;
    for (let i = 0; i < 1000; i++) vy = step_vertical(vy, 1 / 20);
    expect(vy).toBe(MAX_FALL_SPEED_PX);
  });

  it("does not clamp velocities below the max", () => {
    expect(step_vertical(0, 0)).toBe(0);
  });
});

describe("can_jump (coyote time)", () => {
  it("always allowed while grounded, regardless of time_since_floor", () => {
    expect(can_jump(true, 0)).toBe(true);
    expect(can_jump(true, 999)).toBe(true);
  });

  it("allowed just within the coyote window (inclusive boundary)", () => {
    expect(can_jump(false, COYOTE_TIME_S)).toBe(true);
  });

  it("not allowed just past the coyote window", () => {
    expect(can_jump(false, COYOTE_TIME_S + 0.001)).toBe(false);
  });

  it("not allowed long after leaving the floor", () => {
    expect(can_jump(false, 5)).toBe(false);
  });
});

describe("jump_buffered", () => {
  it("true at time 0 and at the upper boundary (inclusive)", () => {
    expect(jump_buffered(0)).toBe(true);
    expect(jump_buffered(JUMP_BUFFER_S)).toBe(true);
  });

  it("false just past the buffer window", () => {
    expect(jump_buffered(JUMP_BUFFER_S + 0.001)).toBe(false);
  });

  it("false for a negative time (press hasn't happened yet)", () => {
    expect(jump_buffered(-0.001)).toBe(false);
  });
});

describe("jump_cut", () => {
  it("cuts upward (negative) velocity towards 0", () => {
    const cut = jump_cut(JUMP_VELOCITY_PX);
    expect(cut).toBeGreaterThan(JUMP_VELOCITY_PX); // less negative
    expect(cut).toBeLessThan(0);
  });

  it("does not affect downward (positive) velocity", () => {
    expect(jump_cut(200)).toBe(200);
  });

  it("does not affect zero velocity", () => {
    expect(jump_cut(0)).toBe(0);
  });
});

describe("movement constants sanity (used elsewhere in the file, exercised indirectly above)", () => {
  it("acceleration and friction are positive", () => {
    expect(ACCEL_PX).toBeGreaterThan(0);
    expect(FRICTION_PX).toBeGreaterThan(0);
  });

  it("gravity is positive (downward)", () => {
    expect(GRAVITY_PX).toBeGreaterThan(0);
  });
});
