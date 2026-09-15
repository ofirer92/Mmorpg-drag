class_name RemoteAuthority
extends CombatAuthority
## T-2.4/T-2.9 endpoint: THE net-mode CombatAuthority. This is the only place
## outside client/scripts/rules/ that is allowed to know about combat while
## networked, and — unlike LocalServer — it never calls RulesCombat.damage /
## RulesLoot.roll_loot / RulesStatus.*: it only ever (a) turns
## register/request_attack/request_skill calls into protocol v1 intents
## (docs/protocol.md) via NetClient, and (b) turns the server's `state` /
## `attack` / `damage` / `died` / `loot` / `error` facts back into the exact
## same signals LocalServer emits, so Player/Monster-views/Hud/SkillBar need
## no net-mode special-casing (CLAUDE.md: "אסור לקליינט לחשב נזק").
##
## Id remapping: the server's own player_id (e.g. "p_7") is only known after
## `joined` — every signal/query below accepts/emits Player.ENTITY_ID
## ("player") for the LOCAL player instead, so existing Player/Hud/SkillBar
## code (written for single-player's fixed "player" id) keeps working
## unchanged. Monster/other-player ids pass through as the server sent them.
##
## Attack/skill intents ride the ALREADY-EXISTING per-tick `input` message
## (client/scripts/net/net_session.gd's _send_input() already copies
## Player.get_last_input()'s attack/skill_id flags onto every `input` —
## that's been true since T-2.3). request_attack()/request_skill() below do
## NOT send anything themselves: they only do local bookkeeping so
## skill_cooldown_left()/unlocked_skills() have something to predict from —
## see the ATTACK_CONFIRM_TIMEOUT_S note below for how a silently-rejected
## attack (docs/protocol.md: "no `attack` and no `error`") un-stalls the
## skill bar.
##
## Known v1 protocol gaps (documented for whoever picks these up next):
## attack/defense are not part of PlayerState/MonsterState, so get_stats()
## reads them as 0 in net mode; there is no crash-state field, so
## is_crashed() is always false; heal()/set_gear_bonus() have no intent yet
## (no consumable-use / gear-equip message in protocol v1) and are no-ops.

## Only archetype with skills in phase 2 — client/scripts/player/player.gd's
## own _basic_skill_id()/_find_skill() already hardcode this same assumption
## locally (see its header), this mirrors that existing precedent rather than
## inventing a new balance literal.
const DEFAULT_ARCHETYPE: String = "stim"

## How long we wait for a confirming `attack` fact (or an `error`) after a
## request_skill() before treating the press as rejected and un-stalling the
## skill bar (docs/protocol.md: a rejected attack produces neither). UI/
## netcode timeout, not a balance number.
const ATTACK_CONFIRM_TIMEOUT_S: float = 1.0

const RemoteMonsterScene: PackedScene = preload("res://scenes/net/remote_monster.tscn")
const RemoteDropScene: PackedScene = preload("res://scenes/net/remote_drop.tscn")

## Emitted when a `loot {added: true}` fact names this player — clinic_lobby/
## main.gd applies it to the real Inventory (the same "server decided, client
## displays" split as every other signal here; not on CombatAuthority's base
## signal set because single-player never routes loot through the authority
## at all — Drop.picked_up goes straight to clinic_lobby today).
signal loot_added(item_id: String, money: int)

var net_client: NetClient = null
var remote_container: Node2D = null
var inventory: Inventory = null
## Set by main.gd once `joined`/`ready_to_play` reports the server's id for
## this connection — "" until then (every id-based query is a safe no-op).
var local_player_id: String = ""

var _archetype: String = DEFAULT_ARCHETYPE
var _players: Dictionary = {}  # id -> raw PlayerState dict from the latest `state`
var _monsters: Dictionary = {}  # id -> raw MonsterState dict
var _monster_views: Dictionary = {}  # id -> RemoteMonster
var _drop_views: Dictionary = {}  # id -> RemoteDrop
var _skill_last_used: Dictionary = {}  # skill_id -> local clock seconds
var _pending_skill: String = ""
var _pending_started_at: float = -1000.0
var _clock_s: float = 0.0
var _last_known_xp: float = -1.0
var _last_known_level: float = -1.0


## Wires this authority to `client`'s facts and where remote monster/drop
## views + looted items go. Call once, before the join handshake completes.
func setup(client: NetClient, container: Node2D, inv: Inventory) -> void:
	net_client = client
	remote_container = container
	inventory = inv
	client.state.connect(_on_state)
	client.attack.connect(_on_attack)
	client.damage.connect(_on_damage)
	client.died.connect(_on_died)
	client.loot.connect(_on_loot)
	client.error.connect(_on_error)


func _process(delta: float) -> void:
	_clock_s += delta
	if _pending_skill != "" and _clock_s - _pending_started_at > ATTACK_CONFIRM_TIMEOUT_S:
		var rejected: String = _pending_skill
		_pending_skill = ""
		skill_rejected.emit(Player.ENTITY_ID, rejected, "timeout")


func register(id: String, _stats: Dictionary, progression_archetype: String = "") -> void:
	if id == Player.ENTITY_ID and progression_archetype != "":
		_archetype = progression_archetype


## Ignores target_id/power (the server decides both) — see the class header.
func request_attack(attacker_id: String, _target_id: String, _power: float) -> void:
	request_skill(attacker_id, [], "")


## See CombatAuthority.needs_local_targets()'s doc comment — the server
## decides who got hit, so this stays false.
func needs_local_targets() -> bool:
	return false


func request_skill(_attacker_id: String, _target_ids: Array[String], skill_id: String) -> bool:
	var use_id: String = skill_id if skill_id != "" else _basic_skill_id()
	if use_id == "":
		return false
	_pending_skill = use_id
	_pending_started_at = _clock_s
	return true


func get_stats(id: String) -> Dictionary:
	var sid: String = _to_server_id(id)
	if _players.has(sid):
		var p: Dictionary = _players[sid]
		return {
			"hp": float(p.get("hp", 0.0)),
			"max_hp": float(p.get("max_hp", 0.0)),
			"attack": 0.0,
			"defense": 0.0,
			"level": float(p.get("level", 1.0)),
			"total_xp": float(p.get("xp", 0.0)),
		}
	if _monsters.has(sid):
		var m: Dictionary = _monsters[sid]
		return {
			"hp": float(m.get("hp", 0.0)),
			"max_hp": float(m.get("max_hp", 0.0)),
			"attack": 0.0,
			"defense": 0.0,
			"level": float(m.get("level", 1.0)),
			"total_xp": 0.0,
		}
	return {"hp": 0.0, "max_hp": 0.0, "attack": 0.0, "defense": 0.0, "level": 1.0, "total_xp": 0.0}


func get_hp(id: String) -> float:
	return float(get_stats(id).hp)


func get_max_hp(id: String) -> float:
	return float(get_stats(id).max_hp)


func is_alive(id: String) -> bool:
	var sid: String = _to_server_id(id)
	if _players.has(sid):
		return bool((_players[sid] as Dictionary).get("alive", true))
	if _monsters.has(sid):
		return bool((_monsters[sid] as Dictionary).get("alive", true))
	return false


## No crash-state field in protocol v1's PlayerState — see class header.
func is_crashed(_id: String) -> bool:
	return false


func is_registered(id: String) -> bool:
	var sid: String = _to_server_id(id)
	return sid != "" and (_players.has(sid) or _monsters.has(sid))


func get_level(id: String) -> float:
	return float(get_stats(id).level)


func get_total_xp(id: String) -> float:
	return float(get_stats(id).total_xp)


func skill_cooldown_left(_id: String, skill_id: String) -> float:
	if not _skill_last_used.has(skill_id):
		return 0.0
	var skill: Dictionary = _find_skill(skill_id)
	if skill.is_empty():
		return 0.0
	var elapsed: float = _clock_s - float(_skill_last_used[skill_id])
	return RulesSkills.skill_cooldown_left(elapsed, float(skill.cooldown))


func unlocked_skills(id: String) -> Array[String]:
	var result: Array[String] = []
	if not RulesBalanceData.CLASSES.archetypes.has(_archetype):
		return result
	var level: float = get_level(id)
	for skill: Dictionary in RulesBalanceData.CLASSES.archetypes[_archetype].skills:
		if RulesSkills.skill_unlocked(float(skill.level), level):
			result.append(String(skill.id))
	return result


## No consumable-use intent in protocol v1 — see class header.
func heal(_id: String, _amount: float) -> void:
	pass


## No gear-equip intent in protocol v1 — see class header.
func set_gear_bonus(_id: String, _bonus: Dictionary) -> void:
	pass


func _basic_skill_id() -> String:
	if not RulesBalanceData.CLASSES.archetypes.has(_archetype):
		return ""
	var skills: Array = RulesBalanceData.CLASSES.archetypes[_archetype].skills
	if skills.is_empty():
		return ""
	return String(skills[0].id)


func _find_skill(skill_id: String) -> Dictionary:
	if not RulesBalanceData.CLASSES.archetypes.has(_archetype):
		return {}
	for skill: Dictionary in RulesBalanceData.CLASSES.archetypes[_archetype].skills:
		if String(skill.id) == skill_id:
			return skill
	return {}


## Player.ENTITY_ID ("player") -> the server's real id for the local player;
## every other id (monsters, other players) passes through unchanged.
func _to_server_id(id: String) -> String:
	if id == Player.ENTITY_ID:
		return local_player_id
	return id


## The inverse of _to_server_id — used when translating an incoming fact's
## id back to what Player/Hud/SkillBar expect.
func _to_local_id(id: String) -> String:
	if local_player_id != "" and id == local_player_id:
		return Player.ENTITY_ID
	return id


func _on_state(data: Dictionary) -> void:
	for raw: Variant in (data.get("players", []) as Array):
		var p: Dictionary = raw
		var id: String = String(p.get("id", ""))
		if id == "":
			continue
		_players[id] = p
		if id == local_player_id:
			_check_progression(p)
			stats_synced.emit(Player.ENTITY_ID)

	var seen_m: Dictionary = {}
	for raw: Variant in (data.get("monsters", []) as Array):
		var m: Dictionary = raw
		var id: String = String(m.get("id", ""))
		if id == "":
			continue
		seen_m[id] = true
		_monsters[id] = m
		_sync_monster_view(id, m)
	for id: String in _monster_views.keys().duplicate():
		if not seen_m.has(id):
			(_monster_views[id] as Node).queue_free()
			_monster_views.erase(id)
			_monsters.erase(id)

	var seen_d: Dictionary = {}
	for raw: Variant in (data.get("drops", []) as Array):
		var d: Dictionary = raw
		var id: String = String(d.get("id", ""))
		if id == "":
			continue
		seen_d[id] = true
		_sync_drop_view(id, d)
	for id: String in _drop_views.keys().duplicate():
		if not seen_d.has(id):
			(_drop_views[id] as Node).queue_free()
			_drop_views.erase(id)


## docs/protocol.md § "There is no xp_gained / level_up message in v1":
## PlayerState.xp/.level in each `state` carry that, so this is what fires
## the same xp_gained/level_up signals LocalServer emits on a real xp grant.
func _check_progression(p: Dictionary) -> void:
	var xp: float = float(p.get("xp", 0.0))
	var level: float = float(p.get("level", 1.0))
	if _last_known_xp < 0.0:
		_last_known_xp = xp
		_last_known_level = level
		return
	if xp > _last_known_xp:
		xp_gained.emit(Player.ENTITY_ID, xp - _last_known_xp, xp, level)
	if level > _last_known_level:
		level_up.emit(Player.ENTITY_ID, level, get_stats(Player.ENTITY_ID))
	_last_known_xp = xp
	_last_known_level = level


func _sync_monster_view(id: String, m: Dictionary) -> void:
	if remote_container == null:
		return
	var view: RemoteMonster
	if _monster_views.has(id):
		view = _monster_views[id]
	else:
		view = RemoteMonsterScene.instantiate()
		remote_container.add_child(view)
		_monster_views[id] = view
	view.apply_state(m)


func _sync_drop_view(id: String, d: Dictionary) -> void:
	if remote_container == null or _drop_views.has(id):
		return
	var view: RemoteDrop = RemoteDropScene.instantiate()
	var item_variant: Variant = d.get("item_id", null)
	view.setup(id, String(item_variant) if item_variant != null else "", net_client)
	remote_container.add_child(view)
	var pos_dict: Dictionary = d.get("pos", {})
	view.global_position = Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0)))
	_drop_views[id] = view


func _on_attack(data: Dictionary) -> void:
	var attacker_id: String = String(data.get("attacker_id", ""))
	if local_player_id == "" or attacker_id != local_player_id:
		return
	var skill_variant: Variant = data.get("skill_id", null)
	var sid: String = String(skill_variant) if skill_variant != null else _basic_skill_id()
	_pending_skill = ""
	_skill_last_used[sid] = _clock_s
	var skill: Dictionary = _find_skill(sid)
	var cooldown: float = float(skill.get("cooldown", 0.0))
	skill_used.emit(Player.ENTITY_ID, sid, cooldown)


func _on_damage(data: Dictionary) -> void:
	var raw_target: String = String(data.get("target_id", ""))
	var amount: float = float(data.get("amount", 0.0))
	var new_hp: float = float(data.get("new_hp", 0.0))
	var crit: bool = bool(data.get("crit", false))
	if _players.has(raw_target):
		(_players[raw_target] as Dictionary)["hp"] = new_hp
	if _monsters.has(raw_target):
		(_monsters[raw_target] as Dictionary)["hp"] = new_hp
		if _monster_views.has(raw_target):
			(_monster_views[raw_target] as RemoteMonster).set_hp_display(new_hp)
	damage_dealt.emit(_to_local_id(raw_target), amount, new_hp, crit)


func _on_died(data: Dictionary) -> void:
	var raw_id: String = String(data.get("id", ""))
	var xp: float = float(data.get("xp", 0.0))
	var item_variant: Variant = data.get("item_id", null)
	var drop_item: String = String(item_variant) if item_variant != null else ""
	if _monster_views.has(raw_id):
		(_monster_views[raw_id] as Node).queue_free()
		_monster_views.erase(raw_id)
	_monsters.erase(raw_id)
	entity_died.emit(_to_local_id(raw_id), xp, drop_item)


func _on_loot(data: Dictionary) -> void:
	var player_id: String = String(data.get("player_id", ""))
	if local_player_id == "" or player_id != local_player_id:
		return
	if not bool(data.get("added", false)):
		return
	var item_variant: Variant = data.get("item_id", null)
	loot_added.emit(String(item_variant) if item_variant != null else "", int(data.get("money", 0)))


func _on_error(data: Dictionary) -> void:
	if _pending_skill == "":
		return
	var rejected: String = _pending_skill
	_pending_skill = ""
	skill_rejected.emit(Player.ENTITY_ID, rejected, String(data.get("code", "rejected")))
