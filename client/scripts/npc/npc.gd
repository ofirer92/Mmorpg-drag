class_name Npc
extends Area2D
## T-0.12: a shop/dialogue NPC (e.g. the pharmacist). Reads its display name
## from RulesBalanceData.NPCS (generated from docs/balance/npcs.yaml) — never
## a literal name/line here; dialogue/shop CONTENT lives in main.gd, which
## owns the DialogueBox/ShopPanel this NPC's interact_requested wires into.
##
## Detects the player with this Area2D's own body_entered/body_exited (same
## collision_layer/mask convention as Drop — see client/scripts/monsters/drop.gd)
## and shows a "talk" prompt near the bottom of the screen while the player
## is in range. Pressing the prompt — or the `attack` action while in range,
## so a controller/keyboard player doesn't need to reach for a screen button —
## emits `interact_requested(npc_id)`.

signal interact_requested(npc_id: String)

@export var npc_id: String = "pharmacist"

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel
@onready var talk_button: Button = $PromptLayer/TalkButton

## True while the player is inside this NPC's interaction Area2D. Exposed
## (not just private) so tests can assert on it without depending on the
## prompt button's visibility as a proxy.
var player_in_range: bool = false


func _ready() -> void:
	var def: Dictionary = RulesBalanceData.NPCS.get("npcs", {}).get(npc_id, {})
	name_label.text = I18n.t(String(def.get("name_key", npc_id)))
	talk_button.text = I18n.t("ui.dialogue.talk")
	talk_button.visible = false
	talk_button.pressed.connect(_on_talk_pressed)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if sprite != null:
		var tex_path: String = "res://assets/generated/npc_%s.png" % npc_id
		if ResourceLoader.exists(tex_path):
			sprite.texture = load(tex_path)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		player_in_range = true
		talk_button.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		player_in_range = false
		talk_button.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if player_in_range and event.is_action_pressed(&"attack"):
		get_viewport().set_input_as_handled()
		interact_requested.emit(npc_id)


func _on_talk_pressed() -> void:
	interact_requested.emit(npc_id)
