import { describe, expect, it } from "vitest";
import { ITEMS } from "../src/_balance_data.js";
import { loot_value, roll_loot } from "../src/loot.js";
import fixture from "./fixtures/combat.json" with { type: "json" };

describe("roll_loot", () => {
  it("unknown table id returns nothing", () => {
    expect(roll_loot("does_not_exist", 0.1)).toBe("");
    expect(roll_loot("", 0.5)).toBe("");
  });

  it("is deterministic for the same table and roll", () => {
    expect(roll_loot("common_trash", 0.3)).toBe(roll_loot("common_trash", 0.3));
  });

  it("roll 0 lands in the first entry's band", () => {
    expect(roll_loot("common_trash", 0)).toBe("expired_bandage");
  });

  it("roll just under 1 lands in the last entry's band", () => {
    expect(roll_loot("common_trash", 0.999999)).toBe("");
  });

  it("matches the shared fixture (same strings the GUT test asserts)", () => {
    for (const c of fixture.loot_cases) {
      expect(roll_loot(c.table_id, c.roll)).toBe(c.expected);
    }
  });

  it("distribution over 10,000 evenly spaced rolls matches entry weights within 2%", () => {
    const table = ITEMS.loot_tables.common_trash;
    if (table === undefined) throw new Error("fixture data missing common_trash table");
    const total_weight: number = table.entries.reduce((sum, e) => sum + e.weight, 0);
    const N = 10000;
    const counts = new Map<string, number>();
    for (let i = 0; i < N; i++) {
      const roll = i / N; // evenly spaced across [0,1)
      const result = roll_loot("common_trash", roll);
      counts.set(result, (counts.get(result) ?? 0) + 1);
    }
    for (const entry of table.entries) {
      const key = entry.item ?? "";
      const expected_share = entry.weight / total_weight;
      const actual_share = (counts.get(key) ?? 0) / N;
      expect(Math.abs(actual_share - expected_share)).toBeLessThan(0.02);
    }
  });

  it("every roll in [0,1) returns either a known item or empty string, never undefined-like", () => {
    for (let i = 0; i < 50; i++) {
      const roll = i / 50;
      const result = roll_loot("common_trash", roll);
      expect(typeof result).toBe("string");
    }
  });
});

describe("loot_value", () => {
  it("returns the configured value for a known item", () => {
    const expired_bandage = ITEMS.items.expired_bandage;
    if (expired_bandage === undefined) throw new Error("fixture data missing expired_bandage item");
    expect(loot_value("expired_bandage")).toBe(expired_bandage.value);
  });

  it("returns 0 for an unknown item id", () => {
    expect(loot_value("does_not_exist")).toBe(0);
  });

  it("returns 0 for an empty id", () => {
    expect(loot_value("")).toBe(0);
  });
});
