import { describe, expect, it } from "vitest";
import { ITEMS } from "../src/_balance_data.js";
import {
  affix_allows_rarity,
  affix_count,
  affix_mult,
  affix_pool_size,
  affix_stat,
  affix_weight,
  item_stat_with_affixes,
  roll_affix_id,
} from "../src/affixes.js";
import fixture from "./fixtures/affixes.json" with { type: "json" };

const RARITIES = ["common", "rare", "epic"] as const;

describe("affix_count", () => {
  it("stays within [min, max] inclusive for every rarity across the full roll range", () => {
    for (const rarity of RARITIES) {
      const slots = ITEMS.affix_slots[rarity];
      if (slots === undefined) throw new Error(`fixture data missing affix_slots.${rarity}`);
      for (let i = 0; i < 200; i++) {
        const roll = i / 200;
        const count = affix_count(rarity, roll);
        expect(count).toBeGreaterThanOrEqual(slots.min);
        expect(count).toBeLessThanOrEqual(slots.max);
      }
    }
  });

  it("hits both bounds (roll 0 → min, roll just under 1 → max)", () => {
    for (const rarity of RARITIES) {
      const slots = ITEMS.affix_slots[rarity];
      if (slots === undefined) throw new Error(`fixture data missing affix_slots.${rarity}`);
      expect(affix_count(rarity, 0)).toBe(slots.min);
      expect(affix_count(rarity, 0.999999)).toBe(slots.max);
    }
  });

  it("an epic item gets at least the epic minimum slot count", () => {
    const epicSlots = ITEMS.affix_slots.epic;
    if (epicSlots === undefined) throw new Error("fixture data missing affix_slots.epic");
    for (let i = 0; i < 50; i++) {
      expect(affix_count("epic", i / 50)).toBeGreaterThanOrEqual(epicSlots.min);
    }
  });

  it("unknown rarity returns 0", () => {
    expect(affix_count("does_not_exist", 0.5)).toBe(0);
    expect(affix_count("", 0.5)).toBe(0);
  });

  it("matches the shared fixture (same numbers the GUT test asserts)", () => {
    for (const c of fixture.affix_count_cases) {
      expect(affix_count(c.rarity, c.roll)).toBe(c.expected);
    }
  });
});

describe("affix_pool_size / affix_allows_rarity", () => {
  it("pool size equals the count of affixes whose rarities list includes the rarity", () => {
    for (const rarity of RARITIES) {
      const expected = Object.values(ITEMS.affixes).filter((a) => a.rarities.includes(rarity)).length;
      expect(affix_pool_size(rarity)).toBe(expected);
    }
  });

  it("pool respects each affix's allowed rarities (only those ids can roll for that rarity)", () => {
    for (const rarity of RARITIES) {
      for (const [id, def] of Object.entries(ITEMS.affixes)) {
        expect(affix_allows_rarity(id, rarity)).toBe(def.rarities.includes(rarity));
      }
    }
  });

  it("unknown rarity has an empty pool; unknown affix id never allows any rarity", () => {
    expect(affix_pool_size("does_not_exist")).toBe(0);
    for (const rarity of RARITIES) {
      expect(affix_allows_rarity("does_not_exist", rarity)).toBe(false);
    }
  });
});

describe("roll_affix_id", () => {
  it("only ever returns an id from the rarity's allowed pool, or ''", () => {
    for (const rarity of RARITIES) {
      for (let i = 0; i < 100; i++) {
        const id = roll_affix_id(rarity, i / 100);
        if (id !== "") expect(affix_allows_rarity(id, rarity)).toBe(true);
      }
    }
  });

  it("unknown rarity always returns ''", () => {
    for (let i = 0; i < 20; i++) expect(roll_affix_id("does_not_exist", i / 20)).toBe("");
  });

  it("matches the shared fixture (same strings the GUT test asserts)", () => {
    for (const c of fixture.roll_affix_id_cases) {
      expect(roll_affix_id(c.rarity, c.roll)).toBe(c.expected);
    }
  });

  it("distribution over 10,000 evenly spaced rolls matches affix weights within 3%", () => {
    for (const rarity of RARITIES) {
      const pool = Object.entries(ITEMS.affixes).filter(([, def]) => def.rarities.includes(rarity));
      const totalWeight = pool.reduce((sum, [, def]) => sum + def.weight, 0);
      const N = 10000;
      const counts = new Map<string, number>();
      for (let i = 0; i < N; i++) {
        const roll = i / N;
        const result = roll_affix_id(rarity, roll);
        counts.set(result, (counts.get(result) ?? 0) + 1);
      }
      for (const [id, def] of pool) {
        const expectedShare = def.weight / totalWeight;
        const actualShare = (counts.get(id) ?? 0) / N;
        expect(Math.abs(actualShare - expectedShare)).toBeLessThan(0.03);
      }
    }
  });
});

describe("affix_stat / affix_mult", () => {
  it("returns the configured flat stat bonus for a known affix", () => {
    for (const [id, def] of Object.entries(ITEMS.affixes)) {
      expect(affix_stat(id, "attack")).toBe(def.stats.attack);
      expect(affix_stat(id, "defense")).toBe(def.stats.defense);
      expect(affix_stat(id, "hp")).toBe(def.stats.hp);
    }
  });

  it("returns the configured percentage multiplier for a known affix", () => {
    for (const [id, def] of Object.entries(ITEMS.affixes)) {
      expect(affix_mult(id, "attack")).toBe(def.mult.attack);
      expect(affix_mult(id, "defense")).toBe(def.mult.defense);
      expect(affix_mult(id, "hp")).toBe(def.mult.hp);
    }
  });

  it("unknown affix id or unknown stat name → 0", () => {
    expect(affix_stat("does_not_exist", "attack")).toBe(0);
    expect(affix_mult("does_not_exist", "attack")).toBe(0);
    const anyId = Object.keys(ITEMS.affixes)[0];
    if (anyId === undefined) throw new Error("fixture data has no affixes");
    expect(affix_stat(anyId, "mana")).toBe(0);
    expect(affix_mult(anyId, "mana")).toBe(0);
  });

  it("affix_weight is 0 for an unknown id and the configured weight otherwise", () => {
    expect(affix_weight("does_not_exist")).toBe(0);
    for (const [id, def] of Object.entries(ITEMS.affixes)) {
      expect(affix_weight(id)).toBe(def.weight);
    }
  });
});

describe("item_stat_with_affixes", () => {
  it("with zero flat and zero mult, returns floor(base)", () => {
    expect(item_stat_with_affixes(7, 0, 0)).toBe(7);
    expect(item_stat_with_affixes(7.9, 0, 0)).toBe(7);
  });

  it("adds flat bonuses before applying the multiplier", () => {
    // (10 + 5) * (1 + 0.1) = 16.5 → floor 16
    expect(item_stat_with_affixes(10, 5, 0.1)).toBe(16);
  });

  it("floors the final result", () => {
    // (10 + 0) * (1 + 0.03) = 10.3 → floor 10
    expect(item_stat_with_affixes(10, 0, 0.03)).toBe(10);
  });

  it("handles a base of 0", () => {
    expect(item_stat_with_affixes(0, 5, 0.5)).toBe(7); // (0+5)*1.5 = 7.5 → floor 7
    expect(item_stat_with_affixes(0, 0, 0)).toBe(0);
  });
});
