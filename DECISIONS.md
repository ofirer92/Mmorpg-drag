# DECISIONS — Architecture Decision Records

פורמט: `## ADR-NNN — title` / Date / Status / Context / Decision / Consequences.
כל שינוי ב-docker-compose.yml, .github/, .claude/, כל ספרייה חדשה, וכל שינוי בהחלטות סעיף 1 של WORKPLAN — דורש ADR כאן.

---

## ADR-001 — Client: Godot 4.3+ / GDScript

Date: 2026-09-14 · Status: accepted
Context: need 2D platformer, mobile+desktop+web from one codebase, text-based source (AI-friendly).
Decision: Godot 4.3+, GDScript with static typing everywhere.
Consequences: GUT for tests; export presets per platform; `client/scripts/rules/` is generated, never hand-edited.

## ADR-002 — Server: Node.js 22 + TypeScript (strict)

Date: 2026-09-14 · Status: accepted
Context: fast iteration, strong AI support, rich ecosystem.
Decision: Node 22, TS strict, no `any`, Zod on every external input. Vitest for tests. pnpm workspaces.
Consequences: server and shared-rules share one toolchain.

## ADR-003 — Network: WebSocket (ws), JSON in phases 2–3, MessagePack in phase 4

Date: 2026-09-14 · Status: accepted
Context: debuggability first, efficiency later.
Decision: `ws` library; JSON envelope `{t: string, ...}`; migrate to MessagePack in T-4.3.
Consequences: docs/protocol.md is the source of truth; `check_protocol_sync.sh` enforces parity.

## ADR-004 — Persistence: PostgreSQL 16 + Redis 7, Drizzle ORM

Date: 2026-09-14 · Status: accepted
Context: GDD requirements; durable state + real-time state/pub-sub.
Decision: Postgres for persistence, Redis for live state, Drizzle for type-safe schema + migrations-as-code.
Consequences: migrations live in `server/drizzle/`; existing migration files are protected by hook.

## ADR-005 — Single source of game rules: packages/shared-rules → generated GDScript

Date: 2026-09-14 · Status: accepted
Context: client and server must never disagree on a number.
Decision: all game math lives once in `packages/shared-rules/src/*.ts` (pure-function subset of TS) and is transpiled to `client/scripts/rules/*.gd` by `scripts/gen_rules.py`, which writes a sha256 header per file.
Consequences: shared-rules code is restricted (no classes/closures/imports beyond the subset); balance numbers live in docs/balance/\*.yaml and are read by shared-rules.

## ADR-006 — CI: GitHub Actions running scripts/check.sh

Date: 2026-09-14 · Status: accepted
Decision: one workflow, one command. `check.sh` is the only definition of green.

## ADR-007 — Infra: Docker Compose (dev) → Fly.io / Hetzner (prod)

Date: 2026-09-14 · Status: accepted
Decision: compose for local dev; `scripts/deploy.sh staging|prod`; prod requires `CONFIRM=yes` and a human.

## ADR-008 — Placeholder art: procedural 32×32 pixel art + Kenney (CC0)

Date: 2026-09-14 · Status: accepted
Decision: `scripts/gen_sprite.py` generates spritesheets from YAML; archetype colours: Stim=yellow, Numb=blue-grey, Illusion=purple, Zen=green, Rage=red. Replacement needs tracked in docs/art_needed.md.

## ADR-009 — Task management: TASKS.md in repo (GitHub Issues optional)

Date: 2026-09-14 · Status: accepted

## ADR-010 — Libraries approved for the initial skeleton

Date: 2026-09-14 · Status: accepted

- server: `ws`, `zod`, `drizzle-orm`, `postgres`, `ioredis`, `pino`; dev: `typescript`, `vitest`, `tsx`, `eslint`, `prettier`, `drizzle-kit`, `@types/node`, `@types/ws`
- shared-rules: `zod`; dev: `typescript`, `vitest`
- python scripts: `pyyaml`, `pillow`, `ruff`
- client: GUT addon (MIT)
  Any addition beyond this list needs a new ADR.

## ADR-011 — Client tests skip (with warning) when godot binary is absent

Date: 2026-09-14 · Status: accepted
Context: not every dev/AI environment has Godot installed; check.sh must still be runnable.
Decision: `scripts/test_client.sh` exits 0 with a loud warning when `godot` is missing, unless `STRICT_CLIENT=1` (set in CI), in which case it fails.
Consequences: a local green is weaker than CI green; CI is authoritative.

## ADR-012 — RulesScript translator: `for (const x of ARR)` support (for loot.ts)

Date: 2026-09-14 · Status: accepted
Context: `roll_loot()` (T-0.6) needs to walk `docs/balance/items.yaml` loot-table entries
(an array of `{item, weight}` objects) cumulatively. The translator only understood the
numeric `for (let i = a; i < b; i++)` loop, which can't iterate an array of objects.
Decision: extend `scripts/gen_rules.py`'s `translate()` with one more line pattern —
`for (const x of EXPR) { ... }` → `for x in EXPR:` — reusing the existing expression
translator (imports/Math/operators) for `EXPR`. No new syntax elsewhere; bracket index
access (`X[key]`) needed no change since it is already valid, identical syntax in GDScript.
To make `ITEMS.loot_tables[table_id]` type-check under TS strict + `noUncheckedIndexedAccess`
(the literal-keyed `as const` type has no index signature for a dynamic `string` key),
`gen_rules.py`'s balance-data generator (`gen_items_ts`) now special-cases the `ITEMS` constant:
it declares `items`/`loot_tables` as `Record<string, ItemDef>` / `Record<string, LootTable>`
and assigns the JSON literal directly against that contextual type (no `as`/`any` cast needed).
Consequences: any future shared-rules function that needs to loop over a YAML-derived list of
objects can use this pattern. Addendum (same day): the translator also rewrites `X[key] == null` / `!= null` to
`X.get(key) == null` / `!= null`, because GDScript's `dict[missing_key]` bracket access prints a
non-fatal `SCRIPT ERROR` while `Dictionary.get()` returns null silently. Guard a dynamic lookup with
`if (X[key] == null) { return ...; }` in TS and both sides stay quiet.

## ADR-013 — Phase 0 single-player combat runs in one "LocalServer" node
Date: 2026-09-14 · Status: accepted (until T-2.9)
Context: CLAUDE.md says the client never computes damage; WORKPLAN Phase 0 is a single-player prototype
and T-2.9 later removes single-player logic ("local server mode").
Decision: all combat resolution in the client lives in exactly one node, `client/scripts/combat/local_server.gd`,
which mimics the future server API: entities send intents (`request_attack`) and receive facts (signals
`damage_dealt`, `entity_died`, `crash_started/ended`). It is the only file outside `client/scripts/rules/`
allowed to call `RulesCombat.damage` / `RulesLoot.roll_loot` / `RulesStatus.*` (enforced by grep in QA, and
by T-2.9's DoD later).
Consequences: Phase 2 replaces LocalServer with the network layer without touching player/monster scenes.

## ADR-014 — Screenshots via xvfb; CI installs it
Date: 2026-09-14 · Status: accepted
Context: `scripts/screenshot.sh` needs a display; the AI sandbox and CI runners have none.
Decision: `screenshot.sh` wraps Godot in `xvfb-run` when no DISPLAY is set and forces the Dummy audio
driver. `.github/workflows/ci.yml` installs `xvfb` and runs one screenshot as a smoke step (artifact
uploaded). Screenshots committed under docs/screenshots/ are the DoD evidence for UI tasks.
Consequences: xvfb is a system package (apt), not a project library; `setup.sh` mentions it for Linux.

## ADR-015 — Skills are server-gated; currency and prices are rule-derived
Date: 2026-09-14 · Status: accepted
Context: T-0.7 adds usable skills, T-0.12 adds a shop. Both need numbers and gates that the client must
not own.
Decision:
- Skill definitions live in docs/balance/classes.yaml (level, power, hits, cooldown, crash_hits,
  range_px). Unlock and cooldown checks are pure rules (shared-rules skills.ts) evaluated by the
  authority (LocalServer now, the real server in phase 2) on the server clock; the client only asks
  `request_skill` and displays `skill_used` / `skill_rejected` / cooldown-left.
- One currency ("אישורי החזר", key ui.currency.name). Monsters drop a uniform integer in their
  monsters.yaml `money` range (economy.ts roll_money) decided by the authority on kill
  (`money_dropped`); the client bag stores it. Prices are value × BUY_PRICE_MULT / SELL_PRICE_MULT
  from shared-rules constants; never typed in UI code.
- Placeholder content policy (Q3–Q6): when a task is blocked on the GDD but the human asks for features,
  engineering placeholders are allowed if they (a) live only in docs/balance/*.yaml + docs/content, (b)
  are marked ⚠️ PLACEHOLDER in the file, and (c) are logged as a Question for human in TASKS.md.
Consequences: swapping content never touches code; phase 2 replaces LocalServer without changing the
skill/shop UI.
