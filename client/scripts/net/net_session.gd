class_name NetSession
extends Node
## T-2.3: glue between a NetClient and this client's own Player/RemotePlayer
## nodes. Owns the Prediction for the local player, samples its input once
## per protocol tick (RulesConstants.TICK_MS) and sends it, reconciles the
## local Player when Prediction says the server disagreed enough to matter,
## and spawns/updates/removes a RemotePlayer per OTHER player in every
## `state`. main.gd wires this up when @export var net_url is non-empty;
## with no NetSession running, gameplay is exactly the phase-0
## LocalServer-only single-player mode (see main.gd's doc comment on the
## hybrid — T-2.4 moves combat to the server, T-2.9 removes LocalServer).

const RemotePlayerScene: PackedScene = preload("res://scenes/net/remote_player.tscn")

## Fires once this session's own `joined` fact has been applied — main.gd
## uses this to hide the "connecting…" HUD label.
signal ready_to_play(player_id: String)

var client: NetClient = null
var player: Player = null
var remote_container: Node2D = null
var prediction: Prediction = Prediction.new()

var my_player_id: String = ""

var _token: String = ""
var _character_id: String = ""
var _seq: int = 0
var _tick: int = 0
var _send_accum_s: float = 0.0
var _remote_players: Dictionary = {}


## Wires this session to an already-transported NetClient (real or
## FakeTransport-backed — see client/tests/test_net_session.gd) and starts
## the join handshake as soon as the transport reports `connected`.
func begin(
	net_client: NetClient,
	local_player: Player,
	container: Node2D,
	token: String = "dev-token",
	character_id: String = "char_dev"
) -> void:
	client = net_client
	player = local_player
	remote_container = container
	_token = token
	_character_id = character_id

	client.connected.connect(_on_connected)
	client.joined.connect(_on_joined)
	client.state.connect(_on_state)
	client.left.connect(_on_left)


## Convenience for main.gd: creates the NetClient (real WebSocket transport),
## adds it as a child of this session and connects to `url`.
func start(url: String, local_player: Player, container: Node2D, token: String = "dev-token", character_id: String = "char_dev") -> void:
	var c: NetClient = NetClient.new()
	add_child(c)
	begin(c, local_player, container, token, character_id)
	c.connect_to(url)


func _on_connected() -> void:
	client.join(_token, _character_id)


func _on_joined(data: Dictionary) -> void:
	my_player_id = String(data.get("player_id", ""))
	_tick = int(data.get("tick", 0))
	_seq = 0
	prediction.reset(player.global_position)
	ready_to_play.emit(my_player_id)


func _physics_process(delta: float) -> void:
	if client == null or my_player_id == "" or player == null:
		return
	_send_accum_s += delta
	var tick_s: float = RulesConstants.TICK_MS / 1000.0
	while _send_accum_s >= tick_s:
		_send_accum_s -= tick_s
		_send_input(tick_s)


func _send_input(tick_s: float) -> void:
	var input: Dictionary = player.get_last_input()
	var dir_f: float = float(input.get("dir", 0.0))
	var dir_i: int = 0
	if dir_f > 0.0:
		dir_i = 1
	elif dir_f < 0.0:
		dir_i = -1
	var jump_held: bool = bool(input.get("jump", false))

	_seq += 1
	_tick += 1
	var msg: Dictionary = {
		"t": "input",
		"seq": _seq,
		"tick": _tick,
		"dir": dir_i,
		"jump": jump_held,
		"attack": bool(input.get("attack", false)),
	}
	var skill_id: String = String(input.get("skill_id", ""))
	if skill_id != "":
		msg["skill_id"] = skill_id
	client.send(msg)

	# Player's own _physics_process already ran this tick (Player is an
	# earlier sibling — see the header comment) — this records what it
	# actually rendered for `seq`, the "predicted position" reconciliation
	# below compares against.
	prediction.record(_seq, player.position, player.velocity, float(dir_i), jump_held, tick_s)


func _on_state(data: Dictionary) -> void:
	var last_seq_map: Dictionary = data.get("last_seq", {})
	var players: Array = data.get("players", [])
	var server_tick: int = int(data.get("tick", 0))
	var seen: Dictionary = {}
	for raw: Variant in players:
		var p: Dictionary = raw
		var id: String = String(p.get("id", ""))
		if id == "":
			continue
		seen[id] = true
		if id == my_player_id:
			_reconcile(p, int(last_seq_map.get(id, -1)))
		else:
			_update_remote(id, p, server_tick)
	_prune_remote(seen)


func _reconcile(p: Dictionary, last_seq: int) -> void:
	if last_seq < 0:
		return
	var pos_dict: Dictionary = p.get("pos", {})
	var vel_dict: Dictionary = p.get("vel", {})
	var server_pos: Vector2 = Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0)))
	var server_vel: Vector2 = Vector2(float(vel_dict.get("x", 0.0)), float(vel_dict.get("y", 0.0)))
	var result: Dictionary = prediction.on_state(server_pos, server_vel, last_seq)
	if bool(result.corrected):
		player.apply_authoritative(result.pos, result.vel)


func _update_remote(id: String, p: Dictionary, server_tick: int) -> void:
	var rp: RemotePlayer
	if _remote_players.has(id):
		rp = _remote_players[id]
	else:
		rp = RemotePlayerScene.instantiate()
		remote_container.add_child(rp)
		_remote_players[id] = rp
	rp.apply_state(p, server_tick)


func _prune_remote(seen: Dictionary) -> void:
	for id: String in _remote_players.keys().duplicate():
		if not seen.has(id):
			(_remote_players[id] as RemotePlayer).queue_free()
			_remote_players.erase(id)


func _on_left(data: Dictionary) -> void:
	var id: String = String(data.get("player_id", ""))
	if _remote_players.has(id):
		(_remote_players[id] as RemotePlayer).queue_free()
		_remote_players.erase(id)
