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
		var property
		if label == "Volumetric Energy":
			property = get_edited_object().has_meta("volumetric")
			if not property:
				get_edited_object().set_meta("volumetric", 1.0)
				_process(_delta)
				return
			else:
				property = get_edited_object().get_meta("volumetric")
			
			if property != control.value:
				control.value = property
		
		elif label == "Apply Volumetrics":
			property = get_edited_object().has_meta("apply_volumetrics")
			if not property:
				get_edited_object().set_meta("apply_volumetrics", false)
				_process(_delta)
				return
			else:
				property = get_edited_object().get_meta("apply_volumetrics")
			
			if property != control.pressed:
				control.pressed = property

func set_label(value : String) -> void:
	label = value
	
	if label == "Volumetric Energy":
		control = EditorSpinSlider.new()
		control.flat = true
		control.min_value = 0
		control.max_value = 16
		control.allow_greater = true
		control.step = 0.01
		control.value = 1.0
		add_child(control)
		control.connect("value_changed", self, "_on_property_changed")
	
	elif label == "Apply Volumetrics":
		control = CheckBox.new()
		control.text = "On"
		add_child(control)
		control.connect("pressed", self, "_on_property_changed", [0.0])

func _on_property_changed(value : float) -> void:
	if label == "Volumetric Energy":
		get_edited_object().set_meta("volumetric", control.value)
	elif label == "Apply Volumetrics":
		get_edited_object().set_meta("apply_volumetrics", control.pressed)
