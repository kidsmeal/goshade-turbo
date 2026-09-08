extends GSTTestBase

## TIME and the scroll uniform are emitted together, or both absent.
## Design: docs/DESIGN.md, Codegen rules and Review revisions.


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


func test_zero_scroll_emits_neither_time_nor_scroll_uniform() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	stack.output_color = layer.id
	assert_eq(layer.coord.scroll, Vector2.ZERO, "a freshly added generator's coord defaults to zero scroll")

	var code: String = GSTCodegen.generate(stack, lib)

	assert_false(code.contains("TIME"), "a static stack has no TIME")
	assert_false(code.contains("%s_scroll" % GSTUniformNames.local_var(layer.id)), "a static stack declares no scroll uniform")
	assert_true(GSTShaderCompile.compiles(code), "the static stack still compiles")


func test_nonzero_scroll_emits_both_time_and_scroll_uniform() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	layer.coord.scroll = Vector2(1.0, 0.0)
	stack.output_color = layer.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("uniform vec2 %s = vec2(1.0, 0.0);" % GSTUniformNames.coord_scroll(layer.id)), "the scroll uniform is declared with the coord block's value")
	assert_true(code.contains("coord%s += %s * TIME;" % [layer.id, GSTUniformNames.coord_scroll(layer.id)]), "the scroll term multiplies TIME")
	assert_true(GSTShaderCompile.compiles(code), "the animated stack compiles; TIME is a built-in fragment() variable")
