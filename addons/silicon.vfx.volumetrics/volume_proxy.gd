tool
extends Spatial

enum {
	GLOBAL,
	LOCAL_BOX,
	LOCAL_SPHERE
}

var material : VolumetricMaterial setget set_material
var bounds_mode := LOCAL_BOX setget set_bounds_mode
var extents := Vector3.ONE setget set_extents
var bounds_fade := Vector3.ZERO setget set_bounds_fade

var vol_id := -1
var vis_notifier := VisibilityNotifier.new()
var in_view = true

func _get_property_list() -> Array:
	var properties := [
		{name="VolumeProxy", type=TYPE_NIL, usage=PROPERTY_USAGE_CATEGORY},
		{name="material", type=TYPE_OBJECT, hint=PROPERTY_HINT_RESOURCE_TYPE, hint_string="VolumetricMaterial"},
		{name="bounds_mode", type=TYPE_INT, hint=PROPERTY_HINT_ENUM, hint_string="Global,Local Box,Local Sphere"},
	]
	
	if bounds_mode != GLOBAL:
		properties += [
			{name="extents", type=TYPE_VECTOR3},
			{name="bounds_fade", type=TYPE_VECTOR3},
		]
	
	return properties

func _enter_tree() -> void:
	set_disable_scale(true)
	
	vol_id = _get_volumetric_server().add_volume(get_viewport())
	set_material(material)
	set_bounds_mode(bounds_mode)
	set_extents(extents)
	set_bounds_fade(bounds_fade)

func _ready() -> void:
	if not vis_notifier.is_inside_tree():
		add_child(vis_notifier)

func _process(delta : float) -> void:
	var vol_visible := is_visible_in_tree()
	if bounds_mode != GLOBAL:
		vol_visible = vol_visible and vis_notifier.is_on_screen()
	_get_volumetric_server().volume_set_param(vol_id, "transform", global_transform.orthonormalized())
	_get_volumetric_server().volume_set_param(vol_id, "visible", vol_visible)

func _exit_tree() -> void:
	_get_volumetric_server().remove_volume(vol_id)
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
		_get_volumetric_server().volume_set_param(vol_id, "shader", material.shaders)

func set_extents(value : Vector3) -> void:
	if not is_inside_tree():
		extents = value
		return
	
	extents.x = max(value.x, 0.01)
	extents.y = max(value.y, 0.01)
	extents.z = max(value.z, 0.01)
	_get_volumetric_server().volume_set_param(vol_id, "bounds_extents", extents)
	update_gizmo()
	
	vis_notifier.aabb = AABB(-extents, extents*2.0)

func set_bounds_mode(value : int) -> void:
	if not is_inside_tree():
		bounds_mode = value
		return
	
	bounds_mode = value
	set_extents(extents)
	
	if value == GLOBAL:
		for volume in get_tree().get_nodes_in_group("_global_volume"):
			volume.set_bounds_mode(LOCAL_BOX)
		bounds_mode = value
		add_to_group("_global_volume")
	elif is_in_group("_global_volume"):
		remove_from_group("_global_volume")
	
	if vol_id != -1:
		_get_volumetric_server().volume_set_param(vol_id, "bounds_mode", bounds_mode)
	property_list_changed_notify()

func set_bounds_fade(value : Vector3) -> void:
	if not is_inside_tree():
		bounds_fade = value
		return
	
	bounds_fade.x = clamp(value.x, 0.0, 1.0)
	bounds_fade.y = clamp(value.y, 0.0, 1.0)
	bounds_fade.z = clamp(value.z, 0.0, 1.0)
	_get_volumetric_server().volume_set_param(vol_id, "bounds_fade", bounds_fade)

func _get_volumetric_server() -> Node:
	return get_tree().root.get_node("/root/VolumetricServer")

