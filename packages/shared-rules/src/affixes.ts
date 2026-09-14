// Item affixes (T-1.7). RulesScript subset (see .claude/skills/shared-rules-authoring).
// Numbers come from docs/balance/items.yaml (affixes / affix_order / affix_slots) — never
// hardcoded here. affix_order lists every affixes key exactly once, in roll order, because
// RulesScript can't iterate a Dictionary's keys directly (only `for (const x of ARR)` over
// arrays — see ADR-012), so the roll order lives explicitly in the YAML.
//
// Caller's job: "no duplicate affix on one item". Each roll_affix_id() call returns a single id;
// if a caller rolls affix_count() ids for an item and gets a repeat, it re-rolls that slot with a
// fresh roll value. This file stays pure/stateless (no loop-until-unique here) so it stays
// deterministic and testable per roll.
import { ITEMS } from "./_balance_data.js";

// Sell-table/roll weight of an affix id, or 0 if the id is unknown.
export function affix_weight(affix_id: string): number {
  if (ITEMS.affixes[affix_id] == null) {
    return 0;
  }
  return ITEMS.affixes[affix_id].weight;
}

// True when an affix is allowed to roll on the given item rarity.
export function affix_allows_rarity(affix_id: string, rarity: string): boolean {
  if (ITEMS.affixes[affix_id] == null) {
    return false;
  }
  for (const r of ITEMS.affixes[affix_id].rarities) {
    if (r == rarity) {
      return true;
    }
  }
  return false;
}

// Number of affixes in docs/balance/items.yaml `affixes` allowed for the given rarity, in YAML
// (affix_order) order. Unknown rarity → 0.
export function affix_pool_size(rarity: string): number {
  let count: number = 0;
  for (const id of ITEMS.affix_order) {
    if (affix_allows_rarity(id, rarity)) {
      count += 1;
    }
  }
  return count;
}

// How many affixes an item of this rarity gets: a uniform integer in the rarity's
// affix_slots [min, max] (inclusive) for a roll in [0,1). Unknown rarity → 0.
export function affix_count(rarity: string, roll: number): number {
  if (ITEMS.affix_slots[rarity] == null) {
    return 0;
  }
  const lo: number = ITEMS.affix_slots[rarity].min;
  const hi: number = Math.max(lo, ITEMS.affix_slots[rarity].max);
  const span: number = hi - lo + 1;
  return lo + Math.min(span - 1, Math.floor(Math.max(0, roll) * span));
}

// Weighted pick of one affix id within the rarity's allowed pool, for a roll in [0,1). Walks
// affix_order cumulatively (each allowed entry claims weight/total of the [0,1) range in order),
// same shape as roll_loot() in loot.ts. "" when the pool is empty (unknown rarity, or a rarity
// with no allowed affixes).
export function roll_affix_id(rarity: string, roll: number): string {
  let total: number = 0;
  for (const id of ITEMS.affix_order) {
    if (affix_allows_rarity(id, rarity)) {
      total += affix_weight(id);
    }
  }
  if (total <= 0) {
    return "";
  }
  let cumulative: number = 0;
  for (const id of ITEMS.affix_order) {
    if (affix_allows_rarity(id, rarity)) {
      cumulative += affix_weight(id);
      if (roll < cumulative / total) {
        return id;
      }
    }
  }
  return "";
}

// Flat stat bonus (attack/defense/hp) an affix grants, or 0 for an unknown affix id or stat name.
export function affix_stat(affix_id: string, stat: string): number {
  if (ITEMS.affixes[affix_id] == null) {
    return 0;
  }
  if (stat == "attack") {
    return ITEMS.affixes[affix_id].stats.attack;
  }
  if (stat == "defense") {
    return ITEMS.affixes[affix_id].stats.defense;
  }
  if (stat == "hp") {
    return ITEMS.affixes[affix_id].stats.hp;
  }
  return 0;
}

// Percentage stat multiplier (attack/defense/hp, 0..0.5) an affix grants, or 0 for an unknown
// affix id or stat name.
export function affix_mult(affix_id: string, stat: string): number {
  if (ITEMS.affixes[affix_id] == null) {
    return 0;
  }
  if (stat == "attack") {
    return ITEMS.affixes[affix_id].mult.attack;
  }
  if (stat == "defense") {
    return ITEMS.affixes[affix_id].mult.defense;
  }
  if (stat == "hp") {
    return ITEMS.affixes[affix_id].mult.hp;
  }
  return 0;
}

// Final stat value after affixes: base plus the sum of all rolled affixes' flat bonuses, then
// scaled by 1 + the sum of all rolled affixes' percentage multipliers, floored.
export function item_stat_with_affixes(base: number, flat_total: number, mult_total: number): number {
  return Math.floor((base + flat_total) * (1 + mult_total));
}
