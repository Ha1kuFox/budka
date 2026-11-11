extends VBoxContainer


signal user_selected(user_id: int)

const COLOR_LIVE: Color = Color(0.207843, 0.517647, 0.894118)

@export var host_user_id: int = 0
@export var remote_streams: RemoteStreams
@export var hover_panel: HoverPanel
@export var broadcaster: StreamBroadcaster

@onready var _users_list: UsersGrid = %UsersList
@onready var _selected_preview: PanelContainer = $Content/ContentBox/SelectedPreview
@onready var _selected_stream: TextureRect = %SelectedStream
@onready var _speaking_border: Panel = %SpeakingBorder
@onready var _bottom_gradient: ColorRect = %BottomGradient

var _users: Array = []
var _selected_id: int = -1
var _streams: Dictionary = {}
var _accent_style: StyleBoxFlat
var _talking: Dictionary = {}


func _ready() -> void:
	_accent_style = StyleBoxFlat.new()
	_accent_style.bg_color = Color(COLOR_LIVE.r, COLOR_LIVE.g, COLOR_LIVE.b, 0.12)
	_accent_style.set_border_width_all(0)
	_accent_style.set_corner_radius_all(12)

	_selected_stream.mouse_filter = Control.MOUSE_FILTER_STOP
	_selected_stream.gui_input.connect(_on_stream_input)
	_users_list.user_picked.connect(_on_user_picked)

	remote_streams.texture_ready.connect(_on_remote_texture_ready)
	remote_streams.stream_removed.connect(_on_remote_texture_removed)
	remote_streams.stream_failed.connect(_on_remote_stream_failed)

	broadcaster.texture_changed.connect(_on_broadcaster_texture)
	broadcaster.sharing_changed.connect(_on_broadcaster_sharing)

	NetworkManager.joined.connect(_on_network_joined)
	NetworkManager.left.connect(_on_network_left)
	NetworkManager.users_changed.connect(_on_network_users)
	NetworkManager.stream_access_unit.connect(_on_network_stream)
	NetworkManager.error.connect(_on_network_error)
	VoiceChat.peer_talking.connect(_on_peer_talking)

	set_users([])


func set_users(users: Array) -> void:
	L.debug("room: users=%d" % users.size())
	_users = users.slice(0, UsersGrid.MAX_USERS).duplicate(true)
	if not _has_user(_selected_id) or not _is_streaming(_selected_id):
		_selected_id = -1
	_users_list.set_users(_users)
	_refresh_view()


func select_user(user_id: int) -> void:
	L.info("room: select user=%d" % user_id)
	if user_id == _selected_id or not _has_user(user_id):
		return
	_selected_id = user_id
	user_selected.emit(user_id)
	_refresh_view()


func clear_selection() -> void:
	if _selected_id == -1:
		return
	L.info("room: clear selection")
	_selected_id = -1
	user_selected.emit(-1)
	_refresh_view()


func set_stream(user_id: int, texture: Texture2D) -> void:
	if texture == null:
		_streams.erase(user_id)
		_users_list.clear_texture(user_id)
	else:
		_streams[user_id] = texture
		_users_list.set_texture(user_id, texture)
	if user_id == _selected_id:
		_refresh_view()


func set_streaming(user_id: int, streaming: bool) -> void:
	for user: Dictionary in _users:
		if int(user.get("id", -1)) == user_id:
			user["streaming"] = streaming
			break
	if user_id == _selected_id and not streaming:
		_selected_id = -1
		user_selected.emit(-1)
	_users_list.set_users(_users)
	_refresh_view()


func get_selected_user() -> Dictionary:
	return _get_user(_selected_id)


func _on_network_joined() -> void:
	L.info("room: joined local_id=%d" % NetworkManager.local_id)
	host_user_id = NetworkManager.local_id


func _on_network_left() -> void:
	L.info("room: left")
	remote_streams.clear()
	_selected_id = -1
	set_users([])


func _on_network_users(users: Array) -> void:
	L.info("room: network users=%d" % users.size())
	remote_streams.prune(users)
	set_users(users)


func _on_network_stream(user_id: int, data: PackedByteArray, keyframe: bool) -> void:
	if user_id == host_user_id:
		return
	remote_streams.push_unit(user_id, data, keyframe)


func _on_network_error(message: String) -> void:
	push_warning("Network: %s" % message)


func _on_peer_talking(peer_id: int, talking: bool) -> void:
	_talking[peer_id] = talking
	_users_list.set_talking(peer_id, talking)
	_update_speaking_border()


func _on_remote_texture_ready(user_id: int, texture: Texture2D) -> void:
	L.info("room: remote texture user=%d" % user_id)
	_users_list.set_texture(user_id, texture)
	if user_id == _selected_id:
		_refresh_view()


func _on_remote_texture_removed(user_id: int) -> void:
	_users_list.clear_texture(user_id)
	if user_id == _selected_id:
		_refresh_view()


func _on_remote_stream_failed(user_id: int, message: String) -> void:
	push_warning("Remote stream %d failed: %s" % [user_id, message])


func _on_broadcaster_texture(texture: Texture2D) -> void:
	_users_list.set_texture(host_user_id, texture)
	if _selected_id == host_user_id:
		_refresh_view()


func _on_broadcaster_sharing(active: bool) -> void:
	_set_host_streaming(active)
	_users_list.set_users(_users)
	_refresh_view()


func _on_stream_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			clear_selection()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _selected_id != -1:
		clear_selection()
		get_viewport().set_input_as_handled()


func _on_user_picked(user_id: int) -> void:
	L.info("room: tile picked user=%d" % user_id)
	if user_id == _selected_id:
		clear_selection()
	else:
		_selected_id = user_id
		user_selected.emit(user_id)
		_refresh_view()
	hover_panel.hide_panel()


func _refresh_view() -> void:
	var texture: Texture2D = _texture_for(_selected_id) if _selected_id != -1 else null
	var show_stream: bool = texture != null
	var overlay_mode: bool = show_stream

	_users_list.set_watching(show_stream)
	_users_list.set_overlay_mode(overlay_mode)
	hover_panel.set_active(overlay_mode)
	_users_list.visible = not _users.is_empty()
	_selected_preview.visible = show_stream
	_bottom_gradient.visible = show_stream
	_selected_stream.texture = texture

	if show_stream:
		_selected_preview.add_theme_stylebox_override("panel", _accent_style)
	else:
		_selected_preview.remove_theme_stylebox_override("panel")

	_update_speaking_border()


func _update_speaking_border() -> void:
	var talking: bool = _selected_id != -1 and _selected_preview.visible and bool(_talking.get(_selected_id, false))
	_speaking_border.call("set_speaking", talking)


func _texture_for(user_id: int) -> Texture2D:
	if _streams.has(user_id):
		return _streams[user_id] as Texture2D
	if user_id == host_user_id and broadcaster.is_active():
		return broadcaster.get_texture()
	return remote_streams.get_texture(user_id)


func _set_host_streaming(value: bool) -> void:
	for user: Dictionary in _users:
		if int(user.get("id", -1)) == host_user_id:
			user["streaming"] = value
			return


func _has_user(user_id: int) -> bool:
	if user_id < 0:
		return false
	for user: Dictionary in _users:
		if int(user.get("id", -1)) == user_id:
			return true
	return false


func _is_streaming(user_id: int) -> bool:
	if user_id == host_user_id and broadcaster.is_active():
		return true
	var user: Dictionary = _get_user(user_id)
	return not user.is_empty() and bool(user.get("streaming", false))


func _get_user(user_id: int) -> Dictionary:
	for user: Dictionary in _users:
		if int(user.get("id", -1)) == user_id:
			return user
	return {}
