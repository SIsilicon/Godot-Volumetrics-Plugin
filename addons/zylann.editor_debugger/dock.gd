tool
extends Control

const Util = preload("util.gd")

signal node_selected(node)

onready var _inspection_checkbox = get_node("VBoxContainer/ShowInInspectorCheckbox")
onready var _label = get_node("VBoxContainer/Label")
onready var _tree_view = get_node("VBoxContainer/Tree")

var _update_interval = 1.0
var _time_before_next_update = 0.0
var _control_highlighter = null


func _enter_tree():
	if Util.is_in_edited_scene(self):
		return
	_control_highlighter = ColorRect.new()
	_control_highlighter.color = Color(1, 1, 0, 0.2)
	_control_highlighter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_control_highlighter.hide()
	get_viewport().call_deferred("add_child", _control_highlighter)


func _exit_tree():
	if _control_highlighter != null:
		_control_highlighter.queue_free()


func _process(delta):
	if Util.is_in_edited_scene(self):
		set_process(false)
		return
		
	var viewport = get_viewport()
	_label.text = str(viewport.get_mouse_position())
	
	_time_before_next_update -= delta
	if _time_before_next_update <= 0:
		_time_before_next_update = _update_interval
		_update_tree()


func _update_tree():
	var root = get_tree().get_root()
	if root == null:
		_tree_view.clear()
		return

	#print("Updating tree")
	
	var root_view = _tree_view.get_root()
	if root_view == null:
		root_view = _create_node_view(root, null)
	
	_update_branch(root, root_view)


func _update_branch(root, root_view):
	if root_view.collapsed and root_view.get_children() != null:
		# Don't care about collapsed nodes.
		# The editor is a big tree, don't waste cycles on things you can't see
		return
	
	var children_views = _get_tree_item_children(root_view)
	
	for i in root.get_child_count():
		var child = root.get_child(i)
		var child_view
		if i >= len(children_views):
			child_view = _create_node_view(child, root_view)
			children_views.append(child_view)
		else:
			child_view = children_views[i]
			var child_view_name = child_view.get_metadata(0)
			if child.name != child_view_name:
				_update_node_view(child, child_view)
		_update_branch(child, child_view)
	
	if root.get_child_count() < len(children_views):
		for i in range(root.get_child_count(), len(children_views)):
			children_views[i].free()


func _create_node_view(node, parent_view):
	#print("Create view for ", node)
	assert(node is Node)
	assert(parent_view == null or parent_view is TreeItem)
	var view = _tree_view.create_item(parent_view)
	view.collapsed = true
	_update_node_view(node, view)
	return view


func _update_node_view(node, view):
	assert(node is Node)
	assert(view is TreeItem)
	view.set_text(0, str(node.get_class(), ": ", node.name))
	view.set_metadata(0, node.name)

			
static func _get_tree_item_children(item):
	var children = []
	var child = item.get_children()
	if child == null:
		return children
	children.append(child)
	child = child.get_next()
	while child != null:
		children.append(child)
		child = child.get_next()
	return children


func _on_Tree_item_selected():
	var node_view = _tree_view.get_selected()
	var node = _get_node_from_view(node_view)
	
	print("Selected ", node)
	
	_highlight_node(node)
	
	emit_signal("node_selected", node)


func _highlight_node(node):
	if node == null:
		_control_highlighter.hide()
	elif node is Control:
		var r = node.get_global_rect()
		_control_highlighter.rect_position = r.position
		_control_highlighter.rect_size = r.size
		_control_highlighter.show()
	else:
		_control_highlighter.hide()


func _get_node_from_view(node_view):
	if node_view.get_parent() == null:
		return get_tree().get_root()
	
	# Reconstruct path
	var path = node_view.get_metadata(0)
	var parent_view = node_view
	while parent_view.get_parent() != null:
		parent_view = parent_view.get_parent()
		# Exclude root
		if parent_view.get_parent() == null:
			break
		path = str(parent_view.get_metadata(0), "/", path)
	
	var node = get_tree().get_root().get_node(path)
	return node


func _focus_in_tree(node):
	_update_tree()
	
	var parent = get_tree().get_root()
	var path = node.get_path()
	var parent_view = _tree_view.get_root()
	
	var node_view = null
	
	for i in range(1, path.get_name_count()):
		var part = path.get_name(i)
		print(part)
		
		var child_view = parent_view.get_children()
		if child_view == null:
			_update_branch(parent, parent_view)
		
		child_view = parent_view.get_children()
		
		while child_view != null and child_view.get_metadata(0) != part:
			child_view = child_view.get_next()
		
		if child_view == null:
			node_view = parent_view
			break
		
		node_view = child_view
		parent = parent.get_node(part)
		parent_view = child_view
	
	if node_view != null:
		_uncollapse_to_root(node_view)
		node_view.select(0)
		_tree_view.ensure_cursor_is_visible()


static func _uncollapse_to_root(node_view):
	var parent_view = node_view.get_parent()
	while parent_view != null:
		parent_view.collapsed = false
		parent_view = parent_view.get_parent()


static func _get_index_path(node):
	var ipath = []
	while node.get_parent() != null:
		ipath.append(node.get_index())
		node = node.get_parent()
	ipath.invert()
	return ipath


func _on_Tree_nothing_selected():
	_control_highlighter.hide()


func _input(event):
	if event is InputEventKey:
		if event.pressed:
			if event.scancode == KEY_F12:
				pick(get_viewport().get_mouse_position())


func pick(mpos):
	var root = get_tree().get_root()
	var node = _pick(root, mpos)
	if node != null:
		print("Picked ", node, " at ", node.get_path())
		_focus_in_tree(node)
	else:
		_highlight_node(null)


func is_inspection_enabled():
	return _inspection_checkbox.pressed


func _pick(root, mpos, level = 0):
	
#	var s = ""
#	for i in level:
#		s = str(s, "  ")
#
#	print(s, "Looking at ", root, ": ", root.name)
	
	var node = null
	
	for i in root.get_child_count():
		var child = root.get_child(i)
		
		if (child is CanvasItem and not child.visible):
			#print(s, child, " is invisible or viewport")
			continue
		if child is Viewport:
			continue
		if child == _control_highlighter:
			continue
		
		if child is Control and child.get_global_rect().has_point(mpos):
			var c = _pick(child, mpos, level + 1)
			if c != null:
				return c
			else:
				node = child
		else:
			var c = _pick(child, mpos, level + 1)
			if c != null:
				return c
	
	return node


func _on_ShowInInspectorCheckbox_toggled(button_pressed):
	pass
