class_name ScreenStream
extends Node


signal frame_ready(image: Image)
signal access_unit_ready(data: PackedByteArray, keyframe: bool)
signal sharing_started
signal sharing_stopped
signal failed(message: String)

@export var stream_size: Vector2i = Vector2i(1280, 720)
@export var fps: int = 24
@export var bitrate_kbps: int = 1500
@export var local_preview: bool = true
@export var loopback: bool = true

@onready var _capture: ScreenCapture = $Capture
@onready var _encoder: H264Encoder = $Encoder
@onready var _decoder: H264Decoder = $Decoder

var _sharing: bool = false


func _ready() -> void:
	_capture.frame_ready.connect(_on_capture_frame)
	_capture.failed.connect(_on_failed)
	_encoder.access_unit_ready.connect(_on_access_unit)
	_encoder.failed.connect(_on_failed)
	_decoder.frame_ready.connect(_on_decoded_frame)
	_decoder.failed.connect(_on_failed)


func _exit_tree() -> void:
	stop_sharing()


func is_sharing() -> bool:
	return _sharing


func start_sharing() -> Error:
	if _sharing:
		return ERR_ALREADY_IN_USE

	L.info("screen: start %s @ %d fps" % [stream_size, fps])
	var size: Vector2i = Vector2i(stream_size.x - stream_size.x % 2, stream_size.y - stream_size.y % 2)

	var err: Error = _decoder.start(size.x, size.y)
	if err != OK:
		return err

	err = _encoder.start(size.x, size.y, fps, bitrate_kbps)
	if err != OK:
		_decoder.stop()
		return err

	err = _capture.start()
	if err != OK:
		_encoder.stop()
		_decoder.stop()
		return err

	_sharing = true
	L.info("screen: sharing started")
	sharing_started.emit()
	return OK


func stop_sharing() -> void:
	if not _sharing:
		return
	L.info("screen: stop sharing")

	_sharing = false
	_capture.stop()
	L.info("screen: sharing stopped")
	_encoder.stop()
	_decoder.stop()
	sharing_stopped.emit()


func push_remote_access_unit(data: PackedByteArray) -> void:
	_decoder.push_access_unit(data)


func _on_capture_frame(image: Image) -> void:
	_encoder.push_frame(image)
	if local_preview:
		frame_ready.emit(image)


func _on_access_unit(data: PackedByteArray, keyframe: bool) -> void:
	if loopback and not local_preview:
		_decoder.push_access_unit(data)
	access_unit_ready.emit(data, keyframe)


func _on_decoded_frame(image: Image) -> void:
	frame_ready.emit(image)


func _on_failed(message: String) -> void:
	stop_sharing()
	failed.emit(message)
