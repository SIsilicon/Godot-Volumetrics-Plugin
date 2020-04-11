extends Control

const ANIMATION_SPEED = 0.5

onready var anim_player := $"../AnimationPlayer"
onready var volume_fog := $"../WorldEnvironment/VolumetricFog"

func _ready() -> void:
	$Panel/VBox/TemporalBlending/SpinBox.value = volume_fog.temporal_blending
	$Panel/VBox/TileSize/OptionButton.selected = volume_fog.tile_size
	$Panel/VBox/Samples/OptionButton.selected = volume_fog.samples
	$Panel/VBox/VolumetricShadows/CheckBox.pressed = volume_fog.volumetric_shadows

func _process(delta : float) -> void:
	$FPS.text = "FPS: " + str(Performance.get_monitor(Performance.TIME_FPS))

func _on_value_changed(value, control : String) -> void:
	match control:
		"AnimatedLights":
			var new_speed = ANIMATION_SPEED * float(value)
			$Tween.interpolate_property(anim_player, "playback_speed", anim_player.playback_speed, new_speed, 0.5, 0, 0)
			$Tween.start()
		"LightType":
			$"../Lights/DirectionalLight".visible = bool(value)
			$"../Lights/OmniLight".visible = not bool(value)
			$"../Lights/OmniLight2".visible = not bool(value)
		"TemporalBlending":
			volume_fog.temporal_blending = value
		"TileSize":
			volume_fog.tile_size = value
		"Samples":
			volume_fog.samples = value
		"VolumetricShadows":
			volume_fog.volumetric_shadows = value
		"TexturedFog":
			$"../VolumeProxy".material.scatter_texture = preload("test_volume.png") if value else null
			$"../VolumeProxy".material.density = 0.15 if value else 0.06
		"HeightFog":
			$"../VolumeProxy2".visible = value
		"EmissiveFog":
			$"../VolumeProxy3".material.emission_strength = float(value) * 3.0
