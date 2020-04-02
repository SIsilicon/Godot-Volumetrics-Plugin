tool
extends Spatial

enum {
	GLOBAL,
	LOCAL_BOX,
	LOCAL_SPHERE
}

var material : VolumetricMaterial setget set_material
var bounds_mode := LOCAL_BOX setget set_bounds_mode

var vol_id := -1
var vis_notifier := VisibilityNotifier.new()

func _get_property_list() -> Array:
	var properties := [
		{name="VolumeSprite", type=TYPE_NIL, usage=PROPERTY_USAGE_CATEGORY},
		{name="material", type=TYPE_OBJECT, hint=PROPERTY_HINT_RESOURCE_TYPE, hint_string="VolumetricMaterial"},
		{name="bounds_mode", type=TYPE_INT, hint=PROPERTY_HINT_ENUM, hint_string="Global,Local Box,Local Sphere"}
	]
	
	return properties

func _enter_tree() -> void:
	if not vis_notifier.is_inside_tree():
		add_child(vis_notifier)
	
	vol_id = VolumetricServer.add_volume(get_viewport())
	set_material(material)
	set_bounds_mode(bounds_mode)

func _process(delta : float) -> void:
	var vol_visible := is_visible_in_tree()
	if bounds_mode != GLOBAL:
		vol_visible = vol_visible and vis_notifier.is_on_screen()
	VolumetricServer.volume_set_param(vol_id, "transform", global_transform)
	VolumetricServer.volume_set_param(vol_id, "visible", vol_visible)

func _exit_tree() -> void:
	VolumetricServer.remove_volume(vol_id)
	if material:
		material.volumes.erase(vol_id)
	vol_id == -1

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
		VolumetricServer.volume_set_param(vol_id, "shader", material.shaders)

func set_bounds_mode(value : int) -> void:
	if not is_inside_tree():
		bounds_mode = value
		return
	
	bounds_mode = value
	
	if value == GLOBAL:
		for volume in get_tree().get_nodes_in_group("_global_volume"):
			volume.set_bounds_mode(LOCAL_BOX)
		bounds_mode = value
		add_to_group("_global_volume")
	elif is_in_group("_global_volume"):
		remove_from_group("_global_volume")
	
	if vol_id != -1:
		VolumetricServer.volume_set_param(vol_id, "bounds_mode", bounds_mode)
