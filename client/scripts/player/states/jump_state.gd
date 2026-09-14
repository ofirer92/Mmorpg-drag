class_name JumpState
extends PlayerState
## Airborne (rising or falling). Covers both jump and fall since the sprite
## sheet only has one "jump" row. No damage/XP logic — server-authoritative.


func enter(_prev: StringName) -> void:
	actor.play_animation(&"jump")


func physics_update(_delta: float) -> void:
	if actor.is_on_floor():
		transition_requested.emit(&"Idle")
