shader_type spatial;
render_mode unshaded;

uniform bool is_transmittance;

uniform sampler2D volume_scattering;
uniform sampler2D volume_transmittance;

uniform int shader_pass;
uniform sampler2D prev_scattering;
uniform sampler2D prev_transmittance;

uniform vec2 tile_factor;
uniform vec3 vol_depth_params;

varying float prev_pass_slice;
varying float next_pass_slice;
varying float tile_num;
varying float inv_tile_num;

void vertex() {
	POSITION = vec4(VERTEX.xy, -1.0, 1.0);
	tile_num = tile_factor.x * tile_factor.y;
	inv_tile_num = 1.0 / tile_num;
	prev_pass_slice = float(shader_pass) / 1.0 * tile_num - 1.0;
	next_pass_slice = float(shader_pass + 1) / 1.0 * tile_num - 1.0;
}

vec4 texture3D_no_filter(sampler2D tex, vec3 uvw, vec2 tiling) {
	float zCoord = uvw.z * tiling.x * tiling.y;
	float zOffset = fract(zCoord);
	
	vec2 uv = uvw.xy / tiling;
	float ratio = tiling.y / tiling.x;
	
	vec2 slice0Offset = vec2(float(int(zCoord) % int(tiling.x)), floor(ratio * zCoord / tiling.y));
	vec4 slice0colour = textureLod(tex, slice0Offset/tiling + uv, 0);
	return slice0colour;
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

void fragment() {
	vec3 uvw = uv_to_uvw(SCREEN_UV, tile_factor);
	
	int slice = int(uvw.z * tile_num);
	
	vec3 final_scattering = vec3(0.0);
	vec3 final_transmittance = vec3(1.0);
	
	ALBEDO = vec3(0.0);
	if(prev_pass_slice >= 0.0) {
		if(slice <= int(prev_pass_slice)) {
			if(is_transmittance) {
				ALBEDO = textureLod(prev_transmittance, SCREEN_UV, 0).rgb;
			} else {
				ALBEDO = textureLod(prev_scattering, SCREEN_UV, 0).rgb;
			}
		} else {
			vec3 volume_cell = vec3(uvw.xy, prev_pass_slice * inv_tile_num);
			final_scattering = texture3D_no_filter(prev_scattering, volume_cell, tile_factor).rgb;
			final_transmittance = texture3D_no_filter(prev_transmittance, volume_cell, tile_factor).rgb;
		}
	}
	
	/* Compute view ray. */
	vec3 volume_cell = vec3(uvw.xy, (prev_pass_slice+1.0) * inv_tile_num);
	vec3 ndc_cell = volume_to_ndc(volume_cell, PROJECTION_MATRIX);
	vec4 view_cell = INV_PROJECTION_MATRIX * vec4(ndc_cell.xyz * 2.0 - 1.0, 1.0);
	view_cell /= view_cell.w;
	
	float prev_ray_len = length(view_cell.xyz);
	float orig_ray_len = prev_ray_len / -view_cell.z;
	
	if(slice > int(prev_pass_slice) && slice <= int(next_pass_slice)) {
		for(int i = int(prev_pass_slice)+1; i <= slice; i++) {
			volume_cell = vec3(uvw.xy, float(i) * inv_tile_num);
			
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
}
