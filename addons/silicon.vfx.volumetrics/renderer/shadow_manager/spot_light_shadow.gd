tool
extends Viewport

var spot_range := 10.0 setget set_range
var spot_angle := 45.0 setget set_angle

var position := Vector3.ZERO setget set_position
var direction := Vector3.FORWARD setget set_direction

func _ready() -> void:
	$Camera.cull_mask |= 1 << 20
	set_meta("_spot_light", true)

func set_range(value : float) -> void:
	spot_range = value
	$Camera.far = spot_range

func set_angle(value : float) -> void:
	spot_angle = value
	$Camera.fov = value * 2.0

func set_position(value : Vector3) -> void:
	position = value
	$Camera.transform.origin = position

func set_direction(value : Vector3) -> void:
	direction = value
	if not $Camera.is_inside_tree():
		yield(self, "ready")
	$Camera.look_at(position - direction, Vector3.UP)

func get_shadow_matrix() -> Matrix4:
	var projection_matrix := Matrix4.new()
	projection_matrix = projection_matrix.get_camera_projection($Camera)
	
	return projection_matrix.mul(Matrix4.new($Camera.transform.inverse()))
