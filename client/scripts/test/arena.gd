class_name Arena
extends Node2D
## T-0.9 DoD scene: a flat floor with a LocalServer, the Player and the 3
## monster types (patrol/chase/patrol per docs/balance/monsters.yaml) placed
## along it, all wired together. Manual/visual testing + screenshot target —
## GUT tests build their own minimal LocalServer/Monster setups directly.

const FLOOR_TOP_Y: float = 700.0
const FLOOR_LEFT_X: float = 0.0
const FLOOR_RIGHT_X: float = 2400.0
const MAP_TOP_Y: float = -400.0
const MAP_BOTTOM_Y: float = 900.0

@onready var local_server: LocalServer = $LocalServer
@onready var player: Player = $Player
@onready var skill_bar: SkillBar = $SkillBar


func _ready() -> void:
	var cam: PlayerCamera = player.get_node("PlayerCamera")
	cam.set_map_bounds(get_map_bounds())
	player.set_local_server(local_server)
	skill_bar.bind(local_server, player)
	for child: Node in get_children():
		if child is Monster:
			(child as Monster).setup(local_server, player)


func get_map_bounds() -> Rect2:
	return Rect2(
		Vector2(FLOOR_LEFT_X, MAP_TOP_Y), Vector2(FLOOR_RIGHT_X - FLOOR_LEFT_X, MAP_BOTTOM_Y - MAP_TOP_Y)
	)
