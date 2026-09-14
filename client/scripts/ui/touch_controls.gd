class_name TouchControls
extends CanvasLayer
## T-0.5: mobile controls — a horizontal VirtualJoystick (left) plus jump /
## attack / skill_1 buttons and an auto-attack toggle (right).
##
## Wiring choice: this feeds the Player ONLY through Input.action_press /
## Input.action_release on the existing InputMap actions (move_left,
## move_right, jump, attack, skill_1) — never a direct call to
## player.set_input(). That keeps this scene fully decoupled: any scene with
## a Player using real input (client/scripts/player/player.gd's
## _read_real_input()) works with this CanvasLayer added as a sibling, no
## wiring code needed in main.gd.

signal auto_attack_toggled(enabled: bool)

## Force the controls visible even when DisplayServer.is_touchscreen_available()
## is false — used by GUT tests and desktop screenshots. Real touch devices
## never need this set.
@export var force_visible: bool = false

@onready var joystick: VirtualJoystick = $Joystick
@onready var jump_button: Button = $ActionButtons/JumpButton
@onready var attack_button: Button = $ActionButtons/AttackButton
@onready var skill_button: Button = $ActionButtons/SkillButton
@onready var auto_attack_toggle: CheckButton = $AutoAttackToggle

var _move_left_pressed: bool = false
var _move_right_pressed: bool = false


func _ready() -> void:
	visible = force_visible or DisplayServer.is_touchscreen_available()

	jump_button.text = I18n.t("ui.touch.jump")
	attack_button.text = I18n.t("ui.touch.attack")
	skill_button.text = I18n.t("ui.touch.skill")
	auto_attack_toggle.text = I18n.t("ui.touch.auto_attack")

	joystick.direction_changed.connect(_on_joystick_direction_changed)
	jump_button.button_down.connect(_on_jump_down)
	jump_button.button_up.connect(_on_jump_up)
	attack_button.button_down.connect(_on_attack_down)
	attack_button.button_up.connect(_on_attack_up)
	skill_button.button_down.connect(_on_skill_down)
	skill_button.button_up.connect(_on_skill_up)
	auto_attack_toggle.toggled.connect(_on_auto_attack_toggled)


func _on_joystick_direction_changed(dir: float) -> void:
	_set_action_held("move_left", dir < 0.0, "_move_left_pressed")
	_set_action_held("move_right", dir > 0.0, "_move_right_pressed")


func _set_action_held(action: StringName, want_pressed: bool, field: String) -> void:
	if get(field) == want_pressed:
		return
	set(field, want_pressed)
	if want_pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _on_jump_down() -> void:
	Input.action_press(&"jump")


func _on_jump_up() -> void:
	Input.action_release(&"jump")


func _on_attack_down() -> void:
	Input.action_press(&"attack")


func _on_attack_up() -> void:
	Input.action_release(&"attack")


func _on_skill_down() -> void:
	Input.action_press(&"skill_1")


func _on_skill_up() -> void:
	Input.action_release(&"skill_1")


func _on_auto_attack_toggled(enabled: bool) -> void:
	auto_attack_toggled.emit(enabled)
