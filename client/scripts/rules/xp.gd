# GENERATED from packages/shared-rules/src/xp.ts sha256:77645706a08600d4 — DO NOT EDIT (run scripts/gen_rules.py)
class_name RulesXp

# XP curve. RulesScript subset (see .claude/skills/shared-rules-authoring). Numbers come from docs/balance/xp_curve.yaml.

# XP needed to go from level-1 to level. Level 1 costs 0.

static func xp_for_level(level: float) -> float:
	if level <= 1.0:
		return 0.0
	var n: float = level - 1.0
	return floor(RulesBalanceData.XP_CURVE.base * pow(n, RulesBalanceData.XP_CURVE.exponent) + RulesBalanceData.XP_CURVE.linear * n)

# Cumulative XP from level 1 to reach level.

static func xp_total_for_level(level: float) -> float:
	var total: float = 0.0
	for l in range(int(2.0), int(level) + 1):
		total += xp_for_level(l)
	return total

# Level reached with a given cumulative XP, capped at max_level.

static func level_for_xp(xp: float) -> float:
	var level: float = 1.0
	var spent: float = 0.0
	for l in range(int(2.0), int(RulesBalanceData.XP_CURVE.max_level) + 1):
		spent += xp_for_level(l)
		if xp < spent:
			return level
		level = l
	return level
