class_name StateMachine
extends Node
## Owns a set of PlayerState children and switches between them (T-0.2).
## Child node names ARE the state names: "Idle", "Run", "Jump", "Attack", "Hurt", "Dead".

@export var initial: StringName = &"Idle"

var current: PlayerState
var states: Dictionary = {}


func _ready() -> void:
	for child: Node in get_children():
		if child is PlayerState:
			var s: PlayerState = child
			states[child.name] = s
			s.actor = get_parent() as Player
			s.transition_requested.connect(_on_transition)
	if states.has(initial):
		current = states[initial]
		current.enter(&"")


func _physics_process(delta: float) -> void:
	if current != null:
		current.physics_update(delta)


## Force a transition from outside the current state (e.g. player.gd reacting
## to a server-driven hurt/death event). Same rules as an internal request:
## unknown names are ignored, terminal states cannot be left.
func request_transition(to: StringName) -> void:
	_on_transition(to)


## T-0.10: bypasses the terminal-state guard. ONLY for an engineering reset
## like a respawn — never for gameplay transitions, which must keep going
## through request_transition/_on_transition and respect is_terminal (Dead
## staying Dead until something outside the state machine, like a respawn,
## explicitly resets it).
func force_enter(to: StringName) -> void:
	if not states.has(to):
		return
	if current != null:
		current.exit()
	current = states[to]
	current.enter(&"")


func _on_transition(to: StringName) -> void:
	if current == null or current.is_terminal:
		return
	if not states.has(to) or states[to] == current:
		return
	var prev: StringName = current.name
	current.exit()
	current = states[to]
	current.enter(prev)
