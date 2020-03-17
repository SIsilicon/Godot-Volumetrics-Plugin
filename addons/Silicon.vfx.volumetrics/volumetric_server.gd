tool
extends Node

var plugin

const PROJECT_PROPERTIES := [
	["rendering/quality/volumetric/start", 0.1],
	["rendering/quality/volumetric/end", 50],
	["rendering/quality/volumetric/distribution", 0.8],
	["rendering/quality/volumetric/tile_size", 2],
	["rendering/quality/volumetric/samples", 1],
	["rendering/quality/volumetric/volumetric_shadows", false]
]

var default_material := preload("VolumeMaterial/default_material.tres")

export var start := 0.1 setget set_start
export var end := 100.0 setget set_end

export var tile_size := 4 setget set_tile_size
export var samples := 64 setget set_samples
export(float, 0.0, 1.0) var distribution := 0.7 setget set_distribution
export var volumetric_shadows := false setget set_volumetric_shadows

var volume_id := 0
var volumes := []

var lights := []

var renderer := preload("Renderer/volumetric_renderer.tscn").instance()

var is_ready := true

func _enter_tree() -> void:
	process_priority = 512
	add_child(renderer)
	
	get_tree().connect("node_added", self, "_on_node_added")
	get_tree().connect("node_removed", self, "_on_node_removed")
	
	update_lights_in_tree(get_tree().root)

func add_volume() -> int:
	if not is_ready:
		yield(self, "ready")
	
	renderer.add_volume(volume_id)
	volumes.append(volume_id)
	renderer.set_volume_param(volume_id, "shader", default_material.shaders)
	volume_id += 1
	
	return volume_id - 1

func remove_volume(vol_id : int) -> void:
	if not is_ready:
		yield(self, "ready")
	
	if volumes.has(vol_id):
		renderer.remove_volume(vol_id)
		volumes.erase(vol_id)
	else:
		printerr("Volume ID " + str(vol_id) + " does not exist!")

func set_volume_param(vol_id : int, param : String, value) -> bool:
	if not is_ready:
		yield(self, "ready")
	
	if volumes.has(vol_id):
		if param == "shader" and (not value or value.empty()):
			value = default_material.shaders
		renderer.set_volume_param(vol_id, param, value)
	else:
		printerr("Volume ID " + str(vol_id) + " does not exist!")
		return false
	return true

func _process(_delta : float) -> void:
	renderer.enabled = not volumes.empty()
	
	for light in lights:
		update_light(light)
	
	for property in PROJECT_PROPERTIES:
		var name : String = property[0].split("/")[-1]
		
		var value
		if ProjectSettings.has_setting(property[0]):
			value = ProjectSettings.get_setting(property[0])
		else:
			value = property[1]
		
		if name == "samples":
			value = [32,64,128,256,512][value]
		elif name == "tile_size":
			value = [2,4,8,16][value]
		
		self.set(name, value)

func _exit_tree() -> void:
	for volume in volumes:
		remove_volume(volume)
	for light in lights:
		_on_node_removed(light)

func set_start(value : float) -> void:
	start = value
	if not is_ready:
		yield(self, "ready")
	renderer.start = start

func set_end(value : float) -> void:
	end = value
	if not is_ready:
		yield(self, "ready")
	renderer.end = end

func set_tile_size(value : int) -> void:
	tile_size = value
	if not is_ready:
		yield(self, "ready")
	renderer.tile_size = tile_size

func set_samples(value : int) -> void:
	samples = value
	if not is_ready:
		yield(self, "ready")
	renderer.samples = samples

func set_distribution(value : float) -> void:
	distribution = value
	if not is_ready:
		yield(self, "ready")
	renderer.distribution = distribution

func set_volumetric_shadows(value : bool) -> void:
	volumetric_shadows = value
	if not is_ready:
		yield(self, "ready")
	renderer.volumetric_shadows = volumetric_shadows

func update_lights_in_tree(node : Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		update_lights_in_tree(child)

func update_light(light : Light) -> void:
	if not light.has_meta("vol_id"):
		return
	
	var id = light.get_meta("vol_id")
	renderer.set_light_param(id, "color", light.light_color * (2.0 * float(not light.light_negative) - 1.0))
	renderer.set_light_param(id, "energy", light.light_energy * float(light.is_visible_in_tree()))
	
	if light is DirectionalLight:
		renderer.set_light_param(id, "position", light.global_transform.basis.z)
	else:
		renderer.set_light_param(id, "position", light.global_transform.origin)
		
		if light is OmniLight:
			renderer.set_light_param(id, "range", light.omni_range)
			renderer.set_light_param(id, "falloff", light.omni_attenuation)
		else:
			renderer.set_light_param(id, "range", light.spot_range)
			renderer.set_light_param(id, "falloff", light.spot_attenuation)
			renderer.set_light_param(id, "direction", light.global_transform.basis.z)
			renderer.set_light_param(id, "spot_angle", light.spot_angle)
			renderer.set_light_param(id, "spot_angle_attenuation", light.spot_angle_attenuation)

func _on_node_added(node : Node) -> void:
	if node is Light and not lights.has(node):
		lights.append(node)
		
		var type : int
		match node.get_class():
			"OmniLight": type = 0
			"SpotLight": type = 1
			"DirectionalLight": type = 2
		
		renderer.add_light(volume_id, type)
		node.set_meta("vol_id", volume_id)
		
		update_light(node)
		
		volume_id += 1

func _on_node_removed(node : Node) -> void:
	if node is Light and lights.has(node):
		lights.erase(node)
		renderer.remove_light(node.get_meta("vol_id"))
		node.remove_meta("vol_id")
