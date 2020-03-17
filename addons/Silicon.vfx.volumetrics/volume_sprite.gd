tool
extends Spatial

var material : VolumetricMaterial setget set_material
var is_global := false setget set_global

var vol_id := -1
var vis_notifier := VisibilityNotifier.new()

func _get_property_list() -> Array:
	var properties := [
		{name="VolumeSprite", type=TYPE_NIL, usage=PROPERTY_USAGE_CATEGORY},
		{name="material", type=TYPE_OBJECT, hint=PROPERTY_HINT_RESOURCE_TYPE, hint_string="VolumetricMaterial"},
		{name="is_global", type=TYPE_BOOL}
	]
	
	return properties

func _ready() -> void:
	if not vis_notifier.is_inside_tree():
		add_child(vis_notifier)
	
	vol_id = VolumetricServer.add_volume()
	
	set_material(material)
	set_global(is_global)

func _process(delta : float) -> void:
	if not VolumetricServer.set_volume_param(vol_id, "transform", global_transform):
		_ready()
	
	var vol_visible := is_visible_in_tree()
	if not is_global:
		vol_visible = vol_visible and vis_notifier.is_on_screen()
	VolumetricServer.set_volume_param(vol_id, "visible", vol_visible)

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

func set_global(value : bool) -> void:
	is_global = value
	
	if not is_inside_tree():
		return
	
	if is_global:
		for volume in get_tree().get_nodes_in_group("_global_volume"):
			volume.set_global(false)
		is_global = value
		add_to_group("_global_volume")
	elif is_in_group("_global_volume"):
		remove_from_group("_global_volume")
	
	if vol_id != -1:
		VolumetricServer.set_volume_param(vol_id, "global", is_global)
