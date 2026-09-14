# GENERATED from packages/shared-rules/src/economy.ts sha256:99d7b8203466a761 — DO NOT EDIT (run scripts/gen_rules.py)
class_name RulesEconomy

# Economy rules. RulesScript subset. Prices derive from item value; money drops from monsters.yaml.

# Shop buy price for an item of the given value.

static func buy_price(value: float) -> float:
	return max(1.0, floor(value * RulesConstants.BUY_PRICE_MULT))

# Shop sell-back price for an item of the given value (never above buy price).

static func sell_price(value: float) -> float:
	return max(0.0, floor(value * RulesConstants.SELL_PRICE_MULT))

# Money dropped by a monster for a roll in [0,1): uniform integer in [min, max].

static func roll_money(min: float, max: float, roll: float) -> float:
	var lo: float = max(0.0, floor(min))
	var hi: float = max(lo, floor(max))
	var span: float = hi - lo + 1.0
	return lo + min(span - 1.0, floor(max(0.0, roll) * span))

# Can the buyer afford count items at this price?

static func can_afford(money: float, price: float, count: float) -> bool:
	return money >= price * max(0.0, count)
