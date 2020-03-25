shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D front;
uniform sampler2D back;
uniform sampler2D left;
uniform sampler2D right;
uniform sampler2D up;
uniform sampler2D down;

vec4 textureCubemap(vec3 uvw) {
	vec3 a = abs(uvw);
	bvec3 ip = greaterThan(uvw, vec3(0.0));
	vec2 uvc;
	if (ip.x && a.x >= a.y && a.x >= a.z) {
		uvc.x = -uvw.z; uvc.y = uvw.y;
		return texture(front, 0.5 * (uvc / a.x + 1.0));
		
	} else if (!ip.x && a.x >= a.y && a.x >= a.z) {
		uvc.x = uvw.z; uvc.y = uvw.y;
		return texture(back, 0.5 * (uvc / a.x + 1.0));
		
	} else if (ip.y && a.y >= a.x && a.y >= a.z) {
		uvc.x = uvw.x; uvc.y = -uvw.z;
		return texture(up, 0.5 * (uvc / a.y + 1.0));
		
	} else if (!ip.y && a.y >= a.x && a.y >= a.z) {
		uvc.x = uvw.x; uvc.y = uvw.z;
		return texture(down, 0.5 * (uvc / a.y + 1.0));
		
	} else if (ip.z && a.z >= a.x && a.z >= a.y) {
		uvc.x = uvw.x; uvc.y = uvw.y;
		return texture(right, 0.5 * (uvc / a.z + 1.0));
		
	} else if (!ip.z && a.z >= a.x && a.z >= a.y) {
		uvc.x = -uvw.x; uvc.y = uvw.y;
		return texture(left, 0.5 * (uvc / a.z + 1.0));
		
	}
	return vec4(0.0);
}

vec3 paraboloid_to_cube(vec2 uv) {
	vec2 new_uv = uv * vec2(2.0, 1.0);
	if(uv.x > 0.5)
		new_uv.x = 2.0 - new_uv.x;
	
	vec3 norm = vec3(new_uv * 2.0 - 1.0, 0.0);
	norm.z = (0.5 - 0.5 * dot(norm.xy, norm.xy)) * (step(uv.x, 0.5) * 2.0 - 1.0);
	norm.z *= -1.0;
	norm = normalize(norm);
	return norm;
}

void fragment() {
	vec3 uvw = paraboloid_to_cube(UV);
	COLOR = textureCubemap(uvw);
}
