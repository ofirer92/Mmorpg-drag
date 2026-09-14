extends Node2D
## Screenshot-only demo scaffold for docs/screenshots/dialogue_390x844.png
## (scripts/screenshot.sh). Opens the DialogueBox on the pharmacist's greet
## line, same content main.gd builds from RulesBalanceData.NPCS on a real
## npc_interact_requested — this demo just skips the map/NPC/player and
## calls show_lines() directly so the UI can be screenshotted on its own.

const DialogueBoxScene: PackedScene = preload("res://scenes/ui/dialogue_box.tscn")

const NPC_ID: String = "pharmacist"


func _ready() -> void:
	var dialogue_box: DialogueBox = DialogueBoxScene.instantiate()
	add_child(dialogue_box)
	var def: Dictionary = RulesBalanceData.NPCS.get("npcs", {}).get(NPC_ID, {})
	var lines: Dictionary = def.get("lines", {})
	var line_keys: Array[String] = []
	for line_id: String in ["greet", "shop", "bye"]:
		if lines.has(line_id):
			line_keys.append(String(lines[line_id]))
	dialogue_box.show_lines(NPC_ID, String(def.get("name_key", NPC_ID)), line_keys)
