extends GutTest
## T-0.12 DoD: ShopPanel (client/scripts/ui/shop_panel.gd) buy/sell against
## Inventory, gated by RulesEconomy prices — never a hardcoded price here
## either. Stock always mirrors docs/balance/npcs.yaml's pharmacist.stock.

const NPC_ID: String = "pharmacist"
const CONSUMABLE_1: String = "expired_bandage"  # value 3, in pharmacist.stock
const WEAPON_1: String = "rubber_stamp_sword"  # value 12, in pharmacist.stock
const NOT_IN_STOCK: String = "triplicate_dagger"  # value 30, NOT in pharmacist.stock


func _panel() -> ShopPanel:
	var packed: PackedScene = load("res://scenes/ui/shop_panel.tscn")
	var node: ShopPanel = packed.instantiate()
	add_child_autofree(node)
	return node


func _pharmacist_def() -> Dictionary:
	return RulesBalanceData.NPCS["npcs"][NPC_ID]


func _buy_price(item_id: String) -> int:
	var value: float = float(RulesBalanceData.ITEMS["items"][item_id]["value"])
	return int(RulesEconomy.buy_price(value))


func _sell_price(item_id: String) -> int:
	var value: float = float(RulesBalanceData.ITEMS["items"][item_id]["value"])
	return int(RulesEconomy.sell_price(value))


func test_stock_ids_lists_exactly_npcs_yaml_stock() -> void:
	var p: ShopPanel = _panel()
	var inv: Inventory = Inventory.new()
	p.bind(inv, NPC_ID)
	var expected: Array = _pharmacist_def()["stock"]
	assert_eq(p.stock_ids().size(), expected.size())
	for id: Variant in expected:
		assert_true(p.stock_ids().has(String(id)), "stock should include %s" % id)


func test_buy_deducts_buy_price_and_adds_the_item() -> void:
	var p: ShopPanel = _panel()
	var inv: Inventory = Inventory.new()
	inv.add_money(100)
	p.bind(inv, NPC_ID)
	var price: int = _buy_price(CONSUMABLE_1)

	assert_true(p.buy(CONSUMABLE_1))
	assert_eq(inv.money, 100 - price)
	assert_eq(inv.count(CONSUMABLE_1), 1)


func test_buy_refused_without_enough_money() -> void:
	var p: ShopPanel = _panel()
	var inv: Inventory = Inventory.new()
	inv.add_money(1)
	p.bind(inv, NPC_ID)
	var price: int = _buy_price(WEAPON_1)
	assert_true(price > 1, "weapon should cost more than 1")

	assert_false(p.buy(WEAPON_1))
	assert_eq(inv.money, 1)
	assert_eq(inv.count(WEAPON_1), 0)


func test_buy_refused_when_bag_is_full_and_money_is_refunded() -> void:
	var p: ShopPanel = _panel()
	var inv: Inventory = Inventory.new(1)  # capacity 1
	inv.add_money(1000)
	inv.add(NOT_IN_STOCK)  # fills the only row
	p.bind(inv, NPC_ID)
	var money_before: int = inv.money

	assert_false(p.buy(CONSUMABLE_1))
	assert_eq(inv.money, money_before, "spend should have been refunded")
	assert_eq(inv.count(CONSUMABLE_1), 0)


func test_sell_removes_the_item_and_adds_sell_price() -> void:
	var p: ShopPanel = _panel()
	var inv: Inventory = Inventory.new()
	inv.add(CONSUMABLE_1, 2)
	p.bind(inv, NPC_ID)
	var price: int = _sell_price(CONSUMABLE_1)

	assert_true(p.sell(CONSUMABLE_1))
	assert_eq(inv.count(CONSUMABLE_1), 1)
	assert_eq(inv.money, price)


func test_sell_consumables_one_unit_at_a_time() -> void:
	var p: ShopPanel = _panel()
	var inv: Inventory = Inventory.new()
	inv.add(CONSUMABLE_1, 3)
	p.bind(inv, NPC_ID)
	p.sell(CONSUMABLE_1)
	assert_eq(inv.count(CONSUMABLE_1), 2)


func test_equipped_items_are_not_sellable() -> void:
	var p: ShopPanel = _panel()
	var inv: Inventory = Inventory.new()
	inv.add(WEAPON_1)
	inv.equip(WEAPON_1)
	p.bind(inv, NPC_ID)

	assert_eq(inv.count(WEAPON_1), 0, "equipped item should have left the bag")
	assert_false(p.sell(WEAPON_1))
	assert_eq(inv.money, 0)
	assert_eq(inv.equipped_item_id("weapon"), WEAPON_1, "still equipped")


func test_equipped_items_do_not_appear_in_bag_rows_for_selling() -> void:
	var inv: Inventory = Inventory.new()
	inv.add(WEAPON_1)
	inv.equip(WEAPON_1)
	var ids: Array[String] = []
	for row: Dictionary in inv.slots():
		ids.append(String(row["item_id"]))
	assert_false(ids.has(WEAPON_1))


func test_buy_button_rows_are_disabled_when_unaffordable() -> void:
	var p: ShopPanel = _panel()
	var inv: Inventory = Inventory.new()  # money 0
	p.bind(inv, NPC_ID)
	assert_true(p.list_box.get_child_count() > 0)
	var any_disabled: bool = false
	for row: Node in p.list_box.get_children():
		var btn: Button = row.get_child(1)
		if btn.disabled:
			any_disabled = true
			assert_eq(btn.text, I18n.t("ui.shop.no_money"))
	assert_true(any_disabled)


func test_close_button_closes_and_emits_closed() -> void:
	var p: ShopPanel = _panel()
	p.bind(Inventory.new(), NPC_ID)
	p.open()
	watch_signals(p)
	p.close_button.pressed.emit()
	assert_false(p.is_open())
	assert_signal_emitted(p, "closed")
