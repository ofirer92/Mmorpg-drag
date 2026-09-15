# GENERATED from packages/shared-rules/src/party.ts sha256:d91d871569c18c90 — DO NOT EDIT (run scripts/gen_rules.py)
class_name RulesParty

# T-2.6: group xp rules. RulesScript subset (see .claude/skills/shared-rules-authoring).
# ⚠️ PLACEHOLDER curve (Q8, docs/balance/party.yaml) — the SHAPE (more total xp for more players who
# damaged the kill, split evenly, capped) is fixed here so the server has something principled to
# run; the designer owns the final numbers once the real GDD lands.

# Bonus percent added to the total xp pool for a kill witnessed by `member_count` damaging players.
# Solo (member_count <= 1) gets no bonus; the bonus stops growing past PARTY.max_bonus_members
# participants (a 5th+ damaging player adds nothing more).

static func group_xp_bonus_pct(member_count: float) -> float:
	var counted: float = max(0.0, min(member_count, RulesBalanceData.PARTY.max_bonus_members) - 1.0)
	return counted * RulesBalanceData.PARTY.group_xp_bonus_pct_per_member

# Each damaging player's xp share of `total_xp`: the group-bonused pool split evenly, floored, and
# never below 1 (so participating always grants something) as long as member_count > 0. 0 for
# member_count <= 0 (nobody to split between).

static func group_xp_share(total_xp: float, member_count: float) -> float:
	if member_count <= 0.0:
		return 0.0
	var bonus_pct: float = group_xp_bonus_pct(member_count)
	var pool: float = floor(total_xp * (1.0 + bonus_pct / 100.0))
	return max(1.0, floor(pool / member_count))
