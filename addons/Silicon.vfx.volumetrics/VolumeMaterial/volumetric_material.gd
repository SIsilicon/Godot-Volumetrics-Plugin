tool
extends Resource
class_name VolumetricMaterial, "../volume_sprite.svg"

signal shader_changed

enum {
	DENSITY_MAP = 1
	MAX_FLAG = 512
}

var material_flags := MAX_FLAG
var material_flags_dirty := false

var shaders := []

var volumes = []

var scatter_color := Color.white setget set_scatter_color
var density := 1.0 setget set_density
var absorption_color := Color.white setget set_absorption_color
var density_map : Texture3D setget set_density_map

func _get_property_list() -> Array:
	var properties := [
		{name="VolumetricMaterial", type=TYPE_NIL, usage=PROPERTY_USAGE_CATEGORY},
		{name="scatter_color", type=TYPE_COLOR, hint=PROPERTY_HINT_COLOR_NO_ALPHA},
		{name="density", type=TYPE_REAL},
		{name="density_map", type=TYPE_OBJECT, hint=PROPERTY_HINT_RESOURCE_TYPE, hint_string="Texture3D"},
		{name="absorption_color", type=TYPE_COLOR, hint=PROPERTY_HINT_COLOR_NO_ALPHA}
	]
	
	return properties

func _init() -> void:
	update_shaders()

func set_all_params() -> void:
	set_scatter_color(scatter_color)
	set_density(density)
	set_absorption_color(absorption_color)
	set_density_map(density_map)

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
		VolumetricServer.set_volume_param(volume, "absorption", absorption_color)

func set_density_map(value : Texture3D) -> void:
	density_map = value
	if density_map:
		set_material_flags(material_flags | DENSITY_MAP)
	else:
		set_material_flags(material_flags & ~DENSITY_MAP)
	
	for volume in volumes:
		VolumetricServer.set_volume_param(volume, "density_map", density_map)

func set_material_flags(value : int) -> void:
	if material_flags != value or material_flags & MAX_FLAG:
		material_flags = value & ~MAX_FLAG
		
		if not material_flags_dirty:
			material_flags_dirty = true
			call_deferred("update_shaders")

func update_shaders() -> void:
	var has_density_map := material_flags & DENSITY_MAP
	
	shaders = [{
		# Scattering shader
		globals = """
			uniform vec3 scatter = vec3(1.0);
			uniform float density = 1.0;""" +\
			("uniform sampler3D density_map;" if has_density_map else ""),
		fragment_code = """
			ALBEDO = scatter * density;""" +\
			("ALBEDO *= textureLod(density_map, UVW, 0.0).rgb;" if has_density_map else "")
	},{
		# Absorption shader
		globals = """
			uniform vec3 scatter = vec3(1.0);
			uniform vec3 absorption = vec3(0.0);
			uniform float density = 1.0;""" +\
			("uniform sampler3D density_map;" if has_density_map else ""),
		fragment_code =\
			"vec3 dens = " + ("textureLod(density_map, UVW, 0.0).rgb * density;" if has_density_map else "vec3(density);") + """
			vec3 scatter_color = scatter * dens;
			vec3 absorption_color = sqrt(absorption);
			absorption_color = max(1.0 - scatter_color, 0.0) * max(1.0 - absorption_color, 0.0) * dens;
			ALBEDO = scatter_color + absorption_color;
		"""
	},{
		# Motion shader
		globals = "render_mode blend_mix; uniform mat4 prev_world_matrix;",
		fragment_code = """
			vec3 prev_wpos = (prev_world_matrix * vec4(UVW * 2.0 - 1.0, 1.0)).xyz;
			ALBEDO = WORLD - prev_wpos;
		"""
	}]
	
	for volume in volumes:
		VolumetricServer.set_volume_param(volume, "shader", shaders)
	
	set_all_params()
	material_flags_dirty = false
	
	emit_signal("shader_changed")
