class_name VirtualJoystick
extends Control
## T-0.5: a left-side horizontal-only drag joystick. Emits direction_changed
## with a QUANTIZED -1.0 / 0.0 / 1.0 (not a continuous value) because the
## Player reads horizontal input from Input.get_axis("move_left",
## "move_right") — two digital actions, not an analog axis — so touch_controls.gd
## maps this straight onto action_press/action_release for those actions.

signal direction_changed(dir: float)

## Drag distance below this fraction of RADIUS_PX counts as centered (dir 0.0).
const DEADZONE: float = 0.25
const RADIUS_PX: float = 60.0

@onready var knob: Control = $Knob

var _dragging: bool = false
var _direction: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_center_knob()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_dragging = true
			apply_horizontal_offset(touch.position.x - size.x / 2.0)
		else:
			_dragging = false
			end_drag()
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				apply_horizontal_offset(mb.position.x - size.x / 2.0)
			else:
				_dragging = false
				end_drag()
	elif event is InputEventScreenDrag and _dragging:
		var drag: InputEventScreenDrag = event
		apply_horizontal_offset(drag.position.x - size.x / 2.0)
	elif event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event
		apply_horizontal_offset(motion.position.x - size.x / 2.0)


## Test/real-input hook: horizontal offset in px from the joystick's center.
func apply_horizontal_offset(offset_px: float) -> void:
	var clamped: float = clampf(offset_px, -RADIUS_PX, RADIUS_PX)
	knob.position = Vector2(size.x / 2.0 + clamped, size.y / 2.0) - knob.size / 2.0
	var normalised: float = clamped / RADIUS_PX
	var new_dir: float = 0.0
	if absf(normalised) >= DEADZONE:
		new_dir = signf(normalised)
	_set_direction(new_dir)


## Test/real-input hook: release the joystick, snapping the knob back to
## center and the direction back to 0.
func end_drag() -> void:
	_dragging = false
	_center_knob()
	_set_direction(0.0)


func _center_knob() -> void:
	knob.position = size / 2.0 - knob.size / 2.0


func _set_direction(dir: float) -> void:
	if is_equal_approx(dir, _direction):
		return
	_direction = dir
	direction_changed.emit(dir)
