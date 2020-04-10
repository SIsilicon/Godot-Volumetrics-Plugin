extends Spatial

func _unhandled_input(event : InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		$Camera.mouse_mode = Input.MOUSE_MODE_VISIBLE
		$Camera.enabled = false
	elif event.is_action_pressed("toggle_gui"):
		$GUI.visible = not $GUI.visible
	elif event.is_action_pressed("exit"):
		get_tree().quit()
	elif event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT and not $Camera.enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		$Camera.mouse_mode = Input.MOUSE_MODE_CAPTURED
		$Camera.enabled = true
		$Camera.mouse_c = true

func _process(delta : float) -> void:
	$VolumeProxy.material.uvw_offset += Vector3(0.1, -0.05, 0.1) * delta
