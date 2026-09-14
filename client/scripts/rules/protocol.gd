# GENERATED from packages/shared-rules/src/protocol.ts sha256:2892a11ef27b7657 — DO NOT EDIT (run scripts/gen_rules.py)
class_name RulesProtocol

const MESSAGE_TYPES: Array[String] = ["ping", "pong", "error"]

static func is_known(t: String) -> bool:
	return t in MESSAGE_TYPES
