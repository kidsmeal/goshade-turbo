extends GSTTestBase

## GSTStackOps.assign_slot refusing a non-source layer on a samples_source
## slot, and codegen's neighbor-sampling emission for a filter fed a source.
## Design: docs/DESIGN.md decision 21, docs/PLAN.md Blocker B6.


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


func test_assigning_a_non_source_layer_to_a_samples_source_slot_is_refused() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)

	var result: Dictionary = GSTStackOps.assign_slot(stack, filter.id, "source", base.id, lib)

	assert_false(result["ok"], "a non-source layer is refused on a samples_source slot")
	assert_false(String(result["reason"]).is_empty(), "the refusal names the slot and the offending layer")
	assert_true(String(result["reason"]).contains("source"), "the refusal reason mentions the slot")
	assert_false(filter.slots.has("source"), "a refused assignment does not write the slot")


func test_assign_slot_with_a_null_library_is_refused_and_leaves_the_slot_unchanged() -> void:
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)

	var result: Dictionary = GSTStackOps.assign_slot(stack, filter.id, "source", base.id, null)

	assert_false(result["ok"], "a null library is a caller bug and the assignment is refused")
	assert_false(String(result["reason"]).is_empty(), "the refusal carries a reason string")
	assert_false(filter.slots.has("source"), "a refused assignment does not write the slot")


func test_assigning_a_texture_layer_to_a_samples_source_slot_succeeds() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)

	var result: Dictionary = GSTStackOps.assign_slot(stack, filter.id, "source", tex.id, lib)

	assert_true(result["ok"], "a texture source layer is accepted on a samples_source slot")
	assert_eq(filter.slots["source"], tex.id, "the slot stores the texture layer id")


func test_assigning_a_screen_layer_to_a_samples_source_slot_succeeds() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var screen: GSTLayer = GSTStackOps.add_layer(stack, "source/screen", GSTLayer.Kind.COLOR, false)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/box_blur", GSTLayer.Kind.COLOR, false)

	var result: Dictionary = GSTStackOps.assign_slot(stack, filter.id, "source", screen.id, lib)

	assert_true(result["ok"], "a screen source layer is accepted on a samples_source slot")
	assert_eq(filter.slots["source"], screen.id, "the slot stores the screen layer id")


func test_filter_default_initializes_only_from_an_immediate_source() -> void:
	var lib: GSTLibrary = _scanned_library()
	var legal_stack: GSTStack = GSTStack.new()
	var texture: GSTLayer = GSTStackOps.add_layer(legal_stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var legal_filter: GSTLayer = GSTStackOps.add_layer(legal_stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	var legal_result: Dictionary = GSTStackOps.initialize_inputs_from_immediate_below(legal_stack, legal_filter.id, lib)
	assert_true(legal_result["ok"], "filter initialization succeeds with a legal immediate source")
	assert_eq(legal_filter.slots.get("source", &""), texture.id, "filter source initializes from the immediate texture")

	var illegal_stack: GSTStack = GSTStack.new()
	GSTStackOps.add_layer(illegal_stack, "source/texture", GSTLayer.Kind.COLOR, false)
	GSTStackOps.add_layer(illegal_stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var illegal_filter: GSTLayer = GSTStackOps.add_layer(illegal_stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	var illegal_result: Dictionary = GSTStackOps.initialize_inputs_from_immediate_below(illegal_stack, illegal_filter.id, lib)
	assert_true(illegal_result["ok"], "filter initialization remains valid when the immediate layer is not a source")
	assert_false(illegal_filter.slots.has("source"), "a filter does not search past its illegal immediate layer for an older source")


func test_assigning_a_slot_whose_own_entry_is_unresolved_in_the_library_is_refused() -> void:
	# An entry id absent from the given library must never bypass the
	# samples_source check: assign_slot refuses instead of silently treating
	# an unresolved entry as "not a filter".
	var lib: GSTLibrary = GSTLibrary.new()
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)

	var result: Dictionary = GSTStackOps.assign_slot(stack, filter.id, "source", base.id, lib)

	assert_false(result["ok"], "an unresolved assigning-layer entry is refused rather than skipping the samples_source check")
	assert_true(String(result["reason"]).contains("filter/pixelate"), "the refusal names the unresolved entry, got: %s" % result["reason"])
	assert_false(filter.slots.has("source"), "a refused assignment does not write the slot")


func test_assigning_a_slot_whose_target_entry_is_unresolved_in_the_library_is_refused() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var stack: GSTStack = GSTStack.new()
	var unresolved_base: GSTLayer = GSTStackOps.add_layer(stack, "not/a/real/entry", GSTLayer.Kind.COLOR, false)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)

	var result: Dictionary = GSTStackOps.assign_slot(stack, filter.id, "source", unresolved_base.id, lib)

	assert_false(result["ok"], "a target layer whose entry is not a source is refused even when its own entry is unresolved")
	assert_false(filter.slots.has("source"), "a refused assignment does not write the slot")


func test_filter_of_filter_is_refused() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var first_filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, first_filter.id, "source", tex.id, lib)
	var second_filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/box_blur", GSTLayer.Kind.COLOR, false)

	var result: Dictionary = GSTStackOps.assign_slot(stack, second_filter.id, "source", first_filter.id, lib)

	assert_false(result["ok"], "filter-of-filter is refused (B6)")


func test_filter_fed_a_texture_source_emits_texture_and_uv() -> void:
	# The literal TEXTURE built-in cannot cross a function-call boundary on
	# Godot 4.6.2 (verified: ERROR: Condition
	# "!actions.custom_samplers.has(...)" is true at the call site), so a
	# filter is not a function at all -- it is an inline block that samples
	# TEXTURE directly (docs/PLAN.md Blocker B10).
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/box_blur", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, filter.id, "source", tex.id, lib)
	stack.output_color = filter.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("texture(TEXTURE,"), "a filter fed a texture source samples TEXTURE directly inside fragment()")
	assert_false(code.contains("gst_self_texture"), "no gst_self_texture uniform exists (B10)")
	assert_true(GSTShaderCompile.compiles(code), "filter fed a texture source compiles")


func test_no_sampler2d_uniform_other_than_screen_texture_is_ever_emitted() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/box_blur", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, filter.id, "source", tex.id, lib)
	stack.output_color = filter.id

	var code: String = GSTCodegen.generate(stack, lib)

	for line: String in code.split("\n"):
		if not line.begins_with("uniform sampler2D"):
			continue
		assert_true(line.begins_with("uniform sampler2D gst_screen_texture"), "the only sampler2D uniform ever emitted is gst_screen_texture, got: %s" % line)
	assert_true(GSTShaderCompile.compiles(code), "texture-fed filter shader compiles")


func test_filter_fed_a_screen_source_emits_screen_texture_and_screen_uv() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var screen: GSTLayer = GSTStackOps.add_layer(stack, "source/screen", GSTLayer.Kind.COLOR, false)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, filter.id, "source", screen.id, lib)
	stack.output_color = filter.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_true(code.contains("texture(gst_screen_texture,"), "a filter fed a screen source samples gst_screen_texture directly inside fragment()")
	assert_true(code.contains("uniform sampler2D gst_screen_texture : hint_screen_texture, filter_linear_mipmap;"), "the screen texture uniform is declared once a screen layer exists")
	assert_true(GSTShaderCompile.compiles(code), "filter fed a screen source compiles")


func test_two_filter_layers_in_one_stack_compile() -> void:
	# Proves block scoping (B10): both filters declare a template-local
	# `cell`/`sum` etc. inside their own `{ }` block, so two filter layers in
	# one stack must not collide.
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var first: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, first.id, "source", tex.id, lib)
	var second: GSTLayer = GSTStackOps.add_layer(stack, "filter/box_blur", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, second.id, "source", tex.id, lib)
	stack.output_color = second.id

	var code: String = GSTCodegen.generate(stack, lib)

	assert_false(code.is_empty(), "two filter layers in one stack still codegens (no stray-token error)")
	assert_true(GSTShaderCompile.compiles(code), "two filter layers in one stack compile")


func test_clearing_a_filters_source_slot_through_assign_slot_is_refused_and_unchanged() -> void:
	# Cross-cutting concern "Manifest code contracts (B10)", Unwired filter
	# rule: a samples_source slot cannot be cleared through assign_slot.
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, filter.id, "source", tex.id, lib)

	var result: Dictionary = GSTStackOps.assign_slot(stack, filter.id, "source", &"", lib)

	assert_false(result["ok"], "clearing a samples_source slot through assign_slot is refused")
	assert_false(String(result["reason"]).is_empty(), "the refusal carries a reason string")
	assert_eq(filter.slots["source"], tex.id, "the slot is unchanged by the refused clear")


func test_removing_a_filters_source_with_a_non_source_layer_below_leaves_the_slot_empty() -> void:
	# decision 22's delete reset must not point a filter at a non-source: it
	# leaves the samples_source slot empty instead (Unwired filter rule).
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)  # index 0, not a source
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)   # index 1
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)  # index 2
	GSTStackOps.assign_slot(stack, filter.id, "source", tex.id, lib)

	var changed: Array[StringName] = GSTStackOps.remove_layer(stack, tex.id, lib)

	assert_eq(changed.size(), 1, "exactly one layer's references changed")
	assert_eq(changed[0], filter.id, "the filter layer is reported as changed")
	assert_eq(filter.slots["source"], &"", "the samples_source slot is left empty rather than pointed at the non-source layer below")


func test_generating_a_stack_with_an_emptied_filter_slot_is_a_codegen_error() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, filter.id, "source", tex.id, lib)
	GSTStackOps.remove_layer(stack, tex.id, lib)
	stack.output_color = filter.id

	var result: GSTCodegenResult = GSTCodegen.generate_result(stack, lib)

	assert_false(result.ok(), "a filter left with an emptied samples_source slot is a codegen error")
	assert_eq(result.code, "", "the codegen error leaves the result code empty")
	assert_true(result.error.contains(String(filter.id)), "the error names the filter layer, got: %s" % result.error)


func test_removing_a_source_with_another_source_directly_below_repoints_the_filter() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var screen: GSTLayer = GSTStackOps.add_layer(stack, "source/screen", GSTLayer.Kind.COLOR, false)   # index 0
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)     # index 1
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)  # index 2
	GSTStackOps.assign_slot(stack, filter.id, "source", tex.id, lib)

	var changed: Array[StringName] = GSTStackOps.remove_layer(stack, tex.id, lib)

	assert_eq(changed.size(), 1, "exactly one layer's references changed")
	assert_eq(changed[0], filter.id, "the filter layer is reported as changed")
	assert_eq(filter.slots["source"], screen.id, "the filter is re-pointed at the source layer now directly below it")

	stack.output_color = filter.id
	var result: GSTCodegenResult = GSTCodegen.generate_result(stack, lib)
	assert_true(result.ok(), "the re-pointed filter generates without error, got: %s" % result.error)
	assert_true(GSTShaderCompile.compiles(result.code), "the re-pointed filter's shader compiles")


func test_unknown_gst_token_in_a_filter_template_is_a_codegen_error() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var broken_entry: GSTManifestEntry = GSTManifestEntry.new()
	broken_entry.id = "filter/broken_test_only"
	broken_entry.function = "broken_test_only"
	broken_entry.kind_out = GSTLayer.Kind.COLOR
	broken_entry.inputs = [{"kind": GSTLayer.Kind.COLOR, "name": "source"}]
	broken_entry.samples_source = true
	broken_entry.code = "GST_OUT = GST_SAMPLE(GST_UV) * GST_NOT_A_REAL_TOKEN;\n"
	lib.add_entry(broken_entry)

	var stack: GSTStack = GSTStack.new()
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, broken_entry.id, GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, filter.id, "source", tex.id, lib)
	stack.output_color = filter.id

	var result: GSTCodegenResult = GSTCodegen.generate_result(stack, lib)

	assert_false(result.ok(), "an unknown GST_ token is a codegen error")
	assert_eq(result.code, "", "an unknown GST_ token leaves the result code empty")
	assert_true(result.error.contains("GST_NOT_A_REAL_TOKEN"), "the result error names the unknown token, got: %s" % result.error)
