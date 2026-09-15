class_name NetSmoke
extends Node2D
## T-2.3 DoD: headless connectivity check against a REAL server, using the
## real WebSocket transport (client/scripts/net/net_transport.gd) — never
## FakeTransport. Connects, joins, sends 40 `input`s over 2 s (matching
## docs/protocol.md's 20 Hz cadence), prints one JSON summary line, then
## quits: exit 0 once it has joined and received at least one `state`
## (with the 40 inputs sent), exit 1 on any failure or a 10 s timeout.
##
## Run (from repo root):
##   HAMIRPAA_SERVER_URL=ws://127.0.0.1:8080 \
##     /tmp/godot/Godot_v4.3-stable_linux.x86_64 --headless --path client \
##     res://scenes/test/net_smoke.tscn
## (HAMIRPAA_SERVER_URL defaults to ws://127.0.0.1:8080 if unset; a
## `--server=ws://host:port` cmdline arg also works, same precedence as
## main.gd's _resolve_net_url().)

const DEFAULT_URL: String = "ws://127.0.0.1:8080"
const INPUT_COUNT: int = 40
const INPUT_INTERVAL_S: float = 2.0 / float(INPUT_COUNT)
const TIMEOUT_S: float = 10.0
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


func _ready() -> void:
	var url: String = _resolve_url()
	_client = NetClient.new()
	add_child(_client)
	_client.connected.connect(func() -> void: _client.join(DEV_TOKEN, DEV_CHARACTER_ID))
	_client.joined.connect(_on_joined)
	_client.state.connect(_on_state)
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
			_client.send({"t": "input", "seq": _sent, "tick": _server_tick, "dir": 1, "jump": false, "attack": false})

	if _joined and _sent >= INPUT_COUNT and _states_received > 0:
		_finish(true)
	elif _elapsed_s >= TIMEOUT_S:
		_finish(false)


func _on_joined(data: Dictionary) -> void:
	_joined = true
	_my_player_id = String(data.get("player_id", ""))
	# docs/protocol.md: `input.tick` must stay within ±40 of the server's OWN
	# tick counter, which is whatever it happened to be at boot + uptime —
	# never assume it starts near 0 (see NetSession._on_joined() for the
	# same convention).
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


func _on_error(data: Dictionary) -> void:
	push_warning("net_smoke: server error %s (%s)" % [String(data.get("code", "")), String(data.get("msg_key", ""))])


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
	}
	print(JSON.stringify(summary))
	get_tree().quit(0 if success else 1)
