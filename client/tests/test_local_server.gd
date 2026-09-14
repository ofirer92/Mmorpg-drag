extends GutTest
## T-0.8/T-0.9 DoD: LocalServer (client/scripts/combat/local_server.gd) is the
## only place client-side that calls RulesCombat/RulesLoot/RulesStatus.
## These tests drive it directly (no Player/Monster nodes) and predict its
## seeded RNG rolls with a second RandomNumberGenerator using the same seed.

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


func test_damage_applied_equals_rules_combat_for_seeded_roll() -> void:
	var server: LocalServer = _server()
	server.seed_rng(42)
	var rolls: Array[float] = _predict_rolls(42, 1)

	var attacker_stats: Dictionary = {"attack": 20.0, "defense": 2.0, "level": 3.0, "hp": 100.0}
	var defender_stats: Dictionary = {"attack": 5.0, "defense": 3.0, "level": 2.0, "hp": 50.0}
	server.register("a", attacker_stats)
	server.register("b", defender_stats)
	watch_signals(server)

	server.request_attack("a", "b", 1.0)

	var expected_dmg: float = RulesCombat.damage(attacker_stats, defender_stats, 1.0, rolls[0])
	var expected_hp: float = RulesCombat.apply_damage(50.0, expected_dmg)
	var expected_crit: bool = rolls[0] < RulesConstants.CRIT_CHANCE
	assert_signal_emitted_with_parameters(
		server, "damage_dealt", ["b", expected_dmg, expected_hp, expected_crit]
	)
	assert_eq(server.get_hp("b"), expected_hp, "LocalServer's own hp matches the applied damage")


func test_hp_never_goes_below_zero() -> void:
	var server: LocalServer = _server()
	server.register("a", {"attack": 1000.0, "defense": 0.0, "level": 10.0, "hp": 100.0})
	server.register("b", {"attack": 1.0, "defense": 0.0, "level": 1.0, "hp": 5.0})
	server.request_attack("a", "b", 1.0)
	assert_eq(server.get_hp("b"), 0.0, "massive overkill still clamps to exactly 0")
	assert_false(server.is_alive("b"))


func test_entity_died_emitted_once_with_xp_and_matching_drop() -> void:
	var server: LocalServer = _server()
	server.seed_rng(7)
	var rolls: Array[float] = _predict_rolls(7, 2)

	var monster_data: Dictionary = RulesBalanceData.MONSTERS.monsters["side_effect_slime"]
	var attacker_stats: Dictionary = {"attack": 50.0, "defense": 0.0, "level": 5.0, "hp": 100.0}
	var defender_stats: Dictionary = {
		"attack": monster_data.attack, "defense": monster_data.defense, "level": monster_data.level, "hp": 0.0
	}
	# One-hit kill: give the defender exactly the hp the seeded first roll deals.
	var one_hit_dmg: float = RulesCombat.damage(attacker_stats, defender_stats, 1.0, rolls[0])
	defender_stats.hp = one_hit_dmg

	server.register("attacker", attacker_stats)
	server.register(
		"monster",
		{
			"attack": monster_data.attack,
			"defense": monster_data.defense,
			"level": monster_data.level,
			"hp": one_hit_dmg,
			"xp": monster_data.xp,
			"loot_table": monster_data.loot_table,
		}
	)
	watch_signals(server)

	server.request_attack("attacker", "monster", 1.0)

	assert_signal_emit_count(server, "entity_died", 1, "entity_died fires exactly once")
	var expected_drop: String = RulesLoot.roll_loot(monster_data.loot_table, rolls[1])
	assert_signal_emitted_with_parameters(
		server, "entity_died", ["monster", float(monster_data.xp), expected_drop]
	)
	assert_false(server.is_alive("monster"))


func test_dead_attacker_cannot_land_a_hit() -> void:
	var server: LocalServer = _server()
	server.register("attacker", {"attack": 1.0, "defense": 0.0, "level": 1.0, "hp": 1.0})
	server.register("killer", {"attack": 1000.0, "defense": 0.0, "level": 1.0, "hp": 100.0})
	server.register("victim", {"attack": 1.0, "defense": 0.0, "level": 1.0, "hp": 100.0})
	server.request_attack("killer", "attacker", 1.0)
	assert_false(server.is_alive("attacker"), "sanity: attacker is dead")

	watch_signals(server)
	server.request_attack("attacker", "victim", 1.0)
	assert_signal_not_emitted(server, "damage_dealt", "a dead attacker cannot land a hit")
	assert_eq(server.get_hp("victim"), 100.0, "victim's hp is untouched")


func test_attacks_on_dead_targets_are_ignored() -> void:
	var server: LocalServer = _server()
	server.register("killer", {"attack": 1000.0, "defense": 0.0, "level": 1.0, "hp": 100.0})
	server.register("victim", {"attack": 1.0, "defense": 0.0, "level": 1.0, "hp": 1.0})
	server.request_attack("killer", "victim", 1.0)
	assert_false(server.is_alive("victim"), "sanity: victim is dead")

	watch_signals(server)
	server.request_attack("killer", "victim", 1.0)
	assert_signal_not_emitted(server, "damage_dealt", "attacking an already-dead target is a no-op")
	assert_eq(server.get_hp("victim"), 0.0, "hp stays at 0, never negative")


func test_four_consecutive_landed_hits_trigger_crash_and_reset_counter() -> void:
	var server: LocalServer = _server()
	server.register("player", {"attack": 20.0, "defense": 0.0, "level": 1.0, "hp": 90.0, "archetype": "stim"})
	server.register("dummy", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 100000.0})
	watch_signals(server)

	var hits_needed: int = int(RulesBalanceData.CLASSES.archetypes.stim.mechanics.crash.hits_in_a_row)
	for i in range(hits_needed - 1):
		server.request_attack("player", "dummy", 1.0)
	assert_signal_not_emitted(server, "crash_started", "not yet at the trigger count")
	assert_eq(server.get_consecutive_hits("player"), float(hits_needed - 1))

	server.request_attack("player", "dummy", 1.0)
	assert_signal_emitted_with_parameters(
		server, "crash_started", ["player", RulesStatus.crash_duration_s()]
	)
	assert_eq(server.get_consecutive_hits("player"), 0.0, "counter resets on trigger")
	assert_true(server.is_crashed("player"))


func test_damage_taken_while_crashed_uses_damage_taken_multiplier() -> void:
	var server: LocalServer = _server()
	server.register("player", {"attack": 20.0, "defense": 0.0, "level": 1.0, "hp": 90.0, "archetype": "stim"})
	server.register("dummy", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 100000.0})
	server.register("monster", {"attack": 10.0, "defense": 0.0, "level": 1.0, "hp": 100.0})

	var hits_needed: int = int(RulesBalanceData.CLASSES.archetypes.stim.mechanics.crash.hits_in_a_row)
	for i in range(hits_needed):
		server.request_attack("player", "dummy", 1.0)
	assert_true(server.is_crashed("player"), "sanity: player is crashed")

	server.seed_rng(11)
	var rolls: Array[float] = _predict_rolls(11, 1)
	var hp_before: float = server.get_hp("player")
	var raw_dmg: float = RulesCombat.damage(
		{"attack": 10.0, "defense": 0.0, "level": 1.0, "hp": 100.0},
		{"attack": 20.0, "defense": 0.0, "level": 1.0, "hp": hp_before},
		1.0,
		rolls[0]
	)
	var expected_dmg: float = RulesStatus.damage_taken(raw_dmg, true)

	watch_signals(server)
	server.request_attack("monster", "player", 1.0)

	assert_signal_emitted_with_parameters(
		server,
		"damage_dealt",
		["player", expected_dmg, hp_before - expected_dmg, rolls[0] < RulesConstants.CRIT_CHANCE]
	)


func test_crash_ends_after_crash_duration_s() -> void:
	var server: LocalServer = _server()
	server.register("player", {"attack": 20.0, "defense": 0.0, "level": 1.0, "hp": 90.0, "archetype": "stim"})
	server.register("dummy", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 100000.0})

	var hits_needed: int = int(RulesBalanceData.CLASSES.archetypes.stim.mechanics.crash.hits_in_a_row)
	for i in range(hits_needed):
		server.request_attack("player", "dummy", 1.0)
	assert_true(server.is_crashed("player"))

	watch_signals(server)
	var duration: float = RulesStatus.crash_duration_s()
	var frames: int = int(duration / DELTA) + 2
	simulate(server, frames, DELTA)

	assert_signal_emitted(server, "crash_ended")
	assert_false(server.is_crashed("player"))


# QA (independent review): an entity must not be able to damage itself, and hp/counters stay untouched.
func test_self_attack_is_ignored() -> void:
	var server: LocalServer = _server()
	server.register("a", {"attack": 1000.0, "defense": 0.0, "level": 1.0, "hp": 50.0})
	watch_signals(server)
	server.request_attack("a", "a", 1.0)
	assert_signal_not_emitted(server, "damage_dealt")
	assert_signal_not_emitted(server, "entity_died")
	assert_eq(server.get_hp("a"), 50.0)


# QA: an unregistered target id is a no-op, never an error.
func test_unknown_ids_are_ignored() -> void:
	var server: LocalServer = _server()
	server.register("a", {"attack": 10.0, "defense": 0.0, "level": 1.0, "hp": 50.0})
	watch_signals(server)
	server.request_attack("a", "ghost", 1.0)
	server.request_attack("ghost", "a", 1.0)
	assert_signal_not_emitted(server, "damage_dealt")
	assert_eq(server.get_hp("a"), 50.0)
