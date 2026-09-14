# GENERATED from packages/shared-rules/src/skills.ts sha256:fc5a842ba9a38263 — DO NOT EDIT (run scripts/gen_rules.py)
class_name RulesSkills

# Skill rules. RulesScript subset. Skill definitions come from docs/balance/classes.yaml (archetypes.<id>.skills).

# A skill is usable once the player reaches its level.

static func skill_unlocked(skill_level: float, player_level: float) -> bool:
	return player_level >= skill_level

# Cooldown gate: ready when the time since last use covers the cooldown (0 = always ready).

static func skill_ready(time_since_use: float, cooldown: float) -> bool:
	if cooldown <= 0.0:
		return true
	return time_since_use >= cooldown

# Seconds left before the skill is ready (0 when ready).

static func skill_cooldown_left(time_since_use: float, cooldown: float) -> float:
	return max(0.0, cooldown - max(0.0, time_since_use))

# Total damage multiplier of a skill over all its hits (for balance sims and tooltips).

static func skill_total_power(skill: Dictionary) -> float:
	return skill.power * max(1.0, skill.hits)

# Extra consecutive-hit counter increments a skill adds beyond the landed hit itself.

static func skill_crash_hits(skill: Dictionary) -> float:
	return max(0.0, skill.crash_hits)
