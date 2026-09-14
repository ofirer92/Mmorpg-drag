extends Node2D
## Screenshot-only demo scaffold for docs/screenshots/shop_390x844.png
## (scripts/screenshot.sh). Seeds an Inventory with some money + a few
## items and opens the ShopPanel bound to the pharmacist so both the Stock
## and Your Bag tabs have something to show. Not a gameplay scene — no
## LocalServer/ClinicLobby needed for a UI screenshot.

const ShopPanelScene: PackedScene = preload("res://scenes/ui/shop_panel.tscn")

var inventory: Inventory = Inventory.new()


func _ready() -> void:
	inventory.money = 40
	inventory.add("expired_bandage", 2)
	inventory.add("rubber_stamp_sword")

	var shop_panel: ShopPanel = ShopPanelScene.instantiate()
	add_child(shop_panel)
	shop_panel.bind(inventory, "pharmacist")
	shop_panel.open()
