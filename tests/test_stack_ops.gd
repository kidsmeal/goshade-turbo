extends GSTTestBase

## Structural mutations: slot assign, reorder, delete. Design decisions 3
## and 22.


## These tests never touch a samples_source slot, but assign_slot now refuses
## any assignment whose assigning layer's entry does not resolve in the
## given library (an unresolved entry must never bypass the source-only
## rule). This builds a minimal library with one manifest entry per entry id
## these tests assign layers with, so resolution succeeds without a full
## library scan.
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
