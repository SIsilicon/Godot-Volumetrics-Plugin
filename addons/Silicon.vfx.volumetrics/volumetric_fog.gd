tool
extends Node

var renderer_id := -1

var start := 0.1 setget set_start
var end := 100.0 setget set_end

var tile_size := 2 setget set_tile_size
var samples := 1 setget set_samples
var distribution := 0.8 setget set_distribution
var temporal_blending := 0.95 setget set_temporal_blending
var volumetric_shadows := false setget set_volumetric_shadows

func _get_property_list() -> Array:
	return [
		{name="Volumetric Fog", type=TYPE_NIL, usage=PROPERTY_USAGE_CATEGORY},
		{name="start", type=TYPE_REAL},
		{name="end", type=TYPE_REAL},
		{name="tile_size", type=TYPE_INT, hint=PROPERTY_HINT_ENUM, hint_string="2x,4x,8x,16x"},
		{name="samples", type=TYPE_INT, hint=PROPERTY_HINT_ENUM, hint_string="32,64,128,256"},
		{name="distribution", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0,1,0.01"},
		{name="temporal_blending", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0,0.95,0.01"},
		{name="volumetric_shadows", type=TYPE_BOOL},
	]

func _enter_tree() -> void:
	renderer_id = VolumetricServer.add_renderer(get_viewport())
	VolumetricServer.renderer_set_start(renderer_id, start)
	VolumetricServer.renderer_set_end(renderer_id, end)
	VolumetricServer.renderer_set_tile_size(renderer_id, [2,4,8,16][tile_size])
	VolumetricServer.renderer_set_samples(renderer_id, [32,64,128,256][samples])
	VolumetricServer.renderer_set_distribution(renderer_id, distribution)
	VolumetricServer.renderer_set_temporal_blending(renderer_id, temporal_blending)
	VolumetricServer.renderer_set_volumetric_shadows(renderer_id, volumetric_shadows)

func _exit_tree() -> void:
	VolumetricServer.remove_renderer(renderer_id)
	renderer_id = -1

func set_start(value : float) -> void:
	start = min(value, end - 0.01)
	if renderer_id == -1:
		yield(self, "ready")
	VolumetricServer.renderer_set_start(renderer_id, start)

func set_end(value : float) -> void:
	end = max(value, start + 0.01)
	if renderer_id == -1:
		yield(self, "ready")
	VolumetricServer.renderer_set_end(renderer_id, end)

func set_tile_size(value : int) -> void:
	tile_size = value
	if renderer_id == -1:
		yield(self, "ready")
	VolumetricServer.renderer_set_tile_size(renderer_id, [2,4,8,16][tile_size])

func set_samples(value : int) -> void:
	samples = value
	if renderer_id == -1:
		yield(self, "ready")
	VolumetricServer.renderer_set_samples(renderer_id, [32,64,128,256][samples])

func set_distribution(value : float) -> void:
	distribution = value
	if renderer_id == -1:
		yield(self, "ready")
	VolumetricServer.renderer_set_distribution(renderer_id, distribution)

func set_temporal_blending(value : float) -> void:
	temporal_blending = value
	if renderer_id == -1:
		yield(self, "ready")
	VolumetricServer.renderer_set_temporal_blending(renderer_id, temporal_blending)

func set_volumetric_shadows(value : bool) -> void:
	volumetric_shadows = value
	if renderer_id == -1:
		yield(self, "ready")
	VolumetricServer.renderer_set_volumetric_shadows(renderer_id, volumetric_shadows)
