class_name HurtState
extends PlayerState
## Plays the hurt animation and returns to Idle when it's done.
## Entered via StateMachine.request_transition(&"Hurt") when the server says
## this player took a hit — the state itself never computes damage/HP.

## Animation length only (short flinch) — not a balance number.
const DURATION_S: float = 0.3

var _elapsed: float = 0.0


func enter(_prev: StringName) -> void:
	_elapsed = 0.0
	actor.play_animation(&"hurt")


func exit() -> void:
	_elapsed = 0.0


func physics_update(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION_S:
		transition_requested.emit(&"Idle")
