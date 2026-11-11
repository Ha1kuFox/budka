class_name VoiceChatController
extends Node

## Friends-only voice chat over the existing MultiplayerAPI peer.
##
## TwoVoIP handles Opus encoding/decoding, RNNoise, AGC and jitter buffering.
## This node only owns the microphone, one speaker per remote peer, host relay
## and the small settings panel.
##
## Voice is off until the local player explicitly enables the microphone.

signal error(message: String)
## Emitted when a participant starts or stops sending voice.
signal peer_talking(peer_id: int, talking: bool)

enum Mode {
	VOX,
	PTT,
}

const MIC_SCENE: PackedScene = preload("res://addons/twovoip/voiphelper/two_voip_mic.tscn")
const SPEAKER_SCENE: PackedScene = preload("res://addons/voice_chat/voice_speaker.tscn")
const PANEL_SCRIPT: GDScript = preload("res://addons/voice_chat/voice_chat_panel.gd")

const MAX_VOICE_PACKET: int = 2048
const MAX_PACKETS_PER_SECOND: int = 200
const VOICE_BUS_NAME: String = "Voice"
const CONFIG_PATH: String = "user://voice_chat.cfg"


class DebugInfo:
	var online: bool = false
	var enabled: bool = false
	var talking: bool = false
	var mode: String = "VOX"
	var noise: bool = true
	var speakers: int = 0
	var tx: int = 0
	var rx: int = 0
	var failure: String = ""


var _mic: Node
var _panel: VoiceChatPanel
var _speakers_root: Node
var _speakers: Dictionary[int, AudioStreamPlayer] = { }
var _voice_bus: int = -1

var _enabled: bool = false
var _mode: int = Mode.VOX
var _noise: bool = true
var _volume_db: float = 0.0
var _input_device: String = ""

var _packets_tx: int = 0
var _packets_rx: int = 0
var _talking: Dictionary = {}
var _last_voice_msec: Dictionary = {}
var _activity_timer: Timer
var _packet_windows: Dictionary[int, Dictionary] = { }
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _failure: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	_ensure_voice_bus()
	if not TwoVoip.native_version_is_compatible():
		_failure = "TwoVoIP native version mismatch"

	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "VoiceChatLayer"
	layer.layer = 100
	add_child(layer)

	_panel = PANEL_SCRIPT.new()
	_panel.voice = self
	layer.add_child(_panel)
	_panel.set_initial(_mode, _noise, _volume_db)

	_speakers_root = Node.new()
	_speakers_root.name = "Speakers"
	add_child(_speakers_root)

	_activity_timer = Timer.new()
	_activity_timer.wait_time = 0.15
	_activity_timer.timeout.connect(_update_activity)
	add_child(_activity_timer)
	_activity_timer.start()

	_mic = MIC_SCENE.instantiate()
	add_child(_mic)
	_mic.connect("transmit_audio_packet", _on_mic_packet)
	_mic.connect("microphone_error", _on_microphone_error)
	_mic.call(
		"init_voip_mic",
		false,
		_panel.mic_button,
		_panel.input_option,
		_panel.ptt_button,
		_panel.vox_button,
		null,
	)

	_apply_opus_settings()
	set_mode(_mode)
	_panel.set_mic_button(false)
	_apply_mic_input(false)
	_apply_input_device()

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_multiplayer_connected)
	multiplayer.server_disconnected.connect(_on_multiplayer_disconnected)

	_update_status()
	if _is_online():
		_sync_speakers()


func _process(_delta: float) -> void:
	if not _is_online() and (_enabled or not _speakers.is_empty()):
		_go_offline()

	if _mode == Mode.PTT and _mic != null:
		var pressed: bool = _enabled and _is_online() and InputMap.has_action("voice_ptt") \
				and Input.is_action_pressed("voice_ptt")
		_mic.get("pttbutton").button_pressed = pressed


func set_mic_enabled(value: bool) -> void:
	if not _failure.is_empty():
		_panel.set_mic_button(false)
		return
	if value and not _is_online():
		_panel.set_mic_button(false)
		emit_signal("error", "Connect to a game before enabling the microphone.")
		_update_status()
		return

	_enabled = value
	_panel.set_mic_button(value)
	_apply_mic_input(value)
	_update_status()


func set_mode(mode: int) -> void:
	_mode = clampi(mode, Mode.VOX, Mode.PTT)
	_panel.set_mode(mode)
	if _mic != null:
		_mic.get("voxbutton").set_pressed_no_signal(_mode == Mode.VOX)
		_mic.call("_on_vox_toggled", _mode == Mode.VOX)
	_save_settings()
	_update_status()


func set_noise_enabled(value: bool) -> void:
	_noise = value
	_panel.set_noise(value)
	_apply_opus_settings()
	_save_settings()


func set_output_volume(value: float) -> void:
	_volume_db = clampf(value, -40.0, 6.0)
	AudioServer.set_bus_volume_db(_voice_bus, _volume_db)
	_save_settings()


func set_input_device(index: int) -> void:
	if _panel == null or index < 0 or index >= _panel.input_option.item_count:
		return
	_input_device = _panel.input_option.get_item_text(index)
	AudioServer.set_input_device(_input_device)
	if _enabled:
		_apply_mic_input(false)
		_apply_mic_input(true)
	_save_settings()


func toggle_panel() -> void:
	if _panel.visible:
		close_panel()
	else:
		open_panel()


func is_panel_open() -> bool:
	return _panel != null and _panel.visible


func open_panel() -> void:
	if _panel.visible:
		return
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_panel.set_mic_button(_enabled)
	_panel.visible = true
	_update_status()


func close_panel() -> void:
	if not _panel.visible:
		return
	_panel.visible = false
	Input.mouse_mode = _previous_mouse_mode
	_save_settings()


func is_mic_enabled() -> bool:
	return _enabled


## Read-only access for game UI that drives voice chat from its own menu.
func get_mode() -> int:
	return _mode


func is_noise_enabled() -> bool:
	return _noise


func get_output_volume() -> float:
	return _volume_db


## Select an input device by name; counterpart of set_input_device() for UI that
## keeps its own device list instead of the built-in panel's option button.
func set_input_device_name(device_name: String) -> void:
	_input_device = device_name
	AudioServer.set_input_device(device_name)
	if _enabled:
		_apply_mic_input(false)
		_apply_mic_input(true)
	_save_settings()


func is_talking() -> bool:
	return _mic != null and _mic.get("currentlytalking")


func get_debug_info() -> DebugInfo:
	var info: DebugInfo = DebugInfo.new()
	info.online = _is_online()
	info.enabled = _enabled
	info.talking = is_talking()
	info.mode = "VOX" if _mode == Mode.VOX else "PTT"
	info.noise = _noise
	info.speakers = _speakers.size()
	info.tx = _packets_tx
	info.rx = _packets_rx
	info.failure = _failure
	return info


func _ensure_voice_bus() -> void:
	_voice_bus = AudioServer.get_bus_index(VOICE_BUS_NAME)
	if _voice_bus >= 0:
		AudioServer.set_bus_volume_db(_voice_bus, _volume_db)
		return

	AudioServer.add_bus()
	_voice_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_voice_bus, VOICE_BUS_NAME)
	AudioServer.set_bus_send(_voice_bus, "Master")
	AudioServer.set_bus_volume_db(_voice_bus, _volume_db)


func _apply_opus_settings() -> void:
	if _mic == null:
		return
	var denoiser: int = TwovoipOpusEncoder.DENOISER_RNNOISE if _noise \
			else TwovoipOpusEncoder.DENOISER_DISABLED
	_mic.call(
		"set_opus_values",
		48000,
		20,
		1,
		16000,
		5,
		true,
		-1,
		denoiser,
		TwovoipOpusEncoder.AGC_APPLIED,
	)
	_mic.call("set_vox_threshhold", 0.02)


func _apply_mic_input(enabled: bool) -> void:
	if _mic == null:
		return
	_mic.get("miconbutton").set_pressed_no_signal(enabled)
	_mic.call("_on_miconbutton", enabled)
	if not enabled:
		_mic.get("pttbutton").button_pressed = false


func _apply_input_device() -> void:
	if _input_device.is_empty() or _panel == null:
		return
	for index: int in range(_panel.input_option.item_count):
		if _panel.input_option.get_item_text(index) == _input_device:
			_panel.select_input_device(index)
			AudioServer.set_input_device(_input_device)
			return


func _on_microphone_error(message: String) -> void:
	_enabled = false
	if _panel != null:
		_panel.set_mic_button(false)
	if _mic != null:
		_mic.get("miconbutton").set_pressed_no_signal(false)
	AudioServer.set_input_device_active(false)
	emit_signal("error", message)
	_update_status()


func _on_mic_packet(packet: PackedByteArray) -> void:
	if not _enabled or not _is_online() or packet.is_empty():
		return

	var control: bool = TwoVoipPacket.is_control_packet(packet)
	var sender_id: int = multiplayer.get_unique_id()
	_packets_tx += 1

	if not control:
		_mark_talking(sender_id)

	if control:
		if multiplayer.is_server():
			rpc("_receive_control", sender_id, packet)
		else:
			rpc_id(1, "_receive_control", sender_id, packet)
	else:
		if multiplayer.is_server():
			rpc("_receive_audio", sender_id, packet)
		else:
			rpc_id(1, "_receive_audio", sender_id, packet)


@rpc("any_peer", "call_remote", "reliable", 2)
func _receive_control(sender_id: int, packet: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id() != sender_id:
		return
	if not _accept_packet(sender_id, packet):
		return

	_deliver_packet(sender_id, packet)
	if multiplayer.is_server():
		rpc("_relay_control", sender_id, packet)


@rpc("authority", "call_remote", "reliable", 2)
func _relay_control(sender_id: int, packet: PackedByteArray) -> void:
	if _accept_relayed(sender_id, packet):
		_deliver_packet(sender_id, packet)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _receive_audio(sender_id: int, packet: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id() != sender_id:
		return
	if not _accept_packet(sender_id, packet):
		return

	_deliver_packet(sender_id, packet)
	if multiplayer.is_server():
		rpc("_relay_audio", sender_id, packet)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _relay_audio(sender_id: int, packet: PackedByteArray) -> void:
	if _accept_relayed(sender_id, packet):
		_deliver_packet(sender_id, packet)


func _accept_packet(sender_id: int, packet: PackedByteArray) -> bool:
	if sender_id == multiplayer.get_unique_id():
		return false
	if packet.is_empty() or packet.size() > MAX_VOICE_PACKET:
		return false
	if not multiplayer.get_peers().has(sender_id):
		return false
	return _allow_packet_rate(sender_id)


func _accept_relayed(sender_id: int, packet: PackedByteArray) -> bool:
	if sender_id == multiplayer.get_unique_id():
		return false
	return not packet.is_empty() and packet.size() <= MAX_VOICE_PACKET


func _allow_packet_rate(sender_id: int) -> bool:
	var now: int = Time.get_ticks_msec()
	var entry: Dictionary = { }
	if _packet_windows.has(sender_id):
		entry = _packet_windows[sender_id]
	var start: int = 0
	if entry.has("start"):
		start = int(entry["start"])
	if entry.is_empty() or now - start >= 1000:
		_packet_windows[sender_id] = { "start": now, "count": 1 }
		return true

	var count: int = int(entry["count"])
	if count >= MAX_PACKETS_PER_SECOND:
		return false
	entry["count"] = count + 1
	_packet_windows[sender_id] = entry
	return true


func _deliver_packet(sender_id: int, packet: PackedByteArray) -> void:
	if sender_id == multiplayer.get_unique_id():
		return
	var speaker: AudioStreamPlayer = _ensure_speaker(sender_id)
	if speaker == null:
		return
	var receiver: Node = speaker.get_node_or_null("TwoVoipSpeaker")
	if receiver == null:
		return
	_packets_rx += 1
	receiver.receive_audio_packet(packet)
	if not TwoVoipPacket.is_control_packet(packet):
		_mark_talking(sender_id)


func _ensure_speaker(peer_id: int) -> AudioStreamPlayer:
	if _speakers.has(peer_id):
		var existing: AudioStreamPlayer = _speakers[peer_id]
		if is_instance_valid(existing):
			return existing
		_speakers.erase(peer_id)

	if peer_id == multiplayer.get_unique_id() or _speakers_root == null:
		return null

	var speaker_resource: Node = SPEAKER_SCENE.instantiate()
	if not speaker_resource is AudioStreamPlayer:
		return null
	var speaker: AudioStreamPlayer = speaker_resource
	speaker.name = "VoiceSpeaker_%d" % peer_id
	speaker.bus = VOICE_BUS_NAME
	_speakers_root.add_child(speaker)
	var two_voip_speaker: Node = speaker.get_node_or_null("TwoVoipSpeaker")
	if two_voip_speaker != null:
		two_voip_speaker.set("audio_buffer_lag_time_target", 0.2)
	_speakers[peer_id] = speaker
	return speaker


func _remove_speaker(peer_id: int) -> void:
	var speaker: AudioStreamPlayer = null
	if _speakers.has(peer_id):
		speaker = _speakers[peer_id]
	if is_instance_valid(speaker):
		speaker.queue_free()
	_speakers.erase(peer_id)


func _clear_speakers() -> void:
	for peer_id: int in _speakers.keys():
		_remove_speaker(peer_id)


func _sync_speakers() -> void:
	if not _is_online():
		return
	for peer_id: int in multiplayer.get_peers():
		_ensure_speaker(peer_id)


func _on_peer_connected(peer_id: int) -> void:
	_ensure_speaker(peer_id)
	_update_status()


func _on_peer_disconnected(peer_id: int) -> void:
	_remove_speaker(peer_id)
	_packet_windows.erase(peer_id)
	_clear_talking(peer_id)
	_update_status()


func _on_multiplayer_connected() -> void:
	_sync_speakers()
	_update_status()


func _on_multiplayer_disconnected() -> void:
	_go_offline()


func _go_offline() -> void:
	_enabled = false
	for peer_id: int in _talking.keys().duplicate():
		_clear_talking(peer_id)
	_clear_speakers()
	_packet_windows.clear()
	if _panel != null:
		_panel.set_mic_button(false)
	_apply_mic_input(false)
	_update_status()


func _is_online() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _update_status() -> void:
	if _panel == null:
		return
	if not _failure.is_empty():
		_panel.set_status(_failure)
	elif not _is_online():
		_panel.set_status("Offline")
	elif not _enabled:
		_panel.set_status("Microphone off")
	else:
		_panel.set_status("Microphone on · %s" % ("VOX" if _mode == Mode.VOX else "Push to talk"))


func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	_mode = clampi(int(config.get_value("voice", "mode", Mode.VOX)), Mode.VOX, Mode.PTT)
	_noise = bool(config.get_value("voice", "noise", true))
	_volume_db = float(config.get_value("voice", "volume_db", 0.0))
	_input_device = String(config.get_value("voice", "input_device", ""))


func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("voice", "mode", _mode)
	config.set_value("voice", "noise", _noise)
	config.set_value("voice", "volume_db", _volume_db)
	config.set_value("voice", "input_device", _input_device)
	config.save(CONFIG_PATH)


func _mark_talking(peer_id: int) -> void:
	_last_voice_msec[peer_id] = Time.get_ticks_msec()
	if bool(_talking.get(peer_id, false)):
		return
	_talking[peer_id] = true
	peer_talking.emit(peer_id, true)


func _clear_talking(peer_id: int) -> void:
	_talking.erase(peer_id)
	_last_voice_msec.erase(peer_id)
	peer_talking.emit(peer_id, false)


func _update_activity() -> void:
	var now: int = Time.get_ticks_msec()
	for peer_id: int in _talking.keys().duplicate():
		if now - int(_last_voice_msec.get(peer_id, 0)) > 350:
			_clear_talking(peer_id)
