shader_type canvas_item;

uniform float opacity : hint_range(0.0, 1.0) = 0.9;

void fragment() {
	float alpha = smoothstep(0.0, 0.8, UV.y);
	COLOR = vec4(0.0, 0.0, 0.0, alpha * opacity);
}
