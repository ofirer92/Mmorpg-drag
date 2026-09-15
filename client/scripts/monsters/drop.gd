class_name Drop
extends Area2D
## T-0.9: a loot pickup a dead monster spawns. LocalServer already decided
## the item id (via RulesLoot.roll_loot) and its rolled affixes (T-1.7b, via
## RulesAffixes on the authority's own rng) before this node was ever created —
## this script only detects the player overlapping it and reports the
## pickup. It never decides what drops, whether it drops, or what it rolled.

signal picked_up(item_id: String, affixes: Array)

@export var item_id: String = ""
## Affix ids rolled for THIS drop (docs/balance/items.yaml). Empty for a plain roll.
@export var affixes: Array[String] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		picked_up.emit(item_id, affixes)
		queue_free()
