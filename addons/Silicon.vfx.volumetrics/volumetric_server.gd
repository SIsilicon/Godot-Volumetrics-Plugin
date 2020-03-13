tool
extends Node

var plugin

var project_properties := [
	"rendering/quality/volumetric/start",
	"rendering/quality/volumetric/end",
	"rendering/quality/volumetric/distribution",
	"rendering/quality/volumetric/tile_size",
	"rendering/quality/volumetric/samples",
]

var default_material := preload("VolumeMaterial/default_material.tres")

export var start := 0.1 setget set_start
export var end := 100.0 setget set_end

export var tile_size := 4 setget set_tile_size
export var samples := 64 setget set_samples
export(float, 0.0, 1.0) var distribution := 0.7 setget set_distribution

var volume_id := 0
var volumes := []

var renderer := preload("Renderer/volumetric_renderer.tscn").instance()

var is_ready := true

func _enter_tree() -> void:
	process_priority = 512
	add_child(renderer)

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
	
	for property in project_properties:
		var name : String = property.split("/")[-1]
#		if not ProjectSettings.has_setting(property):
#			continue
#
		var value = ProjectSettings.get_setting(property)
		
		if value == null:
			return
		
		if name == "samples":
			value = [32,64,128,256,512][value]
		
		self.set(name, value)

func _exit_tree() -> void:
	for volume in volumes:
		remove_volume(volume)

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
