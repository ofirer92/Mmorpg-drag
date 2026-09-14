import { describe, expect, it } from "vitest";
import { XP_CURVE } from "../src/_balance_data.js";
import { level_for_xp, xp_for_level, xp_total_for_level } from "../src/xp.js";
import fixture from "./fixtures/xp_curve.json" with { type: "json" };

describe("xp_for_level", () => {
  it("level 1 costs nothing", () => {
    expect(xp_for_level(1)).toBe(0);
    expect(xp_for_level(0)).toBe(0);
    expect(xp_for_level(-5)).toBe(0);
  });
  it("is monotonic increasing", () => {
    for (let l = 2; l <= XP_CURVE.max_level; l++)
      expect(xp_for_level(l)).toBeGreaterThan(xp_for_level(l - 1));
  });
  it("returns integers", () => {
    for (let l = 1; l <= XP_CURVE.max_level; l++) expect(Number.isInteger(xp_for_level(l))).toBe(true);
  });
  it("matches the shared fixture (same numbers the GUT test asserts)", () => {
    for (const [level, xp] of Object.entries(fixture.xp_for_level))
      expect(xp_for_level(Number(level))).toBe(xp);
  });
});

describe("xp_total_for_level / level_for_xp", () => {
  it("round-trips", () => {
    for (let l = 1; l <= XP_CURVE.max_level; l++) {
      expect(level_for_xp(xp_total_for_level(l))).toBe(l);
      if (l > 1) expect(level_for_xp(xp_total_for_level(l) - 1)).toBe(l - 1);
    }
  });
  it("caps at max_level", () => {
    expect(level_for_xp(Number.MAX_SAFE_INTEGER)).toBe(XP_CURVE.max_level);
  });
  it("matches fixture totals", () => {
    for (const [level, xp] of Object.entries(fixture.xp_total_for_level))
      expect(xp_total_for_level(Number(level))).toBe(xp);
  });
});
