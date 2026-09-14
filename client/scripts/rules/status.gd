# GENERATED from packages/shared-rules/src/status.ts sha256:b7ef33d414effc94 — DO NOT EDIT (run scripts/gen_rules.py)
class_name RulesStatus

# Status mechanics. RulesScript subset. Phase 0: the Stim "crash" — after N consecutive landed hits the
# player crashes for D seconds and takes damage × M. Numbers come from docs/balance/classes.yaml
# (archetypes.stim.mechanics.crash) via _balance_data — never literals here.

# Consecutive-hit counter after an attack: a landed hit increments, a miss/idle resets to 0.

static func next_consecutive_hits(hits: float, hit_landed: bool) -> float:
	if hit_landed:
		return hits + 1.0
	return 0.0

# Does this many consecutive hits trigger the crash?

static func crash_triggers(consecutive_hits: float) -> bool:
	return consecutive_hits >= RulesBalanceData.CLASSES.archetypes.stim.mechanics.crash.hits_in_a_row

# How long the crash lasts, in seconds.

static func crash_duration_s() -> float:
	return RulesBalanceData.CLASSES.archetypes.stim.mechanics.crash.duration_s

# Multiplier applied to damage TAKEN while crashed (1 when not crashed).

static func crash_damage_taken_mult(crash_active: bool) -> float:
	if crash_active:
		return RulesBalanceData.CLASSES.archetypes.stim.mechanics.crash.damage_taken_mult
	return 1.0

# Damage taken after the crash multiplier, floored, never below 0.

static func damage_taken(dmg: float, crash_active: bool) -> float:
	return max(0.0, floor(dmg * crash_damage_taken_mult(crash_active)))
