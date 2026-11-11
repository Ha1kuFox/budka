class_name BottomGradient
extends ColorRect


@export_range(0.0, 1.0, 0.01) var opacity: float = 0.9:
	set(value):
		opacity = value
		_apply()


func _ready() -> void:
	_apply()


func _apply() -> void:
	var shader_material: ShaderMaterial = material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter("opacity", opacity)
