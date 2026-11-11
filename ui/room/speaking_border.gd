class_name SpeakingBorder
extends Panel


const SPEAKING_COLOR: Color = Color(0.180392, 0.760784, 0.494118)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = SPEAKING_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	add_theme_stylebox_override("panel", style)
	visible = false


func set_speaking(speaking: bool) -> void:
	visible = speaking
