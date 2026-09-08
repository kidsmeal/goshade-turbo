extends GSTTestBase

## GSTStackIO: save/load a GSTStack .tres (design decision 8, docs/PLAN.md
## Phase 6 Files). Writes only under user:// (docs/PLAN.md Phase 6
## Verification: "save into user:// or the scratchpad, not into the repo").
##
## _compare_stacks/_compare_layers/_compare_dict/_compare_coord (phase 6 fix
## pass 2, item 2) return every mismatch as a list of strings instead of
## stopping at the first assert_eq failure, so one test run reports every
## field the round trip dropped, reordered, or coerced, not just the first
## one found.


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


## Every persisted GSTStack field: coord_space, output_color, output_alpha,
## next_id, layer count, then layer order and content via _compare_layers.
## Returns early on a layer-count mismatch: a per-index layer comparison is
## meaningless once the arrays are different lengths.
func _compare_stacks(original: GSTStack, loaded: GSTStack) -> Array[String]:
	var mismatches: Array[String] = []
	if int(loaded.coord_space) != int(original.coord_space):
		mismatches.append("stack.coord_space: expected %d, got %d" % [int(original.coord_space), int(loaded.coord_space)])
	if loaded.output_color != original.output_color:
		mismatches.append("stack.output_color: expected '%s', got '%s'" % [String(original.output_color), String(loaded.output_color)])
	if loaded.output_alpha != original.output_alpha:
		mismatches.append("stack.output_alpha: expected '%s', got '%s'" % [String(original.output_alpha), String(loaded.output_alpha)])
	if loaded.next_id != original.next_id:
		mismatches.append("stack.next_id: expected %d, got %d" % [original.next_id, loaded.next_id])
	if loaded.layers.size() != original.layers.size():
		mismatches.append("stack.layers count: expected %d, got %d" % [original.layers.size(), loaded.layers.size()])
		return mismatches
	for i: int in range(original.layers.size()):
		mismatches.append_array(_compare_layers(original.layers[i], loaded.layers[i], i))
	return mismatches


## Every persisted GSTLayer field for one stack-order index: id, entry,
## kind_out, every slots entry, every params entry (with type equality), and
## the coord block (null-ness, then every field when both are non-null).
func _compare_layers(original: GSTLayer, loaded: GSTLayer, index: int) -> Array[String]:
	var mismatches: Array[String] = []
	var prefix: String = "layer[%d] (%s)" % [index, original.entry]
	if loaded.id != original.id:
		mismatches.append("%s.id: expected '%s', got '%s'" % [prefix, String(original.id), String(loaded.id)])
	if loaded.entry != original.entry:
		mismatches.append("%s.entry: expected '%s', got '%s'" % [prefix, original.entry, loaded.entry])
	if loaded.kind_out != original.kind_out:
		mismatches.append("%s.kind_out: expected %d, got %d" % [prefix, original.kind_out, loaded.kind_out])
	mismatches.append_array(_compare_dict("%s.slots" % prefix, original.slots, loaded.slots))
	mismatches.append_array(_compare_dict("%s.params" % prefix, original.params, loaded.params))
	if (original.coord == null) != (loaded.coord == null):
		mismatches.append("%s.coord null-ness: expected %s, got %s" % [prefix, original.coord == null, loaded.coord == null])
	elif original.coord != null:
		mismatches.append_array(_compare_coord("%s.coord" % prefix, original.coord, loaded.coord))
	return mismatches


## Every key present in either dictionary: a key missing after load, an extra
## key introduced by load, a type mismatch (a Color must stay a Color, an int
## must stay an int rather than silently becoming a float through the .tres
## round trip), and a value mismatch are each reported as a separate line.
func _compare_dict(label: String, original: Dictionary, loaded: Dictionary) -> Array[String]:
	var mismatches: Array[String] = []
	for key: Variant in original.keys():
		if not loaded.has(key):
			mismatches.append("%s missing key '%s' after load" % [label, key])
			continue
		var original_value: Variant = original[key]
		var loaded_value: Variant = loaded[key]
		if typeof(loaded_value) != typeof(original_value):
			mismatches.append("%s['%s'] type: expected %s, got %s" % [label, key, type_string(typeof(original_value)), type_string(typeof(loaded_value))])
		elif loaded_value != original_value:
			mismatches.append("%s['%s']: expected %s, got %s" % [label, key, str(original_value), str(loaded_value)])
	for key: Variant in loaded.keys():
		if not original.has(key):
			mismatches.append("%s has unexpected extra key '%s' after load" % [label, key])
	return mismatches


## Every GSTCoordBlock field: scale, offset, rotation, scroll, warp_x/warp_y
## (value and StringName type -- coord is a plain, untyped-value-carrying
## sub-resource path through the Dictionary-free @export fields, but
## warp_x/warp_y are declared StringName so GSTStackIO's own
## _normalize_stringnames defensive re-wrap only applies to GSTLayer.slots;
## checked here anyway as a direct round-trip guarantee), and warp_strength.
func _compare_coord(label: String, original: GSTCoordBlock, loaded: GSTCoordBlock) -> Array[String]:
	var mismatches: Array[String] = []
	if not loaded.scale.is_equal_approx(original.scale):
		mismatches.append("%s.scale: expected %s, got %s" % [label, original.scale, loaded.scale])
	if not loaded.offset.is_equal_approx(original.offset):
		mismatches.append("%s.offset: expected %s, got %s" % [label, original.offset, loaded.offset])
	if not is_equal_approx(loaded.rotation, original.rotation):
		mismatches.append("%s.rotation: expected %s, got %s" % [label, original.rotation, loaded.rotation])
	if not loaded.scroll.is_equal_approx(original.scroll):
		mismatches.append("%s.scroll: expected %s, got %s" % [label, original.scroll, loaded.scroll])
	if typeof(loaded.warp_x) != TYPE_STRING_NAME:
		mismatches.append("%s.warp_x type: expected StringName, got %s" % [label, type_string(typeof(loaded.warp_x))])
	elif loaded.warp_x != original.warp_x:
		mismatches.append("%s.warp_x: expected '%s', got '%s'" % [label, String(original.warp_x), String(loaded.warp_x)])
	if typeof(loaded.warp_y) != TYPE_STRING_NAME:
		mismatches.append("%s.warp_y type: expected StringName, got %s" % [label, type_string(typeof(loaded.warp_y))])
	elif loaded.warp_y != original.warp_y:
		mismatches.append("%s.warp_y: expected '%s', got '%s'" % [label, String(original.warp_y), String(loaded.warp_y)])
	if not is_equal_approx(loaded.warp_strength, original.warp_strength):
		mismatches.append("%s.warp_strength: expected %s, got %s" % [label, original.warp_strength, loaded.warp_strength])
	return mismatches
