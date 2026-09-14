---
name: godot-conventions
description: Godot 4.3 / GDScript conventions for this project — character scene template, state machine, GUT tests, Godot 4 pitfalls, mobile virtual joystick, export presets. Load before any work under client/.
---
# Godot conventions (Hamirpaa)

## Scene = .tscn + one script
One script per scene root. Child nodes communicate up via signals, down via direct calls. No logic in `_process` when a signal or timer works.

## Character scene template
```
Player (CharacterBody2D)            # scripts/player/player.gd
├── Sprite2D
├── AnimationPlayer
├── CollisionShape2D
├── StateMachine (Node)             # scripts/player/state_machine.gd
│   ├── Idle / Run / Jump / Attack / Hurt / Dead   (each extends State)
└── HurtBox (Area2D)
```

```gdscript
# scripts/player/state.gd
class_name State
extends Node
signal transition_requested(to: StringName)
var actor: CharacterBody2D
func enter(_prev: StringName) -> void: pass
func exit() -> void: pass
func physics_update(_delta: float) -> void: pass
func handle_input(_event: InputEvent) -> void: pass
```

```gdscript
# scripts/player/state_machine.gd
class_name StateMachine
extends Node
@export var initial: StringName = &"Idle"
var current: State
var states: Dictionary = {}
func _ready() -> void:
    for child: Node in get_children():
        if child is State:
            var s: State = child
            states[child.name] = s
            s.actor = get_parent() as CharacterBody2D
            s.transition_requested.connect(_on_transition)
    current = states[initial]
    current.enter(&"")
func _physics_process(delta: float) -> void:
    current.physics_update(delta)
func _on_transition(to: StringName) -> void:
    if not states.has(to) or states[to] == current: return
    var prev: StringName = current.name
    current.exit()
    current = states[to]
    current.enter(prev)
```
Movement constants (speed, jump velocity, coyote time, jump buffer) are NOT literals: read them from `Rules.movement()` in `client/scripts/rules/` (generated).

## GUT tests
File: `client/tests/test_<thing>.gd`, `extends GutTest`. Use `add_child_autofree(scene.instantiate())`, `simulate(node, frames, delta)`, `assert_eq`, `assert_almost_eq`, `watch_signals` + `assert_signal_emitted`.
Run: `scripts/test_client.sh`. A test that only instantiates a scene is not a test.

## Godot 4 pitfalls
- `yield` → `await signal`. `await get_tree().process_frame`.
- `TileMap` is deprecated → `TileMapLayer` (one layer per node).
- `export var` → `@export var`. `onready` → `@onready`.
- `instance()` → `instantiate()`. `connect("sig", self, "fn")` → `sig.connect(fn)`.
- `move_and_slide()` takes no args; set `velocity` first.
- `randi()` is not seeded deterministically — tests use `seed(42)`.
- `String` formatting: `"%d hp" % hp`; Hebrew RTL needs `TextServer` support, keep `Label.text_direction = AUTO`.
- Typed arrays: `var xs: Array[int] = []`.

## Mobile controls
`scenes/ui/touch_controls.tscn`: a `VirtualJoystick` (Control with a deadzone, emits `direction_changed(Vector2)`) on the left and 3 `TouchScreenButton`s (jump / attack / skill) on the right, plus an `auto_attack` toggle. Actions map to InputMap names `move_left/right`, `jump`, `attack`, `skill_1`. Hide when `DisplayServer.is_touchscreen_available()` is false.
Test every UI at 390×844 first (project setting `display/window/size`), then 1920×1080. Use `Control.anchors_preset`, never absolute pixels.

## Export presets (client/export_presets.cfg)
Android: min SDK 24, permissions = INTERNET only, keystore from env `ANDROID_KEYSTORE`. iOS: privacy manifest, no tracking. Windows: x86_64, embed pck. Web: threads off (SharedArrayBuffer issues), WSS only, target < 30 MB.
`scripts/export_builds.sh` runs `godot --headless --export-release <preset> <path>`.
