extends GutTest
## T-0.12 DoD: Npc (client/scripts/npc/npc.gd) shows a name from
## RulesBalanceData.NPCS, detects the player entering/leaving its Area2D,
## shows/hides the talk prompt accordingly, and emits interact_requested.
## Also covers ClinicLobby spawning the pharmacist at its npcs.yaml map_cell.

const DELTA: float = 1.0 / 60.0


func _npc(npc_id: String = "pharmacist") -> Npc:
	var packed: PackedScene = load("res://scenes/npc/npc.tscn")
	var node: Npc = packed.instantiate()
	node.npc_id = npc_id
	add_child_autofree(node)
	return node


func _player_at(pos: Vector2) -> Player:
	var packed: PackedScene = load("res://scenes/player/player.tscn")
	var p: Player = packed.instantiate()
	p.global_position = pos
	add_child_autofree(p)
	return p


func test_name_label_comes_from_rules_balance_data() -> void:
	var npc: Npc = _npc()
	var name_key: String = String(RulesBalanceData.NPCS["npcs"]["pharmacist"]["name_key"])
	assert_eq(npc.name_label.text, I18n.t(name_key))


func test_talk_prompt_hidden_by_default() -> void:
	var npc: Npc = _npc()
	assert_false(npc.talk_button.visible)
	assert_false(npc.player_in_range)


func test_talk_prompt_appears_when_player_enters_range() -> void:
	var npc: Npc = _npc()
	npc.global_position = Vector2(400, 400)
	var player: Player = _player_at(Vector2(400, 400))  # squarely overlapping
	await wait_frames(5)
	assert_true(npc.player_in_range)
	assert_true(npc.talk_button.visible)


func test_talk_prompt_hides_when_player_leaves_range() -> void:
	var npc: Npc = _npc()
	npc.global_position = Vector2(400, 400)
	var player: Player = _player_at(Vector2(400, 400))
	await wait_frames(5)
	assert_true(npc.player_in_range)
	player.global_position = Vector2(4000, 4000)
	await wait_frames(5)
	assert_false(npc.player_in_range)
	assert_false(npc.talk_button.visible)


func test_talk_button_emits_interact_requested_with_npc_id() -> void:
	var npc: Npc = _npc()
	watch_signals(npc)
	npc.talk_button.pressed.emit()
	assert_signal_emitted_with_parameters(npc, "interact_requested", ["pharmacist"])


func test_pharmacist_spawns_at_its_npcs_yaml_map_cell_in_clinic_lobby() -> void:
	var packed: PackedScene = load("res://scenes/maps/clinic_lobby.tscn")
	var lobby: ClinicLobby = packed.instantiate()
	add_child_autofree(lobby)
	await wait_frames(1)

	assert_eq(lobby.npcs.size(), 1)
	var npc: Npc = lobby.npcs[0]
	assert_eq(npc.npc_id, "pharmacist")

	var cell_arr: Array = RulesBalanceData.NPCS["npcs"]["pharmacist"]["map_cell"]
	var expected: Vector2 = lobby._cell_center(Vector2i(int(cell_arr[0]), int(cell_arr[1])))
	assert_almost_eq(npc.position, expected, Vector2(0.5, 0.5))


func test_clinic_lobby_re_emits_npc_interact_requested() -> void:
	var packed: PackedScene = load("res://scenes/maps/clinic_lobby.tscn")
	var lobby: ClinicLobby = packed.instantiate()
	add_child_autofree(lobby)
	await wait_frames(1)
	watch_signals(lobby)
	lobby.npcs[0].interact_requested.emit("pharmacist")
	assert_signal_emitted_with_parameters(lobby, "npc_interact_requested", ["pharmacist"])
