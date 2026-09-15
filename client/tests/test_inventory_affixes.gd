extends GutTest
## T-1.7b DoD: bag rows are ITEM INSTANCES carrying rolled affixes. Two rolls of the same item must
## stay distinct, affixes must survive equipping/unequipping/saving, comparison must account for
## them, and the affix numbers must come from RulesAffixes — never from the client.

const WEAPON_COMMON: String = "rubber_stamp_sword"  # common, attack 4
const WEAPON_RARE: String = "triplicate_dagger"  # rare, attack 7
const HEAD_COMMON: String = "ethics_committee_cap"  # common, defense 3 / hp 5
const CONSUMABLE: String = "expired_bandage"
## Flat +2 attack, no multiplier (docs/balance/items.yaml). Legal on common.
const AFFIX_FLAT_ATTACK: String = "off_label"
## +8% defense, no flat (docs/balance/items.yaml). Legal on common.
const AFFIX_MULT_DEFENSE: String = "dosage_adjusted"


func _inv(capacity: int = 20) -> Inventory:
	return Inventory.new(capacity)


## --- stats -------------------------------------------------------------------


func test_item_stats_with_affixes_matches_the_rules_module() -> void:
	var base: int = int(RulesBalanceData.ITEMS["items"][WEAPON_COMMON]["stats"]["attack"])
	var stats: Dictionary = Inventory.item_stats_with_affixes(WEAPON_COMMON, [AFFIX_FLAT_ATTACK])

	var expected: float = RulesAffixes.item_stat_with_affixes(
		float(base), RulesAffixes.affix_stat(AFFIX_FLAT_ATTACK, "attack"), 0.0
	)
	assert_eq(stats["attack"], int(expected))
	assert_gt(stats["attack"], base, "a flat attack affix must actually raise attack")


func test_percentage_affix_applies_after_the_flat_sum() -> void:
	var base: int = int(RulesBalanceData.ITEMS["items"][HEAD_COMMON]["stats"]["defense"])
	var stats: Dictionary = Inventory.item_stats_with_affixes(HEAD_COMMON, [AFFIX_MULT_DEFENSE])

	var expected: float = RulesAffixes.item_stat_with_affixes(
		float(base), 0.0, RulesAffixes.affix_mult(AFFIX_MULT_DEFENSE, "defense")
	)
	assert_eq(stats["defense"], int(expected))


func test_no_affixes_is_the_plain_item() -> void:
	var plain: Dictionary = Inventory.item_stats_with_affixes(WEAPON_COMMON, [])
	assert_eq(plain["attack"], int(RulesBalanceData.ITEMS["items"][WEAPON_COMMON]["stats"]["attack"]))


func test_unknown_affix_ids_contribute_nothing() -> void:
	var real: Dictionary = Inventory.item_stats_with_affixes(WEAPON_COMMON, [])
	var bogus: Dictionary = Inventory.item_stats_with_affixes(WEAPON_COMMON, ["not_an_affix"])
	assert_eq(bogus, real, "a hand-edited save must not be able to invent stats")


## --- instances in the bag ------------------------------------------------------


func test_two_rolls_of_the_same_item_stay_separate_rows() -> void:
	var inv: Inventory = _inv()

	assert_true(inv.add_instance(WEAPON_COMMON, [AFFIX_FLAT_ATTACK]))
	assert_true(inv.add_instance(WEAPON_COMMON, [AFFIX_MULT_DEFENSE]))

	var rows: Array[Dictionary] = inv.slots()
	assert_eq(rows.size(), 2, "different rolls are different items and must not merge")
	assert_eq(inv.affixes_at(0), [AFFIX_FLAT_ATTACK] as Array[String])
	assert_eq(inv.affixes_at(1), [AFFIX_MULT_DEFENSE] as Array[String])


func test_duplicate_and_unknown_affixes_are_cleaned_on_entry() -> void:
	var inv: Inventory = _inv()

	inv.add_instance(WEAPON_COMMON, [AFFIX_FLAT_ATTACK, AFFIX_FLAT_ATTACK, "nope", ""])

	assert_eq(inv.affixes_at(0), [AFFIX_FLAT_ATTACK] as Array[String])


func test_consumables_ignore_affixes_and_still_stack() -> void:
	var inv: Inventory = _inv()

	inv.add_instance(CONSUMABLE, [AFFIX_FLAT_ATTACK])
	inv.add_instance(CONSUMABLE, [])

	assert_eq(inv.slots().size(), 1, "consumables still stack into one row")
	assert_eq(inv.count(CONSUMABLE), 2)
	assert_eq(inv.affixes_at(0), [] as Array[String], "a consumable never carries affixes")


func test_add_instance_rejects_unknown_items_and_a_full_bag() -> void:
	var inv: Inventory = _inv(1)

	assert_false(inv.add_instance("no_such_item", [AFFIX_FLAT_ATTACK]))
	assert_true(inv.add_instance(WEAPON_COMMON, [AFFIX_FLAT_ATTACK]))
	assert_false(inv.add_instance(WEAPON_RARE, [AFFIX_FLAT_ATTACK]), "bag is full")
	assert_eq(inv.slots().size(), 1)


func test_affixes_at_out_of_range_is_empty_not_a_crash() -> void:
	var inv: Inventory = _inv()
	assert_eq(inv.affixes_at(-1), [] as Array[String])
	assert_eq(inv.affixes_at(99), [] as Array[String])


## --- equipping -------------------------------------------------------------------


func test_equip_at_equips_that_exact_instance_and_its_affixes_count() -> void:
	var inv: Inventory = _inv()
	inv.add_instance(WEAPON_COMMON, [])
	inv.add_instance(WEAPON_COMMON, [AFFIX_FLAT_ATTACK])

	assert_true(inv.equip_at(1), "equip the SECOND row, the affixed one")

	assert_eq(inv.equipped_item_id("weapon"), WEAPON_COMMON)
	assert_eq(inv.equipped_affixes_of("weapon"), [AFFIX_FLAT_ATTACK] as Array[String])
	var expected: Dictionary = Inventory.item_stats_with_affixes(WEAPON_COMMON, [AFFIX_FLAT_ATTACK])
	assert_eq(inv.equipped_stats()["attack"], expected["attack"], "gear bonus includes the affix")


func test_swapping_gear_returns_the_old_instance_with_its_affixes() -> void:
	var inv: Inventory = _inv()
	inv.add_instance(WEAPON_COMMON, [AFFIX_FLAT_ATTACK])
	inv.add_instance(WEAPON_RARE, [])
	inv.equip_at(0)

	# Equipping the other weapon swaps the affixed one back into the bag.
	assert_true(inv.equip(WEAPON_RARE))

	assert_eq(inv.equipped_item_id("weapon"), WEAPON_RARE)
	var rows: Array[Dictionary] = inv.slots()
	assert_eq(rows.size(), 1)
	assert_eq(
		inv.affixes_at(0), [AFFIX_FLAT_ATTACK] as Array[String], "the swapped-out roll is not lost"
	)


func test_unequip_returns_the_instance_with_its_affixes() -> void:
	var inv: Inventory = _inv()
	inv.add_instance(HEAD_COMMON, [AFFIX_MULT_DEFENSE])
	inv.equip_at(0)

	assert_true(inv.unequip("head"))

	assert_eq(inv.equipped_item_id("head"), "")
	assert_eq(inv.affixes_at(0), [AFFIX_MULT_DEFENSE] as Array[String])


func test_equip_at_rejects_out_of_range_and_consumables() -> void:
	var inv: Inventory = _inv()
	inv.add_instance(CONSUMABLE, [])

	assert_false(inv.equip_at(0), "a consumable has no gear slot")
	assert_false(inv.equip_at(5))
	assert_eq(inv.count(CONSUMABLE), 1, "a rejected equip must not consume the item")


## --- comparison ---------------------------------------------------------------------


func test_compare_at_uses_the_selected_instances_affixes() -> void:
	var inv: Inventory = _inv()
	inv.add_instance(WEAPON_COMMON, [])  # row 0: plain
	inv.add_instance(WEAPON_COMMON, [AFFIX_FLAT_ATTACK])  # row 1: affixed
	inv.equip_at(0)  # plain one equipped; row 0 is now the affixed one

	var delta: Dictionary = inv.compare_at(0)

	var affix_bonus: int = int(RulesAffixes.affix_stat(AFFIX_FLAT_ATTACK, "attack"))
	assert_eq(
		int(delta["attack"]),
		affix_bonus,
		"the same item with one extra affix is exactly that affix better"
	)


func test_compare_at_out_of_range_is_a_zero_delta() -> void:
	var inv: Inventory = _inv()
	assert_eq(inv.compare_at(3), {"attack": 0, "defense": 0, "hp": 0})


## --- persistence ---------------------------------------------------------------------


func test_affixes_survive_a_save_load_round_trip() -> void:
	var inv: Inventory = _inv()
	inv.add_instance(WEAPON_COMMON, [AFFIX_FLAT_ATTACK])
	inv.add_instance(HEAD_COMMON, [AFFIX_MULT_DEFENSE])
	inv.equip_at(1)

	var restored: Inventory = _inv()
	restored.from_dict(inv.to_dict())

	assert_eq(restored.affixes_at(0), [AFFIX_FLAT_ATTACK] as Array[String], "bag roll restored")
	assert_eq(restored.equipped_item_id("head"), HEAD_COMMON)
	assert_eq(
		restored.equipped_affixes_of("head"),
		[AFFIX_MULT_DEFENSE] as Array[String],
		"equipped roll restored"
	)
	assert_eq(restored.equipped_stats(), inv.equipped_stats())


func test_a_pre_t17b_save_still_loads() -> void:
	# The old shape: `equipped` held a bare item_id String and bag rows had no "affixes" key.
	var restored: Inventory = _inv()
	restored.from_dict(
		{
			"capacity": 20,
			"slots": [{"item_id": WEAPON_COMMON, "count": 1}],
			"equipped": {"head": HEAD_COMMON},
			"money": 5,
		}
	)

	assert_eq(restored.count(WEAPON_COMMON), 1, "an old bag row loads as a plain instance")
	assert_eq(restored.affixes_at(0), [] as Array[String])
	assert_eq(restored.equipped_item_id("head"), HEAD_COMMON, "an old equipped item_id still loads")
	assert_eq(restored.equipped_affixes_of("head"), [] as Array[String])
	assert_eq(restored.money, 5)


func test_a_save_claiming_bogus_affixes_loads_them_as_none() -> void:
	var restored: Inventory = _inv()
	restored.from_dict(
		{
			"capacity": 20,
			"slots": [{"item_id": WEAPON_COMMON, "count": 1, "affixes": ["cheat_affix", 7]}],
			"equipped": {},
			"money": 0,
		}
	)

	assert_eq(restored.affixes_at(0), [] as Array[String], "a hand-edited save cannot invent affixes")


## --- the authority's roll ---------------------------------------------------------


func _server() -> LocalServer:
	return add_child_autofree(LocalServer.new())


func test_local_server_rolls_only_affixes_legal_for_the_items_rarity() -> void:
	var server: LocalServer = _server()
	# Many seeds, so this covers the whole pool rather than one lucky roll.
	for seed_value: int in range(60):
		server.seed_rng(seed_value)
		for item_id: String in [WEAPON_COMMON, WEAPON_RARE, HEAD_COMMON]:
			var rarity: String = String(RulesBalanceData.ITEMS["items"][item_id]["rarity"])
			var rolled: Array[String] = server._roll_affixes(item_id)
			var seen: Array[String] = []
			for affix_id: String in rolled:
				assert_true(
					RulesAffixes.affix_allows_rarity(affix_id, rarity),
					"%s is not legal on a %s item" % [affix_id, rarity]
				)
				assert_false(seen.has(affix_id), "an item must never roll the same affix twice")
				seen.append(affix_id)


func test_roll_count_stays_within_the_rarities_documented_slot_range() -> void:
	var server: LocalServer = _server()
	var slots: Dictionary = RulesBalanceData.ITEMS["affix_slots"]
	for seed_value: int in range(60):
		server.seed_rng(seed_value)
		for item_id: String in [WEAPON_COMMON, WEAPON_RARE]:
			var rarity: String = String(RulesBalanceData.ITEMS["items"][item_id]["rarity"])
			var lo: int = int(slots[rarity]["min"])
			var hi: int = int(slots[rarity]["max"])
			var rolled: Array[String] = server._roll_affixes(item_id)
			assert_between(rolled.size(), lo, hi, "%s rolled %d affixes" % [rarity, rolled.size()])


func test_no_drop_means_no_affixes() -> void:
	var server: LocalServer = _server()
	assert_eq(server._roll_affixes(""), [] as Array[String])
	assert_eq(server._roll_affixes("not_an_item"), [] as Array[String])


## --- shop -----------------------------------------------------------------------


func test_selling_takes_the_instance_the_player_tapped_not_the_oldest() -> void:
	var packed: PackedScene = load("res://scenes/ui/shop_panel.tscn")
	var shop: ShopPanel = add_child_autofree(packed.instantiate())
	var inv: Inventory = _inv()
	inv.add_instance(WEAPON_COMMON, [AFFIX_FLAT_ATTACK])  # row 0 — the good roll
	inv.add_instance(WEAPON_COMMON, [])  # row 1 — the plain one
	shop.bind(inv, "pharmacist")

	assert_true(shop.sell_at(1), "sell the PLAIN one")

	assert_eq(inv.slots().size(), 1)
	assert_eq(
		inv.affixes_at(0),
		[AFFIX_FLAT_ATTACK] as Array[String],
		"selling the plain roll must not consume the affixed one"
	)


func test_sell_at_rejects_an_out_of_range_row() -> void:
	var packed: PackedScene = load("res://scenes/ui/shop_panel.tscn")
	var shop: ShopPanel = add_child_autofree(packed.instantiate())
	var inv: Inventory = _inv()
	inv.add_instance(WEAPON_COMMON, [])
	shop.bind(inv, "pharmacist")

	assert_false(shop.sell_at(9))
	assert_eq(inv.money, 0, "a rejected sale pays nothing")
	assert_eq(inv.slots().size(), 1)
