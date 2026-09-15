class_name RemotePlayer
extends Node2D
## T-2.3: lightweight visual for another joined player. Buffers the last
## few `state` snapshots (apply_state()) and renders INTERP_DELAY_MS behind
## the newest one, lerping between the two straddling snapshots — never
## predicts or computes anything of its own; it only ever plays back what
## the server already said happened (CLAUDE.md — the client never computes
## damage/xp/position, it displays facts).

## Render this far behind the newest snapshot so there are always two known
## points to lerp between even with some jitter/packet loss. UI/netcode
## constant, not a balance number.
const INTERP_DELAY_MS: float = 100.0
## Bounds the snapshot buffer so a stalled connection can't grow it forever.
const MAX_BUFFER: int = 32

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel

var player_id: String = ""
## Oldest first: {tick, t_ms (local receive clock), pos, facing, anim}.
var _buffer: Array[Dictionary] = []
var _clock_ms: float = 0.0


## Called by NetSession once per `state` snapshot that mentions this player.
func apply_state(player_state: Dictionary, server_tick: int) -> void:
	player_id = String(player_state.get("id", player_id))
	name_label.text = String(player_state.get("name", player_id))
	var pos_dict: Dictionary = player_state.get("pos", {})
	var entry: Dictionary = {
		"tick": server_tick,
		"t_ms": _clock_ms,
		"pos": Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0))),
		"facing": int(player_state.get("facing", 1)),
		"anim": String(player_state.get("anim", "idle")),
	}
	_buffer.append(entry)
	if _buffer.size() > MAX_BUFFER:
		_buffer.pop_front()
	if _buffer.size() == 1:
		# First sighting: nothing to interpolate from yet, show it immediately.
		global_position = entry.pos
		_apply_facing(entry.facing)


func _process(delta: float) -> void:
	_clock_ms += delta * 1000.0
	_interpolate()


func _interpolate() -> void:
	if _buffer.is_empty():
		return
	if _buffer.size() < 2:
		global_position = _buffer[-1].pos
		_apply_facing(_buffer[-1].facing)
		return

	var render_t: float = _clock_ms - INTERP_DELAY_MS
	var older: Dictionary = _buffer[0]
	var newer: Dictionary = _buffer[-1]
	for i in range(_buffer.size() - 1):
		if float(_buffer[i].t_ms) <= render_t and render_t <= float(_buffer[i + 1].t_ms):
			older = _buffer[i]
			newer = _buffer[i + 1]
			break

	if render_t <= float(older.t_ms):
		global_position = older.pos
		_apply_facing(older.facing)
		return
	if render_t >= float(newer.t_ms):
		global_position = newer.pos
		_apply_facing(newer.facing)
		return

	var span: float = float(newer.t_ms) - float(older.t_ms)
	var f: float = 0.0 if span <= 0.0 else clampf((render_t - float(older.t_ms)) / span, 0.0, 1.0)
	global_position = (older.pos as Vector2).lerp(newer.pos, f)
	_apply_facing(newer.facing)


func _apply_facing(facing: int) -> void:
	sprite.flip_h = facing < 0
