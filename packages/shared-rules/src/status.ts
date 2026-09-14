// Status mechanics. RulesScript subset. Phase 0: the Stim "crash" — after N consecutive landed hits the
// player crashes for D seconds and takes damage × M. Numbers come from docs/balance/classes.yaml
// (archetypes.stim.mechanics.crash) via _balance_data — never literals here.
import { CLASSES } from "./_balance_data.js";

// Consecutive-hit counter after an attack: a landed hit increments, a miss/idle resets to 0.
export function next_consecutive_hits(hits: number, hit_landed: boolean): number {
  if (hit_landed) {
    return hits + 1;
  }
  return 0;
}

// Does this many consecutive hits trigger the crash?
export function crash_triggers(consecutive_hits: number): boolean {
  return consecutive_hits >= CLASSES.archetypes.stim.mechanics.crash.hits_in_a_row;
}

// How long the crash lasts, in seconds.
export function crash_duration_s(): number {
  return CLASSES.archetypes.stim.mechanics.crash.duration_s;
}

// Multiplier applied to damage TAKEN while crashed (1 when not crashed).
export function crash_damage_taken_mult(crash_active: boolean): number {
  if (crash_active) {
    return CLASSES.archetypes.stim.mechanics.crash.damage_taken_mult;
  }
  return 1;
}

// Damage taken after the crash multiplier, floored, never below 0.
export function damage_taken(dmg: number, crash_active: boolean): number {
  return Math.max(0, Math.floor(dmg * crash_damage_taken_mult(crash_active)));
}
