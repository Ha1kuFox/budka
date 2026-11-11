class_name H264Encoder
extends Node


signal access_unit_ready(data: PackedByteArray, keyframe: bool)
signal failed(message: String)

const FFMPEG: String = "ffmpeg"
const READ_CHUNK: int = 65536
const WRITE_CHUNK: int = 65536
const MAX_BUFFERED_BYTES: int = 8 * 1024 * 1024

var _stdio: FileAccess
var _stderr: FileAccess
var _pid: int = -1

var _write_thread: Thread
var _read_thread: Thread
var _error_thread: Thread

var _started: bool = false
var _running: bool = false
var _generation: int = 0
var _error: String = ""
var _stderr_tail: String = ""

var _frame_mutex: Mutex = Mutex.new()
var _frame_sem: Semaphore = Semaphore.new()
var _pending_frame: Image
var _has_pending_frame: bool = false

var _buffer: PackedByteArray = PackedByteArray()
var _unit_start: int = -1
var _search_from: int = 0

var _width: int = 0
var _height: int = 0
var _fps: int = 0
var _bitrate_kbps: int = 0


func _exit_tree() -> void:
	stop()


func start(width: int, height: int, fps: int, bitrate_kbps: int) -> Error:
	if _started:
		return ERR_ALREADY_IN_USE

	_width = maxi(width - width % 2, 2)
	_height = maxi(height - height % 2, 2)
	_fps = maxi(fps, 1)
	_bitrate_kbps = maxi(bitrate_kbps, 100)
	L.info("encoder: start %dx%d @ %d fps, %d kbps" % [_width, _height, _fps, _bitrate_kbps])

	var result: Dictionary = OS.execute_with_pipe(FFMPEG, _build_args(), true)
	_stdio = result.get("stdio") as FileAccess
	_stderr = result.get("stderr") as FileAccess
	_pid = int(result.get("pid", -1))

	if _stdio == null or _pid <= 0:
		failed.emit("ffmpeg is not available")
		return ERR_CANT_CREATE

	_started = true
	_running = true
	_generation += 1

	_frame_mutex.lock()
	_pending_frame = null
	_has_pending_frame = false
	_frame_mutex.unlock()
	_error = ""
	_stderr_tail = ""
	_buffer.clear()
	_unit_start = -1
	_search_from = 0

	_write_thread = Thread.new()
	_write_thread.start(_write_loop)
	_read_thread = Thread.new()
	_read_thread.start(_read_loop)
	if _stderr != null:
		_error_thread = Thread.new()
		_error_thread.start(_error_loop)

	return OK


func stop() -> void:
	if not _started:
		return

	L.info("encoder: stop")
	_generation += 1
	_started = false
	_running = false
	_frame_sem.post()

	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1

	_join(_write_thread)
	_join(_read_thread)
	_join(_error_thread)
	_write_thread = null
	_read_thread = null
	_error_thread = null

	if _stdio != null:
		_stdio.close()
		_stdio = null
	if _stderr != null:
		_stderr.close()
		_stderr = null


func push_frame(image: Image) -> void:
	if not _started or image == null:
		return

	_frame_mutex.lock()
	_pending_frame = image
	_has_pending_frame = true
	_frame_mutex.unlock()
	_frame_sem.post()


func _build_args() -> PackedStringArray:
	return PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-nostats",
		"-f", "rawvideo", "-pix_fmt", "rgba",
		"-s", "%dx%d" % [_width, _height],
		"-r", str(_fps),
		"-i", "pipe:0",
		"-an",
		"-c:v", "libx264",
		"-preset", "ultrafast",
		"-tune", "zerolatency",
		"-profile:v", "main",
		"-bf", "0",
		"-g", str(_fps),
		"-keyint_min", str(_fps),
		"-sc_threshold", "0",
		"-b:v", "%dk" % _bitrate_kbps,
		"-maxrate", "%dk" % _bitrate_kbps,
		"-bufsize", "%dk" % _bitrate_kbps,
		"-pix_fmt", "yuv420p",
		"-bsf:v", "h264_metadata=aud=insert",
		"-f", "h264", "pipe:1",
	])


func _write_loop() -> void:
	while _running:
		_frame_sem.wait()
		if not _running:
			break

		var image: Image = _take_frame()
		if image == null:
			continue

		var data: PackedByteArray = _prepare(image)
		if data.is_empty():
			continue

		if not _write_all(data):
			_fail("encoder pipe closed")
			break


func _take_frame() -> Image:
	_frame_mutex.lock()
	var image: Image = _pending_frame
	_pending_frame = null
	_has_pending_frame = false
	_frame_mutex.unlock()
	return image


func _prepare(image: Image) -> PackedByteArray:
	var prepared: Image = image
	if prepared.get_format() != Image.FORMAT_RGBA8:
		prepared = prepared.duplicate() as Image
		prepared.convert(Image.FORMAT_RGBA8)
	prepared = _cover(prepared, _width, _height)
	return prepared.get_data()


func _cover(image: Image, width: int, height: int) -> Image:
	var size: Vector2i = image.get_size()
	if size == Vector2i(width, height):
		return image

	var scale: float = maxf(float(width) / float(size.x), float(height) / float(size.y))
	var scaled: Vector2i = Vector2i(ceili(size.x * scale), ceili(size.y * scale))
	var resized: Image = image.duplicate() as Image
	resized.resize(scaled.x, scaled.y, Image.INTERPOLATE_BILINEAR)

	var offset: Vector2i = Vector2i((scaled.x - width) / 2, (scaled.y - height) / 2)
	return resized.get_region(Rect2i(offset, Vector2i(width, height)))


func _write_all(data: PackedByteArray) -> bool:
	var offset: int = 0
	while offset < data.size():
		var end: int = mini(offset + WRITE_CHUNK, data.size())
		if not _stdio.store_buffer(data.slice(offset, end)):
			return false
		offset = end
	return true


func _read_loop() -> void:
	while _running:
		var chunk: PackedByteArray = _stdio.get_buffer(READ_CHUNK)
		if chunk.is_empty():
			break
		_consume(chunk)

	if _running:
		_fail("encoder process ended")


func _error_loop() -> void:
	while _running:
		var chunk: PackedByteArray = _stderr.get_buffer(4096)
		if chunk.is_empty():
			break
		_stderr_tail = (_stderr_tail + chunk.get_string_from_utf8()).right(2048)


func _consume(chunk: PackedByteArray) -> void:
	_buffer.append_array(chunk)

	while true:
		var aud: int = _find_aud(_buffer, _search_from)
		if aud < 0:
			break
		if _unit_start < 0:
			_unit_start = 0
		elif aud > _unit_start:
			_emit_access_unit(_buffer.slice(_unit_start, aud))
			_unit_start = aud
		_search_from = aud + 4

	if _unit_start < 0:
		if _buffer.size() > MAX_BUFFERED_BYTES:
			_buffer.clear()
			_search_from = 0
		return

	if _unit_start > 0:
		_buffer = _buffer.slice(_unit_start)
		_search_from = maxi(_search_from - _unit_start, 0)
		_unit_start = 0


func _emit_access_unit(unit: PackedByteArray) -> void:
	call_deferred("_deferred_access_unit", unit, _has_idr(unit), _generation)


func _deferred_access_unit(unit: PackedByteArray, keyframe: bool, generation: int) -> void:
	if _started and generation == _generation:
		access_unit_ready.emit(unit, keyframe)


func _fail(message: String) -> void:
	if not _started or not _error.is_empty():
		return
	var detail: String = _stderr_tail.strip_edges()
	_error = message if detail.is_empty() else "%s (%s)" % [message, detail]
	call_deferred("_deferred_fail")


func _deferred_fail() -> void:
	if _started:
		failed.emit(_error)


static func _find_aud(data: PackedByteArray, from: int) -> int:
	var i: int = maxi(from, 0)
	var last: int = data.size() - 4
	while i <= last:
		if data[i] == 0 and data[i + 1] == 0 and data[i + 2] == 1 and data[i + 3] == 9:
			return i
		i += 1
	return -1


static func _has_idr(unit: PackedByteArray) -> bool:
	var i: int = 0
	var last: int = unit.size() - 4
	while i <= last:
		if unit[i] == 0 and unit[i + 1] == 0 and unit[i + 2] == 1:
			if (unit[i + 3] & 0x1F) == 5:
				return true
			i += 3
		else:
			i += 1
	return false


func _join(thread: Thread) -> void:
	if thread != null and thread.is_started():
		thread.wait_to_finish()
