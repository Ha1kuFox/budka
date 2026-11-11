class_name H264Decoder
extends Node


signal frame_ready(image: Image)
signal failed(message: String)

const FFMPEG: String = "ffmpeg"
const READ_CHUNK: int = 65536
const WRITE_CHUNK: int = 65536

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

var _input_mutex: Mutex = Mutex.new()
var _input_sem: Semaphore = Semaphore.new()
var _input: Array[PackedByteArray] = []

var _width: int = 0
var _height: int = 0
var _frame_bytes: int = 0


func _exit_tree() -> void:
	stop()


func start(width: int, height: int) -> Error:
	if _started:
		return ERR_ALREADY_IN_USE

	_width = maxi(width - width % 2, 2)
	_height = maxi(height - height % 2, 2)
	_frame_bytes = _width * _height * 4
	L.info("decoder: start %dx%d" % [_width, _height])

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

	_input_mutex.lock()
	_input.clear()
	_input_mutex.unlock()
	_error = ""
	_stderr_tail = ""

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

	L.info("decoder: stop")
	_generation += 1
	_started = false
	_running = false
	_input_sem.post()

	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1

	_join(_write_thread)
	_join(_read_thread)
	_join(_error_thread)
	_write_thread = null
	_read_thread = null
	_error_thread = null

	_input_mutex.lock()
	_input.clear()
	_input_mutex.unlock()

	if _stdio != null:
		_stdio.close()
		_stdio = null
	if _stderr != null:
		_stderr.close()
		_stderr = null


func push_access_unit(data: PackedByteArray) -> void:
	if not _started or data.is_empty():
		return

	_input_mutex.lock()
	_input.push_back(data)
	_input_mutex.unlock()
	_input_sem.post()


func _build_args() -> PackedStringArray:
	return PackedStringArray([
		"-hide_banner", "-loglevel", "error", "-nostats",
		"-probesize", "32", "-analyzeduration", "0",
		"-threads", "1",
		"-f", "h264",
		"-i", "pipe:0",
		"-an",
		"-flags", "low_delay",
		"-fps_mode", "passthrough",
		"-f", "rawvideo", "-pix_fmt", "rgba",
		"pipe:1",
	])


func _write_loop() -> void:
	while _running:
		_input_sem.wait()
		if not _running:
			break

		var unit: PackedByteArray = _pop_input()
		if unit.is_empty():
			continue

		if not _write_all(unit):
			_fail("decoder pipe closed")
			break


func _pop_input() -> PackedByteArray:
	_input_mutex.lock()
	var unit: PackedByteArray = PackedByteArray()
	if not _input.is_empty():
		unit = _input[0]
		_input.remove_at(0)
	_input_mutex.unlock()
	return unit


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
		var frame: PackedByteArray = _read_frame()
		if frame.is_empty():
			break

		var image: Image = Image.create_from_data(
				_width, _height, false, Image.FORMAT_RGBA8, frame)
		call_deferred("_deferred_frame", image, _generation)

	if _running:
		_fail("decoder process ended")


func _read_frame() -> PackedByteArray:
	var frame: PackedByteArray = PackedByteArray()
	while frame.size() < _frame_bytes:
		var want: int = mini(READ_CHUNK, _frame_bytes - frame.size())
		var chunk: PackedByteArray = _stdio.get_buffer(want)
		if chunk.is_empty():
			return PackedByteArray()
		frame.append_array(chunk)
	return frame


func _error_loop() -> void:
	while _running:
		var chunk: PackedByteArray = _stderr.get_buffer(4096)
		if chunk.is_empty():
			break
		_stderr_tail = (_stderr_tail + chunk.get_string_from_utf8()).right(2048)


func _deferred_frame(image: Image, generation: int) -> void:
	if _started and generation == _generation:
		frame_ready.emit(image)


func _fail(message: String) -> void:
	if not _started or not _error.is_empty():
		return
	var detail: String = _stderr_tail.strip_edges()
	_error = message if detail.is_empty() else "%s (%s)" % [message, detail]
	call_deferred("_deferred_fail")


func _deferred_fail() -> void:
	if _started:
		failed.emit(_error)


func _join(thread: Thread) -> void:
	if thread != null and thread.is_started():
		thread.wait_to_finish()
