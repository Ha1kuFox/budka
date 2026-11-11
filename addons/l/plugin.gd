@tool
extends EditorPlugin

## Adds the L autoload and attaches a small listener to the editor's Output
## panel so L messages like "script.gd:42" are clickable.

const AUTOLOAD_NAME: String = "L"
const AUTOLOAD_PATH: String = "res://addons/l/l.gd"
const LISTENER_SCRIPT: GDScript = preload("res://addons/l/output_listener.gd")

var _output_panel: RichTextLabel
var _listener: Node
var _retry_accum: float = 0.0


func _enter_tree() -> void:
	_attach_listener()
	set_process(not is_instance_valid(_listener))


func _process(delta: float) -> void:
	if is_instance_valid(_listener):
		set_process(false)
		return
	_retry_accum += delta
	if _retry_accum < 0.25:
		return
	_retry_accum = 0.0
	_attach_listener()
	if is_instance_valid(_listener):
		set_process(false)


func _attach_listener() -> void:
	if is_instance_valid(_listener):
		return
	_output_panel = _find_output_panel()
	if _output_panel == null:
		return
	_listener = LISTENER_SCRIPT.new()
	_output_panel.add_child(_listener)


func _exit_tree() -> void:
	set_process(false)
	if is_instance_valid(_listener):
		if is_instance_valid(_output_panel) and _listener.get_parent() == _output_panel:
			_output_panel.remove_child(_listener)
		_listener.free()
	_listener = null


func _enable_plugin() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)


func _find_output_panel() -> RichTextLabel:
	var editor_log: Node = _find_editor_log(get_tree().root)
	if editor_log == null:
		return null
	var label: Node = editor_log.find_child("*RichTextLabel*", true, false)
	if label is RichTextLabel:
		return label
	return null


func _find_editor_log(node: Node) -> Node:
	# Godot 4.7 renamed the EditorLog node to "Output", so class detection is
	# required; keep the name fallback for older editors.
	if node.get_class() == "EditorLog" or node.name.contains("EditorLog"):
		return node
	for child: Node in node.get_children():
		var found: Node = _find_editor_log(child)
		if found != null:
			return found
	return null
