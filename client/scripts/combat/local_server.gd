class_name LocalServer
extends Node
## T-0.8/T-0.9: Phase 0 stand-in for the real server (see CLAUDE.md — "the
## server is authoritative; the client never computes damage/XP/drop").
## WORKPLAN T-2.9 later swaps this node for real network messages without
## touching Player/Monster: they only ever send INTENTS here
## (register/request_attack) and react to the FACTS this emits as signals.
##
## This is the ONLY script outside client/scripts/rules/ allowed to call
## RulesCombat.damage / RulesLoot.roll_loot / RulesStatus.* — a grep for
## "RulesCombat.damage(" in client/scripts must hit only this file.
##
## Not an autoload: whoever owns a scene (arena.gd, a test) instances one
## LocalServer node and hands it to each Player/Monster via
## set_local_server()/setup().

signal damage_dealt(target_id: String, amount: float, new_hp: float, crit: bool)
signal entity_died(id: String, xp: float, drop_item_id: String)
signal crash_started(id: String, duration: float)
signal crash_ended(id: String)

## Seeded so tests can predict rolls: create a second RandomNumberGenerator
## with the same seed and call randf() the same number of times.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _entities: Dictionary = {}


func _ready() -> void:
	rng.randomize()


## Tests call this before any request_attack() to make rolls predictable.
func seed_rng(value: int) -> void:
	rng.seed = value


## stats: attack, defense, level, hp (= max hp). Optional: archetype (only
## "stim" gets the crash mechanic), xp (reward on death), loot_table (rolled
## on death; "" or omitted = never drops anything).
func register(id: String, stats: Dictionary) -> void:
	_entities[id] = {
		"attack": float(stats.get("attack", 0.0)),
		"defense": float(stats.get("defense", 0.0)),
		"level": float(stats.get("level", 1.0)),
		"hp": float(stats.get("hp", 1.0)),
		"max_hp": float(stats.get("hp", 1.0)),
		"archetype": String(stats.get("archetype", "")),
		"xp": float(stats.get("xp", 0.0)),
		"loot_table": String(stats.get("loot_table", "")),
		"alive": true,
		"consecutive_hits": 0.0,
		"crash_active": false,
		"crash_remaining": 0.0,
	}


func is_registered(id: String) -> bool:
	return _entities.has(id)


func get_hp(id: String) -> float:
	return _entities.get(id, {}).get("hp", 0.0)


func get_max_hp(id: String) -> float:
	return _entities.get(id, {}).get("max_hp", 0.0)


func is_alive(id: String) -> bool:
	return _entities.get(id, {}).get("alive", false)


func is_crashed(id: String) -> bool:
	return _entities.get(id, {}).get("crash_active", false)


func get_consecutive_hits(id: String) -> float:
	return _entities.get(id, {}).get("consecutive_hits", 0.0)


## Attacker's intent: "I want to hit target_id with power". Ignored (no
## signal, no state change) if either side is unknown or already dead —
## dead entities can neither deal nor take damage.
func request_attack(attacker_id: String, target_id: String, power: float) -> void:
	if attacker_id == target_id:
		return
	if not _entities.has(attacker_id) or not _entities.has(target_id):
		return
	var attacker: Dictionary = _entities[attacker_id]
	var defender: Dictionary = _entities[target_id]
	if not attacker.alive or not defender.alive:
		return

	var roll: float = rng.randf()
	var dmg: float = RulesCombat.damage(_combat_view(attacker), _combat_view(defender), power, roll)
	dmg = RulesStatus.damage_taken(dmg, defender.crash_active)
	var crit: bool = roll < RulesConstants.CRIT_CHANCE
	var new_hp: float = RulesCombat.apply_damage(defender.hp, dmg)
	defender.hp = new_hp

	damage_dealt.emit(target_id, dmg, new_hp, crit)
	_register_landed_hit(attacker_id)

	if RulesCombat.is_dead(new_hp):
		defender.alive = false
		var drop_item: String = ""
		if defender.loot_table != "":
			var loot_roll: float = rng.randf()
			drop_item = RulesLoot.roll_loot(defender.loot_table, loot_roll)
		entity_died.emit(target_id, defender.xp, drop_item)


func _combat_view(e: Dictionary) -> Dictionary:
	return {"attack": e.attack, "defense": e.defense, "level": e.level, "hp": e.hp}


## Stim-only mechanic (T-0.8): four consecutive landed hits by a stim
## attacker crash them for a duration, resetting the counter. Only ever
## reads/writes the ATTACKER's counter — whether the crash actually hurts
## depends on request_attack's `defender.crash_active` check above, whenever
## someone next attacks the crashed entity.
func _register_landed_hit(attacker_id: String) -> void:
	var attacker: Dictionary = _entities[attacker_id]
	if attacker.archetype != "stim":
		return
	attacker.consecutive_hits = RulesStatus.next_consecutive_hits(attacker.consecutive_hits, true)
	if RulesStatus.crash_triggers(attacker.consecutive_hits):
		attacker.consecutive_hits = 0.0
		attacker.crash_active = true
		attacker.crash_remaining = RulesStatus.crash_duration_s()
		crash_started.emit(attacker_id, attacker.crash_remaining)


## Crash countdown. Deliberately a plain per-frame decrement (not a Timer
## node) so GUT's simulate(server, frames, delta) can drive it exactly —
## see client/tests/test_local_server.gd.
func _physics_process(delta: float) -> void:
	for id: String in _entities.keys():
		var e: Dictionary = _entities[id]
		if not e.crash_active:
			continue
		e.crash_remaining -= delta
		if e.crash_remaining <= 0.0:
			e.crash_active = false
			e.crash_remaining = 0.0
			crash_ended.emit(id)
