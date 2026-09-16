extends GutTest
## T-0.3 DoD: a TileMapLayer map with floating platforms, bounds, a spawn marker the player lands
## from, and every platform reachable with a single jump given RulesMovement's constants.
##
## The map is a VERTICAL tower (taller than wide) because the game is portrait-only — see
## project.godot's display/window/handheld/orientation and test_map_is_taller_than_wide below. The
## dimensions here are read from ClinicLobby's own constants rather than hardcoded, so re-shaping the
## tower does not mean editing pixel literals in five assertions.

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


func test_layout_matches_the_declared_grid() -> void:
	var map: ClinicLobby = _spawn_map()
	assert_eq(ClinicLobby.LAYOUT.size(), ClinicLobby.GRID_ROWS, "one layout row per grid row")
	for row: String in ClinicLobby.LAYOUT:
		assert_eq(row.length(), ClinicLobby.GRID_COLS, "every row is the full grid width")
	var tile_layer: TileMapLayer = map.get_node("TileMapLayer")
	var used_rect: Rect2i = tile_layer.get_used_rect()
	assert_eq(used_rect.position, Vector2i.ZERO, "used cells start at the top-left")
	assert_eq(used_rect.size, Vector2i(ClinicLobby.GRID_COLS, ClinicLobby.GRID_ROWS), "used cells span the full grid")


func test_bounds_match_grid_in_pixels() -> void:
	var map: ClinicLobby = _spawn_map()
	var bounds: Rect2 = map.get_bounds()
	var expected := Rect2(
		0,
		0,
		ClinicLobby.GRID_COLS * ClinicLobby.TILE_SIZE,
		ClinicLobby.GRID_ROWS * ClinicLobby.TILE_SIZE
	)
	assert_eq(bounds, expected)


## The portrait requirement itself: the game is locked to a vertical handheld orientation, so the
## playable world has to be taller than it is wide. A landscape map in a 390×844 viewport leaves the
## player staring at empty sky it can never fill — which is exactly what this map used to be
## (60×20 tiles = 1920×640px, three times wider than tall).
func test_map_is_taller_than_wide() -> void:
	var width_px: int = ClinicLobby.GRID_COLS * ClinicLobby.TILE_SIZE
	var height_px: int = ClinicLobby.GRID_ROWS * ClinicLobby.TILE_SIZE
	assert_gt(height_px, width_px, "the tower must be vertical")
	# ...and tall enough to actually scroll on the portrait viewport it is designed for.
	var viewport_height: int = ProjectSettings.get_setting("display/window/size/viewport_height")
	assert_gt(height_px, viewport_height, "the world must exceed one screen of height")


func test_project_is_locked_to_portrait() -> void:
	assert_eq(
		int(ProjectSettings.get_setting("display/window/handheld/orientation")),
		DisplayServer.SCREEN_PORTRAIT,
		"handheld orientation must stay portrait"
	)
	var w: int = ProjectSettings.get_setting("display/window/size/viewport_width")
	var h: int = ProjectSettings.get_setting("display/window/size/viewport_height")
	assert_gt(h, w, "the design viewport itself must be portrait")


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
	assert_eq(cam.limit_right, ClinicLobby.GRID_COLS * ClinicLobby.TILE_SIZE)
	assert_eq(
		cam.limit_bottom,
		ClinicLobby.GRID_ROWS * ClinicLobby.TILE_SIZE + PlayerCamera.BOTTOM_UI_PADDING_PX
	)


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
	# A vertical tower needs a platform every MAX_JUMP_ROWS the whole way up, so the count scales
	# with the map's height rather than being a fixed handful as on the old horizontal strip.
	var climbable_rows: int = ClinicLobby.GRID_ROWS - 4
	assert_gt(platforms.size(), climbable_rows / MAX_JUMP_ROWS - 3, "enough platforms to climb")
	assert_lt(platforms.size(), climbable_rows, "platforms must not fill every row")
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


## T-0.10: 6 monsters wired onto the real map from MONSTER_SPAWNS, each in an
## empty-air cell with a solid tile directly below it (so it lands on
## something instead of falling through the floor forever).
func test_monster_spawns_match_count_and_land_on_solid_ground() -> void:
	var map: ClinicLobby = _spawn_map()
	await wait_frames(1)
	var monster_count: int = 0
	for child: Node in map.get_children():
		if child is Monster:
			monster_count += 1
	assert_eq(monster_count, ClinicLobby.MONSTER_SPAWNS.size(), "one Monster node per MONSTER_SPAWNS entry")

	for entry: Dictionary in ClinicLobby.MONSTER_SPAWNS:
		var cell: Vector2i = entry.cell
		var below: Vector2i = cell + Vector2i(0, 1)
		assert_false(SOLID_CHARS.has(ClinicLobby.LAYOUT[cell.y][cell.x]), "spawn cell %s is empty air" % cell)
		assert_true(SOLID_CHARS.has(ClinicLobby.LAYOUT[below.y][below.x]), "cell below spawn %s is solid" % cell)


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


## T-0.10: monsters are placed on the real map from MONSTER_SPAWNS, not
## hand-wired scene children — this asserts the count matches (at least 6
## per the DoD) and, separately, that every spawn cell is valid: empty air
## with a solid tile directly below it (so monsters spawn standing on
## something, never inside a wall/platform or floating over a gap).
func test_monster_count_matches_spawn_table() -> void:
	var map: ClinicLobby = _spawn_map()
	var monsters: Array = map.get_children().filter(func(c: Node) -> bool: return c is Monster)
	assert_eq(monsters.size(), ClinicLobby.MONSTER_SPAWNS.size())
	assert_gt(monsters.size(), 5, "at least 6 monsters on the map")


func test_every_monster_spawn_cell_is_empty_air_over_a_solid_tile() -> void:
	for entry: Dictionary in ClinicLobby.MONSTER_SPAWNS:
		var cell: Vector2i = entry["cell"]
		var row: String = ClinicLobby.LAYOUT[cell.y]
		assert_eq(row[cell.x], ".", "spawn cell (%d,%d) for %s is empty air" % [cell.x, cell.y, entry["id"]])
		var below_row_index: int = cell.y + 1
		assert_lt(below_row_index, ClinicLobby.LAYOUT.size(), "spawn cell (%d,%d) has a row below it" % [cell.x, cell.y])
		var below_char: String = ClinicLobby.LAYOUT[below_row_index][cell.x]
		assert_true(
			SOLID_CHARS.has(below_char),
			"spawn cell (%d,%d) for %s has a solid tile directly below (got '%s')" % [cell.x, cell.y, entry["id"], below_char]
		)


## The geometry above ("is there a surface within 2 rows?") says a tower is climbable in principle.
## It does NOT say the player physically fits: a ledge 2 rows over a floor leaves 32px of headroom
## for a 30px body, and the first version of this vertical map spawned the player clipped into the
## ledge above, unable to move at all. The layout check passed the whole time. So: actually run the
## player.
func test_player_spawns_with_headroom_and_can_move() -> void:
	var map: ClinicLobby = _spawn_map()
	var player: Player = map.get_node("Player")
	await wait_frames(2)
	# Settle onto the ground first.
	player.set_input(0.0, false, false)
	for i: int in range(30):
		simulate(player, 1, DELTA)
	assert_true(player.is_on_floor(), "the player reaches the floor at spawn")

	var start_x: float = player.global_position.x
	player.set_input(1.0, false, false)
	for i: int in range(30):
		simulate(player, 1, DELTA)
	assert_gt(
		player.global_position.x - start_x,
		16.0,
		"the player must be able to walk — a spawn clipped into a ledge above silently jams movement"
	)


## Proves the climb itself: from the ground, a run-and-jump must actually land the player on a
## higher surface. Without this the tower could be a sealed box and every layout assertion would
## still pass.
func test_player_can_jump_from_the_ground_onto_a_ledge() -> void:
	var map: ClinicLobby = _spawn_map()
	var player: Player = map.get_node("Player")
	await wait_frames(2)
	player.set_input(0.0, false, false)
	for i: int in range(30):
		simulate(player, 1, DELTA)
	var ground_y: float = player.global_position.y
	assert_true(player.is_on_floor())

	# Run right out of the shaft and jump onto the lowest ledge.
	var best_y: float = ground_y
	for i: int in range(120):
		var jump: bool = player.is_on_floor()
		player.set_input(1.0, jump, false)
		simulate(player, 1, DELTA)
		if player.is_on_floor():
			best_y = min(best_y, player.global_position.y)
	assert_lt(
		best_y,
		ground_y - float(ClinicLobby.TILE_SIZE),
		"running and jumping right must land the player at least a tile higher than the ground"
	)


## A tall map introduces a problem a short one never had: the camera clamps to the map's bottom
## edge, so a player standing on the ground row renders at the very bottom of the screen — directly
## underneath the virtual joystick and action buttons. PlayerCamera reserves that band by being
## allowed to scroll past the map's bottom edge.
##
## The band top is measured from the REAL touch_controls scene, not from PlayerCamera's own
## constant — using the camera's constant for both sides would make this test circular (zeroing the
## reserve would move the band with it and the test could never fail).
##
## Camera2D's clamp is applied by hand against the DESIGN viewport (project.godot's 390×844) rather
## than read from get_global_transform_with_canvas(): GUT's window is not the design viewport, so
## the real canvas transform here reflects the harness's size. The player's resting position and the
## camera's limits are both real.
func test_player_on_the_ground_renders_above_the_touch_controls() -> void:
	var map: ClinicLobby = _spawn_map()
	var player: Player = map.get_node("Player")
	var cam: PlayerCamera = player.get_node("PlayerCamera")
	await wait_frames(2)
	player.set_input(0.0, false, false)
	for i: int in range(40):
		simulate(player, 1, DELTA)
	assert_true(player.is_on_floor(), "precondition: the player is standing on the ground row")

	var viewport_height: float = float(ProjectSettings.get_setting("display/window/size/viewport_height"))
	var half: float = viewport_height * 0.5
	var center_y: float = clampf(
		player.global_position.y, float(cam.limit_top) + half, float(cam.limit_bottom) - half
	)
	var screen_y: float = player.global_position.y - (center_y - half)
	var control_band_top: float = viewport_height - _bottom_hud_band_height()

	assert_lt(
		screen_y,
		control_band_top,
		"a grounded player must render above the thumb controls (screen y %.0f, band top %.0f)" % [screen_y, control_band_top]
	)
	assert_gt(screen_y, 0.0, "...and on screen at all")


## Height of the bottom strip the HUD actually occupies, measured from the scenes themselves: the
## joystick and action buttons, plus the skill bar in the strip above them. Each is anchored to the
## bottom edge, so -offset_top is how far up from the bottom it reaches.
func _bottom_hud_band_height() -> float:
	var tallest: float = 0.0
	for entry: Array in [
		["res://scenes/ui/touch_controls.tscn", "Joystick"],
		["res://scenes/ui/touch_controls.tscn", "ActionButtons"],
		["res://scenes/ui/skill_bar.tscn", "Bar"],
	]:
		var packed: PackedScene = load(entry[0])
		var layer: CanvasLayer = add_child_autofree(packed.instantiate())
		var node: Control = layer.get_node(entry[1])
		tallest = max(tallest, -node.offset_top)
	assert_gt(tallest, 0.0, "the bottom HUD must occupy a measurable band")
	return tallest
