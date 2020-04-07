tool
extends WindowDialog

var resolution := 64
var tile_factor := Vector2.ONE

var editor_file_system : EditorFileSystem

func _ready() -> void:
	if get_tree().edited_scene_root != self:
		$VBoxContainer/Create.icon = get_icon("Texture3D", "EditorIcons")
		$Preview/ColorRect.material = $Preview/ColorRect.material.duplicate()
	
	for child in $VBoxContainer.get_children():
		if child is HBoxContainer and child.get_child(1) is SpinBox:
			_on_value_changed(child.get_child(1).value, child.name.to_lower())

func _on_Create_pressed() -> void:
	$FileDialog.popup_centered()

func _on_file_selected(path : String) -> void:
	$Render/ColorRect.material = $Preview/ColorRect.material.duplicate()
	$Render/ColorRect.material.set_shader_param("tile_factor", tile_factor)
	$Render.size = tile_factor * resolution
	
	$Render.render_target_update_mode = Viewport.UPDATE_ONCE
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	
	var image : Image = $Render.get_texture().get_data()
	image.save_png(path)
	
	$FileDialog.hide()
	
	if editor_file_system:
		editor_file_system.scan()

func _on_value_changed(value, control : String) -> void:
	var preview_mat : ShaderMaterial = $Preview/ColorRect.material
	match control:
		"resolution":
			if value > resolution:
				resolution = value
				tile_factor = get_tile_dimension(resolution, true)
			else:
				resolution = value
				tile_factor = get_tile_dimension(resolution, false)
			$VBoxContainer/HBoxContainer/Horizontal.text = "Horizontal Slices: " + str(tile_factor.x)
			$VBoxContainer/HBoxContainer/Vertical.text = "Vertical Slices: " + str(tile_factor.y)
		"seed":
			preview_mat.set_shader_param("seed", value)
		"period":
			preview_mat.set_shader_param("size", value)
		"octaves":
			preview_mat.set_shader_param("octaves", value)
		"persistence":
			preview_mat.set_shader_param("persistence", value)
		"brightness":
			preview_mat.set_shader_param("brightness", value)
		"contrast":
			preview_mat.set_shader_param("contrast", value)

func get_tile_dimension(depth : int, increment := false) -> Vector2:
	var tile_dimension := Vector2(0, 0)
	var last_factor := depth
	
	for i in range(1, depth + 1):
		var candidate_factor := float(depth) / i
		if candidate_factor - floor(candidate_factor) == 0.0:
			if i == candidate_factor:
				tile_dimension = Vector2(i, i)
				break
			elif i == last_factor:
				tile_dimension = Vector2(int(candidate_factor), int(last_factor))
				break
			last_factor = candidate_factor
	
	if tile_dimension[0] == 1:
		resolution += 1 if increment else -1
		$VBoxContainer/Resolution/SpinBox.value = resolution
		return get_tile_dimension(resolution)
	else:
		return tile_dimension
