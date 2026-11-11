class_name HoverPanel
extends Control


const HOVER_HEIGHT: float = 32.0
const TOP_OFFSET: float = HOVER_HEIGHT + 4.0
const HIDE_AFTER: float = 0.25

var _users_list: Control
var _content_box: VBoxContainer
var _grid: UsersGrid
var _overlay: Control
var _hover_zone: Control
var _hide_timer: Timer
var _watch_timer: Timer
var _tween: Tween
var _active: bool = false
var _hovered: bool = false
var _pointer_inside: bool = false
var _panel_height: float = 120.0


func _ready() -> void:
	L.info("hover: HoverPanel ready")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_overlay = Control.new()
	_overlay.name = "UsersOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_hover_zone = Control.new()
	_hover_zone.name = "UsersHoverZone"
	_hover_zone.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hover_zone.offset_bottom = HOVER_HEIGHT
	_hover_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	_hover_zone.visible = false
	_hover_zone.mouse_entered.connect(_show_panel)
	_hover_zone.mouse_exited.connect(_schedule_hide)
	add_child(_hover_zone)

	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.wait_time = HIDE_AFTER
	_hide_timer.timeout.connect(_hide_panel)
	add_child(_hide_timer)

	_watch_timer = Timer.new()
	_watch_timer.wait_time = 0.12
	_watch_timer.timeout.connect(_watch_pointer)
	add_child(_watch_timer)


func setup(users_list: Control, content_box: VBoxContainer, grid: UsersGrid) -> void:
	L.info("hover: setup")
	_users_list = users_list
	_content_box = content_box
	_grid = grid
	_users_list.mouse_entered.connect(_on_panel_entered)
	_users_list.mouse_exited.connect(_on_panel_exited)
	_grid.layout_changed.connect(_on_layout_changed)


func set_active(active: bool) -> void:
	if active == _active:
		return
	_active = active
	L.info("hover: active=%s" % active)
	_hovered = false
	_pointer_inside = false
	_hide_timer.stop()
	_watch_timer.stop()
	_hover_zone.visible = active

	if active:
		_users_list.reparent(_overlay, false)
		_users_list.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_users_list.offset_left = 18.0
		_users_list.offset_right = -18.0
		_apply_geometry()
		_users_list.position.y = -_panel_height - 20.0
	else:
		_users_list.reparent(_content_box, false)
		_content_box.move_child(_users_list, 0)
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


func _hide_panel() -> void:
	if not _active or _pointer_inside:
		return
	var mouse: Vector2 = _users_list.get_global_mouse_position()
	if _users_list.get_global_rect().has_point(mouse) or _hover_zone.get_global_rect().has_point(mouse):
		return

	_hovered = false
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_users_list, "position:y", -_panel_height - 20.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_watch_timer.stop()


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
