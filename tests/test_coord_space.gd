extends GSTTestBase

## Stack-level coord_space: uv / screen_uv / local each read the right
## source, and local adds the varying and vertex() function.
## Design: docs/DESIGN.md, decision 11 and Codegen rules.


func _single_generator_stack() -> Dictionary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	stack.output_color = layer.id
	return {"stack": stack, "library": lib}


func test_uv_space_reads_uv_and_adds_no_vertex_function() -> void:
	var ctx: Dictionary = _single_generator_stack()
	var stack: GSTStack = ctx["stack"]
	stack.coord_space = GSTStack.CoordSpace.UV
	var code: String = GSTCodegen.generate(stack, ctx["library"])

	assert_true(code.contains("vec2 space_coord = UV;"), "uv space reads the built-in UV")
	assert_false(code.contains("void vertex()"), "uv space adds no vertex() function")
	assert_false(code.contains("varying vec2 local_pos;"), "uv space adds no local_pos varying")
	assert_true(GSTShaderCompile.compiles(code), "the uv-space stack compiles")


func test_screen_uv_space_reads_screen_uv() -> void:
	var ctx: Dictionary = _single_generator_stack()
	var stack: GSTStack = ctx["stack"]
	stack.coord_space = GSTStack.CoordSpace.SCREEN_UV
	var code: String = GSTCodegen.generate(stack, ctx["library"])

	assert_true(code.contains("vec2 space_coord = SCREEN_UV;"), "screen_uv space reads the built-in SCREEN_UV")
	assert_false(code.contains("void vertex()"), "screen_uv space adds no vertex() function")
	assert_true(GSTShaderCompile.compiles(code), "the screen_uv-space stack compiles")


func test_local_space_adds_the_varying_and_vertex_function() -> void:
	var ctx: Dictionary = _single_generator_stack()
	var stack: GSTStack = ctx["stack"]
	stack.coord_space = GSTStack.CoordSpace.LOCAL
	var code: String = GSTCodegen.generate(stack, ctx["library"])

	assert_true(code.contains("uniform vec2 gst_rect_size = vec2(1.0);"), "local space declares the rect-size uniform (B5 resolution)")
	assert_true(code.contains("varying vec2 local_pos;"), "local space declares the local_pos varying")
	assert_true(code.contains("void vertex() {"), "local space adds a vertex() function")
	assert_true(code.contains("local_pos = VERTEX / gst_rect_size;"), "vertex() sets local_pos from VERTEX divided by gst_rect_size (B5)")
	assert_true(code.contains("vec2 space_coord = local_pos;"), "local space's fragment() reads the varying")
	assert_true(GSTShaderCompile.compiles(code), "the local-space stack compiles")
