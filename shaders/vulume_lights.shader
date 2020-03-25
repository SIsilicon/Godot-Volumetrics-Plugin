shader_type spatial;
render_mode blend_add,depth_draw_never,depth_test_disable,cull_back,unshaded;

uniform sampler2D Front : hint_albedo;
uniform sampler2D Right : hint_albedo;
uniform sampler2D Left : hint_albedo;
uniform sampler2D Back : hint_albedo;
uniform sampler2D Up : hint_albedo;
uniform sampler2D Down : hint_albedo;

uniform vec3 light_pos;
uniform vec4 colorx:hint_color;

// minimal example of that logic https://www.shadertoy.com/view/XsKGRz
// Licence: no licence, use it as you wish.

// twitter.com/AruGL

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

float rand(vec3 co){
	return fract(sin(dot(co*0.123,vec3(12.9898,78.233,112.166))) * 43758.5453);
}
void mainImage( out vec4 fragColor, vec3 rd, float gd)
{
    vec3 ro = vec3 (0.,0.,0.);
	vec3 mx=vec3(1.,-1.,-1);
	rd*=mx;
	float maxdepth=max(0.01,10.*gd);
	float LIGHT_FALLOFF=50.;
	
	//correct value is 10, but 10 start before object
	float depth_mult=12.35; //set 12-14 to make it more nice(atleast not that bad) on flat objects
	
	const float steps=32.; //GLES2 does not allow not const in loop
	
	vec3 col=vec3(0.0);
	float dt=maxdepth/steps;
	float t=dt*rand(rd); //(rd+iTime)
	for(int i=0;i<int(steps);i++){
		vec3 p=ro+t*rd;
		vec3 L=(p-light_pos*mx);//light direction for shadow lookup
		float d=length(L);
		if(d<LIGHT_FALLOFF){//ignore if light is too far away
			L/=d;
			if(d<(clamp(cubemap(L).r,0.,1.))*depth_mult){
				float rangef=10.; //set 1 to have bright at light source
				col+=colorx.rgb/(rangef+10.0*d*d);
			}
		}
		t+=dt;
		if(t>maxdepth)break;
	}
	
	clamp(col,0.0,1.0);
	
    fragColor = vec4(col,1.0);
}

void fragment(){
	vec3 rd=normalize(((CAMERA_MATRIX*vec4(normalize(-VERTEX),0.0)).xyz));
	vec4 col=vec4(0.);
	
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	depth = depth * 2.0 - 1.0;
	float z = -PROJECTION_MATRIX[3][2] / (depth + PROJECTION_MATRIX[2][2]);
	z*=0.1;
	depth=1.+z;
	depth=1.-clamp(depth,0.,1.);
	
	mainImage(col, rd, depth);
	ALBEDO=col.rgb;
	
	//ALBEDO=ALBEDO*depth;
	
}
