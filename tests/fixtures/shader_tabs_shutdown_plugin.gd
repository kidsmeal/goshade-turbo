@tool
extends EditorPlugin

const STAGE_FILE: String = "shader_tabs_phase1_stage.json"
const RECOVERY_DIR: String = "goshade_turbo_phase1/recovery"
const RECOVERY_FILE: String = "document.json"
const NAMED_STACK_PATH: String = "res://tabs-proof-named.tres"
const FAILED_NAMED_STACK_PATH: String = "res://.godot/editor/blocked-parent/named-failed.tres"
const FAILED_NAMED_RECOVERY_FILE: String = "named_failed_stack.tres"
const UNTITLED_RECOVERY_FILE: String = "untitled_stack.tres"

var _save_count: int = 0
var _external_data_saved: bool = false
var _documents_dirty: bool = false
var _force_failure: bool = false
var _forced_failure_path: String = ""
var _forced_failure_error: String = ""
var _pending_shutdown_stack: GSTStack = null
var _pending_shutdown_stack_path: String = ""
var _pending_shutdown_finish: Callable = Callable()
var _pending_shutdown_finished: bool = false
var _pending_shutdown_actions: int = 0
var _pending_shutdown_value: float = 0.0
var _pending_shutdown_stack_ok: bool = false


func _enter_tree() -> void:
	add_to_group(&"shader_tabs_shutdown_probe")


func _get_plugin_name() -> String:
	return "Shader Tabs Shutdown Probe"


func _get_unsaved_status(for_scene: String) -> String:
	if not for_scene.is_empty() or not _documents_dirty:
		return ""
	return "Named proof document\nUntitled proof document"


func _save_external_data() -> void:
	if not _documents_dirty:
		return
	_save_count = get_save_count() + 1
	var stage: String = get_stage()
	# The pending-shutdown edit is finished here, from inside the same
	# synchronous-quit callback production code will use, not by the proof
	# script beforehand. This is what actually exercises the forced-finish-
	# before-shutdown-save ordering rather than merely recording a flag.
	if _pending_shutdown_finish.is_valid():
		var pending_result: Dictionary = _pending_shutdown_finish.call() as Dictionary
		_pending_shutdown_actions = int(pending_result.get("actions", 0))
		_pending_shutdown_value = float(pending_result.get("value", 0.0))
		_pending_shutdown_finished = true
		_pending_shutdown_finish = Callable()
	if _pending_shutdown_stack != null:
		var pending_save_error: Error = ResourceSaver.save(_pending_shutdown_stack, _pending_shutdown_stack_path)
		_pending_shutdown_stack_ok = pending_save_error == OK
	var named_stack: GSTStack = GSTStack.new()
	named_stack.next_id = 7
	var named_result: Dictionary = GSTStackIO.save(named_stack, NAMED_STACK_PATH)
	_make_blocked_parent()
	var failed_named_stack: GSTStack = GSTStack.new()
	failed_named_stack.next_id = 29
	var failed_named_result: Dictionary = GSTStackIO.save(failed_named_stack, FAILED_NAMED_STACK_PATH)
	var failed_named_recovery: Dictionary = _write_recovery_stack(failed_named_stack, FAILED_NAMED_RECOVERY_FILE)
	var recovery_stack: GSTStack = GSTStack.new()
	recovery_stack.next_id = 42
	var recovery_result: Dictionary = _write_recovery_stack(recovery_stack, UNTITLED_RECOVERY_FILE)
	var metadata_result: Dictionary = _write_recovery_metadata(named_result, failed_named_result, failed_named_recovery, recovery_result)
	_external_data_saved = bool(named_result.get("ok", false)) and not bool(failed_named_result.get("ok", true)) and bool(failed_named_recovery.get("ok", false)) and bool(recovery_result.get("ok", false)) and bool(metadata_result.get("ok", false))
	_documents_dirty = not _external_data_saved
	_write_stage({
		"stage": "confirmed_quit_complete" if stage == "awaiting_confirmed_quit" else stage,
		"save_count": _save_count,
		"named_path": NAMED_STACK_PATH,
		"named_ok": bool(named_result.get("ok", false)),
		"failed_named_path": FAILED_NAMED_STACK_PATH,
		"failed_named_ok": bool(failed_named_result.get("ok", false)),
		"failed_named_reason": String(failed_named_result.get("reason", "")),
		"failed_named_recovery_ok": bool(failed_named_recovery.get("ok", false)),
		"recovery_ok": bool(recovery_result.get("ok", false)),
		"metadata_ok": bool(metadata_result.get("ok", false)),
		"pending_shutdown_finished": _pending_shutdown_finished,
		"pending_shutdown_actions": _pending_shutdown_actions,
		"pending_shutdown_value": _pending_shutdown_value,
		"pending_shutdown_stack_ok": _pending_shutdown_stack_ok,
		"pending_shutdown_stack_path": _pending_shutdown_stack_path,
	})
	if _force_failure:
		_forced_failure_path = _settings_path().path_join("blocked-parent").path_join("document.json")
		_make_blocked_parent()
		var failed: FileAccess = FileAccess.open(_forced_failure_path, FileAccess.WRITE)
		var open_error: Error = FileAccess.get_open_error()
		_forced_failure_error = "%s (%d)" % [error_string(open_error), open_error]
		if failed != null:
			failed.close()
		push_error("TABS_PROOF_EXPECTED_WRITE_FAILURE path=%s error=%s" % [_forced_failure_path, _forced_failure_error])


func get_stage() -> String:
	return String(_read_stage().get("stage", "initial"))


func prepare_confirmed_quit() -> void:
	_documents_dirty = true
	_write_stage({"stage": "awaiting_confirmed_quit", "save_count": _save_count})


func reset_unsaved_documents() -> void:
	_external_data_saved = false
	_documents_dirty = false


func mark_unsaved_documents_dirty() -> void:
	_documents_dirty = true
	_external_data_saved = false


func set_pending_shutdown_target(stack: GSTStack, stack_path: String, finish: Callable) -> void:
	_pending_shutdown_stack = stack
	_pending_shutdown_stack_path = stack_path
	_pending_shutdown_finish = finish


func load_pending_shutdown_stack() -> GSTStack:
	var stack_path: String = String(_read_stage().get("pending_shutdown_stack_path", ""))
	if stack_path.is_empty():
		return null
	return ResourceLoader.load(stack_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GSTStack


func read_recovery_record() -> Dictionary:
	var recovery: FileAccess = FileAccess.open(_recovery_metadata_path(), FileAccess.READ)
	if recovery == null:
		return {}
	var parsed: Variant = JSON.parse_string(recovery.get_as_text())
	recovery.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func load_recovery_stack() -> GSTStack:
	var stack_path: String = _recovery_stack_path("untitled")
	if stack_path.is_empty():
		return null
	return ResourceLoader.load(stack_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GSTStack


func load_failed_named_recovery_stack() -> GSTStack:
	var stack_path: String = _recovery_stack_path("named_failed")
	if stack_path.is_empty():
		return null
	return ResourceLoader.load(stack_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GSTStack


func get_mixed_shutdown_state() -> Dictionary:
	return _read_stage()


func call_unsaved_status(for_scene: String) -> String:
	return _get_unsaved_status(for_scene)


func call_save_external_data() -> void:
	_save_external_data()


func force_write_failure() -> void:
	_force_failure = true
	_documents_dirty = true


func get_forced_failure_path() -> String:
	return _forced_failure_path


func get_forced_failure_error() -> String:
	return _forced_failure_error


func get_save_count() -> int:
	return maxi(_save_count, int(_read_stage().get("save_count", 0)))


func mark_complete() -> void:
	_write_stage({"stage": "complete", "save_count": get_save_count()})


func _write_recovery_stack(stack: GSTStack, file_name: String) -> Dictionary:
	var recovery_dir: String = _settings_path().path_join(RECOVERY_DIR)
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(recovery_dir)
	if dir_error != OK:
		return {"ok": false, "reason": error_string(dir_error)}
	var stack_path: String = recovery_dir.path_join(file_name)
	var stack_error: Error = ResourceSaver.save(stack, stack_path)
	if stack_error != OK:
		return {"ok": false, "reason": error_string(stack_error)}
	return {"ok": true, "stack_path": stack_path}


func _write_recovery_metadata(named_result: Dictionary, failed_named_result: Dictionary, failed_named_recovery: Dictionary, untitled_recovery: Dictionary) -> Dictionary:
	var metadata: FileAccess = FileAccess.open(_recovery_metadata_path(), FileAccess.WRITE)
	if metadata == null:
		return {"ok": false, "reason": error_string(FileAccess.get_open_error())}
	metadata.store_string(JSON.stringify({
		"version": 1,
		"documents": [
			{"id": "named_success", "origin": "named", "save_path": NAMED_STACK_PATH, "saved": bool(named_result.get("ok", false))},
			{"id": "named_failed", "origin": "named", "save_path": FAILED_NAMED_STACK_PATH, "save_reason": String(failed_named_result.get("reason", "")), "recovery_path": String(failed_named_recovery.get("stack_path", ""))},
			{"id": "untitled", "origin": "untitled", "recovery_path": String(untitled_recovery.get("stack_path", ""))},
		],
	}))
	metadata.close()
	return {"ok": true}


func _recovery_stack_path(id: String) -> String:
	var documents: Array = read_recovery_record().get("documents", []) as Array
	for document: Variant in documents:
		if document is Dictionary and String((document as Dictionary).get("id", "")) == id:
			return String((document as Dictionary).get("recovery_path", ""))
	return ""


func _make_blocked_parent() -> void:
	var blocked_parent: String = _settings_path().path_join("blocked-parent")
	var blocker: FileAccess = FileAccess.open(blocked_parent, FileAccess.WRITE)
	if blocker != null:
		blocker.store_string("file blocks child path")
		blocker.close()


func _settings_path() -> String:
	return EditorInterface.get_editor_paths().get_project_settings_dir()


func _recovery_metadata_path() -> String:
	return _settings_path().path_join(RECOVERY_DIR).path_join(RECOVERY_FILE)


func _stage_path() -> String:
	return _settings_path().path_join(STAGE_FILE)


func _read_stage() -> Dictionary:
	var stage: FileAccess = FileAccess.open(_stage_path(), FileAccess.READ)
	if stage == null:
		return {}
	var parsed: Variant = JSON.parse_string(stage.get_as_text())
	stage.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _write_stage(value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_settings_path())
	var stage: FileAccess = FileAccess.open(_stage_path(), FileAccess.WRITE)
	if stage != null:
		stage.store_string(JSON.stringify(value))
		stage.close()
