extends GSTTestBase

## GSTCodegen slot-kind conversion at boundaries between field and color
## layers. Design: docs/DESIGN.md decision 2, docs/PLAN.md Phase 3.


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


func test_matching_kind_slot_stays_a_bare_local() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var field_layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "color/gradient_map", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, op.id, "t", field_layer.id, lib)
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	var expected_call: String = "gradient_map(l%s, " % field_layer.id
	assert_true(code.contains(expected_call), "a field layer wired into a field-expecting slot stays a bare local, no conversion wrapper")
	assert_true(GSTShaderCompile.compiles(code), "field-into-field-expecting slot compiles")


func test_field_into_color_expecting_slot_wraps_vec4() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var field_layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "color/multiply", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, op.id, "a", field_layer.id, lib)
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	var expected: String = "vec4(vec3(l%s), 1.0)" % field_layer.id
	assert_true(code.contains(expected), "a field layer wired into a color-kind slot wraps as vec4(vec3(lN), 1.0) (decision 2)")
	assert_true(GSTShaderCompile.compiles(code), "field-into-color shader compiles")


func test_color_into_field_slot_wraps_luma() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var color_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/smoothstep", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, op.id, "x", color_layer.id, lib)
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	var expected: String = "luma(l%s)" % color_layer.id
	assert_true(code.contains(expected), "a color layer wired into a field-kind slot wraps as luma(lN) (decision 2)")
	assert_true(code.contains("float luma(vec4 c)"), "the luma helper function is declared once a conversion occurs")
	assert_true(GSTShaderCompile.compiles(code), "color-into-field shader compiles")


func test_luma_appears_exactly_once_with_two_conversions() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var color_a: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var color_b: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var op_a: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, op_a.id, "x", color_a.id, lib)
	var op_b: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, op_b.id, "x", color_b.id, lib)
	stack.output_color = op_b.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_eq(code.count("float luma(vec4 c)"), 1, "the luma helper is declared exactly once even with two color-to-field conversions in the stack")
	assert_true(GSTShaderCompile.compiles(code), "two-conversion shader compiles")


func test_no_conversion_omits_luma_helper() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	stack.output_color = layer.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_false(code.contains("luma("), "no color-to-field conversion occurred, so luma is never declared or called")
	assert_true(GSTShaderCompile.compiles(code), "no-conversion shader compiles")


func test_color_warp_converts_through_luma() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var color_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var generator: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	generator.coord.warp_x = color_layer.id
	stack.output_color = generator.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("vec2(luma(l%s), 0.0)" % color_layer.id), "a color warp input converts through luminance")
	assert_eq(code.count("float luma(vec4 c)"), 1, "color warp emits one luma helper")
	assert_true(GSTShaderCompile.compiles(code), "color-warp shader compiles")
