extends GSTTestBase

## GSTLibrary indexing over the real, shipped seed manifests under
## addons/goshade_turbo/library/. Design: docs/DESIGN.md, Manifest entry.


## Every manifest id the library is expected to index (58 entries, 2026-09-15
## unit-failure fix pass). A hardcoded roster count let a block be added
## without being listed, so this is compared as a sorted array against
## GSTLibrary.scan()'s actual result and reports missing/extra ids by name.
## New entries must be added here on purpose.
const EXPECTED_LIBRARY_IDS: Array[String] = [
	"color/add", "color/brightness_contrast", "color/fill", "color/gradient_map",
	"color/hue_shift", "color/mix", "color/multiply", "color/overlay", "color/palette",
	"color/posterize", "color/saturation", "color/screen", "color/soft_light",
	"fieldops/abs", "fieldops/add", "fieldops/alpha", "fieldops/ease", "fieldops/fract",
	"fieldops/invert", "fieldops/max", "fieldops/min", "fieldops/mix", "fieldops/multiply",
	"fieldops/pow", "fieldops/ratchet", "fieldops/remap", "fieldops/smoothstep",
	"filter/box_blur", "filter/chromatic_split", "filter/dither", "filter/outline", "filter/pixelate",
	"generative/cell_borders", "generative/cellular_edges", "generative/checker", "generative/clock",
	"generative/fbm", "generative/hash", "generative/linear_gradient", "generative/perlin",
	"generative/radial_gradient", "generative/snoise", "generative/stripes", "generative/value_noise",
	"generative/voronoi",
	"sdf/box", "sdf/circle", "sdf/intersect", "sdf/line", "sdf/polygon", "sdf/ring",
	"sdf/rounded_box", "sdf/smooth_union", "sdf/star", "sdf/subtract", "sdf/union",
	"source/screen", "source/texture",
]


func test_scan_indexes_the_full_library_roster() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var actual_ids: Array[String] = []
	for id: String in lib.entries.keys():
		actual_ids.append(id)
	var actual_sorted: Array[String] = actual_ids.duplicate()
	actual_sorted.sort()
	var expected_sorted: Array[String] = EXPECTED_LIBRARY_IDS.duplicate()
	expected_sorted.sort()
	assert_eq(actual_sorted, expected_sorted, "library roster matches the expected 58-entry id set (%s)" % _roster_diff_message(actual_ids, EXPECTED_LIBRARY_IDS))
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


func test_every_manifest_input_and_param_has_editor_metadata() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	for id: String in lib.entries.keys():
		var manifest_entry: GSTManifestEntry = lib.get_entry(id)
		for input: Dictionary in manifest_entry.inputs:
			var input_name: String = String(input.get("name", ""))
			assert_false(String(input.get("label", "")).strip_edges().is_empty(), "%s input %s has a nonempty editor label" % [id, input_name])
			assert_false(String(input.get("description", "")).strip_edges().is_empty(), "%s input %s has a nonempty editor description" % [id, input_name])
		for param: Dictionary in manifest_entry.params:
			var param_name: String = String(param.get("name", ""))
			assert_false(String(param.get("label", "")).strip_edges().is_empty(), "%s param %s has a nonempty editor label" % [id, param_name])
			assert_false(String(param.get("description", "")).strip_edges().is_empty(), "%s param %s has a nonempty editor description" % [id, param_name])


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
