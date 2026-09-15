# GENERATED from packages/shared-rules/src/_constants.ts sha256:f39d8b958ba1d908 — DO NOT EDIT (run scripts/gen_rules.py)
class_name RulesConstants

# Global game constants. RulesScript subset — transpiled to client/scripts/rules/constants.gd.
const TICK_RATE_HZ: float = 20.0
const TICK_MS: float = 50.0
const INTEREST_RADIUS_PX: float = 1200.0
# T-2.2: server-side range check for `loot_pickup` (docs/protocol.md § Loot) — never a client claim.
const PICKUP_RADIUS_PX: float = 48.0
const DEF_SCALE: float = 20.0
const CRIT_CHANCE: float = 0.05
const CRIT_MULT: float = 1.5
const MIN_DAMAGE: float = 1.0
const BUY_PRICE_MULT: float = 2.0
const SELL_PRICE_MULT: float = 0.5
