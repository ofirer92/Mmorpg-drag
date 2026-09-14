extends GutTest
## T-0.5 DoD: joystick drag → -1/0/1 direction with a deadzone, buttons press
## the right Input actions, auto-attack toggle emits, and visibility follows
## DisplayServer.is_touchscreen_available() unless force_visible overrides it.


func _spawn(force_visible: bool = true) -> TouchControls:
	var packed: PackedScene = load("res://scenes/ui/touch_controls.tscn")
	var node: TouchControls = packed.instantiate()
	node.force_visible = force_visible
	add_child_autofree(node)
	return node


func _release_actions() -> void:
	for action: StringName in [&"move_left", &"move_right", &"jump", &"attack", &"skill_1"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)


func after_each() -> void:
	_release_actions()


func test_joystick_centered_drag_is_zero_within_deadzone() -> void:
	var tc: TouchControls = _spawn()
	watch_signals(tc.joystick)
	var inside: float = VirtualJoystick.DEADZONE * VirtualJoystick.RADIUS_PX * 0.5
	tc.joystick.apply_horizontal_offset(inside)
	assert_signal_not_emitted(tc.joystick, "direction_changed")


func test_joystick_drag_right_past_deadzone_is_one() -> void:
	var tc: TouchControls = _spawn()
	watch_signals(tc.joystick)
	tc.joystick.apply_horizontal_offset(VirtualJoystick.RADIUS_PX)
	assert_signal_emitted_with_parameters(tc.joystick, "direction_changed", [1.0])


func test_joystick_drag_left_past_deadzone_is_negative_one() -> void:
	var tc: TouchControls = _spawn()
	watch_signals(tc.joystick)
	tc.joystick.apply_horizontal_offset(-VirtualJoystick.RADIUS_PX)
	assert_signal_emitted_with_parameters(tc.joystick, "direction_changed", [-1.0])


func test_joystick_release_returns_to_zero() -> void:
	var tc: TouchControls = _spawn()
	tc.joystick.apply_horizontal_offset(VirtualJoystick.RADIUS_PX)
	watch_signals(tc.joystick)
	tc.joystick.end_drag()
	assert_signal_emitted_with_parameters(tc.joystick, "direction_changed", [0.0])


func test_joystick_drives_move_actions_through_touch_controls() -> void:
	var tc: TouchControls = _spawn()
	tc.joystick.apply_horizontal_offset(VirtualJoystick.RADIUS_PX)
	assert_true(Input.is_action_pressed("move_right"), "dragging right presses move_right")
	assert_false(Input.is_action_pressed("move_left"), "move_left stays released")
	tc.joystick.end_drag()
	assert_false(Input.is_action_pressed("move_right"), "releasing the joystick releases move_right")


func test_jump_button_presses_and_releases_jump_action() -> void:
	var tc: TouchControls = _spawn()
	tc.jump_button.button_down.emit()
	assert_true(Input.is_action_pressed("jump"))
	tc.jump_button.button_up.emit()
	assert_false(Input.is_action_pressed("jump"))


func test_attack_button_presses_and_releases_attack_action() -> void:
	var tc: TouchControls = _spawn()
	tc.attack_button.button_down.emit()
	assert_true(Input.is_action_pressed("attack"))
	tc.attack_button.button_up.emit()
	assert_false(Input.is_action_pressed("attack"))


func test_skill_button_presses_and_releases_skill_1_action() -> void:
	var tc: TouchControls = _spawn()
	tc.skill_button.button_down.emit()
	assert_true(Input.is_action_pressed("skill_1"))
	tc.skill_button.button_up.emit()
	assert_false(Input.is_action_pressed("skill_1"))


func test_auto_attack_toggle_emits_signal() -> void:
	var tc: TouchControls = _spawn()
	watch_signals(tc)
	tc.auto_attack_toggle.toggled.emit(true)
	assert_signal_emitted_with_parameters(tc, "auto_attack_toggled", [true])
	tc.auto_attack_toggle.toggled.emit(false)
	assert_signal_emitted_with_parameters(tc, "auto_attack_toggled", [false])


func test_hidden_by_default_when_no_touchscreen() -> void:
	var tc: TouchControls = _spawn(false)
	assert_eq(tc.visible, DisplayServer.is_touchscreen_available(), "visibility follows touchscreen availability")


func test_force_visible_overrides_touchscreen_detection() -> void:
	var tc: TouchControls = _spawn(true)
	assert_true(tc.visible, "force_visible always shows the controls")


func test_button_labels_come_from_i18n() -> void:
	var tc: TouchControls = _spawn()
	assert_eq(tc.jump_button.text, I18n.t("ui.touch.jump"))
	assert_eq(tc.attack_button.text, I18n.t("ui.touch.attack"))
	assert_eq(tc.skill_button.text, I18n.t("ui.touch.skill"))
	assert_eq(tc.auto_attack_toggle.text, I18n.t("ui.touch.auto_attack"))
