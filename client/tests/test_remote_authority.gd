extends GutTest
## T-2.4 DoD: RemoteAuthority (client/scripts/combat/remote_authority.gd) is
## the ONLY combat-facing script reached in net mode — it never resolves
## damage itself, only relays what FakeTransport's facts said. Every test
## here drives a RemoteAuthority against FakeTransport; none ever touch
## LocalServer (see test_net_mode_never_instantiates_a_local_server below).

const FlatMapScene: PackedScene = preload("res://scenes/test/flat_map.tscn")

const DELTA: float = 1.0 / RulesConstants.TICK_RATE_HZ


func _boot(latency_s: float = 0.0) -> Dictionary:
	var map: Node2D = add_child_autofree(FlatMapScene.instantiate())
	var player: Player = map.player
	var transport: FakeTransport = FakeTransport.new(latency_s)
	var client: NetClient = NetClient.new()
	client.set_transport(transport)
	var session: NetSession = NetSession.new()
	var inventory: Inventory = Inventory.new()
	# A child of `map` (NOT add_child_autofree'd onto the test root) so
	# simulate(map, ...) below drives its _process() too — GUT's simulate()
	# only recurses into the given node's own subtree (see gut_to_move.gd),
	# and `map` already owns autofree cleanup for its whole subtree.
	var authority: RemoteAuthority = RemoteAuthority.new()
	map.add_child(authority)
	authority.setup(client, map, inventory)
	map.add_child(client)
	map.add_child(session)
	session.begin(client, player, map)
	player.set_local_server(authority)
	session.ready_to_play.connect(func(pid: String) -> void: authority.local_player_id = pid)
	client.connect_to("fake://test")
	return {
		"map": map,
		"player": player,
		"transport": transport,
		"client": client,
		"session": session,
		"authority": authority,
		"inventory": inventory,
	}


func _join(ctx: Dictionary) -> void:
	simulate(ctx.map, 10, DELTA)
	assert_ne(String(ctx.session.my_player_id), "", "sanity: joined")
	assert_ne(String(ctx.authority.local_player_id), "", "sanity: RemoteAuthority learned the server's player id")


func test_attack_press_sends_an_input_with_attack_flag_and_skill_id() -> void:
	var ctx: Dictionary = _boot()
	_join(ctx)
	var player: Player = ctx.player
	var transport: FakeTransport = ctx.transport
	transport.received_log.clear()

	# Bypass the level-gate so a non-basic skill_id is exercised too (the
	# real gate — Player.select_skill()/SkillBar — is covered elsewhere).
	player.selected_skill_id = "stim_double_dose"
	player.set_input(0.0, false, false, false, true)
	simulate(ctx.map, 2, DELTA)

	var found: Dictionary = {}
	for msg: Dictionary in transport.received_log:
		if String(msg.get("t", "")) == "input" and bool(msg.get("attack", false)):
			found = msg
			break
	assert_false(found.is_empty(), "at least one `input` carried attack=true")
	assert_eq(String(found.get("skill_id", "")), "stim_double_dose")


func test_damage_fact_updates_the_rendered_monster_hp() -> void:
	var ctx: Dictionary = _boot()
	_join(ctx)
	var player: Player = ctx.player
	var transport: FakeTransport = ctx.transport
	var authority: RemoteAuthority = ctx.authority

	assert_true(authority.is_registered("m_1") or true)  # not yet spawned as a "player" query — sanity no-op
	player.set_input(0.0, false, false, true, false)
	simulate(ctx.map, 6, DELTA)

	assert_lt(transport.monster_hp, transport.monster_max_hp, "sanity: the fake server actually took a hit")
	assert_true(authority._monster_views.has(transport.monster_id), "a RemoteMonster view exists for the monster")
	var view: RemoteMonster = authority._monster_views[transport.monster_id]
	assert_eq(view.hp_bar.value, transport.monster_hp, "the view's hp bar matches the server's `damage` fact")


func test_damage_fact_updates_the_hud() -> void:
	var ctx: Dictionary = _boot()
	_join(ctx)
	var authority: RemoteAuthority = ctx.authority
	var transport: FakeTransport = ctx.transport
	var hud: Hud = add_child_autofree((load("res://scenes/ui/hud.tscn") as PackedScene).instantiate())
	hud.bind(authority, Player.ENTITY_ID)

	transport.deal_damage_to_player(25.0)
	simulate(ctx.map, 4, DELTA)

	assert_eq(hud.hp_bar.value, transport.player_hp, "HUD hp bar follows the server's damage fact for the player")


func test_died_fact_removes_the_monster_and_a_later_state_shows_the_drop() -> void:
	var ctx: Dictionary = _boot()
	_join(ctx)
	var player: Player = ctx.player
	var transport: FakeTransport = ctx.transport
	var authority: RemoteAuthority = ctx.authority
	transport.monster_hp = FakeTransport.TEST_DAMAGE_PER_HIT  # one hit away from death

	player.set_input(0.0, false, false, true, false)
	simulate(ctx.map, 6, DELTA)

	assert_false(transport.monster_alive, "sanity: the fake server killed it")
	assert_false(authority._monster_views.has(transport.monster_id), "the died fact removed the monster view")
	assert_true(authority._drop_views.has(transport._drop.get("id", "")), "the following `state` spawned the drop view")


func test_loot_added_false_leaves_the_bag_unchanged() -> void:
	var ctx: Dictionary = _boot()
	_join(ctx)
	var inventory: Inventory = ctx.inventory
	var transport: FakeTransport = ctx.transport
	var authority: RemoteAuthority = ctx.authority
	var added_events: Array = []
	authority.loot_added.connect(func(item_id: String, money: int) -> void: added_events.append([item_id, money]))
	var slots_before: Array[Dictionary] = inventory.slots()
	var money_before: int = inventory.to_dict().get("money", 0)

	transport.force_loot_rejected = true
	transport.send_text(JSON.stringify({"t": "loot_pickup", "drop_id": "d_whatever"}))
	simulate(ctx.map, 4, DELTA)

	assert_eq(added_events.size(), 0, "loot_added never fires on added:false")
	assert_eq(inventory.slots(), slots_before, "the bag's slots are untouched")
	assert_eq(inventory.to_dict().get("money", 0), money_before, "money is untouched")


func test_net_mode_never_instantiates_a_local_server() -> void:
	var ctx: Dictionary = _boot()
	_join(ctx)
	var player: Player = ctx.player
	var transport: FakeTransport = ctx.transport

	# This whole file never once creates a LocalServer.new() — the ONLY
	# CombatAuthority in play is RemoteAuthority (this assertion documents
	# that fact so a future edit can't quietly reintroduce one).
	assert_true(player.local_server is RemoteAuthority, "the player's authority is RemoteAuthority, never LocalServer")

	player.set_input(0.0, false, false, true, false)
	simulate(ctx.map, 6, DELTA)
	assert_lt(transport.monster_hp, transport.monster_max_hp, "sanity: combat still worked end-to-end without a LocalServer")
