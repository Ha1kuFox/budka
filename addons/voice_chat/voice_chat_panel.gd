class_name VoiceChatPanel
extends PanelContainer

## Compact voice settings panel. VoiceChat creates and owns this node; game UI
## only needs to call VoiceChat.toggle_panel().

const PANEL_WIDTH: int = 360
const PANEL_HEIGHT: int = 300

var voice: Node

var mic_button: CheckButton
var mode_option: OptionButton
var input_option: OptionButton
var volume_slider: HSlider
var noise_check: CheckButton
var status_label: Label

## Buttons required by TwoVoipMic but not part of the visible UI. PTT is driven
## by the voice_ptt input action; VOX is the normal mode.
var ptt_button: Button
var vox_button: Button

var _hint: Label


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_WIDTH * 0.5
	offset_top = -PANEL_HEIGHT * 0.5
	offset_right = PANEL_WIDTH * 0.5
	offset_bottom = PANEL_HEIGHT * 0.5

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title: Label = Label.new()
	title.text = "Voice chat"
	title.add_theme_font_size_override("font_size", 17)
	vbox.add_child(title)

	mic_button = CheckButton.new()
	mic_button.text = "Microphone"
	mic_button.toggle_mode = true
	mic_button.button_pressed = false
	mic_button.toggled.connect(_on_mic_toggled)
	vbox.add_child(mic_button)

	var mode_row: HBoxContainer = HBoxContainer.new()
	var mode_label: Label = Label.new()
	mode_label.text = "Mode"
	mode_label.custom_minimum_size.x = 58
	mode_row.add_child(mode_label)
	mode_option = OptionButton.new()
	mode_option.add_item("Voice activation", 0)
	mode_option.add_item("Push to talk", 1)
	mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_option.item_selected.connect(_on_mode_selected)
	mode_row.add_child(mode_option)
	vbox.add_child(mode_row)

	var input_row: HBoxContainer = HBoxContainer.new()
	var input_label: Label = Label.new()
	input_label.text = "Input"
	input_label.custom_minimum_size.x = 58
	input_row.add_child(input_label)
	input_option = OptionButton.new()
	input_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_option.item_selected.connect(_on_input_selected)
	input_row.add_child(input_option)
	vbox.add_child(input_row)

	var volume_row: HBoxContainer = HBoxContainer.new()
	var volume_label: Label = Label.new()
	volume_label.text = "Volume"
	volume_label.custom_minimum_size.x = 58
	volume_row.add_child(volume_label)
	volume_slider = HSlider.new()
	volume_slider.min_value = -40.0
	volume_slider.max_value = 6.0
	volume_slider.step = 0.5
	volume_slider.value = 0.0
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.value_changed.connect(_on_volume_changed)
	volume_row.add_child(volume_slider)
	vbox.add_child(volume_row)

	noise_check = CheckButton.new()
	noise_check.text = "Noise suppression (RNNoise)"
	noise_check.button_pressed = true
	noise_check.toggled.connect(_on_noise_toggled)
	vbox.add_child(noise_check)

	_hint = Label.new()
	_hint.text = "Hold V for push-to-talk"
	_hint.visible = false
	vbox.add_child(_hint)

	status_label = Label.new()
	status_label.text = "Offline"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(status_label)

	var close_button: Button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(_on_close_pressed)
	vbox.add_child(close_button)

	# Required by TwoVoipMic; no need to display them.
	ptt_button = Button.new()
	ptt_button.visible = false
	add_child(ptt_button)
	vox_button = Button.new()
	vox_button.toggle_mode = true
	vox_button.button_pressed = true
	vox_button.visible = false
	add_child(vox_button)


func set_initial(mode: int, noise: bool, volume_db: float) -> void:
	mode_option.select(mode)
	noise_check.set_pressed_no_signal(noise)
	volume_slider.set_value_no_signal(volume_db)
	_update_hint(mode)


func set_mic_button(enabled: bool) -> void:
	mic_button.set_pressed_no_signal(enabled)


func set_mode(mode: int) -> void:
	mode_option.select(mode)
	_update_hint(mode)


func set_noise(enabled: bool) -> void:
	noise_check.set_pressed_no_signal(enabled)


func set_status(text: String) -> void:
	status_label.text = text


func select_input_device(index: int) -> void:
	if index >= 0 and index < input_option.item_count:
		input_option.select(index)


func _update_hint(mode: int) -> void:
	_hint.visible = mode == 1


func _on_mic_toggled(enabled: bool) -> void:
	if voice != null:
		voice.set_mic_enabled(enabled)


func _on_mode_selected(index: int) -> void:
	if voice != null:
		voice.set_mode(index)


func _on_input_selected(index: int) -> void:
	if voice != null:
		voice.set_input_device(index)


func _on_volume_changed(value: float) -> void:
	if voice != null:
		voice.set_output_volume(value)


func _on_noise_toggled(enabled: bool) -> void:
	if voice != null:
		voice.set_noise_enabled(enabled)


func _on_close_pressed() -> void:
	if voice != null:
		voice.close_panel()
	else:
		visible = false
