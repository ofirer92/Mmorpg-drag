extends GutTest
## T-0.2 DoD: every state transition of the player's StateMachine
## (Idle/Run/Jump/Attack/Hurt/Dead). None of these states compute damage/XP —
## Attack/Hurt/Dead only play an animation/timer and hand control back.

const DELTA: float = 1.0 / 60.0
const SPAWN_POS: Vector2 = Vector2(150.0, 685.0)
const MAX_WAIT_FRAMES: int = 120


func _spawn_player() -> Player:
	var packed: PackedScene = load("res://scenes/test/flat_map.tscn")
	var map: Node2D = add_child_autofree(packed.instantiate())
	var player: Player = map.get_node("Player")
	player.set_physics_process(false)
	return player


func _settle(player: Player) -> void:
	await wait_frames(1)
	player.velocity = Vector2.ZERO
	simulate(player, 1, DELTA)


func _wait_until_state(player: Player, name: StringName) -> bool:
	for i: int in range(MAX_WAIT_FRAMES):
		if player.state_machine.current.name == name:
			return true
		simulate(player, 1, DELTA)
	return player.state_machine.current.name == name


func test_starts_idle() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	assert_eq(String(player.state_machine.current.name), "Idle")


func test_idle_to_run_to_idle() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	assert_eq(String(player.state_machine.current.name), "Idle")

	player.set_input(1.0, false, true)
	assert_true(_wait_until_state(player, &"Run"), "moving transitions Idle -> Run")

	player.set_input(0.0, false, true)
	assert_true(_wait_until_state(player, &"Idle"), "stopping transitions Run -> Idle")


func test_idle_to_jump_to_idle_via_landing() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	assert_eq(String(player.state_machine.current.name), "Idle")

	player.set_input(0.0, true, true)
	assert_true(_wait_until_state(player, &"Jump"), "jumping transitions Idle -> Jump")

	player.set_input(0.0, false, true)
	assert_true(_wait_until_state(player, &"Idle"), "landing transitions Jump -> Idle")


func test_idle_to_attack_to_idle() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	assert_eq(String(player.state_machine.current.name), "Idle")

	player.set_input(0.0, false, true, true)
	assert_true(_wait_until_state(player, &"Attack"), "attack press transitions Idle -> Attack")

	player.set_input(0.0, false, true)
	assert_true(_wait_until_state(player, &"Idle"), "attack animation finishing transitions Attack -> Idle")


func test_any_state_to_hurt_to_idle() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	player.set_input(1.0, false, true)
	assert_true(_wait_until_state(player, &"Run"), "sanity: player is mid-Run")

	player.hurt()
	assert_eq(String(player.state_machine.current.name), "Hurt", "hurt() forces a transition from any state")

	player.set_input(0.0, false, true)
	assert_true(_wait_until_state(player, &"Idle"), "hurt animation finishing transitions Hurt -> Idle")


func test_any_state_to_dead_is_terminal() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	player.set_input(1.0, false, true)
	assert_true(_wait_until_state(player, &"Run"), "sanity: player is mid-Run")

	player.die()
	assert_eq(String(player.state_machine.current.name), "Dead", "die() forces a transition from any state")

	# Nothing can move the machine out of Dead — neither another forced
	# transition nor a state's own requested one.
	player.hurt()
	assert_eq(String(player.state_machine.current.name), "Dead", "Dead refuses hurt()")
	player.state_machine.request_transition(&"Idle")
	assert_eq(String(player.state_machine.current.name), "Dead", "Dead refuses a direct request_transition")
	simulate(player, 30, DELTA)
	assert_eq(String(player.state_machine.current.name), "Dead", "Dead never times out on its own")


func test_ignores_unknown_state_names() -> void:
	var player: Player = _spawn_player()
	await _settle(player)
	assert_eq(String(player.state_machine.current.name), "Idle")
	player.state_machine.request_transition(&"NotARealState")
	assert_eq(String(player.state_machine.current.name), "Idle", "unknown state name is a no-op")
