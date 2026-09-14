class_name ClinicLobby
extends Node2D
## T-0.3: the phase-0 prototype map. A single TileMapLayer (Godot 4.3 —
## TileMap itself is deprecated) built procedurally from LAYOUT, a compact
## 20-rows × 60-cols description ('#' ground, '=' platform, 'W' wall, 'A'
## decorative accent, '.' empty air). Ground + platform + wall tiles carry
## collision (see client/tools/gen_tileset_resource.gd); the platform step
## sizes below were chosen against RulesMovement so every platform is
## reachable with a single jump (max jump height ≈ v²/2g ≈ 75px — see
## client/tests/test_map_clinic_lobby.gd for the "reachable in principle"
## check on this array).

const GRID_COLS: int = 60
const GRID_ROWS: int = 20
const TILE_SIZE: int = 32

## Atlas column order — must match docs/art/specs/tileset_clinic.yaml `tiles:`
## and client/tools/gen_tileset_resource.gd TILE_NAMES.
const ATLAS_COORDS: Dictionary = {
	"ground": Vector2i(0, 0),
	"ground_top": Vector2i(1, 0),
	"platform": Vector2i(2, 0),
	"wall": Vector2i(3, 0),
	"background": Vector2i(4, 0),
	"accent": Vector2i(5, 0),
}

## Layout char → tile name. Empty ('.') cells get no cell at all.
const CHAR_TO_TILE: Dictionary = {
	"#": "ground_top",
	"=": "platform",
	"W": "wall",
	"A": "accent",
}

## 20 rows × 60 columns. Row 0 is the top of the map, row 19 is the ground.
## Walls run the full height at both ends; 8 floating platforms step up from
## the ground and back down again, each ≤ 2 rows (64px) above its nearest
## lower neighbour and ≤ 5 columns (160px) away horizontally.
const LAYOUT: Array[String] = [
	"W..........................................................W",
	"W..........................................................W",
	"W............................AA............................W",
	"W..........................................................W",
	"W..........................................................W",
	"W..........................................................W",
	"W..........................................................W",
	"W..........................................................W",
	"W..........................................................W",
	"W..........................................................W",
	"W..........................................................W",
	"W..................====....................................W",
	"W..........................................................W",
	"W.............====.......====..............................W",
	"W..........................................................W",
	"W........====.................====.........................W",
	"W..........................................................W",
	"W...====...........................====...====.............W",
	"W..........................................................W",
	"W##########################################################W",
]

@onready var tile_layer: TileMapLayer = $TileMapLayer
@onready var spawn: Marker2D = $Spawn
@onready var player: Player = $Player


func _ready() -> void:
	_build_tiles()
	player.global_position = spawn.global_position
	var cam: PlayerCamera = player.get_node("PlayerCamera")
	cam.set_map_bounds(get_bounds())


func _build_tiles() -> void:
	for row: int in range(LAYOUT.size()):
		var line: String = LAYOUT[row]
		for col: int in range(line.length()):
			var ch: String = line[col]
			if not CHAR_TO_TILE.has(ch):
				continue
			var tile_name: String = CHAR_TO_TILE[ch]
			tile_layer.set_cell(Vector2i(col, row), 0, ATLAS_COORDS[tile_name])


## The playable rectangle in pixels, used by PlayerCamera.set_map_bounds().
func get_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(GRID_COLS * TILE_SIZE, GRID_ROWS * TILE_SIZE))
