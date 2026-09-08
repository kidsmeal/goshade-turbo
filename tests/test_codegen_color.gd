extends GSTTestBase

## GSTCodegen over color, source, and filter layers: every entry compiles
## alone, solo output for a color layer, and the color uniform types.
## Design: docs/DESIGN.md, Codegen rules, decision 13.


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


func test_every_color_manifest_compiles_alone_fed_constants() -> void:
	var lib: GSTLibrary = _scanned_library()
	var color_ids: Array[String] = []
	for id: String in lib.entries.keys():
		if id.begins_with("color/"):
			color_ids.append(id)
	assert_true(color_ids.size() >= 13, "the full v0.1 color roster is present (13 entries)")

	for id: String in color_ids:
		var stack: GSTStack = GSTStack.new()
		var layer: GSTLayer = GSTStackOps.add_layer(stack, id, GSTLayer.Kind.COLOR, false)
		stack.output_color = layer.id
		var code: String = GSTCodegen.generate(stack, lib)
		# color/mix's unwired "mask" input (field kind) is fed
		# FALLBACK_FIELD_CONSTANT; the five blends (add, multiply, overlay,
		# screen, soft_light) each carry a "t" param now (decision 14), so
		# they emit a uniform on their own. The sentinel still covers any
		# entry with genuinely zero uniforms (matches
		# test_codegen_fieldop.gd's identical pattern).
		assert_true(GSTShaderCompile.compiles(code, true), "%s compiles alone with every input slot fed the fallback constant" % id)


func test_every_source_manifest_compiles_alone() -> void:
	var lib: GSTLibrary = _scanned_library()
	var source_ids: Array[String] = []
	for id: String in lib.entries.keys():
		if id.begins_with("source/"):
			source_ids.append(id)
	assert_eq(source_ids.size(), 2, "the full v0.1 source roster is present (texture, screen)")

	for id: String in source_ids:
		var stack: GSTStack = GSTStack.new()
		var layer: GSTLayer = GSTStackOps.add_layer(stack, id, GSTLayer.Kind.COLOR, false)
		stack.output_color = layer.id
		var code: String = GSTCodegen.generate(stack, lib)
		# A lone source has no params of its own; source/screen's
		# gst_screen_texture (hint_screen_texture) is excluded from
		# get_shader_uniform_list() (docs/PLAN.md, Verified engine facts
		# style check, reproduced for phase 3), so both need the sentinel.
		assert_true(GSTShaderCompile.compiles(code, true), "%s compiles alone" % id)


func test_source_entries_have_empty_code_and_emit_no_stray_comments() -> void:
	var lib: GSTLibrary = _scanned_library()
	var texture_entry: GSTManifestEntry = lib.get_entry("source/texture")
	var screen_entry: GSTManifestEntry = lib.get_entry("source/screen")
	assert_true(texture_entry.code.is_empty(), "source/texture entry.code is empty (B10 source contract)")
	assert_true(screen_entry.code.is_empty(), "source/screen entry.code is empty (B10 source contract)")

	for source_id: String in ["source/texture", "source/screen"]:
		var stack: GSTStack = GSTStack.new()
		var layer: GSTLayer = GSTStackOps.add_layer(stack, source_id, GSTLayer.Kind.COLOR, false)
		stack.output_color = layer.id
		var code: String = GSTCodegen.generate(stack, lib)
		var body_lines: PackedStringArray = code.split("\n")
		# Lines 0-1 are the header block (license notice, stack header),
		# both legitimately "//" comments (_header_lines). Every other line
		# must carry no stray "//" comment (B10: source entry.code is empty
		# and never reaches file scope).
		for i: int in range(2, body_lines.size()):
			var trimmed: String = body_lines[i].strip_edges()
			assert_false(trimmed.begins_with("//"), "%s: no stray '//' comment outside the header block (line %d: %s)" % [source_id, i, trimmed])


func test_every_filter_manifest_compiles_fed_a_texture_source() -> void:
	var lib: GSTLibrary = _scanned_library()
	var filter_ids: Array[String] = []
	for id: String in lib.entries.keys():
		if id.begins_with("filter/"):
			filter_ids.append(id)
	assert_eq(filter_ids.size(), 5, "the full v0.1 filter roster is present (5 entries)")

	for id: String in filter_ids:
		var stack: GSTStack = GSTStack.new()
		var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
		var filter: GSTLayer = GSTStackOps.add_layer(stack, id, GSTLayer.Kind.COLOR, false)
		var assign_result: Dictionary = GSTStackOps.assign_slot(stack, filter.id, "source", tex.id, lib)
		assert_true(assign_result["ok"], "%s accepts a texture source on its samples_source slot" % id)
		stack.output_color = filter.id
		var code: String = GSTCodegen.generate(stack, lib)
		assert_true(code.contains("texture(TEXTURE,"), "%s samples TEXTURE directly inside fragment() (B10, no gst_self_texture)" % id)
		assert_true(GSTShaderCompile.compiles(code), "%s compiles fed a texture source" % id)


func test_every_filter_manifest_compiles_fed_a_screen_source() -> void:
	var lib: GSTLibrary = _scanned_library()
	var filter_ids: Array[String] = []
	for id: String in lib.entries.keys():
		if id.begins_with("filter/"):
			filter_ids.append(id)
	assert_eq(filter_ids.size(), 5, "the full v0.1 filter roster is present (5 entries)")

	for id: String in filter_ids:
		var stack: GSTStack = GSTStack.new()
		var screen: GSTLayer = GSTStackOps.add_layer(stack, "source/screen", GSTLayer.Kind.COLOR, false)
		var filter: GSTLayer = GSTStackOps.add_layer(stack, id, GSTLayer.Kind.COLOR, false)
		var assign_result: Dictionary = GSTStackOps.assign_slot(stack, filter.id, "source", screen.id, lib)
		assert_true(assign_result["ok"], "%s accepts a screen source on its samples_source slot" % id)
		stack.output_color = filter.id
		var code: String = GSTCodegen.generate(stack, lib)
		assert_true(code.contains("texture(gst_screen_texture,"), "%s samples gst_screen_texture directly inside fragment()" % id)
		assert_true(GSTShaderCompile.compiles(code), "%s compiles fed a screen source" % id)


func test_fieldops_alpha_reads_the_color_alpha_channel() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var color_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var alpha_layer: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/alpha", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, alpha_layer.id, "color", color_layer.id, lib)
	stack.output_color = color_layer.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("float l%s = alpha(l%s);" % [alpha_layer.id, color_layer.id]), "alpha(color) reads the color layer's local directly, no conversion wrapper needed")
	assert_true(GSTShaderCompile.compiles(code), "fieldops/alpha shader compiles")


func test_solo_output_of_a_color_layer_emits_rgb_alpha_one() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var color_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var field_layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	stack.output_color = color_layer.id

	var code: String = GSTCodegen.generate(stack, lib, color_layer.id)

	assert_true(code.contains("COLOR = vec4(l%s.rgb, 1.0);" % color_layer.id), "solo output of a color layer emits vec4(lN.rgb, 1.0)")
	assert_true(GSTShaderCompile.compiles(code), "solo color output shader compiles")


func test_color_param_emits_source_color_uniform_with_no_range() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	stack.output_color = layer.id

	var code: String = GSTCodegen.generate(stack, lib)

	var expected: String = "uniform vec4 l%s_fill_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);" % layer.id
	assert_true(code.contains(expected), "a color-type param emits a source_color uniform with no hint_range")
	assert_false(code.contains("l%s_fill_color : hint_range" % layer.id), "a color-type param never carries hint_range")
	assert_true(GSTShaderCompile.compiles(code), "color-param shader compiles")


func test_vec3_param_emits_plain_vec3_uniform() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "color/palette", GSTLayer.Kind.COLOR, false)
	stack.output_color = layer.id

	var code: String = GSTCodegen.generate(stack, lib)

	var expected: String = "uniform vec3 l%s_palette_a = vec3(0.5, 0.5, 0.5);" % layer.id
	assert_true(code.contains(expected), "a vec3-type param emits a plain vec3 uniform with no hint_range")
	assert_true(GSTShaderCompile.compiles(code), "vec3-param shader compiles")


func test_posterize_quantizes_into_levels_minus_one_intervals() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "color/posterize", GSTLayer.Kind.COLOR, false)
	stack.output_color = layer.id

	var code: String = GSTCodegen.generate(stack, lib)

	var expected_uniform: String = "uniform int l%s_posterize_levels : hint_range(2, 32) = 6;" % layer.id
	assert_true(code.contains(expected_uniform), "posterize's levels param declares the expected uniform")
	assert_true(code.contains("float steps = float(levels - 1);"), "posterize quantizes into levels - 1 intervals, not levels")
	assert_true(GSTShaderCompile.compiles(code), "posterize shader compiles")


## Decision 14: "a mask is mix(a, b, mask)". color/mix's third input is a
## field-kind slot named "mask", not a "t" param; a field layer wired into it
## drives color_mix's third argument directly (design docs/PLAN.md fix pass 5).
func test_mix_field_layer_drives_mask_input() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var a_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var b_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var mask_layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var mix_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/mix", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, mix_layer.id, "a", a_layer.id, lib)
	GSTStackOps.assign_slot(stack, mix_layer.id, "b", b_layer.id, lib)
	GSTStackOps.assign_slot(stack, mix_layer.id, "mask", mask_layer.id, lib)
	stack.output_color = mix_layer.id

	var code: String = GSTCodegen.generate(stack, lib)

	var expected: String = "vec4 l%s = color_mix(l%s, l%s, l%s);" % [mix_layer.id, a_layer.id, b_layer.id, mask_layer.id]
	assert_true(code.contains(expected), "color_mix's third argument is the field layer's local directly, no conversion wrapper")
	assert_true(GSTShaderCompile.compiles(code), "field-driven color_mix shader compiles")


## A field layer wired into color/mix's "a" slot (color kind) still converts
## through vec4(vec3(lN), 1.0) (decision 2), proving "a"/"b" stayed color-kind
## slots and only "mask" is field-kind.
func test_mix_field_layer_in_color_slot_converts_via_vec3() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var field_layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var b_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var mask_layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var mix_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/mix", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, mix_layer.id, "a", field_layer.id, lib)
	GSTStackOps.assign_slot(stack, mix_layer.id, "b", b_layer.id, lib)
	GSTStackOps.assign_slot(stack, mix_layer.id, "mask", mask_layer.id, lib)
	stack.output_color = mix_layer.id

	var code: String = GSTCodegen.generate(stack, lib)

	var expected: String = "vec4 l%s = color_mix(vec4(vec3(l%s), 1.0), l%s, l%s);" % [mix_layer.id, field_layer.id, b_layer.id, mask_layer.id]
	assert_true(code.contains(expected), "a field layer wired into color_mix's color slot 'a' converts through vec4(vec3(lN), 1.0)")
	assert_true(GSTShaderCompile.compiles(code), "field-in-color-slot color_mix shader compiles")


## Decision 14 applied to the whole blend family: each of the five blends
## carries one "t" param (opacity), emitted as a hint_range(0.0, 1.0)
## uniform, and the fragment call passes it as the blend function's third
## argument (design docs/PLAN.md fix pass 5).
func test_blend_family_emits_t_opacity_uniform_and_uses_it() -> void:
	var lib: GSTLibrary = _scanned_library()
	var blends: Dictionary = {
		"color/screen": "blend_screen",
		"color/multiply": "color_multiply",
		"color/overlay": "blend_overlay",
		"color/add": "color_add",
		"color/soft_light": "blend_soft_light",
	}
	for id: String in blends.keys():
		var function_name: String = blends[id]
		var stack: GSTStack = GSTStack.new()
		var a_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
		var b_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
		var blend_layer: GSTLayer = GSTStackOps.add_layer(stack, id, GSTLayer.Kind.COLOR, false)
		GSTStackOps.assign_slot(stack, blend_layer.id, "a", a_layer.id, lib)
		GSTStackOps.assign_slot(stack, blend_layer.id, "b", b_layer.id, lib)
		stack.output_color = blend_layer.id

		var code: String = GSTCodegen.generate(stack, lib)

		var t_uniform: String = "l%s_%s_t" % [blend_layer.id, function_name]
		var expected_uniform: String = "uniform float %s : hint_range(0.0, 1.0) = 1.0;" % t_uniform
		assert_true(code.contains(expected_uniform), "%s emits the t opacity uniform with hint_range(0.0, 1.0)" % id)
		var expected_call: String = "%s(l%s, l%s, %s)" % [function_name, a_layer.id, b_layer.id, t_uniform]
		assert_true(code.contains(expected_call), "%s's fragment call passes the t uniform" % id)
		assert_true(GSTShaderCompile.compiles(code), "%s compiles with the t opacity uniform" % id)


func test_screen_texture_uniform_absent_without_a_screen_layer() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	stack.output_color = layer.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_false(code.contains("gst_screen_texture"), "no screen layer in the stack, so gst_screen_texture is never declared")
	assert_true(GSTShaderCompile.compiles(code), "no-screen-layer shader compiles")
