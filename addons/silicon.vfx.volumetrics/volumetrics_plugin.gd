tool
extends EditorPlugin

const folder = "res://addons/silicon.vfx.volumetrics/"

var editor_camera : Camera
var inspector_plugin : EditorInspectorPlugin

func _ready() -> void:
	name = "VolumetricsPlugin"
	
	# There's this quirk where the icon's import file isn't immediately loaded.
	# This will loop until that file is generated, i.e. it can be loaded in.
	var icon : StreamTexture
	var no_import := false
	while not icon:
		icon = load(folder + "volume_proxy.svg")
		if not icon:
			no_import = true
			yield(get_tree(), "idle_frame")
	if no_import:
		print("Ignore the errors above. This is normal.")
	
	add_autoload_singleton("VolumetricServer", folder + "volumetric_server.gd")
	add_custom_type("VolumetricFog", "Node",
			load(folder + "volumetric_fog.gd"), load(folder + "volumetric_fog.svg")
	)
	add_custom_type("VolumeProxy", "Spatial",
			load(folder + "volume_proxy.gd"), icon
	)
	
	inspector_plugin = preload("editor/inspector_plugin.gd").new()
	add_inspector_plugin(inspector_plugin)
	
	print("Volumetrics plugin enter tree")

func _exit_tree() -> void:
	remove_custom_type("LocalVolume")
	remove_custom_type("VolumetricFog")
	remove_autoload_singleton("VolumetricServer")
	remove_inspector_plugin(inspector_plugin)
	
	print("Volumetrics plugin exit tree")

func forward_spatial_gui_input(p_camera : Camera, p_event : InputEvent) -> bool:
	if not editor_camera:
		editor_camera = p_camera
	return false

func handles(object) -> bool:
	return true

