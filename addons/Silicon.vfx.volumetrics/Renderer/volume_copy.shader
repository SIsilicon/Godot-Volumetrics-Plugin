shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D volume;

void fragment() {
	COLOR = texture(volume, SCREEN_UV);
}
