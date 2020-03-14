shader_type spatial;
render_mode unshaded, blend_mul;

uniform sampler2D volume_transmittance;

uniform vec2 volume_size;
uniform vec2 tile_factor;

uniform vec3 vol_depth_params;

void vertex() {
	POSITION = vec4(VERTEX.xy, -1.0, 1.0);
}

vec4 cubic(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) * (1.0/6.0);
}

vec4 texture_bicubic(sampler2D sampler, vec2 tex_coords) {
	vec2 tex_size = vec2(textureSize(sampler, 0));
	vec2 inv_tex_size = 1.0 / tex_size;
	
	tex_coords = tex_coords * tex_size - 0.5;
	
	vec2 fxy = fract(tex_coords);
	tex_coords -= fxy;
	
	vec4 xcubic = cubic(fxy.x);
	vec4 ycubic = cubic(fxy.y);
	
	vec4 c = tex_coords.xxyy + vec2 (-0.5, +1.5).xyxy;
	
	vec4 s = vec4(xcubic.xz + xcubic.yw, ycubic.xz + ycubic.yw);
	vec4 offset = c + vec4 (xcubic.yw, ycubic.yw) / s;
	
	offset *= inv_tex_size.xxyy;
	
	vec4 sample0 = textureLod(sampler, offset.xz, 0.0);
	vec4 sample1 = textureLod(sampler, offset.yz, 0.0);
	vec4 sample2 = textureLod(sampler, offset.xw, 0.0);
	vec4 sample3 = textureLod(sampler, offset.yw, 0.0);
	
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	
	return mix(mix(sample3, sample2, sx), mix(sample1, sample0, sx), sy);
}

vec4 texture3D(sampler2D tex, vec3 uvw, vec2 tiling) {
	float zCoord = uvw.z * tiling.x * tiling.y;
	float zOffset = fract(zCoord);
	
	vec2 uv = uvw.xy / tiling;
	float ratio = tiling.y / tiling.x;
	vec2 slice0Offset = vec2(float(int(zCoord) % int(tiling.x)), floor(ratio * zCoord / tiling.y));
	zCoord++;
	vec2 slice1Offset = vec2(float(int(zCoord) % int(tiling.x)), floor(ratio * zCoord / tiling.y));
	
	vec4 slice0colour = texture_bicubic(tex, slice0Offset/tiling + uv);
	vec4 slice1colour = texture_bicubic(tex, slice1Offset/tiling + uv);
	
//	return slice0colour; //no filtering.
	return mix(slice0colour, slice1colour, zOffset);
}

vec3 ndc_to_volume(vec3 coords, mat4 projection_matrix) {
	float z = 2.0 * coords.z - 1.0;
	z = -projection_matrix[3][2] / (z + projection_matrix[2][2]);
	z = vol_depth_params.z * log2(z * vol_depth_params.y + vol_depth_params.x);
	return vec3(coords.xy, z);
}

void fragment() {
	vec3 tile_margin = 1.0 / vec3(volume_size, tile_factor.x * tile_factor.y);
	
	vec3 ndc = vec3(SCREEN_UV, texture(DEPTH_TEXTURE, SCREEN_UV).r);
	ndc = ndc_to_volume(ndc, PROJECTION_MATRIX);
	ndc = clamp(ndc, tile_margin * vec3(1,1,0), 1.0 - tile_margin);
	
	vec3 transmittance = texture3D(volume_transmittance, ndc, tile_factor).rgb;
	ALPHA = dot(transmittance, vec3(1.0 / 3.0));
	
	ALBEDO = transmittance;
}
