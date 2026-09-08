extends GSTTestBase

## GSTCodegen output block: color.rgb from output_color plus the four alpha
## modes. Design: docs/DESIGN.md decision 12, docs/PLAN.md Blocker B7.


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


func _stack_with_color_output() -> Dictionary:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var color_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	stack.output_color = color_layer.id
	return {"stack": stack, "library": lib, "color_layer": color_layer}


func test_alpha_none_emits_one() -> void:
	var ctx: Dictionary = _stack_with_color_output()
	var stack: GSTStack = ctx["stack"]
	var color_layer: GSTLayer = ctx["color_layer"]
	stack.output_alpha = &"none"

	var code: String = GSTCodegen.generate(stack, ctx["library"])

	assert_true(code.contains("COLOR = vec4(l%s.rgb, 1.0);" % color_layer.id), "alpha mode none emits a literal 1.0")
	assert_true(GSTShaderCompile.compiles(code), "none-alpha shader compiles")


func test_alpha_texture_emits_texture_alpha() -> void:
	var ctx: Dictionary = _stack_with_color_output()
	var stack: GSTStack = ctx["stack"]
	var color_layer: GSTLayer = ctx["color_layer"]
	stack.output_alpha = &"texture"

	var code: String = GSTCodegen.generate(stack, ctx["library"])

	assert_true(code.contains("COLOR = vec4(l%s.rgb, texture(TEXTURE, UV).a);" % color_layer.id), "alpha mode texture reads TEXTURE's own alpha")
	assert_true(GSTShaderCompile.compiles(code), "texture-alpha shader compiles")


func test_alpha_texture_is_the_same_expression_with_two_texture_layers() -> void:
	# B7: with two or more texture layers, output alpha still reads
	# texture(TEXTURE, UV).a; no tiebreak between the two texture layers.
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var color_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	stack.output_color = color_layer.id
	stack.output_alpha = &"texture"

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("COLOR = vec4(l%s.rgb, texture(TEXTURE, UV).a);" % color_layer.id), "two texture layers still produce the single fixed texture-alpha expression")
	assert_true(GSTShaderCompile.compiles(code), "two-texture-layer shader compiles")


func test_alpha_color_alpha_emits_the_output_colors_own_alpha() -> void:
	var ctx: Dictionary = _stack_with_color_output()
	var stack: GSTStack = ctx["stack"]
	var color_layer: GSTLayer = ctx["color_layer"]
	stack.output_alpha = &"color_alpha"

	var code: String = GSTCodegen.generate(stack, ctx["library"])

	assert_true(code.contains("COLOR = vec4(l%s.rgb, l%s.a);" % [color_layer.id, color_layer.id]), "alpha mode color_alpha reads the output color layer's own alpha")
	assert_true(GSTShaderCompile.compiles(code), "color_alpha shader compiles")


func test_alpha_field_layer_id_emits_the_field_local() -> void:
	var ctx: Dictionary = _stack_with_color_output()
	var stack: GSTStack = ctx["stack"]
	var color_layer: GSTLayer = ctx["color_layer"]
	var lib: GSTLibrary = ctx["library"]
	var alpha_field: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	stack.output_alpha = alpha_field.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("COLOR = vec4(l%s.rgb, l%s);" % [color_layer.id, alpha_field.id]), "alpha mode as a field layer id emits the bare field local")
	assert_true(GSTShaderCompile.compiles(code), "field-alpha shader compiles")


func test_alpha_color_layer_id_converts_through_luma() -> void:
	var ctx: Dictionary = _stack_with_color_output()
	var stack: GSTStack = ctx["stack"]
	var color_layer: GSTLayer = ctx["color_layer"]
	var lib: GSTLibrary = ctx["library"]
	var alpha_color: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	stack.output_alpha = alpha_color.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("COLOR = vec4(l%s.rgb, luma(l%s));" % [color_layer.id, alpha_color.id]), "a color layer id used as alpha converts through luma (decision 12)")
	assert_true(GSTShaderCompile.compiles(code), "color-layer-as-alpha shader compiles")


func test_alpha_unset_with_texture_source_emits_texture_alpha() -> void:
	# decision 12: an unset output_alpha (&"") resolves to "texture" when the
	# stack has a "source/texture" layer.
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var color_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	stack.output_color = color_layer.id
	# stack.output_alpha left at its unset default (&"").

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("COLOR = vec4(l%s.rgb, texture(TEXTURE, UV).a);" % color_layer.id), "unset alpha with a texture source defaults to texture(TEXTURE, UV).a")
	assert_true(GSTShaderCompile.compiles(code), "unset-alpha-with-texture-source shader compiles")


func test_alpha_unset_without_texture_source_emits_one() -> void:
	# decision 12: an unset output_alpha (&"") resolves to "none" when the
	# stack has no "source/texture" layer.
	var ctx: Dictionary = _stack_with_color_output()
	var stack: GSTStack = ctx["stack"]
	var color_layer: GSTLayer = ctx["color_layer"]
	# stack.output_alpha left at its unset default (&""); no texture source.

	var code: String = GSTCodegen.generate(stack, ctx["library"])

	assert_true(code.contains("COLOR = vec4(l%s.rgb, 1.0);" % color_layer.id), "unset alpha with no texture source defaults to a literal 1.0")
	assert_true(GSTShaderCompile.compiles(code), "unset-alpha-without-texture-source shader compiles")


func test_alpha_explicit_none_with_texture_source_still_emits_one() -> void:
	# &"none" is a distinct, explicit choice: it is never reinterpreted by
	# the unset-alpha texture default, even when a texture source exists.
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var color_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	stack.output_color = color_layer.id
	stack.output_alpha = &"none"

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("COLOR = vec4(l%s.rgb, 1.0);" % color_layer.id), "explicit none stays a literal 1.0 even when a texture source exists")
	assert_true(GSTShaderCompile.compiles(code), "explicit-none-with-texture-source shader compiles")


func test_alpha_color_alpha_with_unset_output_color_reads_the_default_colors_alpha() -> void:
	# color_alpha resolves through the same _default_color_layer_id fallback
	# as the output color line itself: never a bare "l" when output_color is
	# unset.
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var top_color: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	stack.output_color = &""
	stack.output_alpha = &"color_alpha"

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("COLOR = vec4(l%s.rgb, l%s.a);" % [top_color.id, top_color.id]), "color_alpha with an unset output_color reads the resolved top color layer's own alpha")
	assert_true(GSTShaderCompile.compiles(code), "color_alpha-with-unset-output-color shader compiles")


func test_output_color_defaults_to_top_color_layer_when_unset() -> void:
	# decision 12 / docs/PLAN.md Phase 4 amendment item 2: an unset
	# stack.output_color defaults to the top (highest stack index) color
	# layer, not the first one added.
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var first_color: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var top_color: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	stack.output_color = &""

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("COLOR = vec4(l%s.rgb, 1.0);" % top_color.id), "unset output_color defaults to the top color layer")
	assert_false(code.contains("COLOR = vec4(l%s.rgb, 1.0);" % first_color.id), "unset output_color does not fall back to the first color layer")
	assert_true(GSTShaderCompile.compiles(code), "default-output-color shader compiles")


func test_output_color_defaults_to_black_when_no_color_layer_exists() -> void:
	# No color layer at all: codegen must not emit an undefined identifier
	# for an empty layer id (docs/PLAN.md Phase 4 amendment item 2).
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	stack.output_color = &""

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("COLOR = vec4(0.0, 0.0, 0.0, 1.0);"), "no color layer at all falls back to a fixed black opaque output line")
	assert_true(GSTShaderCompile.compiles(code), "no-color-layer shader compiles")


func test_field_output_color_still_wraps_as_before() -> void:
	# A field-kind output_color (phase 2 legacy path) keeps the phase 2
	# vec4(vec3(lN), 1.0) form, ignoring output_alpha entirely.
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var field_layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	stack.output_color = field_layer.id
	stack.output_alpha = &"texture"

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("COLOR = vec4(vec3(l%s), 1.0);" % field_layer.id), "a field-kind output_color still wraps as vec4(vec3(lN), 1.0)")
	assert_true(GSTShaderCompile.compiles(code), "field-output shader compiles")
