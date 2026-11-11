class_name ScreenRouter
extends Node


@export var main_menu: Control
@export var room: Control
@export var host_wait: Control
@export var attribution: Label

var _user_count: int = 0


func _ready() -> void:
	NetworkManager.joined.connect(_update)
	NetworkManager.left.connect(_update)
	NetworkManager.users_changed.connect(_on_users_changed)
	_update()


func _on_users_changed(users: Array) -> void:
	_user_count = users.size()
	_update()


func _update() -> void:
	var connected: bool = NetworkManager.connected
	var waiting: bool = connected and NetworkManager.is_host() and _user_count <= 1
	main_menu.visible = not connected
	attribution.visible = not connected
	room.visible = connected and not waiting
	host_wait.visible = waiting
