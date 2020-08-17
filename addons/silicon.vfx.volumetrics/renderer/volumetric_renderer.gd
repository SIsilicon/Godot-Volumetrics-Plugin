tool
extends Node

enum {
	OMNI_LIGHT,
	SPOT_LIGHT,
	DIRECTIONAL_LIGHT,
}

const LIGHT_DATA_SIZE = 34

var default_material = preload("../material/default_material.tres")

var plugin

export var start := 0.1
export var end := 100.0

export var tile_size := 4
export var samples := 64 setget set_samples
export(float, 0.0, 1.0) var distribution := 0.7
export var volumetric_shadows := false

export var ambient_light := Vector3.ONE

export var cull_mask := (1 << 20) - 1

var tiling := Vector2(8, 16)

export var blend := 0.0
var frames_till_blending := 0

var camera : Camera
var camera_transform := Transform()
var prev_cam_transform := Transform()

export var enabled := true setget set_enabled

var canvas := QuadMesh.new()
var shadow_manager := preload("shadow_manager/shadow_manager.tscn").instance()
onready var v_buffers := [$Scatter, $Extinction, $Emission, $Phase, $Motion]

var shadow_size := 1024 setget set_shadow_size

var volumes := {}
var transparent_materials := []

var lights := {}
var light_texture := ImageTexture.new()
var temp_light_img : Image = null

var halton : Array 

func _enter_tree() -> void:
	halton = Halton.genearate_sequence_3D(Vector3(2,5,3), 128)
	halton.shuffle()
	
	var image := Image.new()
	image.create(1, 1, false, Image.FORMAT_RF)
	light_texture.create_from_image(image, 0)
	
	canvas.size = Vector2(2, 2)
	
	add_child(shadow_manager)

func _ready() -> void:
	move_child(shadow_manager, 0)
	shadow_manager.connect("atlas_changed", self, "_on_shadow_atlas_changed")
	
	$LightScatter/ColorRect.material.set_shader_param("light_data", light_texture)
	
	resize(Vector2.ONE)
	
	yield(get_tree(), "idle_frame")
	$LightScatter/ColorRect.material.set_shader_param("shadow_atlas", shadow_manager.get_shadow_atlas())

func _process(delta) -> void:
	set_enabled(not volumes.empty())
	
	# Get the camera, viewport and its size with tiling in account.
	var size = tiling
	var viewport : Viewport
	if Engine.editor_hint:
		if not has_node("/root/EditorNode/VolumetricsPlugin"):
			return
		if not plugin:
			plugin = get_node("/root/EditorNode/VolumetricsPlugin")
		if not plugin or not("editor_camera" in plugin) or not plugin.editor_camera:
			$SolidTransmit.visible = false
			return
		else:
			$SolidTransmit.visible = enabled
		size *= plugin.editor_camera.get_parent().size / tile_size
		camera = plugin.editor_camera
		viewport = camera.get_parent()
	else:
		size *= get_viewport().size / tile_size
		viewport = get_viewport()
		camera = viewport.get_camera()
		if not camera:
			return
	camera.force_update_transform()
	camera_transform = camera.get_camera_transform()
	
#	# This is a hack to compensate for the delay in the editor camera.
#	if true or Engine.editor_hint:
#		camera_transform = prev_cam_transform.interpolate_with(camera_transform, 2)
	
	resize(size)
	shadow_manager.viewport_camera = camera
	
	for view in get_viewports():
		var viewport_camera = view.get_child(0)
		
		if viewport_camera is Camera:
			viewport_camera.global_transform = camera_transform
			viewport_camera.keep_aspect = camera.keep_aspect
			viewport_camera.fov = camera.fov
			viewport_camera.near = start
			viewport_camera.far = end
			view.process_priority = -512
	process_priority = -512
	
	var sample_distribution = 4.0 * (max(1.0 - sqrt(distribution) * 0.95, 1e-2))
	var near = min(-start, -camera.near - 1e-4)
	var far = min(-end, near - 1e-4)
	var vol_depth_params := Vector3()
	vol_depth_params.x = (far - near * pow(2.0, 1.0 / sample_distribution)) / (far - near)
	vol_depth_params.y = (1.0 - vol_depth_params.x) / near
	vol_depth_params.z = sample_distribution
	
	var camera_projection : Matrix4 = Matrix4.new().get_camera_projection(camera)
	for view in [$LightScatter, $LightTransmit]:
		view.get_child(0).material.set_shader_param("tile_factor", tiling)
		view.get_child(0).material.set_shader_param("vol_depth_params", vol_depth_params)
		view.get_child(0).material.set_shader_param("prev_inv_view_matrix", prev_cam_transform.affine_inverse())
		view.get_child(0).material.set_shader_param("curr_view_matrix", camera_transform)
		camera_projection.set_shader_param(view.get_child(0).material, "projection_matrix")
	$LightScatter/ColorRect.material.set_shader_param("volumetric_shadows", volumetric_shadows)
	
	for resolver in [$ResolveScatter/Canvas, $ResolveTransmit/Canvas, $SolidTransmit, $SolidScatter]:
		resolver.material_override.set_shader_param("vol_depth_params", vol_depth_params)
		resolver.material_override.set_shader_param("tile_factor", tiling)
	
	for material in transparent_materials:
		material.tile_factor = tiling
		material.vol_depth_params = vol_depth_params
		material.volume_transmittance = $SolidScatter.material_override.get_shader_param("volume_transmittance")
		material.volume_scattering = $SolidScatter.material_override.get_shader_param("volume_scattering")
	
	var sample_offset : Vector3 = (halton[Engine.get_frames_drawn() % halton.size()]) / Vector3(size.x, size.y, samples) * float(blend != 0)
	$LightScatter.get_child(0).material.set_shader_param("sample_offset", sample_offset)
	
	for buffer in v_buffers:
		for child in buffer.get_children():
			if child is Camera:
				continue
			
			var material = child.material_override
			if not material:
				continue
			
			material.set_shader_param("distribution", distribution)
			material.set_shader_param("tile_factor", tiling)
			material.set_shader_param("camera_near", start)
			material.set_shader_param("camera_far", end)
			material.set_shader_param("vol_depth_params", vol_depth_params)
			material.set_shader_param("sample_offset", sample_offset)
			
			# For motion materials
			if buffer == $Motion:
				var previous_transform : Transform
				if child.has_meta("previous_transform"):
					previous_transform = child.get_meta("previous_transform")
				else:
					previous_transform = child.global_transform
				material.set_shader_param("prev_world_matrix", previous_transform)
				child.set_meta("previous_transform", child.global_transform)
	
	$LightScatter/ColorRect.material.set_shader_param("ambient_light", ambient_light)
	$LightScatter/ColorRect.material.set_shader_param("blend", blend * float(frames_till_blending == 0))
	$LightTransmit/ColorRect.material.set_shader_param("blend", blend * float(frames_till_blending == 0))
	
	# Directional light shadow matrices need an update every frame.
	for key in lights:
		if lights[key].type == DIRECTIONAL_LIGHT and lights[key].shadows:
			var shadow_matrix : Matrix4 = shadow_manager.get_shadow_data(key).shadow_matrix
			pass_light_data(14, lights[key].index, shadow_matrix.get_data())
	
	# Apply all changes to light texture
	if temp_light_img:
		temp_light_img.unlock()
		light_texture.create_from_image(temp_light_img, 0)
		temp_light_img = null
	
	frames_till_blending = max(frames_till_blending - 1, 0)
	prev_cam_transform = camera.get_camera_transform()

func set_samples(value : int) -> void:
	samples = value
	tiling = get_tile_dimension(samples)
	reduce_sample_size()

func get_tile_dimension(depth : int) -> Vector2:
	var tile_dimension := Vector2(0, 0)
	var last_factor := depth
	
	for i in range(1, depth + 1):
		var candidate_factor := float(depth) / i
		if candidate_factor - floor(candidate_factor) == 0.0:
			if i == candidate_factor:
				tile_dimension = Vector2(i, i)
				break
			elif i == last_factor:
				tile_dimension = Vector2(int(candidate_factor), int(last_factor))
				break
			last_factor = candidate_factor
	
	if tile_dimension[0] == 1:
		return get_tile_dimension(depth+1)
	else:
		return tile_dimension

func reduce_sample_size() -> void:
	if not is_inside_tree():
		return
	
	var size : Vector2 = $PrevScatter.size
	while size.x * tiling.x > 16384 or size.y * tiling.y > 16384:
		samples -= 1
		tiling = get_tile_dimension(samples)

func set_enabled(value : bool) -> void:
	if enabled != value:
		enabled = value
		var update_mode := Viewport.UPDATE_ALWAYS if enabled else Viewport.UPDATE_DISABLED
		for viewport in get_viewports():
			viewport.render_target_update_mode = update_mode
		
		if get_node_or_null("SolidScatter"):
			$SolidScatter.visible = enabled
			$SolidTransmit.visible = enabled
		
		frames_till_blending = 3

func get_viewports() -> Array:
	var viewports := []
	for child in get_children():
		if child is Viewport:
			viewports.append(child)
	return viewports

func resize(size : Vector2) -> void:
	if size.floor() != $PrevScatter.size:
		frames_till_blending = 3
		reduce_sample_size()
	
	for viewport in get_viewports():
		viewport.size = size

func set_shadow_size(value : int) -> void:
	shadow_size = value
	if shadow_manager:
		shadow_manager.size = shadow_size

func add_volume(key) -> void:
	var meshes := []
	
	# V-buffers may not be initialized immediately after entering the scene tree
	if not v_buffers and is_inside_tree():
		v_buffers = [$Scatter, $Extinction, $Emission, $Phase, $Motion]
	
	for buffer in v_buffers:
		var canvas_inst := MeshInstance.new()
		canvas_inst.extra_cull_margin = 16384
		canvas_inst.mesh = canvas
		canvas_inst.material_override = ShaderMaterial.new()
		canvas_inst.material_override.shader = preload("volume_injection.shader")
		buffer.add_child(canvas_inst)
		meshes.append(canvas_inst)
	
	volumes[key] = meshes

func remove_volume(key) -> void:
	for mesh in volumes[key]:
		mesh.queue_free()
	volumes.erase(key)

func set_volume_param(key, param : String, value) -> void:
	if param == "transform":
		for mesh in volumes[key]:
			mesh.transform = value
#	elif param == "visible":
#		for mesh in volumes[key]:
#			mesh.visible = value
	elif param == "shader":
		for idx in volumes[key].size():
			var mesh : MeshInstance = volumes[key][idx]
			var material := mesh.material_override
			if value and not value.empty():
				material.shader = value[idx]
			else:
				material.shader = default_material.shaders[idx]
	else:
		for mesh in volumes[key]:
			mesh.material_override.set_shader_param(param, value)

func add_light(key, type : int, data := {}) -> void:
	if not temp_light_img:
		temp_light_img = light_texture.get_data()
	
	var light_data := {
		type = type,
		position = Vector3(),
		color = Color.white,
		energy = 1.0,
		shadows = false
	} if data.empty() else data
	light_data.index = temp_light_img.get_height() if temp_light_img.get_width() == LIGHT_DATA_SIZE else 0
	
	temp_light_img.unlock()
	temp_light_img.crop(LIGHT_DATA_SIZE, (temp_light_img.get_height() + 1) if temp_light_img.get_width() == LIGHT_DATA_SIZE else 1)
	temp_light_img.lock()
	
	pass_light_data(0, light_data.index, type)
	pass_light_data(1, light_data.index, light_data.position)
	pass_light_data(4, light_data.index, light_data.color * light_data.energy)
	
	# If not directional light...
	if type != DIRECTIONAL_LIGHT:
		if not light_data.has("range"):
			light_data.range = 5.0
			light_data.falloff = 2.0
		pass_light_data(7, light_data.index, light_data.range)
		pass_light_data(8, light_data.index, light_data.falloff)
		
		if type == SPOT_LIGHT:
			if not light_data.has("direction"):
				light_data.direction = Vector3.FORWARD
				light_data.spot_angle = deg2rad(45.0)
				light_data.spot_angle_attenuation = 1.0
			pass_light_data(9, light_data.index, light_data.direction)
			pass_light_data(12, light_data.index, light_data.spot_angle_attenuation)
			pass_light_data(13, light_data.index, cos(deg2rad(light_data.spot_angle)))
	
	if light_data.shadows:
		shadow_manager.add_shadow(key, light_data)
		var shadow_coords : Rect2 = shadow_manager.get_shadow_data(key).shadow_coords
		var shadow_matrix : Matrix4 = shadow_manager.get_shadow_data(key).shadow_matrix
		pass_light_data(14, light_data.index, shadow_matrix.get_data())
		pass_light_data(30, light_data.index, shadow_coords)
	
	lights[key] = light_data
	
	$LightScatter/ColorRect.material.set_shader_param("use_light_data", true)

func remove_light(key) -> void:
	var index : int = lights[key].index
	if lights[key].shadows:
		shadow_manager.remove_shadow(key)
	lights.erase(key)
	
	if not temp_light_img:
		temp_light_img = light_texture.get_data()
	
	temp_light_img.unlock()
	temp_light_img.crop(LIGHT_DATA_SIZE if index != 0 else 1, max(index, 1))
	temp_light_img.lock()
	
	if lights.empty():
		$LightScatter/ColorRect.material.set_shader_param("use_light_data", true)
	elif index <= temp_light_img.get_height():
		var other_lights : Array = lights.values()
		other_lights.sort_custom(LightIndexSorter, "sort_ascending")
		for light_data in other_lights:
			if light_data.index <= index:
				continue
			add_light(lights.keys()[lights.values().find(light_data)], light_data.type, light_data)

func set_light_param(key, param : String, value) -> void:
	var light_data : Dictionary = lights[key]
	if light_data[param] == value:
		return
	
	var index : int = light_data.index
	var shadow_data_update := false
	match param:
		"position":
			if light_data.position != value:
				shadow_data_update = true
			
			light_data.position = value
			pass_light_data(1, index, value)
		"color", "energy":
			if typeof(value) == TYPE_COLOR:
				light_data.color = value
			else:
				light_data.energy = value
			
			pass_light_data(4, index, light_data.color * light_data.energy)
		"range":
			if light_data.range != value:
				shadow_data_update = true
				param = "spot_range" if light_data.type == SPOT_LIGHT else "omni_range"
			light_data.range = value
			
			pass_light_data(7, index, light_data.range)
		"falloff":
			light_data.falloff = value
			
			pass_light_data(8, index, light_data.falloff)
		"direction":
			if light_data.direction != value:
				shadow_data_update = true
			light_data.direction = value
			
			pass_light_data(9, light_data.index, light_data.direction)
		"spot_angle_attenuation":
			light_data.spot_angle_attenuation = value
			
			pass_light_data(12, light_data.index, light_data.spot_angle_attenuation)
		"spot_angle":
			if light_data.spot_angle != value:
				shadow_data_update = true
			light_data.spot_angle = value
			
			pass_light_data(13, light_data.index, cos(deg2rad(light_data.spot_angle)))
		"shadows":
			if light_data.shadows != value:
				if value:
					shadow_manager.add_shadow(key, light_data)
					shadow_data_update = true
				else:
					shadow_manager.remove_shadow(key)
					pass_light_data(14, light_data.index, 0)
			light_data.shadows = value
	
	if shadow_data_update and light_data.shadows:
		if light_data.type == DIRECTIONAL_LIGHT and param == "position":
			param = "direction"
		shadow_manager.set_shadow_param(key, param, value)
		var shadow_matrix : Matrix4 = shadow_manager.get_shadow_data(key).shadow_matrix
		pass_light_data(14, light_data.index, shadow_matrix.get_data())

func _on_shadow_atlas_changed(key, coords : Rect2) -> void:
	pass_light_data(30, lights[key].index, coords)

func pass_light_data(index : int, light_index : int, value) -> void:
	if not temp_light_img:
		temp_light_img = light_texture.get_data().duplicate()
		temp_light_img.lock()
	
	match typeof(value):
		TYPE_COLOR:
			pass_light_data(index+0, light_index, value.r)
			pass_light_data(index+1, light_index, value.g)
			pass_light_data(index+2, light_index, value.b)
			return
		TYPE_RECT2:
			pass_light_data(index+0, light_index, value.position.x)
			pass_light_data(index+1, light_index, value.position.y)
			pass_light_data(index+2, light_index, value.size.x)
			pass_light_data(index+3, light_index, value.size.y)
			return
		TYPE_VECTOR3:
			pass_light_data(index+0, light_index, value.x)
			pass_light_data(index+1, light_index, value.y)
			pass_light_data(index+2, light_index, value.z)
			return
		TYPE_ARRAY:
			for i in value.size():
				pass_light_data(index+i, light_index, value[i])
			return
	
	temp_light_img.set_pixel(index, light_index, Color(value, 0,0,0))

class LightIndexSorter:
	static func sort_ascending(a, b) -> bool:
		if a.index < b.index:
			return true
		return false

