shader_type spatial;
render_mode unshaded;

uniform bool is_transmittance;

uniform sampler2D volume_scattering;
uniform sampler2D volume_transmittance;

uniform vec2 tile_factor;
uniform vec3 vol_depth_params;

void vertex() {
	POSITION = vec4(VERTEX.xy, -1.0, 1.0);
}

vec4 texture3D_no_filter(sampler2D tex, vec3 uvw, vec2 tiling) {
	float zCoord = uvw.z * tiling.x * tiling.y;
	float zOffset = fract(zCoord);
	
	vec2 uv = uvw.xy / tiling;
	float ratio = tiling.y / tiling.x;
	
	vec2 slice0Offset = vec2(float(int(zCoord) % int(tiling.x)), floor(ratio * zCoord / tiling.y));
	vec4 slice0colour = texture(tex, slice0Offset/tiling + uv);
	return slice0colour;
}

vec4 texture3D(sampler2D tex, vec3 uvw, vec2 tiling) {
	float zCoord = uvw.z * tiling.x * tiling.y;
	float zOffset = fract(zCoord);
	
	vec2 uv = uvw.xy / tiling;
	float ratio = tiling.y / tiling.x;
	vec2 slice0Offset = vec2(float(int(zCoord) % int(tiling.x)), floor(ratio * zCoord / tiling.y));
	zCoord++;
	vec2 slice1Offset = vec2(float(int(zCoord) % int(tiling.x)), floor(ratio * zCoord / tiling.y));
	
	vec4 slice0colour = texture(tex, slice0Offset/tiling + uv);
	vec4 slice1colour = texture(tex, slice1Offset/tiling + uv);
	
//	return slice0colour; //no filtering.
	return mix(slice0colour, slice1colour, zOffset);
}

vec3 uv_to_uvw(vec2 uv, vec2 tiling) {
	vec3 uvw = vec3(mod(uv * tiling, vec2(1.0)), 0.0);
	uvw.z = floor(uv.x * tiling.x) + floor(uv.y * tiling.y) * tiling.x;
	uvw.z /= tiling.x * tiling.y;
	return uvw;
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

void fragment() {
	vec3 uvw = uv_to_uvw(SCREEN_UV, tile_factor);
	float tile_num = tile_factor.x * tile_factor.y;
	float inv_tile_num = 1.0 / tile_num;
	
	vec3 final_scattering = vec3(0.0);
	vec3 final_transmittance = vec3(1.0);
	
	/* Compute view ray. */
	vec3 ndc_cell = volume_to_ndc(vec3(uvw.xy, 1e-5), PROJECTION_MATRIX);
	vec4 view_cell = PROJECTION_MATRIX * vec4(ndc_cell.xyz * 2.0 - 1.0, 1.0);
	view_cell /= view_cell.w;
	
	/* Ortho */
	float prev_ray_len = view_cell.z;
	float orig_ray_len = 1.0;
	
	/* Persp */
	if (PROJECTION_MATRIX[3][3] == 0.0) {
		prev_ray_len = length(view_cell);
		orig_ray_len = prev_ray_len / view_cell.z;
	}
	
	int slice = int(uvw.z * tile_num);
	for (int i = 0; i <= slice; i++) {
		vec3 volume_cell = vec3(uvw.xy, float(i) * inv_tile_num);
		
		vec3 Lscat = texture3D_no_filter(volume_scattering, volume_cell, tile_factor).rgb;
		vec3 s_extinction = texture3D_no_filter(volume_transmittance, volume_cell, tile_factor).rgb;
		
		float cell_depth = (float(i) + 1.0) * inv_tile_num;
		cell_depth = (exp2(cell_depth / vol_depth_params.z) - vol_depth_params.x) / vol_depth_params.y;
		float ray_len = orig_ray_len * cell_depth;
		
		s_extinction = max(vec3(1e-7) * step(1e-5, Lscat), s_extinction);
		
		/* Evaluate Scattering */
		float s_len = abs(ray_len - prev_ray_len);
		prev_ray_len = ray_len;
		vec3 Tr = exp(-s_extinction * s_len);
		
		if(!is_transmittance) {
			/* integrate along the current step segment */
			Lscat = (Lscat - Lscat * Tr) / max(vec3(1e-8), s_extinction);
			/* accumulate and also take into account the transmittance from previous steps */
			final_scattering += final_transmittance * Lscat;
		}
		final_transmittance *= Tr;
	}
	
	ALBEDO = is_transmittance ? final_transmittance : final_scattering;
}
