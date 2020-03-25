tool
extends EditorInspectorPlugin

var parsed := []

func can_handle(object : Object) -> bool:
	parsed.clear()
	if object is Light:
		return true
	else:
		return false

func parse_category(object : Object, category : String) -> void:
	if category == "Light" and not "Light" in parsed:
		
		var volumetric = preload("editor_property.gd").new()
		volumetric.label = "Volumetric Energy"
		
		add_property_editor("volumetric", volumetric)
		parsed.append("Light")

