class_name RoomToolbox
extends CenterContainer


const COLOR_EXIT: Color = Color(1.0, 0.35, 0.35)

@onready var _exit: Button = %ExitButton
@onready var _mic: Button = %MicButton
@onready var _speaker: Button = %SpeakerButton
@onready var _broadcast: Button = %BroadcastButton
@onready var broadcaster: StreamBroadcaster = get_tree().get_first_node_in_group("stream_broadcaster") as StreamBroadcaster


func _ready() -> void:
	_exit.modulate = COLOR_EXIT
	_exit.pressed.connect(NetworkManager.leave)
	_mic.toggled.connect(_on_mic_toggled)
	_speaker.toggled.connect(_on_speaker_toggled)
	_broadcast.toggled.connect(_on_broadcast_toggled)
	broadcaster.sharing_changed.connect(_on_sharing_changed)
	broadcaster.failed.connect(_on_broadcast_failed)

	_speaker.set_pressed_no_signal(true)
	VoiceChat.set_output_volume(0.0)


func _on_mic_toggled(enabled: bool) -> void:
	var allowed: bool = enabled and NetworkManager.connected
	_mic.set_pressed_no_signal(allowed)
	VoiceChat.set_mic_enabled(allowed)
	L.info("toolbox: mic=%s" % allowed)


func _on_speaker_toggled(enabled: bool) -> void:
	VoiceChat.set_output_volume(0.0 if enabled else -40.0)
	L.info("toolbox: speaker=%s" % enabled)


func _on_broadcast_toggled(enabled: bool) -> void:
	L.info("toolbox: broadcast=%s" % enabled)
	broadcaster.set_enabled(enabled)


func _on_sharing_changed(active: bool) -> void:
	_broadcast.set_pressed_no_signal(active)


func _on_broadcast_failed(message: String) -> void:
	_broadcast.set_pressed_no_signal(false)
	L.warn("toolbox: %s" % message)
