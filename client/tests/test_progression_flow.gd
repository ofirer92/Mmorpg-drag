extends GutTest
## T-0.10 DoD: LocalServer's xp/level-up flow (client/scripts/combat/local_server.gd).
## Monster hp is set to 1.0 in these tests so a single request_attack always
## one-shots it (RulesCombat.MIN_DAMAGE == 1.0 — no roll dependence needed to
## guarantee a kill), keeping the focus on the xp/level bookkeeping.

const DELTA: float = 1.0 / 60.0


func _server() -> LocalServer:
	return add_child_autofree(LocalServer.new())


func _register_slime(server: LocalServer, id: String) -> Dictionary:
	var monster_data: Dictionary = RulesBalanceData.MONSTERS.monsters["side_effect_slime"]
	server.register(
		id,
		{
			"attack": monster_data.attack,
			"defense": monster_data.defense,
			"level": monster_data.level,
			"hp": 1.0,
			"xp": monster_data.xp,
		}
	)
	return monster_data


func test_register_player_archetype_derives_base_stats_at_level_1() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")

	var stim: Dictionary = RulesBalanceData.CLASSES.archetypes.stim
	var stats: Dictionary = server.get_stats("player")
	assert_eq(stats.attack, float(stim.base_attack), "attack equals base_attack at level 1 (no growth yet)")
	assert_eq(stats.defense, float(stim.base_defense), "defense equals base_defense at level 1")
	assert_eq(stats.hp, float(stim.base_hp), "hp equals base_hp at level 1")
	assert_eq(stats.max_hp, float(stim.base_hp), "max_hp equals base_hp at level 1")
	assert_eq(stats.level, 1.0)
	assert_eq(stats.total_xp, 0.0)


func test_kill_grants_xp_gained_with_monsters_yaml_xp() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")
	var monster_data: Dictionary = _register_slime(server, "slime")
	watch_signals(server)

	server.request_attack("player", "slime", 1.0)

	assert_false(server.is_alive("slime"), "sanity: one-shot kill")
	assert_signal_emitted_with_parameters(
		server, "xp_gained", ["player", float(monster_data.xp), float(monster_data.xp), 1.0]
	)
	assert_eq(server.get_total_xp("player"), float(monster_data.xp))


func test_enough_xp_levels_up_and_heals_to_new_max() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")
	server.register("puncher", {"attack": 1.0, "defense": 0.0, "level": 1.0, "hp": 100.0})

	# Damage the player first so a plain "hp stayed the same" pass can't fake
	# the "healed to new max" assertion below.
	server.request_attack("puncher", "player", 1.0)
	assert_lt(server.get_hp("player"), server.get_max_hp("player"), "sanity: player took damage")

	var monster_data: Dictionary = _register_slime(server, "slime_1")
	server.request_attack("player", "slime_1", 1.0)
	assert_eq(server.get_level("player"), 1.0, "one slime's xp is not enough to level up (12 < 16)")

	_register_slime(server, "slime_2")
	watch_signals(server)
	server.request_attack("player", "slime_2", 1.0)

	assert_eq(server.get_level("player"), 2.0, "two slimes' xp (24) crosses the level-2 threshold (16)")
	assert_signal_emitted(server, "level_up")

	var stim: Dictionary = RulesBalanceData.CLASSES.archetypes.stim
	var expected_attack: float = RulesProgression.attack_at_level(stim, stim.growth, 2.0)
	var expected_defense: float = RulesProgression.defense_at_level(stim, stim.growth, 2.0)
	var expected_max_hp: float = RulesProgression.hp_at_level(stim, stim.growth, 2.0)

	var stats: Dictionary = server.get_stats("player")
	assert_eq(stats.attack, expected_attack, "attack recomputed via RulesProgression at the new level")
	assert_eq(stats.defense, expected_defense, "defense recomputed via RulesProgression at the new level")
	assert_eq(stats.max_hp, expected_max_hp, "max_hp recomputed via RulesProgression at the new level")
	assert_eq(stats.hp, expected_max_hp, "leveling up heals to the new max hp (phase-0 default)")
	assert_signal_emitted_with_parameters(server, "level_up", ["player", 2.0, stats])


func test_xp_granted_only_to_the_killer() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")
	server.register("bystander", {"level": 1.0}, "stim")
	_register_slime(server, "slime")
	watch_signals(server)

	server.request_attack("player", "slime", 1.0)

	assert_gt(server.get_total_xp("player"), 0.0, "the killer gained xp")
	assert_eq(server.get_total_xp("bystander"), 0.0, "an entity that never attacked gains nothing")
	assert_signal_emit_count(server, "xp_gained", 1, "xp_gained fires exactly once, for the killer only")


func test_monster_kills_never_grant_xp_to_monsters() -> void:
	var server: LocalServer = _server()
	server.register("attacker_monster", {"attack": 1000.0, "defense": 0.0, "level": 5.0, "hp": 100.0})
	server.register("victim_monster", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 1.0})
	watch_signals(server)

	server.request_attack("attacker_monster", "victim_monster", 1.0)

	assert_false(server.is_alive("victim_monster"), "sanity: the monster died")
	assert_signal_not_emitted(server, "xp_gained", "a monster killer never has progression, so it never gains xp")
	assert_eq(server.get_total_xp("attacker_monster"), 0.0)


## T-0.10: set_progress() is the save-system's restore path (see
## LocalServer.set_progress's doc comment) — it must recompute level/stats
## from a saved cumulative total_xp WITHOUT emitting level_up, unlike the
## live xp-grant path exercised above.
func test_set_progress_restores_level_and_stats_without_emitting_level_up() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")
	watch_signals(server)

	var target_level: float = 3.0
	var saved_total_xp: float = RulesXp.xp_total_for_level(target_level)
	server.set_progress("player", saved_total_xp)

	assert_signal_not_emitted(server, "level_up", "set_progress is a silent restore, not a live level-up")
	assert_eq(server.get_level("player"), target_level)
	assert_eq(server.get_total_xp("player"), saved_total_xp)

	var stim: Dictionary = RulesBalanceData.CLASSES.archetypes.stim
	var stats: Dictionary = server.get_stats("player")
	assert_eq(
		stats.attack, RulesProgression.attack_at_level(stim, stim.growth, target_level), "attack recomputed at the restored level"
	)
	assert_eq(
		stats.defense, RulesProgression.defense_at_level(stim, stim.growth, target_level), "defense recomputed at the restored level"
	)
	assert_eq(
		stats.max_hp, RulesProgression.hp_at_level(stim, stim.growth, target_level), "max_hp recomputed at the restored level"
	)


## QA: set_progress must not silently do nothing for an id that was never
## registered, nor crash — and it's a no-op for entities without a
## progression archetype (monsters never call it, but stay defensive).
func test_set_progress_is_a_safe_no_op_for_unknown_or_non_progression_ids() -> void:
	var server: LocalServer = _server()
	server.register("monster", {"attack": 1.0, "defense": 0.0, "level": 1.0, "hp": 10.0})

	server.set_progress("ghost", 999.0)
	server.set_progress("monster", 999.0)

	assert_eq(server.get_total_xp("monster"), 0.0, "a non-progression entity's xp is untouched")
	assert_eq(server.get_level("monster"), 1.0)
