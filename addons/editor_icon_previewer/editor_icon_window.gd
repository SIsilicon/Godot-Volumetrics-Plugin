tool
extends AcceptDialog

signal update_request()

onready var search_box = $body/search/box
onready var search_box_count_label = $body/search/found

onready var icons_control = $body/icons
onready var previews_container = icons_control.get_node("previews/container")
onready var previews_scroll = icons_control.get_node("previews")
onready var icon_info = icons_control.get_node("info/icon")

onready var icon_preview_size_range = icon_info.get_node("params/size/range")
onready var icon_info_label = icon_info.get_node("label")
onready var icon_preview = icon_info.get_node("preview")
onready var icon_copied_label = icon_info.get_node("copied")
onready var icon_size_label = icon_info.get_node("size")
onready var icon_preview_size = icon_info.get_node("params/size/pixels")

const SELECT_ICON_MSG = "Select any icon."
const ICON_SIZE_MSG = "Icon size: "
const NUMBER_ICONS_MSG = "Found: "
const SNIPPET_TEMPLATE = "get_icon(\"%s\", \"EditorIcons\")"

const MIN_ICON_SIZE = 16
const MAX_ICON_SIZE = 128

var icon_size = MIN_ICON_SIZE
var filter = ''

var _update_queued = false


func _ready():
	icon_info_label.text = SELECT_ICON_MSG

	icon_preview_size_range.min_value = MIN_ICON_SIZE
	icon_preview_size_range.max_value = MAX_ICON_SIZE

	icon_preview.rect_min_size = Vector2(MAX_ICON_SIZE, MAX_ICON_SIZE)

	if has_color("success_color", "Editor"):
		var color = get_color("success_color", "Editor")
		icon_copied_label.add_color_override("font_color", color);

	get_ok().hide() # give more space for icons

	_queue_update()


func _queue_update():

	if not is_inside_tree():
		return

	if _update_queued:
		return

	_update_queued = true

	call_deferred("_update_icons")


func add_icon(p_icon, p_name):
	var icon = TextureRect.new()
	icon.expand = true
	icon.texture = p_icon
	icon.rect_min_size = Vector2(icon_size, icon_size)
	icon.hint_tooltip = p_name
	icon.name = p_name

	icon.connect('gui_input', self, '_icon_gui_input', [icon])

	previews_container.add_child(icon)


func _icon_gui_input(event, icon):

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == BUTTON_LEFT:
			# Copy raw icon's name into the clipboard
			OS.clipboard = icon.hint_tooltip
			icon_copied_label.show()

		elif event.button_index == BUTTON_RIGHT:
			# Copy icon's name with embedded code into the clipboard
			var snippet = SNIPPET_TEMPLATE % [icon.hint_tooltip]
			OS.clipboard = snippet
			icon_copied_label.show()

	elif event is InputEventMouseMotion:
		# Preview hovered icon on the side panel
		icon_info_label.text = icon.hint_tooltip
		icon_preview.texture = icon.texture
		icon_size_label.text = ICON_SIZE_MSG + str(icon.texture.get_size())


func _input(event):
	if event is InputEventKey and event.is_pressed() and not event.echo:
		if event.alt and event.scancode == KEY_I:
			if not visible:
				display()
			else:
				hide()


func _notification(what):
	match what:
		NOTIFICATION_THEME_CHANGED:
			emit_signal("update_request")


func display():
	if previews_container.get_child_count() == 0:
		# First time, request to create previews by the plugin
		emit_signal("update_request")
		call_deferred('popup_centered_ratio', 0.5)
	else:
		popup_centered_ratio(0.5)


func clear():
	for idx in previews_container.get_child_count():
		previews_container.get_child(idx).queue_free()


func _on_size_changed(pixels):
	icon_size = int(clamp(pixels, MIN_ICON_SIZE, MAX_ICON_SIZE))
	_queue_update()


func _update_icons():
	var number = 0

	for idx in previews_container.get_child_count():
		var icon = previews_container.get_child(idx)

		if not filter.is_subsequence_ofi(icon.hint_tooltip):
			icon.visible = false
		else:
			icon.visible = true
			number += 1

		icon.rect_min_size = Vector2(icon_size, icon_size)
		icon.rect_size = icon.rect_min_size

	var sep = previews_container.get_constant('hseparation')
	var cols = int(previews_scroll.rect_size.x / (icon_size + sep))

	previews_container.columns = cols - 1
	icon_preview_size.text = str(icon_size) + " px"

	search_box_count_label.text = NUMBER_ICONS_MSG + str(number)

	_update_queued = false


func _on_window_visibility_changed():
	if visible:
		_queue_update()


func _on_window_resized():
	_queue_update()


func _on_search_text_changed(text):
	filter = text
	_queue_update()


func _on_container_mouse_exited():
	icon_info_label.text = SELECT_ICON_MSG
	icon_size_label.text = ''
	icon_copied_label.hide()
	icon_preview.texture = null


func _on_window_about_to_show():
	# For some reason can't get proper rect size, so need to wait
	yield(previews_container, 'sort_children')
	search_box.grab_focus()
	_queue_update()


func _on_window_popup_hide():
	# Reset
	filter = ''
	icon_size = MIN_ICON_SIZE

	search_box.text = filter
	icon_preview_size_range.value = icon_size
