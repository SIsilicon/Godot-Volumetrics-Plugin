tool
extends Node
class_name SceneBounds

var root : Viewport

var geometry_instances := []

func get_aabb() -> AABB:
	var aabb := AABB(Vector3.ONE * 16384, Vector3.ONE * -32768)
	for instance in geometry_instances:
		if weakref(instance).get_ref() != null:
			aabb = aabb.merge(instance.get_transformed_aabb())
	return aabb

func _init(root : Viewport) -> void:
	self.root = root

func _enter_tree() -> void:
	get_tree().connect("node_added", self, "_on_node_added")
	get_tree().connect("node_removed", self, "_on_node_removed")
	
	update_geometry_in_scene(root)

func update_geometry_in_scene(node : Node) -> void:
	_on_node_added(node)
	if not node is Viewport or node == root:
		for child in node.get_children():
			update_geometry_in_scene(child)

func _on_node_added(node : Node) -> void:
	if node is GeometryInstance:
		geometry_instances.append(node)

func _on_node_removed(node : Node) -> void:
	geometry_instances.erase(node)
