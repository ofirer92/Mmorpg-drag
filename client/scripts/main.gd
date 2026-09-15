extends Node2D
## Entry scene. Phase 0: boots into the clinic-lobby prototype map (player +
## touch controls + monsters + the pharmacist NPC), the HUD, the inventory
## panel, the dialogue box + shop panel (T-0.12), and owns the local save
## (T-0.13). The I18n table itself is populated earlier, by the I18nBoot
## autoload (see client/scripts/i18n_boot.gd).
##
## T-2.3 NetMode switch: `net_url` empty (the default) = single-player,
## exactly today's LocalServer-driven behaviour, byte-for-byte unchanged
## (see client/tests/test_game_session.gd). `net_url` non-empty = a
## NetSession (client/scripts/net/net_session.gd) connects and joins a real
## server for movement sync/reconciliation/remote players. LocalServer keeps
## running EITHER way in phase 2 — it still resolves this client's own
## combat locally even while networked, a deliberate hybrid documented in
## ADR-013: T-2.4 is what moves combat resolution to the server and turns
## this into a true multiplayer client; T-2.9 removes LocalServer entirely.

const ARCHETYPE: String = "stim"
const AUTOSAVE_INTERVAL_S: float = 30.0
## T-2.3: no character-select/auth flow exists yet — these are placeholder
## credentials until a real login screen sends a real token/character_id.
const DEV_TOKEN: String = "dev-token"
const DEV_CHARACTER_ID: String = "char_dev"

## Tests point this at a scratch file; the game uses SaveGame.default_path().
@export var save_path: String = ""
## Tests can disable loading so they start from a clean state.
@export var load_on_ready: bool = true
## T-2.3: ws:// URL of a real server. Empty = single-player. Overridden by
## the HAMIRPAA_SERVER_URL env var or a `--server=...` cmdline arg if set.
@export var net_url: String = ""

var inventory: Inventory = Inventory.new()
## Set only when networking is active (see _start_networking()).
var net_client: NetClient = null

@onready var clinic_lobby: ClinicLobby = $ClinicLobby
@onready var hud: Hud = $Hud
@onready var skill_bar: SkillBar = $SkillBar
@onready var inventory_panel: InventoryPanel = $InventoryPanel
@onready var dialogue_box: DialogueBox = $DialogueBox
@onready var shop_panel: ShopPanel = $ShopPanel
@onready var autosave_timer: Timer = $AutosaveTimer
@onready var net_session: NetSession = $NetSession
@onready var net_status_label: Label = $NetLayer/NetStatusLabel


func _ready() -> void:
	if save_path == "":
		save_path = SaveGame.default_path()
	($Label as Label).text = I18n.t("ui.title")
	var server: LocalServer = clinic_lobby.local_server
	hud.bind(server, Player.ENTITY_ID)
	skill_bar.bind(server, clinic_lobby.player)
	clinic_lobby.inventory = inventory
	inventory_panel.bind(inventory)
	inventory.equipped_changed.connect(_on_equipped_changed)
	inventory_panel.used.connect(_on_item_used)
	server.level_up.connect(_on_level_up)
	server.money_dropped.connect(_on_money_dropped)
	clinic_lobby.npc_interact_requested.connect(_on_npc_interact_requested)
	dialogue_box.shop_requested.connect(_on_dialogue_shop_requested)
	shop_panel.closed.connect(_on_shop_panel_closed)
	autosave_timer.wait_time = AUTOSAVE_INTERVAL_S
	autosave_timer.timeout.connect(save_game)
	autosave_timer.start()
	if load_on_ready and SaveGame.exists(save_path):
		apply_save(SaveGame.load(save_path))
	net_status_label.visible = false
	var resolved_url: String = _resolve_net_url()
	if resolved_url != "":
		_start_networking(resolved_url)
	print("Hamirpaa boot ok — level %d" % int(server.get_level(Player.ENTITY_ID)))


## `net_url` export wins; else HAMIRPAA_SERVER_URL env var; else a
## `--server=...` cmdline arg; else "" (single-player).
func _resolve_net_url() -> String:
	if net_url != "":
		return net_url
	var env_url: String = OS.get_environment("HAMIRPAA_SERVER_URL")
	if env_url != "":
		return env_url
	for arg: String in OS.get_cmdline_args():
		if arg.begins_with("--server="):
			return arg.substr("--server=".length())
	return ""


func _start_networking(url: String) -> void:
	net_status_label.visible = true
	net_status_label.text = I18n.t("ui.net.connecting")
	net_client = NetClient.new()
	add_child(net_client)
	net_client.disconnected.connect(_on_net_disconnected)
	net_client.error.connect(_on_net_error)
	net_session.ready_to_play.connect(_on_net_ready_to_play)
	net_session.begin(net_client, clinic_lobby.player, clinic_lobby, DEV_TOKEN, DEV_CHARACTER_ID)
	net_client.connect_to(url)


func _on_net_ready_to_play(_player_id: String) -> void:
	net_status_label.visible = false


func _on_net_disconnected(_code: int, _reason: String) -> void:
	net_status_label.visible = true
	net_status_label.text = I18n.t("ui.net.disconnected")


func _on_net_error(data: Dictionary) -> void:
	net_status_label.visible = true
	net_status_label.text = I18n.t(String(data.get("msg_key", "ui.net.error")))


## T-0.15: any open panel blocks attacks/skills (polled; panels have no open/close signals in common).
func _process(_delta: float) -> void:
	clinic_lobby.player.ui_blocked = is_ui_open()


func is_ui_open() -> bool:
	return inventory_panel.is_open() or shop_panel.is_open() or dialogue_box.is_open()


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


## T-0.12: only the player's own kills fund their wallet (LocalServer already
## restricts money_dropped to a registered killer — see its doc comment —
## this just filters out the (currently impossible in Phase 0, but harmless
## to guard) case of some other entity being credited).
func _on_money_dropped(killer_id: String, amount: float) -> void:
	if killer_id == Player.ENTITY_ID:
		inventory.add_money(int(amount))


## T-0.12: an NPC's dialogue lines/order come from RulesBalanceData.NPCS
## (docs/balance/npcs.yaml) — never a literal line here. Builds the ordered
## line-key list from whichever of greet/shop/bye that npc_id actually has
## (only "shop"-role NPCs have all three in Phase 0).
func _on_npc_interact_requested(npc_id: String) -> void:
	var def: Dictionary = RulesBalanceData.NPCS.get("npcs", {}).get(npc_id, {})
	var lines: Dictionary = def.get("lines", {})
	var line_keys: Array[String] = []
	for line_id: String in ["greet", "shop", "bye"]:
		if lines.has(line_id):
			line_keys.append(String(lines[line_id]))
	dialogue_box.show_lines(npc_id, String(def.get("name_key", npc_id)), line_keys)


func _on_dialogue_shop_requested(npc_id: String) -> void:
	shop_panel.bind(inventory, npc_id)
	shop_panel.open()


func _on_shop_panel_closed() -> void:
	dialogue_box.shop_closed()


## T-0.13 save shape: {version, saved_at, player: {archetype, level, total_xp, hp,
## position: [x, y]}, inventory: Inventory.to_dict()}. Numbers come back as floats.
## inventory.to_dict() carries `money` (T-0.12) along with slots/equipped/capacity.
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
