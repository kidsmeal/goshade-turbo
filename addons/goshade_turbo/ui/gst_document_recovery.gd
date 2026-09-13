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
## originating save path, and recipe/import origin -- kept separate from the
## stack schema itself (Cross-cutting "Serialization and recovery format":
## "Phase 7 introduces editor-local recovery metadata only... Invalid/
## unknown recovery metadata remains available for diagnosis; no migration
## may silently delete it").


const METADATA_FILE: String = "index.json"
const SCHEMA_VERSION: int = 1


## Directory a document's recovery record lives under, for a given editor
## project-settings base directory (gst_main_panel.gd's get_recovery_dir()
## supplies the real base in production; tests/gst_editor_document_recovery_smoke.gd
## supplies an isolated one).
static func recovery_dir(settings_dir: String) -> String:
	return settings_dir.path_join("goshade_turbo").path_join("recovery")


## Writes one self-contained recovery stack plus its metadata entry under
## `dir`. When `record_id` is non-empty and already indexed, overwrites that
## same record in place instead of appending a new one -- repeated shutdowns
## against the same still-dirty document (decision 10: "Repeated shutdown
## must retain recoverable content and avoid duplicate restoration of one
## record") update, rather than duplicate, its own entry. Checks the stack
## write and the metadata write separately before reporting success (Cross-
## cutting "Check every stack and metadata operation before claiming
## recovery success; a partial record cannot be treated as restored
## content"): a metadata-write failure after a successful stack write still
## reports ok=false, so the caller never marks that record recovered, and
## load_all() below can never resolve an entry for it (the metadata index is
## the only thing load_all() reads). When `record_id` already names an
## indexed record (review round 5, S1), that record's own metadata is read
## and validated *before* its stack file is overwritten -- an invalid
## existing record (unsupported version, or an id/stack_file identity that
## no longer agrees) is rejected with `ok=false` and neither its stack file
## nor its index entry is touched, matching load_all/remove_record's own
## refusal to act on the same shape of invalid record. `quarantined_path` is non-empty only
## when this call itself just quarantined an unreadable `index.json` (fix-now
## round 2, note 1): the caller must report it, since any stack files that
## quarantined index used to reference are now unindexed until reviewed --
## `_load_index`'s own not-ok/ok=true empty-index paths never set it.
## `{ok, record_id, stack_path, reason, quarantined_path}`.
static func write_record(dir: String, stack: GSTStack, original_path: String, recipe_open: bool, recipe_name: String, reopened_import: bool, save_failed: bool, record_id: String = "") -> Dictionary:
	# Fix-now round 4, S1: validated *before* anything else -- including
	# ResourceSaver.save() and DirAccess.make_dir_recursive_absolute() below --
	# because record_id here is exactly the id load_recovery_records() read
	# straight off a previously-loaded index entry (gst_main_panel.gd's
	# doc.recovery_record_id), which _validate_record's own new id/stack_file
	# cross-check (below) only rejects for entries loaded *after* this fix.
	# Any existing_id this call still receives unsafe (e.g. carried in-memory
	# from a document opened before this fix, or a future caller that never
	# went through load_all) must never reach `"%s.tres" % record_id` --
	# that derived stack_file is exactly what resolved outside `dir` before
	# this fix (an id of "../victim" wrote "../victim.tres"). Nothing is
	# written -- not the stack, not the index -- when this rejects.
	if not record_id.is_empty() and not _is_valid_record_id(record_id, "%s.tres" % record_id):
		return {"ok": false, "record_id": record_id, "stack_path": dir, "reason": "recovery record id '%s' is unsafe and was rejected before writing anything to %s" % [record_id, _index_path(dir)], "quarantined_path": ""}
	var id: String = record_id if not record_id.is_empty() else _generate_record_id()
	var stack_file: String = "%s.tres" % id
	var stack_path: String = dir.path_join(stack_file)
	# Review round 5, S1: when record_id names an *already-indexed* record
	# (an overwrite, not a fresh record), that record's own metadata is
	# validated before anything below touches its stack file or its index
	# entry -- `ResourceSaver.save` at `stack_path` below would otherwise
	# destroy an existing safe record's own content even when its indexed
	# metadata is invalid (unsupported version, or an id/stack_file identity
	# that no longer agrees with this call's own `record_id`/derived
	# `stack_file`), before `_validate_record`'s rejection ever gets a
	# chance to preserve it. An unreadable index here is never quarantined
	# on this path (quarantining is only ever safe when no existing record
	# could be consulted at all, which the fresh-record branch below still
	# covers unchanged): failing fast and naming the index path is the only
	# option that neither silently drops this existing record's own
	# reference nor overwrites it blind.
	var existing_index_result: Dictionary = {}
	if not record_id.is_empty():
		existing_index_result = _load_index(dir)
		if not bool(existing_index_result.get("ok", false)):
			return {"ok": false, "record_id": id, "stack_path": stack_path, "reason": "cannot update existing recovery record '%s' against %s: %s" % [record_id, _index_path(dir), existing_index_result.get("reason", "")], "quarantined_path": ""}
		var existing_validation: Dictionary = _find_validated_record(existing_index_result.get("records", []) as Array, record_id)
		if not existing_validation.is_empty() and not bool(existing_validation.get("ok", false)):
			return {"ok": false, "record_id": id, "stack_path": stack_path, "reason": "cannot update existing recovery record '%s' indexed in %s: %s" % [record_id, _index_path(dir), existing_validation.get("reason", "")], "quarantined_path": ""}
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(dir)
	if dir_error != OK:
		return {"ok": false, "record_id": id, "stack_path": stack_path, "reason": "failed to create recovery directory %s: %s" % [dir, error_string(dir_error)], "quarantined_path": ""}
	var stack_error: Error = ResourceSaver.save(stack, stack_path)
	if stack_error != OK:
		return {"ok": false, "record_id": id, "stack_path": stack_path, "reason": "failed to save recovery stack to %s: %s" % [stack_path, error_string(stack_error)], "quarantined_path": ""}
	# `existing_index_result` was already confirmed `ok=true` above whenever
	# `record_id` is non-empty (an unreadable index for an existing id
	# returned before this line ever ran) -- reused here instead of a second
	# `_load_index` call so this call's own write is judged against the same
	# index snapshot its own validation above just checked. A fresh record
	# (`record_id` empty) still reads fresh here, unchanged, since its own
	# quarantine-on-unreadable-index path below only ever applied to that
	# case to begin with.
	var index_result: Dictionary = existing_index_result if not record_id.is_empty() else _load_index(dir)
	# Fix-now round 2, note 1: a quarantine here is otherwise silent -- any
	# stack files the quarantined index used to reference become unreported
	# orphans the moment this call reports ok=true. Carry the quarantined
	# path through the result so _recover_document (gst_main_panel.gd) can
	# push_error it at write time; load_all's own directory scan (below)
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
## when record_id is empty or already absent from the index (gst_main_panel.gd
## calls this unconditionally after a successful save/Save As and after
## Discard; only a document that actually holds a recovery record has
## anything to remove). Never touches any other record's own files. Fix-now
## round 6, note 2 (S2): both the stack deletion and the metadata rewrite are
## now checked before this call claims success -- previously neither
## DirAccess.remove_absolute's nor _write_index's own result was inspected,
## so a failed deletion (its own stack path replaced by a non-empty
## directory) still fell through to dropping the entry from the index
## regardless (an orphaned stack: a file the index no longer names, with no
## way for a later call to rediscover it), and a failed metadata write after
## a successful deletion (the index's own .tmp path blocked) still reported
## nothing (a dangling index entry: naming a stack file that is now gone). A
## failed stack deletion now returns before the index is ever touched, so
## that record stays indexed with its file untouched, ready for a caller to
## retry; a failed metadata write after a successful deletion still leaves
## the real index.json byte-identical to its prior content (_write_index's
## own write-through-a-temp-file-then-rename never touches it on failure),
## so the record stays indexed even though its own stack file is already
## gone -- reported through this call's own new return shape rather than
## silently discarded either way. Reporting itself moved to this call's own
## caller (gst_main_panel.gd's _forget_recovery_record), matching write_
## record's own established convention of never push_error-ing internally.
## Detects a stack path replaced by a directory as present too (not only
## `FileAccess.file_exists()`, which reads `false` against a directory --
## the same presence gap `_load_index` above already guards for index.json;
## a real run of this fix's own regression proved a directory-blocked stack
## path skipped the deletion attempt entirely and still fell through to
## removing the index entry before this was added), so that shape reaches
## `DirAccess.remove_absolute`'s own failure instead of bypassing it.
## `{ok, reason}`: `reason` is "" whenever `ok` is true.
static func remove_record(dir: String, record_id: String) -> Dictionary:
	if record_id.is_empty():
		return {"ok": true, "reason": ""}
	var index_result: Dictionary = _load_index(dir)
	if not bool(index_result.get("ok", false)):
		return {"ok": false, "reason": "could not remove recovery record %s: %s" % [record_id, index_result.get("reason", "")]}
	var validation: Dictionary = _find_validated_record(index_result.get("records", []) as Array, record_id)
	if validation.is_empty():
		return {"ok": true, "reason": ""}
	if not bool(validation.get("ok", false)):
		return {"ok": false, "reason": "could not remove recovery record %s: %s" % [record_id, validation.get("reason", "")]}
	var stack_path: String = String(validation["stack_path"])
	# Round 6 evidence, `recovery_cleanup_stack_deletion_failure_reported`'s
	# own first real run: FileAccess.file_exists() alone reads false against
	# a directory occupying stack_path's own name (confirmed directly against
	# this engine, the same presence gap `_load_index` above already guards
	# against for index.json) -- so this guard used to skip the deletion
	# attempt entirely for that exact shape and fall straight through to
	# removing the index entry anyway, silently orphaning the directory this
	# was supposed to report. DirAccess.dir_exists_absolute() closes it.
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
## silently dropped (Cross-cutting: "Keep failed/unreadable records and
## report their paths, never deleting them"); the index itself is never
## rewritten here, so a transient read failure (e.g. a locked file) can still
## resolve on a later attempt. An unparseable index.json itself (malformed
## JSON, a non-Dictionary root, or a non-Array "records" field) is reported
## the same way, naming _index_path(dir) -- it is never silently treated as
## an empty/absent index, which would otherwise resolve zero records without
## reporting anything. Also reports every `index.json.unreadable-*` file
## already present in `dir` (fix-now round 2, note 1): a prior write_record()
## call may have quarantined an unreadable index and already reported it
## once at that write time, but the quarantined file itself, and any stack
## files its own lost index entries used to reference, stay on disk and
## orphaned -- this makes every later load_all() call (i.e. every editor
## startup, via load_recovery_records()) keep reporting it until a human
## actually removes or inspects it, matching "no migration may silently
## delete it". `{records: Array[Dictionary] (each the original metadata entry
## plus its own "stack": GSTStack), failures: Array[Dictionary]
## {id, path, reason}}`.
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
## conflate (fix-now round 6, notes 1 and 2 consolidation: write_record's
## existing-id path, load_all, and remove_record each read and validated the
## index separately before this, one of them -- write_record -- already
## silently treating "cannot open" the same as "never written"). `present=
## false` (`ok=true`, a fresh empty index) only when `_index_path(dir)`
## confirmedly does not exist at all: nothing has ever been written here.
## `present=true, ok=false` when the path exists but this engine cannot
## resolve it -- unopenable (a locked file, or a directory sharing its exact
## name: `FileAccess.open` returns null identically for both, confirmed
## directly against this engine, so `FileAccess.file_exists()` alone is not
## enough to detect presence either -- it also returns `false` for a
## directory, so `DirAccess.dir_exists_absolute()` is checked too), malformed
## JSON, a non-Dictionary root, a non-Array "records" field, or an
## unsupported version -- `reason` always names `_index_path(dir)`. A caller
## must never treat the second case as the first, which would silently
## discard whatever the file still holds (Cross-cutting "Invalid/unknown
## recovery metadata remains available for diagnosis; no migration may
## silently delete it"). `present=true, ok=true` once the file opened,
## parsed, and resolved into a supported-version `{version, records}` shape.
## Every record already run through `_validate_record` here (`records`, an
## Array of that call's own `{ok, id, stack_path, reason}` result plus this
## call's own added `entry` key holding the original raw Dictionary, in the
## same order as `index["records"]`) so write_record, load_all, and
## remove_record all judge one record's own validity and reconstruct its
## full field set the same way instead of re-reading/re-validating it three
## separate times. Uses the instance JSON API (like gst_header.gd's own
## parse()) so a malformed file never prints an engine ERROR: line on this
## expected-failure path. `{ok, present, index: Dictionary, records: Array,
## reason}`.
static func _load_index(dir: String) -> Dictionary:
	var path: String = _index_path(dir)
	var present: bool = FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)
	if not present:
		return {"ok": true, "present": false, "index": {"version": SCHEMA_VERSION, "records": []}, "records": [], "reason": ""}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "present": true, "index": {}, "records": [], "reason": "recovery index at %s could not be opened: %s" % [path, error_string(FileAccess.get_open_error())]}
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(text) != OK or not (json.get_data() is Dictionary):
		return {"ok": false, "present": true, "index": {}, "records": [], "reason": "recovery index at %s is not valid JSON" % path}
	var parsed: Dictionary = json.get_data() as Dictionary
	if not (parsed.get("records", []) is Array):
		return {"ok": false, "present": true, "index": {}, "records": [], "reason": "recovery index at %s has a non-array \"records\" field" % path}
	if not _is_supported_version(parsed.get("version")):
		return {"ok": false, "present": true, "index": {}, "records": [], "reason": "recovery index at %s has an unsupported or missing version %s" % [path, parsed.get("version")]}
	var validated: Array[Dictionary] = []
	for raw: Variant in (parsed["records"] as Array):
		if not (raw is Dictionary):
			validated.append({"ok": false, "id": "", "stack_path": dir, "reason": "malformed recovery index entry (not a Dictionary)", "entry": {}})
			continue
		var entry: Dictionary = raw as Dictionary
		var validation: Dictionary = _validate_record(entry, dir)
		validation["entry"] = entry
		validated.append(validation)
	return {"ok": true, "present": true, "index": parsed, "records": validated, "reason": ""}


## Finds `record_id`'s own already-validated result (fix-now round 6's
## `_load_index` output, never a raw/unvalidated records array) by the `id`
## every `_validate_record` result -- valid or not -- always carries.
## `{}` when no entry in `validated_records` names this id at all (a fresh
## record, or an index that was never asked about it).
static func _find_validated_record(validated_records: Array, record_id: String) -> Dictionary:
	for raw: Variant in validated_records:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == record_id:
			return raw as Dictionary
	return {}


## `true` only for the one schema version this engine writes and can resolve
## records against. An unknown or missing version is never valid input:
## `_load_index` routes it through the same unreadable-index path as
## malformed JSON, so `write_record` quarantines it (rename, never overwrite)
## instead of silently replacing its version with `SCHEMA_VERSION`, and
## `load_all` reports it as a failure instead of resolving it. Compares the
## `int` and `float` cases separately rather than `int(value) == SCHEMA_VERSION`
## for both (fix-now round 4, S1): `int()` truncates, so a `float` like `1.5`
## previously passed this check for `SCHEMA_VERSION == 1`. JSON's own numeric
## `1.0` (a `float`, never an `int`, per Godot's `JSON.parse`) must still be
## accepted -- compared against `float(SCHEMA_VERSION)` directly, exploiting
## that both sides are always whole numbers representable exactly in a
## double, so no fractional value can equal it.
static func _is_supported_version(value: Variant) -> bool:
	if value is int:
		return (value as int) == SCHEMA_VERSION
	if value is float:
		return (value as float) == float(SCHEMA_VERSION)
	return false


## Validates a recovery record's own id against the same bare-filename rule
## `_is_safe_stack_filename` already applies to `stack_file`, and against
## `stack_file`'s own basename (fix-now round 4, S1). `write_record` derives a
## *fresh* `stack_file` as `"%s.tres" % id` every time an `existing_id` is
## passed back to it (an overwrite of an already-indexed record, e.g.
## gst_main_panel.gd's `_recover_document` replaying `doc.recovery_record_id`
## on a later shutdown) -- so an id that itself contains `..` or a path
## separator resolves *that* derived stack_file outside `dir` even when the
## record's own previously-indexed `stack_file` field stayed a safe bare
## filename. Round 3's `_validate_record` validated `stack_file` on its own
## but never checked whether `id` and `stack_file` actually agree, so a
## planted record shaped `id="../victim"`, `stack_file="safe.tres"` passed
## load validation, and `doc.recovery_record_id` then carried that same
## unsafe id back into `write_record` as `record_id` on the next shutdown,
## which wrote `../victim.tres` before this fix. Requires `stack_file`'s own
## basename (without its `.tres` extension) to equal `id` exactly -- the only
## relationship `write_record` ever assumes between the two.
static func _is_valid_record_id(id: String, stack_file: String) -> bool:
	if id.is_empty() or id.contains("/") or id.contains("\\") or id.contains(".."):
		return false
	return id == stack_file.get_basename()


## Renames dir's own unparseable index.json out of the way instead of
## letting write_record silently overwrite it with a fresh, empty one --
## truncating it that way during a confirmed-shutdown write is exactly the
## window that produces an unreadable index for the next load_all() to find
## (Cross-cutting "no migration may silently delete it"). A no-op returning
## true when no index.json is present to quarantine (a non-Dictionary/non-
## Array failure always implies a present file, but a caller races nothing
## else against this directory). `ok=false` only if the rename itself fails,
## in which case write_record reports the original unreadable-index reason
## and never touches the file; `path` is the quarantined file's own path on
## success (fix-now round 2, note 1: write_record must be able to report it),
## or "" when nothing was quarantined (the no-op case). `{ok, path}`.
static func _quarantine_unreadable_index(dir: String) -> Dictionary:
	var path: String = _index_path(dir)
	if not FileAccess.file_exists(path):
		return {"ok": true, "path": ""}
	var quarantined_path: String = "%s.unreadable-%d" % [path, Time.get_unix_time_from_system()]
	if DirAccess.rename_absolute(path, quarantined_path) != OK:
		return {"ok": false, "path": ""}
	return {"ok": true, "path": quarantined_path}


## Every `index.json.unreadable-*` file currently present directly under
## `dir`, sorted for deterministic ordering -- load_all()'s own read-side half
## of note 1's fix: a file this finds was quarantined by some earlier
## write_record() call and has not been removed since, so its own lost index
## entries (and whatever stack files they referenced) are still unreported
## orphans on every load_all() call until it is gone. Returns an empty array
## when `dir` does not exist yet (nothing has ever been written there).
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
## truncates -- whatever index.json already exists at `path`. Verified
## directly that `DirAccess.rename_absolute` overwrites an existing
## destination file on Windows/Godot 4.4 before relying on it here.
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
	# Fix-now round 4, S1: id/stack_file cross-check. A record whose own id
	# does not agree with its stack_file's basename is inconsistent even when
	# each field passed its own individual check above -- and, critically,
	# left uncaught here, that same id is exactly what a caller (gst_main_
	# panel.gd's _recover_document) carries forward as write_record's own
	# existing_id on a later shutdown, deriving a *fresh* stack_file from the
	# id alone at that point rather than reusing this entry's stack_file.
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
