extends GutTest
## T-I.5 DoD: the generated GDScript must produce the SAME numbers as the TypeScript source.
## Both sides assert packages/shared-rules/tests/fixtures/xp_curve.json (see scripts/gen_fixtures.py).

const FIXTURE_PATH: String = "res://../packages/shared-rules/tests/fixtures/xp_curve.json"


func _load_fixture() -> Dictionary:
	var f: FileAccess = FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	assert_not_null(f, "fixture readable at %s" % FIXTURE_PATH)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary, "fixture is a JSON object")
	return parsed if parsed is Dictionary else {}


func test_level_one_is_free() -> void:
	assert_eq(RulesXp.xp_for_level(1), 0.0)
	assert_eq(RulesXp.xp_for_level(0), 0.0)


func test_matches_shared_fixture() -> void:
	var fx: Dictionary = _load_fixture()
	var table: Dictionary = fx.get("xp_for_level", {})
	assert_gt(table.size(), 0, "fixture has levels")
	for level_key: String in table.keys():
		var level: int = int(level_key)
		assert_eq(RulesXp.xp_for_level(level), float(table[level_key]), "xp_for_level(%d)" % level)
	var totals: Dictionary = fx.get("xp_total_for_level", {})
	for level_key: String in totals.keys():
		var level: int = int(level_key)
		assert_eq(RulesXp.xp_total_for_level(level), float(totals[level_key]), "xp_total_for_level(%d)" % level)


func test_level_for_xp_round_trips() -> void:
	var max_level: int = int(RulesBalanceData.XP_CURVE["max_level"])
	for level: int in range(1, max_level + 1):
		assert_eq(RulesXp.level_for_xp(RulesXp.xp_total_for_level(level)), float(level))
	assert_eq(RulesXp.level_for_xp(1.0e15), float(max_level))


func test_protocol_types_known() -> void:
	assert_true(RulesProtocol.is_known("ping"))
	assert_false(RulesProtocol.is_known("teleport"))
