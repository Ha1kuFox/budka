class_name SettingsButton
extends Button


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	get_tree().get_first_node_in_group("settings_panel").call("toggle")
