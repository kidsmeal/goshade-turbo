extends GSTTestBase

## GSTCodegen over generator layers, and generator+field-op stack order.
## Design: docs/DESIGN.md, Codegen rules. Uses the real, shipped library
## (GSTLibrary.scan over addons/goshade_turbo/library/).


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


func test_single_generator_emits_coord_uniforms_and_local() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	stack.output_color = layer.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("group_uniforms L00_hash;"), "group line uses stack position 0 and function hash")
	assert_true(code.contains("uniform vec2 l0_scale = vec2(1.0, 1.0);"), "scale uniform declared with the coord block default")
	assert_true(code.contains("uniform vec2 l0_offset = vec2(0.0, 0.0);"), "offset uniform declared with the coord block default")
	assert_true(code.contains("uniform float l0_rotation = 0.0;"), "rotation uniform declared with the coord block default")
	assert_true(code.contains("vec2 coord0 = gst_transform(space_coord, l0_scale, l0_rotation, l0_offset);"), "coord transform line matches the B4-resolved arg order")
	assert_true(code.contains("float l0 = hash(coord0);"), "the generator's own local calls its function with the coord local")
	assert_true(code.contains("COLOR = vec4(vec3(l0), 1.0);"), "phase 2 field-only output wraps the field local")
	assert_true(GSTShaderCompile.compiles(code), "a single generator with default params compiles alone")


func test_generator_plus_field_op_emits_exactly_two_locals_in_stack_order() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	var assign_result: Dictionary = GSTStackOps.assign_slot(stack, op.id, "x", base.id)
	assert_true(assign_result["ok"], "wiring invert's x slot to the generator succeeds")
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	var regex: RegEx = RegEx.new()
	regex.compile("\n\tfloat l[0-9]+ = ")
	var matches: Array[RegExMatch] = regex.search_all(code)
	assert_eq(matches.size(), 2, "exactly two fragment() locals for a two-layer stack")

	var base_pos: int = code.find("float l%s = hash(coord%s);" % [base.id, base.id])
	var op_pos: int = code.find("float l%s = invert(l%s);" % [op.id, base.id])
	assert_true(base_pos != -1, "the generator's local line is present")
	assert_true(op_pos != -1, "the field op's local line is present, referencing the generator's local")
	assert_true(base_pos < op_pos, "the generator's local is emitted before the field op's local (stack order)")
	assert_true(GSTShaderCompile.compiles(code), "a generator feeding a field op compiles")


func test_warp_term_emits_missing_axis_as_zero() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var warp_source: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var generator: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	generator.coord.warp_x = warp_source.id
	generator.coord.warp_strength = 0.3
	stack.output_color = generator.id

	var code: String = GSTCodegen.generate(stack, lib)

	var expected_warp_term: String = "coord%s += vec2(l%s, 0.0) * l%s_warp_strength;" % [generator.id, warp_source.id, generator.id]
	assert_true(code.contains(expected_warp_term), "warp_y is unset, so its axis contributes 0.0")
	assert_true(code.contains("uniform float l%s_warp_strength = 0.3;" % generator.id), "warp_strength uniform is declared because a warp axis is set")
	assert_true(GSTShaderCompile.compiles(code), "a generator with one warp axis set compiles")


func test_no_warp_axes_emits_neither_warp_term_nor_warp_strength_uniform() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	stack.output_color = layer.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_false(code.contains("warp_strength"), "no warp axis is set, so no warp_strength uniform or term is emitted")
	assert_true(GSTShaderCompile.compiles(code), "a generator with no warp axes still compiles")


func test_transform_scroll_and_warp_emit_in_order() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var warp_source: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var generator: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	generator.coord.scroll = Vector2(1.0, 0.0)
	generator.coord.warp_x = warp_source.id
	generator.coord.warp_strength = 0.3
	stack.output_color = generator.id

	var code: String = GSTCodegen.generate(stack, lib)

	var transform_pos: int = code.find("coord%s = gst_transform(" % generator.id)
	var scroll_pos: int = code.find("coord%s += %s * TIME;" % [generator.id, GSTUniformNames.coord_scroll(generator.id)])
	var warp_pos: int = code.find("coord%s += vec2(" % generator.id, scroll_pos)
	assert_true(transform_pos != -1, "the gst_transform call is present")
	assert_true(scroll_pos != -1, "the scroll term is present")
	assert_true(warp_pos != -1, "the warp term is present")
	assert_true(transform_pos < scroll_pos, "gst_transform is emitted before the scroll term")
	assert_true(scroll_pos < warp_pos, "the scroll term is emitted before the warp term")
	assert_true(GSTShaderCompile.compiles(code), "a generator with both scroll and warp set compiles")


func test_every_generative_manifest_compiles_alone_with_default_params() -> void:
	var lib: GSTLibrary = _scanned_library()
	var generative_ids: Array[String] = []
	for id: String in lib.entries.keys():
		if id.begins_with("generative/"):
			generative_ids.append(id)
	assert_true(generative_ids.size() >= 11, "the full v0.1 generative roster is present (11 entries)")

	for id: String in generative_ids:
		var stack: GSTStack = GSTStack.new()
		var layer: GSTLayer = GSTStackOps.add_layer(stack, id, GSTLayer.Kind.FIELD, true)
		stack.output_color = layer.id
		var code: String = GSTCodegen.generate(stack, lib)
		assert_true(GSTShaderCompile.compiles(code), "%s compiles alone with default params (a generator always carries at least the scale/offset/rotation uniforms)" % id)
