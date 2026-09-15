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

## T-2.4: this fake server's combat is a TEST DOUBLE, not RulesCombat — it
## deals a fixed amount per accepted attack and always drops the same test
## item, deliberately NOT reusing real balance numbers (a real server would
## call shared-rules; this only needs to prove the CLIENT never computes
## damage itself and only ever reacts to the facts below).
const TEST_DAMAGE_PER_HIT: float = 10.0
const TEST_MONSTER_XP: float = 10.0
const TEST_MONSTER_MONEY: int = 5
const TEST_DROP_ITEM_ID: String = "test_item"

## Test-only introspection: every message this fake server ever received (in
## arrival order, i.e. AFTER the simulated one-way latency), regardless of
## whether it was ever applied — lets tests assert exactly what NetClient
## sent without depending on internal replay timing.
var received_log: Array[Dictionary] = []

var one_way_latency_s: float = 0.0
var player_name: String = "tester"

## T-2.4: test hooks for the combat half of protocol v1 — see the class
## header. Set before connect_to() (or any time before the join handshake
## needs them).
var monster_id: String = "m_1"
var monster_kind: String = "side_effect_slime"
var monster_hp: float = 30.0
var monster_max_hp: float = 30.0
var monster_alive: bool = true
var monster_pos: Vector2 = Vector2(SPAWN_X + 60.0, Prediction.FLOOR_REST_Y)
## Test hook: forces the next loot_pickup to be answered `added: false`
## (bag full / out of range / already taken — docs/protocol.md § Loot),
## regardless of whether a real unclaimed drop exists.
var force_loot_rejected: bool = false
## Test hook: this fake server has no monster AI (see class header), so a
## test that wants to check the HUD reacts to the LOCAL PLAYER taking damage
## calls deal_damage_to_player() directly instead.
var player_hp: float = 100.0
var player_max_hp: float = 100.0

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
var _next_drop_id: int = 1
## {} when there is no unclaimed drop, else {id, pos, item_id, money, expires_tick}.
var _drop: Dictionary = {}


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
		"loot_pickup":
			_on_loot_pickup(msg)
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
	_input_queue.append(
		{
			"seq": int(msg.get("seq", 0)),
			"dir": float(msg.get("dir", 0)),
			"jump": bool(msg.get("jump", false)),
			"attack": bool(msg.get("attack", false)),
			"skill_id": String(msg.get("skill_id", "")),
		}
	)


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
		if bool(next_input.get("attack", false)) and monster_alive:
			_resolve_attack(String(next_input.get("skill_id", "")))
	_enqueue(
		{
			"t": "state",
			"tick": _server_tick,
			"last_seq": {_player_id: _last_seq},
			"players": [_player_view()],
			"monsters": [_monster_view()] if monster_alive else [],
			"drops": _drops_view(),
		}
	)


## Deliberately NOT real combat math (RulesCombat lives in rules/ — this is a
## test double, see TEST_DAMAGE_PER_HIT's doc comment): announces the attack
## (animation cue), deals a fixed hit, and — on the killing blow — enqueues
## `died` with a drop the client picks up on a later `state`, exactly the
## sequence docs/protocol.md § "Attack → damage → death" describes.
func _resolve_attack(skill_id: String) -> void:
	var target_ids: Array[String] = [monster_id]
	_enqueue({"t": "attack", "attacker_id": _player_id, "skill_id": skill_id if skill_id != "" else null, "target_ids": target_ids})
	monster_hp = max(0.0, monster_hp - TEST_DAMAGE_PER_HIT)
	_enqueue({"t": "damage", "target_id": monster_id, "attacker_id": _player_id, "amount": TEST_DAMAGE_PER_HIT, "new_hp": monster_hp, "crit": false})
	if monster_hp <= 0.0 and monster_alive:
		monster_alive = false
		var drop_id: String = "d_%d" % _next_drop_id
		_next_drop_id += 1
		_drop = {
			"id": drop_id,
			"pos": {"x": monster_pos.x, "y": monster_pos.y},
			"item_id": TEST_DROP_ITEM_ID,
			"money": TEST_MONSTER_MONEY,
			"expires_tick": _server_tick + 200,
		}
		_enqueue(
			{
				"t": "died",
				"id": monster_id,
				"killer_id": _player_id,
				"xp": TEST_MONSTER_XP,
				"drop_id": drop_id,
				"item_id": TEST_DROP_ITEM_ID,
				"money": TEST_MONSTER_MONEY,
			}
		)


func _monster_view() -> Dictionary:
	return {
		"id": monster_id,
		"kind": monster_kind,
		"pos": {"x": monster_pos.x, "y": monster_pos.y},
		"vel": {"x": 0.0, "y": 0.0},
		"hp": monster_hp,
		"max_hp": monster_max_hp,
		"level": 1,
		"facing": -1,
		"anim": "idle",
		"alive": monster_alive,
	}


func _drops_view() -> Array:
	if _drop.is_empty():
		return []
	return [_drop]


## docs/protocol.md § Loot: `added: true` broadcast (here: our only client),
## `added: false` to the requester only, on rejection.
func _on_loot_pickup(msg: Dictionary) -> void:
	var drop_id: String = String(msg.get("drop_id", ""))
	if force_loot_rejected or _drop.is_empty() or String(_drop.get("id", "")) != drop_id:
		_enqueue({"t": "loot", "player_id": _player_id, "drop_id": drop_id, "item_id": null, "money": 0, "added": false})
		return
	var item_id: String = String(_drop.get("item_id", ""))
	var money: int = int(_drop.get("money", 0))
	_enqueue({"t": "loot", "player_id": _player_id, "drop_id": drop_id, "item_id": item_id, "money": money, "added": true})
	_drop = {}


func _player_view() -> Dictionary:
	var pos: Vector2 = _state.pos
	var vel: Vector2 = _state.vel
	return {
		"id": _player_id,
		"name": player_name,
		"pos": {"x": pos.x, "y": pos.y},
		"vel": {"x": vel.x, "y": vel.y},
		"hp": player_hp,
		"max_hp": player_max_hp,
		"level": 1,
		"xp": 0,
		"facing": -1 if vel.x < 0.0 else 1,
		"anim": "run" if absf(vel.x) > 1.0 else "idle",
		"alive": player_hp > 0.0,
	}


## Test hook (see player_hp's doc comment): announces a `damage` fact
## against the local player, e.g. to check the HUD reacts.
func deal_damage_to_player(amount: float) -> void:
	player_hp = max(0.0, player_hp - amount)
	_enqueue({"t": "damage", "target_id": _player_id, "attacker_id": monster_id, "amount": amount, "new_hp": player_hp, "crit": false})


func _snapshot() -> Dictionary:
	if not _joined:
		return {"tick": _server_tick, "last_seq": {}, "players": [], "monsters": [], "drops": []}
	return {
		"tick": _server_tick,
		"last_seq": {_player_id: _last_seq},
		"players": [_player_view()],
		"monsters": [_monster_view()] if monster_alive else [],
		"drops": _drops_view(),
	}


func _enqueue(msg: Dictionary) -> void:
	_s2c.append({"ready_at": _time + one_way_latency_s, "text": JSON.stringify(msg)})
