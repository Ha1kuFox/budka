extends Node


signal joined
signal left
signal users_changed(users: Array)
signal stream_access_unit(user_id: int, data: PackedByteArray, keyframe: bool)
signal error(message: String)

const STREAM_CHUNK_SIZE: int = 12 * 1024
const LOCAL: bool = false

@export var use_steam: bool = not LOCAL

var connected: bool = false
var local_id: int = 0

var _con: Node
var _users: Array = []
var _names: Dictionary = {}
var _streaming: Dictionary = {}
var _pending_join_address: String = ""
var _stream_seq: int = 0
var _rx_streams: Dictionary = {}


func _ready() -> void:
	L.info("net: NetworkManager ready")
	_con = get_node("/root/Con")

	_con.hosted.connect(_on_hosted)
	_con.host_failed.connect(_on_host_failed)
	_con.connected.connect(_on_connected)
	_con.connection_failed.connect(_on_connection_failed)
	_con.connection_timed_out.connect(_on_connection_failed)
	_con.disconnected.connect(_on_disconnected)
	_con.client_joined.connect(_on_client_joined)
	_con.client_left.connect(_on_client_left)
	_con.steam_unavailable.connect(_on_error)


func host() -> void:
	L.info("net: host requested")
	if connected:
		return
	_configure_transport()
	_con.set("MAX_CLIENTS", 6)
	L.info("net: transport=%s" % ("steam" if int(_con.get("connection_method")) == 1 else "enet"))
	var result: Error = _con.host()
	if result != OK:
		error.emit("Could not host: %s" % error_string(result))


func join(address: String) -> void:
	L.info("net: join requested: %s" % address)
	if connected:
		return
	_pending_join_address = address.strip_edges()
	if _pending_join_address.is_empty():
		error.emit("Enter a Steam ID or an IP address")
		return
	_configure_transport()
	var result: Error = _con.connect_to(_pending_join_address)
	if result != OK:
		error.emit("Could not connect: %s" % error_string(result))


func get_room_code() -> String:
	var steam_id: int = int(_con.call("get_steam_id"))
	if steam_id > 0:
		return str(steam_id)
	return str(local_id)


func is_host() -> bool:
	return connected and multiplayer.is_server()


func is_client() -> bool:
	return connected and not multiplayer.is_server()


func leave() -> void:
	L.info("net: leave requested")
	if _con != null and _con.is_active():
		_con.stop()
	_close()


func send_stream(data: PackedByteArray, keyframe: bool) -> void:
	if not connected or data.is_empty():
		return

	_stream_seq += 1
	var total: int = maxi(1, ceili(float(data.size()) / float(STREAM_CHUNK_SIZE)))
	for index: int in range(total):
		var start: int = index * STREAM_CHUNK_SIZE
		var chunk: PackedByteArray = data.slice(start, mini(start + STREAM_CHUNK_SIZE, data.size()))
		if multiplayer.is_server():
			rpc("_rpc_stream_chunk", _stream_seq, index, total, keyframe, chunk)
		else:
			rpc_id(1, "_rpc_stream_chunk", _stream_seq, index, total, keyframe, chunk)


func set_streaming(streaming: bool) -> void:
	L.info("net: local streaming=%s" % streaming)
	if not connected:
		return
	if _streaming.has(local_id) == streaming:
		return
	if streaming:
		_streaming[local_id] = true
	else:
		_streaming.erase(local_id)

	if multiplayer.is_server():
		_rebuild_users()
	else:
		rpc_id(1, "_rpc_stream_state", streaming)


func _configure_transport() -> void:
	var steam_ok: bool = use_steam and bool(_con.call("is_steam_available"))
	_con.set("connection_method", 1 if steam_ok else 0)


func _on_hosted(_port: int) -> void:
	L.info("net: hosted, local_id=%d" % multiplayer.get_unique_id())
	connected = true
	local_id = multiplayer.get_unique_id()
	_names.clear()
	_streaming.clear()
	_names[local_id] = _local_name()
	_rebuild_users()
	joined.emit()


func _on_connected() -> void:
	L.info("net: connected, local_id=%d" % multiplayer.get_unique_id())
	connected = true
	local_id = multiplayer.get_unique_id()
	joined.emit()
	rpc_id(1, "_rpc_register", _local_name())


func _on_host_failed(result: Error) -> void:
	L.error("net: hosting failed: %s" % error_string(result))
	error.emit("Hosting failed: %s" % error_string(result))


func _on_connection_failed() -> void:
	L.warn("net: connection failed")
	error.emit("Connection failed")
	_close()


func _on_disconnected() -> void:
	L.warn("net: disconnected")
	_close()


func _on_client_joined(peer_id: int) -> void:
	L.info("net: client joined: %d" % peer_id)
	if not multiplayer.is_server():
		return
	_names[peer_id] = "Player %d" % peer_id
	_rebuild_users()


func _on_client_left(peer_id: int) -> void:
	L.info("net: client left: %d" % peer_id)
	if not multiplayer.is_server():
		return
	_names.erase(peer_id)
	_streaming.erase(peer_id)
	_rebuild_users()


func _on_error(reason: String) -> void:
	L.error("net: %s" % reason)
	error.emit(reason)


func _rebuild_users() -> void:
	if not multiplayer.is_server():
		return

	var ids: Array[int] = [multiplayer.get_unique_id()]
	for peer_id: int in multiplayer.get_peers():
		ids.append(peer_id)

	var users: Array = []
	for user_id: int in ids:
		users.append({
			"id": user_id,
			"name": _name_for(user_id),
			"streaming": _streaming.has(user_id),
		})

	_users = users
	L.info("net: users: %d" % users.size())
	users_changed.emit(users)
	rpc("_rpc_users", users)


func _name_for(user_id: int) -> String:
	if _names.has(user_id):
		return str(_names[user_id])

	var result: String = "Player %d" % user_id
	if _steam_available():
		var steam: Object = Engine.get_singleton("Steam")
		var value: String = str(steam.call("getFriendPersonaName", user_id))
		if not value.is_empty():
			result = value
	_names[user_id] = result
	return result


func _local_name() -> String:
	if _steam_available():
		var steam: Object = Engine.get_singleton("Steam")
		var value: String = str(steam.call("getPersonaName"))
		if not value.is_empty():
			return value
	return "Player"


func _steam_available() -> bool:
	if not Engine.has_singleton("Steam"):
		return false
	var steam: Object = Engine.get_singleton("Steam")
	var result: Dictionary = steam.call("get_steam_init_result")
	if result.is_empty() or int(result.get("status", 1)) != 0:
		return false
	return bool(steam.call("loggedOn"))


func _close() -> void:
	if not connected and _users.is_empty():
		return
	connected = false
	local_id = 0
	L.info("net: closed")
	_users.clear()
	_names.clear()
	_streaming.clear()
	_rx_streams.clear()
	users_changed.emit([])
	left.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_register(nickname: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_names[sender] = nickname.strip_edges()
	L.debug("net: registered %d as %s" % [sender, _names[sender]])
	if _names[sender].is_empty():
		_names[sender] = "Player %d" % sender
	_rebuild_users()


@rpc("authority", "call_remote", "reliable")
func _rpc_users(users: Array) -> void:
	_users = users
	users_changed.emit(users)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_stream_state(streaming: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	if streaming:
		_streaming[sender] = true
	else:
		_streaming.erase(sender)
	L.info("net: remote streaming: %d=%s" % [sender, streaming])
	_rebuild_users()


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_stream_chunk(seq: int, index: int, total: int, keyframe: bool, chunk: PackedByteArray) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if index == 0 and keyframe:
		L.debug("net: keyframe from %d seq=%d total=%d" % [sender, seq, total])
	var data: Variant = _assemble_stream(sender, seq, index, total, keyframe, chunk)
	if data is PackedByteArray:
		stream_access_unit.emit(sender, data, keyframe)

	if multiplayer.is_server():
		for peer_id: int in multiplayer.get_peers():
			if peer_id != sender:
				rpc_id(peer_id, "_rpc_stream_chunk_relay", sender, seq, index, total, keyframe, chunk)


@rpc("authority", "call_remote", "unreliable")
func _rpc_stream_chunk_relay(sender: int, seq: int, index: int, total: int, keyframe: bool, chunk: PackedByteArray) -> void:
	var data: Variant = _assemble_stream(sender, seq, index, total, keyframe, chunk)
	if data is PackedByteArray:
		stream_access_unit.emit(sender, data, keyframe)


func _assemble_stream(sender: int, seq: int, index: int, total: int, keyframe: bool, chunk: PackedByteArray) -> Variant:
	if sender == 0 or sender == local_id or total <= 0 or index < 0 or index >= total or chunk.is_empty():
		return null

	var entry: Dictionary = _rx_streams.get(sender, {})
	if entry.is_empty() or int(entry.get("seq", -1)) != seq:
		if index != 0:
			return null
		var _parts: Array = []
		_parts.resize(total)
		entry = {"seq": seq, "total": total, "parts": _parts, "received": 0, "keyframe": keyframe}
		_rx_streams[sender] = entry

	if int(entry.get("total", 0)) != total:
		return null

	var parts: Array = entry["parts"]
	if parts[index] != null:
		return null
	parts[index] = chunk
	entry["received"] = int(entry.get("received", 0)) + 1

	if int(entry["received"]) < total:
		return null

	var data: PackedByteArray = PackedByteArray()
	for part: PackedByteArray in parts:
		data.append_array(part)
	_rx_streams.erase(sender)
	return data
