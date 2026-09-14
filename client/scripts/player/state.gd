class_name PlayerState
extends Node
## Base class for a single player animation/behaviour state (T-0.2).
## States never compute damage/XP/loot — that stays server-side. A state only
## decides what to show (animation) and when to ask the StateMachine to move on.

signal transition_requested(to: StringName)

## Set by StateMachine._ready(). The player node this state controls.
var actor: Player

## Terminal states (e.g. Dead) set this true in enter() so the StateMachine
## refuses any further transition out of them.
var is_terminal: bool = false


func enter(_prev: StringName) -> void:
	pass


func exit() -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func handle_input(_event: InputEvent) -> void:
	pass
