tool
extends Node

var renderer_id := -1

var start := 0.1 setget set_start
var end := 100.0 setget set_end

var tile_size := 2 setget set_tile_size
var samples := 1 setget set_samples
var distribution := 0.9 setget set_distribution
var temporal_blending := 0.95 setget set_temporal_blending
var volumetric_shadows := false setget set_volumetric_shadows

var shadow_atlas_size := 1024 setget set_shadow_atlas_size

var ambient_light_color := Color.black setget set_ambient_light_color
var ambient_light_energy := 1.0 setget set_ambient_light_energy

func _get_property_list() -> Array:
	return [
		{name="VolumetricFog", type=TYPE_NIL, usage=PROPERTY_USAGE_CATEGORY},
		{name="start", type=TYPE_REAL},
		{name="end", type=TYPE_REAL},
		{name="tile_size", type=TYPE_INT, hint=PROPERTY_HINT_ENUM, hint_string="4x,8x,16x"},
		{name="samples", type=TYPE_INT, hint=PROPERTY_HINT_ENUM, hint_string="32,64,128,256"},
		{name="distribution", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0,1,0.01"},
		{name="temporal_blending", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0,0.95,0.01"},
		{name="volumetric_shadows", type=TYPE_BOOL},
		{name="shadow_atlas_size", type=TYPE_INT},
		
		{name="Ambient Light", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP, hint_string="ambient_light_"},
		{name="ambient_light_color", type=TYPE_COLOR, hint=PROPERTY_HINT_COLOR_NO_ALPHA},
		{name="ambient_light_energy", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0,16,0.01,or_greater"},
	]

func _enter_tree() -> void:
	renderer_id = _get_volumetric_server().add_renderer(get_viewport())
	_get_volumetric_server().renderer_set_start(renderer_id, start)
	_get_volumetric_server().renderer_set_end(renderer_id, end)
	_get_volumetric_server().renderer_set_tile_size(renderer_id, [2,4,8,16][tile_size])
	_get_volumetric_server().renderer_set_samples(renderer_id, [32,64,128,256][samples])
	_get_volumetric_server().renderer_set_distribution(renderer_id, distribution)
	_get_volumetric_server().renderer_set_temporal_blending(renderer_id, temporal_blending)
	_get_volumetric_server().renderer_set_volumetric_shadows(renderer_id, volumetric_shadows)
	_get_volumetric_server().renderer_set_shadow_atlas_size(renderer_id, shadow_atlas_size)
	_get_volumetric_server().renderer_set_ambient_light(renderer_id, Vector3(ambient_light_color.r, ambient_light_color.g, ambient_light_color.b) * ambient_light_energy)

func _exit_tree() -> void:
	_get_volumetric_server().remove_renderer(renderer_id)
	renderer_id = -1

func set_start(value : float) -> void:
	start = min(value, end - 0.01)
	if renderer_id == -1:
		yield(self, "ready")
	_get_volumetric_server().renderer_set_start(renderer_id, start)

func set_end(value : float) -> void:
	end = max(value, start + 0.01)
	if renderer_id == -1:
		yield(self, "ready")
	_get_volumetric_server().renderer_set_end(renderer_id, end)

func set_tile_size(value : int) -> void:
	tile_size = value
	if renderer_id == -1:
		yield(self, "ready")
	_get_volumetric_server().renderer_set_tile_size(renderer_id, [4,8,16][tile_size])

func set_samples(value : int) -> void:
	samples = value
	if renderer_id == -1:
		yield(self, "ready")
	_get_volumetric_server().renderer_set_samples(renderer_id, [32,64,128,256][samples])

func set_distribution(value : float) -> void:
	distribution = value
	if renderer_id == -1:
		yield(self, "ready")
	_get_volumetric_server().renderer_set_distribution(renderer_id, distribution)

func set_temporal_blending(value : float) -> void:
	temporal_blending = value
	if renderer_id == -1:
		yield(self, "ready")
	_get_volumetric_server().renderer_set_temporal_blending(renderer_id, temporal_blending)

func set_volumetric_shadows(value : bool) -> void:
	volumetric_shadows = value
	if renderer_id == -1:
		yield(self, "ready")
	_get_volumetric_server().renderer_set_volumetric_shadows(renderer_id, volumetric_shadows)

func set_shadow_atlas_size(value : int) -> void:
	shadow_atlas_size = clamp(value, 256, 16384)
	if renderer_id == -1:
		yield(self, "ready")
	_get_volumetric_server().renderer_set_shadow_atlas_size(renderer_id, shadow_atlas_size)

func set_ambient_light_color(value : Color) -> void:
	ambient_light_color = value
	if renderer_id == -1:
		yield(self, "ready")
	_get_volumetric_server().renderer_set_ambient_light(renderer_id, Vector3(ambient_light_color.r, ambient_light_color.g, ambient_light_color.b) * ambient_light_energy)

func set_ambient_light_energy(value : float) -> void:
	ambient_light_energy = value
	if renderer_id == -1:
		yield(self, "ready")
	_get_volumetric_server().renderer_set_ambient_light(renderer_id, Vector3(ambient_light_color.r, ambient_light_color.g, ambient_light_color.b) * ambient_light_energy)

func _get_volumetric_server() -> Node:
	return Engine.get_main_loop().root.get_node("/root/VolumetricServer")
