// Global game constants. RulesScript subset — transpiled to client/scripts/rules/constants.gd.
export const TICK_RATE_HZ: number = 20;
export const TICK_MS: number = 50;
export const INTEREST_RADIUS_PX: number = 1200;
// T-2.2: server-side range check for `loot_pickup` (docs/protocol.md § Loot) — never a client claim.
export const PICKUP_RADIUS_PX: number = 48;
export const DEF_SCALE: number = 20;
export const CRIT_CHANCE: number = 0.05;
export const CRIT_MULT: number = 1.5;
export const MIN_DAMAGE: number = 1;
export const BUY_PRICE_MULT: number = 2;
export const SELL_PRICE_MULT: number = 0.5;
