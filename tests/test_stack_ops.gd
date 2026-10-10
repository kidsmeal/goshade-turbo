extends GSTTestBase

## Structural mutations: slot assign, reorder, delete.


## assign_slot refuses any assignment whose assigning layer's entry does not
## resolve in the given library, so this builds a minimal library with one
## manifest entry per entry id these tests assign, without a full scan.
func _test_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	for entry_id: String in ["generative/hash", "generative/snoise", "generative/fbm", "fieldops/invert"]:
		var entry: GSTManifestEntry = GSTManifestEntry.new()
		entry.id = entry_id
		entry.function = entry_id.replace("/", "_")
		if entry_id == "fieldops/invert":
			entry.inputs = [{"name": "a", "kind": GSTLayer.Kind.FIELD}]
		lib.add_entry(entry)
	return lib


func _build_stack_with_dependency() -> Dictionary:
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var dependent: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	var assign_result: Dictionary = GSTStackOps.assign_slot(stack, dependent.id, "a", base.id, _test_library())
	return {"stack": stack, "base": base, "dependent": dependent, "assign_result": assign_result}


func test_slot_assign_accepts_an_earlier_layer() -> void:
	var ctx: Dictionary = _build_stack_with_dependency()
	var assign_result: Dictionary = ctx["assign_result"]
	var dependent: GSTLayer = ctx["dependent"]
	var base: GSTLayer = ctx["base"]
	assert_true(assign_result["ok"], "assigning an earlier layer to a slot succeeds")
	assert_eq(dependent.slots["a"], base.id, "the slot stores the referenced layer id")


func test_slot_assign_refuses_a_forward_reference() -> void:
	var stack: GSTStack = GSTStack.new()
	var dependent: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	var later: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var result: Dictionary = GSTStackOps.assign_slot(stack, dependent.id, "a", later.id, _test_library())
	assert_false(result["ok"], "assigning a later layer as an input is refused (decision 3, no forward references)")
	assert_false(String(result["reason"]).is_empty(), "the refusal carries a reason string")
	assert_false(dependent.slots.has("a"), "a refused assignment does not write the slot")


func test_slot_assign_refuses_an_unknown_manifest_slot() -> void:
	var stack: GSTStack = GSTStack.new()
	var base: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var dependent: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	var result: Dictionary = GSTStackOps.assign_slot(stack, dependent.id, "missing", base.id, _test_library())
	assert_false(result["ok"], "a slot absent from the consumer manifest is refused")
	assert_true(String(result["reason"]).contains("missing"), "the refusal names the unknown slot")
	assert_false(dependent.slots.has("missing"), "a refused unknown slot does not mutate the layer")


func test_initialize_inputs_uses_the_immediate_lower_layer_for_every_manifest_input() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var stack: GSTStack = GSTStack.new()
	var lower: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var mix: GSTLayer = GSTStackOps.add_layer(stack, "color/mix", GSTLayer.Kind.COLOR, false)
	var result: Dictionary = GSTStackOps.initialize_inputs_from_immediate_below(stack, mix.id, lib)
	assert_true(result["ok"], "manifest input initialization succeeds")
	assert_eq(mix.slots.get("a", &""), lower.id, "color input a uses the immediate lower field through conversion")
	assert_eq(mix.slots.get("b", &""), lower.id, "color input b uses the immediate lower field through conversion")
	assert_eq(mix.slots.get("mask", &""), lower.id, "field input mask uses the immediate lower field exactly")


func test_initialize_inputs_on_a_bottom_zero_input_entry_is_a_noop() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var result: Dictionary = GSTStackOps.initialize_inputs_from_immediate_below(stack, layer.id, lib)
	assert_true(result["ok"], "a zero-input bottom layer initializes successfully")
	assert_true(layer.slots.is_empty(), "a zero-input bottom layer stays unwired")


func test_reorder_above_a_referencer_is_refused() -> void:
	var ctx: Dictionary = _build_stack_with_dependency()
	var stack: GSTStack = ctx["stack"]
	var base: GSTLayer = ctx["base"]
	# base is index 0; dependent (which references base) is index 1.
	# Moving base to index 1 would put it at or above its own referencer.
	var result: Dictionary = GSTStackOps.reorder_layer(stack, base.id, 1)
	assert_false(result["ok"], "reordering a layer above a layer that references it is refused (decision 22)")
	assert_false(String(result["reason"]).is_empty(), "the refusal carries a reason string")
	assert_eq(GSTStackOps.find_index(stack, base.id), 0, "stack order is unchanged after a refused reorder")


func test_reorder_below_a_referenced_layer_is_also_refused() -> void:
	var ctx: Dictionary = _build_stack_with_dependency()
	var stack: GSTStack = ctx["stack"]
	var dependent: GSTLayer = ctx["dependent"]
	# dependent references base (index 0). Moving dependent to index 0 would
	# put it at or below the layer it reads from: also a forward reference.
	var result: Dictionary = GSTStackOps.reorder_layer(stack, dependent.id, 0)
	assert_false(result["ok"], "reordering a layer below something it references is refused")
	assert_false(String(result["reason"]).is_empty(), "the refusal carries a reason string")


func test_reorder_that_keeps_all_references_valid_succeeds() -> void:
	var stack: GSTStack = GSTStack.new()
	var a: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var b: GSTLayer = GSTStackOps.add_layer(stack, "generative/snoise", GSTLayer.Kind.FIELD, true)
	var c: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	# a and b reference nothing, so swapping them is legal.
	var result: Dictionary = GSTStackOps.reorder_layer(stack, b.id, 0)
	assert_true(result["ok"], "reordering two layers with no references between them succeeds")
	assert_eq(GSTStackOps.find_index(stack, b.id), 0, "b moved to index 0")
	assert_eq(GSTStackOps.find_index(stack, a.id), 1, "a shifted to index 1")
	assert_eq(GSTStackOps.find_index(stack, c.id), 2, "c is unaffected")


func test_delete_referenced_layer_resets_pointing_slots_to_the_below_default() -> void:
	var stack: GSTStack = GSTStack.new()
	var a: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)     # index 0
	var b: GSTLayer = GSTStackOps.add_layer(stack, "generative/snoise", GSTLayer.Kind.FIELD, true)   # index 1
	var c: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)    # index 2
	GSTStackOps.assign_slot(stack, c.id, "a", b.id, _test_library())

	var changed: Array[StringName] = GSTStackOps.remove_layer(stack, b.id, _test_library())

	assert_eq(changed.size(), 1, "exactly one layer's references changed")
	assert_eq(changed[0], c.id, "the referencer is reported as changed")
	# After removing b, c sits directly above a, so a is c's new below default.
	assert_eq(c.slots["a"], a.id, "the reset slot points at the new below layer")


func test_delete_referenced_layer_resets_coord_warp_refs() -> void:
	var stack: GSTStack = GSTStack.new()
	var mask: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)  # index 0
	var warped: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)  # index 1
	warped.coord.warp_x = mask.id

	var changed: Array[StringName] = GSTStackOps.remove_layer(stack, mask.id, _test_library())

	assert_eq(changed.size(), 1, "the warp-referencing generator is reported as changed")
	assert_eq(changed[0], warped.id, "the changed id is the layer holding the warp reference")
	assert_eq(warped.coord.warp_x, &"", "warp_x resets to empty: mask was the bottom layer, so there is no below default")


func test_delete_unreferenced_layer_reports_no_changes() -> void:
	var stack: GSTStack = GSTStack.new()
	var a: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var b: GSTLayer = GSTStackOps.add_layer(stack, "generative/snoise", GSTLayer.Kind.FIELD, true)
	var changed: Array[StringName] = GSTStackOps.remove_layer(stack, b.id, _test_library())
	assert_eq(changed.size(), 0, "removing an unreferenced layer changes nothing")
	assert_eq(GSTStackOps.find_index(stack, a.id), 0, "the remaining layer keeps its position")


## Library for the v0.2 ops tests: _test_library plus one entry per param
## type the link rules sort (decision 29), including a texture param no
## bundled manifest has yet (decision 27), and a filter with a GST_PARAM.
func _link_library() -> GSTLibrary:
	var lib: GSTLibrary = _test_library()
	var linker: GSTManifestEntry = GSTManifestEntry.new()
	linker.id = "test/linker"
	linker.function = "linker"
	linker.kind_out = GSTLayer.Kind.COLOR
	linker.inputs = [{"name": "a", "kind": GSTLayer.Kind.COLOR}]
	linker.params = [
		{"name": "amount", "type": "float", "default": 0.5, "min": 0.0, "max": 1.0},
		{"name": "steps", "type": "int", "default": 4, "min": 1, "max": 16},
		{"name": "tint", "type": "color", "default": Color.WHITE},
		{"name": "weights", "type": "vec3", "default": Vector3.ONE},
		{"name": "image", "type": "texture", "default": null},
	]
	lib.add_entry(linker)
	var tex: GSTManifestEntry = GSTManifestEntry.new()
	tex.id = "source/texture"
	tex.function = "source_texture"
	tex.kind_out = GSTLayer.Kind.COLOR
	lib.add_entry(tex)
	var filter: GSTManifestEntry = GSTManifestEntry.new()
	filter.id = "filter/test_blur"
	filter.function = "test_blur"
	filter.kind_out = GSTLayer.Kind.COLOR
	filter.samples_source = true
	filter.inputs = [{"name": "source", "kind": GSTLayer.Kind.COLOR}]
	filter.params = [{"name": "radius", "type": "float", "default": 0.01, "min": 0.0, "max": 0.1}]
	lib.add_entry(filter)
	return lib


## A field generator below one linker layer, the linker wired to it.
func _build_link_stack() -> Dictionary:
	var stack: GSTStack = GSTStack.new()
	var field: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var linker: GSTLayer = GSTStackOps.add_layer(stack, "test/linker", GSTLayer.Kind.COLOR, false)
	linker.slots["a"] = field.id
	return {"stack": stack, "field": field, "linker": linker}


func test_duplicate_copies_every_field_and_inserts_directly_above() -> void:
	var stack: GSTStack = GSTStack.new()
	var below: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var original: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	var top: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	var texture: Texture2D = PlaceholderTexture2D.new()
	original.label = "clouds"
	original.enabled = false
	original.params = {"octaves": 5, "nested": {"k": [1, 2]}, "image": texture}
	original.slots = {"a": below.id}
	original.param_links = {"gain": {"target": below.id, "amount": 0.25}}
	original.coord.scale = Vector2(2.0, 3.0)
	original.coord.offset = Vector2(0.1, 0.2)
	original.coord.rotation = 0.5
	original.coord.scroll = Vector2(0.3, 0.4)
	original.coord.warp_x = below.id
	original.coord.warp_y = below.id
	original.coord.warp_strength = 0.7
	var next_id_before: int = stack.next_id

	var copy: GSTLayer = GSTStackOps.duplicate_layer(stack, original.id)

	assert_not_null(copy, "duplicate returns the new layer")
	assert_eq(copy.id, StringName(str(next_id_before)), "the copy takes its id from next_id")
	assert_eq(stack.next_id, next_id_before + 1, "next_id advances by one")
	assert_eq(GSTStackOps.find_index(stack, original.id), 1, "the original keeps its index")
	assert_eq(GSTStackOps.find_index(stack, copy.id), 2, "the copy sits directly above the original")
	assert_eq(GSTStackOps.find_index(stack, top.id), 3, "the layer above shifts up by one")
	assert_eq(copy.entry, original.entry, "entry is copied")
	assert_eq(copy.kind_out, original.kind_out, "kind_out is copied")
	assert_eq(copy.enabled, false, "enabled is copied")
	assert_eq(copy.slots, original.slots, "slots are copied")
	assert_eq(copy.params["octaves"], 5, "params values are copied")
	assert_eq(copy.param_links, original.param_links, "param_links are copied")
	copy.slots["a"] = &""
	copy.params["nested"]["k"].append(3)
	copy.param_links["gain"]["amount"] = -1.0
	assert_eq(original.slots["a"], below.id, "slots are a separate dictionary")
	assert_eq(original.params["nested"]["k"].size(), 2, "params nested containers are deep copied")
	assert_eq(original.param_links["gain"]["amount"], 0.25, "param_links entries are deep copied")
	assert_true(copy.params["image"] == texture, "a texture param shares the original Texture2D")
	assert_true(copy.coord != original.coord, "the coord block is a separate resource")
	assert_eq(copy.coord.scale, Vector2(2.0, 3.0), "coord scale is copied")
	assert_eq(copy.coord.offset, Vector2(0.1, 0.2), "coord offset is copied")
	assert_eq(copy.coord.rotation, 0.5, "coord rotation is copied")
	assert_eq(copy.coord.scroll, Vector2(0.3, 0.4), "coord scroll is copied")
	assert_eq(copy.coord.warp_x, below.id, "coord warp_x is copied")
	assert_eq(copy.coord.warp_y, below.id, "coord warp_y is copied")
	assert_eq(copy.coord.warp_strength, 0.7, "coord warp_strength is copied")


func test_duplicate_label_suffixes_the_user_label() -> void:
	var stack: GSTStack = GSTStack.new()
	var original: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	original.label = "grain"
	var copy: GSTLayer = GSTStackOps.duplicate_layer(stack, original.id, _test_library())
	assert_eq(copy.label, "grain copy", "a labelled original gives `<label> copy`")


func test_duplicate_label_falls_back_to_the_function_name() -> void:
	var stack: GSTStack = GSTStack.new()
	var original: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var copy: GSTLayer = GSTStackOps.duplicate_layer(stack, original.id, _test_library())
	assert_eq(copy.label, "generative_hash copy", "an unlabelled original gives `<function> copy`")


func test_duplicate_of_an_operator_has_no_coord_block() -> void:
	var stack: GSTStack = GSTStack.new()
	var original: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	var copy: GSTLayer = GSTStackOps.duplicate_layer(stack, original.id)
	assert_null(copy.coord, "an operator copy keeps coord null")


func test_can_bypass_refuses_every_library_entry_with_no_inputs() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var checked: int = 0
	var failures: Array[String] = []
	for entry_id: String in lib.entries.keys():
		var entry: GSTManifestEntry = lib.get_entry(entry_id)
		if not entry.inputs.is_empty():
			continue
		var stack: GSTStack = GSTStack.new()
		var layer: GSTLayer = GSTStackOps.add_layer(stack, entry_id, entry.kind_out, entry.coord)
		var result: Dictionary = GSTStackOps.can_bypass(stack, layer.id, lib)
		checked += 1
		if result["ok"] or not String(result["reason"]).contains(entry.function):
			failures.append(entry_id)
	assert_true(checked > 0, "the library holds no-input entries to check")
	assert_true(lib.get_entry("color/fill") != null and lib.get_entry("color/fill").inputs.is_empty(), "color/fill is one of the no-input entries")
	assert_true(lib.get_entry("generative/clock") != null and lib.get_entry("generative/clock").inputs.is_empty(), "generative/clock is one of the no-input entries")
	assert_eq(failures, [] as Array[String], "every no-input entry (%d checked) refuses bypass with a reason naming it" % checked)
	print("test_can_bypass_refuses_every_library_entry_with_no_inputs: %d no-input entries checked, ok == false for %d" % [checked, checked - failures.size()])


func test_can_bypass_reason_names_the_label() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	layer.label = "backdrop"
	var result: Dictionary = GSTStackOps.can_bypass(stack, layer.id, lib)
	assert_false(result["ok"], "a no-input operator refuses bypass")
	assert_true(String(result["reason"]).contains("backdrop"), "the reason names the layer by its label")


func test_can_bypass_allows_an_operator_and_a_filter() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var stack: GSTStack = GSTStack.new()
	GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var op: GSTLayer = GSTStackOps.add_layer(stack, "color/mix", GSTLayer.Kind.COLOR, false)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	assert_true(GSTStackOps.can_bypass(stack, op.id, lib)["ok"], "an operator with inputs can be bypassed")
	assert_true(GSTStackOps.can_bypass(stack, filter.id, lib)["ok"], "a filter can be bypassed")


func test_is_source_layer_covers_texture_screen_and_image() -> void:
	var stack: GSTStack = GSTStack.new()
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var screen: GSTLayer = GSTStackOps.add_layer(stack, "source/screen", GSTLayer.Kind.COLOR, false)
	var image: GSTLayer = GSTStackOps.add_layer(stack, "source/image", GSTLayer.Kind.COLOR, true)
	var gen: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	assert_true(GSTStackOps.is_source_layer(stack, tex.id), "source/texture is a source")
	assert_true(GSTStackOps.is_source_layer(stack, screen.id), "source/screen is a source")
	assert_true(GSTStackOps.is_source_layer(stack, image.id), "source/image is a source")
	assert_false(GSTStackOps.is_source_layer(stack, gen.id), "a generator is not a source")
	assert_false(GSTStackOps.is_source_layer(stack, &""), "an empty id is not a source")
	assert_false(GSTStackOps.is_source_layer(stack, &"999"), "an unknown id is not a source")


func test_filter_slot_accepts_a_source_image_layer() -> void:
	var lib: GSTLibrary = _link_library()
	var image_entry: GSTManifestEntry = GSTManifestEntry.new()
	image_entry.id = "source/image"
	image_entry.function = "source_image"
	image_entry.kind_out = GSTLayer.Kind.COLOR
	image_entry.coord = true
	lib.add_entry(image_entry)
	var stack: GSTStack = GSTStack.new()
	var image: GSTLayer = GSTStackOps.add_layer(stack, "source/image", GSTLayer.Kind.COLOR, true)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/test_blur", GSTLayer.Kind.COLOR, false)
	var result: Dictionary = GSTStackOps.assign_slot(stack, filter.id, "source", image.id, lib)
	assert_true(result["ok"], "a filter slot accepts a source/image layer (decision 28)")


func test_validate_param_link_accepts_float_int_and_filter_params() -> void:
	var lib: GSTLibrary = _link_library()
	var ctx: Dictionary = _build_link_stack()
	var stack: GSTStack = ctx["stack"]
	var field: GSTLayer = ctx["field"]
	var linker: GSTLayer = ctx["linker"]
	assert_true(GSTStackOps.validate_param_link(stack, linker.id, "amount", field.id, lib)["ok"], "a float param links to a field below")
	assert_true(GSTStackOps.validate_param_link(stack, linker.id, "steps", field.id, lib)["ok"], "an int param links to a field below")
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var filter: GSTLayer = GSTStackOps.add_layer(stack, "filter/test_blur", GSTLayer.Kind.COLOR, false)
	filter.slots["source"] = tex.id
	assert_true(GSTStackOps.validate_param_link(stack, filter.id, "radius", linker.id, lib)["ok"], "a filter GST_PARAM float links to a color layer below")


func test_validate_param_link_refuses_color_vec3_and_texture_params() -> void:
	var lib: GSTLibrary = _link_library()
	var ctx: Dictionary = _build_link_stack()
	var stack: GSTStack = ctx["stack"]
	var field: GSTLayer = ctx["field"]
	var linker: GSTLayer = ctx["linker"]
	for param_name: String in ["tint", "weights", "image"]:
		var result: Dictionary = GSTStackOps.validate_param_link(stack, linker.id, param_name, field.id, lib)
		assert_false(result["ok"], "param %s does not link" % param_name)
		assert_true(String(result["reason"]).contains(param_name), "the refusal names param %s" % param_name)


func test_validate_param_link_refuses_a_target_at_or_above_the_linker() -> void:
	var lib: GSTLibrary = _link_library()
	var ctx: Dictionary = _build_link_stack()
	var stack: GSTStack = ctx["stack"]
	var linker: GSTLayer = ctx["linker"]
	var above: GSTLayer = GSTStackOps.add_layer(stack, "generative/snoise", GSTLayer.Kind.FIELD, true)
	var result: Dictionary = GSTStackOps.validate_param_link(stack, linker.id, "amount", above.id, lib)
	assert_false(result["ok"], "a target above the linker is refused")
	assert_true(String(result["reason"]).contains("generative_snoise"), "the refusal names the target")
	assert_false(GSTStackOps.validate_param_link(stack, linker.id, "amount", linker.id, lib)["ok"], "a layer cannot link to itself")


func test_validate_param_link_refuses_unknown_param_target_and_layer() -> void:
	var lib: GSTLibrary = _link_library()
	var ctx: Dictionary = _build_link_stack()
	var stack: GSTStack = ctx["stack"]
	var field: GSTLayer = ctx["field"]
	var linker: GSTLayer = ctx["linker"]
	assert_false(GSTStackOps.validate_param_link(stack, linker.id, "missing", field.id, lib)["ok"], "an undeclared param is refused")
	assert_false(GSTStackOps.validate_param_link(stack, linker.id, "amount", &"999", lib)["ok"], "an unknown target is refused")
	assert_false(GSTStackOps.validate_param_link(stack, &"999", "amount", field.id, lib)["ok"], "an unknown linker is refused")
	assert_false(GSTStackOps.validate_param_link(stack, linker.id, "amount", field.id, null)["ok"], "a null library is refused")


func test_set_and_clear_param_link() -> void:
	var ctx: Dictionary = _build_link_stack()
	var stack: GSTStack = ctx["stack"]
	var field: GSTLayer = ctx["field"]
	var linker: GSTLayer = ctx["linker"]
	var result: Dictionary = GSTStackOps.set_param_link(stack, linker.id, "amount", field.id, 0.5)
	assert_true(result["ok"], "set_param_link stores a link to a layer below")
	assert_eq(linker.param_links["amount"], {"target": field.id, "amount": 0.5}, "the link stores target and amount")
	GSTStackOps.set_param_link(stack, linker.id, "steps", field.id, 4.0)
	assert_eq(linker.param_links["steps"]["amount"], 1.0, "amount clamps to the -1..1 range")
	assert_true(GSTStackOps.clear_param_link(stack, linker.id, "amount"), "clear reports an erased link")
	assert_false(linker.param_links.has("amount"), "the cleared param has no link entry")
	assert_false(GSTStackOps.clear_param_link(stack, linker.id, "amount"), "clearing an absent link reports false")


func test_delete_link_target_clears_the_link_and_reports_the_param() -> void:
	var lib: GSTLibrary = _link_library()
	var ctx: Dictionary = _build_link_stack()
	var stack: GSTStack = ctx["stack"]
	var field: GSTLayer = ctx["field"]
	var linker: GSTLayer = ctx["linker"]
	var unrelated: GSTLayer = GSTStackOps.add_layer(stack, "generative/snoise", GSTLayer.Kind.FIELD, true)
	linker.slots.clear()
	GSTStackOps.set_param_link(stack, linker.id, "amount", field.id, 1.0)
	var report: Array[Dictionary] = []

	var changed: Array[StringName] = GSTStackOps.remove_layer(stack, field.id, lib, report)

	assert_false(linker.param_links.has("amount"), "the link targeting the deleted layer is cleared")
	assert_eq(changed, [linker.id] as Array[StringName], "the linker is reported as changed")
	assert_eq(report.size(), 1, "one cleared reference is reported")
	assert_eq(report[0]["layer"], linker.id, "the report names the linker")
	assert_eq(report[0]["kind"], "link", "the report entry is a link edge")
	assert_eq(report[0]["name"], "amount", "the report contains the param name")
	assert_eq(report[0]["target"], field.id, "the report names the deleted target")
	assert_true(unrelated.param_links.is_empty(), "an unrelated layer is untouched")
	print("test_delete_link_target_clears_the_link_and_reports_the_param: link cleared=%s, report=%s" % [not linker.param_links.has("amount"), str(report)])


func test_delete_reports_slot_and_warp_clears_with_names() -> void:
	var stack: GSTStack = GSTStack.new()
	var a: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var b: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	var c: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	b.slots["a"] = a.id
	c.coord.warp_y = a.id
	var report: Array[Dictionary] = []
	GSTStackOps.remove_layer(stack, a.id, _test_library(), report)
	assert_eq(report.size(), 2, "the slot and the warp clear are both reported")
	assert_eq(report[0], {"layer": b.id, "kind": "slot", "name": "a", "target": a.id}, "the slot clear names the slot")
	assert_eq(report[1], {"layer": c.id, "kind": "warp_y", "name": "warp_y", "target": a.id}, "the warp clear names the warp")


func test_reorder_link_target_above_its_linker_is_refused() -> void:
	var ctx: Dictionary = _build_link_stack()
	var stack: GSTStack = ctx["stack"]
	var field: GSTLayer = ctx["field"]
	var linker: GSTLayer = ctx["linker"]
	linker.slots.clear()
	linker.label = "tinted"
	field.manifest = _link_library().get_entry(field.entry)
	GSTStackOps.set_param_link(stack, linker.id, "amount", field.id, 1.0)
	var result: Dictionary = GSTStackOps.reorder_layer(stack, field.id, 1)
	assert_false(result["ok"], "moving a link target above its linker is refused")
	assert_true(String(result["reason"]).contains("tinted"), "the reason names the linker")
	assert_true(String(result["reason"]).contains("generative_hash"), "the reason names the target")
	assert_eq(GSTStackOps.find_index(stack, field.id), 0, "stack order is unchanged after the refusal")
	print("test_reorder_link_target_above_its_linker_is_refused: ok=%s, reason=%s" % [result["ok"], result["reason"]])


func test_edges_of_lists_slot_warp_and_link_edges_with_names() -> void:
	var stack: GSTStack = GSTStack.new()
	var a: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var b: GSTLayer = GSTStackOps.add_layer(stack, "generative/snoise", GSTLayer.Kind.FIELD, true)
	var c: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	c.slots = {"a": a.id, "unset": &""}
	c.coord.warp_x = b.id
	c.coord.warp_y = a.id
	c.param_links = {"gain": {"target": b.id, "amount": 0.5}}
	var edges: Array[Dictionary] = GSTStackOps.edges_of(c)
	assert_eq(edges.size(), 4, "empty slots are omitted; slot, two warps and one link remain")
	assert_eq(edges[0], {"kind": "slot", "name": "a", "target": a.id}, "slot edge carries the slot name")
	assert_eq(edges[1], {"kind": "warp_x", "name": "warp_x", "target": b.id}, "warp_x edge")
	assert_eq(edges[2], {"kind": "warp_y", "name": "warp_y", "target": a.id}, "warp_y edge")
	assert_eq(edges[3], {"kind": "link", "name": "gain", "target": b.id}, "link edge carries the param name")
	assert_eq(GSTStackOps._references_of(c), [a.id, b.id, a.id, b.id] as Array[StringName], "_references_of projects the edge targets")
