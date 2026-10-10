extends GSTTestBase

## GSTCodegen over field-op (operator) layers: slot wiring, the unwired-slot
## fallback constant, and every roster entry compiling alone.


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


func test_operator_call_args_are_slots_then_params_in_manifest_order() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/smoothstep", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, op.id, "x", base.id, lib)
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("uniform float l%s_gst_smoothstep_edge0 : hint_range(-1.0, 2.0) = 0.0;" % op.id), "edge0 param uniform, B4 naming")
	assert_true(code.contains("uniform float l%s_gst_smoothstep_edge1 : hint_range(-1.0, 2.0) = 1.0;" % op.id), "edge1 param uniform, B4 naming")
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


## Decision 26: a bypassed field operator assigns its first field input to
## its local and still emits its uniforms.
func test_bypassed_field_operator_passes_its_first_input() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/smoothstep", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, op.id, "x", base.id, lib)
	op.enabled = false
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("\tfloat l%s = l%s;" % [op.id, base.id]), "bypassed operator emits l<id> = <first input>")
	assert_false(code.contains("= gst_smoothstep("), "bypassed operator emits no call")
	assert_true(code.contains("uniform float l%s_gst_smoothstep_edge0" % op.id), "bypassed operator keeps its uniforms")
	assert_true(GSTShaderCompile.compiles(code), "bypassed field operator compiles")


func test_bypassed_operator_with_no_inputs_wired_emits_the_fallback_constant() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var op: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/max", GSTLayer.Kind.FIELD, false)
	op.enabled = false
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("\tfloat l%s = %s;" % [op.id, GSTCodegen.FALLBACK_FIELD_CONSTANT]), "unwired bypassed operator emits the field fallback constant line")
	assert_true(GSTShaderCompile.compiles(code, true), "unwired bypassed operator compiles")


## fieldops/alpha has only a color input: bypass converts it through luma.
func test_bypassed_field_operator_with_only_a_color_input_converts_through_luma() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var fill: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/alpha", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, op.id, "color", fill.id, lib)
	op.enabled = false
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("\tfloat l%s = luma(l%s);" % [op.id, fill.id]), "color input converts to field via luma (decision 2)")
	assert_true(code.contains("float luma(vec4 c)"), "luma is declared for the bypass conversion")
	assert_true(GSTShaderCompile.compiles(code), "bypassed fieldops/alpha compiles")


## Decision 29: a linked float param reads the base plus amount expression,
## and the amount uniform sits after the base uniform.
func test_linked_float_param_emits_the_link_expression() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var noise: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/smoothstep", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, op.id, "x", base.id, lib)
	op.param_links["edge0"] = {"target": noise.id, "amount": 0.5}
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	var base_uniform: String = "l%s_gst_smoothstep_edge0" % op.id
	var amount_uniform: String = base_uniform + "_amount"
	assert_true(code.contains("uniform float %s : hint_range(-1.0, 2.0) = 0.0;\nuniform float %s : hint_range(-1.0, 1.0) = 0.5;" % [base_uniform, amount_uniform]), "base uniform kept, amount uniform follows it")
	var expression: String = "clamp(%s + (l%s - 0.5) * %s * (2.0 - -1.0), -1.0, 2.0)" % [base_uniform, noise.id, amount_uniform]
	assert_true(code.contains("gst_smoothstep(l%s, %s, l%s_gst_smoothstep_edge1)" % [base.id, expression, op.id]), "call reads the link expression in place of the uniform")
	assert_false(code.contains("float luma(vec4 c)"), "a field target needs no luma")
	assert_true(GSTShaderCompile.compiles(code), "linked float compiles")


## Decision 29: an int param wraps the expression in int(round(...)) and
## casts the int base to float.
func test_linked_int_param_rounds_back_to_int() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var noise: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var fbm: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	fbm.param_links["octaves"] = {"target": noise.id, "amount": 1.0}
	stack.output_color = fbm.id

	var code: String = GSTCodegen.generate(stack, lib)

	var expected: String = "int(round(clamp(float(l%s_fbm_octaves) + (l%s - 0.5) * l%s_fbm_octaves_amount * (8.0 - 1.0), 1.0, 8.0)))" % [fbm.id, noise.id, fbm.id]
	assert_true(code.contains("int(round(clamp("), "linked int param is wrapped in int(round(clamp(")
	assert_true(code.contains(expected), "generator call reads the int link expression")
	assert_true(code.contains("uniform float l%s_fbm_octaves_amount : hint_range(-1.0, 1.0) = 1.0;" % fbm.id), "amount uniform declared")
	assert_true(GSTShaderCompile.compiles(code), "linked int compiles")


func test_link_amount_zero_compiles() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var noise: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/pow", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, op.id, "x", noise.id, lib)
	var op_entry: GSTManifestEntry = lib.get_entry("fieldops/pow")
	var param_name: String = op_entry.params[0]["name"]
	op.param_links[param_name] = {"target": noise.id, "amount": 0.0}
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("l%s_gst_pow_%s_amount : hint_range(-1.0, 1.0) = 0.0;" % [op.id, param_name]), "amount 0 is emitted as the uniform default")
	assert_true(GSTShaderCompile.compiles(code), "amount 0 link compiles")


func test_remap_zero_width_input_range_compiles() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/remap", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, op.id, "x", base.id, lib)
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


## The 4 sdf operators (union, subtract, intersect, smooth_union) are
## library/sdf/*.tres entries with coord == false and two field inputs
## (a, b). The 7 sdf generators share the "sdf/" id prefix but coord == true;
## tests/test_codegen_generator.gd covers them.
func test_every_sdf_operator_manifest_compiles_alone_fed_constants() -> void:
	var lib: GSTLibrary = _scanned_library()
	var sdf_operator_ids: Array[String] = []
	for id: String in lib.entries.keys():
		if id.begins_with("sdf/") and not lib.get_entry(id).coord:
			sdf_operator_ids.append(id)
	assert_eq(sdf_operator_ids.size(), 4, "the full v0.1 sdf operator roster is present (4 entries)")

	for id: String in sdf_operator_ids:
		var stack: GSTStack = GSTStack.new()
		var layer: GSTLayer = GSTStackOps.add_layer(stack, id, GSTLayer.Kind.FIELD, false)
		stack.output_color = layer.id
		var code: String = GSTCodegen.generate(stack, lib)
		assert_true(GSTShaderCompile.compiles(code, true), "%s compiles alone with every input slot fed the fallback constant" % id)
