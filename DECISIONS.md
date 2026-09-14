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
Consequences: shared-rules code is restricted (no classes/closures/imports beyond the subset); balance numbers live in docs/balance/*.yaml and are read by shared-rules.

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
