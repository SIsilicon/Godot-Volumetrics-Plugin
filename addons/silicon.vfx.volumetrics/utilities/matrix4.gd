tool
extends Reference
class_name Matrix4

var members := [
	[1, 0, 0, 0],
	[0, 1, 0, 0],
	[0, 0, 1, 0],
	[0, 0, 0, 1]
]

func _init(transform := Transform()) -> void:
	members[0][0] = transform.basis[0][0]
	members[0][1] = transform.basis[0][1]
	members[0][2] = transform.basis[0][2]
	members[1][0] = transform.basis[1][0]
	members[1][1] = transform.basis[1][1]
	members[1][2] = transform.basis[1][2]
	members[2][0] = transform.basis[2][0]
	members[2][1] = transform.basis[2][1]
	members[2][2] = transform.basis[2][2]
	members[3][0] = transform.origin[0]
	members[3][1] = transform.origin[1]
	members[3][2] = transform.origin[2]

func mul(matrix : Matrix4):
	var product := [[0,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]]
	for i in 4:
		for j in 4:
			for k in 4:
				product[i][j] += matrix.members[i][k] * members[k][j];
	
	var product_mat = new_matrix4()
	product_mat.members = product
	return product_mat

func to_transform() -> Transform:
	var transform := Transform()
	
	transform.basis[0][0] = members[0][0]
	transform.basis[0][1] = members[0][1]
	transform.basis[0][2] = members[0][2]
	transform.basis[1][0] = members[1][0]
	transform.basis[1][1] = members[1][1]
	transform.basis[1][2] = members[1][2]
	transform.basis[2][0] = members[2][0]
	transform.basis[2][1] = members[2][1]
	transform.basis[2][2] = members[2][2]
	transform.origin[0] = members[3][0]
	transform.origin[1] = members[3][1]
	transform.origin[2] = members[3][2]
	
	return transform

func get_camera_projection(camera : Camera):
	match camera.projection:
		Camera.PROJECTION_PERSPECTIVE:
			return perspective_matrix(camera.fov, camera.get_viewport().size.aspect(), camera.near, camera.far, camera.keep_aspect == Camera.KEEP_WIDTH)
		Camera.PROJECTION_ORTHOGONAL:
			return orthogonal_matrix(camera.size, camera.get_viewport().size.aspect(), camera.near, camera.far, camera.keep_aspect == Camera.KEEP_WIDTH)
		Camera.PROJECTION_FRUSTUM:
			return frustum_matrix(camera.size, camera.get_viewport().size.aspect(), camera.frustum_offset, camera.near, camera.far, camera.keep_aspect == Camera.KEEP_WIDTH)
	
	assert(false)
	return null

func get_element(idx : int) -> float:
	return members[idx/4][idx%4]

func get_data() -> Array:
	return members[0] + members[1] + members[2] + members[3]

func set_shader_param(material : ShaderMaterial, param : String) -> void:
	for i in 4:
		material.set_shader_param(param + str(i), Plane(members[i][0], members[i][1], members[i][2], members[i][3]))

func _to_string() -> String:
	return str(members)

static func perspective_matrix(fov : float, aspect : float, near : float, far : float, flip_fov : bool):
	if flip_fov:
		fov = get_fovy(fov, 1.0 / aspect)
	
	var radians := fov / 2.0 * PI / 180.0
	
	var delta_z := far - near
	var sine := sin(radians)
	
	if (delta_z == 0) || (sine == 0) || (aspect == 0):
		return new_matrix4()
	
	var cotangent := cos(radians) / sine
	
	var matrix = new_matrix4()
	matrix.members[0][0] = cotangent / aspect
	matrix.members[1][1] = cotangent
	matrix.members[2][2] = -(far + near) / delta_z
	matrix.members[2][3] = -1
	matrix.members[3][2] = -2 * near * far / delta_z
	matrix.members[3][3] = 0
	
	return matrix

static func orthogonal_asym_matrix(left : float, right : float, bottom : float, top : float, near : float, far : float):
	var matrix = new_matrix4()
	var members = matrix.members
	members[0][0] = 2.0 / (right - left)
	members[3][0] = -((right + left) / (right - left))
	members[1][1] = 2.0 / (top - bottom)
	members[3][1] = -((top + bottom) / (top - bottom))
	members[2][2] = -2.0 / (far - near)
	members[3][2] = -((far + near) / (far - near))
	members[3][3] = 1.0
	matrix.members = members
	return matrix

static func orthogonal_matrix(size : float, aspect : float, near : float, far : float, flip_fov : bool):
	if not flip_fov:
		size *= aspect
	
	return orthogonal_asym_matrix(-size / 2, +size / 2, -size / aspect / 2, +size / aspect / 2, near, far)

static func frustum_asym_matrix(left : float, right : float, bottom : float, top : float, near : float, far : float):
	var matrix = new_matrix4()
	var x := 2 * near / (right - left)
	var y := 2 * near / (top - bottom)
	
	var a := (right + left) / (right - left)
	var b := (top + bottom) / (top - bottom)
	var c := -(far + near) / (far - near)
	var d := -2 * far * near / (far - near)
	
	var members = matrix.members
	members[0][0] = x; members[0][1] = 0; members[0][2] = a; members[0][3] = 0
	members[1][0] = 0; members[1][1] = y; members[1][2] = b; members[1][3] = 0
	members[2][0] = 0; members[2][1] = 0; members[2][2] = c; members[2][3] = d
	members[3][0] = 0; members[3][1] = 0; members[3][2] =-1; members[3][3] = 0
	matrix.members = members
	return matrix

static func frustum_matrix(size : float, aspect : float, offset : Vector2, near : float, far : float, flipfov : bool):
	if not flipfov:
		size *= aspect
	
	return frustum_asym_matrix(-size / 2 + offset[0], +size / 2 + offset[0], -size / aspect / 2 + offset[1], +size / aspect / 2 + offset[1], near, far)

static func get_fovy(fovx : float, aspect : float) -> float:
	return rad2deg(atan(aspect * tan(deg2rad(fovx) * 0.5)) * 2.0)

static func new_matrix4():
	return load("res://addons/silicon.vfx.volumetrics/utilities/matrix4.gd").new()
