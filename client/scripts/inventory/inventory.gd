class_name Inventory
extends RefCounted
## T-0.11: basic bag + equipment + gear comparison. A pure data model — it
## knows nothing about Player/LocalServer/HUD; the caller wires it up (add
## loot, bind it to a UI panel, persist it via SaveGame). Item definitions
## and stats always come from RulesBalanceData.ITEMS (generated from
## docs/balance/items.yaml) — never a hardcoded number in here.
##
## Bag shape (T-1.7b): an ordered Array[Dictionary] of
## {item_id: String, count: int, affixes: Array[String]} rows, capped at
## `capacity` rows. A row is an ITEM INSTANCE: two rubber-stamp swords with
## different rolled affixes are different items, and the bag must not merge
## them. Consumables never roll affixes, so they still stack into a single
## row (add() increments its count); weapon/head/body items never stack —
## each unit occupies its own row, so two identical swords cost two rows.
## `affixes` is a list of ids from docs/balance/items.yaml `affixes`, rolled
## by whoever created the instance (LocalServer on a kill) — never here.
##
## Equipment shape: `equipped` maps a gear slot name ("weapon" | "head" |
## "body") to the equipped INSTANCE, {item_id: String, affixes: Array[String]},
## at most one per slot — the affixes have to travel with the item or
## equipping would silently strip them. Read it through equipped_item_id() /
## equipped_affixes_of() rather than indexing it directly. equip() always
## moves the previously-equipped item (if any) back into the bag, ignoring
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

## slot(String) -> the equipped INSTANCE {item_id: String, affixes: Array[String]}.
## T-1.7b changed this from a bare item_id so rolled affixes survive equipping;
## prefer equipped_item_id()/equipped_affixes_of() over indexing it.
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
## T-1.7b: an instance's real stats — the item's base stats plus its rolled
## affixes, through RulesAffixes (the same functions the server uses). Flat
## bonuses are summed first, then the percentage multipliers apply to the
## total, exactly as RulesAffixes.item_stat_with_affixes() defines it; the
## client never invents that formula.
static func item_stats_with_affixes(item_id: String, affixes: Array) -> Dictionary:
	var base: Dictionary = _item_stats(item_id)
	if affixes.is_empty():
		return base
	var out: Dictionary = {}
	for key: String in STAT_KEYS:
		var flat_total: float = 0.0
		var mult_total: float = 0.0
		for affix_id: Variant in affixes:
			flat_total += RulesAffixes.affix_stat(String(affix_id), key)
			mult_total += RulesAffixes.affix_mult(String(affix_id), key)
		out[key] = int(RulesAffixes.item_stat_with_affixes(float(base[key]), flat_total, mult_total))
	return out


## Normalises whatever a caller (or a hand-edited save) passed as an affix
## list into an Array[String] of ids that actually exist in items.yaml.
static func _clean_affixes(affixes: Variant) -> Array[String]:
	var out: Array[String] = []
	if not (affixes is Array):
		return out
	for entry: Variant in affixes:
		# str(), not String(): a save file can hold any Variant here, and String() has no
		# constructor for e.g. an int — that raises a runtime error instead of converting.
		var affix_id: String = str(entry)
		# affix_weight() is 0 for an unknown id — the cheapest existence check
		# RulesAffixes exposes.
		if affix_id != "" and RulesAffixes.affix_weight(affix_id) > 0.0 and not out.has(affix_id):
			out.append(affix_id)
	return out


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
	# Non-consumables: one row per unit. Affixless here — an instance with
	# rolled affixes comes in through add_instance().
	if respect_capacity and _rows.size() + count > capacity:
		return false
	for _i: int in range(count):
		_rows.append({"item_id": item_id, "count": 1, "affixes": [] as Array[String]})
	return true


## T-1.7b: adds ONE instance of `item_id` carrying `affixes` (ids from
## docs/balance/items.yaml). This is how a drop enters the bag — the affixes
## were rolled by the combat authority, never here. Unknown affix ids and
## duplicates are dropped. Consumables ignore affixes entirely and stack as
## usual. Returns false (and changes nothing) for an unknown item or a full bag.
func add_instance(item_id: String, affixes: Array) -> bool:
	if _item_def(item_id).is_empty():
		return false
	var clean: Array[String] = _clean_affixes(affixes)
	if clean.is_empty() or _is_consumable(item_id):
		return add(item_id, 1)
	if _rows.size() >= capacity:
		return false
	_rows.append({"item_id": item_id, "count": 1, "affixes": clean})
	changed.emit()
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


## T-1.7b: removes ONE unit from the bag row at `index` — the instance-safe
## counterpart of remove(item_id, 1), which can only ever take the OLDEST
## matching row and would happily sell the player's best roll out from under
## them. Returns false (no change) for an out-of-range index.
func remove_at(index: int) -> bool:
	if index < 0 or index >= _rows.size():
		return false
	_remove_row_unit(index)
	changed.emit()
	return true


## Total held across all bag rows (does not include an equipped unit).
func count(item_id: String) -> int:
	var total: int = 0
	for row: Dictionary in _rows:
		if row["item_id"] == item_id:
			total += int(row["count"])
	return total


## Bag contents in row order, e.g.
## [{"item_id": "expired_bandage", "count": 2, "affixes": []}]. Each row is one
## instance (see the header) — callers that need to act on a SPECIFIC instance
## address it by its index here, not by item_id.
func slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in _rows:
		out.append(
			{
				"item_id": row["item_id"],
				"count": row["count"],
				"affixes": _row_affixes(row).duplicate(),
			}
		)
	return out


static func _row_affixes(row: Dictionary) -> Array[String]:
	return _clean_affixes(row.get("affixes", []))


## The rolled affixes of the bag instance at `index`, or [] when out of range.
func affixes_at(index: int) -> Array[String]:
	if index < 0 or index >= _rows.size():
		return [] as Array[String]
	return _row_affixes(_rows[index])


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
	if slot.is_empty():
		return false
	for i: int in range(_rows.size()):
		if String(_rows[i]["item_id"]) == item_id:
			return equip_at(i)
	return false


## T-1.7b: equips the bag instance at `index`, so a UI listing several rolls of
## the same item can equip the exact one the player tapped — equip(item_id)
## can only ever reach the first. Returns false for an out-of-range index or a
## non-equipable item (e.g. a consumable).
func equip_at(index: int) -> bool:
	if index < 0 or index >= _rows.size():
		return false
	var row: Dictionary = _rows[index]
	var item_id: String = String(row["item_id"])
	var slot: String = _equip_slot_of(item_id)
	if slot.is_empty():
		return false
	var affixes: Array[String] = _row_affixes(row)
	_remove_row_unit(index)
	var previous: Dictionary = equipped.get(slot, {})
	equipped[slot] = {"item_id": item_id, "affixes": affixes}
	if not previous.is_empty():
		_add_instance_internal(
			String(previous.get("item_id", "")), _clean_affixes(previous.get("affixes", [])), false
		)
	equipped_changed.emit(slot, item_id)
	changed.emit()
	return true


## Removes one unit from the row at `index` (dropping the row when it empties).
## Mutates only — never emits `changed`; see _add_internal.
func _remove_row_unit(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var row: Dictionary = _rows[index]
	row["count"] = int(row["count"]) - 1
	if int(row["count"]) <= 0:
		_rows.remove_at(index)


## add_instance()'s mutate-only half, so equip()'s swap-back can put an affixed
## item back without a second `changed` emission (and without the capacity check
## — a swap-back must never lose the item).
func _add_instance_internal(item_id: String, affixes: Array[String], respect_capacity: bool) -> bool:
	if affixes.is_empty() or _is_consumable(item_id):
		return _add_internal(item_id, 1, respect_capacity)
	if respect_capacity and _rows.size() >= capacity:
		return false
	_rows.append({"item_id": item_id, "count": 1, "affixes": affixes.duplicate()})
	return true


## Moves the item equipped in `slot` back into the bag. Returns false (gear
## stays equipped) if `slot` is empty or the bag has no room for it.
func unequip(slot: String) -> bool:
	if not equipped.has(slot):
		return false
	var instance: Dictionary = equipped[slot]
	var item_id: String = String(instance.get("item_id", ""))
	if not _add_instance_internal(item_id, _clean_affixes(instance.get("affixes", [])), true):
		return false
	equipped.erase(slot)
	equipped_changed.emit(slot, "")
	changed.emit()
	return true


## Sum of {attack, defense, hp} across all currently equipped items.
func equipped_stats() -> Dictionary:
	var total: Dictionary = {"attack": 0, "defense": 0, "hp": 0}
	for slot: String in equipped.keys():
		var stats: Dictionary = item_stats_with_affixes(
			equipped_item_id(slot), equipped_affixes_of(slot)
		)
		for key: String in STAT_KEYS:
			total[key] = int(total[key]) + int(stats[key])
	return total


## The item id equipped in `slot`, or "" when the slot is empty.
func equipped_item_id(slot: String) -> String:
	var instance: Variant = equipped.get(slot)
	if not (instance is Dictionary):
		return ""
	return String((instance as Dictionary).get("item_id", ""))


## The rolled affixes of whatever is equipped in `slot`, or [] when empty.
func equipped_affixes_of(slot: String) -> Array[String]:
	var instance: Variant = equipped.get(slot)
	if not (instance is Dictionary):
		return [] as Array[String]
	return _clean_affixes((instance as Dictionary).get("affixes", []))


## Gear comparison: {attack, defense, hp} delta of `item_id` versus whatever
## is currently equipped in its slot (zero if that slot is empty, or if
## `item_id` isn't equipable). Unknown item id → all-zero delta.
func compare(item_id: String, affixes: Array = []) -> Dictionary:
	if _item_def(item_id).is_empty():
		return {"attack": 0, "defense": 0, "hp": 0}
	var slot: String = _equip_slot_of(item_id)
	var candidate: Dictionary = item_stats_with_affixes(item_id, affixes)
	var current: Dictionary = {"attack": 0, "defense": 0, "hp": 0}
	if not slot.is_empty() and equipped.has(slot):
		current = item_stats_with_affixes(equipped_item_id(slot), equipped_affixes_of(slot))
	var delta: Dictionary = {}
	for key: String in STAT_KEYS:
		delta[key] = int(candidate[key]) - int(current[key])
	return delta


## T-1.7b: compare() for the bag instance at `index` — the affix-correct way to
## compare, since two rows of the same item_id can have different rolls.
func compare_at(index: int) -> Dictionary:
	if index < 0 or index >= _rows.size():
		return {"attack": 0, "defense": 0, "hp": 0}
	return compare(String(_rows[index]["item_id"]), affixes_at(index))


## --- save/load ------------------------------------------------------------

## Plain-data snapshot for SaveGame. See SaveGame's header for the save shape.
func to_dict() -> Dictionary:
	var equipped_out: Dictionary = {}
	for slot: String in equipped.keys():
		equipped_out[slot] = {
			"item_id": equipped_item_id(slot),
			"affixes": equipped_affixes_of(slot),
		}
	return {"capacity": capacity, "slots": slots(), "equipped": equipped_out, "money": money}


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
					# Pre-T-1.7b saves have no "affixes" key — those rows load as
					# plain (affixless) instances rather than being discarded.
					_rows.append(
						{
							"item_id": item_id,
							"count": n,
							"affixes": _clean_affixes(entry.get("affixes", [])),
						}
					)
	var loaded_equipped: Variant = d.get("equipped", {})
	if loaded_equipped is Dictionary:
		for slot: String in loaded_equipped.keys():
			# Pre-T-1.7b saves stored a bare item_id String here; T-1.7b and later
			# store the {item_id, affixes} instance. Both must load.
			var raw: Variant = loaded_equipped[slot]
			var item_id: String = ""
			var affixes: Array[String] = []
			if raw is Dictionary:
				item_id = String((raw as Dictionary).get("item_id", ""))
				affixes = _clean_affixes((raw as Dictionary).get("affixes", []))
			else:
				item_id = String(raw)
			if EQUIP_SLOTS.has(slot) and not _item_def(item_id).is_empty():
				equipped[slot] = {"item_id": item_id, "affixes": affixes}
	money = max(0, int(d.get("money", 0)))
	changed.emit()
	money_changed.emit(money)
