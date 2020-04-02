tool
extends ShaderMaterial
class_name TransparentVolumeOverlay

enum {
	TRANSMITTANCE_SHADER,
	SCATTERING_SHADER
}

export var parent_material_ref : Array

var registered := false

var tile_factor := Vector2()
var vol_depth_params := Vector3()
var volume_transmittance : ViewportTexture
var volume_scattering : ViewportTexture

func _init() -> void:
	next_pass = ShaderMaterial.new()
	next_pass.render_priority = 2
	
	if parent_material_ref:
		var parent_material = parent_material_ref[0].get(parent_material_ref[1])
		render_priority += parent_material.render_priority
		next_pass.render_priority += parent_material.render_priority
	
	shader = preload("../renderer/scene_transmit.shader")
	next_pass.shader = preload("../renderer/scene_scatter.shader")
	set_shader_param("is_transparent_pass", true)
	next_pass.set_shader_param("is_transparent_pass", true)
	
	resource_local_to_scene = true
	next_pass.resource_local_to_scene = true
	if not VisualServer.is_connected("frame_pre_draw", self, "_frame_pre_draw"):
		VisualServer.connect("frame_pre_draw", self, "_frame_pre_draw")

func _frame_pre_draw() -> void:
	if parent_material_ref and not parent_material_ref.empty() and weakref(parent_material_ref[0]).get_ref():
		var parent_material = parent_material_ref[0].get(parent_material_ref[1])
		if parent_material:
			render_priority = parent_material.render_priority + 1
			next_pass.render_priority = parent_material.render_priority + 2
			var variables := read_material_properties(parent_material)
			update_shader(variables, parent_material)

func update_shader(variables : Array, parent_mat : Material) -> void:
	var shader_params := []
	var update_required := false
	for variable in variables:
		var property = variable[1]
		var name = property.name
		if parent_mat is SpatialMaterial:
			if property.type in [TYPE_INT, TYPE_BOOL] and not name.ends_with("_texture_channel"):
				var meta_list = get_meta_list()
				if not name in meta_list or get_meta(name) != parent_mat.get(name):
					update_required = true
				set_meta(name, parent_mat.get(name))
			else:
				var value = parent_mat.get(name)
				# texture channels, although are integers, actually are vec4 in the shader.
				if name.ends_with("_texture_channel"):
					value = [
						Plane(1, 0, 0, 0),
						Plane(0, 1, 0, 0),
						Plane(0, 0, 1, 0),
						Plane(0, 0, 0, 1),
						Plane(0.333, 0.333, 0.333, 0)]\
					[parent_mat.get(name)]
				shader_params.append([variable[0], value])
		else:
			# Check for change in shader code
			var prev_code = get_meta("prev_code")
			if not prev_code or prev_code != VisualServer.shader_get_code(parent_mat.shader.get_rid()):
				update_required = true
			set_meta("prev_code", VisualServer.shader_get_code(parent_mat.shader.get_rid()))
			shader_params.append([variable[0], parent_mat.get(name)])
	
	if update_required:
		shader = convert_material(parent_mat, TRANSMITTANCE_SHADER)
		next_pass.shader = convert_material(parent_mat, SCATTERING_SHADER)
	
	for variable in shader_params:
		set_shader_param(variable[0], variable[1])
		next_pass.set_shader_param(variable[0], variable[1])
	
	# Pass volumetric parameters
	set_shader_param("tile_factor", tile_factor)
	set_shader_param("vol_depth_params", vol_depth_params)
	set_shader_param("volume_transmittance", volume_transmittance)
	next_pass.set_shader_param("tile_factor", tile_factor)
	next_pass.set_shader_param("vol_depth_params", vol_depth_params)
	next_pass.set_shader_param("volume_transmittance", volume_transmittance)
	next_pass.set_shader_param("volume_scattering", volume_scattering)

# Returns an array of [shader name, property of material]
func read_material_properties(material : Material) -> Array:
	var property_list := material.get_property_list()
	
	var list := []
	var reading_vars := false
	for property in property_list:
		# Start looking for properties after encountering this.
		if property.name == "Material":
			reading_vars = true
			continue
		
		# Ignore groups, scripts and next_pass
		if not reading_vars or \
				property.usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_CATEGORY) or \
				property.name in ["script", "next_pass"]:
			continue
		
		var shader_name : String = property.name
		
		# Not all properties match with their shader parameter.
		# We'll need to convert some of them.
		if material is SpatialMaterial:
			match shader_name:
				"params_grow_amount":
					shader_name = "grow"
				"params_alpha_scissor_threshold":
					shader_name = "alpha_scissor_threshold"
				"albedo_color":
					shader_name = "albedo"
				"metallic_specular":
					shader_name = "specular"
				"anisotropy":
					shader_name = "anisotropy_ratio"
				"anisotropy_flowmap":
					shader_name = "texture_flowmap"
				"subsurf_scatter_strength":
					shader_name = "subsurface_scattering_strength"
				"refraction_scale":
					shader_name = "refraction"
				"uv1_triplanar_sharpness":
					shader_name = "uv1_blend_sharpness"
				"uv2_triplanar_sharpness":
					shader_name = "uv2_blend_sharpness"
				"distance_fade_min_distance":
					shader_name = "distance_fade_min"
				"distance_fade_max_distance":
					shader_name = "distance_fade_max"
			
			if shader_name.ends_with("_texture"):
				shader_name = "texture_" + shader_name.rstrip("_texture")
			elif shader_name.begins_with("detail_") and property.type == TYPE_OBJECT:
				shader_name = "texture_" + shader_name
		else:
			if shader_name.begins_with("shader_param/"):
				shader_name.erase(0, "shader_param/".length())
		list.append([shader_name, property])
	return list

static func convert_material(material : Material, type : int) -> Shader:
	var base : String 
	if type == TRANSMITTANCE_SHADER:
		base = preload("../renderer/scene_transmit.shader").code
	elif type == SCATTERING_SHADER:
		base = preload("../renderer/scene_scatter.shader").code
	
	var code := VisualServer.shader_get_code(
			VisualServer.material_get_shader(material.get_rid())
	)
	
	# Get the uniforms and functions from the base shader
	var uni_func_start := base.find("//VOL__UNIFORMS_AND_FUNCTIONS__VOL//")
	var uni_func_length := base.find("//VOL__UNIFORMS_AND_FUNCTIONS__VOL//", uni_func_start + 1) - uni_func_start
	var uni_funcs = base.substr(uni_func_start, uni_func_length)
	
	code = code.insert(code.find(";") + 1, "\n" + uni_funcs)
	
	# Get the fragment code from the base shader
	var frag_start := base.find("//VOL__FRAGMENT_CODE__VOL//")
	var frag_length := base.find("//VOL__FRAGMENT_CODE__VOL//", frag_start + 1) - frag_start
	var frag_code = base.substr(frag_start, frag_length)
	
	# The shader may or may not have a fragment shader
	var regex := RegEx.new()
	regex.compile("void\\s+fragment\\s*\\(\\s*\\)\\s*{")
	var has_fragment := regex.search(code)
	if has_fragment:
		var end := has_fragment.get_end() - 1
		var frag_end := find_closing_bracket(code, end)
		code = code.insert(frag_end, frag_code)
	else:
		code += "void fragment() {" + frag_code + "}"
	
	if code.find("unshaded") == -1:
		code += "render_mode unshaded;"
	if type == TRANSMITTANCE_SHADER and code.find("blend_mul") == -1:
		code += "render_mode blend_mul;"
	elif type == SCATTERING_SHADER and code.find("blend_add") == -1:
		code += "render_mode blend_add;"
	
	var shader := Shader.new()
	shader.code = code
	return shader

static func find_closing_bracket(string : String, open_bracket_idx : int) -> int:
	var bracket_count := 1
	var open_bracket := string.substr(open_bracket_idx, 1)
	var close_bracket := "}" if open_bracket == "{" else ")" if open_bracket == "(" else "]"
	var index := open_bracket_idx
	
	while index < string.length():
		var open_index = string.find(open_bracket, index+1)
		var close_index = string.find(close_bracket, index+1)
		
		if close_index != -1 and (open_index == -1 or close_index < open_index):
			index = close_index
			bracket_count -= 1
		elif open_index != -1 and (close_index == -1 or open_index < close_index):
			index = open_index
			bracket_count += 1
		else:
			return -1
		
		if bracket_count <= 0:
			return index
	
	return -1

func set_parent_material_ref(node : GeometryInstance, material_prop : String) -> void:
	parent_material_ref = [node, material_prop]
	if parent_material_ref:
		var parent_material = parent_material_ref[0].get(parent_material_ref[1])
		render_priority = parent_material.render_priority + 1
		next_pass.render_priority = parent_material.render_priority + 2
