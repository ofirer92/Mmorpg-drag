class_name ShopPanel
extends CanvasLayer
## T-0.12: buy/sell shop UI for an NPC's `stock` (docs/balance/npcs.yaml).
## Prices always come from RulesEconomy.buy_price/sell_price(item value) —
## never a literal price here. `bind(inventory, npc_id)` wires this to an
## Inventory + which NPC's stock to show; `open()/close()` show/hide it.
##
## Buying spends money then adds the item, refunding the money if add()
## fails (bag full). Selling removes the item then adds its sell price;
## consumables sell one unit at a time (remove() takes exactly one row-unit
## per call, same as using one from the inventory panel). Equipped items
## never show up in "Your Bag" — Inventory.slots() only ever returns bag
## rows, equip() already moved the item out of the bag.
##
## buy()/sell() are public so tests can call them directly without going
## through button presses; the per-row Buy/Sell buttons just call them.

signal closed

enum Tab { STOCK, BAG }

@onready var root: Control = $Root
@onready var title_label: Label = $Root/Window/Margin/Content/Header/TitleLabel
@onready var money_label: Label = $Root/Window/Margin/Content/Header/MoneyLabel
@onready var close_button: Button = $Root/Window/Margin/Content/Header/CloseButton
@onready var stock_tab_button: Button = $Root/Window/Margin/Content/TabsRow/StockTabButton
@onready var bag_tab_button: Button = $Root/Window/Margin/Content/TabsRow/BagTabButton
@onready var status_label: Label = $Root/Window/Margin/Content/StatusLabel
@onready var list_scroll: ScrollContainer = $Root/Window/Margin/Content/ListScroll
@onready var list_box: VBoxContainer = $Root/Window/Margin/Content/ListScroll/ListVBox

var _inventory: Inventory = null
var _npc_id: String = ""
var _tab: Tab = Tab.STOCK


func _ready() -> void:
	root.visible = false
	title_label.text = I18n.t("ui.shop.title")
	stock_tab_button.text = I18n.t("ui.shop.buy_tab")
	bag_tab_button.text = I18n.t("ui.shop.sell_tab")
	close_button.text = I18n.t("ui.shop.close")
	status_label.text = ""
	close_button.pressed.connect(close)
	stock_tab_button.toggle_mode = true
	bag_tab_button.toggle_mode = true
	stock_tab_button.pressed.connect(_on_stock_tab_pressed)
	bag_tab_button.pressed.connect(_on_bag_tab_pressed)


## Binds this panel to `inventory` and to `npc_id`'s stock (rebinding an
## already-bound panel disconnects the old inventory first).
func bind(inventory: Inventory, npc_id: String) -> void:
	if _inventory != null and _inventory.changed.is_connected(_on_inventory_changed):
		_inventory.changed.disconnect(_on_inventory_changed)
	if _inventory != null and _inventory.money_changed.is_connected(_on_money_changed):
		_inventory.money_changed.disconnect(_on_money_changed)
	_inventory = inventory
	_inventory.changed.connect(_on_inventory_changed)
	_inventory.money_changed.connect(_on_money_changed)
	_npc_id = npc_id
	_tab = Tab.STOCK
	status_label.text = ""
	_refresh()


func open() -> void:
	root.visible = true
	status_label.text = ""
	_refresh()


func close() -> void:
	root.visible = false
	closed.emit()


func is_open() -> bool:
	return root.visible


## Item ids sold by the currently-bound NPC (docs/balance/npcs.yaml `stock`).
func stock_ids() -> Array[String]:
	var def: Dictionary = RulesBalanceData.NPCS.get("npcs", {}).get(_npc_id, {})
	var out: Array[String] = []
	for id: Variant in def.get("stock", []):
		out.append(String(id))
	return out


## Buys one `item_id` at RulesEconomy.buy_price(value): spends the money,
## then adds the item to the bag, refunding the spend if the bag is full.
## Returns false (no state change beyond the refund) on any failure.
func buy(item_id: String) -> bool:
	if _inventory == null:
		return false
	var def: Dictionary = _item_def(item_id)
	if def.is_empty():
		return false
	var price: int = int(RulesEconomy.buy_price(float(def.get("value", 0))))
	if not _inventory.spend_money(price):
		return false
	if not _inventory.add(item_id, 1):
		_inventory.add_money(price)
		return false
	return true


## Sells one unit of `item_id` from the bag at RulesEconomy.sell_price(value).
## Returns false (no state change) if the bag doesn't hold it (this also
## rejects equipped items, since they're never in the bag rows).
func sell(item_id: String) -> bool:
	if _inventory == null:
		return false
	var def: Dictionary = _item_def(item_id)
	if def.is_empty():
		return false
	if not _inventory.remove(item_id, 1):
		return false
	var price: int = int(RulesEconomy.sell_price(float(def.get("value", 0))))
	_inventory.add_money(price)
	return true


func _on_stock_tab_pressed() -> void:
	_tab = Tab.STOCK
	status_label.text = ""
	_refresh()


func _on_bag_tab_pressed() -> void:
	_tab = Tab.BAG
	status_label.text = ""
	_refresh()


func _on_inventory_changed() -> void:
	_refresh()


func _on_money_changed(_money: int) -> void:
	_refresh()


static func _item_def(item_id: String) -> Dictionary:
	return RulesBalanceData.ITEMS.get("items", {}).get(item_id, {})


static func _item_name(item_id: String) -> String:
	var def: Dictionary = _item_def(item_id)
	return I18n.t(String(def.get("name_key", item_id))) if not def.is_empty() else item_id


func _refresh() -> void:
	money_label.text = "%s: %d" % [I18n.t("ui.currency.name"), _inventory.money if _inventory != null else 0]
	# The active tab shows as pressed (toggle look); both stay clickable.
	stock_tab_button.button_pressed = _tab == Tab.STOCK
	bag_tab_button.button_pressed = _tab == Tab.BAG
	list_scroll.visible = true
	for child: Node in list_box.get_children():
		child.queue_free()
	if _inventory == null:
		return
	if _tab == Tab.STOCK:
		_build_stock_rows()
	else:
		_build_bag_rows()


func _build_stock_rows() -> void:
	for item_id: String in stock_ids():
		var def: Dictionary = _item_def(item_id)
		if def.is_empty():
			continue
		var price: int = int(RulesEconomy.buy_price(float(def.get("value", 0))))
		var can_afford: bool = RulesEconomy.can_afford(float(_inventory.money), float(price), 1.0)
		var row: HBoxContainer = HBoxContainer.new()
		var name_label: Label = Label.new()
		name_label.text = "%s — %d" % [_item_name(item_id), price]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var buy_button: Button = Button.new()
		buy_button.custom_minimum_size = Vector2(96, 40)
		buy_button.text = I18n.t("ui.shop.buy") if can_afford else I18n.t("ui.shop.no_money")
		buy_button.disabled = not can_afford
		buy_button.pressed.connect(_on_buy_pressed.bind(item_id))
		row.add_child(buy_button)
		list_box.add_child(row)


func _build_bag_rows() -> void:
	for slot: Dictionary in _inventory.slots():
		var item_id: String = String(slot["item_id"])
		var count: int = int(slot["count"])
		var def: Dictionary = _item_def(item_id)
		if def.is_empty():
			continue
		var price: int = int(RulesEconomy.sell_price(float(def.get("value", 0))))
		var row: HBoxContainer = HBoxContainer.new()
		var name_label: Label = Label.new()
		name_label.text = "%s ×%d — %d" % [_item_name(item_id), count, price]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var sell_button: Button = Button.new()
		sell_button.custom_minimum_size = Vector2(96, 40)
		sell_button.text = I18n.t("ui.shop.sell")
		sell_button.pressed.connect(_on_sell_pressed.bind(item_id))
		row.add_child(sell_button)
		list_box.add_child(row)


func _on_buy_pressed(item_id: String) -> void:
	if buy(item_id):
		status_label.text = ""
	else:
		var def: Dictionary = _item_def(item_id)
		var price: int = int(RulesEconomy.buy_price(float(def.get("value", 0))))
		var can_afford: bool = _inventory != null and RulesEconomy.can_afford(float(_inventory.money), float(price), 1.0)
		status_label.text = I18n.t("ui.shop.no_money") if not can_afford else I18n.t("ui.shop.full")
	_refresh()


func _on_sell_pressed(item_id: String) -> void:
	sell(item_id)
	_refresh()
