extends GSTTestBase

## GSTCodegen over color, source, and filter layers: every entry compiles
## alone, solo output for a color layer, and the color uniform types.


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
		# FALLBACK_FIELD_CONSTANT; the five blends each carry a "t" param, so
		# they emit a uniform on their own. The sentinel covers any entry with
		# zero uniforms.
		assert_true(GSTShaderCompile.compiles(code, true), "%s compiles alone with every input slot fed the fallback constant" % id)


func test_every_source_manifest_compiles_alone() -> void:
	var lib: GSTLibrary = _scanned_library()
	var source_ids: Array[String] = []
	for id: String in lib.entries.keys():
		if id.begins_with("source/"):
			source_ids.append(id)
	assert_eq(source_ids.size(), 3, "the full source roster is present (texture, screen, image)")

	for id: String in source_ids:
		var stack: GSTStack = GSTStack.new()
		var layer: GSTLayer = GSTStackOps.add_layer(stack, id, GSTLayer.Kind.COLOR, lib.get_entry(id).coord)
		stack.output_color = layer.id
		var code: String = GSTCodegen.generate(stack, lib)
		# source/texture has no params; source/screen's gst_screen_texture
		# (hint_screen_texture) is excluded from get_shader_uniform_list(), so
		# both need the sentinel. source/image has coord and sampler uniforms.
		assert_true(GSTShaderCompile.compiles(code, true), "%s compiles alone" % id)


## Decisions 27, 28: source/image emits a sampler2D uniform with no
## hint_range, then its coord block, then one texture() read at coord<id>.
func test_source_image_emits_sampler_uniform_and_coord_read() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "source/image", GSTLayer.Kind.COLOR, true)
	stack.output_color = layer.id
	var code: String = GSTCodegen.generate(stack, lib)
	var id: String = String(layer.id)
	var sampler_line: String = "uniform sampler2D l%s_image_image : source_color, filter_linear, repeat_enable;" % id
	assert_true(code.contains(sampler_line), "sampler2D uniform line exact text:\n%s" % code)
	for line: String in code.split("\n"):
		if line.begins_with("uniform sampler2D l"):
			assert_false(line.contains("hint_range"), "sampler line carries no hint_range: %s" % line)
			assert_false(line.contains("="), "sampler line carries no default: %s" % line)
	assert_true(code.contains("\tvec2 coord%s = gst_transform(space_coord," % id), "coord block line emitted:\n%s" % code)
	assert_true(code.contains("\tvec4 l%s = texture(l%s_image_image, coord%s);" % [id, id, id]), "image read at coord<id>:\n%s" % code)
	assert_false(code.contains("image(coord"), "no generator call to a missing image() function")
	assert_true(GSTShaderCompile.compiles(code), "source/image stack compiles")


## Decision 28: the source/image body is exactly the coord block lines then
## the sampler read, in that order, with no other lines for the layer.
func test_source_image_body_lines_are_the_coord_block_then_the_read() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "source/image", GSTLayer.Kind.COLOR, true)
	layer.coord.scroll = Vector2(0.5, 0.0)
	stack.output_color = layer.id
	var code: String = GSTCodegen.generate(stack, lib)
	var id: String = String(layer.id)
	var expected: Array[String] = [
		"\tvec2 coord%s = gst_transform(space_coord, l%s_scale, l%s_rotation, l%s_offset);" % [id, id, id, id],
		"\tcoord%s += l%s_scroll * TIME;" % [id, id],
		"\tvec4 l%s = texture(l%s_image_image, coord%s);" % [id, id, id],
	]
	var start: int = code.find(expected[0])
	assert_true(start != -1, "coord block opens the body:\n%s" % code)
	assert_true(code.substr(start).begins_with("\n".join(expected) + "\n"), "body is coord block then read, nothing between:\n%s" % code)
	assert_true(GSTShaderCompile.compiles(code), "scrolled source/image compiles")


func test_source_entries_have_empty_code_and_emit_no_stray_comments() -> void:
	var lib: GSTLibrary = _scanned_library()
	var texture_entry: GSTManifestEntry = lib.get_entry("source/texture")
	var screen_entry: GSTManifestEntry = lib.get_entry("source/screen")
	assert_true(texture_entry.code.is_empty(), "source/texture entry.code is empty (B10 source contract)")
	assert_true(screen_entry.code.is_empty(), "source/screen entry.code is empty (B10 source contract)")

	assert_true(lib.get_entry("source/image").code.is_empty(), "source/image entry.code is empty (B10 source contract)")

	for source_id: String in ["source/texture", "source/screen", "source/image"]:
		var stack: GSTStack = GSTStack.new()
		var layer: GSTLayer = GSTStackOps.add_layer(stack, source_id, GSTLayer.Kind.COLOR, lib.get_entry(source_id).coord)
		stack.output_color = layer.id
		var code: String = GSTCodegen.generate(stack, lib)
		var body_lines: PackedStringArray = code.split("\n")
		# Everything through the "// stack:" line is the header block
		# (_header_lines), all "//" comments. No later line may carry one.
		var header_end: int = 0
		while header_end < body_lines.size() and not body_lines[header_end].begins_with(GSTHeader.HEADER_PREFIX):
			header_end += 1
		for i: int in range(header_end + 1, body_lines.size()):
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


## color/mix's third input is a field-kind slot named "mask", not a "t"
## param; a field layer wired into it drives color_mix's third argument.
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


## A field layer wired into color/mix's "a" slot (color kind) converts
## through vec4(vec3(lN), 1.0): "a"/"b" are color-kind slots, only "mask" is
## field-kind.
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


## Each of the five blends carries one "t" param (opacity), emitted as a
## hint_range(0.0, 1.0) uniform and passed as the blend function's third
## argument.
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


## Decision 26: a bypassed color operator passes its first color input.
func test_bypassed_color_operator_passes_its_first_color_input() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var mask: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var a_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var b_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	var mix_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/mix", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, mix_layer.id, "a", a_layer.id, lib)
	GSTStackOps.assign_slot(stack, mix_layer.id, "b", b_layer.id, lib)
	GSTStackOps.assign_slot(stack, mix_layer.id, "mask", mask.id, lib)
	mix_layer.enabled = false
	stack.output_color = mix_layer.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("\tvec4 l%s = l%s;" % [mix_layer.id, a_layer.id]), "bypassed color operator emits l<id> = <first color input>")
	assert_false(code.contains("= color_mix("), "bypassed color operator emits no call")
	assert_true(GSTShaderCompile.compiles(code), "bypassed color operator compiles")


func test_bypassed_color_operator_unwired_emits_the_color_fallback() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var op: GSTLayer = GSTStackOps.add_layer(stack, "color/saturation", GSTLayer.Kind.COLOR, false)
	op.enabled = false
	stack.output_color = op.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("\tvec4 l%s = %s;" % [op.id, GSTCodegen.FALLBACK_COLOR_CONSTANT]), "unwired bypassed color operator emits the color fallback constant line")
	assert_true(GSTShaderCompile.compiles(code, true), "unwired bypassed color operator compiles")


## color/gradient_map has only a field input: bypass converts it to color.
func test_bypassed_color_operator_with_only_a_field_input_converts_to_color() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var field: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var ramp: GSTLayer = GSTStackOps.add_layer(stack, "color/gradient_map", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, ramp.id, "t", field.id, lib)
	ramp.enabled = false
	stack.output_color = ramp.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("\tvec4 l%s = vec4(vec3(l%s), 1.0);" % [ramp.id, field.id]), "field input converts to color (decision 2)")
	assert_true(GSTShaderCompile.compiles(code), "bypassed gradient_map compiles")


## Decision 26: a bypassed filter samples its source unchanged at the
## filter's GST_UV mapping, and keeps its uniforms. A source/image source
## samples its own sampler at coord<src> (decision 28); `%s` is the source id.
func test_bypassed_filter_samples_its_source_unchanged() -> void:
	var lib: GSTLibrary = _scanned_library()
	var cases: Dictionary = {
		"source/texture": "texture(TEXTURE, UV)",
		"source/screen": "texture(gst_screen_texture, SCREEN_UV)",
		"source/image": "texture(l%s_image_image, coord%s)",
	}
	for source_id: String in cases.keys():
		var stack: GSTStack = GSTStack.new()
		var source: GSTLayer = GSTStackOps.add_layer(stack, source_id, GSTLayer.Kind.COLOR, lib.get_entry(source_id).coord)
		var expected_sample: String = String(cases[source_id]).replace("%s", String(source.id))
		var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
		var assign_result: Dictionary = GSTStackOps.assign_slot(stack, filter.id, "source", source.id, lib)
		assert_true(assign_result["ok"], "filter accepts %s: %s" % [source_id, assign_result["reason"]])
		filter.enabled = false
		stack.output_color = filter.id

		var result: GSTCodegenResult = GSTCodegen.generate_result(stack, lib)

		assert_true(result.ok(), "bypassed filter over %s generates: %s" % [source_id, result.error])
		assert_true(result.code.contains("\tvec4 l%s = %s;" % [filter.id, expected_sample]),"bypassed filter over %s emits its source sample:\n%s" % [source_id, result.code])
		assert_false(result.code.contains("snapped"), "bypassed filter over %s emits no template body" % source_id)
		assert_true(result.code.contains("uniform float l%s_pixelate_cell_size" % filter.id), "bypassed filter over %s keeps its uniform" % source_id)
		assert_true(GSTShaderCompile.compiles(result.code), "bypassed filter over %s compiles" % source_id)


## A layer with no inputs refuses bypass (decision 26): a disabled flag
## emits it as is.
func test_disabled_layer_with_no_inputs_emits_unchanged() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var fill: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	fill.enabled = false
	stack.output_color = fill.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("vec4 l%s = fill(" % fill.id), "color/fill has no inputs, so it emits its call")
	assert_true(GSTShaderCompile.compiles(code), "disabled no-input layer compiles")


## Decision 29: a color link target reads through luma and declares it.
func test_color_link_target_emits_luma() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var poster: GSTLayer = GSTStackOps.add_layer(stack, "color/posterize", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, poster.id, "color", tex.id, lib)
	poster.param_links["levels"] = {"target": tex.id, "amount": -0.5}
	stack.output_color = poster.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("int(round(clamp(float(l%s_posterize_levels) + (luma(l%s) - 0.5) * l%s_posterize_levels_amount * (32.0 - 2.0), 2.0, 32.0)))" % [poster.id, tex.id, poster.id]), "color target reads luma(l<target>) inside the int link expression")
	assert_true(code.contains("float luma(vec4 c)"), "_stack_needs_luma counts the color link target")
	assert_true(code.contains("_amount : hint_range(-1.0, 1.0) = -0.5;"), "negative amount literal")
	assert_true(GSTShaderCompile.compiles(code), "color-target link compiles")


## Decision 29: GST_PARAM in a filter template maps to the link expression.
func test_linked_filter_param_substitutes_in_the_template() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var noise: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, filter.id, "source", tex.id, lib)
	filter.param_links["cell_size"] = {"target": noise.id, "amount": 1.0}
	stack.output_color = filter.id

	var result: GSTCodegenResult = GSTCodegen.generate_result(stack, lib)

	assert_true(result.ok(), "linked filter generates: %s" % result.error)
	assert_true(result.code.contains("vec2(clamp(l%s_pixelate_cell_size + (l%s - 0.5) * l%s_pixelate_cell_size_amount * (0.2 - 0.001), 0.001, 0.2))" % [filter.id, noise.id, filter.id]), "GST_PARAM expands to the link expression")
	assert_true(GSTShaderCompile.compiles(result.code), "linked filter compiles")


func test_screen_texture_uniform_absent_without_a_screen_layer() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	stack.output_color = layer.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_false(code.contains("gst_screen_texture"), "no screen layer in the stack, so gst_screen_texture is never declared")
	assert_true(GSTShaderCompile.compiles(code), "no-screen-layer shader compiles")
