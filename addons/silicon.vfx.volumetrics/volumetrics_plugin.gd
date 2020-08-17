tool
extends EditorPlugin

const folder = "res://addons/silicon.vfx.volumetrics/"

var editor_camera : Camera
var inspector_plugin : EditorInspectorPlugin
var gizmo_plugin : EditorSpatialGizmoPlugin
var texture_3d_creator : Control

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
	
	inspector_plugin = load(folder + "editor/inspector_plugin.gd").new()
	add_inspector_plugin(inspector_plugin)
	
	gizmo_plugin = load(folder + "editor/volume_proxy_gizmo_plugin.gd").new()
	gizmo_plugin.editor_selection = get_editor_interface().get_selection()
	gizmo_plugin.undo_redo = get_undo_redo()
	add_spatial_gizmo_plugin(gizmo_plugin)
	
	texture_3d_creator = load(folder + "editor/texture_3d_creator/texture_3d_creator.tscn").instance()
	texture_3d_creator.editor_file_system = get_editor_interface().get_resource_filesystem()
	get_editor_interface().get_base_control().add_child(texture_3d_creator)
	add_tool_menu_item("Create 3D Texture...", texture_3d_creator, "popup_centered_ratio", 0.0)

func _exit_tree() -> void:
	remove_custom_type("LocalVolume")
	remove_custom_type("VolumetricFog")
	remove_autoload_singleton("VolumetricServer")
	remove_inspector_plugin(inspector_plugin)
	remove_spatial_gizmo_plugin(gizmo_plugin)
	remove_tool_menu_item("Create 3D Texture...")
	texture_3d_creator.queue_free()

func forward_spatial_gui_input(p_camera : Camera, p_event : InputEvent) -> bool:
	if not editor_camera:
		editor_camera = p_camera
	return false

func handles(object) -> bool:
	return true

func edit(object) -> void:
	if object is preload("volume_proxy.gd"):
		gizmo_plugin.current_volume = object

