# PROGRESS

## Session 2 — 2026-09-14 — Phase 0 start: player + combat rules
**Done**
- T-0.1/T-0.2/T-0.4: `client/scenes/player/player.tscn` (CharacterBody2D + 6-state StateMachine + PlayerCamera), flat test map, main.tscn boots it. 33 GUT tests total (was 6).
- T-0.6: shared-rules `movement.ts`, `combat.ts` (damage/effective_hp/apply_damage/is_dead), `loot.ts` (roll_loot/loot_value) → generated movement.gd/combat.gd/loot.gd. 64 vitest tests (was 11); GUT parity fixture for damage + loot.
- Translator: `for (const x of ARR)` and `X[k] == null → X.get(k) == null` (ADR-012); `ITEMS` balance data typed as Record for dynamic keys.
- TASKS.md: Phase 0 backlog opened; T-I.2 / T-I.7 blocked on a human (docker daemon, first PR).

**Next**
- T-0.3 (TileMapLayer map 60×20) then T-0.5 (mobile controls) — both need a screenshot DoD; the sandbox has no display server, so screenshots need a human or xvfb in CI.
- T-0.8 crash mechanic + T-0.9 monsters can proceed without the GDD; T-0.7/T-0.12 wait on Q1.
- Human: answer Q1 (copy real GDD), Q2, run scripts/setup.sh, open the first PR.

**Broken / not verified**
- scripts/screenshot.sh cannot run here (no X11/Wayland; only --headless works). Untested until a machine with a display or xvfb.
- Jump buffer fires one physics frame after landing is detected (grounded is read at step start) — acceptable feel, documented in player.gd; revisit if playtest says "sticky".

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
