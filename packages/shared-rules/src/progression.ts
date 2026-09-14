// Character progression: stats at a level and XP-bar helpers. RulesScript subset.
// Growth numbers come from docs/balance/classes.yaml (archetypes.<id>.growth) via _balance_data.
import { XP_CURVE } from "./_balance_data.js";
import { xp_for_level, xp_total_for_level } from "./xp.js";

export interface BaseStats {
  base_hp: number;
  base_attack: number;
  base_defense: number;
}

export interface Growth {
  hp: number;
  attack: number;
  defense: number;
}

// Levels above 1 that contribute growth, clamped to [0, max_level - 1].
export function growth_levels(level: number): number {
  return Math.max(0, Math.min(XP_CURVE.max_level - 1, Math.floor(level) - 1));
}

export function hp_at_level(base: BaseStats, growth: Growth, level: number): number {
  return Math.floor(base.base_hp + growth.hp * growth_levels(level));
}

export function attack_at_level(base: BaseStats, growth: Growth, level: number): number {
  return Math.floor(base.base_attack + growth.attack * growth_levels(level));
}

export function defense_at_level(base: BaseStats, growth: Growth, level: number): number {
  return Math.floor(base.base_defense + growth.defense * growth_levels(level));
}

// XP gathered inside the current level (for the XP bar numerator).
export function xp_into_level(total_xp: number, level: number): number {
  return Math.max(0, total_xp - xp_total_for_level(level));
}

// XP needed to finish the current level (XP bar denominator). 0 at max level.
export function xp_to_next_level(level: number): number {
  if (level >= XP_CURVE.max_level) {
    return 0;
  }
  return xp_for_level(level + 1);
}

// 0..1 fraction of the current level completed; 1 at max level.
export function level_progress(total_xp: number, level: number): number {
  const need: number = xp_to_next_level(level);
  if (need <= 0) {
    return 1;
  }
  return Math.min(1, xp_into_level(total_xp, level) / need);
}
