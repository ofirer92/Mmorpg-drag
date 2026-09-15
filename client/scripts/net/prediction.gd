class_name Prediction
extends RefCounted
## T-2.3: client-side prediction + reconciliation for the LOCAL player,
## isolated from any Node/scene so it is unit-testable in isolation (see
## client/tests/test_prediction.gd).
##
## The real Player already predicts locally every physics tick — it moves
## immediately on local input via its own _physics_process (real
## RulesMovement + real map collision), which is the actual "prediction".
## This class's job is purely reconciliation: NetSession record()s what
## Player actually rendered for each sent seq (the ring buffer + history the
## class-level doc below talks about), and on_state() compares that against
## what the server says happened at the same seq. Only on a real
## disagreement (bigger than RECONCILE_EPSILON_PX — packet loss, a
## real-map collision the flat replay model doesn't know about, ...) does it
## snap and replay the still-unacked inputs forward from the server's
## truth, using the SAME pure RulesMovement functions player.gd's
## _step_physics() calls (step_horizontal/step_vertical/can_jump/
## jump_buffered/jump_cut) on a simplified flat floor (FLOOR_REST_Y) —
## client/scripts/net/fake_transport.gd's fake server uses the exact same
## step() for ITS authoritative sim, so a replay reconstructs what the real
## server would compute. This bounded, occasional replay approximation
## (never the steady-state per-tick position, which comes straight from
## Player's own real physics) is what makes "no visible jitter at 200 ms
## latency" checkable numerically without re-deriving Godot's own
## move_and_slide/collision behaviour by hand.

## How far predicted and server positions may disagree before we snap
## (px). UI/netcode tolerance, not a balance number — kept small because a
## visible snap IS the "jitter" the T-2.3 DoD says must not happen.
const RECONCILE_EPSILON_PX: float = 2.0

## Ring buffer bound: comfortably more than one RTT's worth of unacked
## inputs at 20 Hz (a 1 s RTT would still only need ~20 entries) — a bound,
## not a balance number.
const MAX_BUFFER: int = 128

## Resting y for the CharacterBody2D on the flat test floor used by both this
## class and FakeTransport — matches client/scenes/test/flat_map.tscn's
## Floor (top at y=700) minus the player's half collision height (30/2=15),
## i.e. the same floor client/tests/test_net_session.gd's FlatMap scene
## actually stands on. Map geometry, not a movement/balance literal.
const FLOOR_REST_Y: float = 685.0

## Unacknowledged inputs, oldest first: {seq, dir, jump_held, delta}.
var _buffer: Array[Dictionary] = []
## seq -> the position Player actually rendered right after that input was
## applied (see record()) — "the predicted position" the class doc above and
## docs/protocol.md's reconciliation sequence both mean.
var _history: Dictionary = {}


static func _initial_state(pos: Vector2) -> Dictionary:
	return {
		"pos": pos,
		"vel": Vector2.ZERO,
		"time_since_floor": 0.0,
		"time_since_jump_press": -1.0,
		"jump_held_prev": false,
	}


## Pure function: one physics tick of the simplified flat-floor model, given
## a previous state dict (same shape _initial_state() returns) and this
## tick's input. Mirrors player.gd's _step_physics() horizontal/vertical/
## jump handling exactly, minus facing/hitbox/attack (Prediction only cares
## about pos/vel) and minus real collision (FLOOR_REST_Y stands in for it).
static func step(state: Dictionary, dir: float, jump_held: bool, delta: float) -> Dictionary:
	var pos: Vector2 = state.pos
	var vel: Vector2 = state.vel
	var time_since_floor: float = state.time_since_floor
	var time_since_jump_press: float = state.time_since_jump_press
	var jump_held_prev: bool = state.jump_held_prev

	vel.x = RulesMovement.step_horizontal(vel.x, dir, delta)

	var on_floor_before: bool = is_equal_approx(pos.y, FLOOR_REST_Y) and vel.y >= 0.0
	if on_floor_before:
		time_since_floor = 0.0
	else:
		time_since_floor += delta

	if jump_held and not jump_held_prev:
		time_since_jump_press = 0.0
	elif time_since_jump_press >= 0.0:
		time_since_jump_press += delta
		if not RulesMovement.jump_buffered(time_since_jump_press):
			time_since_jump_press = -1.0

	var wants_jump: bool = time_since_jump_press >= 0.0 and RulesMovement.jump_buffered(time_since_jump_press)
	if wants_jump and RulesMovement.can_jump(on_floor_before, time_since_floor):
		vel.y = RulesMovement.JUMP_VELOCITY_PX
		time_since_jump_press = -1.0
		time_since_floor = RulesMovement.COYOTE_TIME_S + 1.0
	else:
		vel.y = RulesMovement.step_vertical(vel.y, delta)

	if jump_held_prev and not jump_held and vel.y < 0.0:
		vel.y = RulesMovement.jump_cut(vel.y)
	jump_held_prev = jump_held

	pos += vel * delta
	if pos.y >= FLOOR_REST_Y and vel.y >= 0.0:
		pos.y = FLOOR_REST_Y
		vel.y = 0.0

	return {
		"pos": pos,
		"vel": vel,
		"time_since_floor": time_since_floor,
		"time_since_jump_press": time_since_jump_press,
		"jump_held_prev": jump_held_prev,
	}


## Clears the ring buffer/history — called once NetSession learns the
## player's spawn position from `joined` (a fresh join has nothing to
## reconcile yet).
func reset(_pos: Vector2) -> void:
	_buffer.clear()
	_history.clear()


## NetSession calls this once per sent `input`, right after Player's own
## _physics_process already applied that tick's input — `pos`/`vel` are
## Player's REAL rendered state, `dir`/`jump_held`/`delta` are what was sent.
## Bounds the ring buffer to MAX_BUFFER (drops the oldest unacked entry).
func record(seq: int, pos: Vector2, vel: Vector2, dir: float, jump_held: bool, delta: float) -> void:
	_buffer.append({"seq": seq, "pos": pos, "vel": vel, "dir": dir, "jump_held": jump_held, "delta": delta})
	if _buffer.size() > MAX_BUFFER:
		_buffer.pop_front()
	_history[seq] = pos


## The server's `state` said `last_seq` is the newest input it applied for
## us, landing at `server_pos`/`server_vel`. If that disagrees with what we
## predicted at the same seq by more than RECONCILE_EPSILON_PX, snap to the
## server's truth and replay every input still in the buffer newer than
## `last_seq` (the same pure step() above) to catch back up to "now".
## Returns {corrected: bool, pos: Vector2, vel: Vector2} — NetSession only
## touches the real Player when corrected is true.
func on_state(server_pos: Vector2, server_vel: Vector2, last_seq: int) -> Dictionary:
	var corrected: bool = false
	var result_pos: Vector2 = server_pos
	var result_vel: Vector2 = server_vel
	if _history.has(last_seq):
		var predicted_pos: Vector2 = _history[last_seq]
		if predicted_pos.distance_to(server_pos) > RECONCILE_EPSILON_PX:
			corrected = true
			var replay_state: Dictionary = _initial_state(server_pos)
			replay_state.vel = server_vel
			for entry: Dictionary in _buffer:
				if int(entry.seq) > last_seq:
					replay_state = step(replay_state, float(entry.dir), bool(entry.jump_held), float(entry.delta))
			result_pos = replay_state.pos
			result_vel = replay_state.vel

	var kept_buffer: Array[Dictionary] = []
	for entry: Dictionary in _buffer:
		if int(entry.seq) > last_seq:
			kept_buffer.append(entry)
	_buffer = kept_buffer
	for seq: Variant in _history.keys().duplicate():
		if int(seq) <= last_seq:
			_history.erase(seq)

	return {"corrected": corrected, "pos": result_pos, "vel": result_vel}


func buffer_size() -> int:
	return _buffer.size()
