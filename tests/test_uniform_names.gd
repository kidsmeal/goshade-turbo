extends GSTTestBase

## GSTUniformNames: the single source of uniform and group_uniforms tokens.


func test_local_var_and_coord_var() -> void:
	assert_eq(GSTUniformNames.local_var(&"3"), "l3", "the fragment() local for layer 3")
	assert_eq(GSTUniformNames.coord_var(&"3"), "coord3", "the generator coord local for layer 3")


func test_param_uniform_matches_b4_slider_form() -> void:
	assert_eq(GSTUniformNames.param_uniform(&"3", "fbm", "octaves"), "l3_fbm_octaves", "slider uniforms are l<id>_<function>_<param>")
	assert_eq(GSTUniformNames.param_uniform(&"7", "gst_smoothstep", "edge0"), "l7_gst_smoothstep_edge0", "the function segment is the manifest function name, not the id")


func test_coord_uniforms_carry_no_function_segment() -> void:
	assert_eq(GSTUniformNames.coord_scale(&"3"), "l3_scale", "coord scale uniform, no function segment")
	assert_eq(GSTUniformNames.coord_offset(&"3"), "l3_offset", "coord offset uniform, no function segment")
	assert_eq(GSTUniformNames.coord_rotation(&"3"), "l3_rotation", "coord rotation uniform, no function segment")
	assert_eq(GSTUniformNames.coord_scroll(&"3"), "l3_scroll", "coord scroll uniform, no function segment")
	assert_eq(GSTUniformNames.coord_warp_strength(&"3"), "l3_warp_strength", "coord warp_strength uniform, no function segment")


func test_group_line_matches_b3_resolution() -> void:
	assert_eq(GSTUniformNames.group_line(3, "fbm"), "group_uniforms L03_fbm;", "position is two-digit zero-padded, one identifier (B3)")
	assert_eq(GSTUniformNames.group_line(0, "hash"), "group_uniforms L00_hash;", "position 0 (bottom of stack) still zero-pads to two digits")
	assert_eq(GSTUniformNames.group_line(12, "voronoi"), "group_uniforms L12_voronoi;", "position beyond one digit stays two digits, not truncated")


func test_group_line_uses_the_sanitized_label() -> void:
	assert_eq(GSTUniformNames.group_line(3, "fbm", "Clouds"), "group_uniforms L03_Clouds;", "a plain label replaces the function name (decision 25)")
	assert_eq(GSTUniformNames.group_line(3, "fbm", "  Big cloud #2! "), "group_uniforms L03_Big_cloud_2;", "runs of other characters become one underscore, edges dropped")
	assert_eq(GSTUniformNames.group_line(3, "fbm", "a__b"), "group_uniforms L03_a_b;", "a double underscore collapses, GLSL reserves __")
	assert_eq(GSTUniformNames.sanitize_label("héllo wörld"), "h_llo_w_rld", "non-ASCII letters fall outside [A-Za-z0-9_]")


func test_group_line_falls_back_to_function_when_label_sanitizes_empty() -> void:
	assert_eq(GSTUniformNames.group_line(1, "hash", ""), "group_uniforms L01_hash;", "an empty label uses the function name")
	assert_eq(GSTUniformNames.group_line(1, "hash", "!!! ___ ***"), "group_uniforms L01_hash;", "a label with no letter or digit uses the function name")


func test_labeled_layer_keeps_id_based_uniform_names() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	layer.label = "My Clouds"
	var code: String = GSTCodegen.generate(stack, lib)
	assert_true(code.contains("group_uniforms L00_My_Clouds;"), "codegen emits the label group name")
	assert_false(code.contains("group_uniforms L00_fbm;"), "the function group name is replaced")
	assert_true(code.contains("uniform int l0_fbm_octaves"), "param uniform stays l<id>_<function>_<param>")
	assert_true(code.contains("uniform vec2 l0_scale"), "coord uniform stays l<id>_scale")
	assert_true(GSTShaderCompile.compiles(code), "labeled stack compiles")


func test_readable_labels_preserve_native_paths_and_uniform_names() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var entry: GSTManifestEntry = lib.get_entry("generative/fbm")
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, entry.id, entry.kind_out, entry.coord)
	layer.manifest = entry
	layer.set("octaves", 6)
	layer.set("gain", 0.65)
	assert_eq(layer.params, {"octaves": 6, "gain": 0.65}, "native property paths write original manifest keys")
	var generated: GSTCodegenResult = GSTCodegen.generate_result(stack, lib)
	assert_true(generated.ok(), "labeled fbm generates")
	assert_true(generated.code.contains("uniform int l0_fbm_octaves"), "octaves uniform keeps its original identifier")
	assert_true(generated.code.contains("uniform float l0_fbm_gain"), "gain uniform keeps its original identifier")
