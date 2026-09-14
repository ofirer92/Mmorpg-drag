extends GutTest
## T-0.11 DoD: the bag panel renders slots, the comparison row shows the
## right deltas when an item is tapped, and the Equip button actually
## equips (through Inventory's own API — the panel never computes stats).

const WEAPON_1: String = "rubber_stamp_sword"  # attack 4
const WEAPON_2: String = "triplicate_dagger"  # attack 7
const HEAD_1: String = "ethics_committee_cap"
const CONSUMABLE_1: String = "expired_bandage"


func _panel() -> InventoryPanel:
	var packed: PackedScene = load("res://scenes/ui/inventory_panel.tscn")
	var node: InventoryPanel = packed.instantiate()
	add_child_autofree(node)
	return node


func test_starts_closed_and_open_button_toggles() -> void:
	var p: InventoryPanel = _panel()
	assert_false(p.is_open())
	p.open_button.pressed.emit()
	assert_true(p.is_open())
	p.open_button.pressed.emit()
	assert_false(p.is_open())


func test_close_button_closes_the_panel() -> void:
	var p: InventoryPanel = _panel()
	p.open()
	p.close_button.pressed.emit()
	assert_false(p.is_open())


func test_labels_come_from_i18n() -> void:
	var p: InventoryPanel = _panel()
	assert_eq(p.open_button.text, I18n.t("ui.inventory.open"))
	assert_eq(p.title_label.text, I18n.t("ui.inventory.title"))


func test_bind_renders_bag_rows() -> void:
	var p: InventoryPanel = _panel()
	var inv: Inventory = Inventory.new()
	inv.add(WEAPON_1)
	inv.add(CONSUMABLE_1, 3)
	p.bind(inv)
	assert_eq(p.bag_list.get_child_count(), 2)
	assert_false(p.empty_label.visible)


func test_bind_with_empty_inventory_shows_empty_label() -> void:
	var p: InventoryPanel = _panel()
	p.bind(Inventory.new())
	assert_eq(p.bag_list.get_child_count(), 0)
	assert_true(p.empty_label.visible)


func test_tapping_a_bag_item_shows_comparison_with_deltas() -> void:
	var p: InventoryPanel = _panel()
	var inv: Inventory = Inventory.new()
	inv.add(WEAPON_1)
	inv.equip(WEAPON_1)
	inv.add(WEAPON_2)
	p.bind(inv)
	(p.bag_list.get_child(0) as Button).pressed.emit()
	assert_true(p.comparison_panel.visible)
	assert_true(p.attack_delta_label.text.contains("+3"), p.attack_delta_label.text)


func test_comparison_hidden_before_any_selection() -> void:
	var p: InventoryPanel = _panel()
	p.bind(Inventory.new())
	assert_false(p.comparison_panel.visible)


func test_equip_button_equips_the_selected_item() -> void:
	var p: InventoryPanel = _panel()
	var inv: Inventory = Inventory.new()
	inv.add(WEAPON_1)
	p.bind(inv)
	(p.bag_list.get_child(0) as Button).pressed.emit()
	assert_eq(p.action_button.text, I18n.t("ui.inventory.equip"))
	p.action_button.pressed.emit()
	assert_eq(String(inv.equipped.get("weapon", "")), WEAPON_1)
	assert_eq(inv.count(WEAPON_1), 0)


func test_use_button_removes_a_consumable_and_emits_used() -> void:
	var p: InventoryPanel = _panel()
	var inv: Inventory = Inventory.new()
	inv.add(CONSUMABLE_1, 2)
	p.bind(inv)
	(p.bag_list.get_child(0) as Button).pressed.emit()
	assert_eq(p.action_button.text, I18n.t("ui.inventory.use"))
	watch_signals(p)
	p.action_button.pressed.emit()
	assert_signal_emitted_with_parameters(p, "used", [CONSUMABLE_1])
	assert_eq(inv.count(CONSUMABLE_1), 1)


func test_equipped_row_shows_dash_when_slot_is_empty() -> void:
	var p: InventoryPanel = _panel()
	p.bind(Inventory.new())
	assert_true(p.weapon_button.disabled)


func test_equipped_row_shows_item_and_enables_unequip() -> void:
	var p: InventoryPanel = _panel()
	var inv: Inventory = Inventory.new()
	inv.add(HEAD_1)
	inv.equip(HEAD_1)
	p.bind(inv)
	assert_false(p.head_button.disabled)
	p.head_button.pressed.emit()
	assert_eq(String(inv.equipped.get("head", "")), "")
	assert_eq(inv.count(HEAD_1), 1)


func test_bag_list_refreshes_when_inventory_changes_after_bind() -> void:
	var p: InventoryPanel = _panel()
	var inv: Inventory = Inventory.new()
	p.bind(inv)
	assert_eq(p.bag_list.get_child_count(), 0)
	inv.add(WEAPON_1)
	assert_eq(p.bag_list.get_child_count(), 1)
