extends Spatial

func _input(event : InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	
	if event is InputEventKey and event.pressed and event.scancode == KEY_H:
		$VolumeProxy3.visible = not $VolumeProxy3.visible
