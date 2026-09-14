extends GutTest
## T-0.4 DoD: the player's camera follows with a deadzone and stays inside
## the map bounds. Camera2D updates its own transform internally every real
## engine tick (drag/limit logic is engine-side, not a GDScript override we
## can call via simulate()), so these tests await real frames instead.

const SPAWN_POS: Vector2 = Vector2(150.0, 685.0)


func _spawn() -> Dictionary:
	var packed: PackedScene = load("res://scenes/test/flat_map.tscn")
	var map: FlatMap = add_child_autofree(packed.instantiate())
	var player: Player = map.get_node("Player")
	var cam: PlayerCamera = player.get_node("PlayerCamera")
	# The camera follows via the engine's own per-tick logic; the player's
	# horizontal/vertical physics are irrelevant here, so freeze them.
	player.set_physics_process(false)
	return {"map": map, "player": player, "cam": cam}


func test_camera_has_a_deadzone_and_map_bounds_wired_on_ready() -> void:
	var w: Dictionary = _spawn()
	var cam: PlayerCamera = w["cam"]
	var map: FlatMap = w["map"]
	var bounds: Rect2 = map.get_map_bounds()
	assert_true(cam.drag_horizontal_enabled, "horizontal deadzone is enabled")
	assert_true(cam.drag_vertical_enabled, "vertical deadzone is enabled")
	assert_gt(cam.drag_left_margin, 0.0, "deadzone has a non-zero margin")
	assert_eq(cam.limit_left, int(bounds.position.x), "map bounds set limit_left on ready")
	assert_eq(cam.limit_right, int(bounds.position.x + bounds.size.x), "map bounds set limit_right on ready")
	assert_eq(cam.limit_top, int(bounds.position.y), "map bounds set limit_top on ready")
	assert_eq(cam.limit_bottom, int(bounds.position.y + bounds.size.y), "map bounds set limit_bottom on ready")


func test_set_map_bounds_updates_limits() -> void:
	var w: Dictionary = _spawn()
	var cam: PlayerCamera = w["cam"]
	cam.set_map_bounds(Rect2(Vector2(10.0, 20.0), Vector2(500.0, 300.0)))
	assert_eq(cam.limit_left, 10)
	assert_eq(cam.limit_top, 20)
	assert_eq(cam.limit_right, 510)
	assert_eq(cam.limit_bottom, 320)


func test_camera_follows_player_beyond_deadzone() -> void:
	var w: Dictionary = _spawn()
	var player: Player = w["player"]
	var cam: PlayerCamera = w["cam"]
	await wait_frames(3)
	var start_center: Vector2 = cam.get_screen_center_position()
	player.global_position = Vector2(1200.0, 685.0)
	await wait_frames(15)
	var moved_center: Vector2 = cam.get_screen_center_position()
	assert_gt(moved_center.x, start_center.x + 100.0, "camera scrolls toward the player once it leaves the deadzone box")


func test_camera_stays_inside_map_bounds() -> void:
	var w: Dictionary = _spawn()
	var player: Player = w["player"]
	var cam: PlayerCamera = w["cam"]
	var map: FlatMap = w["map"]
	var bounds: Rect2 = map.get_map_bounds()
	await wait_frames(3)

	player.global_position = Vector2(bounds.position.x - 5000.0, 685.0)
	await wait_frames(15)
	var left_center: Vector2 = cam.get_screen_center_position()
	assert_between(
		left_center.x, float(cam.limit_left), float(cam.limit_right), "camera never scrolls past the left limit"
	)

	player.global_position = Vector2(bounds.position.x + bounds.size.x + 5000.0, 685.0)
	await wait_frames(15)
	var right_center: Vector2 = cam.get_screen_center_position()
	assert_between(
		right_center.x, float(cam.limit_left), float(cam.limit_right), "camera never scrolls past the right limit"
	)
	assert_gt(right_center.x, left_center.x, "camera moved toward the right edge, not stuck")
