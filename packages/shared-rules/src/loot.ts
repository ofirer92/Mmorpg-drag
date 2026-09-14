// Loot tables. RulesScript subset (see .claude/skills/shared-rules-authoring).
// Reads docs/balance/items.yaml via the _balance_data.ts loader — never a hardcoded item/weight here.
import { ITEMS } from "./_balance_data.js";

// Returns an item id, or "" for "nothing dropped". Deterministic for roll in [0,1):
// walks the table's weighted entries cumulatively (each entry claims weight/total of the
// [0,1) range in order) and returns the entry whose band contains roll.
// Unknown table_id, an empty table, or landing on a `null` entry all return "".
export function roll_loot(table_id: string, roll: number): string {
  if (ITEMS.loot_tables[table_id] == null) {
    return "";
  }
  let total: number = 0;
  for (const entry of ITEMS.loot_tables[table_id].entries) {
    total += entry.weight;
  }
  if (total <= 0) {
    return "";
  }
  let cumulative: number = 0;
  for (const entry of ITEMS.loot_tables[table_id].entries) {
    cumulative += entry.weight;
    if (roll < cumulative / total) {
      if (entry.item == null) {
        return "";
      }
      return entry.item;
    }
  }
  return "";
}

// Sell/vendor value of an item id, or 0 if the item is unknown.
export function loot_value(item_id: string): number {
  if (ITEMS.items[item_id] == null) {
    return 0;
  }
  return ITEMS.items[item_id].value;
}
