import { describe, expect, it } from "vitest";
import { CLASSES } from "../src/_balance_data.js";
import { skill_cooldown_left, skill_crash_hits, skill_ready, skill_total_power, skill_unlocked } from "../src/skills.js";

const skills = CLASSES.archetypes.stim.skills;

describe("skills", () => {
  it("stim has 5 skills, unlocking at increasing levels within 1..10, first at level 1 with no cooldown", () => {
    expect(skills.length).toBe(5);
    expect(skills[0]?.level).toBe(1);
    expect(skills[0]?.cooldown).toBe(0);
    for (let i = 1; i < skills.length; i++) expect(skills[i]?.level).toBeGreaterThan(skills[i - 1]?.level ?? 0);
    expect(skills[skills.length - 1]?.level).toBeLessThanOrEqual(10);
  });
  it("unlock is inclusive at the skill level", () => {
    expect(skill_unlocked(3, 2)).toBe(false);
    expect(skill_unlocked(3, 3)).toBe(true);
    expect(skill_unlocked(3, 30)).toBe(true);
  });
  it("cooldown gate", () => {
    expect(skill_ready(0, 0)).toBe(true);
    expect(skill_ready(3.99, 4)).toBe(false);
    expect(skill_ready(4, 4)).toBe(true);
    expect(skill_cooldown_left(1, 4)).toBe(3);
    expect(skill_cooldown_left(9, 4)).toBe(0);
    expect(skill_cooldown_left(-5, 4)).toBe(4);
  });
  it("total power and crash hits", () => {
    for (const s of skills) {
      expect(skill_total_power(s)).toBeCloseTo(s.power * Math.max(1, s.hits));
      expect(skill_crash_hits(s)).toBe(s.crash_hits);
    }
    expect(skill_total_power({ level: 1, power: 2, hits: 0, cooldown: 0, crash_hits: -1, range_px: 1 })).toBe(2);
    expect(skill_crash_hits({ level: 1, power: 2, hits: 0, cooldown: 0, crash_hits: -1, range_px: 1 })).toBe(0);
  });
});
