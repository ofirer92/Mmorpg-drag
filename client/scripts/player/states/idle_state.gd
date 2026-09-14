class_name IdleState
extends PlayerState
## Standing still on the floor. No damage/XP logic — server-authoritative.


func enter(_prev: StringName) -> void:
	actor.play_animation(&"idle")


func physics_update(_delta: float) -> void:
	if not actor.is_on_floor():
		transition_requested.emit(&"Jump")
		return
	if actor.attack_requested:
		actor.attack_requested = false
		transition_requested.emit(&"Attack")
		return
	if not is_zero_approx(actor.input_dir):
		transition_requested.emit(&"Run")
