extends GSTTestBase

## GSTLibrary indexing over the real, shipped seed manifests under
## addons/goshade_turbo/library/. Design: docs/DESIGN.md, Manifest entry.


func test_scan_indexes_the_three_seed_manifests() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	assert_eq(lib.size(), 3, "the seed library holds exactly the 3 phase 1 manifests")
	assert_not_null(lib.get_entry("generative/hash"), "hash manifest is indexed")
	assert_not_null(lib.get_entry("generative/snoise"), "snoise manifest is indexed")
	assert_not_null(lib.get_entry("generative/fbm"), "fbm manifest is indexed")
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
