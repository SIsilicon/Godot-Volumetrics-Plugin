tool
extends Node

var root : Viewport

var geometry_instances := []

func _get(property : String):
	if property == "aabb":
		var aabb := AABB(Vector3.ONE * -16384, Vector3.ONE * 32768)
		for instance in geometry_instances:
			aabb.merge(instance.get_transformed_aabb())

func _init(root : Viewport) -> void:
	self.root = root

func _enter_tree() -> void:
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
