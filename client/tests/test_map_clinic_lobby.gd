extends GutTest
## T-0.3 DoD: a 60×20-tile TileMapLayer map with floating platforms, bounds,
## a spawn marker the player lands from, and every platform reachable with a
## single jump given RulesMovement's constants.

const DELTA: float = 1.0 / 60.0
const SOLID_CHARS: Array[String] = ["#", "=", "W"]
## Max vertical rows between a platform and a lower neighbour it can be
## jumped to from (2 rows × 32px = 64px, comfortably under the ≈75px max
## jump height derived from RulesMovement.JUMP_VELOCITY_PX / GRAVITY_PX).
const MAX_JUMP_ROWS: int = 2
## Max horizontal tile gap between two solid groups (5 tiles × 32px = 160px).
const MAX_GAP_COLS: int = 5


func _spawn_map() -> ClinicLobby:
	var packed: PackedScene = load("res://scenes/maps/clinic_lobby.tscn")
	var map: ClinicLobby = add_child_autofree(packed.instantiate())
	return map


func test_map_is_60x20_tiles() -> void:
	var map: ClinicLobby = _spawn_map()
	assert_eq(ClinicLobby.LAYOUT.size(), ClinicLobby.GRID_ROWS, "20 rows")
	for row: String in ClinicLobby.LAYOUT:
		assert_eq(row.length(), ClinicLobby.GRID_COLS, "each row is 60 columns")
	var tile_layer: TileMapLayer = map.get_node("TileMapLayer")
	var used_rect: Rect2i = tile_layer.get_used_rect()
	assert_eq(used_rect.position, Vector2i.ZERO, "used cells start at the top-left")
	assert_eq(used_rect.size, Vector2i(ClinicLobby.GRID_COLS, ClinicLobby.GRID_ROWS), "used cells span the full grid")


func test_bounds_match_grid_in_pixels() -> void:
	var map: ClinicLobby = _spawn_map()
	var bounds: Rect2 = map.get_bounds()
	assert_eq(bounds, Rect2(0, 0, 1920, 640))


func test_ground_row_is_fully_solid() -> void:
	var map: ClinicLobby = _spawn_map()
	var tile_layer: TileMapLayer = map.get_node("TileMapLayer")
	var ground_row: int = ClinicLobby.GRID_ROWS - 1
	for col: int in range(ClinicLobby.GRID_COLS):
		var source_id: int = tile_layer.get_cell_source_id(Vector2i(col, ground_row))
		assert_ne(source_id, -1, "column %d of the ground row has a tile" % col)


func test_camera_bounds_wired_to_player() -> void:
	var map: ClinicLobby = _spawn_map()
	var player: Player = map.get_node("Player")
	var cam: PlayerCamera = player.get_node("PlayerCamera")
	assert_eq(cam.limit_left, 0)
	assert_eq(cam.limit_top, 0)
	assert_eq(cam.limit_right, 1920)
	assert_eq(cam.limit_bottom, 640)


func test_player_spawns_at_spawn_marker() -> void:
	var map: ClinicLobby = _spawn_map()
	var player: Player = map.get_node("Player")
	var spawn: Marker2D = map.get_node("Spawn")
	assert_eq(player.global_position, spawn.global_position)


func test_player_lands_on_ground_within_n_frames() -> void:
	var map: ClinicLobby = _spawn_map()
	var player: Player = map.get_node("Player")
	player.set_physics_process(false)
	await wait_frames(1)
	player.velocity = Vector2.ZERO
	simulate(player, 1, DELTA)
	player.set_input(0.0, false, false)
	var frames: int = 0
	while not player.is_on_floor() and frames < 200:
		simulate(player, 1, DELTA)
		frames += 1
	assert_true(player.is_on_floor(), "player lands on the ground within 200 physics frames")


## Pure layout check: parse LAYOUT into contiguous horizontal runs of solid
## tiles per row, then verify every platform ('=') group has some other
## solid group (ground, wall-adjacent ground, or another platform) that is
## at most MAX_JUMP_ROWS below it (or anywhere above it — falling has no
## height limit) within MAX_GAP_COLS horizontally. That's "reachable in
## principle" without simulating an actual jump arc.
func test_every_platform_is_reachable_in_principle() -> void:
	var groups: Array = _solid_groups(ClinicLobby.LAYOUT)
	var platforms: Array = groups.filter(func(g): return g["char"] == "=")
	assert_gt(platforms.size(), 5, "at least 6 platforms on the map")
	assert_lt(platforms.size(), 11, "at most 10 platforms on the map")
	for p: Dictionary in platforms:
		var reachable: bool = false
		for q: Dictionary in groups:
			if q == p:
				continue
			if q["row"] > p["row"] + MAX_JUMP_ROWS:
				continue
			var gap: int = _col_gap(p, q)
			if gap <= MAX_GAP_COLS:
				reachable = true
				break
		assert_true(
			reachable, "platform at row %d cols %d-%d is reachable from some lower/adjacent surface" % [p["row"], p["col_start"], p["col_end"]]
		)


func _col_gap(a: Dictionary, b: Dictionary) -> int:
	if a["col_end"] < b["col_start"]:
		return b["col_start"] - a["col_end"] - 1
	if b["col_end"] < a["col_start"]:
		return a["col_start"] - b["col_end"] - 1
	return 0


func _solid_groups(layout: Array[String]) -> Array:
	var groups: Array = []
	for row: int in range(layout.size()):
		var line: String = layout[row]
		var run_char: String = ""
		var run_start: int = -1
		for col: int in range(line.length() + 1):
			var ch: String = line[col] if col < line.length() else " "
			var is_solid: bool = SOLID_CHARS.has(ch)
			if is_solid and ch == run_char:
				continue
			if run_start != -1:
				groups.append({"row": row, "col_start": run_start, "col_end": col - 1, "char": run_char})
				run_start = -1
				run_char = ""
			if is_solid:
				run_start = col
				run_char = ch
	return groups
