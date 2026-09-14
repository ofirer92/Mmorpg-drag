class_name Monster
extends CharacterBody2D
## T-0.9: a monster with a small Patrol/Chase/Attack/Hurt/Dead state machine.
## Stats and ai_params come from RulesBalanceData.MONSTERS (generated from
## docs/balance/monsters.yaml) — never a literal hp/attack/speed/radius here.
##
## This script NEVER computes damage/xp/loot — it only sends attack INTENTS
## to LocalServer.request_attack() and displays the FACTS LocalServer sends
## back via its damage_dealt/entity_died signals (hp bar, hurt/dead anim,
## drop spawn).

enum AiState { PATROL, CHASE, ATTACK, HURT, DEAD }

const SPRITE_COLUMNS: int = 4
const ANIM_ROWS: Dictionary = {
	&"idle": {"row": 0, "frames": 2},
	&"run": {"row": 1, "frames": 4},
	&"attack": {"row": 2, "frames": 3},
	&"hurt": {"row": 3, "frames": 1},
	&"dead": {"row": 4, "frames": 1},
}
## Animation frame pace — display timing only, not a balance number.
const FRAME_DURATION_S: float = 0.12
## Visual-only timers (not balance numbers): how long the hurt flinch shows,
## and how long the corpse lingers before the drop appears and it despawns.
const HURT_DURATION_S: float = 0.25
const DEATH_DELAY_S: float = 0.6

## Monsters have no skills in Phase 0 (monsters.yaml has no `power` field for
## them, only players' class skills do) — power=1.0 means their `attack`
## stat IS the base attack input to RulesCombat.damage, unscaled. This is a
## structural default, not a tunable balance number.
const ATTACK_POWER: float = 1.0
const PLAYER_ENTITY_ID: String = "player"

const DropScene: PackedScene = preload("res://scenes/monsters/drop.tscn")

@export var monster_id: String = "side_effect_slime"

@onready var sprite: Sprite2D = $Sprite2D
@onready var hp_bar: ProgressBar = $HpBar
@onready var name_label: Label = $NameLabel
@onready var ground_ahead: RayCast2D = $GroundAhead

var local_server: LocalServer
var target: Node2D
var entity_id: String = ""
var stats: Dictionary = {}
var ai_params: Dictionary = {}
## "patrol" | "chase" | "boss" (docs/balance/monsters.yaml). "boss" behaves
## like "chase" for now — Phase 0 has no boss-specific behaviour yet, so no
## branch is needed: both just run the same Patrol/Chase/Attack machine.
var ai_kind: String = "patrol"

var ai_state: AiState = AiState.PATROL
var spawn_x: float = 0.0
var facing: float = 1.0

var _attack_cooldown_remaining: float = 0.0
var _hurt_elapsed: float = 0.0
var _dead_elapsed: float = 0.0
var _drop_item_id: String = ""
var _drop_spawned: bool = false

var _anim_name: StringName = &"idle"
var _anim_elapsed: float = 0.0


func _ready() -> void:
	spawn_x = global_position.x
	stats = RulesBalanceData.MONSTERS.monsters.get(monster_id, {})
	ai_params = stats.get("ai_params", {})
	ai_kind = stats.get("ai", "patrol")
	entity_id = "%s_%d" % [monster_id, get_instance_id()]
	if sprite != null:
		sprite.texture = load("res://assets/generated/monster_%s.png" % monster_id)
		sprite.hframes = SPRITE_COLUMNS
		sprite.vframes = ANIM_ROWS.size()
	if name_label != null:
		name_label.text = I18n.t(String(stats.get("name_key", monster_id)))
	play_animation(&"idle")


## Called by whoever owns this monster (arena.gd, tests) once both the
## server and the target (the player) exist. LocalServer is autoload-free,
## so it must be handed in rather than looked up globally.
func setup(server: LocalServer, target_node: Node2D) -> void:
	local_server = server
	target = target_node
	local_server.register(
		entity_id,
		{
			"attack": stats.get("attack", 0.0),
			"defense": stats.get("defense", 0.0),
			"level": stats.get("level", 1.0),
			"hp": stats.get("hp", 1.0),
			"xp": stats.get("xp", 0.0),
			"loot_table": stats.get("loot_table", ""),
			"money": stats.get("money", {}),
		}
	)
	if hp_bar != null:
		hp_bar.max_value = stats.get("hp", 1.0)
		hp_bar.value = stats.get("hp", 1.0)
	local_server.damage_dealt.connect(_on_damage_dealt)
	local_server.entity_died.connect(_on_entity_died)


func get_entity_id() -> String:
	return entity_id


func _physics_process(delta: float) -> void:
	if local_server == null:
		return
	match ai_state:
		AiState.PATROL:
			_patrol(delta)
		AiState.CHASE:
			_chase(delta)
		AiState.ATTACK:
			_attack(delta)
		AiState.HURT:
			_hurt(delta)
		AiState.DEAD:
			_dead(delta)
			return
	move_and_slide()
	_step_animation(delta)


func _distance_to_target() -> float:
	if target == null:
		return INF
	return global_position.distance_to(target.global_position)


func _turn_around() -> void:
	facing = -facing
	if ground_ahead != null:
		ground_ahead.position.x = absf(ground_ahead.position.x) * facing
	if sprite != null:
		sprite.flip_h = facing < 0.0


func _patrol(delta: float) -> void:
	velocity.x = ai_params.get("patrol_speed", 0.0) * facing
	velocity.y = RulesMovement.step_vertical(velocity.y, delta)

	# Only turn while still travelling AWAY from spawn past the limit — using a
	# plain `>=` re-triggers every single frame once past the boundary
	# (including right after the flip, since move_and_slide() this frame
	# still used the pre-flip velocity), which flip-flops facing in place
	# instead of actually turning around.
	var offset: float = global_position.x - spawn_x
	var patrol_distance: float = ai_params.get("patrol_distance", 0.0)
	if (facing > 0.0 and offset >= patrol_distance) or (facing < 0.0 and -offset >= patrol_distance):
		_turn_around()
	elif ground_ahead != null:
		ground_ahead.force_raycast_update()
		if not ground_ahead.is_colliding():
			_turn_around()
	elif is_on_wall():
		_turn_around()

	if target != null and _distance_to_target() <= ai_params.get("aggro_radius", 0.0):
		ai_state = AiState.CHASE

	play_animation(&"run" if absf(velocity.x) > 1.0 else &"idle")


func _chase(delta: float) -> void:
	if target == null:
		ai_state = AiState.PATROL
		return
	var dist: float = _distance_to_target()
	if dist > ai_params.get("leash_radius", 0.0):
		ai_state = AiState.PATROL
		velocity.x = 0.0
		velocity.y = RulesMovement.step_vertical(velocity.y, delta)
		play_animation(&"idle")
		return
	if dist <= ai_params.get("attack_range", 0.0):
		ai_state = AiState.ATTACK
		velocity.x = 0.0
		velocity.y = RulesMovement.step_vertical(velocity.y, delta)
		return

	var dir: float = signf(target.global_position.x - global_position.x)
	if dir != 0.0:
		facing = dir
		if sprite != null:
			sprite.flip_h = facing < 0.0
	velocity.x = ai_params.get("chase_speed", 0.0) * dir
	velocity.y = RulesMovement.step_vertical(velocity.y, delta)
	play_animation(&"run" if absf(velocity.x) > 1.0 else &"idle")


func _attack(delta: float) -> void:
	velocity.x = 0.0
	velocity.y = RulesMovement.step_vertical(velocity.y, delta)
	if target == null:
		ai_state = AiState.PATROL
		return
	var dist: float = _distance_to_target()
	if dist > ai_params.get("attack_range", 0.0):
		ai_state = AiState.CHASE
		return

	_attack_cooldown_remaining -= delta
	if _attack_cooldown_remaining <= 0.0:
		var attack_speed: float = max(float(stats.get("attack_speed", 1.0)), 0.01)
		_attack_cooldown_remaining = 1.0 / attack_speed
		local_server.request_attack(entity_id, PLAYER_ENTITY_ID, ATTACK_POWER)
		play_animation(&"attack")
	else:
		play_animation(&"idle")


func _hurt(delta: float) -> void:
	velocity.x = 0.0
	velocity.y = RulesMovement.step_vertical(velocity.y, delta)
	_hurt_elapsed += delta
	if _hurt_elapsed >= HURT_DURATION_S:
		_hurt_elapsed = 0.0
		ai_state = AiState.PATROL


func _dead(delta: float) -> void:
	velocity = Vector2.ZERO
	if _drop_spawned:
		return
	_dead_elapsed += delta
	if _dead_elapsed >= DEATH_DELAY_S:
		_finalize_death()


func _finalize_death() -> void:
	_drop_spawned = true
	if _drop_item_id != "" and get_parent() != null:
		var drop: Area2D = DropScene.instantiate()
		drop.item_id = _drop_item_id
		get_parent().add_child(drop)
		drop.global_position = global_position
	queue_free()


func _on_damage_dealt(target_id: String, _amount: float, new_hp: float, _crit: bool) -> void:
	if target_id != entity_id:
		return
	if hp_bar != null:
		hp_bar.value = new_hp
	if ai_state != AiState.DEAD:
		ai_state = AiState.HURT
		_hurt_elapsed = 0.0
		play_animation(&"hurt")


func _on_entity_died(id: String, _xp: float, drop_item_id: String) -> void:
	if id != entity_id:
		return
	ai_state = AiState.DEAD
	_dead_elapsed = 0.0
	_drop_item_id = drop_item_id
	play_animation(&"dead")


func play_animation(anim: StringName) -> void:
	if anim == _anim_name:
		return
	_anim_name = anim
	_anim_elapsed = 0.0
	var meta: Dictionary = ANIM_ROWS.get(anim, ANIM_ROWS[&"idle"])
	if sprite != null:
		sprite.frame = meta["row"] * SPRITE_COLUMNS


func _step_animation(delta: float) -> void:
	if sprite == null:
		return
	_anim_elapsed += delta
	var meta: Dictionary = ANIM_ROWS.get(_anim_name, ANIM_ROWS[&"idle"])
	var frames: int = meta["frames"]
	if frames <= 1:
		return
	if _anim_elapsed >= FRAME_DURATION_S:
		_anim_elapsed = 0.0
		var col: int = (sprite.frame - meta["row"] * SPRITE_COLUMNS + 1) % frames
		sprite.frame = meta["row"] * SPRITE_COLUMNS + col
