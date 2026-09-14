extends GutTest
## T-0.1 DoD: movement/jump/coyote-time/jump-buffer physics, all driven by
## RulesMovement (client/scripts/rules/movement.gd, generated). Uses the
## flat_map test scene (client/scenes/test/flat_map.tscn) as the world.
##
## Player.gd also runs its own real _physics_process every engine tick, which
## would race with GUT's simulate() and make timing non-deterministic. Every
## test disables it (set_physics_process(false)) and drives the player only
## through explicit simulate() calls with a fixed 1/60s delta — the same rate
## move_and_slide() itself assumes (default physics_ticks_per_second = 60).

const DELTA: float = 1.0 / 60.0
const SPAWN_POS: Vector2 = Vector2(150.0, 685.0)
const EDGE_POS: Vector2 = Vector2(2370.0, 685.0)


func _spawn_player() -> Player:
	var packed: PackedScene = load("res://scenes/test/flat_map.tscn")
	var map: Node2D = add_child_autofree(packed.instantiate())
	var player: Player = map.get_node("Player")
	# Stop the engine's own automatic physics tick from also driving the
	# player — we want every physics step to come from an explicit simulate().
	player.set_physics_process(false)
	return player


## One real frame so the physics server has the floor/player transforms
## synced, then one manual step so is_on_floor() reflects reality.
func _settle(player: Player) -> void:
	await wait_frames(1)
	player.velocity = Vector2.ZERO
	simulate(player, 1, DELTA)


func _reset(player: Player, pos: Vector2) -> void:
	player.global_position = pos
	player.velocity = Vector2.ZERO
	simulate(player, 1, DELTA)


func test_moves_right_and_reaches_max_speed() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	player.set_input(1.0, false, true)
	simulate(player, 20, DELTA)
	assert_almost_eq(player.velocity.x, RulesMovement.MOVE_SPEED_PX, 0.5, "reaches MOVE_SPEED_PX moving right")


func test_moves_left_and_reaches_max_speed() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	player.set_input(-1.0, false, true)
	simulate(player, 20, DELTA)
	assert_almost_eq(player.velocity.x, -RulesMovement.MOVE_SPEED_PX, 0.5, "reaches MOVE_SPEED_PX moving left")


func test_stops_with_friction_when_input_released() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	player.set_input(1.0, false, true)
	simulate(player, 20, DELTA)
	assert_gt(player.velocity.x, 0.0, "moving before releasing input")
	player.set_input(0.0, false, true)
	simulate(player, 20, DELTA)
	assert_almost_eq(player.velocity.x, 0.0, 0.5, "friction brings the player to a stop")


func test_jump_from_floor_sets_jump_velocity() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	assert_true(player.is_on_floor(), "starts on the floor")
	player.set_input(0.0, true, true)
	simulate(player, 1, DELTA)
	assert_eq(player.velocity.y, RulesMovement.JUMP_VELOCITY_PX, "jump sets vy to JUMP_VELOCITY_PX")
	assert_false(player.is_on_floor(), "left the floor on the jump frame")


func test_lands_back_on_the_floor() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	player.set_input(0.0, true, true)
	simulate(player, 1, DELTA)
	player.set_input(0.0, false, true)
	var frames: int = 0
	while not player.is_on_floor() and frames < 200:
		simulate(player, 1, DELTA)
		frames += 1
	assert_true(player.is_on_floor(), "player eventually lands again")
	assert_almost_eq(player.velocity.y, 0.0, 1.0, "vertical velocity is settled once grounded")


func test_cannot_double_jump_mid_air() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	player.set_input(0.0, true, true)
	simulate(player, 1, DELTA)
	assert_eq(player.velocity.y, RulesMovement.JUMP_VELOCITY_PX, "first jump fires")
	# Well past coyote time and still airborne.
	player.set_input(0.0, false, true)
	simulate(player, 20, DELTA)
	assert_false(player.is_on_floor(), "still airborne")
	var vy_before_second_press: float = player.velocity.y
	player.set_input(0.0, true, true)
	simulate(player, 1, DELTA)
	assert_ne(player.velocity.y, RulesMovement.JUMP_VELOCITY_PX, "second press mid-air does not jump again")
	assert_gt(player.velocity.y, vy_before_second_press, "gravity kept acting normally instead of resetting")


func test_coyote_time_allows_jump_shortly_after_leaving_floor() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	_reset(player, EDGE_POS)
	player.set_input(1.0, false, true)
	var frames: int = 0
	while player.is_on_floor() and frames < 200:
		simulate(player, 1, DELTA)
		frames += 1
	assert_false(player.is_on_floor(), "walked off the edge")
	player.set_input(0.0, true, true)
	simulate(player, 1, DELTA)
	assert_eq(player.velocity.y, RulesMovement.JUMP_VELOCITY_PX, "coyote-time jump within COYOTE_TIME_S still fires")


func test_coyote_time_expires() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	_reset(player, EDGE_POS)
	player.set_input(1.0, false, true)
	var frames: int = 0
	while player.is_on_floor() and frames < 200:
		simulate(player, 1, DELTA)
		frames += 1
	assert_false(player.is_on_floor(), "walked off the edge")
	player.set_input(0.0, false, true)
	var wait_frames_count: int = int(RulesMovement.COYOTE_TIME_S * 2.0 / DELTA) + 2
	simulate(player, wait_frames_count, DELTA)
	player.set_input(0.0, true, true)
	simulate(player, 1, DELTA)
	assert_ne(player.velocity.y, RulesMovement.JUMP_VELOCITY_PX, "jump pressed after 2x coyote time does not fire")


func test_jump_buffer_presses_before_landing_still_jumps() -> void:
	var player: Player = _spawn_player()
	await _settle(player)

	# Measure how long an unbuffered jump naturally takes to return to the floor.
	_reset(player, SPAWN_POS)
	player.set_input(0.0, true, true)
	simulate(player, 1, DELTA)
	player.set_input(0.0, false, true)
	var land_frames: int = 0
	while not player.is_on_floor() and land_frames < 200:
		simulate(player, 1, DELTA)
		land_frames += 1
	assert_true(player.is_on_floor(), "measurement jump landed")

	# Repeat, pressing jump again JUMP_BUFFER_S/2 before that landing frame.
	_reset(player, SPAWN_POS)
	player.set_input(0.0, true, true)
	simulate(player, 1, DELTA)
	player.set_input(0.0, false, true)
	var buffer_frames: int = int((RulesMovement.JUMP_BUFFER_S / 2.0) / DELTA)
	var press_frame: int = land_frames - buffer_frames
	simulate(player, press_frame - 1, DELTA)
	player.set_input(0.0, true, true)
	simulate(player, 1, DELTA)
	player.set_input(0.0, false, true)

	var jumped_after_landing: bool = false
	for i: int in range(6):
		simulate(player, 1, DELTA)
		if not player.is_on_floor() and is_equal_approx(player.velocity.y, RulesMovement.JUMP_VELOCITY_PX):
			jumped_after_landing = true
			break
	assert_true(jumped_after_landing, "buffered jump fires right after landing without a fresh press")


func test_jump_cut_when_releasing_early() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	player.set_input(0.0, true, true)
	simulate(player, 1, DELTA)
	assert_eq(player.velocity.y, RulesMovement.JUMP_VELOCITY_PX, "jump starts at full velocity")
	var uncut_vy: float = RulesMovement.step_vertical(RulesMovement.JUMP_VELOCITY_PX, DELTA)
	player.set_input(0.0, false, false)
	simulate(player, 1, DELTA)
	var expected: float = RulesMovement.jump_cut(uncut_vy)
	assert_almost_eq(player.velocity.y, expected, 0.5, "releasing jump early cuts vertical velocity")
	assert_gt(player.velocity.y, uncut_vy, "cut jump rises less than an uncut jump would")
