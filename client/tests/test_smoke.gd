extends GutTest
## T-I.3 DoD: one passing test proving GUT runs headless and the main scene instantiates.


func test_main_scene_instantiates() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	assert_not_null(packed, "main.tscn loads")
	var node: Node = add_child_autofree(packed.instantiate())
	assert_true(node is Node2D, "main root is Node2D")


func test_i18n_falls_back_to_key() -> void:
	I18n.load_table({"class.stim.name": "הממריץ"})
	assert_eq(I18n.t("class.stim.name"), "הממריץ")
	assert_eq(I18n.t("missing.key"), "missing.key")
