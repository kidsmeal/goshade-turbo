extends GSTTestBase

## GSTStackIO: save/load a GSTStack .tres (design decision 8, docs/PLAN.md
## Phase 6 Files). Writes only under user:// (docs/PLAN.md Phase 6
## Verification: "save into user:// or the scratchpad, not into the repo").
##
## _compare_stacks/_compare_layers/_compare_dict/_compare_coord (phase 6 fix
## pass 2, item 2; moved to gst_test_base.gd in phase 7 so
## tests/test_recipe_roundtrip.gd can reuse them, docs/PLAN.md Phase 7 Build)
## return every mismatch as a list of strings instead of stopping at the
## first assert_eq failure, so one test run reports every field the round
## trip dropped, reordered, or coerced, not just the first one found.


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


## A generator with a coord block and warp refs, an operator with slots, an
## int param (type-equality check: octaves must stay int, not become float
## through the .tres round trip), a color param, vec3 params, output_color,
## output_alpha, and a next_id gap (ids 0-4 exist, next_id is 7, simulating
## two deleted layers -- decision 22: ids are never reused). Real shipped
## manifests (generative/hash, generative/fbm, fieldops/invert, color/fill,
## color/palette), not a synthetic fixture (real-input rule).
func _build_stack(lib: GSTLibrary) -> Dictionary:
	var stack: GSTStack = GSTStack.new()

	var hash_layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)

	var fbm: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	fbm.coord.scale = Vector2(2.0, 3.0)
	fbm.coord.offset = Vector2(0.1, -0.2)
	fbm.coord.rotation = 0.5
	fbm.coord.scroll = Vector2(0.3, 0.4)
	fbm.coord.warp_x = hash_layer.id
	fbm.coord.warp_y = &""
	fbm.coord.warp_strength = 0.6
	fbm.params["octaves"] = 6

	var invert: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, invert.id, "x", fbm.id, lib)

	var fill: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	fill.params["color"] = Color(0.2, 0.4, 0.6, 0.9)

	var palette: GSTLayer = GSTStackOps.add_layer(stack, "color/palette", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, palette.id, "t", invert.id, lib)
	palette.params["a"] = Vector3(0.1, 0.2, 0.3)
	palette.params["b"] = Vector3(0.4, 0.5, 0.6)
	palette.params["c"] = Vector3(1.5, 1.0, 0.5)
	palette.params["d"] = Vector3(0.0, 0.33, 0.67)

	stack.output_color = palette.id
	stack.output_alpha = invert.id
	stack.next_id = 7 # gap: ids 5 and 6 never existed (deleted before save)

	return {
		"stack": stack, "hash": hash_layer, "fbm": fbm, "invert": invert,
		"fill": fill, "palette": palette,
	}


func test_save_and_load_round_trips_every_field() -> void:
	var lib: GSTLibrary = _scanned_library()
	var ctx: Dictionary = _build_stack(lib)
	var stack: GSTStack = ctx["stack"]
	var path: String = "user://gst_test_stack_io_roundtrip.tres"

	var save_result: Dictionary = GSTStackIO.save(stack, path)
	assert_true(save_result["ok"], "save succeeds: %s" % save_result["reason"])

	var load_result: Dictionary = GSTStackIO.load(path, lib)
	assert_true(load_result["ok"], "load succeeds: %s" % load_result["reason"])
	var loaded: GSTStack = load_result["stack"]
	assert_not_null(loaded, "load returns a stack")
	if loaded == null:
		DirAccess.remove_absolute(path)
		return

	var mismatches: Array[String] = _compare_stacks(stack, loaded)
	assert_true(mismatches.is_empty(), "round trip field mismatches (%d): %s" % [mismatches.size(), mismatches])

	assert_eq(loaded.layers[0].manifest, lib.get_entry("generative/hash"), "manifest is re-resolved from the library on load (hash)")
	assert_eq(loaded.layers[1].manifest, lib.get_entry("generative/fbm"), "manifest is re-resolved from the library on load (fbm)")
	assert_eq(loaded.layers[2].manifest, lib.get_entry("fieldops/invert"), "manifest is re-resolved from the library on load (invert)")
	assert_eq(loaded.layers[3].manifest, lib.get_entry("color/fill"), "manifest is re-resolved from the library on load (fill)")
	assert_eq(loaded.layers[4].manifest, lib.get_entry("color/palette"), "manifest is re-resolved from the library on load (palette)")

	DirAccess.remove_absolute(path)


func test_load_refuses_unresolved_entry() -> void:
	var lib: GSTLibrary = _scanned_library()
	var ctx: Dictionary = _build_stack(lib)
	var stack: GSTStack = ctx["stack"]
	var path: String = "user://gst_test_stack_io_unresolved.tres"

	var save_result: Dictionary = GSTStackIO.save(stack, path)
	assert_true(save_result["ok"], "save succeeds: %s" % save_result["reason"])

	var empty_lib: GSTLibrary = GSTLibrary.new() # never scanned: every entry is unresolved
	var load_result: Dictionary = GSTStackIO.load(path, empty_lib)
	assert_false(load_result["ok"], "load against a library with no entries is refused")
	assert_true(load_result["reason"].contains("generative/hash") or load_result["reason"].contains("unresolved"), "refusal reason names the unresolved entry: %s" % load_result["reason"])

	DirAccess.remove_absolute(path)


func test_editor_metadata_does_not_enter_saved_resources() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = _build_stack(lib)["stack"] as GSTStack
	var path: String = "user://gst_test_labels_storage.tres"
	for layer: GSTLayer in stack.layers:
		layer.manifest = lib.get_entry(layer.entry)
	var saved: Dictionary = GSTStackIO.save(stack, path)
	assert_true(saved["ok"], "save stack with labeled manifests: %s" % saved["reason"])
	var labeled_text: String = FileAccess.get_file_as_string(path)
	for layer: GSTLayer in stack.layers:
		layer.manifest = null
	saved = GSTStackIO.save(stack, path)
	assert_true(saved["ok"], "save stack without runtime manifests: %s" % saved["reason"])
	assert_eq(FileAccess.get_file_as_string(path), labeled_text, "runtime manifest metadata does not alter serialized resource bytes")
	var loaded: Dictionary = GSTStackIO.load(path, lib)
	assert_true(loaded["ok"], "load retains stored property keys after bookkeeping is hidden")
	if loaded["ok"]:
		assert_true(_compare_stacks(stack, loaded["stack"]).is_empty(), "hidden storage fields and original parameter keys survive save/load")
	DirAccess.remove_absolute(path)
