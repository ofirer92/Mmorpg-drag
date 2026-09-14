extends GutTest
## T-0.6 DoD: the generated GDScript must produce the SAME numbers/strings as the TypeScript source.
## Both sides assert packages/shared-rules/tests/fixtures/combat.json (see scripts/gen_fixtures.py).

const FIXTURE_PATH: String = "res://../packages/shared-rules/tests/fixtures/combat.json"


func _load_fixture() -> Dictionary:
	var f: FileAccess = FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	assert_not_null(f, "fixture readable at %s" % FIXTURE_PATH)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary, "fixture is a JSON object")
	return parsed if parsed is Dictionary else {}


func test_min_damage_floor() -> void:
	var attacker: Dictionary = {"attack": 1.0, "defense": 0.0, "level": 1.0, "hp": 10.0}
	var defender: Dictionary = {"attack": 1.0, "defense": 500.0, "level": 1.0, "hp": 10.0}
	assert_eq(RulesCombat.damage(attacker, defender, 1.0, 0.9), RulesConstants.MIN_DAMAGE)


func test_crit_boundary() -> void:
	var attacker: Dictionary = {"attack": 20.0, "defense": 4.0, "level": 5.0, "hp": 90.0}
	var defender: Dictionary = {"attack": 5.0, "defense": 5.0, "level": 5.0, "hp": 60.0}
	var non_crit: float = RulesCombat.damage(attacker, defender, 1.0, RulesConstants.CRIT_CHANCE)
	var crit: float = RulesCombat.damage(attacker, defender, 1.0, RulesConstants.CRIT_CHANCE - 0.001)
	assert_eq(crit, floor(non_crit * RulesConstants.CRIT_MULT))
	assert_gt(crit, non_crit)


func test_effective_hp_and_apply_damage() -> void:
	var c: Dictionary = {"attack": 0.0, "defense": RulesConstants.DEF_SCALE, "level": 1.0, "hp": 80.0}
	assert_eq(RulesCombat.effective_hp(c), 160.0)
	assert_eq(RulesCombat.apply_damage(10.0, 9999.0), 0.0)
	assert_true(RulesCombat.is_dead(RulesCombat.apply_damage(10.0, 10.0)))


func test_matches_shared_damage_fixture() -> void:
	var fx: Dictionary = _load_fixture()
	var cases: Array = fx.get("damage_cases", [])
	assert_gt(cases.size(), 0, "fixture has damage cases")
	for c: Dictionary in cases:
		var got: float = RulesCombat.damage(c.attacker, c.defender, c.power, c.roll)
		assert_eq(got, float(c.expected), "damage(%s)" % JSON.stringify(c))


func test_matches_shared_loot_fixture() -> void:
	var fx: Dictionary = _load_fixture()
	var cases: Array = fx.get("loot_cases", [])
	assert_gt(cases.size(), 0, "fixture has loot cases")
	for c: Dictionary in cases:
		var got: String = RulesLoot.roll_loot(c.table_id, c.roll)
		assert_eq(got, String(c.expected), "roll_loot(%s)" % JSON.stringify(c))


func test_loot_value_unknown_item_is_zero() -> void:
	assert_eq(RulesLoot.loot_value("does_not_exist"), 0.0)
	assert_eq(RulesLoot.loot_value("expired_bandage"), float(RulesBalanceData.ITEMS.items.expired_bandage.value))
