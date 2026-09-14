// XP curve. RulesScript subset (see .claude/skills/shared-rules-authoring). Numbers come from docs/balance/xp_curve.yaml.
import { XP_CURVE } from "./_balance_data.js";

// XP needed to go from level-1 to level. Level 1 costs 0.
export function xp_for_level(level: number): number {
  if (level <= 1) {
    return 0;
  }
  const n: number = level - 1;
  return Math.floor(XP_CURVE.base * Math.pow(n, XP_CURVE.exponent) + XP_CURVE.linear * n);
}

// Cumulative XP from level 1 to reach level.
export function xp_total_for_level(level: number): number {
  let total: number = 0;
  for (let l = 2; l <= level; l++) {
    total += xp_for_level(l);
  }
  return total;
}

// Level reached with a given cumulative XP, capped at max_level.
export function level_for_xp(xp: number): number {
  let level: number = 1;
  let spent: number = 0;
  for (let l = 2; l <= XP_CURVE.max_level; l++) {
    spent += xp_for_level(l);
    if (xp < spent) {
      return level;
    }
    level = l;
  }
  return level;
}
