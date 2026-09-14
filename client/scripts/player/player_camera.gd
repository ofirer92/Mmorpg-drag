class_name PlayerCamera
extends Camera2D
## T-0.4: follows the player with a deadzone (Camera2D drag margins) and stays
## inside the current map's bounds (Camera2D limits). No game logic here.

## Deadzone box size as a fraction of the half-viewport, Godot's own drag_*_margin units.
const DEADZONE_MARGIN: float = 0.15


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
	limit_bottom = int(rect.position.y + rect.size.y)
