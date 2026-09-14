import { describe, expect, it } from "vitest";
import { BUY_PRICE_MULT, SELL_PRICE_MULT } from "../src/_constants.js";
import { ITEMS, MONSTERS } from "../src/_balance_data.js";
import { buy_price, can_afford, roll_money, sell_price } from "../src/economy.js";

describe("economy", () => {
  it("buy price is value × mult, at least 1; sell never exceeds buy", () => {
    for (const it of Object.values(ITEMS.items)) {
      expect(buy_price(it.value)).toBe(Math.max(1, Math.floor(it.value * BUY_PRICE_MULT)));
      expect(sell_price(it.value)).toBe(Math.floor(it.value * SELL_PRICE_MULT));
      expect(sell_price(it.value)).toBeLessThanOrEqual(buy_price(it.value));
    }
    expect(buy_price(0)).toBe(1);
    expect(sell_price(0)).toBe(0);
  });
  it("roll_money covers [min, max] inclusive and never leaves it", () => {
    expect(roll_money(3, 7, 0)).toBe(3);
    expect(roll_money(3, 7, 0.999999)).toBe(7);
    expect(roll_money(3, 7, 0.5)).toBe(5);
    expect(roll_money(7, 3, 0.5)).toBe(7); // max < min → clamps to min
    expect(roll_money(-2, 2, 0)).toBe(0);
    const seen = new Set<number>();
    for (let i = 0; i < 1000; i++) seen.add(roll_money(1, 4, i / 1000));
    expect([...seen].sort()).toEqual([1, 2, 3, 4]);
  });
  it("every monster has a money range", () => {
    for (const m of Object.values(MONSTERS.monsters)) {
      expect(m.money.min).toBeGreaterThanOrEqual(0);
      expect(m.money.max).toBeGreaterThanOrEqual(m.money.min);
    }
  });
  it("can_afford", () => {
    expect(can_afford(10, 5, 2)).toBe(true);
    expect(can_afford(9, 5, 2)).toBe(false);
    expect(can_afford(0, 5, 0)).toBe(true);
  });
});
