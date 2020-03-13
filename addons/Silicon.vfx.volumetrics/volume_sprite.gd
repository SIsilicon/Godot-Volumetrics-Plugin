tool
extends Spatial

var material : VolumetricMaterial setget set_material

var vol_id := -1

func _get_property_list() -> Array:
	var properties := [
		{name="VolumeSprite", type=TYPE_NIL, usage=PROPERTY_USAGE_CATEGORY},
		{name="material", type=TYPE_OBJECT, hint=PROPERTY_HINT_RESOURCE_TYPE, hint_string="VolumetricMaterial"}
	]
	
	return properties

func _ready() -> void:
	var state = VolumetricServer.add_volume()
	vol_id = state
	set_material(material)

func _process(delta : float) -> void:
	if not VolumetricServer.set_volume_param(vol_id, "transform", global_transform):
		_ready()
	VolumetricServer.set_volume_param(vol_id, "visible", visible)

func _exit_tree() -> void:
	VolumetricServer.remove_volume(vol_id)
	if material:
		material.volumes.erase(vol_id)

func set_material(value : VolumetricMaterial) -> void:
	if not is_inside_tree():
		material = value
		return
	
	if material != null and material != value and material.volumes.has(vol_id):
		material.volumes.erase(vol_id)
	
	material = value
	
	if material:
		if not material.volumes.has(vol_id):
			material.volumes.append(vol_id)
		
		material.set_all_params()
		if material.material_flags_dirty:
			yield(material, "shader_changed")
		VolumetricServer.set_volume_param(vol_id, "shader", material.shaders)
