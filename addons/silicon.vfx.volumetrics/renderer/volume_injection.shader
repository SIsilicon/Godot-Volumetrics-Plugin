shader_type spatial;
render_mode unshaded, blend_add;

uniform bool visible;
//uniform vec2 min_max_depth;

uniform int bounds_mode = 0;
uniform vec3 bounds_extents = vec3(1.0);
uniform vec3 bounds_fade = vec3(0.0);

uniform vec2 tile_factor;
uniform vec3 sample_offset = vec3(0.0);
uniform vec3 vol_depth_params;

/**GLOBALS**/

varying flat mat4 INV_WORLD_MATRIX;

void vertex() {
	if(visible) {
		POSITION = vec4(VERTEX, 1.0);
		INV_WORLD_MATRIX = inverse(WORLD_MATRIX);
	} else {
		POSITION = vec4(-1.0, -1.0, -1.0, 1.0);
	}
}

vec3 volume_to_ndc(vec3 coords, mat4 projection_matrix) {
	float z = (exp2(coords.z / vol_depth_params.z) - vol_depth_params.x) / vol_depth_params.y;
	z = (-projection_matrix[3][2] / z) - projection_matrix[2][2];
	z = z * 0.5 + 0.5;
	return vec3(coords.xy, z);
}

vec3 ndc_to_volume(vec3 coords, mat4 projection_matrix) {
	float z = 2.0 * coords.z - 1.0;
	z = -projection_matrix[3][2] / (z + projection_matrix[2][2]);
	z = vol_depth_params.z * log2(z * vol_depth_params.y + vol_depth_params.x);
	return vec3(coords.xy, z);
}

vec3 uv_to_uvw(vec2 uv, vec2 tiling) {
	vec3 uvw = vec3(mod(uv * tiling, vec2(1.0)), 0.0);
	uvw.z = floor(uv.x * tiling.x) + floor(uv.y * tiling.y) * tiling.x;
	uvw.z /= tiling.x * tiling.y;
	return uvw;
}

void fragment() {
	ALBEDO = vec3(0.0);
	
	vec4 ndc = vec4(uv_to_uvw(SCREEN_UV, tile_factor) + sample_offset, 1.0);
//	if(ndc.z < min_max_depth.x || ndc.z > min_max_depth.y) discard;
	
	ndc.xyz = volume_to_ndc(ndc.xyz, PROJECTION_MATRIX);
	ndc.xyz = ndc.xyz * 2.0 - 1.0;
	ndc.x *= tile_factor.y / tile_factor.x;
	
	ndc = INV_PROJECTION_MATRIX * ndc;
	ndc /= ndc.w;
	ndc = CAMERA_MATRIX * ndc;
	
	vec3 WORLD = ndc.xyz;
	vec3 UVW = (INV_WORLD_MATRIX * vec4(WORLD, 1.0)).xyz / bounds_extents * 0.5 + 0.5;
	
	float FADE = 1.0;
	if(bounds_mode == 1) {
		if(clamp(UVW, 0.0, 1.0) != UVW) discard;
		
		vec3 b = max(bounds_fade, 1e-5);
		vec3 blend = 1.0 - max(2.0 * abs((UVW - 0.5) / b) - 1.0/b + 1.0, 0.0);
		blend = smoothstep(vec3(0.0), vec3(1.0), blend);
		FADE *= min(min(blend.x, blend.y), blend.z);
	} else if(bounds_mode == 2) {
		if(distance(UVW, vec3(0.5)) > 0.5) discard;
		
		float b = max(max(bounds_fade.x, max(bounds_fade.y, bounds_fade.z)), 1e-5);
		float d = distance(UVW, vec3(0.5));
		float blend = 1.0 - max(2.0 * abs(d / b) - 1.0/b + 1.0, 0.0);
		blend = smoothstep(0.0, 1.0, blend);
		FADE *= blend;
	}
	
	/**FRAGMENT CODE**/
}
