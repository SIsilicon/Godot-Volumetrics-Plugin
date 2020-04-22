tool
extends Viewport

var direction := Vector3.FORWARD setget set_direction
var energy := 1.0

var scene_aabb := AABB()

func _ready() -> void:
	$Camera.cull_mask |= 1 << 20
	set_meta("_directional_light", true)

func set_direction(value : Vector3) -> void:
	direction = value
	if not $Camera.is_inside_tree():
		yield(self, "ready")
	$Camera.look_at($Camera.translation - direction, Vector3.UP)

func _process(_delta) -> void:
	var viewport : Viewport = get_parent().get_viewport()
	var camera : Camera = viewport.get_camera()
	var near : float = get_parent().get_parent().start
	var far : float = get_parent().get_parent().end
	
	if scene_aabb.size.length() > 0.0:
		var frustum_center := camera.project_position(
			get_parent().get_viewport().size / 2.0,
			(near + far) / 2.0
		)
		var frustum_points := frustum_points(camera, viewport, near, far)
		var frustum_length : float = frustum_points[0].distance_to(frustum_points[-1])
		
		$Camera.translation = frustum_center
		$Camera.translate_object_local(Vector3(0, 0, frustum_length / 2.0))
		var offset : Vector3 = $Camera.get_camera_transform().xform_inv(frustum_center)
		$Camera.translate_object_local(offset)
		
		var ortho : AABB
		var view_scene_aabb : AABB = $Camera.get_camera_transform().xform_inv(scene_aabb)
		$Camera.translate_object_local(Vector3(0, 0, view_scene_aabb.end.z + 1.0))
		
		for i in 8:
			var view_frustum_point = $Camera.get_camera_transform().xform_inv(frustum_points[i])
			if ortho:
				ortho = ortho.expand(view_frustum_point)
			else:
				ortho = AABB(view_frustum_point, Vector3.ZERO)
		ortho = ortho.intersection(view_scene_aabb)
		ortho.position.z = 1.0
		ortho.end.z = view_scene_aabb.end.z - view_scene_aabb.position.z + 1.0
		
		$Camera.size = frustum_length
		$Camera.near = ortho.position.z
		$Camera.far = ortho.end.z

func get_shadow_matrix() -> Matrix4:
	var projection_matrix := Matrix4.new()
	projection_matrix = projection_matrix.get_camera_projection($Camera)
	
	return projection_matrix.mul(Matrix4.new($Camera.transform.inverse()))

static func frustum_points(camera : Camera, viewport : Viewport, near : float, far : float) -> Array:
	var points := [
		Vector3(0, 0, near),
		Vector3(viewport.size.x, 0, near),
		Vector3(0, viewport.size.y, near),
		Vector3(viewport.size.x, viewport.size.y, near),
		Vector3(0, 0, far),
		Vector3(viewport.size.x, 0, far),
		Vector3(0, viewport.size.y, far),
		Vector3(viewport.size.x, viewport.size.y, far)
	]
	
	for i in 8:
		points[i] = camera.project_position(Vector2(points[i].x, points[i].y), points[i].z)
	
	return points
