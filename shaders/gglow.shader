shader_type spatial;
render_mode blend_add,depth_draw_opaque,cull_back,unshaded;
uniform vec4 colorx:hint_color;

void fragment() {
	ALBEDO = colorx.rgb;
	vec3 rd=normalize(((CAMERA_MATRIX*vec4(normalize(-VERTEX),0.0)).xyz));
	
	float intensity = pow(0.122 + max(dot(NORMAL, normalize(VIEW)),0.), 010.85);
	ALPHA=intensity;
	
	//depth only to have smooth edges on intersect objects
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	depth = depth * 2.0 - 1.0;
	float z = -PROJECTION_MATRIX[3][2] / (depth + PROJECTION_MATRIX[2][2]);
	z*=0.31;
	depth=1.+z;
	depth=1.-clamp(depth,0.,1.);
	
	ALPHA=ALPHA*depth;

}