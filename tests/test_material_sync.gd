extends GSTTestBase

## GSTMaterialSync: rebuilds a ShaderMaterial's code and uniforms from a
## GSTStack's layer resources (decision 7). Design: docs/DESIGN.md decision
## 7, docs/PLAN.md Phase 5 Files.


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


## One generator (generative/fbm: a coord block plus octaves/gain params) and
## one field op (fieldops/invert, wired to it) -- the real shipped manifests,
## not a synthetic fixture (real-input rule).
func _build_stack(lib: GSTLibrary) -> Dictionary:
	var stack: GSTStack = GSTStack.new()
	var fbm: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	var invert: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, invert.id, "x", fbm.id, lib)
	stack.output_color = invert.id
	return {"stack": stack, "fbm": fbm, "invert": invert}


func test_sync_writes_one_uniform_per_param_and_coord_field() -> void:
	var lib: GSTLibrary = _scanned_library()
	var ctx: Dictionary = _build_stack(lib)
	var stack: GSTStack = ctx["stack"]
	var fbm: GSTLayer = ctx["fbm"]
	var material: ShaderMaterial = ShaderMaterial.new()
	var rect_size: Vector2 = Vector2(300.0, 150.0)
	# gst_rect_size is only declared in `local` coord space (GSTCodegen's
	# is_local branch); local exercises the real declared-uniform path here.
	stack.coord_space = GSTStack.CoordSpace.LOCAL

	var result: GSTCodegenResult = GSTMaterialSync.sync(stack, lib, material, &"", rect_size)

	assert_true(result.ok(), "sync of a valid stack succeeds: %s" % result.error)
	assert_eq(material.get_shader_parameter(GSTUniformNames.coord_scale(fbm.id)), Vector2.ONE, "coord scale uniform matches the layer's default coord block value")
	assert_eq(material.get_shader_parameter(GSTUniformNames.coord_offset(fbm.id)), Vector2.ZERO, "coord offset uniform matches the layer's default coord block value")
	assert_eq(material.get_shader_parameter(GSTUniformNames.coord_rotation(fbm.id)), 0.0, "coord rotation uniform matches the layer's default coord block value")
	assert_eq(material.get_shader_parameter(GSTUniformNames.param_uniform(fbm.id, "fbm", "octaves")), 4, "octaves uniform matches the manifest default (int)")
	assert_eq(material.get_shader_parameter(GSTUniformNames.param_uniform(fbm.id, "fbm", "gain")), 0.5, "gain uniform matches the manifest default (float)")
	assert_eq(material.get_shader_parameter("gst_rect_size"), rect_size, "gst_rect_size uniform equals the given rect size (B5)")

	# Coord scroll/warp_strength are omitted at zero (mirrors GSTCodegen):
	# unset params are the caller's own layer defaults, so neither uniform
	# exists in the compiled shader at all.
	assert_eq(material.shader.get_shader_uniform_list().any(func(info: Dictionary) -> bool: return info["name"] == GSTUniformNames.coord_scroll(fbm.id)), false, "scroll uniform is not declared when coord.scroll is zero")


func test_resync_after_a_param_change_updates_only_that_uniform() -> void:
	var lib: GSTLibrary = _scanned_library()
	var ctx: Dictionary = _build_stack(lib)
	var stack: GSTStack = ctx["stack"]
	var fbm: GSTLayer = ctx["fbm"]
	var material: ShaderMaterial = ShaderMaterial.new()
	GSTMaterialSync.sync(stack, lib, material, &"", Vector2(256.0, 256.0))

	fbm.params["octaves"] = 6

	var result: GSTCodegenResult = GSTMaterialSync.sync(stack, lib, material, &"", Vector2(256.0, 256.0))

	assert_true(result.ok(), "resync after a param change succeeds: %s" % result.error)
	assert_eq(material.get_shader_parameter(GSTUniformNames.param_uniform(fbm.id, "fbm", "octaves")), 6, "the changed param's uniform reflects the new value")
	assert_eq(material.get_shader_parameter(GSTUniformNames.param_uniform(fbm.id, "fbm", "gain")), 0.5, "an unchanged param's uniform is untouched by the resync")


func test_codegen_failure_leaves_material_code_and_uniforms_unchanged() -> void:
	var lib: GSTLibrary = _scanned_library()
	var ctx: Dictionary = _build_stack(lib)
	var stack: GSTStack = ctx["stack"]
	var fbm: GSTLayer = ctx["fbm"]
	var material: ShaderMaterial = ShaderMaterial.new()
	var good_result: GSTCodegenResult = GSTMaterialSync.sync(stack, lib, material, &"", Vector2(256.0, 256.0))
	assert_true(good_result.ok(), "baseline sync succeeds before the failure case: %s" % good_result.error)
	var code_before: String = material.shader.code
	var octaves_before: Variant = material.get_shader_parameter(GSTUniformNames.param_uniform(fbm.id, "fbm", "octaves"))

	# An unwired filter slot (B10's "Unwired filter rule"): filter/pixelate's
	# "source" slot defaults to "" and codegen refuses it (docs/PLAN.md
	# Cross-cutting concern "Manifest code contracts (B10)").
	GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)

	var fail_result: GSTCodegenResult = GSTMaterialSync.sync(stack, lib, material, &"", Vector2(256.0, 256.0))

	assert_false(fail_result.ok(), "a stack with an unwired filter slot fails codegen")
	assert_false(fail_result.error.is_empty(), "the failed result carries a non-empty error")
	assert_eq(material.shader.code, code_before, "a failed sync leaves the material's shader code exactly as it was")
	assert_eq(material.get_shader_parameter(GSTUniformNames.param_uniform(fbm.id, "fbm", "octaves")), octaves_before, "a failed sync leaves an existing uniform's value exactly as it was")


func test_solo_variant_compiles_and_differs_from_main_only_in_the_output_line() -> void:
	var lib: GSTLibrary = _scanned_library()
	var ctx: Dictionary = _build_stack(lib)
	var stack: GSTStack = ctx["stack"]
	var fbm: GSTLayer = ctx["fbm"]
	var material: ShaderMaterial = ShaderMaterial.new()

	var main_result: GSTCodegenResult = GSTMaterialSync.sync(stack, lib, material, &"", Vector2(256.0, 256.0))
	assert_true(main_result.ok(), "main sync succeeds: %s" % main_result.error)
	var main_code: String = material.shader.code
	assert_true(GSTShaderCompile.compiles(main_code), "the main-output synced shader compiles")

	var solo_result: GSTCodegenResult = GSTMaterialSync.sync(stack, lib, material, fbm.id, Vector2(256.0, 256.0))
	assert_true(solo_result.ok(), "solo sync succeeds: %s" % solo_result.error)
	var solo_code: String = material.shader.code
	assert_true(GSTShaderCompile.compiles(solo_code), "the solo-output synced shader compiles")

	var main_lines: PackedStringArray = main_code.split("\n")
	var solo_lines: PackedStringArray = solo_code.split("\n")
	assert_eq(main_lines.size(), solo_lines.size(), "main and solo output have the same line count")
	var diff_count: int = 0
	var diff_index: int = -1
	for i: int in range(min(main_lines.size(), solo_lines.size())):
		if main_lines[i] != solo_lines[i]:
			diff_count += 1
			diff_index = i
	assert_eq(diff_count, 1, "main and solo output differ in exactly one line")
	if diff_index != -1:
		assert_true(main_lines[diff_index].strip_edges().begins_with("COLOR ="), "the one differing line is the output line (main side)")
		assert_true(solo_lines[diff_index].strip_edges().begins_with("COLOR ="), "the one differing line is the output line (solo side)")
