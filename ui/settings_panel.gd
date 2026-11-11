class_name SettingsPanel
extends Control


signal mode_selected(mode: int)
signal theme_selected(mode: int)

const MODE_PANEL: int = 0
const MODE_MAIN: int = 1
const THEME_SYSTEM: int = 0
const THEME_LIGHT: int = 1
const THEME_DARK: int = 2

var _overlay: CenterContainer
var _mode_option: OptionButton
var _theme_option: OptionButton
var _button: Button


func _ready() -> void:
	L.info("settings: SettingsPanel ready")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_button()
	_build_overlay()


func set_mode(mode: int) -> void:
	L.debug("settings: mode=%d" % mode)
	if _mode_option != null:
		_mode_option.select(clampi(mode, MODE_PANEL, MODE_MAIN))


func set_theme_mode(mode: int) -> void:
	L.debug("settings: theme=%d" % mode)
	if _theme_option != null:
		_theme_option.select(clampi(mode, THEME_SYSTEM, THEME_DARK))


func close() -> void:
	L.debug("settings: close")
	_overlay.visible = false


func is_open() -> bool:
	return _overlay.visible


func _build_button() -> void:
	_button = Button.new()
	_button.name = "SettingsButton"
	_button.tooltip_text = "Настройки"
	_button.custom_minimum_size = Vector2(48, 48)
	_button.flat = true
	_button.expand_icon = true
	_button.icon = load("res://assets/icons/settings.svg") as Texture2D
	_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var inset: StyleBoxEmpty = StyleBoxEmpty.new()
	inset.content_margin_left = 6.0
	inset.content_margin_top = 6.0
	inset.content_margin_right = 6.0
	inset.content_margin_bottom = 6.0
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		_button.add_theme_stylebox_override(state, inset)
	_button.pressed.connect(_toggle)

	var exit_button: Button = %ExitButton
	var row: HBoxContainer = exit_button.get_parent() as HBoxContainer
	row.add_child(_button)
	row.move_child(_button, exit_button.get_index())


func _build_overlay() -> void:
	_overlay = CenterContainer.new()
	_overlay.name = "SettingsOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	_overlay.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title: Label = Label.new()
	title.text = "Настройки"
	title.theme_type_variation = &"Title"
	box.add_child(title)

	var mode_caption: Label = Label.new()
	mode_caption.text = "Режим интерфейса"
	mode_caption.theme_type_variation = &"Caption"
	box.add_child(mode_caption)

	_mode_option = _make_option(["Панельный", "Основной"])
	_mode_option.item_selected.connect(_on_mode_selected)
	box.add_child(_mode_option)

	var theme_caption: Label = Label.new()
	theme_caption.text = "Тема"
	theme_caption.theme_type_variation = &"Caption"
	box.add_child(theme_caption)

	_theme_option = _make_option(["Системная", "Светлая", "Тёмная"])
	_theme_option.item_selected.connect(_on_theme_selected)
	box.add_child(_theme_option)

	var close_button: Button = Button.new()
	close_button.text = "Закрыть"
	close_button.pressed.connect(close)
	box.add_child(close_button)


func _make_option(items: Array[String]) -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.custom_minimum_size = Vector2(0, 40)
	for item: String in items:
		option.add_item(item)
	return option


func _toggle() -> void:
	_overlay.visible = not _overlay.visible
	L.info("settings: open=%s" % _overlay.visible)


func _on_mode_selected(index: int) -> void:
	L.info("settings: mode=%d" % index)
	mode_selected.emit(index)


func _on_theme_selected(index: int) -> void:
	L.info("settings: theme=%d" % index)
	theme_selected.emit(index)
