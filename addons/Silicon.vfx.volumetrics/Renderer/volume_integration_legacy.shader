shader_type spatial;
render_mode unshaded;

uniform sampler2D volume;
uniform vec2 volume_size;

uniform vec2 tile_factor;

uniform vec3 vol_depth_params;
uniform float distribution;
uniform float camera_near;
uniform float camera_far;
uniform bool is_orthographic = false;

uniform float density_mult = 1.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, -1.0, 1.0);
}

vec4 texture3D(sampler2D tex, vec3 uvw, vec2 tiling, float lod) {
	float zCoord = uvw.z * (tiling.x * tiling.y - 1.0);
	float zOffset = fract(zCoord);
	
	vec2 uv = uvw.xy / tiling;
	float ratio = tiling.y / tiling.x;
	vec2 slice0Offset = vec2(float(int(zCoord) % int(tiling.x)), floor(ratio * zCoord / tiling.y));
//	zCoord++;
//	vec2 slice1Offset = vec2(float(int(zCoord) % int(tiling.x)), floor(ratio * zCoord / tiling.y));
	
	vec4 slice0colour = textureLod(tex, slice0Offset/tiling + uv, lod);
//	vec4 slice1colour = textureLod(tex, slice1Offset/tiling + uv, lod);
	
	return slice0colour; //no filtering.
//	return mix(slice0colour, slice1colour, zOffset);
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

float get_ray_length(vec3 uvw, mat4 projection_matrix, mat4 inv_projection_matrix) {
	vec4 ndc1 = vec4(volume_to_ndc(uvw, projection_matrix), 1.0);
	uvw.z += 1.0 / (tile_factor.x * tile_factor.y);
	vec4 ndc2 = vec4(volume_to_ndc(uvw, projection_matrix), 1.0);
	
	ndc1 = inv_projection_matrix * ndc1;
	ndc1 /= ndc1.w;
	ndc2 = inv_projection_matrix * ndc2;
	ndc2 /= ndc2.w;
	
	return distance(ndc1, ndc2);
}

void fragment() {
	float tile_num = tile_factor.x * tile_factor.y;
	vec2 tile_margin = 1.0 / volume_size;
	
	vec4 ndc = vec4(SCREEN_UV, texture(DEPTH_TEXTURE, SCREEN_UV).r, 1.0);
	
	ndc.xyz = ndc_to_volume(ndc.xyz, PROJECTION_MATRIX);
	
	float max_depth = tile_num - 1.0;
	float start = max_depth * ndc.z;
	vec4 colour = vec4(0.0, 0.0, 0.0, 1.0);
	for(float i = 0.0; i < min(start, max_depth); i++) {
		vec3 tex_coord = vec3(clamp(SCREEN_UV, tile_margin, 1.0 - tile_margin), i / tile_num);
		vec4 vol_sample = texture3D(volume, tex_coord, tile_factor, 0.0);
		float ray_length = get_ray_length(tex_coord, PROJECTION_MATRIX, INV_PROJECTION_MATRIX) * density_mult;
		
		if(i >= start - 1.0) {
			if(vol_sample.a > 0.0) {
				float correct_depth = 1.0 - (i - start + 1.0);
				
				vec3 S = vol_sample.rgb;// incoming light
				vec3 Sint = (S - S * exp(-vol_sample.rgb * ray_length * correct_depth)) / vol_sample.rgb; // integrate along the current step segment
				colour.rgb += colour.a * Sint; // accumulate and also take into account the transmittance from previous steps
				
				// Evaluate transmittance to view independentely
				colour.a *= exp(-length(vol_sample.rgb) * ray_length * correct_depth);
				
				ALBEDO = vec3(correct_depth);
			}
			break;
		}
		
		if(vol_sample.a > 0.0) {
			vec3 S = vol_sample.rgb;// incoming light
			vec3 Sint = (S - S * exp(-vol_sample.a * ray_length)) / vol_sample.a; // integrate along the current step segment
			colour.rgb += colour.a * Sint; // accumulate and also take into account the transmittance from previous steps
			
			// Evaluate transmittance to view independentely
			colour.a *= exp(-vol_sample.a * ray_length);
		}
	}
	
	ALBEDO = colour.rgb;
	ALPHA = 1.0 - colour.a;
}
