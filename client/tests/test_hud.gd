extends GutTest
## T-0.10 DoD: Hud (client/scripts/ui/hud.gd) only DISPLAYS what LocalServer
## reports — never computes hp/xp/stats itself. These tests drive a
## LocalServer directly and assert the HUD's bars/labels/panel follow it.


func _hud() -> Hud:
	var packed: PackedScene = load("res://scenes/ui/hud.tscn")
	return add_child_autofree(packed.instantiate())


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


func test_bind_reflects_get_stats_immediately() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")
	var hud: Hud = _hud()

	hud.bind(server, "player")

	var stats: Dictionary = server.get_stats("player")
	assert_eq(hud.hp_bar.value, stats.hp)
	assert_eq(hud.hp_bar.max_value, stats.max_hp)


func test_hp_bar_reflects_get_stats_after_damage() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")
	server.register("puncher", {"attack": 5.0, "defense": 0.0, "level": 1.0, "hp": 100.0})
	var hud: Hud = _hud()
	hud.bind(server, "player")

	server.request_attack("puncher", "player", 1.0)

	assert_eq(hud.hp_bar.value, server.get_hp("player"))
	assert_lt(hud.hp_bar.value, hud.hp_bar.max_value, "sanity: the hit actually landed")


func test_xp_bar_and_level_label_reflect_get_stats_after_a_kill() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")
	var monster_data: Dictionary = _register_slime(server, "slime")
	var hud: Hud = _hud()
	hud.bind(server, "player")

	server.request_attack("player", "slime", 1.0)

	var level: float = server.get_level("player")
	var expected_into: float = RulesProgression.xp_into_level(server.get_total_xp("player"), level)
	assert_eq(hud.xp_bar.value, expected_into)
	assert_gt(hud.xp_bar.value, 0.0, "sanity: xp was actually granted")
	assert_true(
		hud.xp_label.text.contains(str(int(level))), "level label shows the current level (%s)" % hud.xp_label.text
	)


func test_level_label_updates_and_flash_shows_on_level_up() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")
	var hud: Hud = _hud()
	hud.bind(server, "player")
	assert_false(hud.level_up_label.visible, "no flash before any level-up")

	# Kill enough slimes to cross the level-2 xp threshold, via the normal
	# grant path (request_attack), never via set_progress (which is a silent
	# restore and must NOT flash).
	var xp_needed: float = RulesXp.xp_for_level(2.0)
	var monster_data: Dictionary = RulesBalanceData.MONSTERS.monsters["side_effect_slime"]
	var kills: int = int(ceil(xp_needed / float(monster_data.xp)))
	for i in range(kills):
		_register_slime(server, "slime_%d" % i)
		server.request_attack("player", "slime_%d" % i, 1.0)

	assert_eq(server.get_level("player"), 2.0, "sanity: leveled up")
	assert_true(hud.level_up_label.visible, "level-up flash is showing")
	assert_true(hud.xp_label.text.contains("2"), "level label updated to the new level")
	assert_true(hud.level_detail.text.contains("2"), "stats panel level row updated to the new level")


func test_level_up_flash_hides_itself_after_the_timer() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")
	var hud: Hud = _hud()
	hud.bind(server, "player")

	hud._on_level_up("player", 2.0, server.get_stats("player"))
	assert_true(hud.level_up_label.visible)

	hud.level_up_timer.timeout.emit()
	assert_false(hud.level_up_label.visible, "the flash hides itself once the timer fires")


func test_stats_panel_toggles() -> void:
	var hud: Hud = _hud()
	assert_false(hud.is_stats_panel_open(), "collapsed by default")

	hud.stats_toggle.toggled.emit(true)
	assert_true(hud.is_stats_panel_open())

	hud.stats_toggle.toggled.emit(false)
	assert_false(hud.is_stats_panel_open())


func test_stats_panel_lists_level_hp_attack_defense_and_xp() -> void:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")
	var hud: Hud = _hud()
	hud.bind(server, "player")

	var stats: Dictionary = server.get_stats("player")
	assert_true(hud.level_detail.text.contains(str(int(stats.level))))
	assert_true(hud.hp_detail.text.contains(str(int(stats.hp))))
	assert_true(hud.attack_detail.text.contains(str(int(stats.attack))))
	assert_true(hud.defense_detail.text.contains(str(int(stats.defense))))
