tool
extends Object
class_name CameraMatrix

## Based on:
## https://github.com/godotengine/godot/blob/master/core/math/camera_matrix.cpp

const PERSPECTIVE_IDENTITY = [
		Plane(1, 0, 0, 0),
		Plane(0, 1, 0, 0),
		Plane(0, 0, 1, 0),
		Plane(0, 0, 0, 1)
]

static func get_perspective_matrix(fov : float, aspect : float, near : float, far : float, flip_fov : bool) -> Array:
	if flip_fov:
		fov = get_fovy(fov, 1.0 / aspect)
	
	var radians := fov / 2.0 * PI / 180.0
	
	var delta_z := far - near
	var sine := sin(radians)
	
	if (delta_z == 0) || (sine == 0) || (aspect == 0):
		return PERSPECTIVE_IDENTITY.duplicate()
	
	var cotangent := cos(radians) / sine
	
	var matrix := PERSPECTIVE_IDENTITY.duplicate()
	matrix[0].x = cotangent / aspect
	matrix[1].y = cotangent
	matrix[2].z = -(far + near) / delta_z
	matrix[2].d = -1
	matrix[3].z = -2 * near * far / delta_z
	matrix[3].d = 0
	
	return matrix

static func get_orthogonal_asym_matrix(left : float, right : float, bottom : float, top : float, near : float, far : float) -> Array:
	var matrix := PERSPECTIVE_IDENTITY.duplicate()
	matrix[0].x = 2.0 / (right - left)
	matrix[3].x = -((right + left) / (right - left))
	matrix[1].y = 2.0 / (top - bottom)
	matrix[3].y = -((top + bottom) / (top - bottom))
	matrix[2].z = -2.0 / (far - near)
	matrix[3].z = -((far + near) / (far - near))
	matrix[3].d = 1.0
	return matrix

static func get_orthogonal_matrix(size : float, aspect : float, near : float, far : float, flip_fov : bool) -> Array:
	if not flip_fov:
		size *= aspect
	
	return get_orthogonal_asym_matrix(-size / 2, +size / 2, -size / aspect / 2, +size / aspect / 2, near, far)

static func get_frustum_asym_matrix(left : float, right : float, bottom : float, top : float, near : float, far : float) -> Array:
	var matrix := PERSPECTIVE_IDENTITY.duplicate()
	var x := 2 * near / (right - left)
	var y := 2 * near / (top - bottom)
	
	var a := (right + left) / (right - left)
	var b := (top + bottom) / (top - bottom)
	var c := -(far + near) / (far - near)
	var d := -2 * far * near / (far - near)
	
	matrix[0].x = x; matrix[0].y = 0; matrix[0].z = a; matrix[0].d = 0
	matrix[1].x = 0; matrix[1].y = y; matrix[1].z = b; matrix[1].d = 0
	matrix[2].x = 0; matrix[2].y = 0; matrix[2].z = c; matrix[2].d = d
	matrix[3].x = 0; matrix[3].y = 0; matrix[3].z =-1; matrix[3].d = 0
	return matrix

static func set_frustum_matrix(size : float, aspect : float, offset : Vector2, near : float, far : float, flipfov : bool) -> Array:
	if not flipfov:
		size *= aspect
	
	return get_frustum_asym_matrix(-size / 2 + offset.x, +size / 2 + offset.x, -size / aspect / 2 + offset.y, +size / aspect / 2 + offset.y, near, far)

static func get_fovy(fovx : float, aspect : float) -> float:
	return rad2deg(atan(aspect * tan(deg2rad(fovx) * 0.5)) * 2.0)

static func pass_as_uniform(material : ShaderMaterial, name : String, param : Array) -> void:
	for i in 4:
		material.set_shader_param(name + str(i), param[i])
