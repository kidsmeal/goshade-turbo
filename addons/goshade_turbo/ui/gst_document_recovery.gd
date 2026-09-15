@tool
class_name GSTDocumentRecovery
extends RefCounted

## Project-local shutdown recovery storage (phase 7,
## docs/SHADER_TABS_reviewed-plan.md; decision 10,
## docs/SHADER_TABS_reviewed.md). Stateless static utility, matching
## gst_stack_io.gd's own style: gst_main_panel.gd's save_external_data()
## calls write_record() for every untitled or failed-path dirty document
## during a confirmed quit, and load_recovery_records() calls load_all() at
## startup to reopen them before the normal entry surface.
##
## Storage shape under `dir` (gst_main_panel.gd's get_recovery_dir(), which
## resolves to EditorInterface.get_editor_paths().get_project_settings_dir()
## /goshade_turbo/recovery in production, or an isolated override during
## verification -- never a user's own stack/export path, per decision 10):
## one self-contained `<record_id>.tres` GSTStack per dirty document (the
## same schema GSTStackIO already saves/loads, so a recovered stack round-
## trips through the real editor exactly like any other .tres), plus one
## shared `index.json` metadata file listing every record's identity,
## originating save path, and recipe/import origin. Invalid or unknown
## recovery metadata stays on disk for diagnosis; nothing here may silently
## delete it.


const METADATA_FILE: String = "index.json"
const SCHEMA_VERSION: int = 1


## Directory a document's recovery record lives under, for a given editor
## project-settings base directory.
static func recovery_dir(settings_dir: String) -> String:
	return settings_dir.path_join("goshade_turbo").path_join("recovery")


## Writes one self-contained recovery stack plus its metadata entry under
## `dir`. When `record_id` is non-empty and already indexed, overwrites that
## same record in place instead of appending a new one. The stack write and
## the metadata write are checked separately before reporting success: a
## metadata-write failure after a successful stack write still reports
## `ok=false`, so the caller never marks that record recovered, and load_all()
## below can never resolve an entry for it. When `record_id` already names an
## indexed record, that record's own metadata is read and validated *before*
## its stack file is overwritten -- an invalid existing record (unsupported
## version, or an id/stack_file identity that no longer agrees) is rejected
## with `ok=false` and neither its stack file nor its index entry is touched.
## `quarantined_path` is non-empty only when this call itself just
## quarantined an unreadable `index.json`: the caller must report it, since
## any stack files that quarantined index used to reference are now
## unindexed until reviewed. `{ok, record_id, stack_path, reason,
## quarantined_path}`.
static func write_record(dir: String, stack: GSTStack, original_path: String, recipe_open: bool, recipe_name: String, reopened_import: bool, save_failed: bool, record_id: String = "") -> Dictionary:
	# Validated before anything else -- including ResourceSaver.save() and
	# DirAccess.make_dir_recursive_absolute() below -- because an unsafe
	# record_id must never reach a derived stack_file (an id of "../victim"
	# would otherwise resolve "../victim.tres" outside `dir`).
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
	# Reuses `existing_index_result` (already confirmed ok=true above whenever
	# record_id is non-empty) instead of reading the index a second time, so
	# this write is judged against the same snapshot its own validation above
	# just checked. A fresh record (record_id empty) still reads fresh here.
	var index_result: Dictionary = existing_index_result if not record_id.is_empty() else _load_index(dir)
	# A quarantine here would otherwise be silent: any stack files the
	# quarantined index used to reference become unreported orphans the
	# moment this call reports ok=true. Carry the quarantined path through so
	# the caller can report it at write time; load_all's own directory scan
	# rediscovers the same file on every later startup until it is removed.
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


## Removes record_id's own stack file and metadata entry. A no-op (`ok=true`)
## when record_id is empty or already absent from the index. Never touches
## any other record's own files. Both the stack deletion and the metadata
## rewrite are checked before this call claims success: a failed stack
## deletion returns before the index is ever touched, so that record stays
## indexed with its file untouched, ready for a caller to retry; a failed
## metadata write after a successful deletion leaves the real index.json
## byte-identical to its prior content (_write_index's own
## write-through-a-temp-file-then-rename never touches it on failure), so the
## record stays indexed even though its own stack file is already gone.
## Reporting is left to this call's own caller, matching write_record's own
## convention of never push_error-ing internally. A stack path replaced by a
## directory counts as present too (`FileAccess.file_exists()` alone reads
## `false` against a directory), so that shape reaches
## `DirAccess.remove_absolute`'s own failure instead of bypassing it.
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


## Loads every indexed record's own stack. An entry whose stack cannot be
## resolved (missing/corrupt .tres, or a malformed index entry missing its
## own id/stack_file) is reported in `failures` instead of raising or being
## silently dropped; the index itself is never rewritten here, so a
## transient read failure (e.g. a locked file) can still resolve on a later
## attempt. An unparseable index.json itself (malformed JSON, a
## non-Dictionary root, or a non-Array "records" field) is reported the same
## way, naming _index_path(dir) -- never silently treated as an
## empty/absent index. Also reports every `index.json.unreadable-*` file
## already present in `dir`: a prior write_record() call may have
## quarantined an unreadable index and already reported it once at that
## write time, but the quarantined file itself, and any stack files its own
## lost index entries used to reference, stay on disk and orphaned -- this
## makes every later load_all() call keep reporting it until a human
## actually removes or inspects it. `{records: Array[Dictionary] (each the
## original metadata entry plus its own "stack": GSTStack), failures:
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


## Reads dir's own index.json, distinguishing three states no caller may
## conflate. `present=false` (`ok=true`, a fresh empty index) only when
## `_index_path(dir)` confirmedly does not exist at all: nothing has ever
## been written here. `present=true, ok=false` when the path exists but this
## engine cannot resolve it -- unopenable (a locked file, or a directory
## sharing its exact name: `FileAccess.open` returns null identically for
## both, so `FileAccess.file_exists()` alone is not enough to detect
## presence either -- it also returns `false` for a directory, so
## `DirAccess.dir_exists_absolute()` is checked too), malformed JSON, a
## non-Dictionary root, a non-Array "records" field, or an unsupported
## version -- `reason` always names `_index_path(dir)`. A caller must never
## treat the second case as the first, which would silently discard
## whatever the file still holds. `present=true, ok=true` once the file
## opened, parsed, and resolved into a supported-version `{version,
## records}` shape. Every record is already run through `_validate_record`
## here (`records`, an Array of that call's own `{ok, id, stack_path,
## reason}` result plus this call's own added `entry` key holding the
## original raw Dictionary, in the same order as `index["records"]`; `by_id`,
## the same results keyed by their own `id` for direct lookup) so
## write_record, load_all, and remove_record all judge one record's own
## validity and reconstruct its full field set the same way instead of
## re-reading/re-validating it three separate times. Uses the instance JSON
## API (like gst_header.gd's own parse()) so a malformed file never prints
## an engine ERROR: line on this expected-failure path. `{ok, present,
## index: Dictionary, records: Array, by_id: Dictionary, reason}`.
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


## `true` only for the one schema version this engine writes and can resolve
## records against. An unknown or missing version is never valid input:
## `_load_index` routes it through the same unreadable-index path as
## malformed JSON, so `write_record` quarantines it (rename, never overwrite)
## instead of silently replacing its version with `SCHEMA_VERSION`, and
## `load_all` reports it as a failure instead of resolving it. Compares the
## `int` and `float` cases separately rather than `int(value) == SCHEMA_VERSION`
## for both: `int()` truncates, so a `float` like `1.5` would otherwise pass
## this check for `SCHEMA_VERSION == 1`. JSON's own numeric `1.0` (a `float`,
## never an `int`, per Godot's `JSON.parse`) must still be accepted --
## compared against `float(SCHEMA_VERSION)` directly, exploiting that both
## sides are always whole numbers representable exactly in a double, so no
## fractional value can equal it.
static func _is_supported_version(value: Variant) -> bool:
	if value is int:
		return (value as int) == SCHEMA_VERSION
	if value is float:
		return (value as float) == float(SCHEMA_VERSION)
	return false


## Validates a recovery record's own id against the same bare-filename rule
## `_is_safe_stack_filename` already applies to `stack_file`, and against
## `stack_file`'s own basename. `write_record` derives a *fresh* `stack_file`
## as `"%s.tres" % id` every time an `existing_id` is passed back to it (an
## overwrite of an already-indexed record) -- so an id that itself contains
## `..` or a path separator resolves *that* derived stack_file outside `dir`
## even when the record's own previously-indexed `stack_file` field stayed a
## safe bare filename. Requires `stack_file`'s own basename (without its
## `.tres` extension) to equal `id` exactly -- the only relationship
## `write_record` ever assumes between the two.
static func _is_valid_record_id(id: String, stack_file: String) -> bool:
	if id.is_empty() or id.contains("/") or id.contains("\\") or id.contains(".."):
		return false
	return id == stack_file.get_basename()


## Renames dir's own unparseable index.json out of the way instead of
## letting write_record silently overwrite it with a fresh, empty one --
## truncating it that way during a confirmed-shutdown write is exactly the
## window that produces an unreadable index for the next load_all() to find.
## A no-op returning true when no index.json is present to quarantine.
## `ok=false` only if the rename itself fails, in which case write_record
## reports the original unreadable-index reason and never touches the file;
## `path` is the quarantined file's own path on success, or "" when nothing
## was quarantined (the no-op case). `{ok, path}`.
static func _quarantine_unreadable_index(dir: String) -> Dictionary:
	var path: String = _index_path(dir)
	if not FileAccess.file_exists(path):
		return {"ok": true, "path": ""}
	var quarantined_path: String = "%s.unreadable-%d" % [path, Time.get_unix_time_from_system()]
	if DirAccess.rename_absolute(path, quarantined_path) != OK:
		return {"ok": false, "path": ""}
	return {"ok": true, "path": quarantined_path}


## Every `index.json.unreadable-*` file currently present directly under
## `dir`, sorted for deterministic ordering. Returns an empty array when
## `dir` does not exist yet (nothing has ever been written there).
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
## write that fails partway (temp file cannot be opened, `store_string`'s own
## write fails, or the rename itself fails) never touches -- and so never
## truncates -- whatever index.json already exists at `path`. Confirmed
## directly that `DirAccess.rename_absolute` overwrites an existing
## destination file on Windows/Godot 4.4.
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


## Validates one recovery index entry's own identity, version, stack-filename
## containment, and required field types before `load_all` loads its stack or
## `remove_record` deletes it. `{ok, id, stack_path, reason}`: `id` and
## `stack_path` are always the best values available for reporting, even on
## failure -- but `stack_path` only ever resolves to a real path under `dir`
## once `stack_file` has already passed the bare-filename check below, so an
## invalid entry never hands its caller a path that could point outside the
## recovery directory.
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
	# A record whose own id does not agree with its stack_file's basename is
	# inconsistent even when each field passed its own individual check
	# above -- and, critically, that same id is exactly what a caller (gst_
	# main_panel.gd's _recover_document) carries forward as write_record's
	# own existing_id on a later shutdown, deriving a *fresh* stack_file from
	# the id alone at that point rather than reusing this entry's stack_file.
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


## A bare filename only: no path separator, no `..` anywhere in the string.
## `stack_file` reaches `dir.path_join()` and, on removal, `DirAccess.remove_
## absolute()`, so an entry that fails this must never be joined into a path
## a caller could act on.
static func _is_safe_stack_filename(stack_file: String) -> bool:
	return not (stack_file.is_empty() or stack_file.contains("/") or stack_file.contains("\\") or stack_file.contains(".."))


## Defense in depth behind `_is_safe_stack_filename`: `candidate` (already
## `dir.path_join()`-ed) must still resolve under `dir` once both are
## normalized.
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
