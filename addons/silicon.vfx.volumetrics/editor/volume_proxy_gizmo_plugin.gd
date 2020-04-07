tool
extends EditorSpatialGizmoPlugin

const VolumeProxy = preload("../volume_proxy.gd")

var current_volume : VolumeProxy
var editor_selection : EditorSelection
var undo_redo : UndoRedo

func _init() -> void:
	create_material("main", Color(1,1,0,0.15))
	create_material("lines", Color.yellow)
	create_handle_material("handles")

func get_name() -> String:
	return "VolumeProxy"

func has_gizmo(spatial : Spatial) -> bool:
	if spatial is VolumeProxy:
		return true
	return false

func redraw(gizmo : EditorSpatialGizmo) -> void:
	gizmo.clear()
	
	var volume := gizmo.get_spatial_node()
	
	if volume.bounds_mode == VolumeProxy.GLOBAL:
		return
	
	var corners := [
		Vector3(-1, -1, -1), Vector3(1, -1, -1),
		Vector3(-1, 1, -1), Vector3(1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1),
		Vector3(-1, 1, 1), Vector3(1, 1, 1)
	]
	
	var extents : Vector3 = volume.extents
	
	var lines := PoolVector3Array([
		corners[0] * extents, corners[1] * extents,
		corners[2] * extents, corners[3] * extents,
		corners[0] * extents, corners[2] * extents,
		corners[1] * extents, corners[3] * extents,
		corners[4] * extents, corners[5] * extents,
		corners[6] * extents, corners[7] * extents,
		corners[4] * extents, corners[6] * extents,
		corners[5] * extents, corners[7] * extents,
		corners[0] * extents, corners[4] * extents,
		corners[1] * extents, corners[5] * extents,
		corners[2] * extents, corners[6] * extents,
		corners[3] * extents, corners[7] * extents
	])
	var handles := PoolVector3Array([
		Vector3(extents.x, 0, 0),
		Vector3(0, extents.y, 0),
		Vector3(0, 0, extents.z)
	])
	
	var mesh := CubeMesh.new()
	mesh.size = extents * 2.0
	
	var arr_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = mesh.get_faces()
	# Create the Mesh.
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	arr_mesh.surface_set_material(0, get_material("main", gizmo))
	
	if volume == current_volume and volume in editor_selection.get_selected_nodes():
		gizmo.add_mesh(arr_mesh)
	
	gizmo.add_collision_triangles(arr_mesh.generate_triangle_mesh())
	gizmo.add_lines(lines, get_material("lines", gizmo))
	gizmo.add_handles(handles, get_material("handles", gizmo))

func get_handle_name(gizmo : EditorSpatialGizmo, index : int) -> String:
	return ["Extents X", "Extents Y", "Extents Z"][index]

func get_handle_value(gizmo : EditorSpatialGizmo, index : int):
	return gizmo.get_spatial_node().extents

func set_handle(gizmo : EditorSpatialGizmo, index : int, camera : Camera, point : Vector2):
	var volume := gizmo.get_spatial_node()
	
	var gi = volume.get_global_transform().affine_inverse()
	var extents : Vector3 = volume.extents
	
	var ray_from := camera.project_ray_origin(point)
	var ray_dir := camera.project_ray_normal(point)
	
	var cam_segment = [gi.xform(ray_from), gi.xform(ray_from + ray_dir * 16384)]
	
	var axis : Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][index]
	
	var closest_point := Geometry.get_closest_points_between_segments(Vector3.ZERO, axis * 16384, cam_segment[0], cam_segment[1])[0]
	match index:
		0: extents.x = max(closest_point.x, 0.01)
		1: extents.y = max(closest_point.y, 0.01)
		2: extents.z = max(closest_point.z, 0.01)
	volume.extents = extents
	volume.property_list_changed_notify()

func commit_handle(gizmo : EditorSpatialGizmo, index : int, restore, cancel := false) -> void:
	var volume := gizmo.get_spatial_node()
	
	if cancel:
		volume.extents = restore
		volume.property_list_changed_notify()
		return
	
	undo_redo.create_action("Change Volume Extents")
	undo_redo.add_do_method(volume, "set_extents", volume.extents)
	undo_redo.add_undo_method(volume, "set_extents", restore)
	undo_redo.commit_action()
	volume.property_list_changed_notify()
