tool
extends Reference
class_name Halton

static func halton(index : int, base : int) -> float:
	var f := 1.0
	var r := 0.0
	
	while index > 0:
		f /= base
		r += f * (index % base)
		index /= base
	
	return r

static func genearate_sequence_2D(bases : Vector2, size : int) -> Array:
	var sequence := []
	
	for i in size:
		var vector := Vector2(halton(i, bases.x), halton(i, bases.y))
		sequence.append(vector)
	
	return sequence

static func genearate_sequence_3D(bases : Vector3, size : int) -> Array:
	var sequence := []
	
	for i in size:
		var vector := Vector3(halton(i, bases.x), halton(i, bases.y), halton(i, bases.z))
		sequence.append(vector)
	
	return sequence
