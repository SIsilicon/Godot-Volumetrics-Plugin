shader_type canvas_item;

uniform sampler2D Front : hint_albedo;
uniform sampler2D Right : hint_albedo;
uniform sampler2D Left : hint_albedo;
uniform sampler2D Back : hint_albedo;
uniform sampler2D Up : hint_albedo;
uniform sampler2D Down : hint_albedo;

vec4 cubemap(in vec3 d)
{
	vec3 a = abs(d);
	bvec3 ip =greaterThan(d,vec3(0.));
	vec2 uvc;
	if (ip.x && a.x >= a.y && a.x >= a.z) {uvc.x = -d.z;uvc.y = d.y;
	return texture(Front,0.5 * (uvc / a.x + 1.));
	}else
	if (!ip.x && a.x >= a.y && a.x >= a.z) {uvc.x = d.z;uvc.y = d.y;
	return texture(Back,0.5 * (uvc / a.x + 1.));
	}else
	if (ip.y && a.y >= a.x && a.y >= a.z) {uvc.x = d.x;uvc.y = -d.z;
	return texture(Up,0.5 * (uvc / a.y + 1.));
	}else
	if (!ip.y && a.y >= a.x && a.y >= a.z) {uvc.x = d.x;uvc.y = d.z;
	return texture(Down,0.5 * (uvc / a.y + 1.));
	}else
	if (ip.z && a.z >= a.x && a.z >= a.y) {uvc.x = d.x;uvc.y = d.y;
	return texture(Right,0.5 * (uvc / a.z + 1.));
	}else
	if (!ip.z && a.z >= a.x && a.z >= a.y) {uvc.x = -d.x;uvc.y = d.y;
	return texture(Left,0.5 * (uvc / a.z + 1.));
	}
	return vec4(0.);
}

vec3 rotate_y(vec3 v, float angle)
{
	float ca = cos(angle); float sa = sin(angle);
	return v*mat3(
		vec3(+ca, +.0, -sa),
		vec3(+.0,+1.0, +.0),
		vec3(+sa, +.0, +ca));
}

vec3 rotate_x(vec3 v, float angle)
{
	float ca = cos(angle); float sa = sin(angle);
	return v*mat3(
		vec3(+1.0, +.0, +.0),
		vec3(+.0, +ca, -sa),
		vec3(+.0, +sa, +ca));
}

void panorama_uv(vec2 fragCoord, out vec3 ro,out vec3 rd, in vec2 iResolution){
    float M_PI = 3.1415926535;
    float ymul = 2.0; float ydiff = -1.0;
    vec2 uv = fragCoord.xy / iResolution.xy;
	uv.y=1.-uv.y;
    uv.x = 2.0 * uv.x - 1.0;
    uv.y = ymul * uv.y + ydiff;
    ro = vec3(0., 5., 0.);
    rd = normalize(rotate_y(rotate_x(vec3(0.0, 0.0, 1.0),-uv.y*M_PI/2.0),-uv.x*M_PI));
}

void mainImage( out vec4 fragColor, in vec2 fragCoord, in vec2 iResolution)
{
    vec3 ro = vec3 (0.,0.,0.);
	vec3 rd = vec3(0.);
    vec3 col=vec3(0.);

    panorama_uv(fragCoord,ro,rd,iResolution);
    
    col = cubemap(rd).rgb;
    fragColor = vec4(col,1.0);
}

void fragment(){
	vec2 iResolution=1./TEXTURE_PIXEL_SIZE;
	mainImage(COLOR,FRAGCOORD.xy,iResolution);
}
