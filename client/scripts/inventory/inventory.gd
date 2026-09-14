class_name Inventory
extends RefCounted
## T-0.11: basic bag + equipment + gear comparison. A pure data model — it
## knows nothing about Player/LocalServer/HUD; the caller wires it up (add
## loot, bind it to a UI panel, persist it via SaveGame). Item definitions
## and stats always come from RulesBalanceData.ITEMS (generated from
## docs/balance/items.yaml) — never a hardcoded number in here.
##
## Bag shape: an ordered Array[Dictionary] of {item_id: String, count: int}
## rows, capped at `capacity` rows. Consumables stack into a single existing
## row (add() increments its count); weapon/head/body items never stack —
## each unit occupies its own row, so two identical swords cost two rows.
##
## Equipment shape: `equipped` maps a gear slot name ("weapon" | "head" |
## "body") to an item_id, at most one item per slot. equip() always moves
## the previously-equipped item (if any) back into the bag, ignoring
## capacity for that specific swap-back, so equipping never loses an item.
##
## Unknown item ids are always rejected (false / no-op / all-zero dict) —
## never a crash, since this data can come from a hand-edited save file.
##
## T-0.12: `money` is the shop currency; add_money/spend_money keep it >= 0
## always. ShopPanel is the only caller that mutates it via buy()/sell() —
## everyone else (LocalServer.money_dropped) only ever calls add_money().

signal changed
signal equipped_changed(slot: String, item_id: String)
## T-0.12: the shop currency ("אישורי החזר" — ui.currency.name). Emitted by
## add_money/spend_money whenever the balance actually changes.
signal money_changed(money: int)

const EQUIP_SLOTS: Array[String] = ["weapon", "head", "body"]
const STAT_KEYS: Array[String] = ["attack", "defense", "hp"]

@export var capacity: int = 20

## slot(String) -> item_id(String) currently equipped in that slot.
var equipped: Dictionary = {}

## T-0.12: shop currency. Never goes negative — see add_money/spend_money.
## Never a hardcoded price here; RulesEconomy computes buy/sell prices.
var money: int = 0

var _rows: Array[Dictionary] = []  # [{item_id: String, count: int}, ...]


func _init(capacity_override: int = 20) -> void:
	capacity = capacity_override


## --- item def helpers ------------------------------------------------------

static func _item_def(item_id: String) -> Dictionary:
	if item_id.is_empty():
		return {}
	var items: Dictionary = RulesBalanceData.ITEMS.get("items", {})
	var def: Variant = items.get(item_id)
	return def if def is Dictionary else {}


static func _is_consumable(item_id: String) -> bool:
	return String(_item_def(item_id).get("slot", "")) == "consumable"


static func _equip_slot_of(item_id: String) -> String:
	var slot: String = String(_item_def(item_id).get("slot", ""))
	return slot if EQUIP_SLOTS.has(slot) else ""


static func _item_stats(item_id: String) -> Dictionary:
	var out: Dictionary = {"attack": 0, "defense": 0, "hp": 0}
	var stats: Variant = _item_def(item_id).get("stats")
	if stats is Dictionary:
		for key: String in STAT_KEYS:
			out[key] = int(stats.get(key, 0))
	return out


## --- bag --------------------------------------------------------------------

## Adds `count` of `item_id` to the bag. Consumables stack into an existing
## row; any other item type takes one row per unit. Returns false (no state
## change) for an unknown item id, a non-positive count, or when the bag
## doesn't have enough free rows.
func add(item_id: String, count: int = 1) -> bool:
	if count <= 0 or _item_def(item_id).is_empty():
		return false
	if not _add_internal(item_id, count, true):
		return false
	changed.emit()
	return true


## Mutates the bag only — never emits `changed` itself, so callers that
## perform several mutations per public call (equip's swap-back, add()) can
## batch them into a single `changed` emission.
func _add_internal(item_id: String, count: int, respect_capacity: bool) -> bool:
	if _is_consumable(item_id):
		for row: Dictionary in _rows:
			if row["item_id"] == item_id:
				row["count"] = int(row["count"]) + count
				return true
		if respect_capacity and _rows.size() >= capacity:
			return false
		_rows.append({"item_id": item_id, "count": count})
		return true
	# Non-consumables: one row per unit.
	if respect_capacity and _rows.size() + count > capacity:
		return false
	for _i: int in range(count):
		_rows.append({"item_id": item_id, "count": 1})
	return true


## Removes `count` of `item_id` (oldest rows first). Returns false — and
## changes nothing — if the bag doesn't hold at least `count` of it.
func remove(item_id: String, count: int = 1) -> bool:
	if count <= 0 or self.count(item_id) < count:
		return false
	_remove_internal(item_id, count)
	changed.emit()
	return true


## Mutates the bag only (caller must have already checked enough is held) —
## never emits `changed` itself; see _add_internal.
func _remove_internal(item_id: String, count: int) -> void:
	var remaining: int = count
	var i: int = 0
	while i < _rows.size() and remaining > 0:
		var row: Dictionary = _rows[i]
		if row["item_id"] != item_id:
			i += 1
			continue
		var take: int = min(remaining, int(row["count"]))
		row["count"] = int(row["count"]) - take
		remaining -= take
		if int(row["count"]) <= 0:
			_rows.remove_at(i)
		else:
			i += 1


## Total held across all bag rows (does not include an equipped unit).
func count(item_id: String) -> int:
	var total: int = 0
	for row: Dictionary in _rows:
		if row["item_id"] == item_id:
			total += int(row["count"])
	return total


## Bag contents in row order, e.g. [{"item_id": "expired_bandage", "count": 2}].
func slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in _rows:
		out.append({"item_id": row["item_id"], "count": row["count"]})
	return out


## --- money --------------------------------------------------------------------

## Adds `amount` (e.g. LocalServer's money_dropped, or a shop refund) to the
## balance. Non-positive amounts are a no-op — money never moves backwards
## through add_money (use spend_money for that).
func add_money(amount: int) -> void:
	if amount <= 0:
		return
	money += amount
	money_changed.emit(money)


## Spends `amount`, never taking the balance below zero. Returns false (no
## state change) if `amount` is non-positive or exceeds the current balance.
func spend_money(amount: int) -> bool:
	if amount <= 0 or amount > money:
		return false
	money -= amount
	money_changed.emit(money)
	return true


## --- equipment ----------------------------------------------------------------

## Moves one unit of `item_id` from the bag into its gear slot, swapping any
## previously-equipped item back into the bag (that swap-back always
## succeeds, ignoring capacity, so equipping never loses an item). Returns
## false for an unknown item id, a non-equipable item (e.g. a consumable),
## or an item the bag doesn't hold.
func equip(item_id: String) -> bool:
	var slot: String = _equip_slot_of(item_id)
	if slot.is_empty() or count(item_id) <= 0:
		return false
	_remove_internal(item_id, 1)
	var previous: String = String(equipped.get(slot, ""))
	equipped[slot] = item_id
	if not previous.is_empty():
		_add_internal(previous, 1, false)
	equipped_changed.emit(slot, item_id)
	changed.emit()
	return true


## Moves the item equipped in `slot` back into the bag. Returns false (gear
## stays equipped) if `slot` is empty or the bag has no room for it.
func unequip(slot: String) -> bool:
	if not equipped.has(slot):
		return false
	var item_id: String = String(equipped[slot])
	if not _add_internal(item_id, 1, true):
		return false
	equipped.erase(slot)
	equipped_changed.emit(slot, "")
	changed.emit()
	return true


## Sum of {attack, defense, hp} across all currently equipped items.
func equipped_stats() -> Dictionary:
	var total: Dictionary = {"attack": 0, "defense": 0, "hp": 0}
	for slot: String in equipped.keys():
		var stats: Dictionary = _item_stats(String(equipped[slot]))
		for key: String in STAT_KEYS:
			total[key] = int(total[key]) + int(stats[key])
	return total


## Gear comparison: {attack, defense, hp} delta of `item_id` versus whatever
## is currently equipped in its slot (zero if that slot is empty, or if
## `item_id` isn't equipable). Unknown item id → all-zero delta.
func compare(item_id: String) -> Dictionary:
	if _item_def(item_id).is_empty():
		return {"attack": 0, "defense": 0, "hp": 0}
	var slot: String = _equip_slot_of(item_id)
	var candidate: Dictionary = _item_stats(item_id)
	var current: Dictionary = {"attack": 0, "defense": 0, "hp": 0}
	if not slot.is_empty() and equipped.has(slot):
		current = _item_stats(String(equipped[slot]))
	var delta: Dictionary = {}
	for key: String in STAT_KEYS:
		delta[key] = int(candidate[key]) - int(current[key])
	return delta


## --- save/load ------------------------------------------------------------

## Plain-data snapshot for SaveGame. See SaveGame's header for the save shape.
func to_dict() -> Dictionary:
	return {"capacity": capacity, "slots": slots(), "equipped": equipped.duplicate(), "money": money}


## Restores state written by to_dict(). Unknown item ids and malformed
## entries are silently skipped — never a crash.
func from_dict(d: Dictionary) -> void:
	_rows.clear()
	equipped.clear()
	capacity = max(1, int(d.get("capacity", capacity)))
	var loaded_slots: Variant = d.get("slots", [])
	if loaded_slots is Array:
		for entry: Variant in loaded_slots:
			if entry is Dictionary and entry.has("item_id") and entry.has("count"):
				var item_id: String = String(entry["item_id"])
				var n: int = int(entry["count"])
				if n > 0 and not _item_def(item_id).is_empty():
					_rows.append({"item_id": item_id, "count": n})
	var loaded_equipped: Variant = d.get("equipped", {})
	if loaded_equipped is Dictionary:
		for slot: String in loaded_equipped.keys():
			var item_id: String = String(loaded_equipped[slot])
			if EQUIP_SLOTS.has(slot) and not _item_def(item_id).is_empty():
				equipped[slot] = item_id
	money = max(0, int(d.get("money", 0)))
	changed.emit()
	money_changed.emit(money)
