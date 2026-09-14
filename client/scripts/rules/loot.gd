# GENERATED from packages/shared-rules/src/loot.ts sha256:40d74d2c9ac540d8 — DO NOT EDIT (run scripts/gen_rules.py)
class_name RulesLoot

# Loot tables. RulesScript subset (see .claude/skills/shared-rules-authoring).
# Reads docs/balance/items.yaml via the _balance_data.ts loader — never a hardcoded item/weight here.

# Returns an item id, or "" for "nothing dropped". Deterministic for roll in [0,1):
# walks the table's weighted entries cumulatively (each entry claims weight/total of the
# [0,1) range in order) and returns the entry whose band contains roll.
# Unknown table_id, an empty table, or landing on a `null` entry all return "".

static func roll_loot(table_id: String, roll: float) -> String:
	if RulesBalanceData.ITEMS.loot_tables.get(table_id) == null:
		return ""
	var total: float = 0.0
	for entry in RulesBalanceData.ITEMS.loot_tables[table_id].entries:
		total += entry.weight
	if total <= 0.0:
		return ""
	var cumulative: float = 0.0
	for entry in RulesBalanceData.ITEMS.loot_tables[table_id].entries:
		cumulative += entry.weight
		if roll < cumulative / total:
			if entry.item == null:
				return ""
			return entry.item
	return ""

# Sell/vendor value of an item id, or 0 if the item is unknown.

static func loot_value(item_id: String) -> float:
	if RulesBalanceData.ITEMS.items.get(item_id) == null:
		return 0.0
	return RulesBalanceData.ITEMS.items[item_id].value
