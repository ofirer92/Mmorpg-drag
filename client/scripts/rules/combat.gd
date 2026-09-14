# GENERATED from packages/shared-rules/src/combat.ts sha256:e8ce9c010729ee9d — DO NOT EDIT (run scripts/gen_rules.py)
class_name RulesCombat

# Combat math. RulesScript subset (see .claude/skills/shared-rules-authoring).


# Damage formula (documented once here; docs/balance/report.md and balance_sim.py rely on it via DPS):
#   raw    = attacker.attack * power - defender.defense * 0.5
#   base   = max(MIN_DAMAGE, floor(raw))
#   diff   = attacker.level - defender.level; each level of advantage/disadvantage shifts
#            damage by 5%, capped at +/-25% (so a 5+ level gap always hits the cap)
#   scaled = floor(base * (1 + clamp(diff * 0.05, -0.25, 0.25)))
#   crit   = roll < CRIT_CHANCE multiplies the scaled damage by CRIT_MULT (floored)
#   final  = max(MIN_DAMAGE, scaled)
# `roll` must be in [0,1) and is supplied by the caller (server tick) — never Math.random() here.

static func damage(attacker: Dictionary, defender: Dictionary, power: float, roll: float) -> float:
	var raw: float = attacker.attack * power - defender.defense * 0.5
	var base: float = max(RulesConstants.MIN_DAMAGE, floor(raw))
	var level_diff: float = attacker.level - defender.level
	var diff_mult: float = 1.0 + max(-0.25, min(0.25, level_diff * 0.05))
	var scaled: float = floor(base * diff_mult)
	if roll < RulesConstants.CRIT_CHANCE:
		scaled = floor(scaled * RulesConstants.CRIT_MULT)
	return max(RulesConstants.MIN_DAMAGE, scaled)

# Effective HP: raw HP scaled up by defense. DEF_SCALE points of defense double effective HP.

static func effective_hp(c: Dictionary) -> float:
	return c.hp * (1.0 + c.defense / RulesConstants.DEF_SCALE)

# Apply damage to hp, never going below 0.

static func apply_damage(hp: float, dmg: float) -> float:
	return max(0.0, hp - dmg)

# Whether hp has reached 0 (dead).

static func is_dead(hp: float) -> bool:
	return hp <= 0.0
