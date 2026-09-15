extends Node2D
## Screenshot-only demo scaffold for docs/screenshots/dosage_form_*.png (scripts/screenshot.sh).
## Registers a stim player on a real LocalServer, then drives a genuine level-up through the
## authority's own signal so the form renders REAL RulesProgression numbers — a screenshot of faked
## text would prove nothing about T-1.5. Not a gameplay scene: no map, no touch controls.

const DosageFormScene: PackedScene = preload("res://scenes/ui/dosage_form.tscn")
const DEMO_LEVEL: float = 4.0


func _ready() -> void:
	var server: LocalServer = LocalServer.new()
	add_child(server)
	server.register("player", {"level": 1.0}, "stim")

	var form: DosageForm = DosageFormScene.instantiate()
	add_child(form)
	form.bind(server, "player", "stim")

	# Baseline at DEMO_LEVEL - 1, then cross one real level, exactly as a kill would.
	server.set_progress("player", RulesXp.xp_total_for_level(DEMO_LEVEL - 1.0))
	form.resync()
	server.set_progress("player", RulesXp.xp_total_for_level(DEMO_LEVEL))
	server.level_up.emit("player", DEMO_LEVEL, server.get_stats("player"))

	# HAMIRPAA_DEMO_APPROVED=1 captures the SIGNED state instead (stamp down, button disabled). The
	# stamp hold is stretched past the capture so the form cannot close before the frame is grabbed.
	if OS.get_environment("HAMIRPAA_DEMO_APPROVED") == "1":
		form.stamp_timer.wait_time = 3600.0
		form.approve_button.pressed.emit()
