# TASKS

סטטוסים: `ready` / `in-progress` / `blocked` / `[x]` done. ה-AI לוקח תמיד את ה-`ready` הראשון.
פורמט: `- [ ] ready T-X.Y | agent | description | test: <what proves done>`
משימות שלבים 0–5 נמצאות ב-docs/WORKPLAN.md §10 ומועברות לכאן כשהשלב הקודם עובר Human Checkpoint.

## Questions for human
- [ ] Q1: docs/GDD.md הוא placeholder. יש להעתיק את ה-GDD האמיתי לריפו. (blocks all game-designer work in Phase 0)
- [ ] Q3: monsters.yaml has 2 ENGINEERING PLACEHOLDER monsters (lost_referral, form_27b) so T-0.9 can show 3 AI kinds. game-designer replaces names/numbers in T-0.7. OK? (not blocking)
- [ ] Q4: classes.yaml `growth` per archetype and the retuned xp_curve.yaml are ENGINEERING PLACEHOLDERS (stim reaches level 10 in ~10 min, numb ~24). game-designer owns them in T-0.7/T-1.8. OK? (not blocking)
- [ ] Q5: items.yaml has 5 placeholder items (2 weapons, head, body, consumable) with stats; consumables' `stats.hp` = heal amount. game-designer replaces in T-0.7. OK? (not blocking)
- [ ] Q6: on the human's 'add features' instruction, T-0.7 and T-0.12 were built with PLACEHOLDER skills (5 Stim skills), NPC lines (pharmacist), shop stock and a currency ("אישורי החזר"). All live in docs/balance/*.yaml + docs/content — swap freely. OK? (not blocking)
- [ ] Q7: items.yaml `affixes` (10 satire affixes, slot ranges per rarity) are ENGINEERING PLACEHOLDERS. game-designer owns them (T-1.7 content). OK? (not blocking)
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
- [x] T-0.3 | godot-dev + art-pipeline | One map (TileMapLayer) 60×20 tiles with platforms | test: docs/screenshots/clinic_lobby_1920x1080.png + client/tests/test_map_clinic_lobby.gd (7)
- [x] T-0.4 | godot-dev | Camera with deadzone + map limits | test: client/tests/test_camera.gd (4 tests)
- [x] T-0.5 | godot-dev | Mobile controls: joystick + 3 buttons, auto-attack toggle | test: docs/screenshots/main_390x844.png + client/tests/test_touch_controls.gd (12)
- [x] T-0.6 | server-dev | shared-rules: damage(), xp_for_level(), roll_loot() (+movement) | test: 64 vitest tests + client/tests/test_rules_combat.gd parity fixture
- [x] T-0.7 | game-designer | YAML: Stim (5 skills, levels 1–10), 3 monsters, 10 items — PLACEHOLDER content (Q6) + skill system in the game | test: validate_balance + balance_sim green; client/tests/test_skills.gd (9) + test_skill_bar.gd (6)
- [x] T-0.8 | godot-dev | "Crash" mechanic: after 4 consecutive hits → 2 s of ×2 damage taken (numbers from classes.yaml stim.mechanics.crash via shared-rules) | test: client/tests/test_local_server.gd + docs/playtest_notes.md
- [x] T-0.9 | godot-dev | Monsters: simple AI (patrol/chase/attack), HP bar, death + drop | test: client/tests/test_monster_ai.gd (5) + docs/screenshots/arena_1920x1080.png (3 kinds; placeholders per Q3)
- [x] T-0.10 | godot-dev | XP, level-up, stats UI | test: client/tests/test_progression_flow.gd + test_hud.gd; balance_sim time-to-level-10 table (stim 10 min, others 12–24)
- [x] T-0.11 | godot-dev | Basic inventory + gear comparison | test: docs/screenshots/inventory_390x844.png + client/tests/test_inventory*.gd (39) + test_game_session.gd
- [x] T-0.12 | game-designer + godot-dev | NPC "רוקח": 3 dialogue lines + shop — PLACEHOLDER content (Q6) | test: client/tests/test_shop.gd (10), test_dialogue.gd (6), test_npc.gd (7); screenshots shop/dialogue_390x844.png
- [x] T-0.13 | godot-dev | Local save (JSON) | test: client/tests/test_game_session.gd::test_quit_and_reload_keeps_state (+ test_save_game.gd 13)
- [ ] deferred T-0.14 | devops | Export Android APK + Windows | test: APK runs (human confirms) | note: I18nBoot reads `res://../docs/content/*.yaml` — outside the .pck; export must copy content into client/ (or gen_rules emits a .gd table). Needs export templates (~1 GB download) + export_presets.cfg.

## Phase 1 — מערכת מקצועות (engineering-only rows opened early; archetype rows wait on Q1)
- [ ] blocked T-1.1 | game-designer | 4 more archetypes: full YAML (5 skills each) | test: sim: no archetype > 15% | reason: Q1
- [ ] blocked T-1.2 | godot-dev ×4 | Unique mechanics: Numb / Illusion / Zen / Rage | test: one GUT test per mechanic | reason: Q1
- [ ] blocked T-1.3 | godot-dev + game-designer | Archetype select screen with satirical text | test: screenshot | reason: Q1
- [ ] blocked T-1.4 | game-designer | Level-10 branch: 2 "dosages" per archetype | test: YAML + sim | reason: Q1
- [ ] ready T-1.5 | godot-dev | "טופס עלייה במינון 27-ב" bureaucratic upgrade UI (shell, wired to level-up) | test: screenshot
- [ ] blocked T-1.6 | art-pipeline + game-designer + godot-dev | 3 new zones (10 monsters, 1 boss) | test: sim + screenshot | reason: Q1
- [x] T-1.7 | server-dev | Item affixes (10) — rules level: affixes.ts + YAML + parity fixture (client item instances = T-1.7b) | test: tests/affixes.test.ts (20) + client/tests/test_rules_affixes.gd (11)
- [ ] ready T-1.7b | godot-dev | Inventory item instances with rolled affixes; drops carry affixes; comparison shows affix stats | test: GUT
- [ ] blocked T-1.8 | game-designer | Final XP curve 1–30 | test: sim: level 30 ≈ 12 h | reason: needs T-1.6 monsters for a meaningful sim

## Phase 2 — Multiplayer (engineering-only; started early because Phase 1 content is blocked on Q1)
- [x] T-2.1 | protocol-designer | protocol.md v1: 16 messages (join/joined/leave/left/input/state/attack/damage/died/loot_pickup/loot/chat/chat_msg + ping/pong/error) + Zod + protocol.gd | test: check_protocol_sync green; tests/protocol.test.ts (65)
- [ ] ready T-2.2 | server-dev | Server: one room, 4 players, 20 Hz tick, authoritative movement | test: sim_clients 4
- [ ] ready T-2.3 | godot-dev | Client net layer, prediction + reconciliation | test: 200 ms simulated latency, no jitter
- [ ] ready T-2.4 | server-dev + godot-dev | Combat through the server: attack intent → damage fact | test: 2 clients see the same hp
- [ ] ready T-2.5 | server-dev | Per-player loot | test: 2 players, 2 different drops
- [ ] ready T-2.6 | server-dev | Group XP bonus | test: shared-rules test
- [ ] ready T-2.7 | godot-dev | Chat + quick emoji (mobile) | test: screenshot
- [ ] ready T-2.8 | server-dev + qa | Disconnect/reconnect mid-fight | test: GUT/vitest
- [ ] ready T-2.9 | godot-dev | Remove single-player logic from the client (LocalServer → local server mode) | test: grep: no `damage(` in client outside rules/

## Polish (Phase 0 leftovers)
- [x] T-0.15 | godot-dev | Block attacks/skills while a dialogue, shop or inventory panel is open | test: test_game_session.gd::test_open_panel_blocks_attacks_but_not_movement

### QA reports
- T-I.1: PASS — `scripts/check.sh` green (STRICT_CLIENT=1 with Godot 4.3), `scripts/hooks/test_hooks.sh` 17/17, `pnpm lint` clean, ruff clean.
- T-I.3/T-I.4/T-I.5: PASS — vitest 18 tests, GUT 6 tests/102 asserts, TS and generated GDScript agree on xp_for_level(1..30) and totals via packages/shared-rules/tests/fixtures/xp_curve.json.
- T-I.6: PASS — guard_bash.sh blocked a real recursive delete during the bootstrap session.
- T-0.1/T-0.2/T-0.4: PASS — 21 new GUT tests (movement incl. coyote/buffer/jump-cut boundaries, all 6 state transitions, camera deadzone + limits); player.gd has no movement literals (9 RulesMovement calls). No screenshot: sandbox has no display server — T-0.3's screenshot DoD needs a human or a CI job with xvfb.
- T-0.6: PASS — 50 new vitest tests (combat 18+3 QA, loot 10, movement 22); TS ↔ GDScript parity on 10 damage + 10 loot cases via fixtures/combat.json; QA added: power ≤ 0 / absurd defense / roll == 1 never go below MIN_DAMAGE. Translator gained `for…of` and `X[k] == null → X.get(k)` (ADR-012).
- T-0.3/T-0.5: PASS — 19 new GUT tests; screenshots reviewed at 390×844 and 1920×1080. QA fixes after review: joystick overlapped the left button at 390 px (resized), title was a hardcoded string (now `ui.title` key), button labels clipped (shortened to one word each).
- T-0.8/T-0.9: PASS — 15 new GUT tests; `RulesCombat.damage(` occurs in exactly one client file (local_server.gd, ADR-013). QA added: self-attack and unknown-id intents are ignored. Note: monsters are not yet placed in clinic_lobby.tscn (arena.tscn only) — wire-up is part of T-0.10 (XP flow needs kills on the real map).
- T-0.10: PASS — 17 GUT tests; xp only to the killer, monsters never level, heal-to-full on level-up is a documented phase-0 default. HUD reviewed at both resolutions.
- T-0.11/T-0.13: PASS — 52 module tests + 5 end-to-end session tests (drop → bag, equip → server attack, consumable → server heal, quit-and-reload restores level/hp/bag/gear/position, corrupt save boots fresh). QA fixes: consumables had hp 0 (nothing could heal); inventory button overlapped the title at 390 px. Lead wired the modules (LocalServer.set_gear_bonus/heal/set_hp, ClinicLobby drop routing, main.gd autosave every 30 s + on level-up + on window close).
- T-0.7 (skills): PASS — server-gated unlock/cooldown on the LocalServer clock, rejection reasons tested, hits×power verified against RulesCombat with a seeded rng; the only damage call is still local_server.gd. Lead wired SkillBar into main.tscn; QA fix: the bar overlapped the ground row at 390 px — moved into the strip between map and joystick.
- T-0.12 (NPC/shop): PASS — buy/sell/refund/bag-full/no-money paths tested, prices only via RulesEconomy; money saved and restored; a real kill credits money. QA fix: the active shop tab was rendered disabled (looked inverted) — now a pressed toggle. Known gap: the player can still attack while a dialogue/shop is open (no ui_blocking hook yet).
- T-1.7: PASS — roll bounds/pool/weights verified on both sides via fixtures/affixes.json; 10k-roll distribution within 3%. No client integration yet (T-1.7b).
- T-2.1: PASS — every message has valid + out-of-bounds tests; check_protocol_sync fixed (prettier pads table cells, the regex assumed none). Design notes: facts never omit fields (null instead), input failures are dropped silently (amplification), died carries killer_id. T-2.2 must add PICKUP_RADIUS_PX to shared-rules constants.
- T-0.15: PASS — note for GUT tests: wait_frames() advances physics but not idle _process; await get_tree().process_frame for _process-driven logic.
