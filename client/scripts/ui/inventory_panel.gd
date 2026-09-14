class_name InventoryPanel
extends CanvasLayer
## T-0.11: bag + gear-comparison UI. `bind(inventory)` wires this to an
## Inventory instance and only ever DISPLAYS/mutates it through Inventory's
## own public API (add/remove/equip/unequip/compare) — it never computes
## item stats or effects itself (those come from RulesBalanceData via
## Inventory). Using a consumable only removes it from the bag and emits
## `used`; applying the actual effect (e.g. healing) is the lead's job,
## same "client never computes damage/xp" rule as everywhere else.
##
## Mobile-first: the window uses fractional anchors (not fixed pixels) so it
## scales from 390×844 up to 1920×1080. See client/tests/test_inventory_panel.gd.

signal used(item_id: String)

const COLOR_POSITIVE: Color = Color(0.42, 0.85, 0.45)
const COLOR_NEGATIVE: Color = Color(0.92, 0.4, 0.4)
const COLOR_NEUTRAL: Color = Color(0.8, 0.8, 0.8)
const EQUIP_SLOTS: Array[String] = ["weapon", "head", "body"]

@onready var open_button: Button = $OpenButton
@onready var root: Control = $Root
@onready var title_label: Label = $Root/Window/Margin/Content/Header/TitleLabel
@onready var close_button: Button = $Root/Window/Margin/Content/Header/CloseButton
@onready var weapon_button: Button = $Root/Window/Margin/Content/EquippedRow/WeaponButton
@onready var head_button: Button = $Root/Window/Margin/Content/EquippedRow/HeadButton
@onready var body_button: Button = $Root/Window/Margin/Content/EquippedRow/BodyButton
@onready var bag_list: VBoxContainer = $Root/Window/Margin/Content/BagScroll/BagList
@onready var empty_label: Label = $Root/Window/Margin/Content/EmptyLabel
@onready var comparison_panel: VBoxContainer = $Root/Window/Margin/Content/ComparisonPanel
@onready var attack_delta_label: Label = $Root/Window/Margin/Content/ComparisonPanel/AttackDeltaLabel
@onready var defense_delta_label: Label = $Root/Window/Margin/Content/ComparisonPanel/DefenseDeltaLabel
@onready var hp_delta_label: Label = $Root/Window/Margin/Content/ComparisonPanel/HpDeltaLabel
@onready var action_button: Button = $Root/Window/Margin/Content/ComparisonPanel/ActionButton

var _inventory: Inventory = null
var _selected_item_id: String = ""
var _equip_buttons: Dictionary = {}  # slot(String) -> Button


func _ready() -> void:
	_equip_buttons = {"weapon": weapon_button, "head": head_button, "body": body_button}
	root.visible = false
	open_button.text = I18n.t("ui.inventory.open")
	title_label.text = I18n.t("ui.inventory.title")
	empty_label.text = I18n.t("ui.inventory.empty")
	comparison_panel.visible = false

	open_button.pressed.connect(_on_open_pressed)
	close_button.pressed.connect(close)
	action_button.pressed.connect(_on_action_pressed)
	for slot: String in EQUIP_SLOTS:
		var btn: Button = _equip_buttons[slot]
		btn.pressed.connect(_on_equip_slot_pressed.bind(slot))

	_render_equipped_row()


## Binds this panel to `inventory` and does one initial render from its
## current state (rebinding an already-bound panel disconnects the old one).
func bind(inventory: Inventory) -> void:
	if _inventory != null and _inventory.changed.is_connected(_on_inventory_changed):
		_inventory.changed.disconnect(_on_inventory_changed)
	_inventory = inventory
	_inventory.changed.connect(_on_inventory_changed)
	_selected_item_id = ""
	_refresh()


func is_open() -> bool:
	return root.visible


func open() -> void:
	root.visible = true


func close() -> void:
	root.visible = false


func _on_open_pressed() -> void:
	root.visible = not root.visible


func _on_inventory_changed() -> void:
	_refresh()


func _refresh() -> void:
	_render_equipped_row()
	_rebuild_bag_list()
	if _inventory != null and _selected_item_id != "" and _inventory.count(_selected_item_id) <= 0:
		_selected_item_id = ""
	_update_comparison()


static func _item_name(item_id: String) -> String:
	if item_id.is_empty():
		return "—"
	var def: Dictionary = RulesBalanceData.ITEMS.get("items", {}).get(item_id, {})
	if def.is_empty():
		return item_id
	return I18n.t(String(def.get("name_key", item_id)))


static func _item_slot(item_id: String) -> String:
	return String(RulesBalanceData.ITEMS.get("items", {}).get(item_id, {}).get("slot", ""))


func _render_equipped_row() -> void:
	for slot: String in EQUIP_SLOTS:
		var item_id: String = String(_inventory.equipped.get(slot, "")) if _inventory != null else ""
		var btn: Button = _equip_buttons[slot]
		var line: String = "%s: %s" % [I18n.t("ui.inventory.slot.%s" % slot), _item_name(item_id)]
		if not item_id.is_empty():
			line += " (%s)" % I18n.t("ui.inventory.unequip")
		btn.text = line
		btn.disabled = item_id.is_empty()


func _on_equip_slot_pressed(slot: String) -> void:
	if _inventory == null:
		return
	_inventory.unequip(slot)


func _rebuild_bag_list() -> void:
	for child: Node in bag_list.get_children():
		child.queue_free()
	if _inventory == null:
		empty_label.visible = true
		return
	var rows: Array[Dictionary] = _inventory.slots()
	empty_label.visible = rows.is_empty()
	for row: Dictionary in rows:
		var item_id: String = String(row["item_id"])
		var count: int = int(row["count"])
		var btn: Button = Button.new()
		btn.text = "%s ×%d" % [_item_name(item_id), count]
		btn.custom_minimum_size = Vector2(0, 40)
		btn.pressed.connect(_on_bag_item_pressed.bind(item_id))
		bag_list.add_child(btn)


func _on_bag_item_pressed(item_id: String) -> void:
	_selected_item_id = item_id
	_update_comparison()


func _update_comparison() -> void:
	if _inventory == null or _selected_item_id.is_empty():
		comparison_panel.visible = false
		return
	comparison_panel.visible = true
	var delta: Dictionary = _inventory.compare(_selected_item_id)
	_set_delta_label(attack_delta_label, "ui.inventory.stat.attack", int(delta.get("attack", 0)))
	_set_delta_label(defense_delta_label, "ui.inventory.stat.defense", int(delta.get("defense", 0)))
	_set_delta_label(hp_delta_label, "ui.inventory.stat.hp", int(delta.get("hp", 0)))
	var is_consumable: bool = _item_slot(_selected_item_id) == "consumable"
	action_button.text = I18n.t("ui.inventory.use" if is_consumable else "ui.inventory.equip")


func _set_delta_label(label: Label, stat_key: String, value: int) -> void:
	var sign_str: String = "+" if value >= 0 else ""
	label.text = "%s: %s%d" % [I18n.t(stat_key), sign_str, value]
	if value > 0:
		label.add_theme_color_override("font_color", COLOR_POSITIVE)
	elif value < 0:
		label.add_theme_color_override("font_color", COLOR_NEGATIVE)
	else:
		label.add_theme_color_override("font_color", COLOR_NEUTRAL)


func _on_action_pressed() -> void:
	if _inventory == null or _selected_item_id.is_empty():
		return
	var item_id: String = _selected_item_id
	if _item_slot(item_id) == "consumable":
		if _inventory.remove(item_id, 1):
			used.emit(item_id)
	else:
		_inventory.equip(item_id)
