// Combat math. RulesScript subset (see .claude/skills/shared-rules-authoring).
import { CRIT_CHANCE, CRIT_MULT, DEF_SCALE, MIN_DAMAGE } from "./_constants.js";

export interface Combatant {
  attack: number;
  defense: number;
  level: number;
  hp: number;
}

// Damage formula (documented once here; docs/balance/report.md and balance_sim.py rely on it via DPS):
//   raw    = attacker.attack * power - defender.defense * 0.5
//   base   = max(MIN_DAMAGE, floor(raw))
//   diff   = attacker.level - defender.level; each level of advantage/disadvantage shifts
//            damage by 5%, capped at +/-25% (so a 5+ level gap always hits the cap)
//   scaled = floor(base * (1 + clamp(diff * 0.05, -0.25, 0.25)))
//   crit   = roll < CRIT_CHANCE multiplies the scaled damage by CRIT_MULT (floored)
//   final  = max(MIN_DAMAGE, scaled)
// `roll` must be in [0,1) and is supplied by the caller (server tick) — never Math.random() here.
export function damage(attacker: Combatant, defender: Combatant, power: number, roll: number): number {
  const raw: number = attacker.attack * power - defender.defense * 0.5;
  const base: number = Math.max(MIN_DAMAGE, Math.floor(raw));
  const level_diff: number = attacker.level - defender.level;
  const diff_mult: number = 1 + Math.max(-0.25, Math.min(0.25, level_diff * 0.05));
  let scaled: number = Math.floor(base * diff_mult);
  if (roll < CRIT_CHANCE) {
    scaled = Math.floor(scaled * CRIT_MULT);
  }
  return Math.max(MIN_DAMAGE, scaled);
}

// Effective HP: raw HP scaled up by defense. DEF_SCALE points of defense double effective HP.
export function effective_hp(c: Combatant): number {
  return c.hp * (1 + c.defense / DEF_SCALE);
}

// Apply damage to hp, never going below 0.
export function apply_damage(hp: number, dmg: number): number {
  return Math.max(0, hp - dmg);
}

// Whether hp has reached 0 (dead).
export function is_dead(hp: number): boolean {
  return hp <= 0;
}

// Healing: hp after adding `amount`, floored, clamped to [0, max_hp]. Negative amounts never heal.
export function heal(hp: number, max_hp: number, amount: number): number {
  return Math.max(0, Math.min(max_hp, Math.floor(hp + Math.max(0, amount))));
}
