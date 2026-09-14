// Economy rules. RulesScript subset. Prices derive from item value; money drops from monsters.yaml.
import { BUY_PRICE_MULT, SELL_PRICE_MULT } from "./_constants.js";

// Shop buy price for an item of the given value.
export function buy_price(value: number): number {
  return Math.max(1, Math.floor(value * BUY_PRICE_MULT));
}

// Shop sell-back price for an item of the given value (never above buy price).
export function sell_price(value: number): number {
  return Math.max(0, Math.floor(value * SELL_PRICE_MULT));
}

// Money dropped by a monster for a roll in [0,1): uniform integer in [min, max].
export function roll_money(min: number, max: number, roll: number): number {
  const lo: number = Math.max(0, Math.floor(min));
  const hi: number = Math.max(lo, Math.floor(max));
  const span: number = hi - lo + 1;
  return lo + Math.min(span - 1, Math.floor(Math.max(0, roll) * span));
}

// Can the buyer afford count items at this price?
export function can_afford(money: number, price: number, count: number): boolean {
  return money >= price * Math.max(0, count);
}
