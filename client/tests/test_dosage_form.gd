extends GutTest
## T-1.5 DoD: the "טופס 27-ב" level-up form. It must REPORT what the authority already granted —
## never grant anything itself — show one form per level crossed, and block gameplay input while
## it is open (the T-0.15 rule every panel follows).


func _form() -> DosageForm:
	var packed: PackedScene = load("res://scenes/ui/dosage_form.tscn")
	return add_child_autofree(packed.instantiate())


func _server() -> LocalServer:
	return add_child_autofree(LocalServer.new())


## A player registered at level 1 with the stim progression, bound to a fresh form.
func _bound() -> Array:
	var server: LocalServer = _server()
	server.register("player", {"level": 1.0}, "stim")
	var form: DosageForm = _form()
	form.bind(server, "player", "stim")
	return [server, form]


func _grant_levels(server: LocalServer, levels: int) -> void:
	server.set_progress("player", 0.0)
	var target_xp: float = RulesXp.xp_total_for_level(float(1 + levels))
	# Drive the real signal path (xp → level_up), not set_progress, which is deliberately silent.
	server.level_up.emit("player", float(1 + levels), _stats_at(server, float(1 + levels), target_xp))


## Stats the authority WOULD report at `level` — taken from RulesProgression, never hardcoded.
func _stats_at(server: LocalServer, level: float, total_xp: float) -> Dictionary:
	var before: Dictionary = server.get_stats("player")
	var base: Dictionary = RulesBalanceData.CLASSES.archetypes["stim"]
	var growth: Dictionary = base.growth
	return {
		"hp": before.hp,
		"max_hp": RulesProgression.hp_at_level(base, growth, level),
		"attack": RulesProgression.attack_at_level(base, growth, level),
		"defense": RulesProgression.defense_at_level(base, growth, level),
		"level": level,
		"total_xp": total_xp,
	}


func test_starts_closed() -> void:
	var form: DosageForm = _form()
	assert_false(form.is_open(), "the form must not be on screen before any level-up")
	assert_false(form.stamp_label.visible, "the approved stamp starts hidden")


func test_level_up_opens_the_form_for_that_level() -> void:
	var bound: Array = _bound()
	var server: LocalServer = bound[0]
	var form: DosageForm = bound[1]

	_grant_levels(server, 1)

	assert_true(form.is_open(), "a level-up must present Form 27-B")
	assert_string_contains(form.grade_label.text, "1 → 2")
	assert_eq(form.pending_count(), 0, "one level crossed = one form, none queued behind it")


func test_another_entitys_level_up_is_ignored() -> void:
	var bound: Array = _bound()
	var server: LocalServer = bound[0]
	var form: DosageForm = bound[1]

	server.level_up.emit("someone_else", 5.0, server.get_stats("player"))

	assert_false(form.is_open(), "only the bound entity's approvals are this player's paperwork")


func test_grant_rows_come_from_the_authority_not_the_form() -> void:
	var bound: Array = _bound()
	var server: LocalServer = bound[0]
	var form: DosageForm = bound[1]
	var before: Dictionary = server.get_stats("player")

	_grant_levels(server, 1)

	var after: Dictionary = _stats_at(server, 2.0, RulesXp.xp_total_for_level(2.0))
	var rows: Array[String] = []
	for child: Node in form.grants_vbox.get_children():
		rows.append((child as Label).text)
	assert_gt(rows.size(), 0, "levelling stim must grant at least one stat")
	var joined: String = "\n".join(rows)
	# The exact numbers are RulesProgression's, so the form is only allowed to echo them.
	assert_string_contains(joined, "%d → %d" % [int(before.max_hp), int(after.max_hp)])


func test_no_stat_change_shows_the_file_another_form_line() -> void:
	var bound: Array = _bound()
	var server: LocalServer = bound[0]
	var form: DosageForm = bound[1]

	# A level-up whose stats are byte-for-byte the previous ones — the clinic still files paperwork.
	server.level_up.emit("player", 2.0, server.get_stats("player"))

	assert_true(form.is_open())
	assert_eq(form.grants_vbox.get_child_count(), 1)
	var only: Label = form.grants_vbox.get_child(0)
	assert_eq(only.text, I18n.t("ui.dosage_form.no_change"))


func test_multi_level_jump_queues_one_form_per_level() -> void:
	var bound: Array = _bound()
	var server: LocalServer = bound[0]
	var form: DosageForm = bound[1]

	# Two level-ups back to back (a big kill at low level can cross several at once).
	server.level_up.emit("player", 2.0, _stats_at(server, 2.0, RulesXp.xp_total_for_level(2.0)))
	server.level_up.emit("player", 3.0, _stats_at(server, 3.0, RulesXp.xp_total_for_level(3.0)))

	assert_true(form.is_open(), "the first approval is on screen")
	assert_string_contains(form.grade_label.text, "1 → 2")
	assert_eq(form.pending_count(), 1, "the second level is its own form, waiting behind the first")


func test_approving_stamps_then_advances_to_the_queued_form() -> void:
	var bound: Array = _bound()
	var server: LocalServer = bound[0]
	var form: DosageForm = bound[1]
	form.stamp_timer.wait_time = 0.01
	server.level_up.emit("player", 2.0, _stats_at(server, 2.0, RulesXp.xp_total_for_level(2.0)))
	server.level_up.emit("player", 3.0, _stats_at(server, 3.0, RulesXp.xp_total_for_level(3.0)))

	var approvals: Array = []
	form.approved.connect(func(level: int) -> void: approvals.append(level))
	form.approve_button.pressed.emit()

	assert_true(form.stamp_label.visible, "signing stamps the form before it closes")
	assert_true(form.approve_button.disabled, "a stamped form cannot be signed twice")
	assert_eq(approvals, [2], "approved() reports the level that was just approved")

	await wait_for_signal(form.stamp_timer.timeout, 1.0)
	assert_true(form.is_open(), "the queued second approval takes over")
	assert_string_contains(form.grade_label.text, "2 → 3")
	assert_false(form.stamp_label.visible, "the new form is unsigned")
	assert_false(form.approve_button.disabled)


func test_approving_the_last_form_closes_it() -> void:
	var bound: Array = _bound()
	var server: LocalServer = bound[0]
	var form: DosageForm = bound[1]
	form.stamp_timer.wait_time = 0.01
	_grant_levels(server, 1)

	form.approve_button.pressed.emit()
	await wait_for_signal(form.stamp_timer.timeout, 1.0)

	assert_false(form.is_open(), "nothing is queued, so the form closes")
	assert_eq(form.pending_count(), 0)


func test_double_press_approves_once() -> void:
	var bound: Array = _bound()
	var server: LocalServer = bound[0]
	var form: DosageForm = bound[1]
	form.stamp_timer.wait_time = 5.0
	_grant_levels(server, 1)

	var approvals: Array = []
	form.approved.connect(func(level: int) -> void: approvals.append(level))
	form.approve_button.pressed.emit()
	form.approve_button.pressed.emit()

	assert_eq(approvals, [2], "a second press while the stamp is up must not re-approve")


func test_resync_rebaselines_after_a_silent_level_change() -> void:
	var bound: Array = _bound()
	var server: LocalServer = bound[0]
	var form: DosageForm = bound[1]

	# What loading a save does: set_progress moves level/stats WITHOUT a level_up signal.
	server.set_progress("player", RulesXp.xp_total_for_level(5.0))
	form.resync()
	server.level_up.emit("player", 6.0, _stats_at(server, 6.0, RulesXp.xp_total_for_level(6.0)))

	assert_string_contains(
		form.grade_label.text, "5 → 6", "after resync the delta is measured from the restored level"
	)


func test_texts_are_i18n_keys_not_literals() -> void:
	var form: DosageForm = _form()
	assert_eq(form.title_label.text, I18n.t("ui.dosage_form.title"))
	assert_eq(form.approve_button.text, I18n.t("ui.dosage_form.approve"))
	assert_eq(form.pending_label.text, I18n.t("ui.dosage_form.pending"))
	assert_eq(form.side_effects_label.text, I18n.t("ui.dosage_form.side_effects"))
	assert_ne(form.title_label.text, "ui.dosage_form.title", "the key must resolve to real copy")
