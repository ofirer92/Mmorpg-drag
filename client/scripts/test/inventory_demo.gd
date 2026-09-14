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
	inv.add("triplicate_dagger", 1)
	inv.add("ethics_committee_cap", 1)
	inv.add("liability_waiver_robe", 1)
	inv.equip("rubber_stamp_sword")
	inv.equip("ethics_committee_cap")

	var panel: InventoryPanel = PANEL_SCENE.instantiate()
	add_child(panel)
	panel.bind(inv)
	panel.open()
	# Pre-select the second weapon so the demo shows the gear-comparison row.
	if panel.bag_list.get_child_count() > 0:
		var candidate_button: Button = panel.bag_list.get_child(panel.bag_list.get_child_count() - 1)
		candidate_button.pressed.emit()
