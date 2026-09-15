extends Node2D
## Screenshot/demo target for T-2.3 (docs/screenshots/net_390x844.png) —
## boots the REAL main scene, forces the net status label on and drops a
## RemotePlayer in next to the local player so a human can see what both
## look like together at 390×844. NOT part of the real net flow (that's
## main.gd + client/scripts/net/net_session.gd) and never set as
## run/main_scene.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const RemotePlayerScene: PackedScene = preload("res://scenes/net/remote_player.tscn")


func _ready() -> void:
	var main: Node2D = MainScene.instantiate()
	main.save_path = "user://net_demo_scratch.json"
	main.load_on_ready = false
	add_child(main)

	main.net_status_label.visible = true
	main.net_status_label.text = I18n.t("ui.net.connecting")

	var remote: RemotePlayer = RemotePlayerScene.instantiate()
	main.clinic_lobby.add_child(remote)
	var player_pos: Vector2 = main.clinic_lobby.get_player_position()
	remote.apply_state(
		(
			{
				"id": "p_2",
				"name": "ד\"ר כהן",
				"pos": {"x": player_pos.x + 120.0, "y": player_pos.y},
				"vel": {"x": 0.0, "y": 0.0},
				"hp": 80,
				"max_hp": 100,
				"level": 3,
				"xp": 0,
				"facing": -1,
				"anim": "idle",
				"alive": true,
			}
		),
		0
	)
