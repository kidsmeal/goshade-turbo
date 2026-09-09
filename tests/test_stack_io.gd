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


func test_palette_color_center_uses_color_editor_without_changing_vec3_schema() -> void:
	var lib: GSTLibrary = _scanned_library()
	var entry: GSTManifestEntry = lib.get_entry("color/palette")
	var stack: GSTStack = GSTStack.new()
	var palette: GSTLayer = GSTStackOps.add_layer(stack, "color/palette", GSTLayer.Kind.COLOR, false)
	palette.manifest = entry
	var a_schema: Dictionary = {}
	for param: Dictionary in entry.params:
		if String(param.get("name", "")) == "a":
			a_schema = param
	var property_info: Dictionary = {}
	var vector_properties: Array[String] = []
	for property: Dictionary in palette.get_property_list():
		var property_name: String = String(property.get("name", ""))
		if property_name == "a":
			property_info = property
		elif int(property.get("type", -1)) == TYPE_VECTOR3:
			vector_properties.append(property_name)
	vector_properties.sort()
	assert_eq(String(a_schema.get("type", "")), "vec3", "palette a retains its vec3 shader/storage schema")
	assert_eq(String(a_schema.get("editor", "")), "color_rgb", "palette a opts into the RGB color editor")
	assert_eq(int(property_info.get("type", -1)), TYPE_COLOR, "palette a exposes a Color dynamic editor property")
	assert_eq(int(property_info.get("hint", -1)), PROPERTY_HINT_COLOR_NO_ALPHA, "palette a color editor has no alpha channel")
	assert_eq(vector_properties, ["b", "c", "d"], "palette b/c/d remain Vector3 editor properties")


func test_palette_color_center_access_preserves_rgb_and_ignores_alpha() -> void:
	var lib: GSTLibrary = _scanned_library()
	var palette: GSTLayer = GSTStackOps.add_layer(GSTStack.new(), "color/palette", GSTLayer.Kind.COLOR, false)
	palette.manifest = lib.get_entry(palette.entry)
	var default_value: Variant = palette.get(&"a")
	assert_true(default_value is Color, "palette a reads its raw vec3 default through a Color editor value")
	assert_eq(default_value, Color(0.5, 0.5, 0.5, 1.0), "palette a default preserves RGB and supplies opaque editor alpha")
	var raw_value: Vector3 = Vector3(-0.25, 1.75, 3.5)
	palette.set(&"a", raw_value)
	assert_eq(palette.params.get("a"), raw_value, "a direct Vector3 write remains accepted and raw")
	assert_eq(palette.get(&"a"), Color(raw_value.x, raw_value.y, raw_value.z, 1.0), "negative and HDR Vector3 components survive the Color read adapter")
	var editor_value: Color = Color(-0.5, 2.25, 4.0, 0.125)
	palette.set(&"a", editor_value)
	assert_true(palette.params.get("a") is Vector3, "a Color editor write is normalized to Vector3 backing storage")
	assert_eq(palette.params.get("a"), Vector3(editor_value.r, editor_value.g, editor_value.b), "Color alpha is ignored while negative and HDR RGB are preserved")
	assert_eq(palette.get(&"a"), Color(editor_value.r, editor_value.g, editor_value.b, 1.0), "the adapted read remains opaque without clamping RGB")


func test_palette_color_center_reads_do_not_mutate_and_color_writes_round_trip_as_vec3() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var source: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	source.manifest = lib.get_entry(source.entry)
	var palette: GSTLayer = GSTStackOps.add_layer(stack, "color/palette", GSTLayer.Kind.COLOR, false)
	palette.manifest = lib.get_entry(palette.entry)
	GSTStackOps.assign_slot(stack, palette.id, "t", source.id, lib)
	var raw_before: Dictionary = palette.params.duplicate(true)
	var header_before: String = GSTHeader.header_line(stack)
	var shader_before: String = GSTCodegen.generate(stack, lib)
	var unused_editor_read: Variant = palette.get(&"a")
	assert_true(unused_editor_read is Color, "palette a can be read through the editor adapter")
	assert_eq(palette.params, raw_before, "reading palette a does not insert or rewrite a raw param key")
	assert_eq(GSTHeader.header_line(stack), header_before, "reading palette a leaves the serialized header byte-identical")
	assert_eq(GSTCodegen.generate(stack, lib), shader_before, "reading palette a leaves generated shader text byte-identical")

	var written: Color = Color(1.4, -0.2, 0.625, 0.05)
	palette.set(&"a", written)
	var expected_raw: Vector3 = Vector3(written.r, written.g, written.b)
	var path: String = "user://gst_test_palette_color_center_roundtrip.tres"
	var saved: Dictionary = GSTStackIO.save(stack, path)
	assert_true(saved["ok"], "palette color-center stack saves: %s" % saved["reason"])
	var loaded_result: Dictionary = GSTStackIO.load(path, lib)
	assert_true(loaded_result["ok"], "palette color-center stack reloads: %s" % loaded_result["reason"])
	if loaded_result["ok"]:
		var loaded_palette: GSTLayer = (loaded_result["stack"] as GSTStack).layers[1]
		assert_true(loaded_palette.params.get("a") is Vector3, "saved palette a reloads as Vector3 backing storage")
		assert_eq(loaded_palette.params.get("a"), expected_raw, "saved palette a preserves the written RGB vector")
		assert_eq(loaded_palette.get(&"a"), Color(expected_raw.x, expected_raw.y, expected_raw.z, 1.0), "reloaded palette a exposes the matching opaque Color")
	var header_result: Dictionary = GSTHeader.parse(GSTHeader.header_line(stack), lib)
	assert_true(header_result["ok"], "palette color-center shader header parses")
	if header_result["ok"]:
		var header_palette: GSTLayer = (header_result["stack"] as GSTStack).layers[1]
		assert_true(header_palette.params.get("a") is Vector3, "shader header keeps palette a as a three-component vector")
		assert_eq(header_palette.params.get("a"), expected_raw, "shader header preserves the written palette RGB vector")
	assert_true(GSTCodegen.generate(stack, lib).contains("uniform vec3 l%s_palette_a" % String(palette.id)), "palette a remains a vec3 shader uniform after a Color editor write")
	DirAccess.remove_absolute(path)
