tool
extends Resource
class_name VolumetricMaterial, "volumetric_material.svg"

const SHADER_TEMPLATE = preload("../renderer/volume_injection.shader")

signal shader_changed

enum {
	SCATTER_TEX = 1
	USE_EMISSION = 2
	EMISSION_TEX = 4
	MAX_FLAG = 512
}

var scatter_color := Color.gray setget set_scatter_color
var density := 1.0 setget set_density
var scatter_texture : Texture3D setget set_scatter_texture
var absorption_color := Color.black setget set_absorption_color
var anisotropy := 0.0 setget set_anisotropy

var emission_enabled := false setget set_emission_enabled
var emission_color := Color.white setget set_emission_color
var emission_strength := 0.0 setget set_emission_strength
var emission_texture : Texture3D setget set_emission_texture

var uvw_scale := Vector3.ONE setget set_uvw_scale
var uvw_offset := Vector3.ZERO setget set_uvw_offset

var material_flags := MAX_FLAG
var material_flags_dirty := false

# One shader per v-buffer (Scatter, Extinction, Emission, Phase, Motion)
# See volume_renderer.gd (add_volume)
var shaders := [Shader.new(), Shader.new(), Shader.new(), Shader.new(), Shader.new()]
var volumes = []

func _get_property_list() -> Array:
	var properties := [
		{name="VolumetricMaterial", type=TYPE_NIL, usage=PROPERTY_USAGE_CATEGORY},
		{name="scatter_color", type=TYPE_COLOR, hint=PROPERTY_HINT_COLOR_NO_ALPHA},
		{name="density", type=TYPE_REAL},
		{name="scatter_texture", type=TYPE_OBJECT, hint=PROPERTY_HINT_RESOURCE_TYPE, hint_string="Texture3D"},
		{name="absorption_color", type=TYPE_COLOR, hint=PROPERTY_HINT_COLOR_NO_ALPHA},
		{name="anisotropy", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="-1,1"},
	]
	
	properties += [
		{name="Emission", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP, hint_string="emission_"},
		{name="emission_enabled", type=TYPE_BOOL},
	]
	if emission_enabled:
		properties += [
			{name="emission_color", type=TYPE_COLOR, hint=PROPERTY_HINT_COLOR_NO_ALPHA},
			{name="emission_strength", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0,16,0.01,or_greater"},
			{name="emission_texture", type=TYPE_OBJECT, hint=PROPERTY_HINT_RESOURCE_TYPE, hint_string="Texture3D"},
		]
	
	properties += [
		{name="UVW", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP, hint_string="uvw_"},
		{name="uvw_scale", type=TYPE_VECTOR3},
		{name="uvw_offset", type=TYPE_VECTOR3},
	]
	
	return properties

func _init() -> void:
	update_shaders()

func set_all_params() -> void:
	set_scatter_texture(scatter_texture)
	set_scatter_color(scatter_color)
	set_density(density)
	set_absorption_color(absorption_color)
	set_anisotropy(anisotropy)
	set_emission_color(emission_color)
	set_emission_strength(emission_strength)
	set_emission_texture(emission_texture)
	set_uvw_scale(uvw_scale)
	set_uvw_offset(uvw_offset)

func set_scatter_color(value : Color) -> void:
	scatter_color = value
	var scatter := Vector3(scatter_color.r, scatter_color.g, scatter_color.b);
	for volume in volumes:
		_get_volumetric_server().volume_set_param(volume, "scatter", scatter)

func set_density(value : float) -> void:
	density = max(value, 0.0)
	for volume in volumes:
		_get_volumetric_server().volume_set_param(volume, "density", density)

func set_absorption_color(value : Color) -> void:
	absorption_color = value
	var absorption := Vector3(absorption_color.r, absorption_color.g, absorption_color.b);
	for volume in volumes:
		_get_volumetric_server().volume_set_param(volume, "absorption", absorption)

func set_scatter_texture(value : Texture3D) -> void:
	scatter_texture = value
	if scatter_texture:
		set_material_flags(material_flags | SCATTER_TEX)
	else:
		set_material_flags(material_flags & ~SCATTER_TEX)
	
	for volume in volumes:
		_get_volumetric_server().volume_set_param(volume, "scatter_texture", scatter_texture)

func set_emission_enabled(value : bool) -> void:
	emission_enabled = value
	if emission_enabled:
		set_material_flags(material_flags | USE_EMISSION)
	else:
		set_material_flags(material_flags & ~USE_EMISSION)
	property_list_changed_notify()

func set_emission_color(value : Color) -> void:
	emission_color = value
	var emission := Vector3(emission_color.r, emission_color.g, emission_color.b) * emission_strength;
	for volume in volumes:
		_get_volumetric_server().volume_set_param(volume, "emission", emission)

func set_emission_strength(value : float) -> void:
	emission_strength = max(value, 0.0)
	var emission := Vector3(emission_color.r, emission_color.g, emission_color.b) * emission_strength;
	for volume in volumes:
		_get_volumetric_server().volume_set_param(volume, "emission", emission)

func set_emission_texture(value : Texture3D) -> void:
	emission_texture = value
	if emission_texture:
		set_material_flags(material_flags | EMISSION_TEX)
	else:
		set_material_flags(material_flags & ~EMISSION_TEX)
	
	for volume in volumes:
		_get_volumetric_server().volume_set_param(volume, "emission_texture", emission_texture)

func set_anisotropy(value : float) -> void:
	anisotropy = value
	for volume in volumes:
		_get_volumetric_server().volume_set_param(volume, "anisotropy", anisotropy * 0.99)

func set_uvw_scale(value : Vector3) -> void:
	uvw_scale = value
	for volume in volumes:
		_get_volumetric_server().volume_set_param(volume, "uvw_scale", uvw_scale)

func set_uvw_offset(value : Vector3) -> void:
	uvw_offset = value
	for volume in volumes:
		_get_volumetric_server().volume_set_param(volume, "uvw_offset", uvw_offset)

func set_material_flags(value : int) -> void:
	if material_flags != value or material_flags & MAX_FLAG:
		material_flags = value & ~MAX_FLAG
		
		if not material_flags_dirty:
			material_flags_dirty = true
			call_deferred("update_shaders")

func update_shaders() -> void:
	var has_scatter_tex := material_flags & SCATTER_TEX
	var has_emission_tex := material_flags & EMISSION_TEX
	
	var shader_fragments = [{
		# Scattering shader
		globals = """
			uniform vec3 scatter = vec3(1.0);
			uniform float density = 1.0;
			uniform vec3 uvw_scale = vec3(1.0);
			uniform vec3 uvw_offset = vec3(0.0);""" +\
			("uniform sampler3D scatter_texture;" if has_scatter_tex else ""),
		fragment_code = """
			UVW = mod(UVW * uvw_scale - uvw_offset, 1.0);
			ALBEDO = scatter * density * FADE;""" +\
			("ALBEDO *= textureLod(scatter_texture, UVW, 0.0).rgb;" if has_scatter_tex else "")
	},{
		# Extinction shader
		globals = """
			uniform vec3 scatter = vec3(1.0);
			uniform vec3 absorption = vec3(0.0);
			uniform float density = 1.0;
			uniform vec3 uvw_scale = vec3(1.0);
			uniform vec3 uvw_offset = vec3(0.0);""" +\
			("uniform sampler3D scatter_texture;" if has_scatter_tex else ""),
		fragment_code =\
			"UVW = mod(UVW * uvw_scale - uvw_offset, 1.0);" +\
			"vec3 dens = " + ("textureLod(scatter_texture, UVW, 0.0).rgb * density;" if has_scatter_tex else "vec3(density);") + """
			vec3 scatter_color = scatter;
			vec3 absorption_color = sqrt(absorption);
			absorption_color = max(1.0 - scatter_color, 0.0) * max(1.0 - absorption_color, 0.0);
			ALBEDO = (scatter_color + absorption_color) * dens * FADE;"""
	},{
		# Emission shader
		globals = """
			uniform vec3 uvw_scale = vec3(1.0);
			uniform vec3 uvw_offset = vec3(0.0);""" +\
			("uniform vec3 emission = vec3(0.0);" +\
			("uniform sampler3D emission_texture;" if has_emission_tex else "")) if emission_enabled else "",
		fragment_code =\
			"UVW = mod(UVW * uvw_scale - uvw_offset, 1.0);" +\
			("ALBEDO = textureLod(emission_texture, UVW, 0.0).rgb * emission * FADE;"
			if has_emission_tex else "ALBEDO = emission * FADE;") if emission_enabled else "discard;"
	},{
		# Phase shader
		globals = """
			uniform vec3 uvw_scale = vec3(1.0);
			uniform vec3 uvw_offset = vec3(0.0);
			uniform vec3 scatter = vec3(1.0);
			uniform float density = 1.0;
			uniform float anisotropy = 0.0;""" +\
			("uniform sampler3D scatter_texture;" if has_scatter_tex else ""),
		fragment_code = """
			ALBEDO = scatter * density;
			UVW = mod(UVW * uvw_scale - uvw_offset, 1.0);""" +\
			("ALBEDO *= textureLod(scatter_texture, UVW, 0.0).rgb;" if has_scatter_tex else "") + """
			if(all(lessThanEqual(ALBEDO, vec3(0.0)))) {
				ALBEDO = vec3(0.0);
			} else {
				ALBEDO = vec3(anisotropy, 1.0, 1.0);
			}"""
	},{
		# Motion shader
		globals = "render_mode blend_mix; uniform mat4 prev_world_matrix;",
		fragment_code = """
			vec3 prev_wpos = (prev_world_matrix * vec4((UVW - 0.5) * 2.0 * bounds_extents, 1.0)).xyz;
			ALBEDO = WORLD - prev_wpos;
		"""
	}]
	
	for idx in shader_fragments.size():
		var shader_frag : Dictionary = shader_fragments[idx]
		var code := SHADER_TEMPLATE.code.replace("/**GLOBALS**/", shader_frag.globals)
		code = code.replace("/**FRAGMENT CODE**/", shader_frag.fragment_code)
		shaders[idx].code = code
	
	for volume in volumes:
		_get_volumetric_server().volume_set_param(volume, "shader", shaders)
	
	set_all_params()
	material_flags_dirty = false
	
	emit_signal("shader_changed")

func _get_volumetric_server() -> Node:
	return Engine.get_main_loop().root.get_node("/root/VolumetricServer")
