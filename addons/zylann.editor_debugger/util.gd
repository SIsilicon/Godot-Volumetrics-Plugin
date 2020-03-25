tool


static func get_node_in_parents(node, klass):
	while node != null:
		node = node.get_parent()
		if node != null and node is klass:
			return node
	return null


static func is_in_edited_scene(node):
	#                               .___.
	#           /)               ,-^     ^-. 
	#          //               /           \
	# .-------| |--------------/  __     __  \-------------------.__
	# |WMWMWMW| |>>>>>>>>>>>>> | />>\   />>\ |>>>>>>>>>>>>>>>>>>>>>>:>
	# `-------| |--------------| \__/   \__/ |-------------------'^^
	#          \\               \    /|\    /
	#           \)               \   \_/   /
	#                             |       |
	#                             |+H+H+H+|
	#                             \       /
	#                              ^-----^
	# TODO https://github.com/godotengine/godot/issues/17592
	# This may break some day, don't fly planes with this bullshit.
	# Obviously it won't work for nested viewports since that's basically what this function checks.
	if not node.is_inside_tree():
		return false
	var vp = get_node_in_parents(node, Viewport)
	if vp == null:
		return false
	return vp.get_parent() != null

