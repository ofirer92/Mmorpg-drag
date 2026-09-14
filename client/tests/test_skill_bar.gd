extends GutTest
## T-0.7 DoD: SkillBar (client/scripts/ui/skill_bar.gd) only DISPLAYS what
## LocalServer/RulesSkills report — one button per Stim skill, locked ones
## disabled with the "locked until level" text, a cooldown countdown label,
## and tapping an unlocked button selects it as Player.selected_skill_id.


func _server() -> LocalServer:
	return add_child_autofree(LocalServer.new())


func _player(server: LocalServer) -> Player:
	var packed: PackedScene = load("res://scenes/player/player.tscn")
	var p: Player = packed.instantiate()
	add_child_autofree(p)
	p.set_local_server(server)
	return p


func _bar() -> SkillBar:
	var packed: PackedScene = load("res://scenes/ui/skill_bar.tscn")
	return add_child_autofree(packed.instantiate())


func _skill(index: int) -> Dictionary:
	return RulesBalanceData.CLASSES.archetypes.stim.skills[index]


func test_has_one_button_per_skill() -> void:
	var server: LocalServer = _server()
	var player: Player = _player(server)
	var bar: SkillBar = _bar()
	bar.bind(server, player)

	var skills: Array = RulesBalanceData.CLASSES.archetypes.stim.skills
	assert_eq(bar.buttons.size(), skills.size(), "one button per archetypes.stim.skills entry")
	assert_eq(bar.status_labels.size(), skills.size())
	for i in range(skills.size()):
		assert_eq(bar.skill_ids[i], String(skills[i].id))
		assert_eq(bar.buttons[i].text, I18n.t(String(skills[i].name_key)))


func test_locked_skills_are_disabled_with_the_level_text() -> void:
	var server: LocalServer = _server()
	var player: Player = _player(server)
	var bar: SkillBar = _bar()
	bar.bind(server, player)

	# Level 1: only skills[0] (level 1) is unlocked; the rest are locked.
	assert_false(bar.buttons[0].disabled, "the basic skill is always unlocked")
	for i in range(1, bar.buttons.size()):
		var skill: Dictionary = _skill(i)
		assert_true(bar.buttons[i].disabled, "skill %s needs level %s" % [skill.id, skill.level])
		var expected_text: String = I18n.t("ui.skills.locked") % int(skill.level)
		assert_eq(bar.status_labels[i].text, expected_text)


func test_leveling_up_unlocks_a_button() -> void:
	var server: LocalServer = _server()
	var player: Player = _player(server)
	var bar: SkillBar = _bar()
	bar.bind(server, player)
	var double_dose: Dictionary = _skill(1)
	assert_true(bar.buttons[1].disabled, "sanity: locked at level 1")

	server.set_progress(Player.ENTITY_ID, RulesXp.xp_total_for_level(float(double_dose.level)))
	bar.refresh()

	assert_false(bar.buttons[1].disabled, "unlocked once the player reaches the skill's level")
	assert_eq(bar.status_labels[1].text, "", "no locked text once unlocked")


func test_selecting_an_unlocked_skill_updates_player_selected_skill_id() -> void:
	var server: LocalServer = _server()
	var player: Player = _player(server)
	var bar: SkillBar = _bar()
	bar.bind(server, player)
	var paper_cut: Dictionary = _skill(2)
	server.set_progress(Player.ENTITY_ID, RulesXp.xp_total_for_level(float(paper_cut.level)))
	bar.refresh()

	bar.buttons[2].pressed.emit()

	assert_eq(player.selected_skill_id, "stim_paper_cut")
	assert_true(bar.buttons[2].button_pressed, "the selected button shows as pressed/highlighted")


func test_selecting_a_locked_skill_is_a_no_op() -> void:
	var server: LocalServer = _server()
	var player: Player = _player(server)
	var bar: SkillBar = _bar()
	bar.bind(server, player)
	var before: String = player.selected_skill_id

	bar.buttons[4].pressed.emit()

	assert_eq(player.selected_skill_id, before, "level 10 skill isn't unlocked at level 1")


func test_cooldown_label_shows_seconds_left_after_a_use() -> void:
	var server: LocalServer = _server()
	var player: Player = _player(server)
	var bar: SkillBar = _bar()
	var double_dose: Dictionary = _skill(1)
	server.set_progress(Player.ENTITY_ID, RulesXp.xp_total_for_level(float(double_dose.level)))
	server.register("dummy", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 1000000.0})
	bar.bind(server, player)
	bar.refresh()
	assert_eq(bar.status_labels[1].text, "", "ready, no cooldown text yet")

	server.request_skill(Player.ENTITY_ID, ["dummy"], "stim_double_dose")
	bar.refresh()

	var left: float = server.skill_cooldown_left(Player.ENTITY_ID, "stim_double_dose")
	assert_gt(left, 0.0, "sanity: on cooldown now")
	assert_eq(bar.status_labels[1].text, "%.1f" % left)
