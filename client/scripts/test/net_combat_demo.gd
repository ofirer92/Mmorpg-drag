extends Node2D
## Screenshot/demo target for T-2.4 (docs/screenshots/net_combat_390x844.png)
## — boots the REAL main scene in REAL net mode (main.net_url set + a
## FakeTransport injected via main.test_transport, see main.gd's doc
## comment on that hook) so clinic_lobby.enter_net_mode() actually runs
## (no locally-spawned monsters, Hud/SkillBar bound to a RemoteAuthority —
## exactly what a real client looks like once connected) and then drops in
## one extra RemoteMonster (already at partial hp, as if mid-fight) next to
## the player, the same manual-visual-state trick client/scripts/test/
## net_demo.gd uses for its RemotePlayer, so the screenshot doesn't depend
## on a real join handshake finishing within screenshot_runner.gd's 3-frame
## budget. NOT part of the real net flow and never set as run/main_scene.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const RemoteMonsterScene: PackedScene = preload("res://scenes/net/remote_monster.tscn")

## Demo-only numbers (not balance data): where to place the monster relative
## to the player and how damaged it looks.
const MONSTER_OFFSET_X: float = 90.0
const MONSTER_HP: float = 12.0
const MONSTER_MAX_HP: float = 30.0


func _ready() -> void:
	var main: Node2D = MainScene.instantiate()
	main.save_path = "user://net_combat_demo_scratch.json"
	main.load_on_ready = false
	main.net_url = "fake://demo"
	main.test_transport = FakeTransport.new(0.0)
	add_child(main)
	var mc: int = 0
	for c in main.clinic_lobby.get_children():
		if c is Monster:
			mc += 1
	print("DEBUG monster count right after add_child: ", mc)
	print("DEBUG net_mode: ", main.clinic_lobby._net_mode)

	var monster: RemoteMonster = RemoteMonsterScene.instantiate()
	main.clinic_lobby.add_child(monster)
	var player_pos: Vector2 = main.clinic_lobby.get_player_position()
	monster.apply_state(
		{
			"id": "m_demo",
			"kind": "side_effect_slime",
			"pos": {"x": player_pos.x + MONSTER_OFFSET_X, "y": player_pos.y},
			"vel": {"x": 0.0, "y": 0.0},
			"hp": MONSTER_HP,
			"max_hp": MONSTER_MAX_HP,
			"level": 2,
			"facing": -1,
			"anim": "idle",
			"alive": true,
		}
	)
