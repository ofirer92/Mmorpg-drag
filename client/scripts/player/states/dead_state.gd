class_name DeadState
extends PlayerState
## Terminal state. Entered via StateMachine.request_transition(&"Dead") when
## the server says this player's HP hit 0 — never computed client-side.
## Once here the StateMachine refuses to leave (is_terminal = true).


func enter(_prev: StringName) -> void:
	is_terminal = true
	actor.velocity = Vector2.ZERO
	actor.play_animation(&"dead")


func physics_update(_delta: float) -> void:
	pass
