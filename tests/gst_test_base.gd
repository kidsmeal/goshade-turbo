class_name GSTTestBase
extends RefCounted

## Minimal assertion base for the headless test suite. Every assertion
## records rather than halts, so one test file reports every failure in a
## run instead of stopping at the first. gst_test_runner.gd reads
## `failures` after calling each `test_*` method.

var failures: Array[String] = []


func assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append("assert_true failed: %s" % message)


func assert_false(value: bool, message: String) -> void:
	if value:
		failures.append("assert_false failed: %s" % message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("assert_eq failed: %s (expected %s, got %s)" % [message, str(expected), str(actual)])


func assert_null(value: Variant, message: String) -> void:
	if value != null:
		failures.append("assert_null failed: %s (got %s)" % [message, str(value)])


func assert_not_null(value: Variant, message: String) -> void:
	if value == null:
		failures.append("assert_not_null failed: %s" % message)


func has_failures() -> bool:
	return not failures.is_empty()


## Every persisted GSTStack field: coord_space, output_color, output_alpha,
## next_id, layer count, then layer order and content via _compare_layers.
## Returns early on a layer-count mismatch: a per-index layer comparison is
## meaningless once the arrays are different lengths. Shared by
## tests/test_stack_io.gd and tests/test_recipe_roundtrip.gd (docs/PLAN.md
## Phase 7 Build: "reuse the comparison helper from tests/test_stack_io.gd by
## moving it into tests/gst_test_base.gd").
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
