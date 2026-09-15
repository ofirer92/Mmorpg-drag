extends GutTest
## T-2.3: NetClient (client/scripts/net/net_client.gd) parses/routes protocol
## v1 JSON over an injected transport. Most tests use a minimal in-file
## StubTransport for exact control over what bytes arrive; test_net_session.gd
## covers the fuller FakeTransport (client/scripts/net/fake_transport.gd)
## end-to-end flow.

## A transport double that never actually simulates a server — tests decide
## exactly what bytes NetClient sees by pushing onto `queue`.
class StubTransport extends NetTransport:
	var opened: bool = false
	var queue: Array[String] = []
	var sent: Array[String] = []
	var closed_info: Dictionary = {"code": 0, "reason": ""}

	func connect_to(_url: String) -> Error:
		opened = true
		return OK

	func poll(_delta: float) -> void:
		pass

	func is_open() -> bool:
		return opened

	func is_connecting() -> bool:
		return false

	func send_text(text: String) -> void:
		sent.append(text)

	func has_packet() -> bool:
		return not queue.is_empty()

	func get_packet() -> String:
		return queue.pop_front()

	func close(_code: int = 1000, _reason: String = "") -> void:
		opened = false

	func get_close_info() -> Dictionary:
		return closed_info


func _client() -> NetClient:
	return add_child_autofree(NetClient.new())


func test_connected_signal_fires_once_transport_opens() -> void:
	var transport: StubTransport = StubTransport.new()
	var c: NetClient = _client()
	c.set_transport(transport)
	watch_signals(c)
	c.connect_to("fake://x")
	simulate(c, 1, 0.016)
	assert_signal_emitted(c, "connected")


func test_join_sends_protocol_version_token_and_character() -> void:
	var transport: FakeTransport = FakeTransport.new()
	var c: NetClient = _client()
	c.set_transport(transport)
	c.connect_to("fake://x")
	c.join("tok123", "char_1")
	assert_eq(transport.received_log.size(), 1)
	var msg: Dictionary = transport.received_log[0]
	assert_eq(String(msg.t), "join")
	assert_eq(int(msg.protocol), RulesProtocol.PROTOCOL_VERSION)
	assert_eq(String(msg.token), "tok123")
	assert_eq(String(msg.character_id), "char_1")


func test_joined_and_state_messages_are_parsed_and_routed() -> void:
	var transport: FakeTransport = FakeTransport.new()
	var c: NetClient = _client()
	c.set_transport(transport)
	watch_signals(c)
	c.connect_to("fake://x")
	c.join("tok", "char_1")
	# One tick is enough for FakeTransport (0 latency here) to answer
	# `joined`, and a couple more ticks to also emit at least one `state`.
	simulate(c, 5, 0.05)
	assert_signal_emitted(c, "joined")
	assert_signal_emitted(c, "state")
	assert_signal_emitted(c, "message")


func test_unknown_message_type_is_dropped() -> void:
	var transport: StubTransport = StubTransport.new()
	var c: NetClient = _client()
	c.set_transport(transport)
	c.connect_to("fake://x")
	transport.queue.append(JSON.stringify({"t": "totally_unknown", "x": 1}))
	watch_signals(c)
	simulate(c, 1, 0.016)
	assert_signal_not_emitted(c, "message")


func test_error_message_is_routed_to_error_signal() -> void:
	var transport: StubTransport = StubTransport.new()
	var c: NetClient = _client()
	c.set_transport(transport)
	c.connect_to("fake://x")
	transport.queue.append(JSON.stringify({"t": "error", "code": "rate_limited", "msg_key": "error.rate_limited"}))
	watch_signals(c)
	simulate(c, 1, 0.016)
	assert_signal_emitted(c, "error")
	var params: Array = get_signal_parameters(c, "error")
	assert_eq(String((params[0] as Dictionary).code), "rate_limited")


func test_disconnect_emits_disconnected_signal_with_close_info() -> void:
	var transport: StubTransport = StubTransport.new()
	transport.closed_info = {"code": 1000, "reason": "bye"}
	var c: NetClient = _client()
	c.set_transport(transport)
	c.connect_to("fake://x")
	simulate(c, 1, 0.016)

	watch_signals(c)
	c.disconnect_from()
	simulate(c, 1, 0.016)

	assert_signal_emitted_with_parameters(c, "disconnected", [1000, "bye"])
