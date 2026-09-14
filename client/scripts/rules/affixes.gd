# GENERATED from packages/shared-rules/src/affixes.ts sha256:dfe1ffb1a56e8f9a — DO NOT EDIT (run scripts/gen_rules.py)
class_name RulesAffixes

# Item affixes (T-1.7). RulesScript subset (see .claude/skills/shared-rules-authoring).
# Numbers come from docs/balance/items.yaml (affixes / affix_order / affix_slots) — never
# hardcoded here. affix_order lists every affixes key exactly once, in roll order, because
# RulesScript can't iterate a Dictionary's keys directly (only `for (const x of ARR)` over
# arrays — see ADR-012), so the roll order lives explicitly in the YAML.
#
# Caller's job: "no duplicate affix on one item". Each roll_affix_id() call returns a single id;
# if a caller rolls affix_count() ids for an item and gets a repeat, it re-rolls that slot with a
# fresh roll value. This file stays pure/stateless (no loop-until-unique here) so it stays
# deterministic and testable per roll.

# Sell-table/roll weight of an affix id, or 0 if the id is unknown.

static func affix_weight(affix_id: String) -> float:
	if RulesBalanceData.ITEMS.affixes.get(affix_id) == null:
		return 0.0
	return RulesBalanceData.ITEMS.affixes[affix_id].weight

# True when an affix is allowed to roll on the given item rarity.

static func affix_allows_rarity(affix_id: String, rarity: String) -> bool:
	if RulesBalanceData.ITEMS.affixes.get(affix_id) == null:
		return false
	for r in RulesBalanceData.ITEMS.affixes[affix_id].rarities:
		if r == rarity:
			return true
	return false

# Number of affixes in docs/balance/items.yaml `affixes` allowed for the given rarity, in YAML
# (affix_order) order. Unknown rarity → 0.

static func affix_pool_size(rarity: String) -> float:
	var count: float = 0.0
	for id in RulesBalanceData.ITEMS.affix_order:
		if affix_allows_rarity(id, rarity):
			count += 1.0
	return count

# How many affixes an item of this rarity gets: a uniform integer in the rarity's
# affix_slots [min, max] (inclusive) for a roll in [0,1). Unknown rarity → 0.

static func affix_count(rarity: String, roll: float) -> float:
	if RulesBalanceData.ITEMS.affix_slots.get(rarity) == null:
		return 0.0
	var lo: float = RulesBalanceData.ITEMS.affix_slots[rarity].min
	var hi: float = max(lo, RulesBalanceData.ITEMS.affix_slots[rarity].max)
	var span: float = hi - lo + 1.0
	return lo + min(span - 1.0, floor(max(0.0, roll) * span))

# Weighted pick of one affix id within the rarity's allowed pool, for a roll in [0,1). Walks
# affix_order cumulatively (each allowed entry claims weight/total of the [0,1) range in order),
# same shape as roll_loot() in loot.ts. "" when the pool is empty (unknown rarity, or a rarity
# with no allowed affixes).

static func roll_affix_id(rarity: String, roll: float) -> String:
	var total: float = 0.0
	for id in RulesBalanceData.ITEMS.affix_order:
		if affix_allows_rarity(id, rarity):
			total += affix_weight(id)
	if total <= 0.0:
		return ""
	var cumulative: float = 0.0
	for id in RulesBalanceData.ITEMS.affix_order:
		if affix_allows_rarity(id, rarity):
			cumulative += affix_weight(id)
			if roll < cumulative / total:
				return id
	return ""

# Flat stat bonus (attack/defense/hp) an affix grants, or 0 for an unknown affix id or stat name.

static func affix_stat(affix_id: String, stat: String) -> float:
	if RulesBalanceData.ITEMS.affixes.get(affix_id) == null:
		return 0.0
	if stat == "attack":
		return RulesBalanceData.ITEMS.affixes[affix_id].stats.attack
	if stat == "defense":
		return RulesBalanceData.ITEMS.affixes[affix_id].stats.defense
	if stat == "hp":
		return RulesBalanceData.ITEMS.affixes[affix_id].stats.hp
	return 0.0

# Percentage stat multiplier (attack/defense/hp, 0..0.5) an affix grants, or 0 for an unknown
# affix id or stat name.

static func affix_mult(affix_id: String, stat: String) -> float:
	if RulesBalanceData.ITEMS.affixes.get(affix_id) == null:
		return 0.0
	if stat == "attack":
		return RulesBalanceData.ITEMS.affixes[affix_id].mult.attack
	if stat == "defense":
		return RulesBalanceData.ITEMS.affixes[affix_id].mult.defense
	if stat == "hp":
		return RulesBalanceData.ITEMS.affixes[affix_id].mult.hp
	return 0.0

# Final stat value after affixes: base plus the sum of all rolled affixes' flat bonuses, then
# scaled by 1 + the sum of all rolled affixes' percentage multipliers, floored.

static func item_stat_with_affixes(base: float, flat_total: float, mult_total: float) -> float:
	return floor((base + flat_total) * (1.0 + mult_total))
