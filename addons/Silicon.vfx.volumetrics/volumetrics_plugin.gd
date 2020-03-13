tool
extends EditorPlugin

const folder = "res://addons/Silicon.vfx.volumetrics/"

var editor_camera : Camera

var project_properties = {}

func _ready() -> void:
	name = "VolumetricsPlugin"
	
	# There's this quirk where the icon's import file isn't immemiately loaded.
	# This will loop until that file is generated , i.e. it can be loaded in.
	var icon : StreamTexture
	var no_import := false
	while not icon:
		icon = load(folder + "volume_sprite.svg")
		if not icon:
			no_import = true
			yield(get_tree(), "idle_frame")
	if no_import:
		print("Ignore the errors above. This is normal.")
	
	add_project_prop({name="rendering/quality/volumetric/start", type=TYPE_REAL}, 0.1, "near_clip")
	add_project_prop({name="rendering/quality/volumetric/end", type=TYPE_REAL}, 40.0, "far_clip")
	add_project_prop({name="rendering/quality/volumetric/distribution", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0,1"}, 0.0, "distribution")
	add_project_prop({name="rendering/quality/volumetric/tile_size", type=TYPE_INT}, 4, "tile_size")
	add_project_prop({name="rendering/quality/volumetric/samples", type=TYPE_INT, hint=PROPERTY_HINT_ENUM, hint_string="32,64,128,256,512"}, 2, "samples")
	add_project_prop({name="rendering/quality/volumetric/density_multiplier", type=TYPE_REAL}, 4, "density_multiplier")
	
	add_autoload_singleton("VolumetricServer", folder + "volumetric_server.gd")
#	add_custom_type("VolumetricMaterial", "Resource",
#			load(folder + "VolumeMaterial/volumetric_material.gd"), icon
#	)
	add_custom_type("VolumeSprite", "Spatial",
			load(folder + "volume_sprite.gd"), icon
	)
	
	print("volumetrics plugin enter tree")

func _exit_tree() -> void:
	remove_custom_type("VolumeSprite")
#	remove_custom_type("VolumetricMaterial")
	remove_autoload_singleton("VolumetricServer")
	
	print("volumetrics plugin exit tree")

func add_project_prop(property_info : Dictionary, default, server_var : String) -> void:
	if not ProjectSettings.has_setting(property_info.name):
		ProjectSettings.set_setting(property_info.name, default)
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property_info.name, default)
	project_properties[property_info.name] = server_var

func forward_spatial_gui_input(p_camera : Camera, p_event : InputEvent) -> bool:
	if not editor_camera:
		editor_camera = p_camera
	return false

func handles(object):
	return true
