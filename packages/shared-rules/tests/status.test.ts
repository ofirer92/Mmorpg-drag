import { describe, expect, it } from "vitest";
import { CLASSES } from "../src/_balance_data.js";
import {
  crash_damage_taken_mult,
  crash_duration_s,
  crash_triggers,
  damage_taken,
  next_consecutive_hits,
} from "../src/status.js";

const crash = CLASSES.archetypes.stim.mechanics.crash;

describe("stim crash", () => {
  it("counter increments on a landed hit and resets on a miss", () => {
    expect(next_consecutive_hits(0, true)).toBe(1);
    expect(next_consecutive_hits(3, true)).toBe(4);
    expect(next_consecutive_hits(3, false)).toBe(0);
  });
  it("triggers exactly at hits_in_a_row, not before", () => {
    expect(crash_triggers(crash.hits_in_a_row - 1)).toBe(false);
    expect(crash_triggers(crash.hits_in_a_row)).toBe(true);
    expect(crash_triggers(crash.hits_in_a_row + 10)).toBe(true);
    expect(crash_triggers(0)).toBe(false);
  });
  it("duration and multiplier come from classes.yaml", () => {
    expect(crash_duration_s()).toBe(crash.duration_s);
    expect(crash_damage_taken_mult(true)).toBe(crash.damage_taken_mult);
    expect(crash_damage_taken_mult(false)).toBe(1);
  });
  it("damage taken doubles while crashed, floors, never negative", () => {
    expect(damage_taken(7, true)).toBe(Math.floor(7 * crash.damage_taken_mult));
    expect(damage_taken(7, false)).toBe(7);
    expect(damage_taken(-5, true)).toBe(0);
    expect(damage_taken(0, true)).toBe(0);
  });
});
