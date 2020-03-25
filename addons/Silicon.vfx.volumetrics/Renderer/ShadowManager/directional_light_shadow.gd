tool
extends Viewport

var direction := Vector3.FORWARD setget set_direction

func _ready() -> void:
	$Camera.cull_mask |= 1 << 20
	set_meta("_directional_light", true)

func set_direction(value : Vector3) -> void:
	direction = value
	if not $Camera.is_inside_tree():
		yield(self, "ready")
	$Camera.look_at($Camera.translation - direction, Vector3.UP)

func get_shadow_matrix() -> Matrix4:
	var projection_matrix := Matrix4.new()
	projection_matrix = projection_matrix.get_camera_projection($Camera)
	
	return projection_matrix.mul(Matrix4.new($Camera.transform.inverse()))
