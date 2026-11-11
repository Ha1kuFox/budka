class_name ScreenCapture
extends Node


signal frame_ready(image: Image)
signal failed(message: String)

@export var target_fps: int = 24

@onready var _caster: DesktopCaster = $DesktopCaster

var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)


func _exit_tree() -> void:
	stop()


func start() -> Error:
	if not _timer.is_stopped():
		return OK
	L.info("capture: start")

	if not _caster.is_capturing():
		if not _caster.start():
			var reason: String = _caster.get_last_error()
			failed.emit(reason if not reason.is_empty() else "desktop capture failed")
			return ERR_CANT_CREATE

	_caster.set_target_fps_runtime(target_fps)

	_timer.wait_time = 1.0 / float(maxi(target_fps, 1))
	_timer.start()
	return OK


func stop() -> void:
	L.info("capture: stop")
	_timer.stop()
	if _caster.is_capturing():
		_caster.stop()


func _on_timeout() -> void:
	var texture: Texture2D = _caster.get_texture()
	if texture == null:
		return

	var image: Image = texture.get_image()
	if image != null:
		frame_ready.emit(image)
