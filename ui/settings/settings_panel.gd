class_name SettingsPanel
extends Control


const THEME_SYSTEM: int = 0
const THEME_LIGHT: int = 1
const THEME_DARK: int = 2
const SETTINGS_PATH: String = "user://budka_settings.cfg"

@onready var _overlay: CenterContainer = %SettingsOverlay
@onready var _theme_option: OptionButton = %ThemeOption
@onready var _noise_check: CheckButton = %NoiseCheck
@onready var _mic_mode_option: OptionButton = %MicModeOption
@onready var _device_option: OptionButton = %DeviceOption
@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _volume_value: Label = %VolumeValue
@onready var _close_button: Button = $SettingsOverlay/Panel/Margin/Box/CloseButton
@onready var _ptt_row: VBoxContainer = %PTTRow
@onready var _ptt_button: Button = %PTTButton
@onready var _theme_applier: ThemeApplier = get_parent().get_node("ThemeApplier") as ThemeApplier

var _capturing_ptt: bool = false
var _ptt_keycode: int = KEY_V


func _ready() -> void:
	add_to_group("settings_panel")
	L.info("settings: SettingsPanel ready")
	_theme_option.add_item("Системная")
	_theme_option.add_item("Светлая")
	_theme_option.add_item("Тёмная")
	_mic_mode_option.add_item("VOX")
	_mic_mode_option.add_item("PTT")

	_close_button.pressed.connect(close)
	_theme_option.item_selected.connect(_on_theme_selected)
	_noise_check.toggled.connect(_on_noise_toggled)
	_mic_mode_option.item_selected.connect(_on_mic_mode_selected)
	_device_option.item_selected.connect(_on_device_selected)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_ptt_button.pressed.connect(_on_ptt_button_pressed)
	var room: Control = get_parent().get_node("SafeZone/Room") as Control
	room.visibility_changed.connect(_on_room_visibility_changed)
	_load_ptt_key()
	_sync_state()


func toggle() -> void:
	_toggle()


func close() -> void:
	L.debug("settings: close")
	_cancel_ptt_capture()
	_overlay.visible = false


func is_open() -> bool:
	return _overlay.visible


func _sync_state() -> void:
	_theme_option.select(int(_theme_applier.mode))
	_noise_check.set_pressed_no_signal(VoiceChat.is_noise_enabled())
	_mic_mode_option.select(VoiceChat.get_mode())
	_update_ptt_visibility(VoiceChat.get_mode())
	_volume_slider.set_value_no_signal(VoiceChat.get_output_volume())
	_update_volume_label(VoiceChat.get_output_volume())
	_refresh_devices(AudioServer.get_input_device())


func _refresh_devices(current: String) -> void:
	_device_option.clear()
	_device_option.add_item("По умолчанию")
	var selected: int = 0
	var devices: PackedStringArray = AudioServer.get_input_device_list()
	for index: int in devices.size():
		var _name: String = devices[index]
		_device_option.add_item(_name)
		if _name == current:
			selected = index + 1
	_device_option.select(selected)


func _update_volume_label(value: float) -> void:
	_volume_value.text = "%d dB" % int(value)


func _on_room_visibility_changed() -> void:
	if not (get_parent().get_node("SafeZone/Room") as Control).visible:
		close()


func _toggle() -> void:
	_overlay.visible = not _overlay.visible
	L.info("settings: open=%s" % _overlay.visible)
	if _overlay.visible:
		_sync_state()


func _on_theme_selected(index: int) -> void:
	L.info("settings: theme=%d" % index)
	_theme_applier.mode = index as ThemeApplier.Mode


func _on_noise_toggled(enabled: bool) -> void:
	L.info("settings: noise=%s" % enabled)
	VoiceChat.set_noise_enabled(enabled)


func _on_mic_mode_selected(index: int) -> void:
	L.info("settings: mic mode=%d" % index)
	VoiceChat.set_mode(index)
	_update_ptt_visibility(index)


func _on_device_selected(index: int) -> void:
	var device_name: String = "" if index == 0 else _device_option.get_item_text(index)
	L.info("settings: device=%s" % device_name)
	VoiceChat.set_input_device_name(device_name)


func _on_volume_changed(value: float) -> void:
	_update_volume_label(value)
	VoiceChat.set_output_volume(value)


func _on_ptt_button_pressed() -> void:
	_capturing_ptt = true
	_ptt_button.text = "Нажмите клавишу…"
	L.info("settings: waiting for PTT key")


func _input(event: InputEvent) -> void:
	if _overlay.visible and not _capturing_ptt and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if not _capturing_ptt:
		return
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed:
		return
	if key_event.keycode == KEY_ESCAPE:
		_cancel_ptt_capture()
		get_viewport().set_input_as_handled()
		return
	var keycode: int = int(key_event.physical_keycode)
	if keycode == 0:
		keycode = int(key_event.keycode)
	if keycode == 0:
		return
	_set_ptt_key(keycode)
	_capturing_ptt = false
	get_viewport().set_input_as_handled()


func _set_ptt_key(keycode: int) -> void:
	_ptt_keycode = keycode
	if not InputMap.has_action("voice_ptt"):
		InputMap.add_action("voice_ptt")
	InputMap.action_erase_events("voice_ptt")
	var input_event: InputEventKey = InputEventKey.new()
	input_event.physical_keycode = keycode as Key
	InputMap.action_add_event("voice_ptt", input_event)
	_update_ptt_text()
	_save_ptt_key()
	L.info("settings: PTT key=%s" % OS.get_keycode_string(keycode))


func _load_ptt_key() -> void:
	var config: ConfigFile = ConfigFile.new()
	var stored: int = 0
	if config.load(SETTINGS_PATH) == OK:
		stored = int(config.get_value("input", "ptt_key", 0))
	if stored == 0 and InputMap.has_action("voice_ptt"):
		for event: InputEvent in InputMap.action_get_events("voice_ptt"):
			if event is InputEventKey:
				var key_event: InputEventKey = event as InputEventKey
				stored = int(key_event.physical_keycode)
				if stored == 0:
					stored = int(key_event.keycode)
				break
	if stored == 0:
		stored = KEY_V
	_set_ptt_key(stored)


func _save_ptt_key() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("input", "ptt_key", _ptt_keycode)
	config.save(SETTINGS_PATH)


func _update_ptt_text() -> void:
	var label: String = OS.get_keycode_string(_ptt_keycode)
	_ptt_button.text = label if not label.is_empty() else "?"


func _update_ptt_visibility(mode: int) -> void:
	_ptt_row.visible = mode == 1


func _cancel_ptt_capture() -> void:
	_capturing_ptt = false
	_update_ptt_text()
