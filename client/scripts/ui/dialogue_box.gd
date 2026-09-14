class_name DialogueBox
extends CanvasLayer
## T-0.12: shows one NPC line at a time. `show_lines(npc_id, name_key,
## line_keys)` starts a dialogue: `name_key` is the NPC's display-name key,
## `line_keys` the ordered line keys to show (e.g. [greet, shop, bye] from
## RulesBalanceData.NPCS[id].lines — main.gd builds that array, this box only
## displays it). The Next button (ui.dialogue.next) advances one line at a
## time.
##
## The pharmacist sequence (greet → shop → bye) needs a pause in the middle:
## when Next is pressed on the line that equals RulesBalanceData.NPCS[npc_id]
## .lines.shop, this box does NOT auto-advance to "bye" — instead it hides
## itself and emits `shop_requested(npc_id)` so main.gd can open the shop
## panel over it. Once the shop is closed, main.gd calls `shop_closed()` to
## resume the dialogue at the next line ("bye"). `finished` fires once the
## last line has been advanced past (dialogue fully done, box closed).

signal shop_requested(npc_id: String)
signal finished

@onready var root: Control = $Root
@onready var name_label: Label = $Root/Window/Margin/Content/NameLabel
@onready var line_label: Label = $Root/Window/Margin/Content/LineLabel
@onready var next_button: Button = $Root/Window/Margin/Content/NextButton

var _npc_id: String = ""
var _line_keys: Array[String] = []
var _shop_line_key: String = ""
## True once shop_requested has fired for the current "shop" line, so a
## stray extra Next press (or shop_closed being called twice) can't re-fire it.
var _waiting_for_shop: bool = false
var _index: int = -1


func _ready() -> void:
	root.visible = false
	next_button.text = I18n.t("ui.dialogue.next")
	next_button.pressed.connect(_on_next_pressed)


func show_lines(npc_id: String, name_key: String, line_keys: Array[String]) -> void:
	_npc_id = npc_id
	_line_keys = line_keys.duplicate()
	var lines_def: Dictionary = RulesBalanceData.NPCS.get("npcs", {}).get(npc_id, {}).get("lines", {})
	_shop_line_key = String(lines_def.get("shop", ""))
	_waiting_for_shop = false
	_index = -1
	name_label.text = I18n.t(name_key)
	root.visible = true
	_step_forward()


func is_open() -> bool:
	return root.visible


## Called externally (main.gd) once the shop panel this dialogue opened has
## been closed — resumes the dialogue at the line after "shop".
func shop_closed() -> void:
	if not _waiting_for_shop:
		return
	_waiting_for_shop = false
	root.visible = true
	_step_forward()


func _current_key() -> String:
	return _line_keys[_index] if _index >= 0 and _index < _line_keys.size() else ""


func _step_forward() -> void:
	_index += 1
	if _index >= _line_keys.size():
		root.visible = false
		finished.emit()
		return
	line_label.text = I18n.t(_line_keys[_index])


func _on_next_pressed() -> void:
	if _waiting_for_shop:
		return
	var current_key: String = _current_key()
	if current_key != "" and current_key == _shop_line_key:
		_waiting_for_shop = true
		root.visible = false
		shop_requested.emit(_npc_id)
		return
	_step_forward()
