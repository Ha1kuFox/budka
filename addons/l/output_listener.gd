@tool
extends Node

## Attached by the logger editor plugin to the EditorLog RichTextLabel.
## Opens the source location encoded in a logger message's link.

var _output_panel: RichTextLabel


func _ready() -> void:
	# Godot 4.7's EditorLog already handles res://path:line metadata itself.
	# The listener is only needed by older editors.
	var version: Dictionary = Engine.get_version_info()
	var major: int = int(version["major"])
	var minor: int = int(version["minor"])
	if major > 4 or (major == 4 and minor >= 7):
		return

	var parent: Node = get_parent()
	if parent is RichTextLabel:
		var output_panel: RichTextLabel = parent
		_output_panel = output_panel
		_output_panel.meta_clicked.connect(_on_meta_clicked)


func _on_meta_clicked(meta: String) -> void:
	if not OS.has_feature("editor"):
		return

	var colon: int = meta.rfind(":")
	if colon <= 0:
		return
	var source: String = meta.substr(0, colon)
	if not source.begins_with("res://"):
		return

	var resource: Resource = load(source)
	if resource is Script:
		var script: Script = resource
		EditorInterface.edit_script(script, int(meta.substr(colon + 1)))
		EditorInterface.set_main_screen_editor("Script")
