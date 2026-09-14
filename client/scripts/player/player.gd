class_name Player
extends CharacterBody2D
## T-0.1: moves, jumps, coyote-time, jump-buffer. All numbers come from
## RulesMovement (client/scripts/rules/movement.gd, generated) — never a
## literal speed/gravity/jump value here.
## T-0.2: drives a StateMachine (Idle/Run/Jump/Attack/Hurt/Dead) for animation
## only. This script never computes damage/XP/drop — the server does that.
## T-0.8: if a LocalServer is attached (set_local_server), the player
## registers as "player" and only ever SENDS attack intents
## (local_server.request_attack) and REACTS to its damage/death/crash
## signals — it never calls RulesCombat/RulesStatus itself. With no
## LocalServer attached (existing movement/camera/state-machine tests) the
## player still works fully: no combat, never crashes.

## Entity id this player registers under with LocalServer. Fixed for Phase 0
## (single player, no multiplayer yet).
const ENTITY_ID: String = "player"

const SPRITE_COLUMNS: int = 4
const ANIM_ROWS: Dictionary = {
	&"idle": {"row": 0, "frames": 2},
	&"run": {"row": 1, "frames": 4},
	&"jump": {"row": 2, "frames": 1},
	&"attack": {"row": 3, "frames": 3},
	&"hurt": {"row": 4, "frames": 1},
	&"dead": {"row": 5, "frames": 1},
}
## Time between animation frames — display timing only, not a balance number.
const FRAME_DURATION_S: float = 0.12

## Visual-only: how far in front of the player the HitBox sits, and the
## tint/shake used to show the stim "crash" state. Not balance numbers.
const HIT_BOX_OFFSET_X: float = 18.0
const CRASH_TINT: Color = Color(1.0, 0.35, 0.35, 1.0)
const CRASH_SHAKE_PX: float = 2.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var state_machine: StateMachine = $StateMachine
@onready var hit_box: Area2D = $HitBox
@onready var hit_box_shape: CollisionShape2D = $HitBox/CollisionShape2D

## Set via set_local_server(); null means "no combat" (movement-only tests).
var local_server: LocalServer = null
## Display-only flag driven by LocalServer's crash_started/crash_ended
## signals — never set directly from game logic.
var crashed: bool = false
## -1 or 1, updated from input direction; used to aim the HitBox/sprite.
var facing: float = 1.0

## -1..1 horizontal input, read from InputMap unless set_input() was called.
var input_dir: float = 0.0
## True for exactly one physics frame after an attack press; states consume it.
var attack_requested: bool = false
## T-0.15: set by the scene while a dialogue/shop/inventory panel is open — attack and skill
## presses are ignored (movement stays allowed so the player never feels stuck).
var ui_blocked: bool = false
## True for exactly one physics frame after a skill_1 press; states consume it.
var skill_requested: bool = false

## T-0.7: the skill id the `skill_1` action sends. Defaults to "" (falls back
## to the basic skill) — set_local_server() and level-ups update it to the
## highest unlocked non-basic skill via _update_selected_skill().
var selected_skill_id: String = ""

var _jump_held: bool = false
var _jump_held_prev: bool = false
## Seconds since jump was last pressed; negative means "no buffered press".
var _time_since_jump_press: float = -1.0
## Seconds since we were last on the floor; large means "never (yet)".
var _time_since_floor: float = 999.0

var _use_injected_input: bool = false
var _injected_attack_pressed: bool = false
var _injected_skill_pressed: bool = false

## "basic" or "selected" — which skill the currently-queued/playing Attack
## state should send; set when attack_requested/skill_requested go true,
## consumed by perform_attack().
var _next_attack_kind: String = "basic"
## Set by perform_attack(), resolved one physics frame later (Area2D overlap
## lists only reflect a CollisionShape2D resize on the NEXT physics step —
## see _resolve_pending_attack()).
var _attack_query_pending: bool = false
var _pending_skill_id: String = ""
var _default_hit_box_size: Vector2 = Vector2.ZERO

var _anim_name: StringName = &"idle"
var _anim_elapsed: float = 0.0


func _ready() -> void:
	play_animation(&"idle")
	if hit_box_shape != null and hit_box_shape.shape is RectangleShape2D:
		_default_hit_box_size = (hit_box_shape.shape as RectangleShape2D).size


func _physics_process(delta: float) -> void:
	if not _use_injected_input:
		_read_real_input()
	_step_physics(delta)
	_resolve_pending_attack()
	_step_animation(delta)
	_step_crash_visual()
	_injected_attack_pressed = false
	_injected_skill_pressed = false


## Attaches this player to a Phase 0 LocalServer (autoload-free — see
## client/scripts/combat/local_server.gd) and registers its stim stats.
## Never called → local_server stays null → no combat, ever (movement tests).
func set_local_server(server: LocalServer) -> void:
	local_server = server
	## T-0.10: base/growth-derived stats now live in LocalServer.register()
	## via the progression_archetype param — see local_server.gd — so this
	## only needs to say "I'm a level-1 stim", never literal base numbers.
	local_server.register(ENTITY_ID, {"level": 1.0}, "stim")
	local_server.damage_dealt.connect(_on_damage_dealt)
	local_server.entity_died.connect(_on_entity_died)
	local_server.crash_started.connect(_on_crash_started)
	local_server.crash_ended.connect(_on_crash_ended)
	local_server.level_up.connect(_on_level_up)
	_update_selected_skill(local_server.get_level(ENTITY_ID))


## Called by AttackState.enter(). Grows the HitBox to the chosen skill's
## range_px and marks the query pending — never computes damage itself; the
## actual request_skill() intent is sent one physics frame later, once the
## resized Area2D's overlap list has caught up (see _resolve_pending_attack()).
func perform_attack() -> void:
	if local_server == null or hit_box == null:
		return
	var skill_id: String = selected_skill_id if (_next_attack_kind == "selected" and selected_skill_id != "") else _basic_skill_id()
	if skill_id == "":
		return
	_pending_skill_id = skill_id
	_grow_hit_box(skill_id)
	_attack_query_pending = true


func _basic_skill_id() -> String:
	var skills: Array = RulesBalanceData.CLASSES.archetypes.stim.skills
	if skills.is_empty():
		return ""
	return String(skills[0].id)


func _find_skill(skill_id: String) -> Dictionary:
	for skill: Dictionary in RulesBalanceData.CLASSES.archetypes.stim.skills:
		if String(skill.id) == skill_id:
			return skill
	return {}


func _grow_hit_box(skill_id: String) -> void:
	if hit_box_shape == null:
		return
	var shape: RectangleShape2D = hit_box_shape.shape as RectangleShape2D
	if shape == null:
		return
	var skill: Dictionary = _find_skill(skill_id)
	var range_px: float = float(skill.get("range_px", _default_hit_box_size.x))
	shape.size = Vector2(range_px, _default_hit_box_size.y)
	hit_box.position.x = (range_px * 0.5) * facing


func _restore_hit_box() -> void:
	if hit_box_shape == null:
		return
	var shape: RectangleShape2D = hit_box_shape.shape as RectangleShape2D
	if shape != null:
		shape.size = _default_hit_box_size
	hit_box.position.x = HIT_BOX_OFFSET_X * facing


## Reads the HitBox's overlap list (now caught up to the resize perform_attack
## did last frame — see the class-level Area2D-timing note above), sends one
## request_skill() intent covering every overlapping Monster, then restores
## the HitBox to its default reach. A rejected/empty-target use does nothing
## further — LocalServer.skill_rejected is the place to react to a refusal.
func _resolve_pending_attack() -> void:
	if not _attack_query_pending:
		return
	_attack_query_pending = false
	var target_ids: Array[String] = []
	for body: Node2D in hit_box.get_overlapping_bodies():
		if body is Monster:
			target_ids.append((body as Monster).get_entity_id())
	_restore_hit_box()
	if target_ids.is_empty() or local_server == null:
		return
	local_server.request_skill(ENTITY_ID, target_ids, _pending_skill_id)


func _on_damage_dealt(target_id: String, _amount: float, _new_hp: float, _crit: bool) -> void:
	if target_id == ENTITY_ID:
		hurt()


func _on_entity_died(id: String, _xp: float, _drop_item_id: String) -> void:
	if id == ENTITY_ID:
		die()


func _on_crash_started(id: String, _duration: float) -> void:
	if id == ENTITY_ID:
		crashed = true


func _on_crash_ended(id: String) -> void:
	if id == ENTITY_ID:
		crashed = false


func _on_level_up(id: String, new_level: float, _stats: Dictionary) -> void:
	if id == ENTITY_ID:
		_update_selected_skill(new_level)


## Picks the highest-level unlocked non-basic skill as the skill_1 target.
## "" (falls back to the basic skill in perform_attack()) if none unlocked yet.
func _update_selected_skill(level: float) -> void:
	var basic_id: String = _basic_skill_id()
	var best_id: String = ""
	var best_level: float = -1.0
	for skill: Dictionary in RulesBalanceData.CLASSES.archetypes.stim.skills:
		var sid: String = String(skill.id)
		if sid == basic_id:
			continue
		var skill_level: float = float(skill.level)
		if RulesSkills.skill_unlocked(skill_level, level) and skill_level > best_level:
			best_level = skill_level
			best_id = sid
	selected_skill_id = best_id


## UI hook (skill_bar.gd): try to make `skill_id` the skill_1 target. Refuses
## (returns false, no change) if the server doesn't say it's unlocked yet.
func select_skill(skill_id: String) -> bool:
	if local_server == null or not local_server.unlocked_skills(ENTITY_ID).has(skill_id):
		return false
	selected_skill_id = skill_id
	return true


## Display-only reaction to `crashed` — tint + a small shake. No game logic.
func _step_crash_visual() -> void:
	if crashed:
		sprite.modulate = CRASH_TINT
		sprite.position.x = randf_range(-CRASH_SHAKE_PX, CRASH_SHAKE_PX)
	else:
		sprite.modulate = Color.WHITE
		sprite.position.x = 0.0


## Test/AI hook: drive the player without real InputEvents.
## dir: -1..1 horizontal intent. jump_pressed: true on the single frame the
## jump button went down (edge, not held). jump_held: current held state,
## used for coyote/jump-cut. attack_pressed/skill_pressed: same edge semantics
## as jump_pressed — attack_pressed sends the basic skill, skill_pressed sends
## selected_skill_id (see perform_attack()).
func set_input(dir: float, jump_pressed: bool, jump_held: bool, attack_pressed: bool = false, skill_pressed: bool = false) -> void:
	_use_injected_input = true
	input_dir = clampf(dir, -1.0, 1.0)
	if jump_pressed:
		_time_since_jump_press = 0.0
	_jump_held = jump_held
	if attack_pressed:
		_injected_attack_pressed = true
	if skill_pressed:
		_injected_skill_pressed = true


func _read_real_input() -> void:
	input_dir = Input.get_axis("move_left", "move_right")
	if Input.is_action_just_pressed("jump"):
		_time_since_jump_press = 0.0
	_jump_held = Input.is_action_pressed("jump")
	if Input.is_action_just_pressed("attack"):
		_injected_attack_pressed = true
	if Input.is_action_just_pressed("skill_1"):
		_injected_skill_pressed = true


func _step_physics(delta: float) -> void:
	if input_dir != 0.0:
		facing = signf(input_dir)
		sprite.flip_h = facing < 0.0
		if hit_box != null:
			hit_box.position.x = HIT_BOX_OFFSET_X * facing

	velocity.x = RulesMovement.step_horizontal(velocity.x, input_dir, delta)

	var on_floor_before: bool = is_on_floor()
	if on_floor_before:
		_time_since_floor = 0.0
	else:
		_time_since_floor += delta

	if _time_since_jump_press >= 0.0:
		_time_since_jump_press += delta
		if not RulesMovement.jump_buffered(_time_since_jump_press):
			_time_since_jump_press = -1.0

	var wants_jump: bool = _time_since_jump_press >= 0.0 and RulesMovement.jump_buffered(_time_since_jump_press)
	if wants_jump and RulesMovement.can_jump(on_floor_before, _time_since_floor):
		velocity.y = RulesMovement.JUMP_VELOCITY_PX
		_time_since_jump_press = -1.0
		_time_since_floor = RulesMovement.COYOTE_TIME_S + 1.0
	else:
		velocity.y = RulesMovement.step_vertical(velocity.y, delta)

	if _jump_held_prev and not _jump_held and velocity.y < 0.0:
		velocity.y = RulesMovement.jump_cut(velocity.y)
	_jump_held_prev = _jump_held

	if _injected_attack_pressed and not ui_blocked:
		attack_requested = true
		_next_attack_kind = "basic"
	if _injected_skill_pressed and not ui_blocked:
		skill_requested = true
		_next_attack_kind = "selected"

	move_and_slide()


func _step_animation(delta: float) -> void:
	_anim_elapsed += delta
	var meta: Dictionary = ANIM_ROWS.get(_anim_name, ANIM_ROWS[&"idle"])
	var frames: int = meta["frames"]
	if frames <= 1:
		return
	if _anim_elapsed >= FRAME_DURATION_S:
		_anim_elapsed = 0.0
		var col: int = (sprite.frame - meta["row"] * SPRITE_COLUMNS + 1) % frames
		sprite.frame = meta["row"] * SPRITE_COLUMNS + col


## Called by states — never by game logic that decides damage/XP/loot.
func play_animation(anim: StringName) -> void:
	if anim == _anim_name:
		return
	_anim_name = anim
	_anim_elapsed = 0.0
	var meta: Dictionary = ANIM_ROWS.get(anim, ANIM_ROWS[&"idle"])
	sprite.frame = meta["row"] * SPRITE_COLUMNS


## Server told us we got hit. This does NOT compute damage — only shows it.
func hurt() -> void:
	state_machine.request_transition(&"Hurt")


## Server told us HP hit 0. This does NOT compute death conditions.
func die() -> void:
	state_machine.request_transition(&"Dead")


## T-0.10: called by whoever owns the map (clinic_lobby.gd) AFTER it has
## already told LocalServer to revive() this entity and moved this node to
## the spawn point — this only resets the DISPLAY side (leaves Dead, clears
## the crash tint/shake) via StateMachine.force_enter, which is the one
## legitimate way out of a terminal state.
func respawn() -> void:
	velocity = Vector2.ZERO
	crashed = false
	state_machine.force_enter(&"Idle")
