extends GutTest
## T-2.3: NetSession (client/scripts/net/net_session.gd) end-to-end, driven
## by FakeTransport (client/scripts/net/fake_transport.gd) at a 100 ms
## one-way latency (200 ms RTT — the DoD's number). Uses the same FlatMap
## test scene client/tests/test_player_movement.gd already stands the real
## Player on, so the real Player's own physics and Prediction/FakeTransport's
## flat-floor model are standing on the exact same floor
## (Prediction.FLOOR_REST_Y).
##
## simulate() drives BOTH _process (NetClient) and _physics_process
## (Player, NetSession) with an explicit delta, so this is fully
## deterministic — no OS-clock waiting for "200 ms" to actually pass.

const FlatMapScene: PackedScene = preload("res://scenes/test/flat_map.tscn")
const RemotePlayerScene: PackedScene = preload("res://scenes/net/remote_player.tscn")

const ONE_WAY_LATENCY_S: float = 0.1
const DELTA: float = 1.0 / RulesConstants.TICK_RATE_HZ


func _boot() -> Dictionary:
	var map: Node2D = add_child_autofree(FlatMapScene.instantiate())
	var player: Player = map.player
	var transport: FakeTransport = FakeTransport.new(ONE_WAY_LATENCY_S)
	var client: NetClient = NetClient.new()
	client.set_transport(transport)
	var session: NetSession = NetSession.new()
	map.add_child(client)
	map.add_child(session)
	session.begin(client, player, map)
	client.connect_to("fake://test")
	return {"map": map, "player": player, "transport": transport, "client": client, "session": session}


func test_join_handshake_completes_over_simulated_latency() -> void:
	var ctx: Dictionary = _boot()
	var session: NetSession = ctx.session
	watch_signals(session)

	# 200 ms RTT for join+joined, plus room for a couple of state ticks.
	simulate(ctx.map, 30, DELTA)

	assert_signal_emitted(session, "ready_to_play")
	assert_ne(session.my_player_id, "")


func test_local_player_walks_right_without_visible_jitter_and_converges() -> void:
	var ctx: Dictionary = _boot()
	var player: Player = ctx.player
	var transport: FakeTransport = ctx.transport
	var start_x: float = player.position.x

	var max_backward_delta: float = 0.0
	var prev_x: float = player.position.x
	var walk_ticks: int = int(2.0 / DELTA)
	for i in range(walk_ticks):
		player.set_input(1.0, false, false)
		simulate(ctx.map, 1, DELTA)
		var dx: float = player.position.x - prev_x
		if dx < -0.01:
			max_backward_delta = max(max_backward_delta, -dx)
		prev_x = player.position.x

	assert_lt(max_backward_delta, 4.0, "no visible backward jump from reconciliation at 200 ms RTT")
	assert_gt(player.position.x, start_x + 50.0, "sanity: the player actually walked")

	# Stop and let the fake server drain its latency-delayed input queue so
	# both sides can settle on the same deterministic resting position.
	var settle_ticks: int = int(2.0 / DELTA)
	for i in range(settle_ticks):
		player.set_input(0.0, false, false)
		simulate(ctx.map, 1, DELTA)

	assert_almost_eq(
		player.position.x, float(transport._state.pos.x), 1.0, "local player converges to the server's authoritative x once both are idle"
	)


func test_remote_player_interpolation_is_monotonic_and_smooth() -> void:
	var rp: RemotePlayer = add_child_autofree(RemotePlayerScene.instantiate())
	var tick: int = 0
	var last_x: float = -INF
	for i in range(60):
		if i % 3 == 0:
			rp.apply_state(
				{
					"id": "p_2",
					"name": "Bob",
					"pos": {"x": float(i) * 4.0, "y": Prediction.FLOOR_REST_Y},
					"vel": {"x": 80.0, "y": 0.0},
					"facing": 1,
					"anim": "run",
					"hp": 100,
					"max_hp": 100,
					"level": 1,
					"xp": 0,
					"alive": true,
				},
				tick
			)
			tick += 1
		simulate(rp, 1, DELTA)
		assert_gte(rp.global_position.x, last_x - 0.05, "no teleport backward at frame %d" % i)
		last_x = rp.global_position.x


func test_single_player_mode_has_no_networking() -> void:
	var main_scene: PackedScene = preload("res://scenes/main.tscn")
	var main: Node2D = main_scene.instantiate()
	main.save_path = "user://test_net_session_single_player.json"
	main.load_on_ready = false
	add_child_autofree(main)

	assert_eq(main.net_url, "", "sanity: default is single-player")
	assert_null(main.net_client, "no NetClient is created when net_url is empty")
	assert_false(main.net_status_label.visible, "connection label stays hidden in single-player")

	SaveGame.delete(main.save_path)
