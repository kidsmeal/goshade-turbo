extends GSTTestBase

## GSTLibrary indexing over the real, shipped seed manifests under
## addons/goshade_turbo/library/. Design: docs/DESIGN.md, Manifest entry.


func test_scan_indexes_the_full_library_roster() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	# Phase 1 shipped 3 seed manifests. Phase 2 filled out the v0.1 generative
	# (11) and fieldops (11) rosters. Phase 3 adds source (2), filter (5),
	# color (13), and fieldops/alpha (1): 22 + 21 = 43. This count grows again
	# in phase 8 (sdf).
	assert_eq(lib.size(), 43, "phase 2's 22 plus phase 3's source/filter/color/alpha roster (21)")
	assert_not_null(lib.get_entry("generative/hash"), "hash manifest is indexed")
	assert_not_null(lib.get_entry("generative/snoise"), "snoise manifest is indexed")
	assert_not_null(lib.get_entry("generative/fbm"), "fbm manifest is indexed")
	assert_not_null(lib.get_entry("source/texture"), "source/texture manifest is indexed")
	assert_not_null(lib.get_entry("source/screen"), "source/screen manifest is indexed")
	assert_not_null(lib.get_entry("filter/pixelate"), "filter/pixelate manifest is indexed")
	assert_not_null(lib.get_entry("color/fill"), "color/fill manifest is indexed")
	assert_not_null(lib.get_entry("fieldops/alpha"), "fieldops/alpha manifest is indexed")
	assert_true(lib.duplicate_functions.is_empty(), "no duplicate functions in the seed library")


func test_scan_loaded_entries_carry_real_shader_code_and_citations() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()

	var hash_entry: GSTManifestEntry = lib.get_entry("generative/hash")
	assert_eq(hash_entry.function, "hash", "hash manifest declares function hash")
	assert_true(hash_entry.coord, "hash is a generator")
	assert_false(hash_entry.source_math.is_empty(), "hash cites its math source")
	assert_false(hash_entry.code.is_empty(), "hash carries real GLSL code")

	var snoise_entry: GSTManifestEntry = lib.get_entry("generative/snoise")
	assert_eq(snoise_entry.function, "snoise", "snoise manifest declares function snoise")
	var expected_snoise_depends: Array[String] = ["generative/hash"]
	assert_eq(snoise_entry.depends, expected_snoise_depends, "snoise depends on hash")
	assert_false(snoise_entry.source_math.is_empty(), "snoise cites its math source")

	var fbm_entry: GSTManifestEntry = lib.get_entry("generative/fbm")
	assert_eq(fbm_entry.function, "fbm", "fbm manifest declares function fbm")
	assert_eq(fbm_entry.kind_out, GSTLayer.Kind.FIELD, "fbm outputs a field")
	var expected_fbm_depends: Array[String] = ["generative/snoise"]
	assert_eq(fbm_entry.depends, expected_fbm_depends, "fbm depends on snoise")
	assert_eq(fbm_entry.params.size(), 2, "fbm declares octaves and gain params")
	assert_false(fbm_entry.source_math.is_empty(), "fbm cites its math source")


func test_every_manifest_kind_field_is_a_valid_gst_layer_kind() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var valid_kinds: Array[int] = [GSTLayer.Kind.FIELD, GSTLayer.Kind.COLOR]
	for id: String in lib.entries.keys():
		var manifest_entry: GSTManifestEntry = lib.get_entry(id)
		assert_true(valid_kinds.has(manifest_entry.kind_out), "%s kind_out is a valid GSTLayer.Kind value" % id)
		for input: Dictionary in manifest_entry.inputs:
			assert_true(valid_kinds.has(input["kind"]), "%s input %s kind is a valid GSTLayer.Kind value" % [id, input["name"]])


## GSTLayer._property_type_for maps exactly these five type strings; any
## other value falls back to TYPE_FLOAT with a push_warning naming the entry
## and param (docs/PLAN.md phase 4 fix pass 2, item 1). Every real manifest
## param type must be one of the known set so the inspector column never
## silently falls back for shipped data.
func test_every_manifest_param_type_is_known() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var known_types: Array[String] = ["int", "float", "color", "vec2", "vec3"]
	for id: String in lib.entries.keys():
		var manifest_entry: GSTManifestEntry = lib.get_entry(id)
		for param: Dictionary in manifest_entry.params:
			var param_type: String = String(param.get("type", ""))
			assert_true(known_types.has(param_type), "%s param %s has known type '%s'" % [id, param["name"], param_type])


func test_add_entry_flags_a_duplicate_function_name() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	var first: GSTManifestEntry = GSTManifestEntry.new()
	first.id = "generative/foo"
	first.function = "foo"
	var second: GSTManifestEntry = GSTManifestEntry.new()
	second.id = "generative/foo_alt"
	second.function = "foo"

	assert_true(lib.add_entry(first), "the first claim of a function name succeeds")
	assert_false(lib.add_entry(second), "a second claim of the same function name is refused")
	assert_true(lib.has_duplicate_function("foo"), "the collision is recorded")
	assert_eq(lib.size(), 1, "the duplicate entry is not indexed")
