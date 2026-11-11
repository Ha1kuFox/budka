@tool
extends EditorPlugin


func _enable_plugin() -> void:
	add_autoload_singleton("Con", "res://addons/conn/conn.gd")


func _disable_plugin() -> void:
	remove_autoload_singleton("Con")
