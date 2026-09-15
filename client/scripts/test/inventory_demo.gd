extends Node2D
## Demo scaffold for docs/screenshots/inventory_390x844.png (scripts/screenshot.sh).
## Seeds an Inventory with a representative mix of items, binds it to the
## InventoryPanel, and opens the panel with an item pre-selected so the
## comparison row is visible in the screenshot.

const PANEL_SCENE: PackedScene = preload("res://scenes/ui/inventory_panel.tscn")


func _ready() -> void:
	var inv: Inventory = Inventory.new()
	inv.add("expired_bandage", 3)
	inv.add("placebo_pill", 1)
	inv.add("rubber_stamp_sword", 1)
	# T-1.7b: two more rolls of the SAME sword, so the shot shows instances being told apart by
	# their affixes (and the comparison row reading the selected instance, not the item id).
	inv.add_instance("rubber_stamp_sword", ["off_label"])
	inv.add_instance("triplicate_dagger", ["side_effects_may_include", "insured"])
	inv.add("ethics_committee_cap", 1)
	inv.add_instance("liability_waiver_robe", ["dosage_adjusted"])
	inv.equip("rubber_stamp_sword")
	inv.equip("ethics_committee_cap")

	var panel: InventoryPanel = PANEL_SCENE.instantiate()
	add_child(panel)
	panel.bind(inv)
	panel.open()
	# Pre-select the affixed sword so the comparison row shows an affix-inclusive delta against the
	# plain one currently equipped.
	for child: Node in panel.bag_list.get_children():
		if (child as Button).text.contains("["):
			(child as Button).pressed.emit()
			break
