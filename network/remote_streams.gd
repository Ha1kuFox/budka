class_name RemoteStreams
extends Node


signal texture_ready(user_id: int, texture: Texture2D)
signal stream_removed(user_id: int)
signal stream_failed(user_id: int, message: String)

@export var stream_size: Vector2i = Vector2i(1280, 720)

var _decoders: Dictionary = {}
var _textures: Dictionary = {}


func _ready() -> void:
	L.info("stream: RemoteStreams ready")


func push_unit(user_id: int, data: PackedByteArray, keyframe: bool) -> void:
	var decoder: H264Decoder = _decoders.get(user_id) as H264Decoder
	if decoder == null:
		if not keyframe:
			return
		L.info("stream: decoder start user=%d size=%s" % [user_id, stream_size])
		decoder = H264Decoder.new()
		add_child(decoder)
		var size: Vector2i = stream_size
		var result: Error = decoder.start(size.x - size.x % 2, size.y - size.y % 2)
		if result != OK:
			decoder.queue_free()
			return
		decoder.frame_ready.connect(_on_frame.bind(user_id))
		decoder.failed.connect(_on_failed.bind(user_id))
		_decoders[user_id] = decoder

	decoder.push_access_unit(data)


func drop(user_id: int) -> void:
	L.info("stream: drop user=%d" % user_id)
	var decoder: H264Decoder = _decoders.get(user_id) as H264Decoder
	_decoders.erase(user_id)
	if decoder != null:
		decoder.stop()
		decoder.queue_free()

	_textures.erase(user_id)
	stream_removed.emit(user_id)


func clear() -> void:
	for user_id: int in _decoders.keys().duplicate():
		drop(user_id)


func prune(users: Array) -> void:
	var valid: Dictionary = {}
	for user: Dictionary in users:
		if bool(user.get("streaming", false)):
			valid[int(user.get("id", -1))] = true

	for user_id: int in _decoders.keys().duplicate():
		if not valid.has(user_id):
			drop(user_id)


func get_texture(user_id: int) -> Texture2D:
	return _textures.get(user_id) as Texture2D


func has_texture(user_id: int) -> bool:
	return _textures.has(user_id)


func _on_frame(image: Image, user_id: int) -> void:
	var first: bool = not _textures.has(user_id)
	var texture: ImageTexture = _textures.get(user_id) as ImageTexture
	if texture == null or texture.get_size() != Vector2(image.get_size()):
		texture = ImageTexture.create_from_image(image)
		_textures[user_id] = texture
	else:
		texture.update(image)

	if first:
		L.info("stream: first frame user=%d" % user_id)
		texture_ready.emit(user_id, texture)


func _on_failed(message: String, user_id: int) -> void:
	L.warn("stream: user=%d decoder failed: %s" % [user_id, message])
	stream_failed.emit(user_id, message)
	drop(user_id)
