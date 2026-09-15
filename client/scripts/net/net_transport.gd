class_name NetTransport
extends RefCounted
## T-2.3: NetClient's transport interface, and its default (real) implementation
## — wraps Godot's WebSocketPeer. NetClient never talks to WebSocketPeer
## directly; it only calls the methods below, so client/scripts/net/fake_transport.gd
## can override every one of them with an in-process, latency-simulating fake
## server for GUT tests (see its header) without NetClient knowing the
## difference. "abstract-ish": there is no `abstract` keyword in GDScript —
## this class IS the concrete WebSocket transport; FakeTransport just
## overrides each method.

var _socket: WebSocketPeer = WebSocketPeer.new()


## Starts connecting; non-blocking (poll() drives the handshake forward).
func connect_to(url: String) -> Error:
	return _socket.connect_to_url(url)


## Called every NetClient._process(delta). delta is unused by the real
## WebSocket (FakeTransport uses it to advance its simulated clock).
func poll(_delta: float) -> void:
	_socket.poll()


func is_open() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func is_connecting() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING


func send_text(text: String) -> void:
	_socket.send_text(text)


func has_packet() -> bool:
	return _socket.get_ready_state() == WebSocketPeer.STATE_OPEN and _socket.get_available_packet_count() > 0


func get_packet() -> String:
	return _socket.get_packet().get_string_from_utf8()


func close(code: int = 1000, reason: String = "") -> void:
	_socket.close(code, reason)


## code/reason as GDScript primitives so NetClient never has to know about
## WebSocketPeer — Dictionary is the interface's lingua franca, same shape
## FakeTransport returns.
func get_close_info() -> Dictionary:
	return {"code": _socket.get_close_code(), "reason": _socket.get_close_reason()}
