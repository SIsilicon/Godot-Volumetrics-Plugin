tool
extends Reference
class_name FrustumAABBIntersection

var frustum := []

func _init(camera : Camera) -> void:
	frustum = camera.get_frustum()

# Algorithm from
# https://www.iquilezles.org/www/articles/frustumcorrect/frustumcorrect.htm
func is_inside_frustum(aabb : AABB) -> bool:
	
	# check box outside/inside of frustum
	for i in 6:
		var out := 0
		out += float(frustum[i].is_point_over(aabb.get_endpoint(0)))
		out += float(frustum[i].is_point_over(aabb.get_endpoint(1)))
		out += float(frustum[i].is_point_over(aabb.get_endpoint(2)))
		out += float(frustum[i].is_point_over(aabb.get_endpoint(3)))
		out += float(frustum[i].is_point_over(aabb.get_endpoint(4)))
		out += float(frustum[i].is_point_over(aabb.get_endpoint(5)))
		out += float(frustum[i].is_point_over(aabb.get_endpoint(6)))
		out += float(frustum[i].is_point_over(aabb.get_endpoint(7)))
		if(out == 8):
			return false
	
	return true

