tool
extends Resource
class_name VolumetricMaterial, "volumetric_material.svg"

const SHADER_TEMPLATE = preload("../Renderer/volume_injection.shader")

signal shader_changed

enum {
	DENSITY_MAP = 1
	MAX_FLAG = 512
}

var material_flags := MAX_FLAG
var material_flags_dirty := false

# One shader per v-buffer (Scatter, Extinction, Emission, Phase, Motion)
# See volume_renderer.gd (add_volume)
var shaders := [Shader.new(), Shader.new(), Shader.new(), Shader.new(), Shader.new()]

var volumes = []

var scatter_color := Color.gray setget set_scatter_color
var density := 1.0 setget set_density
var absorption_color := Color.black setget set_absorption_color
var density_map : Texture3D setget set_density_map
var emission_color := Color.white setget set_emission_color
var emission_strength := 0.0 setget set_emission_strength
var anisotropy := 0.0 setget set_anisotropy

func _get_property_list() -> Array:
	var properties := [
		{name="VolumetricMaterial", type=TYPE_NIL, usage=PROPERTY_USAGE_CATEGORY},
		{name="scatter_color", type=TYPE_COLOR, hint=PROPERTY_HINT_COLOR_NO_ALPHA},
		{name="density", type=TYPE_REAL},
		{name="density_map", type=TYPE_OBJECT, hint=PROPERTY_HINT_RESOURCE_TYPE, hint_string="Texture3D"},
		{name="absorption_color", type=TYPE_COLOR, hint=PROPERTY_HINT_COLOR_NO_ALPHA},
		{name="anisotropy", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="-1,1"},
		{name="Emission", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP, hint_string="emission_"},
		{name="emission_color", type=TYPE_COLOR, hint=PROPERTY_HINT_COLOR_NO_ALPHA},
		{name="emission_strength", type=TYPE_REAL},
	]
	
	return properties

func _init() -> void:
	update_shaders()

func set_all_params() -> void:
	set_scatter_color(scatter_color)
	set_density(density)
	set_density_map(density_map)
	set_absorption_color(absorption_color)
	set_anisotropy(anisotropy)
	set_emission_color(emission_color)
	set_emission_strength(emission_strength)

func set_scatter_color(value : Color) -> void:
	scatter_color = value
	var scatter := Vector3(scatter_color.r, scatter_color.g, scatter_color.b);
	for volume in volumes:
		VolumetricServer.set_volume_param(volume, "scatter", scatter)

func set_density(value : float) -> void:
	density = max(value, 0.0)
	for volume in volumes:
		VolumetricServer.set_volume_param(volume, "density", density)

func set_absorption_color(value : Color) -> void:
	absorption_color = value
	var absorption := Vector3(absorption_color.r, absorption_color.g, absorption_color.b);
	for volume in volumes:
		VolumetricServer.set_volume_param(volume, "absorption", absorption)

func set_density_map(value : Texture3D) -> void:
	density_map = value
	if density_map:
		set_material_flags(material_flags | DENSITY_MAP)
	else:
		set_material_flags(material_flags & ~DENSITY_MAP)
	
	for volume in volumes:
		VolumetricServer.set_volume_param(volume, "density_map", density_map)

func set_emission_color(value : Color) -> void:
	emission_color = value
	var emission := Vector3(emission_color.r, emission_color.g, emission_color.b) * emission_strength;
	for volume in volumes:
		VolumetricServer.set_volume_param(volume, "emission", emission)

func set_emission_strength(value : float) -> void:
	emission_strength = max(value, 0.0)
	var emission := Vector3(emission_color.r, emission_color.g, emission_color.b) * emission_strength;
	for volume in volumes:
		VolumetricServer.set_volume_param(volume, "emission", emission)

func set_anisotropy(value : float) -> void:
	anisotropy = value
	for volume in volumes:
		VolumetricServer.set_volume_param(volume, "anisotropy", anisotropy * 0.99)

func set_material_flags(value : int) -> void:
	if material_flags != value or material_flags & MAX_FLAG:
		material_flags = value & ~MAX_FLAG
		
		if not material_flags_dirty:
			material_flags_dirty = true
			call_deferred("update_shaders")

func update_shaders() -> void:
	var has_density_map := material_flags & DENSITY_MAP
	
	var shader_fragments = [{
		# Scattering shader
		globals = """
			uniform vec3 scatter = vec3(1.0);
			uniform float density = 1.0;""" +\
			("uniform sampler3D density_map;" if has_density_map else ""),
		fragment_code = """
			ALBEDO = scatter * density;""" +\
			("ALBEDO *= textureLod(density_map, UVW, 0.0).rgb;" if has_density_map else "")
	},{
		# Extinction shader
		globals = """
			uniform vec3 scatter = vec3(1.0);
			uniform vec3 absorption = vec3(0.0);
			uniform float density = 1.0;""" +\
			("uniform sampler3D density_map;" if has_density_map else ""),
		fragment_code =\
			"vec3 dens = " + ("textureLod(density_map, UVW, 0.0).rgb * density;" if has_density_map else "vec3(density);") + """
			vec3 scatter_color = scatter;
			vec3 absorption_color = sqrt(absorption);
			absorption_color = max(1.0 - scatter_color, 0.0) * max(1.0 - absorption_color, 0.0);
			ALBEDO = (scatter_color + absorption_color) * dens;"""
	},{
		# Emission shader
		globals = """
			uniform vec3 emission = vec3(0.0);""",
		fragment_code = """
			ALBEDO = emission;"""
	},{
		# Phase shader
		globals = """
			uniform vec3 scatter = vec3(1.0);
			uniform float density = 1.0;
			uniform float anisotropy = 0.0;""" +\
			("uniform sampler3D density_map;" if has_density_map else ""),
		fragment_code = """
			ALBEDO = scatter * density;""" +\
			("ALBEDO *= textureLod(density_map, UVW, 0.0).rgb;" if has_density_map else "") + """
			if(all(lessThanEqual(ALBEDO, vec3(0.0)))) {
				ALBEDO = vec3(0.0);
			} else {
				ALBEDO = vec3(anisotropy, 1.0, 1.0);
			}"""
	},{
		# Motion shader
		globals = "render_mode blend_mix; uniform mat4 prev_world_matrix;",
		fragment_code = """
			vec3 prev_wpos = (prev_world_matrix * vec4(UVW * 2.0 - 1.0, 1.0)).xyz;
			ALBEDO = WORLD - prev_wpos;
		"""
	}]
	
	for idx in shader_fragments.size():
		var shader_frag : Dictionary = shader_fragments[idx]
		var code := SHADER_TEMPLATE.code.replace("/**GLOBALS**/", shader_frag.globals)
		code = code.replace("/**FRAGMENT CODE**/", shader_frag.fragment_code)
		shaders[idx].code = code
	
	for volume in volumes:
		VolumetricServer.set_volume_param(volume, "shader", shaders)
	
	set_all_params()
	material_flags_dirty = false
	
	emit_signal("shader_changed")
