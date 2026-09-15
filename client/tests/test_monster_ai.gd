extends GutTest
## T-0.9 DoD: Monster (client/scripts/monsters/monster.gd) patrol/chase/attack
## AI, hurt/death, and the drop pickup. Builds a minimal floor + LocalServer
## by hand instead of using arena.tscn, so each test controls exactly one
## variable (target position, seed, ...).

const DELTA: float = 1.0 / 60.0
const MONSTER_Y: float = 685.0


func _make_floor(width: float, center_x: float) -> StaticBody2D:
	var f: StaticBody2D = StaticBody2D.new()
	f.position = Vector2(center_x, 732.0)
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(width, 64.0)
	shape.shape = rect
	f.add_child(shape)
	return f


func _make_monster(monster_id: String, x: float) -> Monster:
	var packed: PackedScene = load("res://scenes/monsters/monster.tscn")
	var monster: Monster = packed.instantiate()
	monster.monster_id = monster_id
	monster.position = Vector2(x, MONSTER_Y)
	return monster


func _make_target(x: float) -> Node2D:
	var n: Node2D = Node2D.new()
	n.position = Vector2(x, MONSTER_Y)
	return n


## Adds floor+monster(+target) to the tree, settles physics, registers the
## monster with a fresh LocalServer, returns everything the test needs.
func _spawn(monster_id: String, spawn_x: float, floor_width: float, floor_center_x: float, target: Node2D) -> Dictionary:
	var root: Node2D = add_child_autofree(Node2D.new())
	root.add_child(_make_floor(floor_width, floor_center_x))
	var monster: Monster = _make_monster(monster_id, spawn_x)
	root.add_child(monster)
	if target != null:
		root.add_child(target)
	await wait_frames(1)
	simulate(monster, 1, DELTA)

	var server: LocalServer = add_child_autofree(LocalServer.new())
	server.register("player", {"attack": 0.0, "defense": 0.0, "level": 1.0, "hp": 100000.0})
	monster.setup(server, target)
	return {"root": root, "monster": monster, "server": server}


func test_patrol_turns_around_at_patrol_distance() -> void:
	var spawn_x: float = 2000.0
	var w: Dictionary = await _spawn("side_effect_slime", spawn_x, 4000.0, spawn_x, null)
	var monster: Monster = w["monster"]
	var patrol_distance: float = monster.ai_params.get("patrol_distance", 0.0)

	var max_x: float = spawn_x
	var min_x: float = spawn_x
	for i in range(600):
		simulate(monster, 1, DELTA)
		max_x = max(max_x, monster.global_position.x)
		min_x = min(min_x, monster.global_position.x)

	assert_almost_eq(max_x - spawn_x, patrol_distance, 4.0, "patrol turns around at +patrol_distance")
	assert_almost_eq(spawn_x - min_x, patrol_distance, 4.0, "patrol turns around at -patrol_distance")


func test_enters_chase_when_player_within_aggro_radius() -> void:
	var spawn_x: float = 2000.0
	var slime: Dictionary = RulesBalanceData.MONSTERS.monsters["side_effect_slime"]
	# Inside aggro_radius but outside attack_range, so it chases without
	# immediately jumping straight to Attack.
	var offset: float = (float(slime.ai_params.aggro_radius) + float(slime.ai_params.attack_range)) / 2.0
	var target: Node2D = _make_target(spawn_x + offset)
	var w: Dictionary = await _spawn("side_effect_slime", spawn_x, 4000.0, spawn_x, target)
	var monster: Monster = w["monster"]

	simulate(monster, 5, DELTA)
	assert_eq(monster.ai_state, Monster.AiState.CHASE, "player inside aggro_radius triggers chase")


func test_returns_to_patrol_beyond_leash_radius() -> void:
	var spawn_x: float = 2000.0
	var slime: Dictionary = RulesBalanceData.MONSTERS.monsters["side_effect_slime"]
	var offset: float = (float(slime.ai_params.aggro_radius) + float(slime.ai_params.attack_range)) / 2.0
	var target: Node2D = _make_target(spawn_x + offset)
	var w: Dictionary = await _spawn("side_effect_slime", spawn_x, 4000.0, spawn_x, target)
	var monster: Monster = w["monster"]

	simulate(monster, 5, DELTA)
	assert_eq(monster.ai_state, Monster.AiState.CHASE, "sanity: chasing first")

	var leash_radius: float = monster.ai_params.get("leash_radius", 0.0)
	target.position.x = spawn_x + leash_radius + 50.0
	simulate(monster, 5, DELTA)
	assert_eq(monster.ai_state, Monster.AiState.PATROL, "beyond leash_radius gives up and returns to patrol")


func test_attacks_only_in_range_and_respects_attack_speed_cooldown() -> void:
	var spawn_x: float = 2000.0
	var target: Node2D = _make_target(spawn_x + 5.0)  # inside attack_range from frame 1
	var w: Dictionary = await _spawn("side_effect_slime", spawn_x, 4000.0, spawn_x, target)
	var monster: Monster = w["monster"]
	var server: LocalServer = w["server"]
	var attack_speed: float = float(RulesBalanceData.MONSTERS.monsters["side_effect_slime"].attack_speed)

	# Prime: walk PATROL -> CHASE -> ATTACK.
	simulate(monster, 5, DELTA)
	assert_eq(monster.ai_state, Monster.AiState.ATTACK, "sanity: close target reaches ATTACK state")

	watch_signals(server)
	var duration: float = 2.0
	simulate(monster, int(duration / DELTA), DELTA)
	var count_in_range: int = get_signal_emit_count(server, "damage_dealt")

	assert_gt(count_in_range, 0, "attacked at least once while in range")
	var loose_upper_bound: int = int(ceil(duration * attack_speed)) + 2
	assert_lt(
		count_in_range, loose_upper_bound + 1, "does not attack faster than 1/attack_speed intervals"
	)
	# Sanity that there IS a cooldown at all: at 60 fps for 2s that's up to 120
	# physics frames — an ungated monster would fire on (almost) every one.
	assert_lt(count_in_range, 20, "clearly cooldown-gated, not firing every physics frame")

	# Now move the target out of attack_range and confirm attacks stop.
	target.position.x = spawn_x + monster.ai_params.get("attack_range", 0.0) + 200.0
	simulate(monster, 5, DELTA)
	var count_after_leaving_range: int = get_signal_emit_count(server, "damage_dealt")
	simulate(monster, int(1.0 / DELTA), DELTA)
	assert_eq(
		get_signal_emit_count(server, "damage_dealt"),
		count_after_leaving_range,
		"no further attacks once the target left attack_range"
	)


func test_dies_at_zero_hp_spawns_a_drop_and_the_player_can_pick_it_up() -> void:
	var spawn_x: float = 2000.0
	var w: Dictionary = await _spawn("side_effect_slime", spawn_x, 4000.0, spawn_x, null)
	var root: Node2D = w["root"]
	var monster: Monster = w["monster"]
	var server: LocalServer = w["server"]

	server.register("killer", {"attack": 100000.0, "defense": 0.0, "level": 10.0, "hp": 100.0})

	# Find a seed whose loot roll actually drops something (common_trash is
	# 70% expired_bandage / 30% nothing) — deterministic search, not luck.
	var seed_value: int = 1
	var predicted_loot_roll: float = 0.0
	while true:
		var predict: RandomNumberGenerator = RandomNumberGenerator.new()
		predict.seed = seed_value
		predict.randf()  # consumed by the killing blow's damage roll
		predicted_loot_roll = predict.randf()
		if predicted_loot_roll < 0.7:
			break
		seed_value += 1
	server.seed_rng(seed_value)

	var monster_data: Dictionary = RulesBalanceData.MONSTERS.monsters["side_effect_slime"]
	var expected_item: String = RulesLoot.roll_loot(monster_data.loot_table, predicted_loot_roll)
	assert_ne(expected_item, "", "sanity: the seed we picked actually drops something")
	var item_def: Dictionary = RulesBalanceData.ITEMS["items"][expected_item]

	server.request_attack("killer", monster.get_entity_id(), 1.0)
	assert_eq(monster.ai_state, Monster.AiState.DEAD, "entity_died flips the monster to Dead immediately")

	var death_frames: int = int(Monster.DEATH_DELAY_S / DELTA) + 3
	simulate(monster, death_frames, DELTA)
	await wait_frames(2)

	assert_false(is_instance_valid(monster), "monster is freed after the death delay")

	var drop: Drop = null
	for child: Node in root.get_children():
		if child is Drop:
			drop = child
	assert_not_null(drop, "a Drop pickup was spawned")
	assert_eq(drop.item_id, expected_item, "drop matches RulesLoot.roll_loot for the seeded roll")
	# T-1.7b: the drop node carries whatever the AUTHORITY rolled for it — the monster copies the
	# affixes off entity_died, it never rolls them itself.
	var rolled: Array[String] = drop.affixes
	for affix_id: String in rolled:
		assert_true(
			RulesAffixes.affix_allows_rarity(affix_id, String(item_def.get("rarity", ""))),
			"a rolled affix must be legal for the dropped item's rarity: %s" % affix_id
		)

	# NOTE: drop.gd frees itself (queue_free) the moment it's picked up, so by
	# the time we get to assert, `drop` may already be a dangling reference —
	# calling GUT's signal-watch asserts on a freed Object crashes the engine.
	# Capture the signal manually instead of relying on watch_signals(drop).
	# Use a Dictionary (reference type) since GDScript lambdas capture plain
	# local vars by VALUE — a bool/String written inside the lambda would not
	# be visible out here.
	var picked_up: Dictionary = {"called": false, "item": "", "affixes": []}
	drop.picked_up.connect(
		func(item_id: String, affixes: Array) -> void:
			picked_up.called = true
			picked_up.item = item_id
			picked_up.affixes = affixes
	)

	var player_packed: PackedScene = load("res://scenes/player/player.tscn")
	var player: Player = player_packed.instantiate()
	player.global_position = drop.global_position
	root.add_child(player)
	await wait_frames(3)

	assert_true(picked_up.called, "the player overlapping the drop emits picked_up")
	assert_eq(picked_up.item, expected_item, "picked_up carries the correct item id")
	# T-1.7b: the drop reports whatever the authority rolled for it — here nothing was set on the
	# node, so an empty list, never a null or a missing argument.
	assert_eq(picked_up.affixes, rolled, "picked_up carries the drop's own rolled affixes")
