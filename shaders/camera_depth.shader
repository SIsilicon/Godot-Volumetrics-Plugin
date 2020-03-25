shader_type spatial;
render_mode blend_mix,depth_draw_never,depth_test_disable,cull_back,unshaded;

void fragment() {
	//depth, I do not know other way to get viewport depth texture in Godot
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	depth = depth * 2.0 - 1.0;
	float z = -PROJECTION_MATRIX[3][2] / (depth + PROJECTION_MATRIX[2][2]);
	//float x = (SCREEN_UV.x * 2.0 - 1.0) * z / PROJECTION_MATRIX[0][0];
	//float y = (SCREEN_UV.y * 2.0 - 1.0) * z / PROJECTION_MATRIX[1][1];
	z*=0.1;
	depth=1.+z;
	depth=1.-clamp(depth,0.,1.);
	ALBEDO=vec3(depth);
}