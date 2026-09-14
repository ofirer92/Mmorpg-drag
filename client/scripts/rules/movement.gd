# GENERATED from packages/shared-rules/src/movement.ts sha256:ff8c24f87cac0aac — DO NOT EDIT (run scripts/gen_rules.py)
class_name RulesMovement

# Player movement constants + helpers. RulesScript subset. Numbers here are the ONLY source for
# client/scripts/rules/movement.gd — the client never types a speed or gravity literal.
const MOVE_SPEED_PX: float = 220.0
const ACCEL_PX: float = 1800.0
const FRICTION_PX: float = 2200.0
const GRAVITY_PX: float = 1800.0
const FALL_GRAVITY_MULT: float = 1.6
const JUMP_VELOCITY_PX: float = -520.0
const JUMP_CUT_MULT: float = 0.45
const MAX_FALL_SPEED_PX: float = 900.0
const COYOTE_TIME_S: float = 0.1
const JUMP_BUFFER_S: float = 0.12

# Horizontal velocity after one physics step given input direction (-1..1).

static func step_horizontal(vx: float, dir: float, delta: float) -> float:
	var target: float = dir * MOVE_SPEED_PX
	if dir == 0.0:
		if vx > 0.0:
			return max(0.0, vx - FRICTION_PX * delta)
		return min(0.0, vx + FRICTION_PX * delta)
	if vx < target:
		return min(target, vx + ACCEL_PX * delta)
	return max(target, vx - ACCEL_PX * delta)

# Vertical velocity after one physics step. Falling uses stronger gravity for a snappier arc.

static func step_vertical(vy: float, delta: float) -> float:
	var g: float = GRAVITY_PX
	if vy > 0.0:
		g = GRAVITY_PX * FALL_GRAVITY_MULT
	return min(MAX_FALL_SPEED_PX, vy + g * delta)

# A jump is allowed if grounded now, or left the ground less than COYOTE_TIME_S ago.

static func can_jump(on_floor: bool, time_since_floor: float) -> bool:
	if on_floor:
		return true
	return time_since_floor <= COYOTE_TIME_S

# A jump press is still "buffered" if it happened less than JUMP_BUFFER_S ago.

static func jump_buffered(time_since_press: float) -> bool:
	return time_since_press >= 0.0 and time_since_press <= JUMP_BUFFER_S

# Releasing jump early cuts upward velocity.

static func jump_cut(vy: float) -> float:
	if vy < 0.0:
		return vy * JUMP_CUT_MULT
	return vy
