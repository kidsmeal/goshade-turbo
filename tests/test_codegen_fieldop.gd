extends GSTTestBase

## GSTCodegen over field-op (operator) layers: slot wiring, the unwired-slot
## fallback constant, and every roster entry compiling alone.
## Design: docs/DESIGN.md, Codegen rules.


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


func test_operator_call_args_are_slots_then_params_in_manifest_order() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/smoothstep", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, op.id, "x", base.id)
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("uniform float l%s_gst_smoothstep_edge0 : hint_range(0.0, 1.0) = 0.0;" % op.id), "edge0 param uniform, B4 naming")
	assert_true(code.contains("uniform float l%s_gst_smoothstep_edge1 : hint_range(0.0, 1.0) = 1.0;" % op.id), "edge1 param uniform, B4 naming")
	var expected_line: String = "float l%s = gst_smoothstep(l%s, l%s_gst_smoothstep_edge0, l%s_gst_smoothstep_edge1);" % [op.id, base.id, op.id, op.id]
	assert_true(code.contains(expected_line), "call args are the wired input local first, then params in manifest declaration order")
	assert_true(GSTShaderCompile.compiles(code), "a generator feeding a field op with params compiles")


func test_unwired_operator_slot_falls_back_to_a_constant() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var op: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("float l%s = invert(0.5);" % op.id), "an unwired input slot is fed the fallback constant, not an empty local reference")
	assert_true(GSTShaderCompile.compiles(code, true), "invert alone has zero uniforms of its own; the compile helper's sentinel covers that")


func test_remap_zero_width_input_range_compiles() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/remap", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, op.id, "x", base.id)
	op.params["in_min"] = 1.0
	op.params["in_max"] = 1.0
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(GSTShaderCompile.compiles(code), "remap with in_min == in_max compiles; the manifest's zero-width guard, not codegen, handles the degenerate range")


func test_every_fieldop_manifest_compiles_alone_fed_constants() -> void:
	var lib: GSTLibrary = _scanned_library()
	var fieldop_ids: Array[String] = []
	for id: String in lib.entries.keys():
		if id.begins_with("fieldops/"):
			fieldop_ids.append(id)
	assert_true(fieldop_ids.size() >= 11, "the full v0.1 field-op roster is present (11 entries)")

	for id: String in fieldop_ids:
		var stack: GSTStack = GSTStack.new()
		var layer: GSTLayer = GSTStackOps.add_layer(stack, id, GSTLayer.Kind.FIELD, false)
		stack.output_color = layer.id
		var code: String = GSTCodegen.generate(stack, lib)
		assert_true(GSTShaderCompile.compiles(code, true), "%s compiles alone with every input slot fed the fallback constant" % id)
