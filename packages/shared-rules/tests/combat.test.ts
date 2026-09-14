import { describe, expect, it } from "vitest";
import { CRIT_CHANCE, CRIT_MULT, DEF_SCALE, MIN_DAMAGE } from "../src/_constants.js";
import { apply_damage, damage, effective_hp, is_dead } from "../src/combat.js";
import type { Combatant } from "../src/combat.js";
import fixture from "./fixtures/combat.json" with { type: "json" };

function fighter(over: Partial<Combatant> = {}): Combatant {
  return { attack: 10, defense: 4, level: 3, hp: 50, ...over };
}

describe("damage", () => {
  it("never returns less than MIN_DAMAGE, even when defense crushes raw damage", () => {
    const attacker: Combatant = fighter({ attack: 1, defense: 0, level: 1 });
    const defender: Combatant = fighter({ attack: 1, defense: 500, level: 1 });
    expect(damage(attacker, defender, 1.0, 0.9)).toBe(MIN_DAMAGE);
  });

  it("never returns less than MIN_DAMAGE with zero power (pure defense subtraction)", () => {
    const attacker: Combatant = fighter();
    const defender: Combatant = fighter();
    expect(damage(attacker, defender, 0, 0.9)).toBe(MIN_DAMAGE);
  });

  it("floors the raw damage", () => {
    const attacker: Combatant = fighter({ attack: 7, defense: 0, level: 3 });
    const defender: Combatant = fighter({ defense: 3, level: 3 });
    // raw = 7*1 - 3*0.5 = 5.5 -> floor 5
    expect(damage(attacker, defender, 1.0, 0.9)).toBe(5);
  });

  it("crits just below CRIT_CHANCE and multiplies by CRIT_MULT", () => {
    const attacker: Combatant = fighter({ attack: 20, defense: 4, level: 5 });
    const defender: Combatant = fighter({ defense: 5, level: 5 });
    const non_crit: number = damage(attacker, defender, 1.0, CRIT_CHANCE); // roll == chance -> no crit
    const crit: number = damage(attacker, defender, 1.0, CRIT_CHANCE - 0.001); // just under -> crit
    expect(crit).toBe(Math.floor(non_crit * CRIT_MULT));
    expect(crit).toBeGreaterThan(non_crit);
  });

  it("does not crit exactly at the CRIT_CHANCE boundary (roll < chance, not <=)", () => {
    const attacker: Combatant = fighter({ attack: 20, defense: 4, level: 5 });
    const defender: Combatant = fighter({ defense: 5, level: 5 });
    expect(damage(attacker, defender, 1.0, 0.05)).toBe(damage(attacker, defender, 1.0, 0.5));
    expect(damage(attacker, defender, 1.0, 0.049)).not.toBe(damage(attacker, defender, 1.0, 0.5));
  });

  it("boosts damage up to +25% when attacker is far higher level", () => {
    const attacker: Combatant = fighter({ attack: 12, defense: 4, level: 30 });
    const defender: Combatant = fighter({ attack: 5, defense: 1, level: 1 });
    const same_level: Combatant = fighter({ attack: 12, defense: 4, level: 1 });
    const boosted: number = damage(attacker, defender, 1.0, 0.9);
    const baseline: number = damage(same_level, defender, 1.0, 0.9);
    expect(boosted).toBe(Math.floor(baseline * 1.25));
  });

  it("reduces damage down to -25% when attacker is far lower level", () => {
    const attacker: Combatant = fighter({ attack: 12, defense: 4, level: 1 });
    const defender: Combatant = fighter({ attack: 5, defense: 1, level: 30 });
    const same_level: Combatant = fighter({ attack: 12, defense: 4, level: 30 });
    const reduced: number = damage(attacker, defender, 1.0, 0.9);
    const baseline: number = damage(same_level, defender, 1.0, 0.9);
    expect(reduced).toBe(Math.floor(baseline * 0.75));
  });

  it("level-diff cap is reached by +/-5 levels and doesn't grow further beyond it", () => {
    const defender: Combatant = fighter({ attack: 5, defense: 1, level: 10 });
    const at_cap: Combatant = fighter({ attack: 12, defense: 4, level: 15 });
    const past_cap: Combatant = fighter({ attack: 12, defense: 4, level: 25 });
    expect(damage(at_cap, defender, 1.0, 0.9)).toBe(damage(past_cap, defender, 1.0, 0.9));
  });

  it("is deterministic for the same inputs", () => {
    const attacker: Combatant = fighter();
    const defender: Combatant = fighter({ level: 4 });
    expect(damage(attacker, defender, 1.2, 0.33)).toBe(damage(attacker, defender, 1.2, 0.33));
  });

  it("matches the shared fixture (same numbers the GUT test asserts)", () => {
    for (const c of fixture.damage_cases) {
      expect(damage(c.attacker, c.defender, c.power, c.roll)).toBe(c.expected);
    }
  });
});

describe("effective_hp", () => {
  it("equals raw hp when defense is 0", () => {
    expect(effective_hp(fighter({ hp: 80, defense: 0 }))).toBe(80);
  });

  it("doubles at defense == DEF_SCALE", () => {
    expect(effective_hp(fighter({ hp: 80, defense: DEF_SCALE }))).toBe(160);
  });

  it("scales linearly with defense", () => {
    expect(effective_hp(fighter({ hp: 100, defense: DEF_SCALE / 2 }))).toBe(150);
  });
});

describe("apply_damage / is_dead", () => {
  it("subtracts damage from hp", () => {
    expect(apply_damage(50, 20)).toBe(30);
  });

  it("never goes below 0 even with overkill damage", () => {
    expect(apply_damage(10, 9999)).toBe(0);
  });

  it("handles zero damage", () => {
    expect(apply_damage(50, 0)).toBe(50);
  });

  it("is_dead is true only at hp <= 0", () => {
    expect(is_dead(1)).toBe(false);
    expect(is_dead(0)).toBe(true);
    expect(is_dead(-5)).toBe(true);
  });

  it("a lethal hit always results in is_dead", () => {
    expect(is_dead(apply_damage(10, 10))).toBe(true);
    expect(is_dead(apply_damage(10, 9))).toBe(false);
  });
});

// QA (independent review): cases the implementer did not cover.
describe("damage — QA edge cases", () => {
  const a = { attack: 10, defense: 0, level: 1, hp: 100 };
  const d = { attack: 0, defense: 0, level: 1, hp: 100 };
  it("power 0 or negative still deals MIN_DAMAGE, never heals", () => {
    expect(damage(a, d, 0, 0.5)).toBe(MIN_DAMAGE);
    expect(damage(a, d, -3, 0.5)).toBe(MIN_DAMAGE);
    expect(damage(a, d, -3, 0)).toBe(MIN_DAMAGE); // crit on a floored hit stays at the floor
  });
  it("a defender with absurd defense still takes MIN_DAMAGE", () => {
    expect(damage(a, { ...d, defense: 1e9 }, 1, 0.5)).toBe(MIN_DAMAGE);
  });
  it("a roll of exactly 1 (out of range) is treated as a non-crit, not an error", () => {
    expect(damage(a, d, 1, 1)).toBe(damage(a, d, 1, 0.5));
  });
});
