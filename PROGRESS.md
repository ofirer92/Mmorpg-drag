# PROGRESS

## Session 1 — 2026-09-14 — Phase -1 bootstrap
**Done**
- Monorepo skeleton created per docs/WORKPLAN.md §2 (client/, server/, packages/shared-rules/, scripts/, .claude/, docs/).
- CLAUDE.md, TASKS.md, DECISIONS.md, docs/WORKPLAN.md in place.
- All 10 sub-agents (.claude/agents/) and 6 skills (.claude/skills/) written.
- Hooks wired in .claude/settings.json → scripts/hooks/*. `scripts/check.sh` is the single source of "green".
- shared-rules: `xp_for_level` + `gen_rules.py` producing client/scripts/rules/*.gd with sha headers.
- Server: Node 22 + TS strict + ws; validate → rate-limit → handler pipeline; 7 Vitest tests (health, ping/pong with 2 clients, invalid-message drop + disconnect, flood → rate_limited).
- shared-rules: 11 Vitest tests (xp curve vs fixture, protocol schemas). Client: Godot 4.3 project, GUT 9.3.0 vendored, 6 GUT tests / 102 asserts — generated xp.gd matches the TS fixture number-for-number (T-I.5 DoD proven on both sides).
- Hooks verified live: guard_bash.sh blocked a recursive delete during this very session; scripts/hooks/test_hooks.sh 17/17.
- Balance toolchain: validate_balance.py + balance_sim.py (report in docs/balance/report.md, verdict APPROVED). gen_sprite.py produced client/assets/generated/stim.png.
- docker-compose (postgres 16, redis 7), GitHub Actions CI running ruff + eslint + hooks test + check.sh with STRICT_CLIENT=1.

**Next**
- T-I.2: run `scripts/setup.sh` on a real machine and confirm `docker compose ps` shows 2 services up.
- T-I.7: open the first PR so CI proves itself green.
- Human checkpoint: approve structure, copy the real docs/GDD.md in (Q1), answer Q2.
- Then Phase 0 (T-0.1 …) — move rows from docs/WORKPLAN.md §10 into TASKS.md.

**Broken / not verified**
- test_client.sh was verified with a downloaded Godot 4.3 binary; without `godot` on PATH it skips with a warning (ADR-011). screenshot.sh and export_builds.sh are written but unexercised (no scene worth shooting, no export presets yet — T-0.14).
- docker compose was not brought up here (no daemon access) — T-I.2 stays ready for a human machine.
- docs/GDD.md is a placeholder — the real GDD must be copied in by a human.
- gdformat/gdlint/yamllint not installed here; format_and_lint.sh skips them silently.

## Session 0
Repo created, nothing built yet.
