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


func _build_broken_stack() -> GSTStack:
	var stack: GSTStack = GSTStack.new()
	GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	return stack


func _is_safe_transparent_material(material: ShaderMaterial) -> bool:
	return (
		material != null
		and material.shader != null
		and material.shader.code.contains("shader_type canvas_item")
		and material.shader.code.contains("COLOR = vec4(0.0)")
	)


func test_installation_reset_creates_a_fresh_safe_material_and_clears_success() -> void:
	var lib: GSTLibrary = _scanned_library()
	var cache: GSTMaterialSync = GSTMaterialSync.new()
	cache.reset_installation()
	var first_material: ShaderMaterial = cache.get_material()

	assert_true(_is_safe_transparent_material(first_material), "reset initializes a transparent canvas_item material")
	assert_false(cache.has_successful_preview(), "a reset installation has no successful preview")

	var ctx: Dictionary = _build_stack(lib)
	var success: GSTCodegenResult = cache.sync_preview(ctx["stack"], lib, &"", Vector2(256.0, 256.0))
	assert_true(success.ok(), "a valid non-empty stack succeeds after reset: %s" % success.error)
	assert_false(success.code.is_empty(), "a valid non-empty stack returns generated shader code")
	assert_true(cache.has_successful_preview(), "a valid non-empty result marks the installation successful")

	cache.reset_installation()
	var second_material: ShaderMaterial = cache.get_material()
	assert_false(is_same(second_material, first_material), "reset replaces the previous installation's material instance")
	assert_true(_is_safe_transparent_material(second_material), "the replacement material is initialized to transparent canvas_item output")
	assert_false(cache.has_successful_preview(), "reset clears the previous installation's success state")


func test_failed_preview_retains_the_current_installations_last_success() -> void:
	var lib: GSTLibrary = _scanned_library()
	var ctx: Dictionary = _build_stack(lib)
	var stack: GSTStack = ctx["stack"]
	var fbm: GSTLayer = ctx["fbm"]
	var cache: GSTMaterialSync = GSTMaterialSync.new()
	cache.reset_installation()
	var success: GSTCodegenResult = cache.sync_preview(stack, lib, &"", Vector2(256.0, 256.0))
	assert_true(success.ok(), "baseline instance sync succeeds before the failure case: %s" % success.error)
	var material_before: ShaderMaterial = cache.get_material()
	var code_before: String = material_before.shader.code
	var octaves_before: Variant = material_before.get_shader_parameter(GSTUniformNames.param_uniform(fbm.id, "fbm", "octaves"))

	GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	var failure: GSTCodegenResult = cache.sync_preview(stack, lib, &"", Vector2(128.0, 128.0))

	assert_false(failure.ok(), "an unwired filter fails instance preview sync")
	assert_false(failure.error.is_empty(), "the failed instance result carries its codegen error")
	assert_true(is_same(cache.get_material(), material_before), "failure retains the current installation's material instance")
	assert_eq(cache.get_material().shader.code, code_before, "failure retains the last successful shader code")
	assert_eq(cache.get_material().get_shader_parameter(GSTUniformNames.param_uniform(fbm.id, "fbm", "octaves")), octaves_before, "failure retains the last successful uniform value")
	assert_true(cache.has_successful_preview(), "failure after success keeps the recovery state true")


func test_failure_before_success_keeps_the_safe_blank_material() -> void:
	var lib: GSTLibrary = _scanned_library()
	var cache: GSTMaterialSync = GSTMaterialSync.new()
	cache.reset_installation()
	var material_before: ShaderMaterial = cache.get_material()
	var code_before: String = material_before.shader.code

	var failure: GSTCodegenResult = cache.sync_preview(_build_broken_stack(), lib, &"", Vector2(256.0, 256.0))

	assert_false(failure.ok(), "an unwired filter fails before the installation has a successful preview")
	assert_true(is_same(cache.get_material(), material_before), "failure before success retains the safe material instance")
	assert_eq(cache.get_material().shader.code, code_before, "failure before success retains safe transparent shader code")
	assert_true(_is_safe_transparent_material(cache.get_material()), "failure before success leaves transparent output available")
	assert_false(cache.has_successful_preview(), "failure before success cannot claim a previous preview")


func test_empty_stack_clears_success_and_blocks_stale_recovery() -> void:
	var lib: GSTLibrary = _scanned_library()
	var ctx: Dictionary = _build_stack(lib)
	var cache: GSTMaterialSync = GSTMaterialSync.new()
	cache.reset_installation()
	var success: GSTCodegenResult = cache.sync_preview(ctx["stack"], lib, &"", Vector2(256.0, 256.0))
	assert_true(success.ok(), "baseline instance sync succeeds before clearing the stack: %s" % success.error)
	var successful_code: String = cache.get_material().shader.code

	var empty_result: GSTCodegenResult = cache.sync_preview(GSTStack.new(), lib, &"", Vector2(256.0, 256.0))
	var blank_material: ShaderMaterial = cache.get_material()
	assert_true(empty_result.ok(), "an empty stack is a successful non-error state")
	assert_true(empty_result.code.is_empty(), "an empty stack returns no generated effect code")
	assert_false(blank_material.shader.code == successful_code, "an empty stack removes the previous successful effect")
	assert_true(_is_safe_transparent_material(blank_material), "an empty stack leaves safe transparent output")
	assert_false(cache.has_successful_preview(), "an empty stack clears the installation's success state")

	var blank_code: String = blank_material.shader.code
	var failure: GSTCodegenResult = cache.sync_preview(_build_broken_stack(), lib, &"", Vector2(256.0, 256.0))
	assert_false(failure.ok(), "a later broken edit still reports its codegen error")
	assert_true(is_same(cache.get_material(), blank_material), "the later broken edit retains the safe blank material instance")
	assert_eq(cache.get_material().shader.code, blank_code, "the later broken edit cannot restore the removed effect")
	assert_false(cache.has_successful_preview(), "the later broken edit cannot claim stale recovery")


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
