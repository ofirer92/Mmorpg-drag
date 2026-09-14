import { describe, expect, it } from "vitest";
import { CLASSES, XP_CURVE } from "../src/_balance_data.js";
import {
  attack_at_level,
  defense_at_level,
  growth_levels,
  hp_at_level,
  level_progress,
  xp_into_level,
  xp_to_next_level,
} from "../src/progression.js";
import { level_for_xp, xp_for_level, xp_total_for_level } from "../src/xp.js";

const stim = CLASSES.archetypes.stim;

describe("stats at level", () => {
  it("level 1 (and below) equals base stats", () => {
    expect(hp_at_level(stim, stim.growth, 1)).toBe(stim.base_hp);
    expect(attack_at_level(stim, stim.growth, 0)).toBe(stim.base_attack);
    expect(defense_at_level(stim, stim.growth, -3)).toBe(stim.base_defense);
  });
  it("grows linearly and floors", () => {
    expect(hp_at_level(stim, stim.growth, 10)).toBe(Math.floor(stim.base_hp + stim.growth.hp * 9));
    expect(attack_at_level(stim, stim.growth, 10)).toBe(Math.floor(stim.base_attack + stim.growth.attack * 9));
    expect(defense_at_level(stim, stim.growth, 10)).toBe(Math.floor(stim.base_defense + stim.growth.defense * 9));
  });
  it("never grows past max_level", () => {
    expect(growth_levels(XP_CURVE.max_level)).toBe(XP_CURVE.max_level - 1);
    expect(growth_levels(XP_CURVE.max_level + 50)).toBe(XP_CURVE.max_level - 1);
    expect(hp_at_level(stim, stim.growth, 999)).toBe(hp_at_level(stim, stim.growth, XP_CURVE.max_level));
  });
  it("every archetype has growth numbers", () => {
    for (const a of Object.values(CLASSES.archetypes)) expect(a.growth.hp).toBeGreaterThan(0);
  });
});

describe("xp bar helpers", () => {
  it("xp_into_level is 0 exactly at a level boundary and grows within the level", () => {
    for (let l = 1; l < XP_CURVE.max_level; l++) {
      const start = xp_total_for_level(l);
      expect(xp_into_level(start, l)).toBe(0);
      expect(xp_into_level(start + 5, l)).toBe(5);
      expect(level_for_xp(start)).toBe(l);
    }
  });
  it("xp_to_next_level matches the curve; progress is 0..1 and 1 at max level", () => {
    expect(xp_to_next_level(1)).toBe(xp_for_level(2));
    expect(level_progress(0, 1)).toBe(0);
    expect(level_progress(xp_for_level(2) - 1, 1)).toBeLessThan(1);
    expect(level_progress(xp_total_for_level(XP_CURVE.max_level), XP_CURVE.max_level)).toBe(1);
    expect(level_progress(-100, 1)).toBe(0);
  });
});
