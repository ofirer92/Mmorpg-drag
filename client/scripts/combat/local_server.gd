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
## T-0.10: XP/level-up facts. `level` on xp_gained is the level AFTER this
## grant is applied (so a grant that levels you up reports the new level,
## not the old one) — level_up then fires separately for anyone who wants
## to react only to the level boundary (HUD flash, etc.).
signal xp_gained(id: String, amount: float, total_xp: float, level: float)
signal level_up(id: String, new_level: float, stats: Dictionary)

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
##
## `progression_archetype`: T-0.10 — when non-empty (e.g. "stim"), this
## entity's attack/defense/hp are DERIVED from RulesProgression using
## RulesBalanceData.CLASSES.archetypes[progression_archetype]'s base+growth
## at `stats.level` (any attack/defense/hp in `stats` are ignored), and the
## entity starts tracking total_xp so it can gain xp/level up (see
## request_attack's death handling below). This is separate from the
## `archetype` key inside `stats` (still used only for the stim crash
## mechanic) so existing callers that pass literal stats + a crash archetype
## keep working unchanged; monsters never pass this and so never gain xp
## even when they land a killing blow (see _grant_xp_to_killer).
func register(id: String, stats: Dictionary, progression_archetype: String = "") -> void:
	var level: float = float(stats.get("level", 1.0))
	var has_progression: bool = progression_archetype != ""
	var archetype: String = progression_archetype if has_progression else String(stats.get("archetype", ""))
	var base: Dictionary = {}
	var growth: Dictionary = {}
	var attack: float
	var defense: float
	var max_hp: float
	if has_progression and RulesBalanceData.CLASSES.archetypes.has(progression_archetype):
		base = RulesBalanceData.CLASSES.archetypes[progression_archetype]
		growth = base.growth
		attack = RulesProgression.attack_at_level(base, growth, level)
		defense = RulesProgression.defense_at_level(base, growth, level)
		max_hp = RulesProgression.hp_at_level(base, growth, level)
	else:
		attack = float(stats.get("attack", 0.0))
		defense = float(stats.get("defense", 0.0))
		max_hp = float(stats.get("hp", 1.0))
	_entities[id] = {
		"attack": attack,
		"defense": defense,
		"level": level,
		"hp": max_hp,
		"max_hp": max_hp,
		"archetype": archetype,
		"xp": float(stats.get("xp", 0.0)),
		"loot_table": String(stats.get("loot_table", "")),
		"alive": true,
		"consecutive_hits": 0.0,
		"crash_active": false,
		"crash_remaining": 0.0,
		"last_attacker": "",
		"has_progression": has_progression,
		"total_xp": 0.0,
		"base_stats": base,
		"growth_stats": growth,
	}


## T-0.10: used later by the save system to restore a player's progression
## (e.g. after register() re-creates them fresh at level 1) — recomputes
## level and progression-derived stats from a saved cumulative total_xp
## WITHOUT emitting level_up (that signal is reserved for a live level-up
## event during play, not a silent restore on load). Heals to full for the
## same phase-0 reason as the live level-up path below — see
## _grant_xp_to_killer's doc comment. No-op for unknown ids or entities
## registered without a progression archetype (monsters never call this).
func set_progress(id: String, total_xp: float) -> void:
	if not _entities.has(id):
		return
	var e: Dictionary = _entities[id]
	if not e.has_progression:
		return
	e.total_xp = total_xp
	e.level = RulesXp.level_for_xp(total_xp)
	var base: Dictionary = e.base_stats
	var growth: Dictionary = e.growth_stats
	e.attack = RulesProgression.attack_at_level(base, growth, e.level)
	e.defense = RulesProgression.defense_at_level(base, growth, e.level)
	e.max_hp = RulesProgression.hp_at_level(base, growth, e.level)
	e.hp = e.max_hp


## T-0.10 phase-0 default (see clinic_lobby.gd for the 2 s delay/where):
## revives a dead entity back to full hp with no lingering crash/hit-streak
## state. Designer may want a penalty (xp loss, partial hp, ...) later — this
## is a placeholder, not a final rule. No-op for an unknown id.
func revive(id: String) -> void:
	if not _entities.has(id):
		return
	var e: Dictionary = _entities[id]
	e.alive = true
	e.hp = e.max_hp
	e.crash_active = false
	e.crash_remaining = 0.0
	e.consecutive_hits = 0.0
	e.last_attacker = ""


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


func get_level(id: String) -> float:
	return _entities.get(id, {}).get("level", 0.0)


func get_total_xp(id: String) -> float:
	return _entities.get(id, {}).get("total_xp", 0.0)


## hp/max_hp/attack/defense/level/total_xp for whoever owns a stats panel
## (HUD). Empty-dict-safe defaults so an unknown id reads as all-zero rather
## than erroring.
func get_stats(id: String) -> Dictionary:
	var e: Dictionary = _entities.get(id, {})
	return {
		"hp": e.get("hp", 0.0),
		"max_hp": e.get("max_hp", 0.0),
		"attack": e.get("attack", 0.0),
		"defense": e.get("defense", 0.0),
		"level": e.get("level", 0.0),
		"total_xp": e.get("total_xp", 0.0),
	}


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
	defender.last_attacker = attacker_id

	damage_dealt.emit(target_id, dmg, new_hp, crit)
	_register_landed_hit(attacker_id)

	if RulesCombat.is_dead(new_hp):
		defender.alive = false
		var drop_item: String = ""
		if defender.loot_table != "":
			var loot_roll: float = rng.randf()
			drop_item = RulesLoot.roll_loot(defender.loot_table, loot_roll)
		entity_died.emit(target_id, defender.xp, drop_item)
		_grant_xp_to_killer(defender)


func _combat_view(e: Dictionary) -> Dictionary:
	return {"attack": e.attack, "defense": e.defense, "level": e.level, "hp": e.hp}


## T-0.10: grants `victim`'s xp reward to whoever landed the killing blow —
## but ONLY if that killer was registered with a progression archetype
## (register(..., progression_archetype)). Monsters are registered without
## one, so a monster killing another entity (or the player killing nothing
## in particular) never grants xp to a monster. Recomputes level via
## RulesXp.level_for_xp on the new cumulative total; on a level increase,
## recomputes attack/defense/max_hp via RulesProgression from the killer's
## stored base/growth data.
##
## Phase-0 design default (documented here for the designer to revisit):
## leveling up heals the killer to their new max hp immediately, rather than
## keeping the hp deficit they had before the kill.
func _grant_xp_to_killer(victim: Dictionary) -> void:
	var killer_id: String = String(victim.get("last_attacker", ""))
	if killer_id == "" or not _entities.has(killer_id):
		return
	var killer: Dictionary = _entities[killer_id]
	if not killer.has_progression:
		return

	var xp_amount: float = victim.xp
	killer.total_xp += xp_amount
	var new_level: float = RulesXp.level_for_xp(killer.total_xp)
	xp_gained.emit(killer_id, xp_amount, killer.total_xp, new_level)

	if new_level > killer.level:
		killer.level = new_level
		var base: Dictionary = killer.base_stats
		var growth: Dictionary = killer.growth_stats
		killer.attack = RulesProgression.attack_at_level(base, growth, new_level)
		killer.defense = RulesProgression.defense_at_level(base, growth, new_level)
		killer.max_hp = RulesProgression.hp_at_level(base, growth, new_level)
		killer.hp = killer.max_hp
		level_up.emit(killer_id, new_level, get_stats(killer_id))


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
