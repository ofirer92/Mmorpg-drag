class_name NetClient
extends Node
## T-2.3: talks to the server over a NetTransport (the real WebSocket by
## default — client/scripts/net/net_transport.gd; tests inject
## client/scripts/net/fake_transport.gd's FakeTransport instead, see
## client/tests/test_net_client.gd). Parses protocol v1 JSON
## (docs/protocol.md), drops any message type RulesProtocol.is_known()
## doesn't recognise, and routes known ones to typed signals. NEVER computes
## damage/xp/loot itself — only relays what the server said (CLAUDE.md).


## docs/protocol.md: "every 5 s".
const PING_INTERVAL_S: float = 5.0

signal connected
signal disconnected(code: int, reason: String)
## Every valid, known message, before the typed signal below also fires.
signal message(msg: Dictionary)
signal joined(data: Dictionary)
signal state(data: Dictionary)
signal left(data: Dictionary)
signal attack(data: Dictionary)
signal damage(data: Dictionary)
signal died(data: Dictionary)
signal loot(data: Dictionary)
signal chat_msg(data: Dictionary)
signal error(data: Dictionary)
signal pong(data: Dictionary)

## -1 until the first pong arrives.
var rtt_ms: float = -1.0

var _transport: NetTransport = null
var _was_open: bool = false
var _ping_accum_s: float = 0.0
var _last_ping_sent_ms: float = -1.0


func _init(transport: NetTransport = null) -> void:
	_transport = transport


## Tests call this before connect_to() to inject a FakeTransport.
func set_transport(transport: NetTransport) -> void:
	_transport = transport


## Lazily creates the real WebSocket transport if none was injected.
func connect_to(url: String) -> void:
	if _transport == null:
		_transport = NetTransport.new()
	_was_open = false
	_transport.connect_to(url)


func disconnect_from() -> void:
	if _transport != null:
		_transport.close()


func send(msg: Dictionary) -> void:
	if _transport != null:
		_transport.send_text(JSON.stringify(msg))


func join(token: String, character_id: String) -> void:
	send({"t": "join", "protocol": RulesProtocol.PROTOCOL_VERSION, "token": token, "character_id": character_id})


func _process(delta: float) -> void:
	if _transport == null:
		return
	_transport.poll(delta)

	var is_open_now: bool = _transport.is_open()
	if is_open_now and not _was_open:
		_was_open = true
		connected.emit()
	elif not is_open_now and _was_open:
		_was_open = false
		var info: Dictionary = _transport.get_close_info()
		disconnected.emit(int(info.get("code", 0)), String(info.get("reason", "")))

	while _transport.has_packet():
		_on_packet(_transport.get_packet())

	if _was_open:
		_ping_accum_s += delta
		if _ping_accum_s >= PING_INTERVAL_S:
			_ping_accum_s = 0.0
			_send_ping()


func _send_ping() -> void:
	_last_ping_sent_ms = Time.get_ticks_msec()
	send({"t": "ping", "ts": _last_ping_sent_ms})


func _on_packet(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		push_warning("NetClient: dropped a non-object message: %s" % text)
		return
	var msg: Dictionary = parsed as Dictionary
	var t: String = String(msg.get("t", ""))
	if not RulesProtocol.is_known(t):
		push_warning("NetClient: dropped unknown message type '%s'" % t)
		return

	message.emit(msg)
	match t:
		"joined":
			joined.emit(msg)
		"state":
			state.emit(msg)
		"left":
			left.emit(msg)
		"attack":
			attack.emit(msg)
		"damage":
			damage.emit(msg)
		"died":
			died.emit(msg)
		"loot":
			loot.emit(msg)
		"chat_msg":
			chat_msg.emit(msg)
		"error":
			error.emit(msg)
		"pong":
			_on_pong(msg)
		_:
			# Schema-valid C→S intent types (join/input/leave/...) never arrive
			# from a server; nothing to route.
			pass


func _on_pong(msg: Dictionary) -> void:
	pong.emit(msg)
	var ts: float = float(msg.get("ts", -1.0))
	if ts >= 0.0:
		rtt_ms = Time.get_ticks_msec() - ts
