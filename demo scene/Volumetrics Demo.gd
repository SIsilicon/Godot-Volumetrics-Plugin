extends Spatial

func _input(event : InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()

func _ready() -> void:
	yield(get_tree().create_timer(2.0), "timeout")
	var fog = $WorldEnvironment/VolumetricFog
	$WorldEnvironment.remove_child(fog)
	add_child(fog)
