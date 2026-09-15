extends GutTest
## T-2.3: Prediction (client/scripts/net/prediction.gd) is pure/isolated from
## any scene, so it's exercised directly here — no NetSession/FakeTransport
## needed (see test_net_session.gd for the end-to-end version). These tests
## stand in for NetSession by driving an idealized client whose rendered
## position exactly matches Prediction.step()'s flat-floor model (built with
## _walk()) — the same pure function client/scripts/net/fake_transport.gd's
## fake server uses — so the numbers are exact, not approximate.

const DT: float = 1.0 / RulesConstants.TICK_RATE_HZ


func _pred() -> Prediction:
	var p: Prediction = Prediction.new()
	p.reset(Vector2(0.0, Prediction.FLOOR_REST_Y))
	return p


## Simulates `count` ticks of `dir` starting from rest at (0, FLOOR_REST_Y),
## record()ing each tick into `p` like NetSession would from a real Player
## whose physics happens to match the flat model exactly. Returns the
## {seq: {dir, jump_held}} inputs sent, for tests that need to replay them
## by hand.
func _walk(p: Prediction, count: int, dir: float) -> Array[Dictionary]:
	var state: Dictionary = {
		"pos": Vector2(0.0, Prediction.FLOOR_REST_Y),
		"vel": Vector2.ZERO,
		"time_since_floor": 0.0,
		"time_since_jump_press": -1.0,
		"jump_held_prev": false,
	}
	var inputs: Array[Dictionary] = []
	for seq in range(1, count + 1):
		state = Prediction.step(state, dir, false, DT)
		p.record(seq, state.pos, state.vel, dir, false, DT)
		inputs.append({"seq": seq, "dir": dir, "jump_held": false})
	return inputs


func test_no_correction_when_server_agrees() -> void:
	var p: Prediction = _pred()
	var state: Dictionary = {
		"pos": Vector2(0.0, Prediction.FLOOR_REST_Y),
		"vel": Vector2.ZERO,
		"time_since_floor": 0.0,
		"time_since_jump_press": -1.0,
		"jump_held_prev": false,
	}
	for seq in range(1, 6):
		state = Prediction.step(state, 1.0, false, DT)
		p.record(seq, state.pos, state.vel, 1.0, false, DT)

	var result: Dictionary = p.on_state(state.pos, state.vel, 5)

	assert_false(bool(result.corrected))


func test_small_disagreement_does_not_snap() -> void:
	var p: Prediction = _pred()
	var state: Dictionary = {
		"pos": Vector2(0.0, Prediction.FLOOR_REST_Y),
		"vel": Vector2.ZERO,
		"time_since_floor": 0.0,
		"time_since_jump_press": -1.0,
		"jump_held_prev": false,
	}
	for seq in range(1, 6):
		state = Prediction.step(state, 1.0, false, DT)
		p.record(seq, state.pos, state.vel, 1.0, false, DT)

	var nudged: Vector2 = state.pos + Vector2(Prediction.RECONCILE_EPSILON_PX * 0.5, 0.0)
	var result: Dictionary = p.on_state(nudged, state.vel, 5)

	assert_false(bool(result.corrected), "a sub-epsilon disagreement must not trigger a visible snap")


func test_large_disagreement_snaps_and_replay_matches_a_manual_replay() -> void:
	var p: Prediction = _pred()
	var inputs: Array[Dictionary] = _walk(p, 5, 1.0)

	# Wildly different from anything recorded above.
	var server_pos: Vector2 = Vector2(5000.0, Prediction.FLOOR_REST_Y)
	var server_vel: Vector2 = Vector2.ZERO
	var result: Dictionary = p.on_state(server_pos, server_vel, 3)

	assert_true(bool(result.corrected), "a large disagreement must snap")

	# Manually replay seq 4 and 5 from the server's stated state with the
	# exact same pure step() the server itself would use — this is what
	# on_state()'s replay is supposed to reproduce.
	var expected_state: Dictionary = {
		"pos": server_pos,
		"vel": server_vel,
		"time_since_floor": 0.0,
		"time_since_jump_press": -1.0,
		"jump_held_prev": false,
	}
	for entry: Dictionary in inputs:
		if int(entry.seq) > 3:
			expected_state = Prediction.step(expected_state, float(entry.dir), bool(entry.jump_held), DT)

	assert_almost_eq(result.pos, expected_state.pos, Vector2(0.01, 0.01))
	assert_almost_eq(result.vel, expected_state.vel, Vector2(0.01, 0.01))


func test_on_state_prunes_acked_inputs_from_the_buffer() -> void:
	var p: Prediction = _pred()
	_walk(p, 10, 1.0)
	assert_eq(p.buffer_size(), 10)

	p.on_state(Vector2(999.0, Prediction.FLOOR_REST_Y), Vector2.ZERO, 7)

	assert_eq(p.buffer_size(), 3, "only seq 8/9/10 (still unacked) should remain")


func test_ring_buffer_is_bounded_even_with_no_acks() -> void:
	var p: Prediction = _pred()
	_walk(p, Prediction.MAX_BUFFER + 50, 1.0)

	assert_lte(p.buffer_size(), Prediction.MAX_BUFFER)
