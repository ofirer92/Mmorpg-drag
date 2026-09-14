class_name Drop
extends Area2D
## T-0.9: a loot pickup a dead monster spawns. LocalServer already decided
## the item id (via RulesLoot.roll_loot) before this node was ever created —
## this script only detects the player overlapping it and reports the
## pickup. It never decides what drops or whether it drops.

signal picked_up(item_id: String)

@export var item_id: String = ""


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		picked_up.emit(item_id)
		queue_free()
