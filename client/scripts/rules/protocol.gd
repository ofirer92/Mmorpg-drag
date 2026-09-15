# GENERATED from packages/shared-rules/src/protocol.ts sha256:f04b46f55512fe1d — DO NOT EDIT (run scripts/gen_rules.py)
class_name RulesProtocol

const PROTOCOL_VERSION: int = 1

const MESSAGE_TYPES: Array[String] = ["ping", "join", "leave", "input", "loot_pickup", "chat", "pong", "error", "joined", "left", "state", "attack", "damage", "died", "loot", "chat_msg"]

static func is_known(t: String) -> bool:
	return t in MESSAGE_TYPES
