class_name StreamBroadcaster
extends Node


signal texture_changed(texture: Texture2D)
signal sharing_changed(active: bool)
signal failed(message: String)

@onready var _stream: ScreenStream = get_parent() as ScreenStream

var _active: bool = false
var _texture: ImageTexture


func _enter_tree() -> void:
	add_to_group("stream_broadcaster")


func _ready() -> void:
	_stream.frame_ready.connect(_on_frame)
	_stream.failed.connect(_on_failed)
	_stream.access_unit_ready.connect(_on_access_unit)
	NetworkManager.left.connect(_on_left)


func is_active() -> bool:
	return _active


func get_texture() -> Texture2D:
	return _texture


func set_enabled(enabled: bool) -> void:
	if enabled == _active:
		return

	if enabled:
		var error: Error = _stream.start_sharing()
		if error != OK:
			sharing_changed.emit(false)
			failed.emit("screen capture failed: %s" % error_string(error))
			return
		_active = true
		NetworkManager.set_streaming(true)
	else:
		_stream.stop_sharing()
		_active = false
		_texture = null
		NetworkManager.set_streaming(false)
		texture_changed.emit(null)

	sharing_changed.emit(_active)


func _on_frame(image: Image) -> void:
	if _texture == null or _texture.get_size() != Vector2(image.get_size()):
		_texture = ImageTexture.create_from_image(image)
	else:
		_texture.update(image)
	texture_changed.emit(_texture)


func _on_access_unit(data: PackedByteArray, keyframe: bool) -> void:
	NetworkManager.send_stream(data, keyframe)


func _on_failed(message: String) -> void:
	_active = false
	failed.emit(message)
	sharing_changed.emit(false)
	texture_changed.emit(null)


func _on_left() -> void:
	if _active:
		_stream.stop_sharing()
		_active = false
		_texture = null
		sharing_changed.emit(false)
		texture_changed.emit(null)
