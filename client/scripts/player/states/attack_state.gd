class_name AttackState
extends PlayerState
## Plays the attack animation and returns to Idle when it's done.
## This is a purely visual timer — it NEVER computes damage. Whether the
## attack actually hits something and for how much is decided by the server;
## this state only shows the swing.

## Animation length only (3 frames of the attack row) — not a balance number.
const DURATION_S: float = 0.35

var _elapsed: float = 0.0


func enter(_prev: StringName) -> void:
	_elapsed = 0.0
	actor.play_animation(&"attack")


func exit() -> void:
	_elapsed = 0.0


func physics_update(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION_S:
		transition_requested.emit(&"Idle")
