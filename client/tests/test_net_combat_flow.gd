extends GutTest
## T-2.4 DoD: end-to-end combat against FakeTransport at a realistic 100 ms
## one-way latency (200 ms RTT — the same number T-2.3's DoD used), driven
## entirely through the real Player/RemoteAuthority/NetSession stack (never
## by calling FakeTransport's internals directly, except to read its
## "ground truth" for assertions). Single-player tests are untouched by any
## of this — see client/tests/test_local_server.gd, test_hud.gd, etc.

const FlatMapScene: PackedScene = preload("res://scenes/test/flat_map.tscn")

const ONE_WAY_LATENCY_S: float = 0.1
const DELTA: float = 1.0 / RulesConstants.TICK_RATE_HZ


func _boot(latency_s: float = ONE_WAY_LATENCY_S) -> Dictionary:
	var map: Node2D = add_child_autofree(FlatMapScene.instantiate())
	var player: Player = map.player
	var transport: FakeTransport = FakeTransport.new(latency_s)
	var client: NetClient = NetClient.new()
	client.set_transport(transport)
	var session: NetSession = NetSession.new()
	var inventory: Inventory = Inventory.new()
	# A child of `map` (NOT add_child_autofree'd onto the test root) so
	# simulate(map, ...) below drives its _process() too — see the matching
	# comment in test_remote_authority.gd's _boot().
	var authority: RemoteAuthority = RemoteAuthority.new()
	map.add_child(authority)
	authority.setup(client, map, inventory)
	map.add_child(client)
	map.add_child(session)
	session.begin(client, player, map)
	player.set_local_server(authority)
	session.ready_to_play.connect(func(pid: String) -> void: authority.local_player_id = pid)
	client.connect_to("fake://test")
	return {"map": map, "player": player, "transport": transport, "session": session, "authority": authority}


func _join(ctx: Dictionary) -> void:
	# 200 ms RTT for join+joined, plus room for a couple of state ticks —
	# same budget client/tests/test_net_session.gd's join test uses.
	simulate(ctx.map, 30, DELTA)
	assert_ne(String(ctx.authority.local_player_id), "", "sanity: joined before the combat flow starts")


func test_monster_hp_drops_only_after_the_damage_fact_arrives_not_immediately() -> void:
	var ctx: Dictionary = _boot()
	_join(ctx)
	var player: Player = ctx.player
	var transport: FakeTransport = ctx.transport
	var authority: RemoteAuthority = ctx.authority
	var hp_before: float = transport.monster_hp

	player.set_input(0.0, false, false, true, false)
	# One physics frame: the local attack animation may start, but nothing
	# has round-tripped to "the server" and back yet at 100 ms one-way
	# latency (a single ~16 ms frame is nowhere near a full RTT).
	simulate(ctx.map, 1, DELTA)

	assert_eq(transport.monster_hp, hp_before, "sanity: not even the fake server has resolved the hit yet")
	if authority._monster_views.has(transport.monster_id):
		var view: RemoteMonster = authority._monster_views[transport.monster_id]
		assert_eq(view.hp_bar.value, hp_before, "the client's rendered hp has NOT dropped yet — no damage fact arrived")

	# Enough ticks for input -> server -> attack/damage fact -> back to us.
	simulate(ctx.map, 20, DELTA)

	assert_lt(transport.monster_hp, hp_before, "sanity: the fake server did resolve the hit by now")
	assert_true(authority._monster_views.has(transport.monster_id))
	var view_after: RemoteMonster = authority._monster_views[transport.monster_id]
	assert_eq(view_after.hp_bar.value, transport.monster_hp, "the rendered hp now matches the server's damage fact")


func test_two_consecutive_attacks_respect_the_cooldown_display() -> void:
	var ctx: Dictionary = _boot()
	_join(ctx)
	var player: Player = ctx.player
	var authority: RemoteAuthority = ctx.authority

	player.selected_skill_id = "stim_double_dose"
	player.set_input(0.0, false, false, false, true)
	# Long enough for the `attack` fact confirming the first use to round-trip.
	simulate(ctx.map, 20, DELTA)

	var cooldown_after_first: float = authority.skill_cooldown_left(Player.ENTITY_ID, "stim_double_dose")
	assert_gt(cooldown_after_first, 0.0, "on cooldown right after the server confirmed the first use")

	# Second press immediately — still well within stim_double_dose's cooldown.
	player.set_input(0.0, false, false, false, true)
	simulate(ctx.map, 4, DELTA)

	var cooldown_after_second_press: float = authority.skill_cooldown_left(Player.ENTITY_ID, "stim_double_dose")
	assert_gt(cooldown_after_second_press, 0.0, "still shows a cooldown — the display isn't reset/stuck at zero")
	assert_lte(cooldown_after_second_press, cooldown_after_first, "the cooldown counts down, it doesn't restart from the second (rejected) press")


func test_unconfirmed_attack_times_out_and_does_not_leave_the_bar_stuck() -> void:
	var ctx: Dictionary = _boot(0.0)
	# No monster to hit: the fake server (see fake_transport.gd's _step_tick)
	# silently ignores an attack input when monster_alive is false — exactly
	# docs/protocol.md's "a rejected attack produces no attack and no error".
	ctx.transport.monster_alive = false
	_join(ctx)
	var player: Player = ctx.player
	var authority: RemoteAuthority = ctx.authority
	var rejected_events: Array = []
	authority.skill_rejected.connect(func(_id: String, skill_id: String, reason: String) -> void: rejected_events.append([skill_id, reason]))

	player.selected_skill_id = "stim_double_dose"
	player.set_input(0.0, false, false, false, true)
	simulate(ctx.map, 2, DELTA)
	assert_eq(rejected_events.size(), 0, "sanity: not rejected yet, still waiting on the confirm window")

	var frames: int = int(RemoteAuthority.ATTACK_CONFIRM_TIMEOUT_S / DELTA) + 5
	simulate(ctx.map, frames, DELTA)

	assert_eq(rejected_events.size(), 1, "skill_rejected fires once the confirm window elapses with no `attack` fact")
	assert_eq(rejected_events[0][0], "stim_double_dose")
	assert_eq(
		authority.skill_cooldown_left(Player.ENTITY_ID, "stim_double_dose"),
		0.0,
		"never actually confirmed, so no cooldown shows — the bar is not stuck"
	)
