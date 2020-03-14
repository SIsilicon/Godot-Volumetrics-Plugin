shader_type canvas_item;
render_mode blend_disabled;

uniform bool is_transmission;

uniform sampler2D current_volume;
uniform sampler2D previous_volume;

uniform sampler2D extinction_volume; // If not transmission
uniform sampler2D motion_volume;

uniform float blend : hint_range(0.0, 1.0) = 0.0;

uniform vec2 tile_factor;
uniform vec3 vol_depth_params;

uniform vec4 projection_matrix0 = vec4(1, 0, 0, 0);
uniform vec4 projection_matrix1 = vec4(0, 1, 0, 0);
uniform vec4 projection_matrix2 = vec4(0, 0, 1, 0);
uniform vec4 projection_matrix3 = vec4(0, 0, 0, 1);

uniform mat4 curr_view_matrix;
uniform mat4 prev_inv_view_matrix;

uniform bool use_light_data = false;
uniform sampler2D light_data;

const float M_PI = 3.141592653;

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
	
	//return slice0colour; //no filtering.
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

void calculate_light(int light_index, vec3 wpos, vec3 wdir, float anisotropy, inout vec3 lighting) {
	int type = int(texelFetch(light_data, ivec2(0, light_index), 0).r);
	vec3 light_pos = vec3(
		texelFetch(light_data, ivec2(1, light_index), 0).r,
		texelFetch(light_data, ivec2(2, light_index), 0).r,
		texelFetch(light_data, ivec2(3, light_index), 0).r
	);
	vec3 light_energy = vec3(
		texelFetch(light_data, ivec2(4, light_index), 0).r,
		texelFetch(light_data, ivec2(5, light_index), 0).r,
		texelFetch(light_data, ivec2(6, light_index), 0).r
	);
	
	vec4 light_dir = vec4(light_pos - wpos.xyz, 0.0);
	light_dir.w = length(light_dir.xyz);
	
	// light is not directional
	vec3 attenuation = light_energy;
	if(type != 2) {
		float range = texelFetch(light_data, ivec2(7, light_index), 0).r;
		float falloff = texelFetch(light_data, ivec2(8, light_index), 0).r;
		
		if(light_dir.w > range) return;
		
		attenuation *= pow(max(1.0 - light_dir.w/range, 0.0), falloff);
	}
	
	float phase = phase_function(wdir, light_dir.xyz / light_dir.w, 0.6);
	
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
	
	vec3 uvw = uv_to_uvw(SCREEN_UV, tile_factor);
	vec4 ndc = 2.0 * vec4(volume_to_ndc(uvw, projection_matrix), 1.0) - 1.0;
	vec4 view = inverse(projection_matrix) * ndc;
	view /= view.w;
	
	vec4 wpos = curr_view_matrix * view;
	
	if(is_transmission) {
		COLOR.rgb = volume_sample;
	} else {
		COLOR.rgb = volume_sample * 0.4;
		
		
		if(use_light_data) {
			ivec2 light_data_size = textureSize(light_data, 0);
			vec3 wdir = normalize(wpos.xyz - curr_view_matrix[3].xyz);
			vec3 lighting = vec3(0.0);
			
			for(int i = 0; i < light_data_size.y; i++) {
				calculate_light(i, wpos.xyz, wdir, 0.3, lighting);
			}
			COLOR.rgb += lighting * volume_sample;
		}
	}
	
	vec4 motion = vec4(texture(motion_volume, SCREEN_UV).xyz, 0.0);
	
	vec4 prev_ndc = projection_matrix * prev_inv_view_matrix * (wpos - motion);
	prev_ndc = (prev_ndc / prev_ndc.w) * 0.5 + 0.5;
	vec3 prev_uvw = ndc_to_volume(prev_ndc.xyz, projection_matrix);
	
	if(clamp(prev_uvw.xyz, 0.0, 1.0) == prev_uvw.xyz) {
		vec3 previous_vol_sample = texture3D(previous_volume, prev_uvw, tile_factor).rgb;
		COLOR.rgb = mix(COLOR.rgb, previous_vol_sample, blend);
	}
	
	if(any(isnan(COLOR))) {
		COLOR = vec4(0.0);
	}
}
