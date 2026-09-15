class_name LocalServer
extends CombatAuthority
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
## set_local_server()/setup(). T-2.4: extends CombatAuthority (see
## combat_authority.gd) purely so Player/Hud/SkillBar/clinic_lobby can be
## typed against the authority interface instead of this concrete class —
## every signal below is now declared on CombatAuthority and simply
## inherited here, with NO behaviour change from before T-2.4.

## T-1.7b: upper bound on affix re-rolls per drop, so _roll_affixes() cannot spin when a rarity's
## allowed pool is smaller than the slot count it asks for. Not a balance number — a loop guard.
const MAX_AFFIX_REROLLS: int = 32

## Seeded so tests can predict rolls: create a second RandomNumberGenerator
## with the same seed and call randf() the same number of times.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _entities: Dictionary = {}

## Server clock, seconds — advances via _physics_process(delta) (see
## client/tests/test_local_server.gd's simulate() usage) or a direct jump via
## advance_time() for skill-cooldown tests that don't want to simulate every
## frame. Skill cooldowns are timestamped against this clock, never against
## OS time (mirrors the future networked server's tick clock).
var _time: float = 0.0


func _ready() -> void:
	rng.randomize()


## Tests call this before any request_attack() to make rolls predictable.
func seed_rng(value: int) -> void:
	rng.seed = value


## Test hook: jump the server clock forward without stepping physics frames
## (crash timers are untouched — use simulate(server, frames, delta) instead
## if a test also needs the crash countdown to progress).
func advance_time(seconds: float) -> void:
	_time += seconds


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
		"money_min": float((stats.get("money", {}) as Dictionary).get("min", 0)),
		"money_max": float((stats.get("money", {}) as Dictionary).get("max", 0)),
		"alive": true,
		"consecutive_hits": 0.0,
		"crash_active": false,
		"crash_remaining": 0.0,
		"last_attacker": "",
		"has_progression": has_progression,
		"total_xp": 0.0,
		"base_stats": base,
		"growth_stats": growth,
		"gear": {"attack": 0.0, "defense": 0.0, "hp": 0.0},
		"last_use": {},
	}


## Recompute attack/defense/max_hp for a progression entity from its level plus
## equipped-gear bonuses (Inventory.equipped_stats()). hp is clamped to the new max.
func _recompute_progression_stats(e: Dictionary) -> void:
	if not e.has_progression:
		return
	var base: Dictionary = e.base_stats
	var growth: Dictionary = e.growth_stats
	var gear: Dictionary = e.gear
	e.attack = RulesProgression.attack_at_level(base, growth, e.level) + float(gear.attack)
	e.defense = RulesProgression.defense_at_level(base, growth, e.level) + float(gear.defense)
	e.max_hp = RulesProgression.hp_at_level(base, growth, e.level) + float(gear.hp)
	e.hp = min(e.hp, e.max_hp)


## T-0.11: equipped gear adds flat attack/defense/hp (the sum comes from
## Inventory.equipped_stats(); items.yaml holds the numbers). Only progression
## entities (the player) carry gear. No-op for unknown ids.
func set_gear_bonus(id: String, bonus: Dictionary) -> void:
	if not _entities.has(id):
		return
	var e: Dictionary = _entities[id]
	if not e.has_progression:
		return
	var old_max: float = e.max_hp
	e.gear = {
		"attack": float(bonus.get("attack", 0)),
		"defense": float(bonus.get("defense", 0)),
		"hp": float(bonus.get("hp", 0)),
	}
	_recompute_progression_stats(e)
	# Gaining max hp from gear raises current hp by the same amount (no free heal beyond that).
	if e.max_hp > old_max:
		e.hp = min(e.max_hp, e.hp + (e.max_hp - old_max))


## T-0.11: a consumable's `stats.hp` heals via RulesCombat.heal. Ignored for
## dead/unknown entities. Emits healed(id, actual_amount, new_hp).
func heal(id: String, amount: float) -> void:
	if not _entities.has(id):
		return
	var e: Dictionary = _entities[id]
	if not e.alive:
		return
	var new_hp: float = RulesCombat.heal(e.hp, e.max_hp, amount)
	var actual: float = new_hp - e.hp
	e.hp = new_hp
	healed.emit(id, actual, new_hp)


## T-0.13: restore hp from a save (clamped to max, ≥ 1 so a loaded player is never dead).
func set_hp(id: String, hp: float) -> void:
	if not _entities.has(id):
		return
	var e: Dictionary = _entities[id]
	e.hp = clamp(hp, 1.0, e.max_hp)


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
	_recompute_progression_stats(e)
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
		entity_died.emit(target_id, defender.xp, drop_item, _roll_affixes(drop_item))
		_grant_xp_to_killer(defender)


## T-1.7b: rolls the affixes a freshly dropped `item_id` carries, on this
## authority's own seeded rng — the client never decides this, the authority
## does (in solo mode that IS this class; see ADR-013).
##
## RulesAffixes is pure and stateless per roll, so "no duplicate affix on one
## item" is explicitly the caller's job (see affixes.gd's header): each slot is
## re-rolled with a fresh value until it yields an id not already taken, and
## gives up after MAX_AFFIX_REROLLS so a rarity whose pool is smaller than its
## slot count can never spin forever.
func _roll_affixes(item_id: String) -> Array[String]:
	var out: Array[String] = []
	if item_id == "":
		return out
	var def: Dictionary = RulesBalanceData.ITEMS.get("items", {}).get(item_id, {})
	var rarity: String = String(def.get("rarity", ""))
	if rarity == "":
		return out
	var wanted: int = int(RulesAffixes.affix_count(rarity, rng.randf()))
	var pool: int = int(RulesAffixes.affix_pool_size(rarity))
	wanted = min(wanted, pool)
	var attempts: int = 0
	while out.size() < wanted and attempts < MAX_AFFIX_REROLLS:
		attempts += 1
		var affix_id: String = RulesAffixes.roll_affix_id(rarity, rng.randf())
		if affix_id != "" and not out.has(affix_id):
			out.append(affix_id)
	return out


func _combat_view(e: Dictionary) -> Dictionary:
	return {"attack": e.attack, "defense": e.defense, "level": e.level, "hp": e.hp}


## T-0.7: attacker's intent "use skill_id on target_ids" — the skill-system
## counterpart to request_attack. Only progression entities (register(...,
## progression_archetype)) have skills (monsters never do). Looks the skill up
## in the attacker's archetype (docs/balance/classes.yaml
## archetypes.<archetype>.skills), gates it server-side with RulesSkills
## (skill_unlocked/skill_ready against `_time`), and on success re-uses
## request_attack once per hit per target (so damage/crit/crash/xp/money all
## keep working exactly like a plain attack) plus RulesSkills.skill_crash_hits
## extra _register_landed_hit increments for the attacker (self-crash risk).
## Returns true iff the intent was accepted; on rejection emits
## skill_rejected(id, skill_id, reason) and does nothing else.
func request_skill(attacker_id: String, target_ids: Array[String], skill_id: String) -> bool:
	if not _entities.has(attacker_id):
		skill_rejected.emit(attacker_id, skill_id, "unknown")
		return false
	var attacker: Dictionary = _entities[attacker_id]
	if not attacker.has_progression:
		skill_rejected.emit(attacker_id, skill_id, "unknown")
		return false
	var skill: Dictionary = _find_skill(attacker.archetype, skill_id)
	if skill.is_empty():
		skill_rejected.emit(attacker_id, skill_id, "unknown")
		return false
	if not attacker.alive:
		skill_rejected.emit(attacker_id, skill_id, "dead")
		return false
	if not RulesSkills.skill_unlocked(float(skill.level), attacker.level):
		skill_rejected.emit(attacker_id, skill_id, "locked")
		return false
	var cooldown: float = float(skill.cooldown)
	var time_since_use: float = _time - _last_use_time(attacker, skill_id)
	if not RulesSkills.skill_ready(time_since_use, cooldown):
		skill_rejected.emit(attacker_id, skill_id, "cooldown")
		return false

	(attacker.last_use as Dictionary)[skill_id] = _time
	skill_used.emit(attacker_id, skill_id, cooldown)

	var power: float = float(skill.power)
	var hits: int = int(skill.hits)
	for target_id: String in target_ids:
		if target_id == attacker_id:
			continue
		for i in range(hits):
			request_attack(attacker_id, target_id, power)

	var extra_crash_hits: int = int(RulesSkills.skill_crash_hits(skill))
	for i in range(extra_crash_hits):
		_register_landed_hit(attacker_id)

	return true


## No timestamp yet ("never used") reads as ready for any cooldown.
func _last_use_time(e: Dictionary, skill_id: String) -> float:
	return float((e.last_use as Dictionary).get(skill_id, -1000000.0))


func _find_skill(archetype: String, skill_id: String) -> Dictionary:
	if not RulesBalanceData.CLASSES.archetypes.has(archetype):
		return {}
	var skills: Array = RulesBalanceData.CLASSES.archetypes[archetype].skills
	for skill: Dictionary in skills:
		if String(skill.id) == skill_id:
			return skill
	return {}


## Seconds left before `id` can use `skill_id` again (0 if ready/unknown).
func skill_cooldown_left(id: String, skill_id: String) -> float:
	if not _entities.has(id):
		return 0.0
	var e: Dictionary = _entities[id]
	var skill: Dictionary = _find_skill(e.archetype, skill_id)
	if skill.is_empty():
		return 0.0
	var time_since_use: float = _time - _last_use_time(e, skill_id)
	return RulesSkills.skill_cooldown_left(time_since_use, float(skill.cooldown))


## Skill ids `id` has reached the level for, in archetype skill order.
## Empty for unknown/non-progression entities.
func unlocked_skills(id: String) -> Array[String]:
	var result: Array[String] = []
	if not _entities.has(id):
		return result
	var e: Dictionary = _entities[id]
	if not e.has_progression or not RulesBalanceData.CLASSES.archetypes.has(e.archetype):
		return result
	var skills: Array = RulesBalanceData.CLASSES.archetypes[e.archetype].skills
	for skill: Dictionary in skills:
		if RulesSkills.skill_unlocked(float(skill.level), e.level):
			result.append(String(skill.id))
	return result


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
	if victim.money_max > 0.0:
		var money: float = RulesEconomy.roll_money(victim.money_min, victim.money_max, rng.randf())
		if money > 0.0:
			money_dropped.emit(killer_id, money)
	killer.total_xp += xp_amount
	var new_level: float = RulesXp.level_for_xp(killer.total_xp)
	xp_gained.emit(killer_id, xp_amount, killer.total_xp, new_level)

	if new_level > killer.level:
		killer.level = new_level
		_recompute_progression_stats(killer)
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
	_time += delta
	for id: String in _entities.keys():
		var e: Dictionary = _entities[id]
		if not e.crash_active:
			continue
		e.crash_remaining -= delta
		if e.crash_remaining <= 0.0:
			e.crash_active = false
			e.crash_remaining = 0.0
			crash_ended.emit(id)
