tool
extends Node

enum {
	OMNI_LIGHT,
	SPOT_LIGHT,
	DIRECTIONAL_LIGHT,
}

signal atlas_changed(key)

var shadows := {}

var viewport_camera : Camera
var size := 2048 setget set_size

var atlas_spaces : Array
var atlas_subdivs = [0, 0, 0, 0]

var scene_bounds : SceneBounds

func _enter_tree() -> void:
	scene_bounds = SceneBounds.new(get_viewport())
	add_child(scene_bounds)

func _ready() -> void:
	$ShadowAtlas.size = Vector2(size, size)
	$ShadowRenderer.layers = 1 << 20
	
	if true or Engine.editor_hint:
		$TextureRect.visible = false

func _process(_delta : float) -> void:
	var subdivs := [1, 4, 16, 64, 256, 1024]
	var s1 : int = subdivs[max(get_viewport().shadow_atlas_quad_0, 1) - 1]
	var s2 : int = subdivs[max(get_viewport().shadow_atlas_quad_1, 1) - 1]
	var s3 : int = subdivs[max(get_viewport().shadow_atlas_quad_2, 1) - 1]
	var s4 : int = subdivs[max(get_viewport().shadow_atlas_quad_3, 1) - 1]
	set_atlas_subdivs(s1, s2, s3, s4)
	
	var scene_aabb : AABB = scene_bounds.get_aabb()
	
	var shadows_ordered := shadows.values()
	if viewport_camera:
		for s in shadows_ordered:
			s.camera = viewport_camera.global_transform.origin
		shadows_ordered.sort_custom(ShadowSort, "compare")
		for s in shadows_ordered:
			s.erase("camera")
	
	for i in shadows_ordered.size():
		var shadow_dat : Dictionary = shadows_ordered[i]
		var canvas : TextureRect = shadow_dat.canvas
		var coords : Rect2 = atlas_spaces[i]
		
		if shadow_dat.type == DIRECTIONAL_LIGHT:
			shadow_dat.shadow.scene_aabb = scene_aabb
		
		canvas.anchor_left = coords.position.x
		canvas.anchor_right = coords.end.x
		canvas.anchor_top = coords.position.y
		canvas.anchor_bottom = coords.end.y
		shadow_dat.shadow.size = coords.size * size
		
		if shadow_dat.coords != coords:
			emit_signal("atlas_changed", shadows.keys()[shadows.values().find(shadow_dat)], coords)
		shadow_dat.coords = coords

func add_shadow(key, light : Dictionary) -> void:
	var shadow_map : Node
	
	if light.type == SPOT_LIGHT:
		shadow_map = preload("spot_light_shadow.tscn").instance()
		add_child(shadow_map)
		shadow_map.position = light.position
		shadow_map.direction = light.direction
		shadow_map.spot_range = light.range
		shadow_map.spot_angle = light.spot_angle
	elif light.type == OMNI_LIGHT:
		shadow_map = preload("omni_light_shadow.tscn").instance()
		add_child(shadow_map)
		shadow_map._ready()
		shadow_map.position = light.position
		shadow_map.omni_range = light.range
	elif light.type == DIRECTIONAL_LIGHT:
		shadow_map = preload("directional_light_shadow.tscn").instance()
		add_child(shadow_map)
		shadow_map.direction = light.position
		shadow_map.energy = light.energy
	
	if shadow_map:
		var texture_rect := TextureRect.new()
		$ShadowAtlas.add_child(texture_rect)
		texture_rect.expand = true
		texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
		texture_rect.anchor_left = 0
		texture_rect.anchor_top = 0
		texture_rect.anchor_bottom = 0
		texture_rect.anchor_right = 0
		
		if light.type in [SPOT_LIGHT, DIRECTIONAL_LIGHT]:
			var shadow_texture : ViewportTexture = shadow_map.get_texture()
			texture_rect.texture = shadow_texture
		elif light.type == OMNI_LIGHT:
			texture_rect.texture = AnimatedTexture.new() # Placeholder
			texture_rect.material = ShaderMaterial.new()
			texture_rect.material.shader = preload("cube_to_dualparabloid.shader")
			texture_rect.material.set_shader_param("front", shadow_map.viewports[0].get_texture())
			texture_rect.material.set_shader_param("back", shadow_map.viewports[1].get_texture())
			texture_rect.material.set_shader_param("left", shadow_map.viewports[2].get_texture())
			texture_rect.material.set_shader_param("right", shadow_map.viewports[3].get_texture())
			texture_rect.material.set_shader_param("up", shadow_map.viewports[4].get_texture())
			texture_rect.material.set_shader_param("down", shadow_map.viewports[5].get_texture())
		
		shadows[key] = {shadow=shadow_map, canvas=texture_rect, coords=Rect2(), type=light.type}

func remove_shadow(key) -> void:
	shadows[key].canvas.queue_free()
	shadows[key].shadow.queue_free()
	shadows.erase(key)

func set_shadow_param(key, param : String, value) -> void:
	var shadow : Node = shadows[key].shadow
	if param in shadow:
		shadow.set(param, value)

func get_shadow_atlas() -> ViewportTexture:
	var atlas : ViewportTexture = $ShadowAtlas.get_texture()
	atlas.flags = Texture.FLAG_FILTER
	return atlas

func get_shadow_data(key) -> Dictionary:
	var shadow_data := {
		shadow_matrix = shadows[key].shadow.get_shadow_matrix(),
		shadow_coords = shadows[key].coords
	}
	return shadow_data

func set_size(value : int) -> void:
	size = value
	if not is_inside_tree():
		yield(self, "ready")
	$ShadowAtlas.size = Vector2(size, size)

func set_atlas_subdivs(s1 : int, s2 : int, s3 : int, s4 : int) -> void:
	if s1 == atlas_subdivs[0] and s2 == atlas_subdivs[1] and s3 == atlas_subdivs[2] and s4 == atlas_subdivs[3]:
		return
	
	atlas_subdivs = [s1, s2, s3, s4]
	
	atlas_spaces = []
	atlas_spaces.resize(atlas_subdivs[0] + atlas_subdivs[1] + atlas_subdivs[2] + atlas_subdivs[3])
	for i in atlas_spaces.size():
		var subdiv_root := 0
		var quad_size := 0.0; var x := 0.0; var y := 0.0
		
		if get_quadrant(i) == 0:
			subdiv_root = int(sqrt(atlas_subdivs[0]))
			quad_size = 0.5 / subdiv_root
			x = i % subdiv_root * quad_size
			y = floor(float(i / subdiv_root)) * quad_size
			
		elif get_quadrant(i) == 1:
			var j = i - atlas_subdivs[0]
			subdiv_root = int(sqrt(atlas_subdivs[1]))
			quad_size = 0.5 / subdiv_root
			x = j % subdiv_root * quad_size + 0.5
			y = floor(float(j / subdiv_root)) * quad_size
			
		elif get_quadrant(i) == 2:
			var j = i - atlas_subdivs[0] - atlas_subdivs[1]
			subdiv_root = int(sqrt(atlas_subdivs[2]))
			quad_size = 0.5 / subdiv_root
			x = j % subdiv_root * quad_size
			y = floor(float(j / subdiv_root)) * quad_size + 0.5
			
		else:
			var j = i - atlas_subdivs[0] - atlas_subdivs[1] - atlas_subdivs[2]
			subdiv_root = int(sqrt(atlas_subdivs[3]))
			quad_size = 0.5 / subdiv_root
			x = j % subdiv_root * quad_size + 0.5
			y = floor(float(j / subdiv_root)) * quad_size + 0.5
		
		atlas_spaces[i] = Rect2(x, y, quad_size, quad_size)

func get_quadrant(index : int) -> int:
	if index < atlas_subdivs[0]:
		return 0
	elif index < atlas_subdivs[0] + atlas_subdivs[1]:
		return 1
	elif index < atlas_subdivs[0] + atlas_subdivs[1] + atlas_subdivs[2]:
		return 2
	else:
		return 3

class ShadowSort:
	
	static func compare(s1, s2) -> bool:
		var priority_diff := get_shadow_priority(s2) - get_shadow_priority(s1)
		
		if priority_diff == 0:
			if s1.type == DIRECTIONAL_LIGHT:
				return s2.shadow.energy - s1.shadow.energy < 0
			
			var cam_distance1 : float = s1.camera.distance_squared_to(s1.shadow.position)
			var cam_distance2 : float = s1.camera.distance_squared_to(s2.shadow.position)
			
			return cam_distance2 - cam_distance1 < 0
		
		return priority_diff < 0;
	
	static func get_shadow_priority(shadow) -> int:
		match shadow.type:
			DIRECTIONAL_LIGHT: return 2
			OMNI_LIGHT: return 1
			SPOT_LIGHT: return 0
			_: return -1

