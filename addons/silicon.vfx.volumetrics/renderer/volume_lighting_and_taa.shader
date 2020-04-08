shader_type canvas_item;
render_mode blend_disabled;

uniform bool is_transmission;

uniform sampler2D current_volume;
uniform sampler2D previous_volume;
uniform sampler2D motion_volume;

// If is not transmission
uniform sampler2D extinction_volume;
uniform sampler2D emission_volume;
uniform sampler2D phase_volume;

uniform float blend : hint_range(0.0, 1.0) = 0.0;

uniform vec2 tile_factor;
uniform vec3 vol_depth_params;
uniform vec3 sample_offset;

uniform vec4 projection_matrix0 = vec4(1, 0, 0, 0);
uniform vec4 projection_matrix1 = vec4(0, 1, 0, 0);
uniform vec4 projection_matrix2 = vec4(0, 0, 1, 0);
uniform vec4 projection_matrix3 = vec4(0, 0, 0, 1);

uniform mat4 curr_view_matrix;
uniform mat4 prev_inv_view_matrix;

uniform bool use_light_data = false;
uniform bool volumetric_shadows = true;
uniform sampler2D light_data;
uniform sampler2D shadow_atlas;

uniform vec3 ambient_light;

const float M_PI = 3.141592653;

vec4 texture3D(sampler2D tex, vec3 uvw, vec2 tiling) {
	float tile_count = tiling.x * tiling.y;
	float zCoord = uvw.z * (tile_count - 1.0);
	float zOffset = fract(zCoord);
	
	vec2 margin = 1.0 / vec2(textureSize(tex, 0));
	
	vec2 uv = uvw.xy / tiling;
	float ratio = tiling.y / tiling.x;
	vec2 slice0Offset = vec2(float(int(zCoord) % int(tiling.x)), floor(ratio * zCoord / tiling.y));
	zCoord++;
	vec2 slice1Offset = vec2(float(int(zCoord) % int(tiling.x)), floor(ratio * zCoord / tiling.y));
	
	vec4 rect0 = vec4(slice0Offset/tiling + margin, slice0Offset/tiling + 1.0 / tiling - margin);
	vec4 rect1 = vec4(slice1Offset/tiling + margin, slice1Offset/tiling + 1.0 / tiling - margin);
	
	vec4 slice0colour = texture(tex, clamp(slice0Offset/tiling + uv, rect0.xy, rect0.zw));
	vec4 slice1colour = texture(tex, clamp(slice1Offset/tiling + uv, rect1.xy, rect1.zw));
	
//	return slice0colour; //no filtering.
	return mix(slice0colour, slice1colour, zOffset);
}

vec3 uv_to_uvw(vec2 uv, vec2 tiling) {
	vec3 uvw = vec3(mod(uv * tiling, vec2(1.0)), 0.0);
	uvw.z = floor(uv.x * tiling.x) + floor(uv.y * tiling.y) * tiling.x;
	uvw.z /= tiling.x * tiling.y;
	return uvw;
}

vec2 uvw_to_uv(vec3 uvw, vec2 tiling) {
	vec2 uv = uvw.xy / tiling;
	uv.x += mod(uvw.z * tiling.y, 1.0);
	uv.y += floor(uvw.z * tiling.y) / tiling.y;
	return uv.xy;
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

float phase_function(vec3 v, vec3 l, float g) {
	/* Henyey-Greenstein */
	float cos_theta = dot(v, l);
	g = clamp(g, -1.0 + 1e-3, 1.0 - 1e-3);
	float sqr_g = g * g;
	return (1.0 - sqr_g) / max(1e-8, 4.0 * M_PI * pow(1.0 + sqr_g - 2.0 * g * cos_theta, 3.0 / 2.0));
}

vec3 participating_media_extinction(vec3 wpos, mat4 view_projection_matrix, mat4 projection_matrix) {
	vec4 ndc = view_projection_matrix * vec4(wpos, 1.0);
	ndc /= ndc.w;
	vec3 volume_co = ndc_to_volume(ndc.xyz * 0.5 + 0.5, projection_matrix);
	
	return texture3D(extinction_volume, clamp(volume_co, 0.0, 1.0), tile_factor).rgb;
}

const float VOL_SHADOW_MAX_STEPS = 32.0;

vec3 light_volume_shadow(vec3 ray_wpos, vec4 l_vector, mat4 view_projection_matrix, mat4 projection_matrix) {
	/* Heterogeneous volume shadows */
	float dd = l_vector.w / VOL_SHADOW_MAX_STEPS;
	vec3 L = l_vector.xyz * l_vector.w;
	vec3 shadow = vec3(1.0);
	for (float s = 0.5; s < VOL_SHADOW_MAX_STEPS; s += 1.0) {
		vec3 pos = ray_wpos + L * (s / VOL_SHADOW_MAX_STEPS);
		vec3 s_extinction = participating_media_extinction(pos, view_projection_matrix, projection_matrix);
		shadow *= exp(-s_extinction * dd);
	}
	
	return shadow;
}

float get_light_data(int offset, int index) {
	return texelFetch(light_data, ivec2(offset, index), 0).r;
}

vec2 cube_to_paraboloid(vec3 norm) {
	norm = normalize(norm);
	norm.x = -norm.x;
	
	norm.xy /= 1.0 + abs(norm.z);
	norm.xy = norm.xy * vec2(0.25, 0.5) + vec2(0.25, 0.5);
	
	norm.x *= step(norm.z, 0.0) * 2.0 - 1.0;
	norm.x = mod(norm.x, 1.0);
	
	return norm.xy;
}

void calculate_light(int light_index, vec3 wpos, vec3 wdir, float anisotropy, mat4 view_projection_matrix, mat4 projection_matrix, inout vec3 lighting) {
	int type = int(get_light_data(0, light_index));
	vec3 light_pos = vec3(
		get_light_data(1, light_index),
		get_light_data(2, light_index),
		get_light_data(3, light_index)
	);
	vec3 light_energy = vec3(
		get_light_data(4, light_index),
		get_light_data(5, light_index),
		get_light_data(6, light_index)
	);
	
	vec4 light_dir = vec4(light_pos, 1.0);
	
	vec3 attenuation = light_energy;
	
	// light is not directional
	float range;
	if(type != 2) {
		light_dir = vec4(light_pos - wpos, 0.0);
		light_dir.w = length(light_dir.xyz);
		
		range = get_light_data(7, light_index);
		float falloff = get_light_data(8, light_index);
		if(light_dir.w > range) return;
		
		attenuation *= pow(max(1.0 - light_dir.w/range, 0.0), falloff) * 2.0 * M_PI;
		
		if(type == 1) {
			vec3 spot_dir = vec3(
				get_light_data(9, light_index),
				get_light_data(10, light_index),
				get_light_data(11, light_index)
			);
			vec2 spot_att_angle = vec2(
				get_light_data(12, light_index),
				get_light_data(13, light_index)
			);
			float scos = max(dot(normalize(light_dir.xyz), spot_dir), spot_att_angle.y);
			float spot_rim = max(0.0001, (1.0 - scos) / (1.0 - spot_att_angle.y));
			attenuation *= 1.0 - pow(spot_rim, spot_att_angle.x);
		}
	} else {
		attenuation *= M_PI * 0.5;
	}
	
	if(all(lessThanEqual(attenuation, vec3(0.001)))) return;
	
	mat4 shadow_matrix = mat4(get_light_data(14, light_index));
	if(shadow_matrix[0][0] != 0.0) {
		shadow_matrix = mat4(
			vec4(get_light_data(14, light_index), get_light_data(15, light_index), get_light_data(16, light_index), get_light_data(17, light_index)),
			vec4(get_light_data(18, light_index), get_light_data(19, light_index), get_light_data(20, light_index), get_light_data(21, light_index)),
			vec4(get_light_data(22, light_index), get_light_data(23, light_index), get_light_data(24, light_index), get_light_data(25, light_index)),
			vec4(get_light_data(26, light_index), get_light_data(27, light_index), get_light_data(28, light_index), get_light_data(29, light_index))
		);
		vec4 shadow_rect = vec4(
			get_light_data(30, light_index), get_light_data(31, light_index), get_light_data(32, light_index), get_light_data(33, light_index)
		);
		
		vec4 shadow_coords;
		if(type == 1) {
			shadow_coords = shadow_matrix * vec4(wpos, 1.0);
			shadow_coords /= shadow_coords.w;
			shadow_coords = shadow_coords * 0.5 + 0.5;
		} else if(type == 2) {
			shadow_coords = shadow_matrix * vec4(wpos, 1.0);
			shadow_coords = shadow_coords * 0.5 + 0.5;
		} else if(type == 0) {
			shadow_coords = shadow_matrix * vec4(wpos, 1.0);
			shadow_coords.xy = cube_to_paraboloid(shadow_coords.xyz);
		}
		shadow_coords.xy = shadow_coords.xy * shadow_rect.zw + shadow_rect.xy;
		
		if(type == 2 && texture(shadow_atlas, shadow_coords.xy).r < shadow_coords.z) {
			return;
		} else if(type != 2 && texture(shadow_atlas, shadow_coords.xy).r < light_dir.w / range) {
			return;
		}
	}
	
	if(all(lessThanEqual(attenuation, vec3(0.0)))) return;
	
	if(volumetric_shadows) {
		attenuation *= light_volume_shadow(wpos, light_dir, view_projection_matrix, projection_matrix);
	}
	
	float phase = phase_function(wdir, light_dir.xyz / light_dir.w, anisotropy);
	lighting += attenuation * phase;
}

void fragment() {
	vec3 volume_sample = texture(current_volume, SCREEN_UV).rgb;
	
	mat4 projection_matrix = mat4(
		projection_matrix0,
		projection_matrix1,
		projection_matrix2,
		projection_matrix3
	);
	
	vec3 uvw = uv_to_uvw(SCREEN_UV, tile_factor) + sample_offset;
	vec4 ndc = 2.0 * vec4(volume_to_ndc(uvw, projection_matrix), 1.0) - 1.0;
	vec4 view = inverse(projection_matrix) * ndc;
	view /= view.w;
	
	vec4 wpos = curr_view_matrix * view;
	
	if(is_transmission) {
		COLOR.rgb = volume_sample;
	} else {
		COLOR.rgb = volume_sample * ambient_light / (4.0 * M_PI);
		COLOR.rgb += texture(emission_volume, SCREEN_UV).rgb;
		
		if(use_light_data && any(greaterThan(volume_sample, vec3(1e-5)))) {
			mat4 view_projection_matrix = projection_matrix * inverse(curr_view_matrix);
			
			float anisotropy = texture(phase_volume, SCREEN_UV).r / max(1.0, texture(phase_volume, SCREEN_UV).g);
			ivec2 light_data_size = textureSize(light_data, 0);
			vec3 wdir = normalize(wpos.xyz - curr_view_matrix[3].xyz);
			vec3 lighting = vec3(0.0);
			
			for(int i = 0; i < light_data_size.y; i++) {
				calculate_light(i, wpos.xyz, wdir, anisotropy, view_projection_matrix, projection_matrix, lighting);
			}
			COLOR.rgb += lighting * volume_sample;
		}
	}
	
	vec4 motion = vec4(texture(motion_volume, SCREEN_UV).xyz, 0.0);
	
	vec4 prev_ndc = projection_matrix * prev_inv_view_matrix * (wpos - motion);
	prev_ndc = (prev_ndc / prev_ndc.w) * 0.5 + 0.5;
	vec3 prev_uvw = ndc_to_volume(prev_ndc.xyz, projection_matrix);
	
	if(clamp(prev_uvw.xyz, 0.0, 1.0) == prev_uvw.xyz) {
		vec3 previous_vol_sample = texture3D(previous_volume, prev_uvw - sample_offset, tile_factor).rgb;
		COLOR.rgb = mix(COLOR.rgb, previous_vol_sample, blend);
	}
	
	if(any(isnan(COLOR))) {
		COLOR = vec4(0.0);
	}
}
