# GENERATED from packages/shared-rules/src/progression.ts sha256:15aeccc84ac3e280 — DO NOT EDIT (run scripts/gen_rules.py)
class_name RulesProgression

# Character progression: stats at a level and XP-bar helpers. RulesScript subset.
# Growth numbers come from docs/balance/classes.yaml (archetypes.<id>.growth) via _balance_data.



# Levels above 1 that contribute growth, clamped to [0, max_level - 1].

static func growth_levels(level: float) -> float:
	return max(0.0, min(RulesBalanceData.XP_CURVE.max_level - 1.0, floor(level) - 1.0))

static func hp_at_level(base: Dictionary, growth: Dictionary, level: float) -> float:
	return floor(base.base_hp + growth.hp * growth_levels(level))

static func attack_at_level(base: Dictionary, growth: Dictionary, level: float) -> float:
	return floor(base.base_attack + growth.attack * growth_levels(level))

static func defense_at_level(base: Dictionary, growth: Dictionary, level: float) -> float:
	return floor(base.base_defense + growth.defense * growth_levels(level))

# XP gathered inside the current level (for the XP bar numerator).

static func xp_into_level(total_xp: float, level: float) -> float:
	return max(0.0, total_xp - RulesXp.xp_total_for_level(level))

# XP needed to finish the current level (XP bar denominator). 0 at max level.

static func xp_to_next_level(level: float) -> float:
	if level >= RulesBalanceData.XP_CURVE.max_level:
		return 0.0
	return RulesXp.xp_for_level(level + 1.0)

# 0..1 fraction of the current level completed; 1 at max level.

static func level_progress(total_xp: float, level: float) -> float:
	var need: float = xp_to_next_level(level)
	if need <= 0.0:
		return 1.0
	return min(1.0, xp_into_level(total_xp, level) / need)
