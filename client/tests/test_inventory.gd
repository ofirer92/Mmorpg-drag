extends GutTest
## T-0.11 DoD: bag add/stack/capacity/remove, equip/unequip with swap-back,
## equipped_stats summation, gear-comparison deltas, and to_dict/from_dict
## round trips — all against client/scripts/inventory/inventory.gd, with no
## Node/scene involved (pure RefCounted logic).

const WEAPON_1: String = "rubber_stamp_sword"
const WEAPON_2: String = "triplicate_dagger"
const HEAD_1: String = "ethics_committee_cap"
const BODY_1: String = "liability_waiver_robe"
const CONSUMABLE_1: String = "expired_bandage"


func _equipped_in(inv: Inventory, slot: String) -> String:
	return String(inv.equipped.get(slot, ""))


func test_add_unknown_item_is_rejected() -> void:
	var inv: Inventory = Inventory.new()
	assert_false(inv.add("does_not_exist"))
	assert_eq(inv.slots().size(), 0)


func test_add_non_positive_amount_is_rejected() -> void:
	var inv: Inventory = Inventory.new()
	assert_false(inv.add(CONSUMABLE_1, 0))
	assert_false(inv.add(CONSUMABLE_1, -3))


func test_add_consumable_stacks_into_one_row() -> void:
	var inv: Inventory = Inventory.new()
	assert_true(inv.add(CONSUMABLE_1, 2))
	assert_true(inv.add(CONSUMABLE_1, 3))
	assert_eq(inv.slots().size(), 1)
	assert_eq(inv.count(CONSUMABLE_1), 5)


func test_add_equippable_items_do_not_stack() -> void:
	var inv: Inventory = Inventory.new()
	inv.add(WEAPON_1)
	inv.add(WEAPON_1)
	assert_eq(inv.slots().size(), 2, "each unit of a non-consumable takes its own row")
	assert_eq(inv.count(WEAPON_1), 2)


func test_add_respects_capacity() -> void:
	var inv: Inventory = Inventory.new(2)
	assert_true(inv.add(WEAPON_1))
	assert_true(inv.add(WEAPON_2))
	assert_false(inv.add(HEAD_1), "bag is full at capacity 2")
	assert_eq(inv.slots().size(), 2)


func test_add_more_of_a_held_consumable_does_not_need_a_new_row_even_when_full() -> void:
	var inv: Inventory = Inventory.new(1)
	assert_true(inv.add(CONSUMABLE_1, 1))
	assert_true(inv.add(CONSUMABLE_1, 1), "topping up an existing stack never needs a new row")
	assert_eq(inv.count(CONSUMABLE_1), 2)


func test_remove_decrements_and_drops_empty_row() -> void:
	var inv: Inventory = Inventory.new()
	inv.add(CONSUMABLE_1, 3)
	assert_true(inv.remove(CONSUMABLE_1, 2))
	assert_eq(inv.count(CONSUMABLE_1), 1)
	assert_true(inv.remove(CONSUMABLE_1, 1))
	assert_eq(inv.count(CONSUMABLE_1), 0)
	assert_eq(inv.slots().size(), 0)


func test_remove_more_than_held_fails_and_changes_nothing() -> void:
	var inv: Inventory = Inventory.new()
	inv.add(CONSUMABLE_1, 1)
	assert_false(inv.remove(CONSUMABLE_1, 5))
	assert_eq(inv.count(CONSUMABLE_1), 1)


func test_remove_unknown_item_fails() -> void:
	var inv: Inventory = Inventory.new()
	assert_false(inv.remove("does_not_exist", 1))


func test_count_sums_across_multiple_non_stacking_rows() -> void:
	var inv: Inventory = Inventory.new()
	inv.add(WEAPON_1)
	inv.add(WEAPON_1)
	inv.add(WEAPON_1)
	assert_eq(inv.count(WEAPON_1), 3)


func test_slots_returns_bag_contents_in_row_order() -> void:
	var inv: Inventory = Inventory.new()
	inv.add(WEAPON_1)
	inv.add(HEAD_1)
	var s: Array[Dictionary] = inv.slots()
	assert_eq(s.size(), 2)
	assert_eq(s[0]["item_id"], WEAPON_1)
	assert_eq(s[1]["item_id"], HEAD_1)


func test_equip_moves_item_from_bag_to_equipped_slot() -> void:
	var inv: Inventory = Inventory.new()
	inv.add(WEAPON_1)
	assert_true(inv.equip(WEAPON_1))
	assert_eq(_equipped_in(inv, "weapon"), WEAPON_1)
	assert_eq(inv.count(WEAPON_1), 0, "the equipped unit left the bag")


func test_equip_swaps_previous_item_back_into_bag() -> void:
	var inv: Inventory = Inventory.new()
	inv.add(WEAPON_1)
	inv.add(WEAPON_2)
	inv.equip(WEAPON_1)
	assert_true(inv.equip(WEAPON_2))
	assert_eq(_equipped_in(inv, "weapon"), WEAPON_2)
	assert_eq(inv.count(WEAPON_1), 1, "the previously-equipped weapon returned to the bag")


func test_equip_consumable_fails() -> void:
	var inv: Inventory = Inventory.new()
	inv.add(CONSUMABLE_1)
	assert_false(inv.equip(CONSUMABLE_1))
	assert_eq(inv.count(CONSUMABLE_1), 1, "a rejected equip must not remove the item from the bag")


func test_equip_item_not_held_fails() -> void:
	var inv: Inventory = Inventory.new()
	assert_false(inv.equip(WEAPON_1))


func test_equip_unknown_item_fails() -> void:
	var inv: Inventory = Inventory.new()
	assert_false(inv.equip("does_not_exist"))


func test_unequip_returns_item_to_bag() -> void:
	var inv: Inventory = Inventory.new()
	inv.add(HEAD_1)
	inv.equip(HEAD_1)
	assert_true(inv.unequip("head"))
	assert_eq(_equipped_in(inv, "head"), "")
	assert_eq(inv.count(HEAD_1), 1)


func test_unequip_empty_slot_fails() -> void:
	var inv: Inventory = Inventory.new()
	assert_false(inv.unequip("head"))
	assert_false(inv.unequip("not_a_slot"))


func test_unequip_fails_without_bag_room_and_leaves_gear_equipped() -> void:
	var inv: Inventory = Inventory.new(1)
	inv.add(HEAD_1)
	inv.equip(HEAD_1)
	inv.add(CONSUMABLE_1)  # fills the bag's single row
	assert_false(inv.unequip("head"), "no room to return the item")
	assert_eq(_equipped_in(inv, "head"), HEAD_1, "gear stays equipped when the swap-back fails")


func test_equipped_stats_sums_every_equipped_slot() -> void:
	var inv: Inventory = Inventory.new()
	inv.add(WEAPON_1)
	inv.add(HEAD_1)
	inv.add(BODY_1)
	inv.equip(WEAPON_1)
	inv.equip(HEAD_1)
	inv.equip(BODY_1)
	var stats: Dictionary = inv.equipped_stats()
	assert_eq(stats["attack"], 4)
	assert_eq(stats["defense"], 9)
	assert_eq(stats["hp"], 20)


func test_equipped_stats_empty_when_nothing_equipped() -> void:
	var inv: Inventory = Inventory.new()
	var stats: Dictionary = inv.equipped_stats()
	assert_eq(stats, {"attack": 0, "defense": 0, "hp": 0})


func test_compare_against_currently_equipped_item() -> void:
	var inv: Inventory = Inventory.new()
	inv.add(WEAPON_1)
	inv.equip(WEAPON_1)
	var delta: Dictionary = inv.compare(WEAPON_2)
	assert_eq(delta["attack"], 3, "triplicate_dagger(7) - rubber_stamp_sword(4)")
	assert_eq(delta["defense"], 0)
	assert_eq(delta["hp"], 0)


func test_compare_against_empty_slot_equals_the_items_own_stats() -> void:
	var inv: Inventory = Inventory.new()
	var delta: Dictionary = inv.compare(HEAD_1)
	assert_eq(delta, {"attack": 0, "defense": 3, "hp": 5})


func test_compare_unknown_item_is_all_zero() -> void:
	var inv: Inventory = Inventory.new()
	assert_eq(inv.compare("does_not_exist"), {"attack": 0, "defense": 0, "hp": 0})


func test_to_dict_from_dict_round_trip() -> void:
	var inv: Inventory = Inventory.new(5)
	inv.add(CONSUMABLE_1, 2)
	inv.add(WEAPON_1)
	inv.add(WEAPON_2)
	inv.equip(WEAPON_2)

	var d: Dictionary = inv.to_dict()
	var restored: Inventory = Inventory.new()
	restored.from_dict(d)

	assert_eq(restored.capacity, 5)
	assert_eq(restored.count(CONSUMABLE_1), 2)
	assert_eq(restored.count(WEAPON_1), 1)
	assert_eq(_equipped_in(restored, "weapon"), WEAPON_2)
	assert_eq(restored.to_dict(), d)


func test_from_dict_skips_unknown_items_without_crashing() -> void:
	var inv: Inventory = Inventory.new()
	inv.from_dict(
		{
			"capacity": 10,
			"slots": [{"item_id": "does_not_exist", "count": 3}, {"item_id": CONSUMABLE_1, "count": 1}],
			"equipped": {"weapon": "also_missing", "head": HEAD_1},
		}
	)
	assert_eq(inv.count(CONSUMABLE_1), 1)
	assert_eq(inv.count("does_not_exist"), 0)
	assert_eq(_equipped_in(inv, "weapon"), "")
	assert_eq(_equipped_in(inv, "head"), HEAD_1)


func test_from_dict_with_malformed_payload_does_not_crash() -> void:
	var inv: Inventory = Inventory.new()
	inv.from_dict({})
	assert_eq(inv.slots().size(), 0)


func test_changed_signal_emitted_on_add_remove_equip_unequip() -> void:
	var inv: Inventory = Inventory.new()
	watch_signals(inv)
	inv.add(WEAPON_1)
	assert_signal_emitted(inv, "changed")
	inv.equip(WEAPON_1)
	assert_signal_emit_count(inv, "changed", 2)
	inv.unequip("weapon")
	assert_signal_emit_count(inv, "changed", 3)


func test_equipped_changed_signal_carries_slot_and_item() -> void:
	var inv: Inventory = Inventory.new()
	inv.add(WEAPON_1)
	watch_signals(inv)
	inv.equip(WEAPON_1)
	assert_signal_emitted_with_parameters(inv, "equipped_changed", ["weapon", WEAPON_1])
	inv.unequip("weapon")
	assert_signal_emitted_with_parameters(inv, "equipped_changed", ["weapon", ""])
