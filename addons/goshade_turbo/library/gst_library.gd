@tool
class_name GSTLibrary
extends RefCounted

## Scans addons/goshade_turbo/library/**/*.tres, loads each as a
## GSTManifestEntry, and indexes it by manifest id. Refuses a duplicate
## `function`: add_entry() returns false and records the collision in
## duplicate_functions. It never raises, so the test runner sees no error line.
## Design: docs/DESIGN.md, Manifest entry and Codegen rules.

const DEFAULT_ROOT: String = "res://addons/goshade_turbo/library"

## Manifest id (String) -> GSTManifestEntry.
var entries: Dictionary = {}
## GLSL function name (String) -> manifest id (String) that claimed it first.
var _function_to_id: Dictionary = {}
## Function names that were seen more than once during a scan.
var duplicate_functions: Array[String] = []


func scan(root: String = DEFAULT_ROOT) -> void:
	entries.clear()
	_function_to_id.clear()
	duplicate_functions.clear()
	_scan_dir(root)


func _scan_dir(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_error("GSTLibrary: cannot open directory %s" % path)
		return
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while entry_name != "":
		if not entry_name.begins_with("."):
			var full_path: String = path.path_join(entry_name)
			if dir.current_is_dir():
				_scan_dir(full_path)
			elif entry_name.ends_with(".tres"):
				_load_entry(full_path)
		entry_name = dir.get_next()
	dir.list_dir_end()


func _load_entry(path: String) -> void:
	var res: Resource = ResourceLoader.load(path)
	if res is GSTManifestEntry:
		add_entry(res as GSTManifestEntry)
	else:
		push_error("GSTLibrary: %s did not load as GSTManifestEntry" % path)


## Indexes one entry. Returns false and records the collision when
## `function` was already claimed by any earlier entry. Never raises
## an engine-level error: a duplicate function name is a data problem the
## caller (and the test suite) must be able to observe via the return value
## and `duplicate_functions`, not an uncaught SCRIPT ERROR that no GDScript
## hook can catch.
func add_entry(entry: GSTManifestEntry) -> bool:
	if _function_to_id.has(entry.function):
		duplicate_functions.append(entry.function)
		return false
	entries[entry.id] = entry
	_function_to_id[entry.function] = entry.id
	return true


func has_duplicate_function(function_name: String) -> bool:
	return duplicate_functions.has(function_name)


func get_entry(id: String) -> GSTManifestEntry:
	return entries.get(id, null)


func size() -> int:
	return entries.size()
