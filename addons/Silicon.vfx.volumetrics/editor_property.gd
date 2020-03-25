tool
extends EditorProperty

var control : Control

func _set(property : String, value) -> bool:
	if property == "label":
		set_label(value)
		return true
	return false

func _process(_delta : float) -> void:
	if get_edited_object():
		var property = get_edited_object().has_meta("volumetric")
		if not property:
			property = 1.0
		else:
			property = get_edited_object().get_meta("volumetric")
		
		if typeof(property) != TYPE_REAL:
			get_edited_object().set_meta("volumetric", 1.0)
			_process(_delta)
			return
		
		if property != control.value:
			control.value = property

func set_label(value : String) -> void:
	label = value
	
	control = EditorSpinSlider.new()
	control.min_value = 0
	control.max_value = 16
	control.allow_greater = true
	control.step = 0.01
	control.value = 1.0
	add_child(control)
	control.connect("value_changed", self, "_on_property_changed")

func _on_property_changed(value : float) -> void:
	get_edited_object().set_meta("volumetric", control.value)
