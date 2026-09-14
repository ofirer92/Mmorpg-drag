extends GutTest
## T-0.12 DoD: DialogueBox (client/scripts/ui/dialogue_box.gd) advances
## greet → shop → bye, pausing on "shop" to let the caller open the shop
## panel (shop_requested), and resuming into "bye" only once shop_closed()
## is called; finished fires once the dialogue is fully done.

const NPC_ID: String = "pharmacist"


func _box() -> DialogueBox:
	var packed: PackedScene = load("res://scenes/ui/dialogue_box.tscn")
	var node: DialogueBox = packed.instantiate()
	add_child_autofree(node)
	return node


func _lines() -> Array[String]:
	var def: Dictionary = RulesBalanceData.NPCS["npcs"][NPC_ID]
	var lines: Dictionary = def["lines"]
	return [String(lines["greet"]), String(lines["shop"]), String(lines["bye"])]


func test_show_lines_opens_and_shows_the_first_line() -> void:
	var db: DialogueBox = _box()
	db.show_lines(NPC_ID, "npc.pharmacist.name", _lines())
	assert_true(db.is_open())
	assert_eq(db.name_label.text, I18n.t("npc.pharmacist.name"))
	assert_eq(db.line_label.text, I18n.t("npc.pharmacist.greet"))


func test_next_advances_from_greet_to_shop() -> void:
	var db: DialogueBox = _box()
	db.show_lines(NPC_ID, "npc.pharmacist.name", _lines())
	db.next_button.pressed.emit()
	assert_eq(db.line_label.text, I18n.t("npc.pharmacist.shop"))
	assert_true(db.is_open())


func test_next_on_the_shop_line_emits_shop_requested_once_and_hides() -> void:
	var db: DialogueBox = _box()
	db.show_lines(NPC_ID, "npc.pharmacist.name", _lines())
	db.next_button.pressed.emit()  # greet -> shop line shown
	watch_signals(db)
	db.next_button.pressed.emit()  # on shop line -> shop_requested
	assert_signal_emit_count(db, "shop_requested", 1)
	assert_signal_emitted_with_parameters(db, "shop_requested", [NPC_ID])
	assert_false(db.is_open(), "box hides while the shop is open")

	# Pressing Next again while waiting for the shop must not double-fire.
	db.next_button.pressed.emit()
	assert_signal_emit_count(db, "shop_requested", 1)


func test_shop_closed_resumes_into_bye() -> void:
	var db: DialogueBox = _box()
	db.show_lines(NPC_ID, "npc.pharmacist.name", _lines())
	db.next_button.pressed.emit()  # -> shop line
	db.next_button.pressed.emit()  # -> shop_requested, waiting

	db.shop_closed()
	assert_true(db.is_open())
	assert_eq(db.line_label.text, I18n.t("npc.pharmacist.bye"))


func test_finished_emitted_after_the_last_line() -> void:
	var db: DialogueBox = _box()
	db.show_lines(NPC_ID, "npc.pharmacist.name", _lines())
	db.next_button.pressed.emit()  # -> shop
	db.next_button.pressed.emit()  # -> shop_requested
	db.shop_closed()  # -> bye
	watch_signals(db)
	db.next_button.pressed.emit()  # -> past the last line
	assert_signal_emitted(db, "finished")
	assert_false(db.is_open())


func test_dialogue_without_a_shop_line_never_requests_the_shop() -> void:
	var db: DialogueBox = _box()
	var greet_only: Array[String] = ["npc.pharmacist.greet"]
	db.show_lines("no_shop_npc", "npc.pharmacist.name", greet_only)
	watch_signals(db)
	db.next_button.pressed.emit()
	assert_signal_not_emitted(db, "shop_requested")
	assert_signal_emitted(db, "finished")
