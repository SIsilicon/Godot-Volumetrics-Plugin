tool
extends Node

var omni_range := 10.0 setget set_range
var position := Vector3.ZERO setget set_position

var size := Vector2(256, 256) setget set_size

var viewports : Array

func _ready() -> void:
	viewports = [$Front, $Back, $Left, $Right, $Up, $Down]
	
	for viewport in viewports:
		viewport.get_child(0).cull_mask |= 1 << 20
	set_meta("_omni_light", true)

func set_range(value : float) -> void:
	omni_range = value
	for viewport in viewports:
		viewport.get_child(0).far = omni_range

func set_position(value : Vector3) -> void:
	position = value
	for viewport in viewports:
		viewport.get_child(0).transform.origin = position

func set_size(value : Vector2) -> void:
	size = value
	for viewport in viewports:
		viewport.size = size / 3.0

func get_shadow_matrix() -> Matrix4:
	return Matrix4.new(Transform().translated(-position))
