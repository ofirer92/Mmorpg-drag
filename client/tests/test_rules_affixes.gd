extends GutTest
## T-1.7 DoD: the generated GDScript must produce the SAME numbers/strings as the TypeScript source.
## Both sides assert packages/shared-rules/tests/fixtures/affixes.json (see scripts/gen_fixtures.py).

const FIXTURE_PATH: String = "res://../packages/shared-rules/tests/fixtures/affixes.json"
const RARITIES: Array[String] = ["common", "rare", "epic"]


func _load_fixture() -> Dictionary:
	var f: FileAccess = FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	assert_not_null(f, "fixture readable at %s" % FIXTURE_PATH)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary, "fixture is a JSON object")
	return parsed if parsed is Dictionary else {}


func test_affix_count_bounds_per_rarity() -> void:
	for rarity: String in RARITIES:
		var slots: Dictionary = RulesBalanceData.ITEMS.affix_slots[rarity]
		for i: int in range(200):
			var count: float = RulesAffixes.affix_count(rarity, i / 200.0)
			assert_between(count, float(slots.min), float(slots.max), "affix_count(%s)" % rarity)
		assert_eq(RulesAffixes.affix_count(rarity, 0.0), float(slots.min))
		assert_eq(RulesAffixes.affix_count(rarity, 0.999999), float(slots.max))


func test_affix_count_unknown_rarity_is_zero() -> void:
	assert_eq(RulesAffixes.affix_count("does_not_exist", 0.5), 0.0)


func test_matches_shared_affix_count_fixture() -> void:
	var fx: Dictionary = _load_fixture()
	var cases: Array = fx.get("affix_count_cases", [])
	assert_gt(cases.size(), 0, "fixture has affix_count cases")
	for c: Dictionary in cases:
		var got: float = RulesAffixes.affix_count(c.rarity, c.roll)
		assert_eq(got, float(c.expected), "affix_count(%s)" % JSON.stringify(c))


func test_pool_respects_rarities() -> void:
	for rarity: String in RARITIES:
		var expected: int = 0
		for id: String in RulesBalanceData.ITEMS.affixes.keys():
			var allowed: bool = RulesBalanceData.ITEMS.affixes[id]["rarities"].has(rarity)
			assert_eq(RulesAffixes.affix_allows_rarity(id, rarity), allowed)
			if allowed:
				expected += 1
		assert_eq(RulesAffixes.affix_pool_size(rarity), float(expected))


func test_pool_size_unknown_rarity_is_zero() -> void:
	assert_eq(RulesAffixes.affix_pool_size("does_not_exist"), 0.0)


func test_roll_affix_id_only_returns_allowed_ids_or_empty() -> void:
	for rarity: String in RARITIES:
		for i: int in range(100):
			var id: String = RulesAffixes.roll_affix_id(rarity, i / 100.0)
			if id != "":
				assert_true(RulesAffixes.affix_allows_rarity(id, rarity))


func test_roll_affix_id_unknown_rarity_is_empty() -> void:
	assert_eq(RulesAffixes.roll_affix_id("does_not_exist", 0.5), "")


func test_matches_shared_roll_affix_id_fixture() -> void:
	var fx: Dictionary = _load_fixture()
	var cases: Array = fx.get("roll_affix_id_cases", [])
	assert_gt(cases.size(), 0, "fixture has roll_affix_id cases")
	for c: Dictionary in cases:
		var got: String = RulesAffixes.roll_affix_id(c.rarity, c.roll)
		assert_eq(got, String(c.expected), "roll_affix_id(%s)" % JSON.stringify(c))


func test_affix_stat_and_mult_known_and_unknown() -> void:
	var affixes: Dictionary = RulesBalanceData.ITEMS.affixes
	for id: String in affixes.keys():
		var def: Dictionary = affixes[id]
		assert_eq(RulesAffixes.affix_stat(id, "attack"), float(def.stats.attack))
		assert_eq(RulesAffixes.affix_stat(id, "defense"), float(def.stats.defense))
		assert_eq(RulesAffixes.affix_stat(id, "hp"), float(def.stats.hp))
		assert_eq(RulesAffixes.affix_mult(id, "attack"), float(def.mult.attack))
	assert_eq(RulesAffixes.affix_stat("does_not_exist", "attack"), 0.0)
	assert_eq(RulesAffixes.affix_mult("does_not_exist", "attack"), 0.0)
	var any_id: String = affixes.keys()[0]
	assert_eq(RulesAffixes.affix_stat(any_id, "mana"), 0.0)


func test_item_stat_with_affixes_floors_and_zero_mult() -> void:
	assert_eq(RulesAffixes.item_stat_with_affixes(7.0, 0.0, 0.0), 7.0)
	assert_eq(RulesAffixes.item_stat_with_affixes(7.9, 0.0, 0.0), 7.0)
	assert_eq(RulesAffixes.item_stat_with_affixes(10.0, 5.0, 0.1), 16.0)
	assert_eq(RulesAffixes.item_stat_with_affixes(0.0, 5.0, 0.5), 7.0)


func test_epic_item_gets_at_least_epic_min_slots() -> void:
	var epic_slots: Dictionary = RulesBalanceData.ITEMS.affix_slots["epic"]
	for i: int in range(50):
		assert_true(RulesAffixes.affix_count("epic", i / 50.0) >= float(epic_slots.min))
