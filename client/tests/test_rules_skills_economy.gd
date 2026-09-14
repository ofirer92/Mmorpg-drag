extends GutTest
## Parity for generated skills.gd / economy.gd against the TS tests' expectations.


func test_skill_gates() -> void:
	assert_false(RulesSkills.skill_unlocked(3, 2))
	assert_true(RulesSkills.skill_unlocked(3, 3))
	assert_true(RulesSkills.skill_ready(0, 0))
	assert_false(RulesSkills.skill_ready(3.99, 4))
	assert_true(RulesSkills.skill_ready(4, 4))
	assert_eq(RulesSkills.skill_cooldown_left(1, 4), 3.0)
	var skills: Array = RulesBalanceData.CLASSES["archetypes"]["stim"]["skills"]
	assert_eq(skills.size(), 5)
	var third: Dictionary = skills[2]
	assert_eq(RulesSkills.skill_total_power(third), float(third["power"]) * float(third["hits"]))


func test_economy() -> void:
	assert_eq(RulesEconomy.buy_price(0), 1.0)
	assert_eq(RulesEconomy.buy_price(10), floor(10.0 * RulesConstants.BUY_PRICE_MULT))
	assert_eq(RulesEconomy.sell_price(10), floor(10.0 * RulesConstants.SELL_PRICE_MULT))
	assert_eq(RulesEconomy.roll_money(3, 7, 0.0), 3.0)
	assert_eq(RulesEconomy.roll_money(3, 7, 0.999999), 7.0)
	assert_eq(RulesEconomy.roll_money(3, 7, 0.5), 5.0)
	assert_true(RulesEconomy.can_afford(10, 5, 2))
	assert_false(RulesEconomy.can_afford(9, 5, 2))


func test_kill_drops_money_to_killer() -> void:
	var server: LocalServer = add_child_autofree(LocalServer.new())
	server.seed_rng(7)
	server.register("hero", {"level": 1.0}, "stim")
	server.register("slime", {"attack": 1.0, "defense": 0.0, "level": 1.0, "hp": 1.0, "xp": 5.0, "money": {"min": 2, "max": 4}})
	watch_signals(server)
	server.request_attack("hero", "slime", 1.0)
	assert_signal_emitted(server, "money_dropped")
	var params: Array = get_signal_parameters(server, "money_dropped")
	assert_eq(params[0], "hero")
	assert_between(params[1], 2.0, 4.0)
