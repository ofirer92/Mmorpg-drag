class_name PlayerCamera
extends Camera2D
## T-0.4: follows the player with a deadzone (Camera2D drag margins) and stays
## inside the current map's bounds (Camera2D limits). No game logic here.

## Deadzone box size as a fraction of the half-viewport, Godot's own drag_*_margin units.
const DEADZONE_MARGIN: float = 0.15

## Reserved band at the bottom of the (portrait) screen that the bottom HUD covers: the virtual
## joystick and action buttons (client/scenes/ui/touch_controls.tscn, 136px up from the bottom) and
## the skill bar sitting in the strip above them (client/scenes/ui/skill_bar.tscn, 206px). The
## camera may scroll this far PAST the map's bottom edge, which keeps a player standing on the
## ground row above that HUD instead of hidden behind it. It only shows empty background, and only
## on a map tall enough for the bottom limit to bind at all — on the old 640px-tall horizontal map
## the limits were smaller than the viewport, so this never came up.
## client/tests/test_map_clinic_lobby.gd re-measures the band from those scenes, so a HUD that grows
## fails the test rather than silently eating the play area.
const BOTTOM_UI_PADDING_PX: int = 206


func _ready() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = true
	drag_horizontal_enabled = true
	drag_vertical_enabled = true
	drag_left_margin = DEADZONE_MARGIN
	drag_right_margin = DEADZONE_MARGIN
	drag_top_margin = DEADZONE_MARGIN
	drag_bottom_margin = DEADZONE_MARGIN
	make_current()


## Called once the map is known (e.g. by FlatMap._ready()) — clamps the
## camera so it never shows outside the playable area.
func set_map_bounds(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.position.x + rect.size.x)
	limit_bottom = int(rect.position.y + rect.size.y) + BOTTOM_UI_PADDING_PX
