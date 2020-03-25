tool
extends Node

enum {
	OMNI_LIGHT = 0,
	SPOT_LIGHT = 1,
	DIRECTIONAL_LIGHT = 2
}

var default_material := preload("VolumeMaterial/default_material.tres")

var id_counter := 0

var volumes := {}
var lights := {}
var renderers := {}

var orphan_volumes := {}

func _enter_tree() -> void:
	process_priority = 512
	
	get_tree().connect("node_added", self, "_on_node_added")
	get_tree().connect("node_removed", self, "_on_node_removed")

### TODO : remove light metas
func _exit_tree() -> void:
	for renderer in renderers:
		remove_renderer(renderer)
	volumes.clear()
	orphan_volumes.clear()

func add_volume(viewport : Viewport) -> int:
	var volume = {viewport=viewport}
	
	var r_id = get_renderer_by_viewport(viewport)
	if r_id == -1:
		orphan_volumes[id_counter] = volume
		id_counter += 1
		return id_counter - 1
	
	var renderer = renderers[r_id].node
	renderer.add_volume(id_counter)
	renderer.set_volume_param(id_counter, "shader", default_material.shaders)
	
	volume.renderer = renderer
	volumes[id_counter] = volume
	
	id_counter += 1
	return id_counter - 1

func remove_volume(id : int) -> void:
	if volumes.has(id):
		var renderer = volumes[id].renderer
		renderer.remove_volume(id)
		volumes.erase(id)
	elif orphan_volumes.has(id):
		volumes.erase(id)

func volume_set_param(id : int, param : String, value) -> void:
	var volume
	if volumes.has(id) or orphan_volumes.has(id):
		if param == "shader" and (not value or value.empty()):
			value = default_material.shaders
		
		if orphan_volumes.has(id):
			volume = orphan_volumes[id]
		else:
			volume = volumes[id]
		
		if not volume.has("params"):
			volume.params = {}
		volume.params[param] = value
	if volumes.has(id):
		volume.renderer.set_volume_param(id, param, value)

func add_renderer(viewport : Viewport) -> int:
	var renderer = preload("Renderer/volumetric_renderer.tscn").instance()
	renderers[id_counter] = {node=renderer, viewport=viewport}
	if viewport == get_parent():
		add_child(renderer)
	else:
		viewport.add_child(renderer)
	renderer.enabled = true
	
	var ids = orphan_volumes.keys()
	for id in ids:
		if orphan_volumes[id].viewport == viewport:
			var volume = orphan_volumes[id]
			renderer.add_volume(id)
			
			orphan_volumes.erase(id)
			volumes[id] = volume
			
			if volume.params.has("shader"):
				renderer.set_volume_param(id, "shader", volume.params.shader)
			else:
				renderer.set_volume_param(id, "shader", default_material)
			
			for param in volume.params:
				if param == "shader":
					continue
				renderer.set_volume_param(id, param, volume.params[param])
			volume.renderer = renderer
	
	var r_id = id_counter
	id_counter += 1
	
	update_lights_in_viewport(viewport, viewport)
	
	return r_id

func remove_renderer(id : int) -> void:
	if renderers.has(id):
		var light_keys := lights.keys()
		for idx in range(lights.size()-1, -1, -1):
			if lights[light_keys[idx]] == renderers[id].node:
				_on_node_removed(light_keys[idx])
		
		renderers[id].node.queue_free()
		
		var viewport = renderers[id].viewport
		var ids = volumes.keys()
		for vol_id in ids:
			var volume = volumes[vol_id]
			volumes.erase(vol_id)
			orphan_volumes[vol_id] = volume
		
		renderers.erase(id)

func renderer_set_start(id : int, value : float) -> void:
	renderers[id].node.start = value

func renderer_set_end(id : int, value : float) -> void:
	renderers[id].node.end = value

func renderer_set_tile_size(id : int, value : int) -> void:
	renderers[id].node.tile_size = value

func renderer_set_samples(id : int, value : int) -> void:
	renderers[id].node.samples = value

func renderer_set_distribution(id : int, value : float) -> void:
	renderers[id].node.distribution = value

func renderer_set_temporal_blending(id : int, value : float) -> void:
	renderers[id].node.blend = value

func renderer_set_volumetric_shadows(id : int, value : bool) -> void:
	renderers[id].node.volumetric_shadows = value

func get_renderer_by_viewport(viewport : Viewport) -> int:
	for id in renderers:
		if renderers[id].viewport == viewport:
			return id
	return -1

func add_light(light : Light) -> void:
	pass

func _process(_delta : float) -> void:
	for light in lights:
		update_light(light)

func update_lights_in_viewport(node : Node, viewport : Viewport) -> void:
	if node is Light:
		_on_node_added(node)
	if not node is Viewport or node == viewport:
		for child in node.get_children():
			update_lights_in_viewport(child, viewport)

func update_light(light : Light) -> void:
	var renderer = lights[light]
	
	var is_volumetric = light.has_meta("volumetric")
	is_volumetric = true if not is_volumetric else light.get_meta("volumetric")
	if is_volumetric and not light.has_meta("_vol_id"):
		_on_node_added(light)
	elif not is_volumetric and light.has_meta("_vol_id"):
		renderer.remove_light(light.get_meta("_vol_id"))
		light.remove_meta("_vol_id")
	
	if not light.has_meta("_vol_id"):
		return
	
	var id : int = light.get_meta("_vol_id")
	renderer.set_light_param(id, "color", light.light_color * (2.0 * float(not light.light_negative) - 1.0))
	renderer.set_light_param(id, "energy", light.light_energy * float(light.is_visible_in_tree()) * light.get_meta("volumetric"))
	
	if light is SpotLight or light is OmniLight:
		renderer.set_light_param(id, "shadows", light.shadow_enabled)
	
	var transform := light.global_transform if light.is_inside_tree() else light.transform
	
	if light is DirectionalLight:
		renderer.set_light_param(id, "position", transform.basis.z)
	else:
		renderer.set_light_param(id, "position", transform.origin)
		
		if light is OmniLight:
			renderer.set_light_param(id, "range", light.omni_range)
			renderer.set_light_param(id, "falloff", light.omni_attenuation)
		else:
			renderer.set_light_param(id, "range", light.spot_range)
			renderer.set_light_param(id, "falloff", light.spot_attenuation)
			renderer.set_light_param(id, "direction", transform.basis.z)
			renderer.set_light_param(id, "spot_angle", light.spot_angle)
			renderer.set_light_param(id, "spot_angle_attenuation", light.spot_angle_attenuation)

func _on_node_added(node : Node) -> void:
	if node is Light:
		var viewport := node.get_viewport()
		var r_id := get_renderer_by_viewport(viewport)
		if r_id == -1:
			return
		
		var renderer = renderers[r_id].node
		if not lights.has(node):
			lights[node] = renderer
		elif node.has_meta("_vol_id"):
			return
		
		var type : int
		match node.get_class():
			"OmniLight": type = OMNI_LIGHT
			"SpotLight": type = SPOT_LIGHT
			"DirectionalLight": type = DIRECTIONAL_LIGHT
		
		renderer.add_light(id_counter, type)
		node.set_meta("_vol_id", id_counter)
		
		update_light(node)
		
		id_counter += 1

func _on_node_removed(node : Node) -> void:
	if node is Light and lights.has(node):
		var renderer = lights[node]
		lights.erase(node)
		renderer.remove_light(node.get_meta("_vol_id"))
		node.remove_meta("_vol_id")

