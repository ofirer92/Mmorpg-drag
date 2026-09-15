class_name FakeTransport
extends NetTransport
## T-2.3: in-process fake server for GUT tests (client/tests/test_net_client.gd,
## test_net_session.gd) — speaks protocol v1 JSON (docs/protocol.md) over two
## queues instead of a real socket, each held back by `one_way_latency_s`
## (0.1 s + 0.1 s = the 200 ms round trip T-2.3's DoD requires). Its
## authoritative movement sim is Prediction.step() — the SAME pure function
## NetSession's client-side prediction replays — so client and "server"
## agree on physics exactly and reconciliation only ever fires on real
## packet loss/jitter, not on model drift. NOT a substitute for T-2.2's real
## server: it only ever tracks one connecting player and never validates/
## rate-limits anything — see client/scripts/test/net_smoke.gd for the real
## thing.
##
## Time is advanced explicitly via poll(delta) (called by NetClient._process,
## itself driven by GUT's simulate(node, frames, delta) in tests) rather than
## OS time, so latency tests are exact and instant to run.

const SPAWN_X: float = 150.0

## Test-only introspection: every message this fake server ever received (in
## arrival order, i.e. AFTER the simulated one-way latency), regardless of
## whether it was ever applied — lets tests assert exactly what NetClient
## sent without depending on internal replay timing.
var received_log: Array[Dictionary] = []

var one_way_latency_s: float = 0.0
var player_name: String = "tester"

var _time: float = 0.0
var _open: bool = false
var _c2s: Array[Dictionary] = []
var _s2c: Array[Dictionary] = []
var _tick_accum_s: float = 0.0
var _server_tick: int = 0
var _player_id: String = ""
var _joined: bool = false
var _state: Dictionary = {}
var _last_seq: int = -1
var _input_queue: Array[Dictionary] = []
var _next_id: int = 1


func _init(latency_s: float = 0.0) -> void:
	one_way_latency_s = latency_s


func connect_to(_url: String) -> Error:
	_open = true
	return OK


func poll(delta: float) -> void:
	if not _open:
		return
	_time += delta
	_drain_c2s()
	_tick_accum_s += delta
	var tick_s: float = RulesConstants.TICK_MS / 1000.0
	while _tick_accum_s >= tick_s:
		_tick_accum_s -= tick_s
		_step_tick(tick_s)


func is_open() -> bool:
	return _open


func is_connecting() -> bool:
	return false


func send_text(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return
	var msg: Dictionary = parsed as Dictionary
	received_log.append(msg)
	_c2s.append({"ready_at": _time + one_way_latency_s, "msg": msg})


func has_packet() -> bool:
	return not _s2c.is_empty() and float(_s2c[0].ready_at) <= _time


func get_packet() -> String:
	var entry: Dictionary = _s2c.pop_front()
	return String(entry.text)


func close(_code: int = 1000, _reason: String = "") -> void:
	_open = false


func get_close_info() -> Dictionary:
	return {"code": 1000, "reason": "fake_transport_closed"}


func _drain_c2s() -> void:
	while not _c2s.is_empty() and float(_c2s[0].ready_at) <= _time:
		var entry: Dictionary = _c2s.pop_front()
		_handle(entry.msg as Dictionary)


func _handle(msg: Dictionary) -> void:
	match String(msg.get("t", "")):
		"join":
			_on_join()
		"input":
			_on_input(msg)
		"ping":
			_enqueue({"t": "pong", "ts": msg.get("ts", 0), "server_ts": int(_time * 1000.0)})
		_:
			pass


func _on_join() -> void:
	_player_id = "p_%d" % _next_id
	_next_id += 1
	_joined = true
	_state = {
		"pos": Vector2(SPAWN_X, Prediction.FLOOR_REST_Y),
		"vel": Vector2.ZERO,
		"time_since_floor": 0.0,
		"time_since_jump_press": -1.0,
		"jump_held_prev": false,
	}
	_last_seq = -1
	_input_queue.clear()
	_enqueue(
		{
			"t": "joined",
			"player_id": _player_id,
			"zone_id": "fake_zone",
			"tick": _server_tick,
			"tick_ms": int(RulesConstants.TICK_MS),
			"state": _snapshot(),
		}
	)


func _on_input(msg: Dictionary) -> void:
	if not _joined:
		return
	_input_queue.append({"seq": int(msg.get("seq", 0)), "dir": float(msg.get("dir", 0)), "jump": bool(msg.get("jump", false))})


## Drains at most one queued input per server tick (protocol.md: "server:
## queue intent; drain inside zone.step(dt)") — the real server's own
## cadence, independent of when packets happen to arrive.
func _step_tick(tick_s: float) -> void:
	_server_tick += 1
	if not _joined:
		return
	if not _input_queue.is_empty():
		var next_input: Dictionary = _input_queue.pop_front()
		_state = Prediction.step(_state, float(next_input.dir), bool(next_input.jump), tick_s)
		_last_seq = int(next_input.seq)
	_enqueue({"t": "state", "tick": _server_tick, "last_seq": {_player_id: _last_seq}, "players": [_player_view()], "monsters": [], "drops": []})


func _player_view() -> Dictionary:
	var pos: Vector2 = _state.pos
	var vel: Vector2 = _state.vel
	return {
		"id": _player_id,
		"name": player_name,
		"pos": {"x": pos.x, "y": pos.y},
		"vel": {"x": vel.x, "y": vel.y},
		"hp": 100,
		"max_hp": 100,
		"level": 1,
		"xp": 0,
		"facing": -1 if vel.x < 0.0 else 1,
		"anim": "run" if absf(vel.x) > 1.0 else "idle",
		"alive": true,
	}


func _snapshot() -> Dictionary:
	if not _joined:
		return {"tick": _server_tick, "last_seq": {}, "players": [], "monsters": [], "drops": []}
	return {
		"tick": _server_tick,
		"last_seq": {_player_id: _last_seq},
		"players": [_player_view()],
		"monsters": [],
		"drops": [],
	}


func _enqueue(msg: Dictionary) -> void:
	_s2c.append({"ready_at": _time + one_way_latency_s, "text": JSON.stringify(msg)})
