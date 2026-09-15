# PROGRESS

## Session 9 — 2026-09-15 — Phase 1: Form 27-B + item instances
**Done**
- T-1.5 "טופס עלייה במינון 27-ב": every level-up now presents a bureaucratic approval form that REPORTS the grants the authority already applied (it never grants anything itself, so it works against LocalServer or RemoteAuthority unchanged). One form per level crossed, the rest queued; signing stamps it, blocks a double-approval and saves. Modal, so it joins the T-0.15 set that blocks attacks. The level-10 dosage branch is shown as pending the ethics committee rather than faked — it is blocked on Q1.
- T-1.7b item instances: a bag row is now {item_id, count, affixes}. Two rolls of the same sword stay distinct, affixes survive equip/swap-back/unequip/save, and equip/compare/sell address the exact instance tapped — the old id-based remove() would have sold the player's best roll. LocalServer rolls affixes on its own seeded rng (re-roll on duplicate, bounded); 60 seeds assert every roll is legal for the rarity and within the documented slot range. Pre-T-1.7b saves still load.
- Totals: vitest 165 + 42, GUT 283 across 34 scripts (was 249/32). check.sh GREEN in strict mode.

**Next**
- T-2.7 chat UI, T-2.8 disconnect/reconnect mid-fight, T-2.10 (new) drops carrying affixes over the wire.
- Human: Q1–Q9, Phase 0 playtest, first PR.

**Broken / not verified**
- Another false-green class found and closed: GUT reports PASS even when a runtime SCRIPT ERROR fires every frame. Two real defects were hiding behind that — a ternary assigning an untyped Array to an Array[String], and `String(7)` (no such constructor) on an untrusted save value. Only a screenshot run surfaced the first. scripts/test_client.sh now fails on any SCRIPT ERROR, which immediately caught the second.
- T-2.9 is now BLOCKED on Q9, not ready: "the server is always the authority, even solo" needs a product decision on whether offline play survives, and the solo branch still carries gear, heals, save/load and the shop economy that the server does not implement.
- Net mode still shows every drop as affixless (T-2.10) and reports attack/defense as 0 in get_stats, so Form 27-B shows only the max_hp row there.
- Still no auth (any non-empty token joins) — T-3.2. Placeholder content everywhere (Q3–Q8).

## Session 8 — 2026-09-15 — Phase 2: combat through the server
**Done**
- T-2.4 combat is server-authoritative end to end: the Zone does its own target selection (an attack is a flag on the per-tick input, never a target list), enforces unlock/cooldown/dead/self gates on the server clock, runs the crash streak, and emits attack/damage/died facts. Client-side, a CombatAuthority seam picks LocalServer (solo) or RemoteAuthority (net), so HUD, skill bar, monsters and drops are unchanged by which one is live.
- T-2.5 private per-player drops (own snapshot only, owner-only pickup in PICKUP_RADIUS_PX) and T-2.6 group XP shared among damagers via a new shared-rules party module (placeholder curve, Q8). ADR-017.
- Verified against the real server, not just fakes: headless client killed monster m_1 (60 hp → 0, 6 server-confirmed hits); 4-client sim 0 violations; net-mode screenshots at both resolutions show 6 server-driven monsters and a live HP bar.
- Totals: vitest 165 + 42, GUT 249 (32 scripts). check.sh GREEN in strict mode.

**Next**
- T-2.7 chat UI, T-2.8 disconnect/reconnect mid-fight, T-2.9 delete the single-player combat branch (the CombatAuthority seam is the hook).
- Human: Q1–Q8, Phase 0 playtest, first PR.

**Broken / not verified**
- Both sub-agents were terminated mid-task by a rate limit; their remainder (ADR-017, two parity tests, a wrong test assumption, debug scratch) was finished by the lead. Nothing was left half-applied, but the work was not agent-reviewed.
- Tooling trap found and fixed: screenshot.sh used to print "saved" when only a STALE file existed, and its frame budget was shorter than a net scene needs — every net-mode screenshot before this session was silently the previous image. It now deletes the target first and fails loudly.
- Still no auth (any non-empty token joins) — T-3.2. Placeholder content everywhere (Q3–Q8).

## Session 7 — 2026-09-15 — Phase 2: server room + client net layer
**Done**
- T-2.2: authoritative Node server — one Zone (4 players, 20 Hz), tile collision + player sim on shared-rules movement, join/leave/input/state/chat, per-type rate limits, /health tick p95. Map layout moved to docs/maps (shared data, ADR-016). 36 server tests; live 4-client sim clean.
- T-2.3: client NetClient/NetSession with prediction + reconciliation (2 px epsilon, replay), remote-player interpolation (100 ms), FakeTransport for tests, net_smoke headless scene verified against the real server. Net mode via HAMIRPAA_SERVER_URL / --server=; single-player path unchanged.
- Tooling: PROTOCOL_VERSION generated into protocol.gd and checked; test_client.sh fails on unloadable test scripts (GUT used to skip them silently).
- Totals: vitest 165 + 36, GUT 232 (29 scripts). check.sh GREEN in strict mode.

**Next**
- T-2.4 combat through the server (attack intent → damage/died facts; LocalServer becomes the local-mode adapter), then T-2.5 per-player loot, T-2.6 group xp, T-2.8 reconnect, T-2.9 remove single-player combat.
- Human: Q1–Q7, Phase 0 playtest, first PR.

**Broken / not verified**
- Net mode is a hybrid: movement is server-authoritative, combat is still local (ADR-013) until T-2.4.
- Server physics is a simplified AABB sim; the client reconciles, so small divergences are expected (ADR-016). No auth yet (any non-empty token joins) — T-3.2.
- Controls anchored under the Node2D root collapse to content size; top-level UI must live in a CanvasLayer (noted by the net agent).

## Session 6 — 2026-09-14 — Phase 1/2 engineering: affix rules, protocol v1, UI blocking
**Done**
- T-1.7 (rules level): 10 placeholder affixes in items.yaml (Q7), shared-rules affixes.ts (count/pool/weighted roll/stat+mult/item_stat_with_affixes), parity fixture asserted by vitest and GUT.
- T-2.1: docs/protocol.md v1 with 16 messages, sequences, bounds rationale and error codes; Zod schemas + parseServerMessage; protocol.gd regenerated; 65 protocol tests. check_protocol_sync regex fixed.
- T-0.15: attacks/skills blocked while a panel is open. Backlog opened for Phase 1 (engineering rows) and Phase 2.
- Totals: vitest 165 + 7, GUT 212. check.sh GREEN in strict mode.

**Next**
- T-2.2 server room (4 players, 20 Hz, authoritative movement, PICKUP_RADIUS_PX) → T-2.3 client net layer with prediction/reconciliation → T-2.4 combat through the server. These replace LocalServer (ADR-013) per T-2.9.
- T-1.7b inventory item instances with affixes; T-1.5 form 27-ב UI shell.
- Human: Q1–Q7, Phase 0 playtest, first PR.

**Broken / not verified**
- The PostToolUse prettier hook reformats markdown tables in docs/; scripts that parse docs must tolerate padded cells (check_protocol_sync now does).
- Two agents running the full check concurrently can see a transient red while the other edits; only sequential final runs count.

## Session 5 — 2026-09-14 — Phase 0: skills, pharmacist, shop, currency
**Done**
- Skill system (T-0.7): 5 placeholder Stim skills in classes.yaml, shared-rules skills.ts; LocalServer.request_skill gates unlock + cooldown on the server clock; attack = basic skill, skill button = selected skill; SkillBar UI with cooldowns and locked levels.
- Pharmacist NPC + shop (T-0.12): npcs.yaml, 3 dialogue lines, talk prompt, dialogue box, buy/sell shop; currency "אישורי החזר" dropped by monsters (economy.ts roll_money) and saved with the bag. ADR-015.
- Content: 10 items, money ranges per monster, validator covers skills/money/npcs.
- Totals: vitest 84 + 7, GUT 200 (was 147). check.sh GREEN in strict mode. Screenshots: main (skill bar), shop, dialogue.

**Next**
- Phase 0 is feature-complete except T-0.14 (export, deferred by the human). Human checkpoint: 20-minute mobile playtest — "is it fun?" — gates Phase 1.
- Phase 1 candidates that need no GDD: T-1.5 "טופס 27-ב" upgrade UI shell, T-1.7 item affixes (rules + loot), T-1.8 XP curve to level 30 (sim). T-1.1/1.2/1.3 (other archetypes) need Q1.
- Polish gaps: block attacks while UI is open; NPC label overlaps platform tiles; consumable use has no cooldown.

**Broken / not verified**
- All skill/NPC/item/currency content is placeholder (Q3–Q6) — swap in docs/balance + docs/content only.
- Export still unresolved: I18nBoot reads docs/content from outside the .pck (T-0.14 note).

## Session 4 — 2026-09-14 — Phase 0: progression, HUD, inventory, save
**Done**
- T-0.10 XP/level-up/HUD: LocalServer grants xp to the killer, levels via RulesXp, stats via RulesProgression (new shared-rules module + classes.yaml growth, Q4); 6 monsters live on clinic_lobby; HUD with HP/XP bars, stats panel, level-up flash.
- T-0.11 inventory + gear comparison and T-0.13 JSON save, wired end to end: drops → bag, equip → LocalServer.set_gear_bonus, consumable → LocalServer.heal (new RulesCombat.heal), autosave (30 s / level-up / window close), load on boot. 5 placeholder items (Q5).
- XP curve retuned (was ~100 min to level 10, now 10–24 min by archetype); balance_sim prints a time-to-level table.
- Totals: vitest 76 + 7, GUT 147 (was 71). check.sh GREEN in strict mode. Screenshots refreshed.

**Next**
- T-0.14 export (Android APK + Windows): needs export templates + export_presets.cfg + moving docs/content YAML into the .pck (I18nBoot reads res://../docs today).
- T-0.7 / T-0.12 remain blocked on Q1 (real GDD). Then Phase 0 Human Checkpoint: 20-minute mobile playtest ("is it fun?").
- Human: answer Q1–Q5, playtest docs/playtest_notes.md, open the first PR.

**Broken / not verified**
- Duplicate agents were accidentally launched in this session (the first pair survived a container reset I assumed had killed them); one duplicate briefly overwrote inventory.gd before being stopped. Final files were re-verified by the owning agent and by the full check. Lesson: check `git status` for agent output before relaunching.
- Balance: numb takes ~24 min to level 10 (placeholder numbers).
- Consumables heal via their `stats.hp`; no cooldown or use animation yet.

## Session 3 — 2026-09-14 — Phase 0: map, mobile controls, monsters, crash
**Done**
- T-0.3 clinic_lobby map (TileMapLayer 60×20, generated tileset, 8 jumpable platforms) + T-0.5 touch controls (joystick, 3 buttons, auto-attack toggle; Hebrew labels via I18nBoot autoload). Screenshots in docs/screenshots/.
- T-0.9 monsters (patrol/chase/attack/hurt/dead AI from monsters.yaml ai_params, HP bar, drop pickup) + T-0.8 Stim crash, both resolved inside the single LocalServer node (ADR-013). Arena test scene with 3 monster kinds.
- shared-rules status.ts (crash), monster ai_params + 2 placeholder monsters (Q3), screenshot.sh under xvfb (ADR-014; CI installs xvfb and uploads screenshots).
- Totals: vitest 68 + 7, GUT 69 (was 35). check.sh GREEN in strict mode.

**Next**
- T-0.10 XP/level-up/stats UI: place monsters in clinic_lobby, LocalServer grants xp on entity_died, RulesXp.level_for_xp, HUD. Then T-0.11 inventory (drops → inventory), T-0.13 local save.
- Human: playtest docs/playtest_notes.md (crash feel), answer Q1–Q3, open the first PR (CI now includes a screenshot smoke step).

**Broken / not verified**
- Monsters exist only in scenes/test/arena.tscn, not yet on the real map (T-0.10 wires them).
- Sub-agent reported client/tests/ was briefly wiped mid-session by a concurrent process and restored from git; final state verified (11 test files, tracked ones identical to HEAD). Run agents on disjoint directories only.
- Balance: level-3 placeholder monster has TTK > 8 s vs level-1 stats (expected; game-designer tunes in T-0.7).

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
