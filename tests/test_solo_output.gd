extends GSTTestBase

## Solo preview output: same codegen, output line replaced by the selected
## layer instead of stack.output_color, without mutating the stack.
## Design: docs/DESIGN.md, decision 13.


func _build_stack() -> Dictionary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, op.id, "x", base.id)
	stack.output_color = op.id
	return {"stack": stack, "library": lib, "base": base, "op": op}


func test_default_output_uses_stack_output_color() -> void:
	var ctx: Dictionary = _build_stack()
	var stack: GSTStack = ctx["stack"]
	var op: GSTLayer = ctx["op"]
	var code: String = GSTCodegen.generate(stack, ctx["library"])
	assert_true(code.contains("COLOR = vec4(vec3(l%s), 1.0);" % op.id), "output wraps the stack's output_color field local")
	assert_true(GSTShaderCompile.compiles(code), "the default-output shader compiles")


func test_solo_output_replaces_the_output_line_with_the_selected_layer() -> void:
	var ctx: Dictionary = _build_stack()
	var stack: GSTStack = ctx["stack"]
	var base: GSTLayer = ctx["base"]
	var op: GSTLayer = ctx["op"]
	var code: String = GSTCodegen.generate(stack, ctx["library"], base.id)

	assert_true(code.contains("COLOR = vec4(vec3(l%s), 1.0);" % base.id), "solo output wraps the selected layer, not stack.output_color")
	assert_false(code.contains("COLOR = vec4(vec3(l%s), 1.0);" % op.id), "the non-selected output_color layer is not the output line")
	assert_true(GSTShaderCompile.compiles(code), "the solo-output shader compiles")


func test_solo_output_does_not_mutate_the_stack() -> void:
	var ctx: Dictionary = _build_stack()
	var stack: GSTStack = ctx["stack"]
	var base: GSTLayer = ctx["base"]
	var op: GSTLayer = ctx["op"]
	var before: String = GSTCodegen.generate(stack, ctx["library"])
	assert_true(GSTShaderCompile.compiles(before), "the pre-solo shader compiles")

	var solo_code: String = GSTCodegen.generate(stack, ctx["library"], base.id)
	assert_true(GSTShaderCompile.compiles(solo_code), "the solo-call shader compiles")

	assert_eq(stack.output_color, op.id, "solo preview does not change stack.output_color")
	var after: String = GSTCodegen.generate(stack, ctx["library"])
	assert_true(GSTShaderCompile.compiles(after), "the post-solo shader compiles")
	assert_eq(before, after, "a non-solo codegen call before and after a solo call produces identical text")
