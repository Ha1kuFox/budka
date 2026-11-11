@tool
class_name ThemeApplier
extends Node


signal theme_changed(dark: bool)

enum Mode {
	SYSTEM,
	LIGHT,
	DARK,
}

@export var mode: Mode = Mode.SYSTEM:
	set(value):
		mode = value
		_apply()

@export var dark_theme: Theme:
	set(value):
		dark_theme = value
		_apply()

@export var light_theme: Theme:
	set(value):
		light_theme = value
		_apply()

@export var target: Control:
	set(value):
		target = value
		_apply()


func _enter_tree() -> void:
	_apply()


func _ready() -> void:
	_apply()


func is_dark() -> bool:
	match mode:
		Mode.LIGHT:
			return false
		Mode.DARK:
			return true

	if DisplayServer.is_dark_mode_supported():
		return DisplayServer.is_dark_mode()
	return true


func set_dark(dark: bool) -> void:
	mode = Mode.DARK if dark else Mode.LIGHT


func _apply() -> void:
	if not is_inside_tree():
		return

	var dark: bool = is_dark()
	var chosen: Theme = dark_theme if dark else light_theme
	if chosen == null:
		return

	var control: Control = target if target != null else get_parent() as Control
	if control == null:
		return

	if control.theme != chosen:
		control.theme = chosen

	var background: ColorRect = control.get_node_or_null("BG") as ColorRect
	if background != null:
		background.color = chosen.get_color("background", "Window")

	theme_changed.emit(dark)
