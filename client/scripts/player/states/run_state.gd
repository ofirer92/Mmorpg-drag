class_name RunState
extends PlayerState
## Moving on the floor. No damage/XP logic — server-authoritative.


func enter(_prev: StringName) -> void:
	actor.play_animation(&"run")


func physics_update(_delta: float) -> void:
	if not actor.is_on_floor():
		transition_requested.emit(&"Jump")
		return
	if actor.attack_requested or actor.skill_requested:
		actor.attack_requested = false
		actor.skill_requested = false
		transition_requested.emit(&"Attack")
		return
	if is_zero_approx(actor.input_dir) and absf(actor.velocity.x) < 1.0:
		transition_requested.emit(&"Idle")
