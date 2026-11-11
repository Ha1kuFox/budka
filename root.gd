extends Control


signal exit_requested
signal mic_toggled(enabled: bool)
signal speaker_toggled(enabled: bool)
signal broadcast_toggled(enabled: bool)
signal user_selected(user_id: int)

enum UIMode {
	PANEL,
	MAIN,
}

const COLOR_LIVE: Color = Color(0.207843, 0.517647, 0.894118)
const COLOR_EXIT: Color = Color(1.0, 0.35, 0.35)

@export var demo_users: Array[String] = []
@export var host_user_id: int = 0

@onready var _users_list: UsersGrid = %UsersList
@onready var _content_box: VBoxContainer = _users_list.get_parent() as VBoxContainer
@onready var _selected_preview: PanelContainer = _content_box.get_node("SelectedPreview") as PanelContainer
@onready var _selected_stream: TextureRect = %SelectedStream
@onready var _exit_button: Button = %ExitButton
@onready var _mic_button: Button = %MicButton
@onready var _speaker_button: Button = %SpeakerButton
@onready var _broadcast_button: Button = %BroadcastButton
@onready var _main_menu: Control = $SafeZone/MainMenu
@onready var _room: Control = $SafeZone/Room
@onready var _screen_stream: ScreenStream = $ScreenStream
@onready var _remote_streams: RemoteStreams = $RemoteStreams
@onready var _hover_panel: HoverPanel = $HoverPanel
@onready var _settings_panel: SettingsPanel = $SettingsPanel
@onready var _theme_applier: ThemeApplier = $ThemeApplier
@onready var _speaking_border: Panel = %SpeakingBorder
@onready var _attribution: Label = $Attribution
@onready var _bottom_gradient: ColorRect = %BottomGradient

var _users: Array = []
var _selected_id: int = -1
var _streams: Dictionary = {}
var _accent_style: StyleBoxFlat

var _local_streaming: bool = false
var _local_texture: ImageTexture

var _ui_mode: UIMode = UIMode.PANEL
var _network: Node
var _talking: Dictionary = {}


func _ready() -> void:
	L.info("room: ready")
	_exit_button.modulate = COLOR_EXIT
	_exit_button.pressed.connect(_on_exit_pressed)
	_mic_button.toggled.connect(_on_mic_toggled)
	_speaker_button.toggled.connect(_on_speaker_toggled)
	_broadcast_button.toggled.connect(_on_broadcast_toggled)

	_speaker_button.set_pressed_no_signal(true)
	_apply_speaker_volume(true)

	_accent_style = StyleBoxFlat.new()
	_accent_style.bg_color = Color(COLOR_LIVE.r, COLOR_LIVE.g, COLOR_LIVE.b, 0.12)
	_accent_style.set_border_width_all(0)
	_accent_style.set_corner_radius_all(12)

	_selected_stream.mouse_filter = Control.MOUSE_FILTER_STOP
	_selected_stream.gui_input.connect(_on_stream_input)

	var voice: Node = get_node_or_null("/root/VoiceChat")
	if voice != null and voice.has_signal("error"):
		voice.error.connect(_on_voice_error)
	if voice != null and voice.has_signal("peer_talking"):
		voice.peer_talking.connect(_on_peer_talking)

	_screen_stream.frame_ready.connect(_on_screen_frame)
	_screen_stream.failed.connect(_on_screen_failed)
	_screen_stream.access_unit_ready.connect(_on_local_access_unit)

	_users_list.user_picked.connect(_on_user_picked)
	_remote_streams.texture_ready.connect(_on_remote_texture_ready)
	_remote_streams.stream_removed.connect(_on_remote_texture_removed)
	_remote_streams.stream_failed.connect(_on_remote_stream_failed)

	_hover_panel.setup(_users_list, _content_box, _users_list)
	_settings_panel.mode_selected.connect(_on_ui_mode_selected)
	_settings_panel.theme_selected.connect(_on_theme_selected)
	_settings_panel.set_mode(UIMode.PANEL)
	_settings_panel.set_theme_mode(int(_theme_applier.mode))

	_setup_network()

	if _network == null:
		_apply_demo_users()
	else:
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


func set_ui_mode(mode: UIMode) -> void:
	if mode == _ui_mode:
		return
	L.info("room: ui mode=%d" % mode)
	_ui_mode = mode
	_settings_panel.set_mode(mode)
	_settings_panel.close()
	_refresh_view()


func _setup_network() -> void:
	_network = get_node_or_null("/root/NetworkManager")

	var connect_button: Button = $SafeZone/MainMenu/Buttons/ConnectionRow/ConnectButton
	var host_button: Button = $SafeZone/MainMenu/Buttons/HostButton
	var uid_input: LineEdit = $SafeZone/MainMenu/Buttons/ConnectionRow/UIDInput

	if _network != null:
		_network.joined.connect(_on_network_joined)
		_network.left.connect(_on_network_left)
		_network.users_changed.connect(_on_network_users)
		_network.stream_access_unit.connect(_on_network_stream)
		_network.error.connect(_on_network_error)
		connect_button.pressed.connect(func() -> void: _network.join(uid_input.text))
		host_button.pressed.connect(func() -> void: _network.host())
	else:
		connect_button.pressed.connect(_show_room)
		host_button.pressed.connect(_show_room)

	if _network != null and _network.connected:
		_show_room()
	else:
		_show_main_menu()


func _on_network_joined() -> void:
	L.info("room: joined local_id=%d" % _network.local_id)
	host_user_id = _network.local_id
	_show_room()


func _on_network_left() -> void:
	L.info("room: left")
	_stop_streaming()
	_remote_streams.clear()
	_selected_id = -1
	_settings_panel.close()
	set_users([])
	_show_main_menu()


func _on_network_users(users: Array) -> void:
	L.info("room: network users=%d" % users.size())
	_remote_streams.prune(users)
	set_users(users)


func _on_network_stream(user_id: int, data: PackedByteArray, keyframe: bool) -> void:
	if user_id == host_user_id:
		return
	_remote_streams.push_unit(user_id, data, keyframe)


func _on_peer_talking(peer_id: int, talking: bool) -> void:
	_talking[peer_id] = talking
	_users_list.set_talking(peer_id, talking)
	L.debug("room: talking user=%d state=%s" % [peer_id, talking])
	_update_speaking_border()


func _on_voice_error(message: String) -> void:
	L.warn("voice: %s" % message)


func _on_network_error(message: String) -> void:
	push_warning("Network: %s" % message)


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


func _on_stream_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			clear_selection()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _settings_panel.is_open():
			_settings_panel.close()
			get_viewport().set_input_as_handled()
		elif _selected_id != -1:
			clear_selection()
			get_viewport().set_input_as_handled()


func _on_ui_mode_selected(mode: int) -> void:
	set_ui_mode(mode as UIMode)


func _on_theme_selected(mode: int) -> void:
	L.info("room: theme=%d" % mode)
	_theme_applier.mode = mode as ThemeApplier.Mode
	_settings_panel.set_theme_mode(mode)


func _on_user_picked(user_id: int) -> void:
	L.info("room: tile picked user=%d" % user_id)
	if user_id == _selected_id:
		clear_selection()
	else:
		_selected_id = user_id
		user_selected.emit(user_id)
		_refresh_view()
	_hover_panel.hide_panel()


func _on_exit_pressed() -> void:
	L.info("room: exit")
	exit_requested.emit()
	if _network != null:
		_network.leave()
	else:
		_stop_streaming()
		_show_main_menu()


func _on_mic_toggled(enabled: bool) -> void:
	L.info("room: mic=%s" % enabled)
	mic_toggled.emit(enabled)
	if enabled and (_network == null or not _network.connected):
		_mic_button.set_pressed_no_signal(false)
		return
	var voice: Node = get_node_or_null("/root/VoiceChat")
	if voice != null and voice.has_method("set_mic_enabled"):
		voice.set_mic_enabled(enabled)


func _on_speaker_toggled(enabled: bool) -> void:
	L.info("room: speaker=%s" % enabled)
	speaker_toggled.emit(enabled)
	_apply_speaker_volume(enabled)


func _apply_speaker_volume(enabled: bool) -> void:
	var voice: Node = get_node_or_null("/root/VoiceChat")
	if voice != null and voice.has_method("set_output_volume"):
		voice.set_output_volume(0.0 if enabled else -40.0)


func _on_broadcast_toggled(enabled: bool) -> void:
	L.info("room: broadcast=%s" % enabled)
	broadcast_toggled.emit(enabled)
	if enabled:
		var error: Error = _screen_stream.start_sharing()
		if error != OK:
			_broadcast_button.set_pressed_no_signal(false)
			return
		_local_streaming = true
		_set_host_streaming(true)
		L.info("room: sharing %s @ %d fps" % [_screen_stream.stream_size, _screen_stream.fps])
		_users_list.set_users(_users)
		if _network != null:
			_network.set_streaming(true)
	else:
		_stop_streaming()
	_refresh_view()


func _stop_streaming() -> void:
	if _local_streaming:
		L.info("room: stop sharing")
	_screen_stream.stop_sharing()
	_local_streaming = false
	_local_texture = null
	_users_list.clear_texture(host_user_id)
	_set_host_streaming(false)
	_users_list.set_users(_users)
	if _network != null:
		_network.set_streaming(false)
	if _broadcast_button.button_pressed:
		_broadcast_button.set_pressed_no_signal(false)


func _on_screen_frame(image: Image) -> void:
	var first: bool = _local_texture == null
	if first:
		L.info("room: local first frame %s" % image.get_size())
	if first or _local_texture.get_size() != Vector2(image.get_size()):
		_local_texture = ImageTexture.create_from_image(image)
	else:
		_local_texture.update(image)

	_users_list.set_texture(host_user_id, _local_texture)
	if _selected_id == host_user_id:
		_selected_stream.texture = _local_texture
		if first:
			_refresh_view()


func _on_screen_failed(message: String) -> void:
	L.error("room: screen stream: %s" % message)
	push_error("screen stream: %s" % message)
	_stop_streaming()
	_refresh_view()


func _on_local_access_unit(data: PackedByteArray, keyframe: bool) -> void:
	if _network != null:
		_network.send_stream(data, keyframe)


func _apply_demo_users() -> void:
	var users: Array = []
	for i: int in demo_users.size():
		users.append({"id": i, "name": demo_users[i], "streaming": i > 0})
	set_users(users)


func _refresh_view() -> void:
	var texture: Texture2D = _texture_for(_selected_id) if _selected_id != -1 else null
	var show_stream: bool = texture != null
	var overlay_mode: bool = _ui_mode == UIMode.MAIN and show_stream

	_users_list.set_watching(show_stream)
	_users_list.set_overlay_mode(overlay_mode)
	_hover_panel.set_active(overlay_mode)
	_users_list.visible = not _users.is_empty()
	_selected_preview.visible = show_stream
	_bottom_gradient.visible = show_stream
	_users_list.size_flags_vertical = 0 if show_stream and not overlay_mode else (3 if not show_stream else 0)
	_selected_stream.texture = texture

	if show_stream:
		_selected_preview.add_theme_stylebox_override("panel", _accent_style)
	else:
		_selected_preview.remove_theme_stylebox_override("panel")

	_update_speaking_border()


func _update_speaking_border() -> void:
	var talking: bool = _selected_id != -1 and _selected_preview.visible and bool(_talking.get(_selected_id, false))
	_speaking_border.call("set_speaking", talking)


func _show_room() -> void:
	L.info("room: enter room")
	_main_menu.visible = false
	_attribution.visible = false
	_room.visible = true
	_refresh_view()


func _show_main_menu() -> void:
	L.info("room: show main menu")
	_room.visible = false
	_main_menu.visible = true
	_attribution.visible = true


func _texture_for(user_id: int) -> Texture2D:
	if _streams.has(user_id):
		return _streams[user_id] as Texture2D
	if _local_streaming and user_id == host_user_id:
		return _local_texture
	return _remote_streams.get_texture(user_id)


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
	if user_id == host_user_id and _local_streaming:
		return true
	var user: Dictionary = _get_user(user_id)
	return not user.is_empty() and bool(user.get("streaming", false))


func _get_user(user_id: int) -> Dictionary:
	for user: Dictionary in _users:
		if int(user.get("id", -1)) == user_id:
			return user
	return {}
