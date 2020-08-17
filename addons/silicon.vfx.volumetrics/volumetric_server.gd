tool
extends Node

enum {
	OMNI_LIGHT = 0,
	SPOT_LIGHT = 1,
	DIRECTIONAL_LIGHT = 2
}

var default_material := preload("material/default_material.tres")

var id_counter := 0

var renderers := {}
var volumes := {}
var lights := {}
var geom_instances := {}

var orphan_volumes := {}

var can_function := true

func _enter_tree() -> void:
	process_priority = 512
	get_tree().connect("node_added", self, "_on_node_added")
	get_tree().connect("node_removed", self, "_on_node_removed")
	
	if OS.get_current_video_driver() == OS.VIDEO_DRIVER_GLES2:
		can_function = false
		printerr("Volumetrics Plugin: Sorry, but this rendering feature does not work in GLES2!")

### TODO : remove light metas
func _exit_tree() -> void:
	for renderer in renderers:
		remove_renderer(renderer)
	for light in lights:
		unregister_node(light)
	for geom_instance in geom_instances:
		unregister_node(geom_instance)
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
	if get_renderer_by_viewport(viewport) != -1:
		return -1
	
	if not can_function:
		id_counter += 1
		return id_counter - 1
	
	var renderer = preload("renderer/volumetric_renderer.tscn").instance()
	renderers[id_counter] = {node=renderer, viewport=viewport}
	
	
	var r_id = id_counter
	id_counter += 1
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
				renderer.set_volume_param(id, "shader", default_material.shaders)
			
			for param in volume.params:
				if param == "shader":
					continue
				renderer.set_volume_param(id, param, volume.params[param])
			volume.renderer = renderer
	
	update_nodes_in_viewport(viewport, viewport)
	
	return r_id

func remove_renderer(id : int) -> void:
	if renderers.has(id):
		var viewport = renderers[id].viewport
		
		var light_keys := lights.keys()
		for idx in range(lights.size()-1, -1, -1):
			if lights[light_keys[idx]] == renderers[id].node:
				_on_node_removed(light_keys[idx])
		
#		for material in renderers[id].node.transparent_materials:
#			orphan_transparent_materials[material] = viewport
		
		renderers[id].node.queue_free()
		
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

func renderer_set_ambient_light(id : int, value : Vector3) -> void:
	renderers[id].node.ambient_light = value

func renderer_set_cull_mask(id : int, value : int) -> void:
	renderers[id].node.cull_mask = value

func renderer_set_temporal_blending(id : int, value : float) -> void:
	renderers[id].node.blend = value

func renderer_set_volumetric_shadows(id : int, value : bool) -> void:
	renderers[id].node.volumetric_shadows = value

func renderer_set_shadow_atlas_size(id : int, value : int) -> void:
	renderers[id].node.shadow_manager.size = value

func get_renderer_by_viewport(viewport : Viewport) -> int:
	for id in renderers:
		if renderers[id].viewport == viewport:
			return id
	return -1

func _process(_delta : float) -> void:
	for light in lights:
		update_light(light)
	
	for geom_inst in geom_instances:
		update_geometry_instance(geom_inst)

func update_nodes_in_viewport(node : Node, viewport : Viewport) -> void:
	if (node is Light or node is GeometryInstance) and node.is_inside_tree():
		register_node(node)
	if not node is Viewport or node == viewport:
		for child in node.get_children():
			update_nodes_in_viewport(child, viewport)

func update_light(light : Light) -> void:
	var renderer = lights[light]
	var camera : Camera = renderer.camera
	
	var is_volumetric = light.has_meta("volumetric")
	is_volumetric = true if not is_volumetric else light.get_meta("volumetric")
	
	var in_cull_mask = (renderer.cull_mask & light.layers) != 0
	
	if camera and not light is DirectionalLight:
		var light_aabb : AABB = light.get_transformed_aabb()
		var frustum_intersection = FrustumAABBIntersection.new(camera)
		is_volumetric = is_volumetric and frustum_intersection.is_inside_frustum(light_aabb)
	
	if is_volumetric and not light.has_meta("_vol_id") and in_cull_mask:
		_on_node_added(light)
	elif (not is_volumetric or not in_cull_mask) and light.has_meta("_vol_id"):
		renderer.remove_light(light.get_meta("_vol_id"))
		light.remove_meta("_vol_id")
	
	if not light.has_meta("_vol_id"):
		return
	
	var id : int = light.get_meta("_vol_id")
	var energy : float = light.get_meta("volumetric") if light.has_meta("volumetric") else 1.0
	energy *= light.light_energy
	renderer.set_light_param(id, "color", light.light_color * (2.0 * float(not light.light_negative) - 1.0))
	renderer.set_light_param(id, "energy", energy * float(light.is_visible_in_tree()))
	
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

func update_geometry_instance(geom : GeometryInstance) -> void:
	if not geom:
		return
	var geom_data : Dictionary = geom_instances[geom]
	
	var apply_volumetrics := geom.has_meta("apply_volumetrics")
	if apply_volumetrics:
		apply_volumetrics = geom.get_meta("apply_volumetrics")
	
	var materials_to_convert := []
	if apply_volumetrics and geom_data.renderer:
		if geom is MeshInstance:
			for mat_idx in geom.get_surface_material_count():
				var material : Material = geom.get_surface_material(mat_idx)
				if material and is_transparent_material(material):
					materials_to_convert.append("material/" + str(mat_idx))
		elif geom is CSGPrimitive:
			if geom.material and is_transparent_material(geom.material):
				materials_to_convert.append("material")
		if geom.material_override and is_transparent_material(geom.material_override):
			materials_to_convert.append("material_override")
	
	geom_data.active_mats = {}
	for material in materials_to_convert:
		var geom_mat = geom.get(material)
		geom_mat.resource_local_to_scene = true
		
		if not geom_data.prev_mats.has(geom_mat):
			var volume_overlay := preload("material/transparent_volume_overlayer.gd").new()
			geom_mat.next_pass = volume_overlay
			volume_overlay.set_parent_material_ref(geom, material)
			
			geom_data.active_mats[geom_mat] = volume_overlay
			geom_data.renderer.transparent_materials.append(volume_overlay)
		else:
			geom_data.active_mats[geom_mat] = geom_data.prev_mats[geom_mat]
	
	for mat in geom_data.prev_mats:
		if not mat in geom_data.active_mats.keys():
			mat.next_pass = null
			if geom_data.renderer:
				geom_data.renderer.transparent_materials.erase(geom_data.prev_mats[mat])
	
	geom_data.prev_mats = geom_data.active_mats.duplicate()

func register_node(node : Node) -> void:
	assert(node.is_inside_tree())
	
	var viewport := node.get_viewport()
	var r_id := get_renderer_by_viewport(viewport)
	if r_id == -1:
		return
	var renderer = renderers[r_id].node
	
	if node is Light:
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
		id_counter += 1
		
		update_light(node)
	
	elif node is GeometryInstance:
		if not geom_instances.has(node):
			geom_instances[node] = {
				renderer=renderer,
				active_mats={},
				prev_mats={}
			}
		elif node.has_meta("_vol_id"):
			return
		
		node.set_meta("_vol_id", id_counter)
		id_counter += 1
		
		update_geometry_instance(node)

func unregister_node(node : Node) -> void:
	if lights.has(node):
		var renderer = lights[node]
		lights.erase(node)
		if node.has_meta("_vol_id"):
			renderer.remove_light(node.get_meta("_vol_id"))
			node.remove_meta("_vol_id")
	elif geom_instances.has(node):
		var renderer = geom_instances[node].renderer
		if renderer:
			for mat in geom_instances[node].active_mats:
				renderer.transparent_materials.erase(geom_instances[node].prev_mats[mat])
		geom_instances.erase(node)
		node.remove_meta("_vol_id")

func _on_node_added(node : Node) -> void:
	if node is Light or node is GeometryInstance:
		register_node(node)

func _on_node_removed(node : Node) -> void:
	if node is Light or node is GeometryInstance:
		unregister_node(node)

# Helper function
static func is_transparent_material(material : Material) -> bool:
	var shader = VisualServer.material_get_shader(material.get_rid())
	var code = VisualServer.shader_get_code(shader)
	
	if code.find("blend_mul") != -1 or \
		code.find("blend_add") != -1 or \
		code.find("blend_sub") != -1 or \
		code.find("ALPHA") != -1 or \
		code.find("SCREEN_TEXTURE") != -1 or \
		code.find("DEPTH_TEXTURE") != -1:
			return true
	
	return false
