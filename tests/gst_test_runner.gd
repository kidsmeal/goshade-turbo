extends SceneTree

## Inner headless test runner. Discovers tests/test_*.gd, runs every test_*
## method on each, and quits 1 if gst_test_base.gd recorded any assertion
## failure. Always run through the tests/run_codegen_tests.gd wrapper, never
## invoked directly as the named verification command: GDScript exposes no
## hook that catches an engine-level SCRIPT ERROR (an assert() failure or a
## runtime error the engine itself prints), so an aborted test method still
## reports this script's own exit 0 here. The wrapper inspects this script's
## captured stdout/stderr for SCRIPT ERROR / ERROR: / Parse error and fails
## the run even when this inner runner does not observe the abort.
##
## Prerequisite, once after clone and after adding any new class_name
## script: `godot --headless --path . --import`. Without it, class_name
## globals fail with a Parse error in this -s run.

const TEST_DIR: String = "res://tests"


func _initialize() -> void:
	var test_paths: Array[String] = _discover_test_files()
	var file_count: int = 0
	var method_count: int = 0
	var all_failures: Array[String] = []

	for path: String in test_paths:
		file_count += 1
		var script: Script = load(path) as Script
		if script == null:
			all_failures.append("%s: failed to load as a Script" % path)
			continue
		var instance: Object = script.new()
		var method_names: Array[String] = _test_method_names(instance)
		for method_name: String in method_names:
			method_count += 1
			instance.call(method_name)
		var failures: Array = instance.get("failures")
		for failure: Variant in failures:
			all_failures.append("%s: %s" % [path, str(failure)])

	print("GST tests: %d file(s), %d test method(s), %d failure(s)" % [file_count, method_count, all_failures.size()])
	for failure: String in all_failures:
		print("  FAIL " + failure)

	if all_failures.is_empty():
		quit(0)
	else:
		quit(1)


func _discover_test_files() -> Array[String]:
	var result: Array[String] = []
	var dir: DirAccess = DirAccess.open(TEST_DIR)
	if dir == null:
		push_error("gst_test_runner: cannot open %s" % TEST_DIR)
		return result
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and entry_name.begins_with("test_") and entry_name.ends_with(".gd"):
			result.append(TEST_DIR.path_join(entry_name))
		entry_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


func _test_method_names(instance: Object) -> Array[String]:
	var names: Array[String] = []
	for method_info: Dictionary in instance.get_method_list():
		var method_name: String = method_info["name"]
		if method_name.begins_with("test_"):
			names.append(method_name)
	names.sort()
	return names
