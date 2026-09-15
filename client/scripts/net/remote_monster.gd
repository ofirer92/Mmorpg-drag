class_name RemoteMonster
extends Node2D
## T-2.4: server-driven view of one `MonsterState` entry (docs/protocol.md).
## Spawned/updated/removed by client/scripts/combat/remote_authority.gd from
## `state.monsters`, exactly the way client/scripts/net/remote_player.gd
## renders `state.players` — buffered + interpolated, NEVER computing an AI
## decision or a damage number itself (CLAUDE.md: the client only ever
## displays what the server already decided). `apply_state()`/`set_hp_display()`
## are the only writes; nothing else touches this node's game state.

## Render this far behind the newest snapshot — same constant/reasoning as
## RemotePlayer.INTERP_DELAY_MS (kept in sync intentionally; UI/netcode
## constant, not a balance number).
const INTERP_DELAY_MS: float = 100.0
const MAX_BUFFER: int = 32

@onready var sprite: Sprite2D = $Sprite2D
@onready var hp_bar: ProgressBar = $HpBar
@onready var name_label: Label = $NameLabel

var monster_id: String = ""
var kind: String = ""
## Oldest first: {t_ms (local receive clock), pos, facing, anim}.
var _buffer: Array[Dictionary] = []
var _clock_ms: float = 0.0
var _max_hp: float = 1.0


## Called by RemoteAuthority once per `state` snapshot that mentions this
## monster id.
func apply_state(monster_state: Dictionary) -> void:
	monster_id = String(monster_state.get("id", monster_id))
	var new_kind: String = String(monster_state.get("kind", kind))
	if new_kind != kind or kind == "":
		kind = new_kind
		_apply_kind_visuals()
	_max_hp = float(monster_state.get("max_hp", _max_hp))
	set_hp_display(float(monster_state.get("hp", _max_hp)))

	var pos_dict: Dictionary = monster_state.get("pos", {})
	var entry: Dictionary = {
		"t_ms": _clock_ms,
		"pos": Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0))),
		"facing": int(monster_state.get("facing", 1)),
		"anim": String(monster_state.get("anim", "idle")),
	}
	_buffer.append(entry)
	if _buffer.size() > MAX_BUFFER:
		_buffer.pop_front()
	if _buffer.size() == 1:
		global_position = entry.pos
		_apply_facing(entry.facing)


## RemoteAuthority calls this immediately on a `damage` fact (which precedes
## the next `state` per docs/protocol.md's sequence) so the hp bar reacts
## without waiting a whole tick.
func set_hp_display(hp: float) -> void:
	if hp_bar != null:
		hp_bar.max_value = max(_max_hp, 1.0)
		hp_bar.value = hp


func _apply_kind_visuals() -> void:
	var stats: Dictionary = RulesBalanceData.MONSTERS.monsters.get(kind, {})
	if name_label != null:
		name_label.text = I18n.t(String(stats.get("name_key", kind)))
	if sprite != null:
		var path: String = "res://assets/generated/monster_%s.png" % kind
		if ResourceLoader.exists(path):
			sprite.texture = load(path)
		sprite.hframes = 4
		sprite.vframes = 5


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
	if sprite != null:
		sprite.flip_h = facing < 0
