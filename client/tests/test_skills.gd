extends GutTest
## T-0.7 DoD: LocalServer.request_skill() (client/scripts/combat/local_server.gd)
## is the server-side gate for the Stim's 5 skills (docs/balance/classes.yaml
## archetypes.stim.skills). These tests drive it directly (no Player/UI nodes)
## and predict its seeded RNG rolls the same way test_local_server.gd does.

const DELTA: float = 1.0 / 60.0


func _server() -> LocalServer:
	return add_child_autofree(LocalServer.new())


func _predict_rolls(seed_value: int, count: int) -> Array[float]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var rolls: Array[float] = []
	for i in range(count):
		rolls.append(rng.randf())
	return rolls


func _skill(skill_id: String) -> Dictionary:
	for skill: Dictionary in RulesBalanceData.CLASSES.archetypes.stim.skills:
		if String(skill.id) == skill_id:
			return skill
	return {}


func test_locked_skill_is_rejected_with_reason_locked() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")
	server.register("dummy", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 100.0})
	watch_signals(server)

	var ok: bool = server.request_skill("player", ["dummy"], "stim_double_dose")

	assert_false(ok, "level 1 hasn't reached stim_double_dose's level 3 yet")
	assert_signal_emitted_with_parameters(server, "skill_rejected", ["player", "stim_double_dose", "locked"])
	assert_signal_not_emitted(server, "damage_dealt")
	assert_eq(server.get_hp("dummy"), 100.0)


func test_unlocked_skill_lands_hits_times_at_the_skills_power() -> void:
	var server: LocalServer = _server()
	server.seed_rng(42)
	var skill: Dictionary = _skill("stim_paper_cut")
	var hits: int = int(skill.hits)
	var rolls: Array[float] = _predict_rolls(42, hits)

	server.register("player", {"level": float(skill.level)}, "stim")
	server.register("dummy", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 1000000.0})
	var attacker_view: Dictionary = server.get_stats("player")
	var defender_view: Dictionary = server.get_stats("dummy")
	watch_signals(server)

	var ok: bool = server.request_skill("player", ["dummy"], "stim_paper_cut")

	assert_true(ok, "level matches the skill's required level")
	assert_signal_emit_count(server, "damage_dealt", hits, "one damage_dealt per hit")
	var expected_hp: float = defender_view.hp
	for roll: float in rolls:
		var dmg: float = RulesCombat.damage(attacker_view, defender_view, float(skill.power), roll)
		expected_hp = RulesCombat.apply_damage(expected_hp, dmg)
	assert_eq(server.get_hp("dummy"), expected_hp, "total damage matches hits × RulesCombat.damage at the skill's power")


func test_skill_used_signal_carries_the_skills_cooldown() -> void:
	var server: LocalServer = _server()
	var skill: Dictionary = _skill("stim_double_dose")
	server.register("player", {"level": float(skill.level)}, "stim")
	server.register("dummy", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 1000000.0})
	watch_signals(server)

	server.request_skill("player", ["dummy"], "stim_double_dose")

	assert_signal_emitted_with_parameters(
		server, "skill_used", ["player", "stim_double_dose", float(skill.cooldown)]
	)


func test_cooldown_rejects_a_second_use_then_accepts_after_it_elapses() -> void:
	var server: LocalServer = _server()
	var skill: Dictionary = _skill("stim_double_dose")
	server.register("player", {"level": float(skill.level)}, "stim")
	server.register("dummy", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 1000000.0})

	assert_true(server.request_skill("player", ["dummy"], "stim_double_dose"), "sanity: first use succeeds")

	watch_signals(server)
	var second: bool = server.request_skill("player", ["dummy"], "stim_double_dose")
	assert_false(second, "still on cooldown")
	assert_signal_emitted_with_parameters(server, "skill_rejected", ["player", "stim_double_dose", "cooldown"])
	assert_almost_eq(server.skill_cooldown_left("player", "stim_double_dose"), float(skill.cooldown), 0.001)

	server.advance_time(float(skill.cooldown))
	var third: bool = server.request_skill("player", ["dummy"], "stim_double_dose")
	assert_true(third, "cooldown fully elapsed")
	assert_eq(server.skill_cooldown_left("player", "stim_double_dose"), float(skill.cooldown), "just used again — full cooldown left")


func test_crash_hits_skill_adds_extra_consecutive_hit_increments() -> void:
	var server: LocalServer = _server()
	var skill: Dictionary = _skill("stim_overdose_form")
	server.register("player", {"level": float(skill.level)}, "stim")
	server.register("dummy", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 1000000.0})
	assert_eq(server.get_consecutive_hits("player"), 0.0, "sanity: no hits landed yet")

	server.request_skill("player", ["dummy"], "stim_overdose_form")

	var expected: float = float(int(skill.hits)) + float(skill.crash_hits)
	assert_eq(server.get_consecutive_hits("player"), expected, "landed hit(s) + skill_crash_hits extra increments")
	assert_lt(
		server.get_consecutive_hits("player"),
		float(RulesBalanceData.CLASSES.archetypes.stim.mechanics.crash.hits_in_a_row),
		"sanity: not enough to actually trigger the crash in this test"
	)
	assert_false(server.is_crashed("player"))


func test_dead_attacker_cannot_request_a_skill() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")
	server.register("killer", {"attack": 1000.0, "defense": 0.0, "level": 1.0, "hp": 100.0})
	server.register("dummy", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 100.0})
	server.request_attack("killer", "player", 1.0)
	assert_false(server.is_alive("player"), "sanity: player is dead")

	watch_signals(server)
	var ok: bool = server.request_skill("player", ["dummy"], "stim_jab")

	assert_false(ok)
	assert_signal_emitted_with_parameters(server, "skill_rejected", ["player", "stim_jab", "dead"])
	assert_signal_not_emitted(server, "damage_dealt")


func test_monster_without_progression_cannot_request_a_skill() -> void:
	var server: LocalServer = _server()
	server.register("monster", {"attack": 10.0, "defense": 0.0, "level": 10.0, "hp": 100.0})
	server.register("dummy", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 100.0})
	watch_signals(server)

	var ok: bool = server.request_skill("monster", ["dummy"], "stim_jab")

	assert_false(ok, "monsters have no progression archetype, so no skills")
	assert_signal_emitted_with_parameters(server, "skill_rejected", ["monster", "stim_jab", "unknown"])
	assert_signal_not_emitted(server, "damage_dealt")


func test_unknown_skill_id_is_rejected() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 10.0}, "stim")
	server.register("dummy", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 100.0})
	watch_signals(server)

	var ok: bool = server.request_skill("player", ["dummy"], "not_a_real_skill")

	assert_false(ok)
	assert_signal_emitted_with_parameters(server, "skill_rejected", ["player", "not_a_real_skill", "unknown"])


func test_unlocked_skills_grows_with_set_progress() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")

	assert_eq(server.unlocked_skills("player"), ["stim_jab"] as Array[String])

	server.set_progress("player", RulesXp.xp_total_for_level(5.0))
	assert_eq(server.get_level("player"), 5.0, "sanity: reached level 5")

	var unlocked: Array[String] = server.unlocked_skills("player")
	assert_true(unlocked.has("stim_jab"))
	assert_true(unlocked.has("stim_double_dose"))
	assert_true(unlocked.has("stim_paper_cut"))
	assert_false(unlocked.has("stim_rush_order"), "level 7 skill not unlocked yet at level 5")
	assert_eq(unlocked.size(), 3)
