extends GutTest
## T-0.11 + T-0.13 wiring: drops land in the bag, gear changes combat stats, consumables heal
## through the server, and quit-and-reload keeps level / hp / bag / gear / position.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const SAVE_PATH: String = "user://test_game_session.json"

var _weapon_id: String = ""
var _consumable_id: String = ""


func before_all() -> void:
	var items: Dictionary = RulesBalanceData.ITEMS["items"]
	for id: String in items.keys():
		var it: Dictionary = items[id]
		if it["slot"] == "weapon" and _weapon_id == "" and int(it["stats"]["attack"]) > 0:
			_weapon_id = id
		if it["slot"] == "consumable" and _consumable_id == "" and int(it["stats"]["hp"]) > 0:
			_consumable_id = id
	assert_ne(_weapon_id, "", "items.yaml has a weapon with attack")
	assert_ne(_consumable_id, "", "items.yaml has a healing consumable")


func before_each() -> void:
	SaveGame.delete(SAVE_PATH)


func after_all() -> void:
	SaveGame.delete(SAVE_PATH)


func _boot(load_save: bool) -> Node2D:
	var main: Node2D = MainScene.instantiate()
	main.save_path = SAVE_PATH
	main.load_on_ready = load_save
	add_child_autofree(main)
	return main


func test_drop_pickup_lands_in_inventory() -> void:
	var main: Node2D = _boot(false)
	var lobby: ClinicLobby = main.clinic_lobby
	var drop: Drop = preload("res://scenes/monsters/drop.tscn").instantiate()
	drop.item_id = _consumable_id
	drop.global_position = lobby.get_player_position()
	lobby.add_child(drop)
	watch_signals(lobby)
	await wait_frames(5)
	assert_signal_emitted(lobby, "item_picked_up")
	assert_eq(main.inventory.count(_consumable_id), 1)


func test_equipping_a_weapon_raises_server_attack() -> void:
	var main: Node2D = _boot(false)
	var server: LocalServer = main.clinic_lobby.local_server
	var before: float = server.get_stats(Player.ENTITY_ID).attack
	assert_true(main.inventory.add(_weapon_id))
	assert_true(main.inventory.equip(_weapon_id))
	var bonus: int = int(RulesBalanceData.ITEMS["items"][_weapon_id]["stats"]["attack"])
	assert_eq(server.get_stats(Player.ENTITY_ID).attack, before + float(bonus))
	assert_true(main.inventory.unequip("weapon"))
	assert_eq(server.get_stats(Player.ENTITY_ID).attack, before)


func test_using_a_consumable_heals_through_the_server() -> void:
	var main: Node2D = _boot(false)
	var server: LocalServer = main.clinic_lobby.local_server
	var max_hp: float = server.get_max_hp(Player.ENTITY_ID)
	server.set_hp(Player.ENTITY_ID, 1.0)
	assert_true(main.inventory.add(_consumable_id))
	watch_signals(server)
	main.inventory_panel.used.emit(_consumable_id)
	var heal_amount: float = float(RulesBalanceData.ITEMS["items"][_consumable_id]["stats"]["hp"])
	assert_signal_emitted(server, "healed")
	assert_eq(server.get_hp(Player.ENTITY_ID), RulesCombat.heal(1.0, max_hp, heal_amount))


func test_quit_and_reload_keeps_state() -> void:
	var main: Node2D = _boot(false)
	var server: LocalServer = main.clinic_lobby.local_server
	server.set_progress(Player.ENTITY_ID, RulesXp.xp_total_for_level(3))
	assert_true(main.inventory.add(_weapon_id))
	assert_true(main.inventory.equip(_weapon_id))
	assert_true(main.inventory.add(_consumable_id, 2))
	server.set_hp(Player.ENTITY_ID, 7.0)
	main.clinic_lobby.set_player_position(Vector2(500.0, 300.0))
	assert_eq(main.save_game(), OK)
	main.queue_free()
	await wait_frames(1)

	var again: Node2D = _boot(true)
	var server2: LocalServer = again.clinic_lobby.local_server
	var stats: Dictionary = server2.get_stats(Player.ENTITY_ID)
	assert_eq(stats.level, 3.0, "level restored")
	assert_eq(stats.hp, 7.0, "hp restored")
	assert_eq(again.inventory.equipped.get("weapon", ""), _weapon_id, "gear restored")
	assert_eq(again.inventory.count(_consumable_id), 2, "bag restored")
	var bonus: int = int(RulesBalanceData.ITEMS["items"][_weapon_id]["stats"]["attack"])
	var stim: Dictionary = RulesBalanceData.CLASSES["archetypes"]["stim"]
	assert_eq(stats.attack, RulesProgression.attack_at_level(stim, stim["growth"], 3) + float(bonus), "gear bonus re-applied")
	assert_almost_eq(again.clinic_lobby.get_player_position(), Vector2(500.0, 300.0), Vector2(1.0, 1.0), "position restored")


func test_missing_or_corrupt_save_boots_fresh() -> void:
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var main: Node2D = _boot(true)
	assert_eq(main.clinic_lobby.local_server.get_level(Player.ENTITY_ID), 1.0)
	assert_eq(main.inventory.slots().size(), 0)


## T-0.12: money is part of Inventory.to_dict()/from_dict() (see
## client/tests/test_inventory.gd for the module-level round trip); this
## proves it actually survives a real quit-and-reload through main.gd.
func test_money_is_saved_and_restored() -> void:
	var main: Node2D = _boot(false)
	main.inventory.add_money(42)
	assert_eq(main.save_game(), OK)
	main.queue_free()
	await wait_frames(1)

	var again: Node2D = _boot(true)
	assert_eq(again.inventory.money, 42)


## T-0.12: LocalServer.money_dropped(killer_id, amount) is only wired in
## main.gd (this file's job to prove, not local_server.gd's — see ADR-013);
## a kill by the player must land money in the bag.
func test_money_dropped_from_a_kill_lands_in_inventory() -> void:
	var main: Node2D = _boot(false)
	var server: LocalServer = main.clinic_lobby.local_server
	var money_before: int = main.inventory.money
	server.register("test_victim", {"attack": 0.0, "defense": 0.0, "hp": 1.0, "money": {"min": 5, "max": 5}})

	server.request_attack(Player.ENTITY_ID, "test_victim", 9999.0)

	assert_eq(main.inventory.money, money_before + 5)


# T-0.15: attacks and skills are ignored while any UI panel is open; movement still works.
# main.gd polls the panels in _process, so this test awaits idle frames explicitly (GUT's
# wait_frames() advances physics frames but not idle _process here).
func test_open_panel_blocks_attacks_but_not_movement() -> void:
	var main: Node2D = _boot(false)
	var player: Player = main.clinic_lobby.player
	main.inventory_panel.open()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(main.is_ui_open())
	assert_true(player.ui_blocked)
	player.set_input(1.0, false, false, true, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(player.attack_requested, "attack ignored while UI open")
	assert_false(player.skill_requested, "skill ignored while UI open")
	assert_gt(player.velocity.x, 0.0, "movement still allowed")
	main.inventory_panel.close()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(player.ui_blocked)
