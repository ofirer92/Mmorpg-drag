---
name: shared-rules-authoring
description: How to write pure game-rule functions in packages/shared-rules that gen_rules.py can transpile to GDScript — the allowed TypeScript subset, how the translator works, and the damage() example. Load before editing packages/shared-rules/src.
---
# Shared-rules authoring

Every game number and formula lives ONCE in `packages/shared-rules/src/*.ts` and is transpiled to `client/scripts/rules/*.gd` by `scripts/gen_rules.py`. Files whose name starts with `_` or that are named `protocol.ts` / `index.ts` are handled specially (see below).

## Allowed subset ("RulesScript")
- Top-level `export const NAME: number = ...;` (constants) and `export function name(a: number, b: number): number { ... }`.
- Types: `number`, `boolean`, `string`, and plain object params typed by an exported `interface` with only those field types.
- Statements: `const`/`let` with type annotation, `if/else`, `for (let i = 0; i < n; i++)`, `return`, arithmetic, comparisons, `&&`/`||`/`!`.
- Calls to `Math.floor`, `Math.ceil`, `Math.round`, `Math.max`, `Math.min`, `Math.abs`, `Math.pow`, `Math.sqrt`, and to other functions in the same file or imported from `./_yaml` loaders.
- NOT allowed: classes, closures/arrow functions, arrays of objects, `Map`, string templates, `switch`, try/catch, ternaries with side effects, destructuring, spread, async, `this`.
- Randomness: never call `Math.random`. Take `roll: number` (0..1) as a parameter so both sides are deterministic and testable.

## How gen_rules.py translates
Line-oriented regex translation (not a full parser). It maps:
`export function f(a: number): number {` → `static func f(a: float) -> float:`
`const x: number = ...;` → `var x: float = ...`
`Math.floor(x)` → `floori(x)` (int) / `floor` etc.; `Math.pow(a,b)` → `pow(a,b)`; `&&`→`and`, `||`→`or`, `!x`→`not x`; `//` comments kept; braces → indentation.
Each output file starts with `# GENERATED from packages/shared-rules/src/<file> sha256:<hash> — DO NOT EDIT`.
If your function doesn't survive translation, simplify it — don't extend the translator without an ADR.

## Example
```ts
// src/combat.ts
import { CRIT_MULT } from "./_constants";
export interface Combatant { attack: number; defense: number; level: number; }
export function damage(attacker: Combatant, defender: Combatant, power: number, roll: number): number {
  const raw: number = attacker.attack * power - defender.defense * 0.5;
  const base: number = Math.max(1, Math.floor(raw));
  if (roll < 0.05) {
    return Math.floor(base * CRIT_MULT);
  }
  return base;
}
```
Test in `packages/shared-rules/tests/combat.test.ts` (Vitest) AND in `client/tests/test_rules_combat.gd` (GUT) with the same fixture values, asserting the same numbers. `scripts/check.sh` runs both.

## Balance numbers
Numbers come from `docs/balance/*.yaml`. `gen_rules.py` also emits `client/scripts/rules/balance_data.gd` (a const Dictionary) and `packages/shared-rules/src/_balance_data.ts` from the YAML, so both sides read identical data. Never type a balance number into .ts or .gd by hand.
