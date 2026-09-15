// T-2.4: a small seedable PRNG for every server-authoritative roll (crit / loot / money). Combat and
// loot math never call Math.random() directly, so a Zone can be seeded and a test gets reproducible
// rolls — mirrors client/scripts/combat/local_server.gd's seed_rng()/RandomNumberGenerator.seed.
export type Rng = () => number;

/**
 * mulberry32: fast, statistically fine for gameplay rolls, fully deterministic per seed. Returns a
 * float in [0, 1) on every call, same contract as shared-rules' `roll` parameters (damage/roll_loot/
 * roll_money all expect this range).
 */
export function createRng(seed: number): Rng {
  let a = seed >>> 0;
  return function rng(): number {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
