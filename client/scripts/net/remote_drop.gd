class_name RemoteDrop
extends Area2D
## T-2.4: server-driven view of one `DropState` entry (docs/protocol.md).
## Visually identical to client/scripts/monsters/drop.gd but NEVER grants the
## item itself — on overlap it sends a `loot_pickup {drop_id}` intent and
## waits; the bag only changes once client/scripts/combat/remote_authority.gd
## sees the matching `loot {added: true}` fact (CLAUDE.md: the client never
## decides what it picked up). Removed by RemoteAuthority when the drop id
## disappears from a later `state.drops` (picked up or expired) — this node
## never queue_frees itself on overlap the way the single-player Drop does.

var drop_id: String = ""
var item_id: String = ""
var net_client: NetClient = null

## True once this drop has sent its one loot_pickup intent — protocol.md's
## `loot_pickup` is rate-limited (5/s burst 10) and pickup is a single
## human-paced action, so we never spam it every physics frame the player
## stays overlapping.
var _requested: bool = false


func setup(id: String, item: String, client: NetClient) -> void:
	drop_id = id
	item_id = item
	net_client = client


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _requested or net_client == null:
		return
	if not (body is Player):
		return
	_requested = true
	net_client.send({"t": "loot_pickup", "drop_id": drop_id})
