class_name FlatMap
extends Node2D
## T-0.1/T-0.4 test scene: one flat floor wide enough to walk (and walk off
## the edge of, for coyote-time), with the player spawned above it.
## Wires the player's camera to the map bounds so movement/camera tests can
## reuse a single ground truth for the floor's position.

const FLOOR_TOP_Y: float = 700.0
const FLOOR_LEFT_X: float = 0.0
const FLOOR_RIGHT_X: float = 2400.0
const MAP_TOP_Y: float = -400.0
const MAP_BOTTOM_Y: float = 900.0

@onready var player: Player = $Player


func _ready() -> void:
	var cam: PlayerCamera = player.get_node("PlayerCamera")
	cam.set_map_bounds(get_map_bounds())


func get_map_bounds() -> Rect2:
	return Rect2(
		Vector2(FLOOR_LEFT_X, MAP_TOP_Y), Vector2(FLOOR_RIGHT_X - FLOOR_LEFT_X, MAP_BOTTOM_Y - MAP_TOP_Y)
	)
