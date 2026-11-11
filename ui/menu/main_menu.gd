class_name MainMenu
extends CenterContainer


@onready var _uid: LineEdit = %UIDInput
@onready var _connect: Button = %ConnectButton
@onready var _host: Button = %HostButton


func _ready() -> void:
	_connect.pressed.connect(func() -> void: NetworkManager.join(_uid.text))
	_host.pressed.connect(NetworkManager.host)
