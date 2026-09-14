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

## T-0.10: monsters placed on the real map — id must match
## docs/balance/monsters.yaml, cell is a LAYOUT (col, row) grid coordinate
## that must be empty ('.') with a solid tile directly below it (row + 1),
## enforced by client/tests/test_map_clinic_lobby.gd. 3 ground-level
## side_effect_slime, 2 lost_referral near the mid platforms, 1 form_27b far
## to the right (see LAYOUT above for the platform columns).
const MONSTER_SPAWNS: Array[Dictionary] = [
	{"id": "side_effect_slime", "cell": Vector2i(10, 18)},
	{"id": "side_effect_slime", "cell": Vector2i(30, 18)},
	{"id": "side_effect_slime", "cell": Vector2i(50, 18)},
	{"id": "lost_referral", "cell": Vector2i(20, 10)},
	{"id": "lost_referral", "cell": Vector2i(15, 12)},
	{"id": "form_27b", "cell": Vector2i(55, 18)},
]

## Phase-0 default (see LocalServer.revive's doc comment for the "full hp,
## no penalty" part of this choice): seconds between the player's
## entity_died and the respawn-at-Spawn happening. Designer may want a
## death screen / longer delay / xp penalty later.
const RESPAWN_DELAY_S: float = 2.0

const MonsterScene: PackedScene = preload("res://scenes/monsters/monster.tscn")
const NpcScene: PackedScene = preload("res://scenes/npc/npc.tscn")

@onready var tile_layer: TileMapLayer = $TileMapLayer
@onready var spawn: Marker2D = $Spawn
@onready var player: Player = $Player
@onready var local_server: LocalServer = $LocalServer

## T-0.11: the player's bag. Set by main.gd (or a test) before drops appear; drops
## spawned into this scene by dying monsters are routed here on pickup.
var inventory: Inventory = null
## Emitted after a drop was picked up and added (or rejected when the bag is full).
signal item_picked_up(item_id: String, added: bool)

## T-0.12: NPCs live on this map (currently just the pharmacist), spawned in
## _ready() from RulesBalanceData.NPCS's `map_cell` (docs/balance/npcs.yaml)
## so the spawn point can never drift from the balance data. See
## _spawn_npcs()/_cell_center() below — the same convention MONSTER_SPAWNS
## uses.
var npcs: Array[Npc] = []
## Re-emitted from whichever Npc the player interacted with; main.gd owns
## deciding what a given npc_id's dialogue/shop actually says.
signal npc_interact_requested(npc_id: String)


func _ready() -> void:
	child_entered_tree.connect(_on_child_entered_tree)
	_build_tiles()
	player.global_position = spawn.global_position
	var cam: PlayerCamera = player.get_node("PlayerCamera")
	cam.set_map_bounds(get_bounds())

	player.set_local_server(local_server)
	_spawn_monsters()
	_spawn_npcs()
	local_server.entity_died.connect(_on_entity_died)


func _spawn_monsters() -> void:
	for entry: Dictionary in MONSTER_SPAWNS:
		var monster: Monster = MonsterScene.instantiate()
		monster.monster_id = String(entry.id)
		monster.position = _cell_center(entry.cell)
		add_child(monster)
		monster.setup(local_server, player)


func _spawn_npcs() -> void:
	var all_npcs: Dictionary = RulesBalanceData.NPCS.get("npcs", {})
	for npc_id: String in all_npcs.keys():
		var def: Dictionary = all_npcs[npc_id]
		var cell_arr: Array = def.get("map_cell", [0, 0])
		var cell: Vector2i = Vector2i(int(cell_arr[0]), int(cell_arr[1]))
		var npc: Npc = NpcScene.instantiate()
		npc.npc_id = npc_id
		npc.position = _cell_center(cell)
		add_child(npc)
		npc.interact_requested.connect(_on_npc_interact_requested)
		npcs.append(npc)


func _on_npc_interact_requested(npc_id: String) -> void:
	npc_interact_requested.emit(npc_id)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE_SIZE + TILE_SIZE / 2.0, cell.y * TILE_SIZE + TILE_SIZE / 2.0)


## T-0.10 phase-0 default: the player always respawns at Spawn, full hp,
## after a flat delay — see MONSTER_SPAWNS/RESPAWN_DELAY_S doc comments and
## LocalServer.revive(). Monster deaths are handled entirely inside
## monster.gd (drop + queue_free), so this only reacts to the PLAYER dying.
func _on_entity_died(id: String, _xp: float, _drop_item_id: String) -> void:
	if id != Player.ENTITY_ID:
		return
	await get_tree().create_timer(RESPAWN_DELAY_S).timeout
	local_server.revive(Player.ENTITY_ID)
	player.global_position = spawn.global_position
	player.respawn()


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


func _on_child_entered_tree(node: Node) -> void:
	if node is Drop:
		var drop: Drop = node
		drop.picked_up.connect(_on_drop_picked_up)


func _on_drop_picked_up(item_id: String) -> void:
	var added: bool = inventory != null and inventory.add(item_id)
	item_picked_up.emit(item_id, added)


## T-0.13: where the player currently stands (saved) / put them back (loaded).
func get_player_position() -> Vector2:
	return player.global_position


func set_player_position(pos: Vector2) -> void:
	player.global_position = pos
	player.velocity = Vector2.ZERO
