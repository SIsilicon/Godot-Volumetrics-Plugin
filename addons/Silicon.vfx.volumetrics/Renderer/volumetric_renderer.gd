tool
extends Node

const SHADER_TEMPLATE = preload("volume_injection.shader")

var plugin

export var start := 0.1
export var end := 100.0

export var tile_size := 4
export var samples := 64 setget set_samples
export(float, 0.0, 1.0) var distribution := 0.7

export var density_multiplier := 1.0

var tiling := Vector2(8, 16)

var base_blend := 0.0

var camera : Camera
var camera_transform := Transform()
var prev_cam_transform := Transform()

export var enabled := true setget set_enabled

var canvas := QuadMesh.new()

var volumes := {}

var blue_random = BlueNoise.new(randi())

func _ready() -> void:
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
	
	for resolver in [$ResolveScatter/Canvas, $ResolveTransmit/Canvas, $SolidTransmit, $SolidScatter]:
		resolver.material_override.set_shader_param("vol_depth_params", vol_depth_params)
		resolver.material_override.set_shader_param("tile_factor", tiling)
	
	var sample_offset := Vector3(blue_random.next() / size.x, blue_random.next() / size.y, blue_random.next() / samples)
	for child in $Scatter.get_children() + $Extinction.get_children() + $Motion.get_children():
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
		var previous_transform : Transform
		if child.has_meta("previous_transform"):
			previous_transform = child.get_meta("previous_transform")
		else:
			previous_transform = child.global_transform
		material.set_shader_param("prev_world_matrix", previous_transform)
		child.set_meta("previous_transform", child.global_transform)
	
	var blend = float(base_blend) / (1.0 + Engine.get_frames_per_second()) * Engine.get_frames_per_second()
	$LightScatter/ColorRect.material.set_shader_param("blend", blend)
	$LightTransmit/ColorRect.material.set_shader_param("blend", blend)

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
		
		if get_tree():
			reset_taa()

func get_viewports() -> Array:
	var viewports := []
	for child in get_children():
		if child is Viewport:
			viewports.append(child)
	return viewports

func resize(size : Vector2) -> void:
	if size != $PrevScatter.size:
		for viewport in get_viewports():
			viewport.size = size
		reset_taa()

func reset_taa() -> void:
	base_blend = 0.0
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	base_blend = 0.95

func add_volume(key) -> void:
	var meshes := []
	
	for buffer in [$Scatter, $Extinction, $Motion]:
		var canvas_inst := MeshInstance.new()
		canvas_inst.extra_cull_margin = 16384
		canvas_inst.mesh = canvas
		canvas_inst.material_override = ShaderMaterial.new()
		canvas_inst.material_override.shader = SHADER_TEMPLATE
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
			
			var shader_fragments : Dictionary = value[idx]
			var code := SHADER_TEMPLATE.code.replace("/**GLOBALS**/", shader_fragments.globals)
			code = code.replace("/**FRAGMENT CODE**/", shader_fragments.fragment_code)
			material.shader = Shader.new()
			material.shader.code = code
	else:
		for mesh in volumes[key]:
			mesh.material_override.set_shader_param(param, value)
