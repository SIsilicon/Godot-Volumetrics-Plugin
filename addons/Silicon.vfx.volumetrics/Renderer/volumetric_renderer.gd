tool
extends Node

const LIGHT_DATA_SIZE = 14

var plugin

export var start := 0.1
export var end := 100.0

export var tile_size := 4
export var samples := 64 setget set_samples
export(float, 0.0, 1.0) var distribution := 0.7
export var volumetric_shadows := false

var tiling := Vector2(8, 16)

var blend := 0.95
var frames_since_resize := 0

var camera : Camera
var camera_transform := Transform()
var prev_cam_transform := Transform()

export var enabled := true setget set_enabled

var canvas := QuadMesh.new()
onready var v_buffers := [$Scatter, $Extinction, $Emission, $Phase, $Motion]

var volumes := {}

var lights := {}
var light_texture := ImageTexture.new()
var temp_light_img : Image = null

var halton := Halton.genearate_sequence_3D(Vector3(2,5,3), 128)

func _enter_tree() -> void:
	halton.shuffle()
	
	var image := Image.new()
	image.create(1, 1, false, Image.FORMAT_RF)
	light_texture.create_from_image(image, 0)

func _ready() -> void:
	$LightScatter/ColorRect.material.set_shader_param("light_data", light_texture)
	
	canvas.size = Vector2(2, 2)
	if Engine.editor_hint and get_tree().edited_scene_root == self:
		set_enabled(false)
	
	process_priority = 512
	resize(Vector2.ONE)

func _process(_delta : float) -> void:
	var size = tiling
	prev_cam_transform = camera_transform
	
	var viewport : Viewport
	if Engine.editor_hint:
		if not plugin:
			plugin = get_node("/root/EditorNode/VolumetricsPlugin")
		if not plugin.editor_camera:
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
	camera_transform = camera.global_transform
	
	resize(size)
	
	for viewport in get_viewports():
		var viewport_camera = viewport.get_child(0)
		if viewport_camera is Camera:
			viewport_camera.transform = camera.global_transform
			viewport_camera.keep_aspect = camera.keep_aspect
			viewport_camera.fov = camera.fov
			viewport_camera.near = start
			viewport_camera.far = end
	
	var sample_distribution = 4.0 * (max(1.0 - distribution * 0.95, 1e-2))
	var near = min(-start, -camera.near - 1e-4)
	var far = min(-end, near - 1e-4)
	var vol_depth_params := Vector3()
	vol_depth_params.x = (far - near * pow(2.0, 1.0 / sample_distribution)) / (far - near)
	vol_depth_params.y = (1.0 - vol_depth_params.x) / near
	vol_depth_params.z = sample_distribution
	
	var camera_projection := CameraMatrix.get_perspective_matrix(camera.fov, viewport.size.aspect(), camera.near, camera.far, camera.keep_aspect == Camera.KEEP_WIDTH)
	for viewport in [$LightScatter, $LightTransmit]:
		viewport.get_child(0).material.set_shader_param("tile_factor", tiling)
		viewport.get_child(0).material.set_shader_param("vol_depth_params", vol_depth_params)
		viewport.get_child(0).material.set_shader_param("prev_inv_view_matrix", prev_cam_transform.inverse())
		viewport.get_child(0).material.set_shader_param("curr_view_matrix", camera_transform)
		CameraMatrix.pass_as_uniform(viewport.get_child(0).material, "projection_matrix", camera_projection)
	$LightScatter/ColorRect.material.set_shader_param("volumetric_shadows", volumetric_shadows)
	
	for resolver in [$ResolveScatter/Canvas, $ResolveTransmit/Canvas, $SolidTransmit, $SolidScatter]:
		resolver.material_override.set_shader_param("vol_depth_params", vol_depth_params)
		resolver.material_override.set_shader_param("tile_factor", tiling)
	
	var sample_offset : Vector3 = halton[Engine.get_frames_drawn() % halton.size()] / Vector3(size.x, size.y, samples)
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
	
	$LightScatter/ColorRect.material.set_shader_param("blend", blend * min(frames_since_resize, 1))
	$LightTransmit/ColorRect.material.set_shader_param("blend", blend * min(frames_since_resize, 1))
	
	# Apply all changes to light texture
	if temp_light_img:
		temp_light_img.unlock()
		light_texture.create_from_image(temp_light_img, 0)
		temp_light_img = null
	
	frames_since_resize += 1

func set_samples(value : int) -> void:
	samples = value
	tiling = get_tile_dimension(samples)

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

func set_enabled(value : bool) -> void:
	if enabled != value:
		enabled = value
		var update_mode := Viewport.UPDATE_ALWAYS if enabled else Viewport.UPDATE_DISABLED
		for viewport in get_viewports():
			viewport.render_target_update_mode = update_mode
		
		if get_node_or_null("SolidScatter"):
			$SolidScatter.visible = enabled
			$SolidTransmit.visible = enabled
		
		frames_since_resize = 0

func get_viewports() -> Array:
	var viewports := []
	for child in get_children():
		if child is Viewport:
			viewports.append(child)
	return viewports

func resize(size : Vector2) -> void:
	if size.floor() != $PrevScatter.size:
		frames_since_resize = 0
	
	for viewport in get_viewports():
		viewport.size = size

func add_volume(key) -> void:
	var meshes := []
	
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
	elif param == "visible":
		for mesh in volumes[key]:
			mesh.visible = value
	elif param == "shader":
		for idx in volumes[key].size():
			var mesh : MeshInstance = volumes[key][idx]
			var material := mesh.material_override
			material.shader = value[idx]
	else:
		for mesh in volumes[key]:
			mesh.material_override.set_shader_param(param, value)

# type 0 = OmniLight
# type 1 = SpotLight
# type 2 = DirectionalLight
func add_light(key, type : int, data := {}) -> void:
	if not temp_light_img:
		temp_light_img = light_texture.get_data()
	
	var light_data := {
		type = type,
		position = Vector3(),
		color = Color.white,
		energy = 1.0
	} if data.empty() else data
	light_data.index = temp_light_img.get_height() if temp_light_img.get_width() == LIGHT_DATA_SIZE else 0
	
	temp_light_img.unlock()
	temp_light_img.crop(LIGHT_DATA_SIZE, (temp_light_img.get_height() + 1) if temp_light_img.get_width() == LIGHT_DATA_SIZE else 1)
	temp_light_img.lock()
	
	# type
	pass_light_data(0, light_data.index, type)
	# position
	pass_light_data(1, light_data.index, light_data.position.x)
	pass_light_data(2, light_data.index, light_data.position.y)
	pass_light_data(3, light_data.index, light_data.position.z)
	# color and energy
	pass_light_data(4, light_data.index, light_data.color.r * light_data.energy)
	pass_light_data(5, light_data.index, light_data.color.g * light_data.energy)
	pass_light_data(6, light_data.index, light_data.color.b * light_data.energy)
	
	# If not directional light...
	if type != 2:
		if not light_data.has("range"):
			light_data.range = 5.0
			light_data.falloff = 2.0
		pass_light_data(7, light_data.index, light_data.range)
		pass_light_data(8, light_data.index, light_data.falloff)
		
		if type == 1:
			if not light_data.has("direction"):
				light_data.direction = Vector3.FORWARD
				light_data.spot_angle = deg2rad(45.0)
				light_data.spot_angle_attenuation = 1.0
			pass_light_data(9, light_data.index, light_data.direction.x)
			pass_light_data(10, light_data.index, light_data.direction.y)
			pass_light_data(11, light_data.index, light_data.direction.z)
			pass_light_data(12, light_data.index, light_data.spot_angle_attenuation)
			pass_light_data(13, light_data.index, light_data.spot_angle)
	
	lights[key] = light_data
	
	$LightScatter/ColorRect.material.set_shader_param("use_light_data", true)

func remove_light(key) -> void:
	var index : int = lights[key].index
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
	
	if not temp_light_img:
		temp_light_img = light_texture.get_data().duplicate()
		temp_light_img.lock()
	
	var index : int = light_data.index
	match param:
		"position":
			light_data.position = value
			pass_light_data(1, index, value.x)
			pass_light_data(2, index, value.y)
			pass_light_data(3, index, value.z)
		"color", "energy":
			if typeof(value) == TYPE_COLOR:
				light_data.color = value
			else:
				light_data.energy = value
			
			pass_light_data(4, index, light_data.color.r * light_data.energy)
			pass_light_data(5, index, light_data.color.g * light_data.energy)
			pass_light_data(6, index, light_data.color.b * light_data.energy)
		"range":
			light_data.range = value
			pass_light_data(7, index, light_data.range)
		"falloff":
			light_data.falloff = value
			pass_light_data(8, index, light_data.falloff)
		"direction":
			light_data.direction = value
			pass_light_data(9, light_data.index, light_data.direction.x)
			pass_light_data(10, light_data.index, light_data.direction.y)
			pass_light_data(11, light_data.index, light_data.direction.z)
		"spot_angle_attenuation":
			light_data.spot_angle_attenuation = value
			pass_light_data(12, light_data.index, light_data.spot_angle_attenuation)
		"spot_angle":
			light_data.spot_angle = cos(deg2rad(value))
			pass_light_data(13, light_data.index, light_data.spot_angle)

func pass_light_data(index : int, light_index : int, value) -> void:
	temp_light_img.set_pixel(index, light_index, Color(value, 0,0,0))

class LightIndexSorter:
	static func sort_ascending(a, b) -> bool:
		if a.index < b.index:
			return true
		return false

