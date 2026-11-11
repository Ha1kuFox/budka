class_name HoverPanel
extends Control


const TOP_OFFSET: float = 40.0

@export var users_list: Control
@export var hover_zone: Control
@export var grid: UsersGrid

var _users_list: Control
var _hover_zone: Control
var _grid: UsersGrid
@onready var _hide_timer: Timer = %HideTimer
@onready var _watch_timer: Timer = %WatchTimer
var _tween: Tween
var _active: bool = false
var _hovered: bool = false
var _pointer_inside: bool = false
var _panel_height: float = 120.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_users_list = users_list
	_hover_zone = hover_zone
	_grid = grid
	_hover_zone.mouse_entered.connect(_show_panel)
	_hover_zone.mouse_exited.connect(_schedule_hide)
	_users_list.mouse_entered.connect(_on_panel_entered)
	_users_list.mouse_exited.connect(_on_panel_exited)
	_grid.layout_changed.connect(_on_layout_changed)
	_hide_timer.timeout.connect(_hide_panel)
	_watch_timer.timeout.connect(_watch_pointer)


func set_active(active: bool) -> void:
	if active == _active:
		return
	if _tween != null:
		_tween.kill()
	_active = active
	_hovered = false
	_pointer_inside = false
	_hide_timer.stop()
	_watch_timer.stop()
	_hover_zone.visible = active

	if active:
		_users_list.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_users_list.offset_left = 18.0
		_users_list.offset_right = -18.0
		_apply_geometry()
		_users_list.position.y = -_panel_height - 20.0
	else:
		_users_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_users_list.offset_left = 0.0
		_users_list.offset_top = 0.0
		_users_list.offset_right = 0.0
		_users_list.offset_bottom = 0.0
		_users_list.position = Vector2.ZERO


func _on_layout_changed(height: float) -> void:
	_panel_height = height
	if _active:
		_apply_geometry()
		if not _hovered:
			_users_list.position.y = -_panel_height - 20.0


func _apply_geometry() -> void:
	_users_list.offset_top = TOP_OFFSET
	_users_list.offset_bottom = TOP_OFFSET + _panel_height


func _show_panel() -> void:
	if not _active:
		return
	_hovered = true
	_hide_timer.stop()
	_watch_timer.start()
	_apply_geometry()
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_users_list, "position:y", TOP_OFFSET, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func hide_panel() -> void:
	if not _active:
		return
	_hovered = false
	_pointer_inside = false
	_hide_timer.stop()
	_watch_timer.stop()
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_users_list, "position:y", -_panel_height - 20.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)


func _hide_panel() -> void:
	if not _active:
		return

	var mouse: Vector2 = _users_list.get_global_mouse_position()
	if _pointer_inside or _users_list.get_global_rect().has_point(mouse) or _hover_zone.get_global_rect().has_point(mouse):
		return

	_hovered = false
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_users_list, "position:y", -_panel_height - 20.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_watch_timer.stop()


func _schedule_hide() -> void:
	if _active and not _pointer_inside:
		_hide_timer.start()


func _watch_pointer() -> void:
	if not _active:
		_watch_timer.stop()
		return

	var mouse: Vector2 = _users_list.get_global_mouse_position()
	if _users_list.get_global_rect().has_point(mouse) or _hover_zone.get_global_rect().has_point(mouse):
		_pointer_inside = true
		return

	_pointer_inside = false
	_hide_panel()


func _on_panel_entered() -> void:
	_pointer_inside = true
	_hide_timer.stop()


func _on_panel_exited() -> void:
	_pointer_inside = false
	_schedule_hide()
