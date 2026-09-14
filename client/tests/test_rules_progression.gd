extends GutTest
## Parity for generated progression.gd against the same YAML numbers the TS tests use.


func test_stats_at_level() -> void:
	var stim: Dictionary = RulesBalanceData.CLASSES["archetypes"]["stim"]
	var growth: Dictionary = stim["growth"]
	assert_eq(RulesProgression.hp_at_level(stim, growth, 1), float(stim["base_hp"]))
	assert_eq(RulesProgression.hp_at_level(stim, growth, 10), floor(float(stim["base_hp"]) + float(growth["hp"]) * 9.0))
	assert_eq(RulesProgression.attack_at_level(stim, growth, 10), floor(float(stim["base_attack"]) + float(growth["attack"]) * 9.0))
	var max_level: int = int(RulesBalanceData.XP_CURVE["max_level"])
	assert_eq(RulesProgression.growth_levels(max_level + 50), float(max_level - 1))


func test_xp_bar_helpers() -> void:
	assert_eq(RulesProgression.xp_to_next_level(1), RulesXp.xp_for_level(2))
	assert_eq(RulesProgression.level_progress(0, 1), 0.0)
	var start_l5: float = RulesXp.xp_total_for_level(5)
	assert_eq(RulesProgression.xp_into_level(start_l5 + 7.0, 5), 7.0)
	assert_eq(RulesProgression.level_progress(start_l5 + 7.0, 5), min(1.0, 7.0 / RulesXp.xp_for_level(6)))
