# TASKS

סטטוסים: `ready` / `in-progress` / `blocked` / `[x]` done. ה-AI לוקח תמיד את ה-`ready` הראשון.
פורמט: `- [ ] ready T-X.Y | agent | description | test: <what proves done>`
משימות שלבים 0–5 נמצאות ב-docs/WORKPLAN.md §10 ומועברות לכאן כשהשלב הקודם עובר Human Checkpoint.

## Questions for human
- [ ] Q1: docs/GDD.md הוא placeholder. יש להעתיק את ה-GDD האמיתי לריפו. (blocks all game-designer work in Phase 0)
- [ ] Q2: שם הריפו/תיקייה הוא `Mmorpg-drag`, ה-WORKPLAN מניח `hamirpaa`. להשאיר? (devops, not blocking)

## Phase -1 — תשתית
- [x] T-I.1 | devops | Monorepo per WORKPLAN §2, CLAUDE.md, full .claude/ (agents, skills, settings.json hooks), scripts/ | test: `ls` matches structure; `scripts/check.sh` runs
- [ ] ready T-I.2 | devops | `setup.sh` + docker-compose (postgres, redis) verified on a real machine | test: `docker compose ps` — 2 services up
- [x] T-I.3 | godot-dev | Empty Godot project + GUT addon vendored + passing tests | test: `scripts/test_client.sh` green (verified with Godot 4.3.stable: 6 tests, 102 asserts)
- [x] T-I.4 | server-dev | Empty Node server + Vitest + health test | test: `scripts/test_server.sh` green
- [x] T-I.5 | server-dev | shared-rules with `xp_for_level` + gen_rules.py works | test: `.gd` generated; TS test and GUT test agree on the numbers
- [x] T-I.6 | devops | All hooks + check.sh | test: editing a protected file is blocked (see scripts/hooks/test_hooks.sh)
- [ ] ready T-I.7 | devops | CI on GitHub Actions runs check.sh | test: first PR green
- [x] T-I.8 | doc-keeper | All Skills written | test: 6 skill folders with SKILL.md

### QA reports
- T-I.1: PASS — `scripts/check.sh` green (STRICT_CLIENT=1 with Godot 4.3), `scripts/hooks/test_hooks.sh` 17/17, `pnpm lint` clean, ruff clean.
- T-I.3/T-I.4/T-I.5: PASS — vitest 18 tests, GUT 6 tests/102 asserts, TS and generated GDScript agree on xp_for_level(1..30) and totals via packages/shared-rules/tests/fixtures/xp_curve.json.
- T-I.6: PASS — guard_bash.sh blocked a real recursive delete during the bootstrap session.
