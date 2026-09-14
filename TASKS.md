# TASKS

סטטוסים: `ready` / `in-progress` / `blocked` / `[x]` done. ה-AI לוקח תמיד את ה-`ready` הראשון.
פורמט: `- [ ] ready T-X.Y | agent | description | test: <what proves done>`
משימות שלבים 0–5 נמצאות ב-docs/WORKPLAN.md §10 ומועברות לכאן כשהשלב הקודם עובר Human Checkpoint.

## Questions for human
- [ ] Q1: docs/GDD.md הוא placeholder. יש להעתיק את ה-GDD האמיתי לריפו. (blocks all game-designer work in Phase 0)
- [ ] Q3: monsters.yaml has 2 ENGINEERING PLACEHOLDER monsters (lost_referral, form_27b) so T-0.9 can show 3 AI kinds. game-designer replaces names/numbers in T-0.7. OK? (not blocking)
- [ ] Q2: שם הריפו/תיקייה הוא `Mmorpg-drag`, ה-WORKPLAN מניח `hamirpaa`. להשאיר? (devops, not blocking)

## Phase -1 — תשתית
- [x] T-I.1 | devops | Monorepo per WORKPLAN §2, CLAUDE.md, full .claude/ (agents, skills, settings.json hooks), scripts/ | test: `ls` matches structure; `scripts/check.sh` runs
- [ ] blocked T-I.2 | devops | `setup.sh` + docker-compose (postgres, redis) verified on a real machine | test: `docker compose ps` — 2 services up | reason: no docker daemon in the AI environment — a human runs scripts/setup.sh once
- [x] T-I.3 | godot-dev | Empty Godot project + GUT addon vendored + passing tests | test: `scripts/test_client.sh` green (verified with Godot 4.3.stable: 6 tests, 102 asserts)
- [x] T-I.4 | server-dev | Empty Node server + Vitest + health test | test: `scripts/test_server.sh` green
- [x] T-I.5 | server-dev | shared-rules with `xp_for_level` + gen_rules.py works | test: `.gd` generated; TS test and GUT test agree on the numbers
- [x] T-I.6 | devops | All hooks + check.sh | test: editing a protected file is blocked (see scripts/hooks/test_hooks.sh)
- [ ] blocked T-I.7 | devops | CI on GitHub Actions runs check.sh | test: first PR green | reason: the AI does not open PRs unasked — human opens a PR from claude/design-from-doc-bojzm5 (or asks for one)
- [x] T-I.8 | doc-keeper | All Skills written | test: 6 skill folders with SKILL.md

## Phase 0 — פרוטוטייפ Single-player
- [x] T-0.1 | godot-dev | Player: movement, jump, coyote-time, jump buffer (constants from RulesMovement) | test: client/tests/test_player_movement.gd (10 tests)
- [x] T-0.2 | godot-dev | Player state machine (Idle/Run/Jump/Attack/Hurt/Dead) | test: client/tests/test_state_machine.gd (7 tests)
- [ ] in-progress T-0.3 | godot-dev + art-pipeline | One map (TileMapLayer) 60×20 tiles with platforms | test: screenshot in docs/screenshots/
- [x] T-0.4 | godot-dev | Camera with deadzone + map limits | test: client/tests/test_camera.gd (4 tests)
- [ ] in-progress T-0.5 | godot-dev | Mobile controls: joystick + 3 buttons, auto-attack toggle | test: screenshot at 390×844
- [x] T-0.6 | server-dev | shared-rules: damage(), xp_for_level(), roll_loot() (+movement) | test: 64 vitest tests + client/tests/test_rules_combat.gd parity fixture
- [ ] blocked T-0.7 | game-designer | YAML: Stim (5 skills, levels 1–10), 3 monsters, 10 items | test: validate_balance + balance_sim green | reason: waiting Q1 (real GDD) — skill names/mechanics are product decisions
- [ ] in-progress T-0.8 | godot-dev | "Crash" mechanic: after 4 consecutive hits → 2 s of ×2 damage taken (numbers from classes.yaml stim.mechanics.crash via shared-rules) | test: GUT test + feel documented in PROGRESS
- [ ] in-progress T-0.9 | godot-dev | Monsters: simple AI (patrol/chase/attack), HP bar, death + drop | test: 3 kinds on the map
- [ ] ready T-0.10 | godot-dev | XP, level-up, stats UI | test: level 10 in 15 min (simulation)
- [ ] ready T-0.11 | godot-dev | Basic inventory + gear comparison | test: screenshot
- [ ] blocked T-0.12 | game-designer + godot-dev | NPC "רוקח": 3 dialogue lines + shop | test: buy/sell tested | reason: waiting Q1
- [ ] ready T-0.13 | godot-dev | Local save (JSON) | test: quit-and-reload keeps state
- [ ] ready T-0.14 | devops | Export Android APK + Windows | test: APK runs (human confirms)

### QA reports
- T-I.1: PASS — `scripts/check.sh` green (STRICT_CLIENT=1 with Godot 4.3), `scripts/hooks/test_hooks.sh` 17/17, `pnpm lint` clean, ruff clean.
- T-I.3/T-I.4/T-I.5: PASS — vitest 18 tests, GUT 6 tests/102 asserts, TS and generated GDScript agree on xp_for_level(1..30) and totals via packages/shared-rules/tests/fixtures/xp_curve.json.
- T-I.6: PASS — guard_bash.sh blocked a real recursive delete during the bootstrap session.
- T-0.1/T-0.2/T-0.4: PASS — 21 new GUT tests (movement incl. coyote/buffer/jump-cut boundaries, all 6 state transitions, camera deadzone + limits); player.gd has no movement literals (9 RulesMovement calls). No screenshot: sandbox has no display server — T-0.3's screenshot DoD needs a human or a CI job with xvfb.
- T-0.6: PASS — 50 new vitest tests (combat 18+3 QA, loot 10, movement 22); TS ↔ GDScript parity on 10 damage + 10 loot cases via fixtures/combat.json; QA added: power ≤ 0 / absurd defense / roll == 1 never go below MIN_DAMAGE. Translator gained `for…of` and `X[k] == null → X.get(k)` (ADR-012).
