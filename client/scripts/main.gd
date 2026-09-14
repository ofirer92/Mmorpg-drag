extends Node2D
## Entry scene. Phase 0: boots into the clinic-lobby prototype map (player +
## touch controls + monsters), the HUD and the inventory panel, and owns the
## local save (T-0.13). The I18n table itself is populated earlier, by the
## I18nBoot autoload (see client/scripts/i18n_boot.gd).

const ARCHETYPE: String = "stim"
const AUTOSAVE_INTERVAL_S: float = 30.0

## Tests point this at a scratch file; the game uses SaveGame.default_path().
@export var save_path: String = ""
## Tests can disable loading so they start from a clean state.
@export var load_on_ready: bool = true

var inventory: Inventory = Inventory.new()

@onready var clinic_lobby: ClinicLobby = $ClinicLobby
@onready var hud: Hud = $Hud
@onready var inventory_panel: InventoryPanel = $InventoryPanel
@onready var autosave_timer: Timer = $AutosaveTimer


func _ready() -> void:
	if save_path == "":
		save_path = SaveGame.default_path()
	($Label as Label).text = I18n.t("ui.title")
	var server: LocalServer = clinic_lobby.local_server
	hud.bind(server, Player.ENTITY_ID)
	clinic_lobby.inventory = inventory
	inventory_panel.bind(inventory)
	inventory.equipped_changed.connect(_on_equipped_changed)
	inventory_panel.used.connect(_on_item_used)
	server.level_up.connect(_on_level_up)
	autosave_timer.wait_time = AUTOSAVE_INTERVAL_S
	autosave_timer.timeout.connect(save_game)
	autosave_timer.start()
	if load_on_ready and SaveGame.exists(save_path):
		apply_save(SaveGame.load(save_path))
	print("Hamirpaa boot ok — level %d" % int(server.get_level(Player.ENTITY_ID)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func _on_equipped_changed(_slot: String, _item_id: String) -> void:
	clinic_lobby.local_server.set_gear_bonus(Player.ENTITY_ID, inventory.equipped_stats())


## A consumable's effect is its `stats.hp` (items.yaml); the server applies it.
func _on_item_used(item_id: String) -> void:
	var items: Dictionary = RulesBalanceData.ITEMS["items"]
	if not items.has(item_id):
		return
	var stats: Dictionary = items[item_id].get("stats", {})
	clinic_lobby.local_server.heal(Player.ENTITY_ID, float(stats.get("hp", 0)))


func _on_level_up(_id: String, _level: float, _stats: Dictionary) -> void:
	save_game()


## T-0.13 save shape: {version, saved_at, player: {archetype, level, total_xp, hp,
## position: [x, y]}, inventory: Inventory.to_dict()}. Numbers come back as floats.
func collect_save() -> Dictionary:
	var server: LocalServer = clinic_lobby.local_server
	var stats: Dictionary = server.get_stats(Player.ENTITY_ID)
	var pos: Vector2 = clinic_lobby.get_player_position()
	return {
		"player": {
			"archetype": ARCHETYPE,
			"level": stats.level,
			"total_xp": stats.total_xp,
			"hp": stats.hp,
			"position": [pos.x, pos.y],
		},
		"inventory": inventory.to_dict(),
	}


func save_game() -> Error:
	return SaveGame.save(save_path, collect_save())


func apply_save(data: Dictionary) -> void:
	if data.is_empty():
		return
	var server: LocalServer = clinic_lobby.local_server
	var player_data: Dictionary = data.get("player", {})
	var inv_data: Dictionary = data.get("inventory", {})
	inventory.from_dict(inv_data)
	server.set_progress(Player.ENTITY_ID, float(player_data.get("total_xp", 0.0)))
	server.set_gear_bonus(Player.ENTITY_ID, inventory.equipped_stats())
	server.set_hp(Player.ENTITY_ID, float(player_data.get("hp", server.get_max_hp(Player.ENTITY_ID))))
	var pos: Variant = player_data.get("position", null)
	if pos is Array and pos.size() == 2:
		clinic_lobby.set_player_position(Vector2(float(pos[0]), float(pos[1])))
	hud.refresh()
