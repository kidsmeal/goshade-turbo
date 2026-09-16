@tool
class_name GSTDocumentRecovery
extends RefCounted

## Project-local shutdown recovery storage. Stateless static utility:
## gst_main_panel.gd save_external_data() calls write_record() for every
## untitled or failed-path dirty document during a confirmed quit, and
## load_recovery_records() calls load_all() at startup to reopen them.
##
## Storage shape under `dir` (gst_main_panel.gd get_recovery_dir():
## EditorInterface.get_editor_paths().get_project_settings_dir()
## /goshade_turbo/recovery, or an isolated override under test; never a
## user's own stack/export path): one self-contained `<record_id>.tres`
## GSTStack per dirty document (the GSTStackIO schema), plus one shared
## `index.json` listing every record's identity, originating save path, and
## recipe/import origin. Invalid or unknown recovery metadata stays on disk
## for diagnosis; nothing here may silently delete it.


const METADATA_FILE: String = "index.json"
const SCHEMA_VERSION: int = 1


## Recovery directory under the editor project-settings base directory.
static func recovery_dir(settings_dir: String) -> String:
	return settings_dir.path_join("goshade_turbo").path_join("recovery")


## Writes one self-contained recovery stack plus its metadata entry under
## `dir`. A non-empty, already-indexed `record_id` overwrites that record in
## place. The stack write and the metadata write are checked separately: a
## metadata-write failure after a successful stack write reports `ok=false`,
## so the caller never marks that record recovered and load_all() never
## resolves it. An already-indexed `record_id` has its metadata validated
## before its stack file is overwritten; an invalid existing record
## (unsupported version, or id/stack_file mismatch) is rejected with
## `ok=false` and neither file is touched. `quarantined_path` is non-empty
## only when this call quarantined an unreadable `index.json`; the caller
## must report it, since stack files that index referenced are now unindexed.
## `{ok, record_id, stack_path, reason, quarantined_path}`.
static func write_record(dir: String, stack: GSTStack, original_path: String, recipe_open: bool, recipe_name: String, reopened_import: bool, save_failed: bool, record_id: String = "") -> Dictionary:
	# Validated before ResourceSaver.save() and make_dir_recursive_absolute():
	# an unsafe record_id must never reach a derived stack_file (an id of
	# "../victim" would resolve "../victim.tres" outside `dir`).
	if not record_id.is_empty() and not _is_valid_record_id(record_id, "%s.tres" % record_id):
		return {"ok": false, "record_id": record_id, "stack_path": dir, "reason": "recovery record id '%s' is unsafe and was rejected before writing anything to %s" % [record_id, _index_path(dir)], "quarantined_path": ""}
	var id: String = record_id if not record_id.is_empty() else _generate_record_id()
	var stack_file: String = "%s.tres" % id
	var stack_path: String = dir.path_join(stack_file)
	var existing_index_result: Dictionary = {}
	if not record_id.is_empty():
		existing_index_result = _load_index(dir)
		if not bool(existing_index_result.get("ok", false)):
			return {"ok": false, "record_id": id, "stack_path": stack_path, "reason": "cannot update existing recovery record '%s' against %s: %s" % [record_id, _index_path(dir), existing_index_result.get("reason", "")], "quarantined_path": ""}
		var existing_validation: Dictionary = (existing_index_result.get("by_id", {}) as Dictionary).get(record_id, {})
		if not existing_validation.is_empty() and not bool(existing_validation.get("ok", false)):
			return {"ok": false, "record_id": id, "stack_path": stack_path, "reason": "cannot update existing recovery record '%s' indexed in %s: %s" % [record_id, _index_path(dir), existing_validation.get("reason", "")], "quarantined_path": ""}
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(dir)
	if dir_error != OK:
		return {"ok": false, "record_id": id, "stack_path": stack_path, "reason": "failed to create recovery directory %s: %s" % [dir, error_string(dir_error)], "quarantined_path": ""}
	var stack_error: Error = ResourceSaver.save(stack, stack_path)
	if stack_error != OK:
		return {"ok": false, "record_id": id, "stack_path": stack_path, "reason": "failed to save recovery stack to %s: %s" % [stack_path, error_string(stack_error)], "quarantined_path": ""}
	# Reuses `existing_index_result` (ok=true whenever record_id is non-empty)
	# so this write is judged against the snapshot validated above.
	var index_result: Dictionary = existing_index_result if not record_id.is_empty() else _load_index(dir)
	# A quarantine here is otherwise silent: stack files the quarantined index
	# referenced become unreported orphans once this call reports ok=true.
	# Carry the path through so the caller reports it; load_all's directory
	# scan rediscovers the file on every later startup until it is removed.
	var quarantined_path: String = ""
	if not bool(index_result.get("ok", false)):
		var quarantine_result: Dictionary = _quarantine_unreadable_index(dir)
		if not bool(quarantine_result.get("ok", false)):
			return {"ok": false, "record_id": id, "stack_path": stack_path, "reason": String(index_result.get("reason", "")), "quarantined_path": ""}
		quarantined_path = String(quarantine_result.get("path", ""))
		index_result = {"ok": true, "index": {"version": SCHEMA_VERSION, "records": []}, "reason": ""}
	var index: Dictionary = index_result["index"] as Dictionary
	var records: Array = index.get("records", []) as Array
	var existing_index: int = _find_record_index(records, id)
	var entry: Dictionary = {
		"id": id,
		"version": SCHEMA_VERSION,
		"stack_file": stack_file,
		"original_path": original_path,
		"recipe_open": recipe_open,
		"recipe_name": recipe_name,
		"reopened_import": reopened_import,
		"save_failed": save_failed,
		"created_unix": Time.get_unix_time_from_system(),
	}
	if existing_index == -1:
		records.append(entry)
	else:
		records[existing_index] = entry
	index["version"] = SCHEMA_VERSION
	index["records"] = records
	if not _write_index(dir, index):
		return {"ok": false, "record_id": id, "stack_path": stack_path, "reason": "failed to write recovery metadata to %s" % _index_path(dir), "quarantined_path": quarantined_path}
	return {"ok": true, "record_id": id, "stack_path": stack_path, "reason": "", "quarantined_path": quarantined_path}


## Removes record_id's stack file and metadata entry. A no-op (`ok=true`)
## when record_id is empty or absent from the index. Never touches another
## record's files. A failed stack deletion returns before the index is
## touched, so the record stays indexed for retry. A failed metadata write
## after a successful deletion leaves index.json byte-identical (_write_index
## never touches it on failure), so the record stays indexed with its stack
## file gone. Never push_errors internally; reporting is the caller's. A
## stack path replaced by a directory counts as present
## (`FileAccess.file_exists()` reads `false` against a directory), so it
## reaches `DirAccess.remove_absolute`'s failure instead of bypassing it.
## `{ok, reason}`: `reason` is "" whenever `ok` is true.
static func remove_record(dir: String, record_id: String) -> Dictionary:
	if record_id.is_empty():
		return {"ok": true, "reason": ""}
	var index_result: Dictionary = _load_index(dir)
	if not bool(index_result.get("ok", false)):
		return {"ok": false, "reason": "could not remove recovery record %s: %s" % [record_id, index_result.get("reason", "")]}
	var validation: Dictionary = (index_result.get("by_id", {}) as Dictionary).get(record_id, {})
	if validation.is_empty():
		return {"ok": true, "reason": ""}
	if not bool(validation.get("ok", false)):
		return {"ok": false, "reason": "could not remove recovery record %s: %s" % [record_id, validation.get("reason", "")]}
	var stack_path: String = String(validation["stack_path"])
	if FileAccess.file_exists(stack_path) or DirAccess.dir_exists_absolute(stack_path):
		var remove_error: Error = DirAccess.remove_absolute(stack_path)
		if remove_error != OK:
			return {"ok": false, "reason": "failed to delete recovery stack %s: %s" % [stack_path, error_string(remove_error)]}
	var index: Dictionary = index_result["index"] as Dictionary
	var records: Array = index.get("records", []) as Array
	var existing_index: int = _find_record_index(records, record_id)
	if existing_index == -1:
		return {"ok": true, "reason": ""}
	records.remove_at(existing_index)
	index["records"] = records
	if not _write_index(dir, index):
		return {"ok": false, "reason": "deleted recovery stack %s but failed to write updated recovery metadata to %s; recovery record %s is now a dangling index entry until this succeeds" % [stack_path, _index_path(dir), record_id]}
	return {"ok": true, "reason": ""}


## Loads every indexed record's stack. An entry whose stack cannot be
## resolved (missing/corrupt .tres, or a malformed entry missing id/stack_file)
## is reported in `failures`; the index is never rewritten here, so a
## transient read failure can resolve on a later attempt. An unparseable
## index.json (malformed JSON, non-Dictionary root, non-Array "records") is
## reported the same way, naming _index_path(dir), never treated as empty.
## Also reports every `index.json.unreadable-*` file in `dir` on every call:
## the quarantined file and any stack files its lost entries referenced stay
## on disk until a human removes or inspects them. `{records:
## Array[Dictionary] (each metadata entry plus "stack": GSTStack), failures:
## Array[Dictionary] {id, path, reason}}`.
static func load_all(dir: String, library: GSTLibrary) -> Dictionary:
	var index_result: Dictionary = _load_index(dir)
	var loaded: Array[Dictionary] = []
	var failures: Array[Dictionary] = []
	for quarantined_path: String in _find_quarantined_indexes(dir):
		failures.append({"id": "", "path": quarantined_path, "reason": "quarantined recovery index (unreadable when written); any recovery records it referenced are no longer indexed and must be recovered manually"})
	if not bool(index_result.get("ok", false)):
		failures.append({"id": "", "path": _index_path(dir), "reason": String(index_result.get("reason", ""))})
		return {"records": loaded, "failures": failures}
	for raw_validation: Variant in (index_result.get("records", []) as Array):
		var validation: Dictionary = raw_validation as Dictionary
		if not bool(validation.get("ok", false)):
			failures.append({"id": String(validation.get("id", "")), "path": String(validation.get("stack_path", dir)), "reason": String(validation.get("reason", ""))})
			continue
		var id: String = String(validation["id"])
		var stack_path: String = String(validation["stack_path"])
		var load_result: Dictionary = GSTStackIO.load(stack_path, library)
		if not bool(load_result.get("ok", false)):
			failures.append({"id": id, "path": stack_path, "reason": String(load_result.get("reason", ""))})
			continue
		var merged: Dictionary = (validation.get("entry", {}) as Dictionary).duplicate()
		merged["stack"] = load_result["stack"]
		loaded.append(merged)
	return {"records": loaded, "failures": failures}


static func _index_path(dir: String) -> String:
	return dir.path_join(METADATA_FILE)


## Reads dir's index.json, distinguishing three states. `present=false`
## (`ok=true`, a fresh empty index) only when `_index_path(dir)` does not
## exist. `present=true, ok=false` when the path exists but cannot be
## resolved: unopenable (a locked file, or a directory of the same name;
## `FileAccess.open` returns null for both and `FileAccess.file_exists()`
## returns `false` for a directory, so `DirAccess.dir_exists_absolute()` is
## checked too), malformed JSON, a non-Dictionary root, a non-Array "records"
## field, or an unsupported version; `reason` names `_index_path(dir)`. A
## caller must never treat this case as the first, which would discard what
## the file holds. `present=true, ok=true` once the file parsed into a
## supported-version `{version, records}` shape. Every record is run through
## `_validate_record` here: `records` holds each `{ok, id, stack_path,
## reason}` result plus an `entry` key with the raw Dictionary, in
## `index["records"]` order; `by_id` holds the same results keyed by `id`.
## write_record, load_all, and remove_record all judge validity through this
## one path. Uses the instance JSON API (as gst_header.gd parse() does) so a
## malformed file never prints an engine ERROR: line. `{ok, present, index:
## Dictionary, records: Array, by_id: Dictionary, reason}`.
static func _load_index(dir: String) -> Dictionary:
	var path: String = _index_path(dir)
	var present: bool = FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)
	if not present:
		return {"ok": true, "present": false, "index": {"version": SCHEMA_VERSION, "records": []}, "records": [], "by_id": {}, "reason": ""}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "present": true, "index": {}, "records": [], "by_id": {}, "reason": "recovery index at %s could not be opened: %s" % [path, error_string(FileAccess.get_open_error())]}
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(text) != OK or not (json.get_data() is Dictionary):
		return {"ok": false, "present": true, "index": {}, "records": [], "by_id": {}, "reason": "recovery index at %s is not valid JSON" % path}
	var parsed: Dictionary = json.get_data() as Dictionary
	if not (parsed.get("records", []) is Array):
		return {"ok": false, "present": true, "index": {}, "records": [], "by_id": {}, "reason": "recovery index at %s has a non-array \"records\" field" % path}
	if not _is_supported_version(parsed.get("version")):
		return {"ok": false, "present": true, "index": {}, "records": [], "by_id": {}, "reason": "recovery index at %s has an unsupported or missing version %s" % [path, parsed.get("version")]}
	var validated: Array[Dictionary] = []
	var by_id: Dictionary = {}
	for raw: Variant in (parsed["records"] as Array):
		if not (raw is Dictionary):
			var malformed: Dictionary = {"ok": false, "id": "", "stack_path": dir, "reason": "malformed recovery index entry (not a Dictionary)", "entry": {}}
			validated.append(malformed)
			continue
		var entry: Dictionary = raw as Dictionary
		var validation: Dictionary = _validate_record(entry, dir)
		validation["entry"] = entry
		validated.append(validation)
		if not String(validation.get("id", "")).is_empty():
			by_id[validation["id"]] = validation
	return {"ok": true, "present": true, "index": parsed, "records": validated, "by_id": by_id, "reason": ""}


## `true` only for SCHEMA_VERSION. An unknown or missing version is routed by
## `_load_index` through the unreadable-index path, so `write_record`
## quarantines it (rename, never overwrite) and `load_all` reports it as a
## failure. `int` and `float` are compared separately: `int()` truncates, so
## a `float` `1.5` would pass `int(value) == SCHEMA_VERSION`. JSON's numeric
## `1.0` (always a `float` from Godot's `JSON.parse`) is compared against
## `float(SCHEMA_VERSION)`; both sides are whole numbers exactly representable
## in a double.
static func _is_supported_version(value: Variant) -> bool:
	if value is int:
		return (value as int) == SCHEMA_VERSION
	if value is float:
		return (value as float) == float(SCHEMA_VERSION)
	return false


## Validates a record id against the same bare-filename rule
## `_is_safe_stack_filename` applies to `stack_file`, and requires
## `stack_file`'s basename (without `.tres`) to equal `id`. `write_record`
## derives a fresh `stack_file` as `"%s.tres" % id` whenever an existing id is
## passed back, so an id containing `..` or a path separator resolves outside
## `dir` even when the indexed `stack_file` field was safe.
static func _is_valid_record_id(id: String, stack_file: String) -> bool:
	if id.is_empty() or id.contains("/") or id.contains("\\") or id.contains(".."):
		return false
	return id == stack_file.get_basename()


## Renames dir's unparseable index.json out of the way instead of letting
## write_record overwrite it with a fresh empty one; truncating it during a
## confirmed-shutdown write is the window that produces an unreadable index
## for the next load_all(). A no-op returning true when no index.json is
## present. `ok=false` only if the rename fails, in which case write_record
## reports the original unreadable-index reason and never touches the file.
## `path` is the quarantined file's path, or "" when nothing was quarantined.
## `{ok, path}`.
static func _quarantine_unreadable_index(dir: String) -> Dictionary:
	var path: String = _index_path(dir)
	if not FileAccess.file_exists(path):
		return {"ok": true, "path": ""}
	var quarantined_path: String = "%s.unreadable-%d" % [path, Time.get_unix_time_from_system()]
	if DirAccess.rename_absolute(path, quarantined_path) != OK:
		return {"ok": false, "path": ""}
	return {"ok": true, "path": quarantined_path}


## Every `index.json.unreadable-*` file directly under `dir`, sorted. Empty
## when `dir` does not exist.
static func _find_quarantined_indexes(dir: String) -> Array[String]:
	var found: Array[String] = []
	var handle: DirAccess = DirAccess.open(dir)
	if handle == null:
		return found
	var prefix: String = "%s.unreadable-" % METADATA_FILE
	handle.list_dir_begin()
	var file_name: String = handle.get_next()
	while not file_name.is_empty():
		if not handle.current_is_dir() and file_name.begins_with(prefix):
			found.append(dir.path_join(file_name))
		file_name = handle.get_next()
	handle.list_dir_end()
	found.sort()
	return found


## Writes through a temp file then renames it over the real index path, so a
## write that fails partway (temp open, `store_string`, or the rename) never
## touches the existing index.json. `DirAccess.rename_absolute` overwrites an
## existing destination on Windows/Godot 4.4 (verified).
static func _write_index(dir: String, index: Dictionary) -> bool:
	var path: String = _index_path(dir)
	var temp_path: String = "%s.tmp" % path
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(index))
	var store_error: Error = file.get_error()
	file.close()
	if store_error != OK:
		DirAccess.remove_absolute(temp_path)
		return false
	if DirAccess.rename_absolute(temp_path, path) != OK:
		DirAccess.remove_absolute(temp_path)
		return false
	return true


## Validates one index entry's identity, version, stack-filename containment,
## and required field types before `load_all` loads its stack or
## `remove_record` deletes it. `{ok, id, stack_path, reason}`: `id` and
## `stack_path` are the best values available for reporting even on failure,
## but `stack_path` only resolves under `dir` once `stack_file` has passed
## the bare-filename check, so an invalid entry never yields a path outside
## the recovery directory.
static func _validate_record(entry: Dictionary, dir: String) -> Dictionary:
	var id_raw: Variant = entry.get("id")
	if not (id_raw is String) or (id_raw as String).is_empty():
		return {"ok": false, "id": "", "stack_path": dir, "reason": "recovery index entry is missing its own id or has a non-string id"}
	var id: String = id_raw
	if not _is_supported_version(entry.get("version")):
		return {"ok": false, "id": id, "stack_path": dir, "reason": "recovery index entry %s has an unsupported or missing version %s" % [id, entry.get("version")]}
	var stack_file_raw: Variant = entry.get("stack_file")
	if not (stack_file_raw is String) or (stack_file_raw as String).is_empty():
		return {"ok": false, "id": id, "stack_path": dir, "reason": "recovery index entry %s is missing its own stack_file or has a non-string stack_file" % id}
	var stack_file: String = stack_file_raw
	if not _is_safe_stack_filename(stack_file):
		return {"ok": false, "id": id, "stack_path": dir, "reason": "recovery index entry %s has an unsafe stack_file '%s' (must be a bare filename)" % [id, stack_file]}
	var stack_path: String = dir.path_join(stack_file)
	if not _path_stays_under(dir, stack_path):
		return {"ok": false, "id": id, "stack_path": dir, "reason": "recovery index entry %s's stack_file resolves outside the recovery directory" % id}
	# An id that disagrees with stack_file's basename is inconsistent even when
	# each field passed alone: gst_main_panel.gd _recover_document carries this
	# id forward as write_record's existing id on a later shutdown, which
	# derives a fresh stack_file from the id alone.
	if not _is_valid_record_id(id, stack_file):
		return {"ok": false, "id": id, "stack_path": stack_path, "reason": "recovery index entry's id '%s' does not match its own stack_file '%s'; rejecting as an inconsistent record" % [id, stack_file]}
	if not (entry.get("original_path", "") is String):
		return {"ok": false, "id": id, "stack_path": stack_path, "reason": "recovery index entry %s has a non-string original_path" % id}
	if not (entry.get("recipe_name", "") is String):
		return {"ok": false, "id": id, "stack_path": stack_path, "reason": "recovery index entry %s has a non-string recipe_name" % id}
	if not (entry.get("recipe_open", false) is bool):
		return {"ok": false, "id": id, "stack_path": stack_path, "reason": "recovery index entry %s has a non-bool recipe_open" % id}
	if not (entry.get("reopened_import", false) is bool):
		return {"ok": false, "id": id, "stack_path": stack_path, "reason": "recovery index entry %s has a non-bool reopened_import" % id}
	if not (entry.get("save_failed", false) is bool):
		return {"ok": false, "id": id, "stack_path": stack_path, "reason": "recovery index entry %s has a non-bool save_failed" % id}
	return {"ok": true, "id": id, "stack_path": stack_path, "reason": ""}


## A bare filename only: no path separator, no `..`. `stack_file` reaches
## `dir.path_join()` and `DirAccess.remove_absolute()`, so an entry failing
## this must never be joined into a path.
static func _is_safe_stack_filename(stack_file: String) -> bool:
	return not (stack_file.is_empty() or stack_file.contains("/") or stack_file.contains("\\") or stack_file.contains(".."))


## Defense in depth behind `_is_safe_stack_filename`: `candidate` (already
## `dir.path_join()`-ed) must resolve under `dir` once both are normalized.
static func _path_stays_under(dir: String, candidate: String) -> bool:
	var normalized_dir: String = dir.simplify_path()
	if not normalized_dir.ends_with("/"):
		normalized_dir += "/"
	return candidate.simplify_path().begins_with(normalized_dir)


static func _find_record_index(records: Array, record_id: String) -> int:
	for i: int in range(records.size()):
		var raw: Variant = records[i]
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == record_id:
			return i
	return -1


static func _generate_record_id() -> String:
	return "%d_%d" % [Time.get_ticks_usec(), randi()]
