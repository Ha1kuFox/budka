extends Node

## Small logger with clickable source links in the Godot editor.
##
## Usage:
##   L.debug("...")
##   L.info("...")
##   L.warn("...")
##   L.error("...")
##   L.fatal("...") # prints the full stack, then crashes the process
##
## In the editor, messages are printed with a clickable file:line prefix that
## opens the caller in the script editor. In exported builds the same calls
## become plain console lines; debug messages are suppressed by default.

enum Level {
	DEBUG,
	INFO,
	WARN,
	ERROR,
}

const LEVEL_NAMES: Array[String] = ["DEBUG", "INFO", "WARN", "ERROR"]

## DEBUG in the editor, INFO in exported builds.
var min_level: int = Level.DEBUG if OS.has_feature("editor") else Level.INFO


func debug(message: Variant = "", stack_depth: int = 1) -> void:
	_write(Level.DEBUG, message, stack_depth)


func info(message: Variant = "", stack_depth: int = 1) -> void:
	_write(Level.INFO, message, stack_depth)


func warn(message: Variant = "", stack_depth: int = 1) -> void:
	_write(Level.WARN, message, stack_depth)


func error(message: Variant = "", stack_depth: int = 1) -> void:
	_write(Level.ERROR, message, stack_depth)


## Logs a fatal message with every available stack frame, then crashes the
## process. This is intentionally not suppressible by the log level.
func fatal(message: Variant = "") -> void:
	var text: String = str(message)
	var stack: Array[Dictionary] = get_stack()

	if OS.has_feature("editor"):
		_print_fatal_editor(text, stack)
	else:
		_print_fatal_plain(text, stack)

	get_tree().quit(999)


func set_min_level(level: int) -> void:
	min_level = clampi(level, Level.DEBUG, Level.ERROR)


func _write(level: int, message: Variant, stack_depth: int) -> void:
	if level < min_level:
		return

	var text: String = str(message)
	if not OS.has_feature("editor"):
		_print_plain(level, text)
		return

	var stack: Array[Dictionary] = get_stack()
	_print_editor(level, text, stack, stack_depth + 1)


func _print_editor(level: int, text: String, stack: Array[Dictionary], index: int) -> void:
	if index < 0 or index >= stack.size():
		_print_plain(level, text)
		return

	var entry: Dictionary = stack[index]
	var source: String = String(entry.get("source", ""))
	var line: int = int(entry.get("line", 0))
	if source.is_empty():
		_print_plain(level, text)
		return

	var url: String = "%s:%d" % [source, line]
	var label: String = _escape_bbcode(source.get_file())
	var level_name: String = LEVEL_NAMES[level]
	print_rich("[url=%s]%s:%d[/url] [%s] %s" % [url, label, line, level_name, _escape_bbcode(text)])


func _print_fatal_editor(text: String, stack: Array[Dictionary]) -> void:
	print_rich("[b][color=red][FATAL][/color][/b] %s" % _escape_bbcode(text))
	for index: int in range(1, stack.size()):
		var entry: Dictionary = stack[index]
		var source: String = String(entry.get("source", ""))
		if source.is_empty():
			continue
		var line: int = int(entry.get("line", 0))
		var function: String = _escape_bbcode(String(entry.get("function", "<anonymous>")))
		var label: String = _escape_bbcode(source.get_file())
		if source.begins_with("res://"):
			print_rich("  [url=%s:%d]%s:%d[/url] %s()" % [source, line, label, line, function])
		else:
			print_rich("  %s:%d %s()" % [label, line, function])


func _print_fatal_plain(text: String, stack: Array[Dictionary]) -> void:
	printerr("[FATAL] %s" % text)
	for index: int in range(1, stack.size()):
		var entry: Dictionary = stack[index]
		var source: String = String(entry.get("source", ""))
		if source.is_empty():
			continue
		printerr(
			"  at %s:%d %s()"
			% [source, int(entry.get("line", 0)), String(entry.get("function", "<anonymous>"))]
		)


func _print_plain(level: int, text: String) -> void:
	var line: String = "[%s] %s" % [LEVEL_NAMES[level], text]
	if level == Level.ERROR:
		printerr(line)
	else:
		print(line)


func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")
