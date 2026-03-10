@tool
extends RefCounted
class_name AgentCommandServer

signal status_changed(is_running: bool, bind_address: String, port: int)
signal message_logged(text: String)
signal command_processed(command: String, response: Dictionary)

var bind_address: String = "127.0.0.1"
var port: int = 47891
var auth_token: String = ""
var command_handler: Callable = Callable()

var _server: TCPServer = TCPServer.new()
var _clients: Dictionary = {}
var _next_client_id: int = 1

func is_running() -> bool:
	return _server != null and _server.is_listening()

func start() -> int:
	if is_running():
		emit_signal("message_logged", "Server already running at %s:%d." % [bind_address, port])
		emit_signal("status_changed", true, bind_address, port)
		return OK

	_server = TCPServer.new()
	var err: int = _server.listen(port, bind_address)
	if err != OK:
		emit_signal("message_logged", "Failed to start server on %s:%d (%s)." % [bind_address, port, error_string(err)])
		emit_signal("status_changed", false, bind_address, port)
		return err

	emit_signal("message_logged", "Server listening on %s:%d." % [bind_address, port])
	emit_signal("status_changed", true, bind_address, port)
	return OK

func stop() -> void:
	if not is_running():
		return

	for client_id in _clients.keys():
		_close_client(int(client_id))
	_clients.clear()

	_server.stop()
	emit_signal("message_logged", "Server stopped.")
	emit_signal("status_changed", false, bind_address, port)

func process() -> void:
	if not is_running():
		return

	while _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		if peer == null:
			break
		var client_id: int = _next_client_id
		_next_client_id += 1
		_clients[client_id] = {"peer": peer, "buffer": ""}
		emit_signal("message_logged", "Client %d connected." % client_id)

	var disconnected_clients: Array[int] = []
	for client_key in _clients.keys().duplicate():
		var client_id: int = int(client_key)
		var client_info: Dictionary = _clients.get(client_id, {})
		var peer: StreamPeerTCP = client_info.get("peer")
		if peer == null:
			disconnected_clients.append(client_id)
			continue

		peer.poll()
		var status: int = peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			var available_bytes: int = peer.get_available_bytes()
			if available_bytes > 0:
				var chunk: String = peer.get_utf8_string(available_bytes)
				client_info["buffer"] = str(client_info.get("buffer", "")) + chunk
				_clients[client_id] = client_info
				_drain_client_buffer(client_id)
		else:
			disconnected_clients.append(client_id)

	for client_id in disconnected_clients:
		_close_client(client_id)

func _drain_client_buffer(client_id: int) -> void:
	if not _clients.has(client_id):
		return

	var client_info: Dictionary = _clients.get(client_id, {})
	var buffer: String = str(client_info.get("buffer", ""))
	while true:
		var newline_index: int = buffer.find("\n")
		if newline_index == -1:
			break

		var raw_line: String = buffer.substr(0, newline_index)
		buffer = buffer.substr(newline_index + 1)
		var line: String = raw_line.strip_edges()
		if line.is_empty():
			continue
		_handle_line(client_id, line)

	client_info["buffer"] = buffer
	_clients[client_id] = client_info

func _handle_line(client_id: int, line: String) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		_send_response(client_id, _error_response("invalid_json", "Expected a JSON object request."))
		return

	var request: Dictionary = parsed
	var request_id: Variant = request.get("id", null)
	var token: String = str(request.get("token", ""))
	if not auth_token.is_empty() and token != auth_token:
		var unauthorized: Dictionary = _error_response("unauthorized", "Missing or invalid auth token.")
		if request_id != null:
			unauthorized["id"] = request_id
		_send_response(client_id, unauthorized)
		return

	var command: String = str(request.get("command", "")).strip_edges()
	if command.is_empty():
		var empty_command: Dictionary = _error_response("missing_command", "Request must include a command.")
		if request_id != null:
			empty_command["id"] = request_id
		_send_response(client_id, empty_command)
		return

	var args: Dictionary = {}
	if typeof(request.get("args", {})) == TYPE_DICTIONARY:
		args = request.get("args", {})

	var response: Dictionary
	if command_handler.is_valid():
		var raw_response: Variant = command_handler.call(command, args)
		if typeof(raw_response) == TYPE_DICTIONARY:
			response = raw_response
		else:
			response = {
				"ok": true,
				"result": raw_response,
			}
	else:
		response = _error_response("no_handler", "Command handler is not configured.")

	response = _sanitize_dictionary(response)
	response["command"] = command
	if request_id != null:
		response["id"] = _sanitize_variant(request_id)

	emit_signal("command_processed", command, response)
	_send_response(client_id, response)

func _send_response(client_id: int, response: Dictionary) -> void:
	if not _clients.has(client_id):
		return
	var client_info: Dictionary = _clients.get(client_id, {})
	var peer: StreamPeerTCP = client_info.get("peer")
	if peer == null:
		return

	var payload: String = JSON.stringify(_sanitize_dictionary(response)) + "\n"
	var err: int = peer.put_data(payload.to_utf8_buffer())
	if err != OK:
		emit_signal("message_logged", "Failed to send response to client %d (%s)." % [client_id, error_string(err)])

func _close_client(client_id: int) -> void:
	if not _clients.has(client_id):
		return
	var client_info: Dictionary = _clients.get(client_id, {})
	var peer: StreamPeerTCP = client_info.get("peer")
	if peer != null:
		peer.disconnect_from_host()
	_clients.erase(client_id)
	emit_signal("message_logged", "Client %d disconnected." % client_id)

func _error_response(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": {
			"code": code,
			"message": message,
		},
	}

func _sanitize_dictionary(value: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	for key in value.keys():
		output[str(key)] = _sanitize_variant(value[key])
	return output

func _sanitize_variant(value: Variant) -> Variant:
	var value_type: int = typeof(value)
	match value_type:
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_ARRAY:
			var output_array: Array = []
			for item in value:
				output_array.append(_sanitize_variant(item))
			return output_array
		TYPE_DICTIONARY:
			return _sanitize_dictionary(value)
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_COLOR:
			return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
		_:
			return str(value)
