extends GSTTestBase

## GSTIncludeWalk: depth-first over depends, deduped by id, dependencies
## emitted before dependents. Design: docs/DESIGN.md, Codegen rules.


func _make_entry(id: String, function_name: String, depends: Array[String]) -> GSTManifestEntry:
	var entry: GSTManifestEntry = GSTManifestEntry.new()
	entry.id = id
	entry.function = function_name
	entry.depends = depends
	return entry


func _synthetic_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.add_entry(_make_entry("math/c", "c_fn", []))
	lib.add_entry(_make_entry("math/b", "b_fn", ["math/c"]))
	lib.add_entry(_make_entry("generative/a", "a_fn", ["math/b"]))
	lib.add_entry(_make_entry("generative/d", "d_fn", []))
	return lib


func test_dependencies_are_ordered_before_the_dependent() -> void:
	var lib: GSTLibrary = _synthetic_library()
	var root_ids: Array[String] = ["generative/a"]
	var order: Array[GSTManifestEntry] = GSTIncludeWalk.walk(root_ids, lib)
	var ids: Array[String] = []
	for entry: GSTManifestEntry in order:
		ids.append(entry.id)
	assert_eq(ids, ["math/c", "math/b", "generative/a"], "c before b before a, depth first over depends")


func test_a_shared_dependency_is_emitted_once() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.add_entry(_make_entry("math/shared", "shared_fn", []))
	lib.add_entry(_make_entry("generative/x", "x_fn", ["math/shared"]))
	lib.add_entry(_make_entry("generative/y", "y_fn", ["math/shared"]))
	var order: Array[GSTManifestEntry] = GSTIncludeWalk.walk(["generative/x", "generative/y"], lib)
	var ids: Array[String] = []
	for entry: GSTManifestEntry in order:
		ids.append(entry.id)
	assert_eq(ids, ["math/shared", "generative/x", "generative/y"], "shared dependency emitted once, before both dependents")
	assert_eq(ids.count("math/shared"), 1, "the shared entry appears exactly once")


func test_independent_roots_are_all_included() -> void:
	var lib: GSTLibrary = _synthetic_library()
	var order: Array[GSTManifestEntry] = GSTIncludeWalk.walk(["generative/a", "generative/d"], lib)
	var ids: Array[String] = []
	for entry: GSTManifestEntry in order:
		ids.append(entry.id)
	assert_eq(ids, ["math/c", "math/b", "generative/a", "generative/d"], "d has no depends, appended after a's chain")


func test_walk_over_the_real_shipped_fbm_chain() -> void:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	var order: Array[GSTManifestEntry] = GSTIncludeWalk.walk(["generative/fbm"], lib)
	var ids: Array[String] = []
	for entry: GSTManifestEntry in order:
		ids.append(entry.id)
	assert_eq(ids, ["generative/hash", "generative/snoise", "generative/fbm"], "the real fbm -> snoise -> hash depends chain resolves hash first, fbm last")
