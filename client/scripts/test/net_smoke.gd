class_name NetSmoke
extends Node2D
## T-2.3 + T-2.4 DoD: headless end-to-end check against a REAL server, using the real WebSocket
## transport (client/scripts/net/net_transport.gd) — never FakeTransport. It joins, walks toward the
## nearest monster, attacks it, and reports what the SERVER said: the monster's hp before and after,
## and the `damage` facts it received. Prints one JSON summary line, then quits: exit 0 when it
## joined, received `state`s, reached a monster and landed at least one server-confirmed hit;
## exit 1 on any failure or timeout.
##
## Run (from repo root):
##   HAMIRPAA_SERVER_URL=ws://127.0.0.1:8080 \
##     /tmp/godot/Godot_v4.3-stable_linux.x86_64 --headless --path client \
##     res://scenes/test/net_smoke.tscn
## (HAMIRPAA_SERVER_URL defaults to ws://127.0.0.1:8080 if unset; a `--server=ws://host:port`
## cmdline arg also works, same precedence as main.gd's _resolve_net_url().)

const DEFAULT_URL: String = "ws://127.0.0.1:8080"
const INPUT_COUNT: int = 120
const INPUT_INTERVAL_S: float = 1.0 / float(RulesConstants.TICK_RATE_HZ)
const TIMEOUT_S: float = 25.0
## Close enough that the server's own range check (the basic skill's range_px) will find the monster.
const ATTACK_RANGE_PX: float = 30.0
## T-2.3: no auth/character-select flow exists yet — see main.gd's DEV_TOKEN.
const DEV_TOKEN: String = "dev-token"
const DEV_CHARACTER_ID: String = "char_dev"

var _client: NetClient = null
var _joined: bool = false
var _my_player_id: String = ""
var _states_received: int = 0
var _last_seq: int = 0
var _sent: int = 0
var _server_tick: int = 0
var _elapsed_s: float = 0.0
var _send_accum_s: float = 0.0
var _others: Array[String] = []
var _my_pos: Dictionary = {"x": 0.0, "y": 0.0}
var _done: bool = false

# T-2.4 combat observations, all taken from server facts only.
var _target_id: String = ""
var _target_hp_first: int = -1
var _target_hp_last: int = -1
var _target_dx: float = 0.0
var _hits_landed: int = 0
var _damage_dealt: int = 0
var _in_range: bool = false
var _target_alive: bool = true


func _ready() -> void:
	var url: String = _resolve_url()
	_client = NetClient.new()
	add_child(_client)
	_client.connected.connect(func() -> void: _client.join(DEV_TOKEN, DEV_CHARACTER_ID))
	_client.joined.connect(_on_joined)
	_client.state.connect(_on_state)
	_client.damage.connect(_on_damage)
	_client.error.connect(_on_error)
	_client.disconnected.connect(_on_disconnected)
	_client.connect_to(url)


func _resolve_url() -> String:
	var env_url: String = OS.get_environment("HAMIRPAA_SERVER_URL")
	if env_url != "":
		return env_url
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("--server="):
			return arg.substr("--server=".length())
	return DEFAULT_URL


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed_s += delta

	if _joined and _sent < INPUT_COUNT:
		_send_accum_s += delta
		while _send_accum_s >= INPUT_INTERVAL_S and _sent < INPUT_COUNT:
			_send_accum_s -= INPUT_INTERVAL_S
			_sent += 1
			_server_tick += 1
			# Walk toward the nearest monster until in range, then stand still and attack.
			var dir: int = 0
			if not _in_range:
				dir = 1 if _target_dx >= 0.0 else -1
			_client.send(
				{
					"t": "input",
					"seq": _sent,
					"tick": _server_tick,
					"dir": dir,
					"jump": false,
					"attack": _in_range,
				}
			)

	if _joined and _target_id != "" and not _target_alive:
		_finish(true)  # the server reported our target dead — combat round-trip proven
	elif _joined and _sent >= INPUT_COUNT and _states_received > 0:
		_finish(_hits_landed > 0)
	elif _elapsed_s >= TIMEOUT_S:
		_finish(false)


func _on_joined(data: Dictionary) -> void:
	_joined = true
	_my_player_id = String(data.get("player_id", ""))
	# docs/protocol.md: `input.tick` must stay within ±40 of the server's OWN tick counter, which is
	# whatever it happened to be at boot + uptime — never assume it starts near 0 (see
	# NetSession._on_joined() for the same convention).
	_server_tick = int(data.get("tick", 0))


func _on_state(data: Dictionary) -> void:
	_states_received += 1
	var players: Array = data.get("players", [])
	_others.clear()
	for raw: Variant in players:
		var p: Dictionary = raw
		var id: String = String(p.get("id", ""))
		if id == "":
			continue
		if id == _my_player_id:
			_my_pos = p.get("pos", {"x": 0.0, "y": 0.0})
		else:
			_others.append(id)
	var last_seq_map: Dictionary = data.get("last_seq", {})
	_last_seq = int(last_seq_map.get(_my_player_id, 0))
	_track_target(data.get("monsters", []))


## Locks onto the nearest living monster the server reports on first sight and follows THAT one for
## the rest of the run — re-targeting after a kill would silently replace the hp trajectory this test
## exists to show. Every number here comes from the server; the client never computes damage
## (ADR-013/ADR-017).
func _track_target(monsters: Array) -> void:
	var my_x: float = float(_my_pos.get("x", 0.0))
	if _target_id == "":
		var best_dx: float = 0.0
		for raw: Variant in monsters:
			var candidate: Dictionary = raw
			if not bool(candidate.get("alive", false)):
				continue
			var candidate_pos: Dictionary = candidate.get("pos", {})
			var candidate_dx: float = float(candidate_pos.get("x", 0.0)) - my_x
			if _target_id == "" or absf(candidate_dx) < absf(best_dx):
				_target_id = String(candidate.get("id", ""))
				best_dx = candidate_dx
				_target_hp_first = int(candidate.get("hp", 0))
		if _target_id == "":
			return
		_target_dx = best_dx

	for raw: Variant in monsters:
		var m: Dictionary = raw
		if String(m.get("id", "")) != _target_id:
			continue
		var pos: Dictionary = m.get("pos", {})
		_target_hp_last = int(m.get("hp", 0))
		_target_alive = bool(m.get("alive", false))
		_target_dx = float(pos.get("x", 0.0)) - my_x
		_in_range = _target_alive and absf(_target_dx) <= ATTACK_RANGE_PX
		return


func _on_damage(data: Dictionary) -> void:
	if String(data.get("attacker_id", "")) != _my_player_id:
		return
	_hits_landed += 1
	_damage_dealt += int(data.get("amount", 0))


func _on_error(data: Dictionary) -> void:
	push_warning(
		"net_smoke: server error %s (%s)" % [String(data.get("code", "")), String(data.get("msg_key", ""))]
	)


func _on_disconnected(_code: int, _reason: String) -> void:
	if not _done:
		_finish(false)


func _finish(success: bool) -> void:
	_done = true
	var summary: Dictionary = {
		"joined": _joined,
		"states_received": _states_received,
		"last_seq": _last_seq,
		"my_pos": _my_pos,
		"others": _others,
		"target_id": _target_id,
		"target_hp_first": _target_hp_first,
		"target_hp_last": _target_hp_last,
		"target_alive": _target_alive,
		"hits_landed": _hits_landed,
		"damage_dealt": _damage_dealt,
	}
	print(JSON.stringify(summary))
	get_tree().quit(0 if success else 1)
