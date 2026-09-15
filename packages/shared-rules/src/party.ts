// T-2.6: group xp rules. RulesScript subset (see .claude/skills/shared-rules-authoring).
// ⚠️ PLACEHOLDER curve (Q8, docs/balance/party.yaml) — the SHAPE (more total xp for more players who
// damaged the kill, split evenly, capped) is fixed here so the server has something principled to
// run; the designer owns the final numbers once the real GDD lands.
import { PARTY } from "./_balance_data.js";

// Bonus percent added to the total xp pool for a kill witnessed by `member_count` damaging players.
// Solo (member_count <= 1) gets no bonus; the bonus stops growing past PARTY.max_bonus_members
// participants (a 5th+ damaging player adds nothing more).
export function group_xp_bonus_pct(member_count: number): number {
  const counted: number = Math.max(0, Math.min(member_count, PARTY.max_bonus_members) - 1);
  return counted * PARTY.group_xp_bonus_pct_per_member;
}

// Each damaging player's xp share of `total_xp`: the group-bonused pool split evenly, floored, and
// never below 1 (so participating always grants something) as long as member_count > 0. 0 for
// member_count <= 0 (nobody to split between).
export function group_xp_share(total_xp: number, member_count: number): number {
  if (member_count <= 0) {
    return 0;
  }
  const bonus_pct: number = group_xp_bonus_pct(member_count);
  const pool: number = Math.floor(total_xp * (1 + bonus_pct / 100));
  return Math.max(1, Math.floor(pool / member_count));
}
