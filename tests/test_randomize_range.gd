extends GSTTestBase

## GSTRandomize (docs/PLAN.md Phase 8 Build item 3, design decision 16):
## every randomized value stays inside its manifest range and carries the
## correct GDScript type, the same seed reproduces the same values, and a
## stack with no randomizable params yields an empty change set.

const RUNS_PER_RECIPE: int = 200
const RECIPES_DIR: String = "res://addons/goshade_turbo/recipes"


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


func _recipe_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(RECIPES_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and entry_name.ends_with(".tres"):
			paths.append(RECIPES_DIR.path_join(entry_name))
		entry_name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


## Every shipped recipe, randomized RUNS_PER_RECIPE times: every produced
## value stays inside the manifest's own min/max (or, for a vec3 param with
## no declared min/max, inside [0, 1] per component -- color/palette's
## a/b/c/d), and carries the GDScript type its manifest "type" implies.
func test_every_recipe_randomize_stays_inside_manifest_range() -> void:
	var lib: GSTLibrary = _scanned_library()
	var recipe_paths: Array[String] = _recipe_paths()
	assert_true(recipe_paths.size() >= 12, "at least 12 shipped recipes to check (got %d)" % recipe_paths.size())

	var checked_values: int = 0
	for path: String in recipe_paths:
		var load_result: Dictionary = GSTStackIO.load(path, lib)
		assert_true(load_result["ok"], "%s loads: %s" % [path, load_result.get("reason", "")])
		if not load_result["ok"]:
			continue
		var stack: GSTStack = load_result["stack"]

		for run_index: int in range(RUNS_PER_RECIPE):
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.randomize()
			var changes: Dictionary = GSTRandomize.randomize(stack, lib, rng)
			for layer: GSTLayer in stack.layers:
				var entry: GSTManifestEntry = lib.get_entry(layer.entry)
				if entry == null or entry.params.is_empty():
					assert_false(changes.has(layer.id), "%s layer %s (%s, no params) has no randomize entry" % [path, String(layer.id), layer.entry])
					continue
				assert_true(changes.has(layer.id), "%s layer %s (%s) has a randomize entry" % [path, String(layer.id), layer.entry])
				var layer_changes: Dictionary = changes.get(layer.id, {})
				for param: Dictionary in entry.params:
					var param_name: String = String(param["name"])
					assert_true(layer_changes.has(param_name), "%s layer %s param %s was randomized" % [path, String(layer.id), param_name])
					checked_values += 1
					_assert_in_range(path, layer.entry, param, layer_changes.get(param_name))

	assert_true(checked_values > 0, "at least one param value was checked across %d recipes x %d runs" % [recipe_paths.size(), RUNS_PER_RECIPE])


func _assert_in_range(path: String, entry_id: String, param: Dictionary, value: Variant) -> void:
	var param_type: String = String(param["type"])
	var param_name: String = String(param["name"])
	var label: String = "%s %s.%s" % [path, entry_id, param_name]
	match param_type:
		"int":
			assert_true(typeof(value) == TYPE_INT, "%s value %s is int" % [label, value])
			assert_true(int(value) >= int(param["min"]) and int(value) <= int(param["max"]), "%s value %s inside [%s, %s]" % [label, value, param["min"], param["max"]])
		"float":
			assert_true(typeof(value) == TYPE_FLOAT, "%s value %s is float" % [label, value])
			assert_true(float(value) >= float(param["min"]) and float(value) <= float(param["max"]), "%s value %s inside [%s, %s]" % [label, value, param["min"], param["max"]])
		"color":
			assert_true(typeof(value) == TYPE_COLOR, "%s value %s is Color" % [label, value])
			var c: Color = value
			assert_true(c.r >= 0.0 and c.r <= 1.0 and c.g >= 0.0 and c.g <= 1.0 and c.b >= 0.0 and c.b <= 1.0, "%s color %s channels inside [0, 1]" % [label, c])
			assert_eq(c.a, 1.0, "%s color alpha is 1.0" % label)
		"vec2":
			assert_true(typeof(value) == TYPE_VECTOR2, "%s value %s is Vector2" % [label, value])
			var v2: Vector2 = value
			var min2: float = float(param.get("min", 0.0))
			var max2: float = float(param.get("max", 1.0))
			assert_true(v2.x >= min2 and v2.x <= max2 and v2.y >= min2 and v2.y <= max2, "%s vec2 %s inside [%s, %s]" % [label, v2, min2, max2])
		"vec3":
			assert_true(typeof(value) == TYPE_VECTOR3, "%s value %s is Vector3" % [label, value])
			var v3: Vector3 = value
			var min3: float = float(param.get("min", 0.0))
			var max3: float = float(param.get("max", 1.0))
			assert_true(v3.x >= min3 and v3.x <= max3 and v3.y >= min3 and v3.y <= max3 and v3.z >= min3 and v3.z <= max3, "%s vec3 %s inside [%s, %s]" % [label, v3, min3, max3])
		_:
			assert_true(false, "%s has an unknown param type '%s'" % [label, param_type])


## Two RandomNumberGenerators seeded identically produce byte-identical
## change sets on the same stack.
func test_same_seed_reproduces_same_values() -> void:
	var lib: GSTLibrary = _scanned_library()
	var load_a: Dictionary = GSTStackIO.load("%s/fire.tres" % RECIPES_DIR, lib)
	var load_b: Dictionary = GSTStackIO.load("%s/fire.tres" % RECIPES_DIR, lib)
	assert_true(load_a["ok"] and load_b["ok"], "fire.tres loads twice independently")
	if not (load_a["ok"] and load_b["ok"]):
		return

	var rng_a: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_a.seed = 424242
	var rng_b: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_b.seed = 424242

	var changes_a: Dictionary = GSTRandomize.randomize(load_a["stack"], lib, rng_a)
	var changes_b: Dictionary = GSTRandomize.randomize(load_b["stack"], lib, rng_b)
	assert_eq(changes_a.size(), changes_b.size(), "same seed produces the same number of changed layers")
	for layer_id: Variant in changes_a.keys():
		assert_true(changes_b.has(layer_id), "layer %s present in both change sets" % String(layer_id))
		var params_a: Dictionary = changes_a[layer_id]
		var params_b: Dictionary = changes_b.get(layer_id, {})
		for param_name: Variant in params_a.keys():
			assert_eq(params_b.get(param_name), params_a[param_name], "layer %s param %s reproduces under the same seed" % [String(layer_id), param_name])


## A stack whose only layer's entry declares no params (source/texture)
## yields an empty change set: nothing to randomize, nothing returned.
func test_stack_with_no_params_yields_empty_change_set() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var changes: Dictionary = GSTRandomize.randomize(stack, lib, rng)
	assert_true(changes.is_empty(), "a stack with only a param-less layer yields an empty change set (got %s)" % changes)


## GSTRandomize.apply writes every changed value through the matching
## layer's own Object.set() (so GSTLayer._set runs, docs/PLAN.md Phase 8 fix
## pass 2, item 1), the same requirement every real caller already meets:
## gst_main_panel.gd only ever calls apply() on a live panel stack, whose
## layers always carry a resolved manifest (set at add time by
## gst_undo.gd's add_layer, or at load time by gst_stack_io.gd's load), so
## the manifest is resolved here too before calling apply().
func test_apply_writes_every_changed_value_onto_the_layer() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	layer.manifest = lib.get_entry("generative/fbm")
	var changes: Dictionary = {layer.id: {"octaves": 7, "gain": 0.65}}
	GSTRandomize.apply(stack, changes)
	assert_eq(layer.params.get("octaves"), 7, "octaves written onto the layer")
	assert_eq(layer.params.get("gain"), 0.65, "gain written onto the layer")
