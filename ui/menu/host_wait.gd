class_name HostWait
extends CenterContainer


@onready var _code: Label = %HostCode
@onready var _copy: Button = %CopyCodeButton
@onready var _cancel: Button = %CancelHostButton


func _ready() -> void:
	_copy.pressed.connect(_on_copy_pressed)
	_cancel.pressed.connect(NetworkManager.leave)
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if not visible:
		return
	_code.text = NetworkManager.get_room_code()
	_copy.text = "Скопировать"


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_code.text)
	_copy.text = "Скопировано"
	L.info("room: host code copied")
