class_name CombatAuthority
extends Node
## T-2.4/T-2.9: the seam between game code (Player/Monster/HUD/SkillBar/map)
## and whoever actually resolves combat. This is the T-2.9 endpoint the
## WORKPLAN promises: in single-player, LocalServer (client/scripts/combat/
## local_server.gd) extends this and resolves damage/xp/loot itself, exactly
## as it always has (CLAUDE.md still allows it — it's the only script outside
## rules/ that may call RulesCombat.damage/RulesLoot.roll_loot). In net mode,
## client/scripts/combat/remote_authority.gd's RemoteAuthority extends this
## instead and NEVER computes anything: it turns every call below into a
## protocol v1 intent (docs/protocol.md) and turns the server's facts back
## into these exact same signals. Game code (Player.set_local_server, hud.gd,
## skill_bar.gd) is typed against THIS class, never against LocalServer
## directly, so it needs no net-mode special-casing anywhere — a grep for
## "RulesCombat.damage(" or "RulesLoot.roll_loot(" outside rules/ must only
## ever hit local_server.gd, in single-player OR net mode.
##
## "abstract-ish", same pattern as client/scripts/net/net_transport.gd: no
## `abstract` keyword in GDScript, so this IS a concrete (inert) class whose
## methods return harmless defaults; subclasses override every one that
## matters. Not meant to be used directly by a scene.

## -- Signals every entity-facing script (Player/Monster/Hud/SkillBar) reacts
## to. LocalServer emits these when it resolves combat locally; RemoteAuthority
## re-emits them (with ids remapped so the local player is always
## Player.ENTITY_ID, never the server's own player_id) when the matching
## protocol fact arrives. See each subclass for exact emission rules.
signal damage_dealt(target_id: String, amount: float, new_hp: float, crit: bool)
signal entity_died(id: String, xp: float, drop_item_id: String)
signal crash_started(id: String, duration: float)
signal crash_ended(id: String)
signal xp_gained(id: String, amount: float, total_xp: float, level: float)
signal level_up(id: String, new_level: float, stats: Dictionary)
signal healed(id: String, amount: float, new_hp: float)
signal money_dropped(killer_id: String, amount: float)
signal skill_used(id: String, skill_id: String, cooldown: float)
signal skill_rejected(id: String, skill_id: String, reason: String)
## Emitted when an entity's stats changed without a combat event to announce it — in net mode the
## authoritative hp/level/xp arrive in ordinary `state` snapshots, and a display that only refreshes
## on damage would sit on stale (or unknown) numbers until something hit you. LocalServer never needs
## it: there, every stat change already has a signal.
signal stats_synced(id: String)


## Tell this authority about a combat entity. In single-player this creates
## real server-side stats (LocalServer.register); in net mode the server
## already knows about every entity from `join`/`state`, so this is a no-op
## bookkeeping call (RemoteAuthority only remembers the archetype for its own
## unlocked_skills()/cooldown display math).
func register(_id: String, _stats: Dictionary, _progression_archetype: String = "") -> void:
	pass


## Attacker's intent to hit target_id. Single-player: resolves immediately.
## Net mode: never resolves anything itself — see RemoteAuthority's header.
func request_attack(_attacker_id: String, _target_id: String, _power: float) -> void:
	pass


## Attacker's intent to use skill_id on target_ids. Returns true iff the
## intent was locally accepted (single-player: unlocked + off cooldown; net
## mode: always true — the server is the one who can actually refuse, via a
## timeout/no-`attack`-fact or an `error`, which surfaces as skill_rejected).
func request_skill(_attacker_id: String, _target_ids: Array[String], _skill_id: String) -> bool:
	return false


## True (the default) when this authority needs Player's own HitBox-overlap
## query to already have found real target_ids before request_skill() is
## worth calling at all — true for LocalServer (it computes damage itself,
## so an empty target list really is "swung at nothing"). RemoteAuthority
## overrides this to false: the SERVER decides who got hit, never the
## client's local hitbox, so Player.gd must still send the intent even when
## its own hitbox query found nobody (see player.gd's _resolve_pending_attack()).
func needs_local_targets() -> bool:
	return true


## hp/max_hp/attack/defense/level/total_xp. Net mode: attack/defense are not
## part of protocol v1's PlayerState/MonsterState (docs/protocol.md) and read
## 0 — a known limitation, not a bug (see remote_authority.gd's header).
func get_stats(_id: String) -> Dictionary:
	return {"hp": 0.0, "max_hp": 0.0, "attack": 0.0, "defense": 0.0, "level": 0.0, "total_xp": 0.0}


func get_hp(_id: String) -> float:
	return 0.0


func get_max_hp(_id: String) -> float:
	return 0.0


func is_alive(_id: String) -> bool:
	return false


func is_crashed(_id: String) -> bool:
	return false


func is_registered(_id: String) -> bool:
	return false


func get_level(_id: String) -> float:
	return 0.0


func get_total_xp(_id: String) -> float:
	return 0.0


## Seconds left before `id` can use `skill_id` again — display-only in net
## mode (RemoteAuthority predicts it from the last confirmed `attack` fact
## plus the skill's own cooldown read from balance data, never from a real
## server-side timer the client can see).
func skill_cooldown_left(_id: String, _skill_id: String) -> float:
	return 0.0


## Skill ids `id` has reached the level for, in archetype skill order.
func unlocked_skills(_id: String) -> Array[String]:
	return []


## A consumable's effect. No protocol v1 message exists for this yet (out of
## T-2.4 scope) — RemoteAuthority's override is a documented no-op.
func heal(_id: String, _amount: float) -> void:
	pass


## Equipped-gear flat stat bonus. Same no-protocol-yet note as heal() above.
func set_gear_bonus(_id: String, _bonus: Dictionary) -> void:
	pass
