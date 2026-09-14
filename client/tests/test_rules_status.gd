extends GutTest
## Parity for generated status.gd (stim crash) against the same YAML numbers the TS tests use.


func test_crash_numbers_come_from_classes_yaml() -> void:
	var crash: Dictionary = RulesBalanceData.CLASSES["archetypes"]["stim"]["mechanics"]["crash"]
	var n: int = int(crash["hits_in_a_row"])
	assert_false(RulesStatus.crash_triggers(n - 1))
	assert_true(RulesStatus.crash_triggers(n))
	assert_eq(RulesStatus.crash_duration_s(), float(crash["duration_s"]))
	assert_eq(RulesStatus.crash_damage_taken_mult(true), float(crash["damage_taken_mult"]))
	assert_eq(RulesStatus.crash_damage_taken_mult(false), 1.0)


func test_counter_and_damage_taken() -> void:
	assert_eq(RulesStatus.next_consecutive_hits(3, true), 4.0)
	assert_eq(RulesStatus.next_consecutive_hits(3, false), 0.0)
	assert_eq(RulesStatus.damage_taken(7, false), 7.0)
	assert_eq(RulesStatus.damage_taken(7, true), floor(7.0 * RulesStatus.crash_damage_taken_mult(true)))
	assert_eq(RulesStatus.damage_taken(-5, true), 0.0)
