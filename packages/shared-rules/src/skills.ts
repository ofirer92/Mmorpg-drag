// Skill rules. RulesScript subset. Skill definitions come from docs/balance/classes.yaml (archetypes.<id>.skills).
export interface SkillDef {
  level: number;
  power: number;
  hits: number;
  cooldown: number;
  crash_hits: number;
  range_px: number;
}

// A skill is usable once the player reaches its level.
export function skill_unlocked(skill_level: number, player_level: number): boolean {
  return player_level >= skill_level;
}

// Cooldown gate: ready when the time since last use covers the cooldown (0 = always ready).
export function skill_ready(time_since_use: number, cooldown: number): boolean {
  if (cooldown <= 0) {
    return true;
  }
  return time_since_use >= cooldown;
}

// Seconds left before the skill is ready (0 when ready).
export function skill_cooldown_left(time_since_use: number, cooldown: number): number {
  return Math.max(0, cooldown - Math.max(0, time_since_use));
}

// Total damage multiplier of a skill over all its hits (for balance sims and tooltips).
export function skill_total_power(skill: SkillDef): number {
  return skill.power * Math.max(1, skill.hits);
}

// Extra consecutive-hit counter increments a skill adds beyond the landed hit itself.
export function skill_crash_hits(skill: SkillDef): number {
  return Math.max(0, skill.crash_hits);
}
