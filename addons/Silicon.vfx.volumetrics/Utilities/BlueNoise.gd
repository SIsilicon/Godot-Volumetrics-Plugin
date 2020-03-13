tool
extends Reference
class_name BlueNoise

var noise_values := []
var data_size : int
var _seed : int

func _init(_seed : int) -> void:
	noise_values = Array(preload("BlueNoise.png").get_data().get_data())
	data_size = noise_values.size()
	self._seed = wrapi(_seed, 0, data_size)

func next() -> float:
	var value = noise_values[_seed] / 255.0
	_seed = wrapi(_seed + 1, 0, data_size)
	return value
