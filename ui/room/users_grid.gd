class_name UsersGrid
extends PanelContainer


signal user_picked(user_id: int)
signal layout_changed(height: float)

const MAX_USERS: int = 6
const GRID_GAP: float = 10.0
const ASPECT: float = 16.0 / 9.0

@export var _grid: GridContainer

var _users: Array = []
var _textures: Dictionary = {}
var _cells: Array[AspectRatioContainer] = []
var _tiles: Array[Button] = []
var _borders: Array[Panel] = []
var _talking: Dictionary = {}
var _template: AspectRatioContainer
var _watching: bool = false
var _overlay_mode: bool = false
var _panel_height: float = 0.0
var _last_logged_size: Vector2 = Vector2.ZERO
var _last_logged_columns: int = 0


func _ready() -> void:
	L.info("grid: UsersGrid ready")
	_template = _grid.get_child(0) as AspectRatioContainer
	_template.visible = false
	get_viewport().size_changed.connect(_layout)


func set_users(users: Array) -> void:
	L.debug("grid: users=%d" % users.size())
	_users = users.slice(0, MAX_USERS).duplicate(true)
	for user_id: int in _talking.keys().duplicate():
		if _index_of(user_id) == -1:
			_talking.erase(user_id)
	_rebuild()
	_layout.call_deferred()


func set_watching(watching: bool) -> void:
	if _watching == watching:
		return
	L.debug("grid: watching=%s" % watching)
	_watching = watching
	_layout.call_deferred()


func set_overlay_mode(overlay: bool) -> void:
	if _overlay_mode == overlay:
		return
	L.debug("grid: overlay=%s" % overlay)
	_overlay_mode = overlay
	_layout.call_deferred()


func get_panel_height() -> float:
	return _panel_height


func set_texture(user_id: int, texture: Texture2D) -> void:
	_textures[user_id] = texture
	var index: int = _index_of(user_id)
	if index != -1:
		_update_preview(index)


func set_talking(user_id: int, talking: bool) -> void:
	_talking[user_id] = talking
	var index: int = _index_of(user_id)
	if index != -1:
		_update_talking(index)


func clear_texture(user_id: int) -> void:
	_textures.erase(user_id)
	var index: int = _index_of(user_id)
	if index != -1:
		_update_preview(index)


func has_user(user_id: int) -> bool:
	return _index_of(user_id) != -1


func is_streaming(user_id: int) -> bool:
	for user: Dictionary in _users:
		if int(user.get("id", -1)) == user_id:
			return bool(user.get("streaming", false))
	return false


func _rebuild() -> void:
	var count: int = _users.size()
	_ensure_cells(count)
	_grid.visible = count > 0

	for i: int in _cells.size():
		var cell: AspectRatioContainer = _cells[i]
		cell.visible = i < count
		if not cell.visible:
			continue

		var user: Dictionary = _users[i]
		var tile: Button = _tiles[i]
		var user_id: int = int(user.get("id", -1))
		tile.set_meta("user_id", user_id)
		var name_label: Label = tile.get_node(NodePath("TileMargin/TileVBox/TileName"))
		name_label.text = str(user.get("name", "Без имени"))
		name_label.add_theme_color_override("font_color", Color(0.207843, 0.517647, 0.894118) if bool(user.get("streaming", false)) else Color(1, 1, 1))
		tile.tooltip_text = "Смотреть экран: %s" % name_label.text
		_update_preview(i)
		_update_talking(i)


func _ensure_cells(count: int) -> void:
	while _cells.size() < count:
		var cell: AspectRatioContainer = _template.duplicate() as AspectRatioContainer
		cell.visible = true
		cell.ratio = ASPECT
		cell.size_flags_vertical = 0
		_grid.add_child(cell)

		var tile: Button = cell.get_node("Tile") as Button
		tile.custom_minimum_size = Vector2.ZERO
		tile.pressed.connect(_on_tile_pressed.bind(tile))
		_ensure_preview(tile)
		_cells.append(cell)
		_tiles.append(tile)

		_borders.append(tile.get_node("TalkingBorder") as Panel)


func _ensure_preview(tile: Button) -> TextureRect:
	var view: Control = tile.get_node("TileMargin/TileVBox/TileView") as Control
	return view.get_node("TileStream") as TextureRect


func _update_preview(index: int) -> void:
	if index < 0 or index >= _tiles.size() or index >= _users.size():
		return
	var user_id: int = int(_users[index].get("id", -1))
	var tile: Button = _tiles[index]
	var preview: TextureRect = _ensure_preview(tile)
	var texture: Texture2D = _textures.get(user_id) as Texture2D
	preview.texture = texture
	preview.visible = texture != null
	var empty: Label = tile.get_node("TileMargin/TileVBox/TileView/TileEmpty") as Label
	if empty != null:
		empty.visible = texture == null


func _update_talking(index: int) -> void:
	if index < 0 or index >= _borders.size() or index >= _users.size():
		return
	var user_id: int = int(_users[index].get("id", -1))
	_borders[index].visible = bool(_talking.get(user_id, false))


func _layout() -> void:
	var count: int = _users.size()
	if count == 0:
		_panel_height = 0.0
		layout_changed.emit(_panel_height)
		return

	var columns: int = count if _watching else (2 if count < 5 else 3)
	_grid.columns = columns
	var rows: int = ceili(float(count) / float(columns))

	var viewport: Vector2 = get_viewport_rect().size
	var width_available: float = viewport.x - 60.0
	var height_available: float = viewport.y - 128.0
	if _watching:
		height_available = clampf(viewport.y * (0.4 if _overlay_mode else 0.42), 200.0, 520.0)
	if width_available <= 0.0 or height_available <= 0.0:
		_layout.call_deferred()
		return

	var width: float = (width_available - GRID_GAP * (columns - 1)) / columns
	var height: float = width / ASPECT
	var max_height: float = (height_available - GRID_GAP * (rows - 1)) / rows
	if height > max_height:
		height = max_height
		width = height * ASPECT

	var sz: Vector2 = Vector2(floorf(width), floorf(height))
	if sz != _last_logged_size or columns != _last_logged_columns:
		L.debug("grid: columns=%d rows=%d cell=%s watch=%s overlay=%s" % [columns, rows, sz, _watching, _overlay_mode])
		_last_logged_size = sz
		_last_logged_columns = columns
	for i: int in count:
		_cells[i].custom_minimum_size = sz

	var grid_height: float = size.y * rows + GRID_GAP * (rows - 1)
	_panel_height = grid_height + 24.0
	if _overlay_mode:
		custom_minimum_size = Vector2.ZERO
	else:
		custom_minimum_size.y = _panel_height if _watching else 128.0
	layout_changed.emit(_panel_height)


func _index_of(user_id: int) -> int:
	for i: int in _users.size():
		if int(_users[i].get("id", -1)) == user_id:
			return i
	return -1


func _on_tile_pressed(tile: Button) -> void:
	if not tile.has_meta("user_id"):
		return
	var user_id: int = int(tile.get_meta("user_id"))
	if user_id < 0:
		return
	user_picked.emit(user_id)
