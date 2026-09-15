extends GutTest
## T-2.6 parity: the generated party.gd must agree with packages/shared-rules/src/party.ts (asserted
## by tests/party.test.ts) on every group-xp number, because the server splits the xp and the client
## displays it. Numbers come from docs/balance/party.yaml (⚠️ placeholder curve, Q8).


func test_solo_kill_gets_no_bonus_and_the_full_xp() -> void:
	assert_eq(RulesParty.group_xp_bonus_pct(1), 0.0)
	assert_eq(RulesParty.group_xp_share(100, 1), 100.0)


func test_bonus_grows_per_extra_member_and_caps() -> void:
	var per: float = float(RulesBalanceData.PARTY["group_xp_bonus_pct_per_member"])
	var cap: int = int(RulesBalanceData.PARTY["max_bonus_members"])
	assert_eq(RulesParty.group_xp_bonus_pct(2), per)
	assert_eq(RulesParty.group_xp_bonus_pct(cap), float(cap - 1) * per)
	assert_eq(
		RulesParty.group_xp_bonus_pct(cap + 5),
		RulesParty.group_xp_bonus_pct(cap),
		"past the cap an extra member adds nothing"
	)


func test_share_splits_the_bonused_pool_evenly_and_floors() -> void:
	var per: float = float(RulesBalanceData.PARTY["group_xp_bonus_pct_per_member"])
	var pool: float = floor(100.0 * (1.0 + per / 100.0))
	assert_eq(RulesParty.group_xp_share(100, 2), floor(pool / 2.0))
	assert_true(RulesParty.group_xp_share(100, 2) < 100.0, "a 2-way split is less than soloing")


func test_share_never_drops_below_one_and_handles_empty_parties() -> void:
	assert_eq(RulesParty.group_xp_share(1, 4), 1.0, "participating always grants at least 1 xp")
	assert_eq(RulesParty.group_xp_share(0, 3), 1.0)
	assert_eq(RulesParty.group_xp_share(100, 0), 0.0, "nobody to split between")
	assert_eq(RulesParty.group_xp_share(100, -2), 0.0)
