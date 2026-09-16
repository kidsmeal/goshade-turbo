@tool
extends RefCounted

## Smoke selector GST_EDITOR_SMOKE=tabs_recovery (dispatched by
## tests/gst_editor_smoke.gd): confirmed-shutdown save and project-local
## document recovery.
## GSTMainPanel.get_recovery_dir() resolves under the running project's
## settings directory; run this selector against the isolated project under
## .now/tabs-validation/ so no real project's recovery records are written.
## Two-stage: a JSON stage file directly under the project settings
## directory (a sibling of goshade_turbo/recovery) records which half of the
## Save-and-Quit round trip this process is. Every other check runs in one
## editor session by calling plugin._get_unsaved_status/_save_external_data
## directly, the callbacks Godot's quit confirmation and scene-close invoke.
## tests/fixtures/shader_tabs_shutdown_plugin.cfg/.gd must stay disabled for
## this selector; it would also answer the confirmed-quit dialog.
## Prints one "SMOKE <item> PASS|FAIL <detail>" line per check and
## "SMOKE SUMMARY pass=N fail=M"; exit code 1 on any failure.

const STAGE_FILE: String = "gst_recovery_smoke_stage.json"
const HOST_SCENE_PATH: String = "res://tests/fixtures/shader_tabs_host.tscn"
const NAMED_OK_PATH: String = "user://gst_recovery_named_ok.tres"
const BLOCKED_PARENT: String = "user://gst_recovery_blocked_parent"
const BLOCKED_PATH: String = "user://gst_recovery_blocked_parent/named_failed.tres"
const QUIT_UNTITLED_MARKER: int = 42017
const QUIT_NAMED_FAILED_MARKER: int = 42018
const QUIT_NAMED_FAILED_PATH: String = "user://gst_recovery_blocked_parent/quit_named_failed.tres"

var _pass_count: int = 0
var _fail_count: int = 0


func run(plugin: EditorPlugin) -> void:
	for i: int in range(5):
		await plugin.get_tree().process_frame
	await _settle_editor(plugin)
	var panel: GSTMainPanel = plugin.get_panel() as GSTMainPanel
	_check("panel", panel != null, "panel present=%s" % [panel != null])
	if panel == null:
		_finish(plugin)
		return

	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await plugin.get_tree().process_frame

	var stage: Dictionary = _read_stage()
	var stage_name: String = String(stage.get("stage", ""))
	if stage_name == "confirmed_quit_complete":
		await _verify_fresh_open(plugin, panel, stage)
		return

	await _run_initial(plugin, panel)


## Stage 1: every single-session check, then two dirty documents handed off
## to a real confirmed quit.
func _run_initial(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	# A prior aborted run's leftover recovery record reopens as a dirty
	# document in _ready() before this script runs; discard it so record
	# counts start at zero.
	for doc: GSTDocument in panel.get_documents():
		if doc.is_dirty():
			await panel.close_document(doc)
			if panel.is_close_dialog_visible():
				panel._on_close_custom_action("discard")
				await plugin.get_tree().process_frame

	if panel.is_start_screen_visible():
		panel.get_create_empty_button().pressed.emit()
		await plugin.get_tree().process_frame
		panel.get_picker().cancelled.emit()
		await plugin.get_tree().process_frame

	await _check_two_untitled_documents_get_distinct_unsaved_status_lines(plugin, panel)

	var dir: String = panel.get_recovery_dir()
	_wipe_dir_contents(dir)
	_cleanup_paths([NAMED_OK_PATH])
	_unblock(BLOCKED_PARENT)

	await _check_nonempty_for_scene_reports_empty(plugin, panel)
	_check_record_schema_round_trip(panel)
	_check_write_record_directory_failure(panel)
	_check_read_side_failures(panel)
	_check_write_record_metadata_failure_preserves_previous_index(panel)
	_check_unknown_index_version_rejected(panel)
	_check_stack_file_traversal_rejected(panel)
	await _check_record_id_traversal_rejected_before_write(plugin, panel)
	_check_fractional_index_version_rejected(panel)
	_check_fractional_record_version_rejected(panel)
	_check_float_whole_number_version_accepted(panel)
	await _check_existing_record_validated_before_write(plugin, panel)
	await _check_dual_failure_does_not_falsely_mark_recovered(plugin, panel)
	await _check_metadata_write_failure_leaves_document_needing_attention(plugin, panel)
	await _check_recover_document_reports_quarantine_at_write_time(plugin, panel)
	await _check_index_open_failure_distinguished_from_absence(plugin, panel)
	await _check_recovery_cleanup_stack_deletion_failure_reported(plugin, panel)
	await _check_recovery_cleanup_index_replacement_failure_reported(plugin, panel)

	var doc_ok: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	await panel.save_to_path(NAMED_OK_PATH)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("generative/hash", GSTLayer.Kind.FIELD, true)
	await plugin.get_tree().process_frame
	var doc_ok_expected_fingerprint: String = GSTDocument.compute_fingerprint(doc_ok.stack)

	var doc_failed: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	_make_blocked_parent(BLOCKED_PARENT)
	doc_failed.current_path = BLOCKED_PATH
	var doc_failed_fingerprint_round1: String = GSTDocument.compute_fingerprint(doc_failed.stack)

	var doc_untitled: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("generative/checker", GSTLayer.Kind.FIELD, true)
	await plugin.get_tree().process_frame
	var doc_untitled_fingerprint_round1: String = GSTDocument.compute_fingerprint(doc_untitled.stack)

	var status_before_save: String = plugin._get_unsaved_status("")
	var lines_before_save: PackedStringArray = status_before_save.split("\n")
	_check("unsaved_status_lists_dirty_documents", lines_before_save.size() >= 3, "status='%s'" % [status_before_save])

	# --- round 1: healthy recovery dir, mixed named-ok/named-failed/untitled ---
	plugin._save_external_data()
	var loaded_named_ok: Dictionary = GSTStackIO.load(NAMED_OK_PATH, panel.get_library())
	var round1_records: Array = (GSTDocumentRecovery.load_all(dir, panel.get_library()).get("records", []) as Array)
	var round1_failed_entry: Dictionary = _find_entry(round1_records, doc_failed.recovery_record_id)
	var round1_untitled_entry: Dictionary = _find_entry(round1_records, doc_untitled.recovery_record_id)
	var round1_ok: bool = (
		not doc_ok.is_dirty() and doc_ok.recovery_record_id.is_empty()
		and bool(loaded_named_ok.get("ok", false)) and GSTDocument.compute_fingerprint(loaded_named_ok["stack"]) == doc_ok_expected_fingerprint
		and doc_failed.is_dirty() and not doc_failed.recovery_record_id.is_empty()
		and doc_untitled.is_dirty() and not doc_untitled.recovery_record_id.is_empty()
		and round1_records.size() == 2
		and String(round1_failed_entry.get("original_path", "")) == BLOCKED_PATH and bool(round1_failed_entry.get("save_failed", false))
		and String(round1_untitled_entry.get("original_path", "")) == "" and not bool(round1_untitled_entry.get("save_failed", false))
		and GSTDocument.compute_fingerprint(round1_failed_entry.get("stack")) == doc_failed_fingerprint_round1
		and GSTDocument.compute_fingerprint(round1_untitled_entry.get("stack")) == doc_untitled_fingerprint_round1
	)
	_check("round1_mixed_named_and_untitled_recovery", round1_ok, "doc_ok_dirty=%s doc_failed_dirty=%s doc_untitled_dirty=%s records=%d failed_entry=%s untitled_entry=%s" % [doc_ok.is_dirty(), doc_failed.is_dirty(), doc_untitled.is_dirty(), round1_records.size(), round1_failed_entry, round1_untitled_entry])

	# Godot re-checks every plugin's _get_unsaved_status("") after
	# _save_external_data() and does not exit while it reports anything, so a
	# document whose recovery record matches its content must drop out of the
	# status while staying is_dirty() for its tab star.
	var status_after_round1: String = plugin._get_unsaved_status("")
	var status_after_round1_ok: bool = not status_after_round1.contains(doc_failed.current_path.get_file().get_basename()) and doc_failed.is_dirty() and doc_untitled.is_dirty()
	_check("recovered_document_stops_blocking_shutdown_status", status_after_round1_ok, "status='%s' doc_failed_dirty=%s doc_untitled_dirty=%s" % [status_after_round1, doc_failed.is_dirty(), doc_untitled.is_dirty()])

	# --- round 2: repeated shutdown against still-dirty documents updates the
	# same record in place instead of duplicating it. ---
	var round1_failed_id: String = doc_failed.recovery_record_id
	var round1_untitled_id: String = doc_untitled.recovery_record_id
	if panel.get_active_document() != doc_failed:
		await panel.activate_document(doc_failed)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("fieldops/invert", GSTLayer.Kind.FIELD, false)
	await plugin.get_tree().process_frame
	var doc_failed_fingerprint_round2: String = GSTDocument.compute_fingerprint(doc_failed.stack)
	if panel.get_active_document() != doc_untitled:
		await panel.activate_document(doc_untitled)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("fieldops/invert", GSTLayer.Kind.FIELD, false)
	await plugin.get_tree().process_frame
	var doc_untitled_fingerprint_round2: String = GSTDocument.compute_fingerprint(doc_untitled.stack)
	plugin._save_external_data()
	var round2_records: Array = (GSTDocumentRecovery.load_all(dir, panel.get_library()).get("records", []) as Array)
	var round2_failed_entry: Dictionary = _find_entry(round2_records, doc_failed.recovery_record_id)
	var round2_untitled_entry: Dictionary = _find_entry(round2_records, doc_untitled.recovery_record_id)
	var round2_ok: bool = (
		round2_records.size() == 2
		and doc_failed.recovery_record_id == round1_failed_id and doc_untitled.recovery_record_id == round1_untitled_id
		and GSTDocument.compute_fingerprint(round2_failed_entry.get("stack")) == doc_failed_fingerprint_round2
		and GSTDocument.compute_fingerprint(round2_untitled_entry.get("stack")) == doc_untitled_fingerprint_round2
	)
	_check("round2_repeated_shutdown_updates_same_record", round2_ok, "records=%d failed_id_unchanged=%s untitled_id_unchanged=%s" % [round2_records.size(), doc_failed.recovery_record_id == round1_failed_id, doc_untitled.recovery_record_id == round1_untitled_id])

	_check_metadata_write_failure_does_not_silently_succeed(panel)

	# --- Save cleanup removes doc_failed's record. ---
	var fixed_path: String = "user://gst_recovery_named_failed_fixed.tres"
	_cleanup_paths([fixed_path])
	var save_result: Dictionary = await panel._save_stack_to_path(doc_failed, fixed_path)
	var save_cleanup_ok: bool = bool(save_result.get("ok", false)) and not doc_failed.is_dirty() and doc_failed.recovery_record_id.is_empty()
	_check("save_removes_recovery_record", save_cleanup_ok, "save_result=%s recovery_record_id='%s'" % [save_result, doc_failed.recovery_record_id])

	# --- Discard cleanup removes doc_untitled's record. ---
	await panel.close_document(doc_untitled)
	var dialog_shown: bool = panel.is_close_dialog_visible()
	if dialog_shown:
		panel._on_close_custom_action("discard")
		await plugin.get_tree().process_frame
	var discard_cleanup_ok: bool = dialog_shown and not panel.get_documents().has(doc_untitled)
	_check("discard_removes_recovery_record", discard_cleanup_ok, "dialog_shown=%s still_open=%s" % [dialog_shown, panel.get_documents().has(doc_untitled)])

	var records_after_cleanup: Array = (GSTDocumentRecovery.load_all(dir, panel.get_library()).get("records", []) as Array)
	_check("recovery_dir_empty_after_save_and_discard_cleanup", records_after_cleanup.is_empty(), "remaining=%d listing=%s" % [records_after_cleanup.size(), _list_dir(dir)])

	_cleanup_paths([NAMED_OK_PATH, fixed_path])
	_unblock(BLOCKED_PARENT)

	if _fail_count > 0:
		_finish(plugin)
		return

	# --- Confirmed-quit setup: two dirty documents, one untitled and one with
	# an unwritable current_path, identified by a stack.next_id marker the
	# next process can look up. ---
	var quit_untitled: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	quit_untitled.stack.next_id = QUIT_UNTITLED_MARKER

	var quit_failed: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	_make_blocked_parent(BLOCKED_PARENT)
	quit_failed.current_path = QUIT_NAMED_FAILED_PATH
	quit_failed.stack.next_id = QUIT_NAMED_FAILED_MARKER

	var status_before_quit: String = plugin._get_unsaved_status("")
	_check("unsaved_status_before_quit_lists_both", status_before_quit.contains("quit_named_failed") and quit_untitled.is_dirty() and quit_failed.is_dirty(), "status='%s'" % [status_before_quit])

	# Written as "confirmed_quit_complete" directly: this process drives the
	# quit below in the same call chain, and only the next process reads it.
	_write_stage({
		"stage": "confirmed_quit_complete",
		"untitled_marker": QUIT_UNTITLED_MARKER,
		"named_failed_marker": QUIT_NAMED_FAILED_MARKER,
		"named_failed_path": QUIT_NAMED_FAILED_PATH,
	})
	print("SMOKE_RECOVERY READY_FOR_CONFIRMED_QUIT")
	await _drive_confirmed_quit(plugin)


## Asserts two dirty untitled documents render as two distinct lines in
## get_unsaved_status_text(""), matching the tab row's per-document
## "Untitled %d" numbering (_tab_title, gst_main_panel.gd).
func _check_two_untitled_documents_get_distinct_unsaved_status_lines(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var doc_a: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	var doc_b: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	var status: String = plugin._get_unsaved_status("")
	var lines: PackedStringArray = status.split("\n")
	var distinct_ok: bool = doc_a.is_dirty() and doc_b.is_dirty() and lines.size() == 2 and lines[0] != lines[1]
	_check("two_untitled_documents_get_distinct_unsaved_status_lines", distinct_ok, "status='%s'" % [status])
	await panel.close_document(doc_a)
	if panel.is_close_dialog_visible():
		panel._on_close_custom_action("discard")
		await plugin.get_tree().process_frame
	await panel.close_document(doc_b)
	if panel.is_close_dialog_visible():
		panel._on_close_custom_action("discard")
		await plugin.get_tree().process_frame


func _check_nonempty_for_scene_reports_empty(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	# Close any scene Godot reopened on startup so the confirmed quit later
	# in this run does not race Godot's own save handling for it.
	# Uses MenuBar id_pressed, as _drive_confirmed_quit does: a synthetic
	# Ctrl+Shift+W InputEventKey does not reach the shortcut in this
	# environment.
	_close_current_scene(plugin)
	EditorInterface.open_scene_from_path(HOST_SCENE_PATH)
	await _frames(plugin, 5)
	var status_scene: String = plugin._get_unsaved_status(HOST_SCENE_PATH)
	_check("for_scene_reports_no_shader_owned_data", status_scene.is_empty(), "status='%s'" % [status_scene])
	_close_current_scene(plugin)
	var scene_closed: bool = plugin.get_tree().edited_scene_root == null
	_check("host_scene_closed_before_recovery_flow", scene_closed, "edited_scene_root=%s" % [plugin.get_tree().edited_scene_root])
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await plugin.get_tree().process_frame


func _close_current_scene(plugin: EditorPlugin) -> void:
	if plugin.get_tree().edited_scene_root == null:
		return
	var bar: MenuBar = _find_menu_bar(plugin.get_tree().root)
	if bar == null:
		return
	var close_result: Dictionary = _find_menu_item_id(bar, "Scene", "Close Scene")
	if not bool(close_result.get("found", false)):
		return
	(close_result["popup"] as PopupMenu).id_pressed.emit(int(close_result["id"]))
	for i: int in range(6):
		await plugin.get_tree().process_frame


## Round trip of GSTDocumentRecovery's record schema (version, id,
## stack_file, original_path, recipe/import origin fields) in a throwaway
## directory.
func _check_record_schema_round_trip(panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_schema_check")
	_wipe_dir_contents(dir)
	var stack: GSTStack = GSTStack.new()
	stack.next_id = 99
	var write_result: Dictionary = GSTDocumentRecovery.write_record(dir, stack, "res://original.tres", true, "fire", false, true)
	var loaded: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var records: Array = loaded.get("records", []) as Array
	var entry: Dictionary = records[0] as Dictionary if records.size() == 1 else {}
	var loaded_stack: GSTStack = entry.get("stack") as GSTStack
	var schema_ok: bool = (
		bool(write_result.get("ok", false)) and records.size() == 1 and (loaded.get("failures", []) as Array).is_empty()
		and int(entry.get("version", -1)) == GSTDocumentRecovery.SCHEMA_VERSION
		and String(entry.get("id", "")) == String(write_result.get("record_id", ""))
		and String(entry.get("original_path", "")) == "res://original.tres"
		and bool(entry.get("recipe_open", false)) == true and String(entry.get("recipe_name", "")) == "fire"
		and bool(entry.get("reopened_import", false)) == false and bool(entry.get("save_failed", false)) == true
		and loaded_stack != null and loaded_stack.next_id == 99
	)
	_check("record_schema_round_trip", schema_ok, "write_result=%s entry_keys=%s" % [write_result, entry.keys()])
	_wipe_dir_contents(dir)


## Asserts a named document whose save failed and whose recovery write also
## fails keeps recovery_record_id/recovery_fingerprint unset, so
## needs_shutdown_attention() still reports it. Calls _recover_document
## directly in a throwaway directory; the push_error text is not asserted
## (no script-side stderr capture).
func _check_dual_failure_does_not_falsely_mark_recovered(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	var blocked_base: String = ProjectSettings.globalize_path("user://gst_recovery_dual_failure_check")
	_make_blocked_parent(blocked_base)
	doc.current_path = "user://gst_recovery_dual_failure_named.tres"
	var dir: String = GSTDocumentRecovery.recovery_dir(blocked_base)
	panel._recover_document(doc, dir, "simulated named-save failure")
	var dual_failure_ok: bool = doc.recovery_record_id.is_empty() and doc.recovery_fingerprint.is_empty() and doc.needs_shutdown_attention()
	_check("dual_failure_does_not_falsely_mark_recovered", dual_failure_ok, "recovery_record_id='%s' recovery_fingerprint='%s' needs_attention=%s" % [doc.recovery_record_id, doc.recovery_fingerprint, doc.needs_shutdown_attention()])
	_unblock(blocked_base)
	await panel.close_document(doc)
	if panel.is_close_dialog_visible():
		panel._on_close_custom_action("discard")
		await plugin.get_tree().process_frame


## Asserts _recover_document, against a pre-existing unreadable index.json,
## reports the write as recovered (write_record quarantines the index, then
## writes fresh). The push_error naming the quarantined path is not asserted
## (no script-side stderr capture).
func _check_recover_document_reports_quarantine_at_write_time(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	var base: String = ProjectSettings.globalize_path("user://gst_recovery_recover_document_quarantine_check")
	_wipe_dir_contents(base)
	var dir: String = GSTDocumentRecovery.recovery_dir(base)
	DirAccess.make_dir_recursive_absolute(dir)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var index_file: FileAccess = FileAccess.open(index_path, FileAccess.WRITE)
	index_file.store_string("{ this is not valid json")
	index_file.close()
	panel._recover_document(doc, dir, "")
	var recovered_ok: bool = not doc.recovery_record_id.is_empty() and doc.recovery_fingerprint == GSTDocument.compute_fingerprint(doc.stack)
	_check("recover_document_reports_quarantine_at_write_time", recovered_ok, "recovery_record_id='%s' listing=%s (see this pass's own stderr for the push_error naming the quarantined index.json.unreadable-* path)" % [doc.recovery_record_id, _list_dir(dir)])
	_wipe_dir_contents(base)
	await panel.close_document(doc)
	if panel.is_close_dialog_visible():
		panel._on_close_custom_action("discard")
		await plugin.get_tree().process_frame


## Asserts an index.json that cannot be opened is never treated as absent.
## Plants a directory named "index.json": FileAccess.open on a directory
## fails on Windows and Linux, and FileAccess.file_exists() reads false for
## it, so _load_index also checks DirAccess.dir_exists_absolute().
## Exercises three paths: load_all (one failure by the index path, zero
## records), write_record with an existing id (ok=false naming the index
## path, no stack file or index.json written), and _recover_document (doc's
## recovery identity unset, needs_shutdown_attention() true).
func _check_index_open_failure_distinguished_from_absence(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_index_open_failure")
	_wipe_dir_contents(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	DirAccess.make_dir_recursive_absolute(index_path)
	var listing_before: PackedStringArray = _list_dir(dir)

	var loaded: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var failures: Array = loaded.get("failures", []) as Array
	var records: Array = loaded.get("records", []) as Array
	var load_ok: bool = records.is_empty() and failures.size() == 1 and String((failures[0] as Dictionary).get("path", "")) == index_path

	var write_result: Dictionary = GSTDocumentRecovery.write_record(dir, GSTStack.new(), "", false, "", false, false, "existing_against_unopenable_index")
	var write_ok: bool = not bool(write_result.get("ok", false)) and String(write_result.get("reason", "")).contains(index_path)
	var listing_after_write: PackedStringArray = _list_dir(dir)

	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	doc.recovery_record_id = "existing_against_unopenable_index"
	panel._recover_document(doc, dir, "")
	var listing_after_recover: PackedStringArray = _list_dir(dir)
	var recover_ok: bool = doc.recovery_record_id == "existing_against_unopenable_index" and doc.recovery_fingerprint.is_empty() and doc.needs_shutdown_attention()

	var no_new_files_ok: bool = listing_after_write == listing_before and listing_after_recover == listing_before
	_check("index_open_failure_distinguished_from_absence", load_ok and write_ok and recover_ok and no_new_files_ok, "failures=%s write_result=%s listing_before=%s listing_after_write=%s listing_after_recover=%s needs_attention=%s" % [failures, write_result, listing_before, listing_after_write, listing_after_recover, doc.needs_shutdown_attention()])
	await panel.close_document(doc)
	if panel.is_close_dialog_visible():
		panel._on_close_custom_action("discard")
		await plugin.get_tree().process_frame
	_wipe_dir_contents(dir)


## Asserts a record whose stack file cannot be deleted (path replaced by a
## non-empty directory; DirAccess.remove_absolute fails outright on it) is
## never treated as removed: the index entry and the blocked path survive
## and doc's recovery identity stays set.
## Exercises remove_record directly and _forget_recovery_record against the
## panel's real recovery dir (_forget_recovery_record takes no dir argument).
func _check_recovery_cleanup_stack_deletion_failure_reported(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var dir: String = panel.get_recovery_dir()
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	panel._recover_document(doc, dir, "")
	var record_id: String = doc.recovery_record_id
	var fingerprint_before: String = doc.recovery_fingerprint
	var stack_path: String = dir.path_join("%s.tres" % record_id)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var recover_ok: bool = not record_id.is_empty() and FileAccess.file_exists(stack_path)
	DirAccess.remove_absolute(stack_path)
	DirAccess.make_dir_recursive_absolute(stack_path)
	var blocker_file: FileAccess = FileAccess.open(stack_path.path_join("child.txt"), FileAccess.WRITE)
	blocker_file.store_string("blocks remove_absolute")
	blocker_file.close()
	var index_before: String = _read_file_text(index_path)

	var direct_remove_result: Dictionary = GSTDocumentRecovery.remove_record(dir, record_id)
	var direct_ok: bool = (
		not bool(direct_remove_result.get("ok", false)) and not String(direct_remove_result.get("reason", "")).is_empty()
		and _read_file_text(index_path) == index_before
		and DirAccess.dir_exists_absolute(stack_path) and FileAccess.file_exists(stack_path.path_join("child.txt"))
	)

	panel._forget_recovery_record(doc)
	var panel_ok: bool = (
		doc.recovery_record_id == record_id and doc.recovery_fingerprint == fingerprint_before
		and _read_file_text(index_path) == index_before
		and DirAccess.dir_exists_absolute(stack_path) and FileAccess.file_exists(stack_path.path_join("child.txt"))
	)
	_check("recovery_cleanup_stack_deletion_failure_reported", recover_ok and direct_ok and panel_ok, "record_id='%s' direct_remove_result=%s recovery_record_id_after='%s' index_unchanged=%s stack_dir_survived=%s" % [record_id, direct_remove_result, doc.recovery_record_id, _read_file_text(index_path) == index_before, DirAccess.dir_exists_absolute(stack_path)])

	_remove_dir_recursive(stack_path)
	await panel.close_document(doc)
	if panel.is_close_dialog_visible():
		panel._on_close_custom_action("discard")
		await plugin.get_tree().process_frame


## Asserts a metadata rewrite that fails after the stack deletion succeeded
## (index.json.tmp blocked by a directory) is reported: doc's recovery
## identity stays set and index.json's bytes are unchanged (_write_index
## writes through a temp file, then renames).
## The deleted stack file is an accepted residual of this failure order and
## is not asserted. After the .tmp block is lifted, closing doc with Discard
## runs _forget_recovery_record again and succeeds, leaving the dir clean.
func _check_recovery_cleanup_index_replacement_failure_reported(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var dir: String = panel.get_recovery_dir()
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	panel._recover_document(doc, dir, "")
	var record_id: String = doc.recovery_record_id
	var fingerprint_before: String = doc.recovery_fingerprint
	var stack_path: String = dir.path_join("%s.tres" % record_id)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var recover_ok: bool = not record_id.is_empty() and FileAccess.file_exists(stack_path)
	var temp_path: String = "%s.tmp" % index_path
	DirAccess.make_dir_recursive_absolute(temp_path)
	var index_before: String = _read_file_text(index_path)

	panel._forget_recovery_record(doc)
	var panel_ok: bool = (
		doc.recovery_record_id == record_id and doc.recovery_fingerprint == fingerprint_before
		and _read_file_text(index_path) == index_before
	)
	_check("recovery_cleanup_index_replacement_failure_reported", recover_ok and panel_ok, "record_id='%s' recovery_record_id_after='%s' index_unchanged=%s stack_deleted_as_known_residual=%s" % [record_id, doc.recovery_record_id, _read_file_text(index_path) == index_before, not FileAccess.file_exists(stack_path)])

	DirAccess.remove_absolute(temp_path)
	await panel.close_document(doc)
	if panel.is_close_dialog_visible():
		panel._on_close_custom_action("discard")
		await plugin.get_tree().process_frame


## Asserts write_record reports ok=false with a reason when a plain file
## blocks the recovery directory's ancestor.
func _check_write_record_directory_failure(panel: GSTMainPanel) -> void:
	var blocked_base: String = ProjectSettings.globalize_path("user://gst_recovery_dir_blocked")
	_make_blocked_parent(blocked_base)
	var dir: String = GSTDocumentRecovery.recovery_dir(blocked_base)
	var result: Dictionary = GSTDocumentRecovery.write_record(dir, GSTStack.new(), "", false, "", false, false)
	_check("write_record_reports_directory_failure", not bool(result.get("ok", false)) and not String(result.get("reason", "")).is_empty(), "result=%s" % [result])
	_unblock(blocked_base)


## Asserts a failed _write_index (writes index.json.tmp, then renames over
## index.json) leaves the previous index.json bytes unchanged. Blocking the
## temp path with a directory makes FileAccess.open return null while
## index.json stays a normal file.
func _check_write_record_metadata_failure_preserves_previous_index(panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_preserve_previous_index")
	_wipe_dir_contents(dir)
	var stack_v1: GSTStack = GSTStack.new()
	stack_v1.next_id = 111
	var write1: Dictionary = GSTDocumentRecovery.write_record(dir, stack_v1, "", false, "", false, false)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var previous_index_file: FileAccess = FileAccess.open(index_path, FileAccess.READ)
	var previous_index_content: String = previous_index_file.get_as_text()
	previous_index_file.close()
	var temp_path: String = "%s.tmp" % index_path
	DirAccess.make_dir_absolute(temp_path)
	var stack_v2: GSTStack = GSTStack.new()
	stack_v2.next_id = 222
	var write2: Dictionary = GSTDocumentRecovery.write_record(dir, stack_v2, "", false, "", false, false, String(write1.get("record_id", "")))
	var reopened_index_file: FileAccess = FileAccess.open(index_path, FileAccess.READ)
	var index_after_failure: String = reopened_index_file.get_as_text()
	reopened_index_file.close()
	var preserved_ok: bool = (
		bool(write1.get("ok", false)) and not bool(write2.get("ok", false)) and not String(write2.get("reason", "")).is_empty()
		and index_after_failure == previous_index_content
	)
	_check("write_record_metadata_failure_preserves_previous_index", preserved_ok, "write1=%s write2=%s unchanged=%s" % [write1, write2, index_after_failure == previous_index_content])
	DirAccess.remove_absolute(temp_path)
	_wipe_dir_contents(dir)


## Asserts a metadata-write failure through _recover_document leaves doc
## without a recovery record and needs_shutdown_attention() true.
func _check_metadata_write_failure_leaves_document_needing_attention(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	var base: String = ProjectSettings.globalize_path("user://gst_recovery_metadata_failure_attention_check")
	_wipe_dir_contents(base)
	var dir: String = GSTDocumentRecovery.recovery_dir(base)
	DirAccess.make_dir_recursive_absolute(dir)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	DirAccess.make_dir_absolute("%s.tmp" % index_path)
	panel._recover_document(doc, dir, "")
	var attention_ok: bool = doc.recovery_record_id.is_empty() and doc.recovery_fingerprint.is_empty() and doc.needs_shutdown_attention()
	_check("metadata_write_failure_leaves_document_needing_attention", attention_ok, "recovery_record_id='%s' recovery_fingerprint='%s' needs_attention=%s" % [doc.recovery_record_id, doc.recovery_fingerprint, doc.needs_shutdown_attention()])
	_wipe_dir_contents(base)
	await panel.close_document(doc)
	if panel.is_close_dialog_visible():
		panel._on_close_custom_action("discard")
		await plugin.get_tree().process_frame


## Asserts an index.json or record entry with an unknown version is
## rejected: load_all reports one failure by the index path with zero
## records; write_record quarantines it by rename. The referenced stack file
## survives untouched.
func _check_unknown_index_version_rejected(panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_readside_unknown_version")
	_wipe_dir_contents(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var stack_path: String = dir.path_join("planted.tres")
	var index_file: FileAccess = FileAccess.open(index_path, FileAccess.WRITE)
	index_file.store_string(JSON.stringify({"version": 99, "records": [{"id": "planted", "version": 99, "stack_file": "planted.tres", "original_path": "", "recipe_open": false, "recipe_name": "", "reopened_import": false, "save_failed": false, "created_unix": 0}]}))
	index_file.close()
	var stack_file: FileAccess = FileAccess.open(stack_path, FileAccess.WRITE)
	stack_file.store_string("planted stack content")
	stack_file.close()
	var loaded: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var failures: Array = loaded.get("failures", []) as Array
	var records: Array = loaded.get("records", []) as Array
	var load_rejected_ok: bool = records.is_empty() and failures.size() == 1 and String((failures[0] as Dictionary).get("path", "")) == index_path
	var write_result: Dictionary = GSTDocumentRecovery.write_record(dir, GSTStack.new(), "", false, "", false, false)
	var quarantined_path: String = String(write_result.get("quarantined_path", ""))
	var quarantine_ok: bool = bool(write_result.get("ok", false)) and not quarantined_path.is_empty() and FileAccess.file_exists(quarantined_path) and FileAccess.file_exists(index_path) and FileAccess.file_exists(stack_path)
	_check("unknown_index_version_rejected_by_load_and_quarantined_by_write", load_rejected_ok and quarantine_ok, "failures=%s write_result=%s planted_stack_preserved=%s" % [failures, write_result, FileAccess.file_exists(stack_path)])
	_wipe_dir_contents(dir)


## Asserts an index entry whose stack_file escapes the recovery directory
## ("../x.tres") is rejected by load_all and remove_record; the targeted
## file and the index entry both survive.
func _check_stack_file_traversal_rejected(panel: GSTMainPanel) -> void:
	var base_dir: String = ProjectSettings.globalize_path("user://gst_recovery_readside_traversal")
	_wipe_dir_contents(base_dir)
	var dir: String = base_dir.path_join("inner")
	DirAccess.make_dir_recursive_absolute(dir)
	var outside_path: String = base_dir.path_join("escaped.tres")
	var outside_file: FileAccess = FileAccess.open(outside_path, FileAccess.WRITE)
	outside_file.store_string("must never be touched")
	outside_file.close()
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var malicious_stack_file: String = "../escaped.tres"
	var index_file: FileAccess = FileAccess.open(index_path, FileAccess.WRITE)
	index_file.store_string(JSON.stringify({"version": GSTDocumentRecovery.SCHEMA_VERSION, "records": [{"id": "traversal", "version": GSTDocumentRecovery.SCHEMA_VERSION, "stack_file": malicious_stack_file, "original_path": "", "recipe_open": false, "recipe_name": "", "reopened_import": false, "save_failed": false, "created_unix": 0}]}))
	index_file.close()
	var loaded: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var failures: Array = loaded.get("failures", []) as Array
	var records: Array = loaded.get("records", []) as Array
	var load_rejected_ok: bool = records.is_empty() and failures.size() == 1 and String((failures[0] as Dictionary).get("id", "")) == "traversal" and FileAccess.file_exists(outside_path)
	GSTDocumentRecovery.remove_record(dir, "traversal")
	var outside_survived: bool = FileAccess.file_exists(outside_path)
	var index_after_remove: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var entry_still_present: bool = (index_after_remove.get("failures", []) as Array).size() == 1
	_check("stack_file_traversal_rejected_by_load_and_remove", load_rejected_ok and outside_survived and entry_still_present, "failures=%s outside_survived=%s entry_still_present=%s" % [failures, outside_survived, entry_still_present])
	_wipe_dir_contents(base_dir)


## Asserts a record whose `id` ("../victim") disagrees with its `stack_file`
## ("safe.tres") is rejected before write_record derives a stack_file from
## `id` alone ("%s.tres" % id), which would write outside the recovery
## directory. Plants the file that derived path resolves to one directory
## above `dir`, plus the entry's own `safe.tres`. load_all must reject by
## path; _recover_document with that id as recovery_record_id must leave the
## outside file and index.json byte-identical.
func _check_record_id_traversal_rejected_before_write(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var base_dir: String = ProjectSettings.globalize_path("user://gst_recovery_id_traversal")
	_wipe_dir_contents(base_dir)
	var dir: String = base_dir.path_join("inner")
	DirAccess.make_dir_recursive_absolute(dir)
	var outside_path: String = base_dir.path_join("victim.tres")
	var outside_file: FileAccess = FileAccess.open(outside_path, FileAccess.WRITE)
	outside_file.store_string("must never be touched")
	outside_file.close()
	var safe_stack_path: String = dir.path_join("safe.tres")
	var safe_stack: GSTStack = GSTStack.new()
	safe_stack.next_id = 7
	ResourceSaver.save(safe_stack, safe_stack_path)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var index_file: FileAccess = FileAccess.open(index_path, FileAccess.WRITE)
	index_file.store_string(JSON.stringify({"version": GSTDocumentRecovery.SCHEMA_VERSION, "records": [{"id": "../victim", "version": GSTDocumentRecovery.SCHEMA_VERSION, "stack_file": "safe.tres", "original_path": "", "recipe_open": false, "recipe_name": "", "reopened_import": false, "save_failed": false, "created_unix": 0}]}))
	index_file.close()
	var outside_before: String = _read_file_text(outside_path)
	var index_before: String = _read_file_text(index_path)

	var loaded: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var failures: Array = loaded.get("failures", []) as Array
	var records: Array = loaded.get("records", []) as Array
	var load_rejected_ok: bool = records.is_empty() and failures.size() == 1 and String((failures[0] as Dictionary).get("id", "")) == "../victim" and String((failures[0] as Dictionary).get("path", "")) == safe_stack_path

	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	doc.recovery_record_id = "../victim"
	panel._recover_document(doc, dir, "")

	var outside_after: String = _read_file_text(outside_path)
	var index_after: String = _read_file_text(index_path)
	var shutdown_rejected_ok: bool = (
		outside_after == outside_before and index_after == index_before
		and doc.recovery_fingerprint.is_empty() and doc.needs_shutdown_attention()
	)
	_check("record_id_traversal_rejected_by_load_and_write", load_rejected_ok and shutdown_rejected_ok, "failures=%s outside_unchanged=%s index_unchanged=%s needs_attention=%s" % [failures, outside_after == outside_before, index_after == index_before, doc.needs_shutdown_attention()])
	await panel.close_document(doc)
	if panel.is_close_dialog_visible():
		panel._on_close_custom_action("discard")
		await plugin.get_tree().process_frame
	_wipe_dir_contents(base_dir)


## Asserts an index-level `version` of `1.5` is rejected by load_all
## (reported by the index path, planted stack untouched); `int(value)`
## truncation would accept it.
func _check_fractional_index_version_rejected(panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_fractional_index_version")
	_wipe_dir_contents(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var stack_path: String = dir.path_join("planted.tres")
	var index_file: FileAccess = FileAccess.open(index_path, FileAccess.WRITE)
	index_file.store_string('{"version": 1.5, "records": [{"id": "planted", "version": 1, "stack_file": "planted.tres", "original_path": "", "recipe_open": false, "recipe_name": "", "reopened_import": false, "save_failed": false, "created_unix": 0}]}')
	index_file.close()
	var stack_file: FileAccess = FileAccess.open(stack_path, FileAccess.WRITE)
	stack_file.store_string("planted stack content")
	stack_file.close()
	var loaded: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var failures: Array = loaded.get("failures", []) as Array
	var records: Array = loaded.get("records", []) as Array
	var rejected_ok: bool = records.is_empty() and failures.size() == 1 and String((failures[0] as Dictionary).get("path", "")) == index_path and FileAccess.file_exists(stack_path)
	_check("fractional_index_version_1_5_rejected", rejected_ok, "failures=%s planted_stack_preserved=%s" % [failures, FileAccess.file_exists(stack_path)])
	_wipe_dir_contents(dir)


## Asserts a record-level `version` of `1.5` is rejected by
## `_validate_record` (shared by `load_all` and `remove_record`) with a
## valid index-level version, reported by the entry's id.
func _check_fractional_record_version_rejected(panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_fractional_record_version")
	_wipe_dir_contents(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var stack_path: String = dir.path_join("planted.tres")
	var index_file: FileAccess = FileAccess.open(index_path, FileAccess.WRITE)
	index_file.store_string('{"version": 1, "records": [{"id": "planted", "version": 1.5, "stack_file": "planted.tres", "original_path": "", "recipe_open": false, "recipe_name": "", "reopened_import": false, "save_failed": false, "created_unix": 0}]}')
	index_file.close()
	var stack_file: FileAccess = FileAccess.open(stack_path, FileAccess.WRITE)
	stack_file.store_string("planted stack content")
	stack_file.close()
	var loaded: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var failures: Array = loaded.get("failures", []) as Array
	var records: Array = loaded.get("records", []) as Array
	var rejected_ok: bool = records.is_empty() and failures.size() == 1 and String((failures[0] as Dictionary).get("id", "")) == "planted" and FileAccess.file_exists(stack_path)
	_check("fractional_record_version_1_5_rejected", rejected_ok, "failures=%s planted_stack_preserved=%s" % [failures, FileAccess.file_exists(stack_path)])
	_wipe_dir_contents(dir)


## Asserts `1.0` is accepted at index and record level: Godot's `JSON.parse`
## resolves any number with a decimal point to `float`, and
## `_is_supported_version` compares its float branch against
## `float(SCHEMA_VERSION)`.
func _check_float_whole_number_version_accepted(panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_float_whole_version")
	_wipe_dir_contents(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var stack_path: String = dir.path_join("planted.tres")
	var stack: GSTStack = GSTStack.new()
	stack.next_id = 42
	ResourceSaver.save(stack, stack_path)
	var index_file: FileAccess = FileAccess.open(index_path, FileAccess.WRITE)
	index_file.store_string('{"version": 1.0, "records": [{"id": "planted", "version": 1.0, "stack_file": "planted.tres", "original_path": "", "recipe_open": false, "recipe_name": "", "reopened_import": false, "save_failed": false, "created_unix": 0}]}')
	index_file.close()
	var loaded: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var failures: Array = loaded.get("failures", []) as Array
	var records: Array = loaded.get("records", []) as Array
	var entry: Dictionary = records[0] as Dictionary if records.size() == 1 else {}
	var loaded_stack: GSTStack = entry.get("stack") as GSTStack
	var accepted_ok: bool = failures.is_empty() and records.size() == 1 and String(entry.get("id", "")) == "planted" and loaded_stack != null and loaded_stack.next_id == 42
	_check("float_whole_number_version_1_0_accepted", accepted_ok, "failures=%s records=%d" % [failures, records.size()])
	_wipe_dir_contents(dir)


## Asserts write_record's existing_id path validates the indexed record
## before touching its stack file or index entry. Three planted shapes, each
## in its own directory: (a) record-level "version" 1.5; (b) index-level
## "version" 1.5; (c) "stack_file" ("other.tres") disagreeing with "id"
## ("planted"). Each case calls write_record directly (ok=false, reason
## names the index path and record id, both planted files byte-identical),
## then _recover_document with that id as recovery_record_id (same
## preservation, needs_shutdown_attention() true).
## Also asserts the fresh-record quarantine path (no existing_id, unreadable
## index) still quarantines and reports.
func _check_existing_record_validated_before_write(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	await _check_existing_record_case(plugin, panel, "gst_recovery_existing_record_version", "existing_record_level_version_1_5_rejected",
		'{"version": 1, "records": [{"id": "planted", "version": 1.5, "stack_file": "planted.tres", "original_path": "", "recipe_open": false, "recipe_name": "", "reopened_import": false, "save_failed": false, "created_unix": 0}]}',
		"planted.tres")
	await _check_existing_record_case(plugin, panel, "gst_recovery_existing_index_version", "existing_index_level_version_1_5_rejected",
		'{"version": 1.5, "records": [{"id": "planted", "version": 1, "stack_file": "planted.tres", "original_path": "", "recipe_open": false, "recipe_name": "", "reopened_import": false, "save_failed": false, "created_unix": 0}]}',
		"planted.tres")
	await _check_existing_record_case(plugin, panel, "gst_recovery_existing_identity_mismatch", "existing_record_identity_mismatch_rejected",
		'{"version": 1, "records": [{"id": "planted", "version": 1, "stack_file": "other.tres", "original_path": "", "recipe_open": false, "recipe_name": "", "reopened_import": false, "save_failed": false, "created_unix": 0}]}',
		"other.tres")
	_check_fresh_record_quarantine_path_still_works_after_existing_record_fix(panel)


## Plants `index_json` and `stack_file_name` under a fresh directory,
## snapshots both, calls write_record with existing id "planted", then
## _recover_document with a document carrying "planted" as
## recovery_record_id; asserts both files byte-identical and neither call
## claims success.
func _check_existing_record_case(plugin: EditorPlugin, panel: GSTMainPanel, dir_name: String, check_name: String, index_json: String, stack_file_name: String) -> void:
	var dir: String = ProjectSettings.globalize_path("user://%s" % dir_name)
	_wipe_dir_contents(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var stack_path: String = dir.path_join(stack_file_name)
	var index_file: FileAccess = FileAccess.open(index_path, FileAccess.WRITE)
	index_file.store_string(index_json)
	index_file.close()
	var stack_file: FileAccess = FileAccess.open(stack_path, FileAccess.WRITE)
	stack_file.store_string("planted existing record content for %s" % check_name)
	stack_file.close()
	var index_before: String = _read_file_text(index_path)
	var stack_before: String = _read_file_text(stack_path)

	var overwrite_stack: GSTStack = GSTStack.new()
	overwrite_stack.next_id = 777
	var write_result: Dictionary = GSTDocumentRecovery.write_record(dir, overwrite_stack, "", false, "", false, false, "planted")
	var write_reason: String = String(write_result.get("reason", ""))
	var write_rejected_ok: bool = (
		not bool(write_result.get("ok", false)) and write_reason.contains(index_path) and write_reason.contains("planted")
		and _read_file_text(index_path) == index_before and _read_file_text(stack_path) == stack_before
	)

	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	doc.recovery_record_id = "planted"
	panel._recover_document(doc, dir, "")
	var recover_rejected_ok: bool = (
		_read_file_text(index_path) == index_before and _read_file_text(stack_path) == stack_before
		and doc.recovery_fingerprint.is_empty() and doc.needs_shutdown_attention()
	)
	_check(check_name, write_rejected_ok and recover_rejected_ok, "write_result=%s recover_needs_attention=%s index_unchanged=%s stack_unchanged=%s" % [write_result, doc.needs_shutdown_attention(), _read_file_text(index_path) == index_before, _read_file_text(stack_path) == stack_before])
	await panel.close_document(doc)
	if panel.is_close_dialog_visible():
		panel._on_close_custom_action("discard")
		await plugin.get_tree().process_frame
	_wipe_dir_contents(dir)


func _check_fresh_record_quarantine_path_still_works_after_existing_record_fix(panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_existing_record_fresh_quarantine_recheck")
	_wipe_dir_contents(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var index_file: FileAccess = FileAccess.open(index_path, FileAccess.WRITE)
	index_file.store_string("{ this is not valid json")
	index_file.close()
	var write_result: Dictionary = GSTDocumentRecovery.write_record(dir, GSTStack.new(), "", false, "", false, false)
	var quarantined_path: String = String(write_result.get("quarantined_path", ""))
	var quarantine_still_works_ok: bool = (
		bool(write_result.get("ok", false)) and not quarantined_path.is_empty()
		and FileAccess.file_exists(quarantined_path) and FileAccess.file_exists(index_path)
	)
	_check("existing_record_fix_preserves_fresh_record_quarantine_path", quarantine_still_works_ok, "write_result=%s" % [write_result])
	_wipe_dir_contents(dir)


## Planted on-disk corruption cases load_all() must report by path rather
## than resolve to zero records or throw out of _ready() (a non-array
## "records" field threw "Invalid cast: could not convert value to
## 'Array'"). Each runs in its own directory and writes the index.json by
## hand, never through write_record.
func _check_read_side_failures(panel: GSTMainPanel) -> void:
	_check_corrupt_stack_with_valid_index_entry(panel)
	_check_unparseable_index_json(panel)
	_check_non_array_records_field(panel)
	_check_quarantine_reported_at_write_time(panel)
	_check_preexisting_quarantine_reported_on_load(panel)


## Asserts a corrupt .tres with a valid index entry is reported by its stack
## path; the corrupt file and index.json are left on disk.
func _check_corrupt_stack_with_valid_index_entry(panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_readside_corrupt_stack")
	_wipe_dir_contents(dir)
	var stack: GSTStack = GSTStack.new()
	stack.next_id = 5
	var write_result: Dictionary = GSTDocumentRecovery.write_record(dir, stack, "res://original.tres", false, "", false, false)
	var stack_path: String = String(write_result.get("stack_path", ""))
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var corrupt_file: FileAccess = FileAccess.open(stack_path, FileAccess.WRITE)
	corrupt_file.store_string("not a valid GSTStack resource")
	corrupt_file.close()
	var loaded: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var failures: Array = loaded.get("failures", []) as Array
	var records: Array = loaded.get("records", []) as Array
	var reported_ok: bool = failures.size() == 1 and String((failures[0] as Dictionary).get("path", "")) == stack_path
	var planted_preserved: bool = FileAccess.file_exists(stack_path) and FileAccess.file_exists(index_path)
	_check("readside_corrupt_stack_with_valid_index_entry", bool(write_result.get("ok", false)) and records.is_empty() and reported_ok and planted_preserved, "write_result=%s failures=%s planted_preserved=%s" % [write_result, failures, planted_preserved])
	_wipe_dir_contents(dir)


## Asserts an index.json that fails JSON parsing (e.g. truncated mid-write)
## is reported by its path rather than read as an absent index.
func _check_unparseable_index_json(panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_readside_unparseable_index")
	_wipe_dir_contents(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var file: FileAccess = FileAccess.open(index_path, FileAccess.WRITE)
	file.store_string("{ this is not valid json")
	file.close()
	var loaded: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var failures: Array = loaded.get("failures", []) as Array
	var records: Array = loaded.get("records", []) as Array
	var reported_ok: bool = failures.size() == 1 and String((failures[0] as Dictionary).get("path", "")) == index_path
	var planted_preserved: bool = FileAccess.file_exists(index_path)
	_check("readside_unparseable_index_json", records.is_empty() and reported_ok and planted_preserved, "failures=%s planted_preserved=%s" % [failures, planted_preserved])
	_wipe_dir_contents(dir)


## Asserts a JSON object whose "records" field is not an Array is reported
## by the index path rather than throwing out of load_all().
func _check_non_array_records_field(panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_readside_non_array_records")
	_wipe_dir_contents(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var file: FileAccess = FileAccess.open(index_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": GSTDocumentRecovery.SCHEMA_VERSION, "records": "not_an_array"}))
	file.close()
	var loaded: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var failures: Array = loaded.get("failures", []) as Array
	var records: Array = loaded.get("records", []) as Array
	var reported_ok: bool = failures.size() == 1 and String((failures[0] as Dictionary).get("path", "")) == index_path
	var planted_preserved: bool = FileAccess.file_exists(index_path)
	_check("readside_non_array_records_field", records.is_empty() and reported_ok and planted_preserved, "failures=%s planted_preserved=%s" % [failures, planted_preserved])
	_wipe_dir_contents(dir)


## Asserts write_record quarantines a pre-existing unreadable index.json and
## returns the quarantined path in its result. Plants a truncated index.json
## plus an orphan.tres that only the lost index referenced; both must remain
## on disk.
func _check_quarantine_reported_at_write_time(panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_readside_quarantine_write")
	_wipe_dir_contents(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	var orphan_stack_path: String = dir.path_join("orphan.tres")
	var index_file: FileAccess = FileAccess.open(index_path, FileAccess.WRITE)
	index_file.store_string("{ this is not valid json")
	index_file.close()
	var orphan_file: FileAccess = FileAccess.open(orphan_stack_path, FileAccess.WRITE)
	orphan_file.store_string("orphaned stack referenced only by the now-unreadable index")
	orphan_file.close()
	var write_result: Dictionary = GSTDocumentRecovery.write_record(dir, GSTStack.new(), "", false, "", false, false)
	var quarantined_path: String = String(write_result.get("quarantined_path", ""))
	# write_record returns ok=true: after quarantining, it writes a fresh
	# index.json holding this call's entry, so index_path exists again.
	var quarantine_ok: bool = (
		bool(write_result.get("ok", false)) and not quarantined_path.is_empty()
		and quarantined_path.begins_with(index_path) and quarantined_path.contains(".unreadable-")
		and quarantined_path != index_path
		and FileAccess.file_exists(quarantined_path) and FileAccess.file_exists(index_path)
		and FileAccess.file_exists(orphan_stack_path)
	)
	_check("quarantine_reported_at_write_time", quarantine_ok, "write_result=%s orphan_preserved=%s" % [write_result, FileAccess.file_exists(orphan_stack_path)])
	_wipe_dir_contents(dir)


## Asserts a pre-existing index.json.unreadable-* file is reported by
## load_all on every call, since nothing removes it.
func _check_preexisting_quarantine_reported_on_load(panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_readside_preexisting_quarantine")
	_wipe_dir_contents(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var quarantined_path: String = dir.path_join("%s.unreadable-1789198480" % GSTDocumentRecovery.METADATA_FILE)
	var quarantined_file: FileAccess = FileAccess.open(quarantined_path, FileAccess.WRITE)
	quarantined_file.store_string("{ this is not valid json")
	quarantined_file.close()
	var loaded_first: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var loaded_second: Dictionary = GSTDocumentRecovery.load_all(dir, panel.get_library())
	var failures_first: Array = loaded_first.get("failures", []) as Array
	var failures_second: Array = loaded_second.get("failures", []) as Array
	var reported_first: bool = failures_first.size() == 1 and String((failures_first[0] as Dictionary).get("path", "")) == quarantined_path
	var reported_second: bool = failures_second.size() == 1 and String((failures_second[0] as Dictionary).get("path", "")) == quarantined_path
	var planted_preserved: bool = FileAccess.file_exists(quarantined_path)
	_check("preexisting_quarantine_reported_on_every_load", reported_first and reported_second and planted_preserved, "failures_first=%s failures_second=%s planted_preserved=%s" % [failures_first, failures_second, planted_preserved])
	_wipe_dir_contents(dir)


## Asserts write_record reports ok=false when index.json has been replaced by
## a directory after a first successful write. Runs in a throwaway
## directory, not the live recovery dir _run_initial uses.
func _check_metadata_write_failure_does_not_silently_succeed(panel: GSTMainPanel) -> void:
	var dir: String = ProjectSettings.globalize_path("user://gst_recovery_metadata_failure_check")
	_wipe_dir_contents(dir)
	var stack_v1: GSTStack = GSTStack.new()
	stack_v1.next_id = 11
	var write1: Dictionary = GSTDocumentRecovery.write_record(dir, stack_v1, "", false, "", false, false)
	var record_id: String = String(write1.get("record_id", ""))
	var index_path: String = dir.path_join(GSTDocumentRecovery.METADATA_FILE)
	DirAccess.remove_absolute(index_path)
	DirAccess.make_dir_absolute(index_path)
	var stack_v2: GSTStack = GSTStack.new()
	stack_v2.next_id = 22
	var write2: Dictionary = GSTDocumentRecovery.write_record(dir, stack_v2, "", false, "", false, false, record_id)
	_check("metadata_write_failure_does_not_silently_succeed", bool(write1.get("ok", false)) and not record_id.is_empty() and not bool(write2.get("ok", false)) and not String(write2.get("reason", "")).is_empty(), "write1=%s write2=%s" % [write1, write2])
	_wipe_dir_contents(dir)


func _settle_editor(plugin: EditorPlugin) -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	var clear_frames: int = 0
	while Time.get_ticks_msec() < deadline:
		if _has_startup_modal(plugin.get_tree().root):
			clear_frames = 0
		else:
			clear_frames += 1
		if clear_frames >= 30:
			return true
		await plugin.get_tree().process_frame
	return not _has_startup_modal(plugin.get_tree().root)


func _has_startup_modal(node: Node) -> bool:
	if node is Label:
		var label: Label = node as Label
		var text: String = label.text.to_lower()
		if label.is_visible_in_tree() and (text.contains("loading editor") or text.contains("importing") or text.contains("pre-import") or text.contains("scanning files") or text.contains("please wait")):
			return true
	for child: Node in node.get_children():
		if _has_startup_modal(child):
			return true
	return false


## Godot 4.4's editor top bar is a MenuBar (EditorTitleBar); "Quit" is an
## item of its "Scene" menu, and PopupMenu.id_pressed is the signal
## EditorNode's _menu_option connects to for a click or Ctrl+Shift+Q alike.
## A synthetic InputEventKey through push_input does not reach that shortcut
## in this environment, so the menu's id_pressed is emitted directly.
func _drive_confirmed_quit(plugin: EditorPlugin) -> void:
	await _settle_editor(plugin)
	var bar: MenuBar = _find_menu_bar(plugin.get_tree().root)
	if bar == null:
		_check("quit_confirmation", false, "EditorTitleBar's own MenuBar was not found")
		_finish(plugin)
		return
	var quit_result: Dictionary = _find_menu_item_id(bar, "Scene", "Quit")
	if not bool(quit_result.get("found", false)):
		_check("quit_confirmation", false, "Scene menu's own Quit item was not found")
		_finish(plugin)
		return
	var scene_popup: PopupMenu = quit_result["popup"] as PopupMenu
	# Emitted once: EditorNode builds/reuses the ConfirmationDialog on every
	# "Quit" activation; re-emitting while waiting re-triggers the handler
	# mid-build.
	scene_popup.id_pressed.emit(int(quit_result["id"]))
	var dialog: ConfirmationDialog = null
	for attempt: int in range(6):
		await _frames(plugin, 30)
		dialog = _find_quit_dialog(plugin.get_tree().root)
		if dialog != null and dialog.visible:
			break
	if dialog == null or not dialog.visible:
		_dump_visible_windows(plugin.get_tree().root)
		_check("quit_confirmation", false, "Scene > Quit did not expose a visible ConfirmationDialog")
		_finish(plugin)
		return
	var status_text: String = _visible_dialog_text(dialog)
	_check("quit_confirmation", status_text.contains("quit_named_failed"), "text='%s'" % [status_text])
	var save_quit: Button = _find_button(dialog, "Save and Quit")
	if save_quit == null:
		save_quit = _find_button(dialog, "Save & Quit")
	if save_quit == null:
		_check("save_and_quit_control", false, "Save and Quit button was absent")
		_finish(plugin)
		return
	_check("save_and_quit_control", true, "button='%s'" % [save_quit.text])
	# Click through the dialog's own embedded Window/Viewport: a focused
	# Enter key and a direct pressed.emit() both ran _save_external_data()
	# but never closed the dialog or exited the process.
	await _click_button(plugin, save_quit)
	print("SMOKE_RECOVERY SAVE_AND_QUIT_ACTIVATION_DISPATCHED")


## Stage 2: the editor session reopened after the confirmed quit.
## load_recovery_records() already ran from the panel's _ready() before this
## script gets control.
func _verify_fresh_open(plugin: EditorPlugin, panel: GSTMainPanel, stage: Dictionary) -> void:
	var dir: String = panel.get_recovery_dir()
	var untitled_marker: int = int(stage.get("untitled_marker", -1))
	var named_failed_marker: int = int(stage.get("named_failed_marker", -1))
	var named_failed_path: String = String(stage.get("named_failed_path", ""))

	var start_screen_hidden: bool = not panel.is_start_screen_visible()
	var docs: Array[GSTDocument] = panel.get_documents()
	var recovered_untitled: GSTDocument = _find_by_marker(docs, untitled_marker)
	var recovered_failed: GSTDocument = _find_by_marker(docs, named_failed_marker)
	var untitled_ok: bool = recovered_untitled != null and recovered_untitled.is_dirty() and recovered_untitled.current_path.is_empty()
	var failed_ok: bool = recovered_failed != null and recovered_failed.is_dirty() and recovered_failed.current_path == named_failed_path
	_check("restoration_before_entry", start_screen_hidden and untitled_ok and failed_ok, "start_screen_hidden=%s untitled_ok=%s failed_ok=%s document_count=%d" % [start_screen_hidden, untitled_ok, failed_ok, docs.size()])
	print("SMOKE_RECOVERY recovery_dir=%s listing_after_reopen=%s" % [dir, _list_dir(dir)])

	var fixed_path: String = "user://gst_recovery_quit_untitled_saved.tres"
	_cleanup_paths([fixed_path])
	var save_result: Dictionary = {}
	if recovered_untitled != null:
		save_result = await panel._save_stack_to_path(recovered_untitled, fixed_path)
	var save_ok: bool = recovered_untitled != null and bool(save_result.get("ok", false)) and not recovered_untitled.is_dirty() and recovered_untitled.recovery_record_id.is_empty()
	_check("post_restart_save_cleanup", save_ok, "save_result=%s" % [save_result])

	var discard_ok: bool = false
	if recovered_failed != null:
		await panel.close_document(recovered_failed)
		var dialog_shown: bool = panel.is_close_dialog_visible()
		if dialog_shown:
			panel._on_close_custom_action("discard")
			await plugin.get_tree().process_frame
		discard_ok = dialog_shown and not panel.get_documents().has(recovered_failed)
	_check("post_restart_discard_cleanup", discard_ok, "discard_ok=%s" % [discard_ok])

	var final_records: Array = (GSTDocumentRecovery.load_all(dir, panel.get_library()).get("records", []) as Array)
	_check("recovery_dir_empty_after_final_cleanup", final_records.is_empty(), "remaining=%d listing=%s" % [final_records.size(), _list_dir(dir)])

	_cleanup_paths([fixed_path])
	_unblock(BLOCKED_PARENT)
	# A passing stage 2 deletes the stage file so the next invocation starts
	# as stage 1. A failed run leaves it for diagnosis.
	if _fail_count == 0:
		_delete_stage()
	_finish(plugin)


func _find_by_marker(docs: Array[GSTDocument], marker: int) -> GSTDocument:
	for doc: GSTDocument in docs:
		if doc.stack != null and doc.stack.next_id == marker:
			return doc
	return null


func _find_entry(records: Array, record_id: String) -> Dictionary:
	for raw: Variant in records:
		if raw is Dictionary and String((raw as Dictionary).get("id", "")) == record_id:
			return raw as Dictionary
	return {}


func _make_blocked_parent(dir_path: String) -> void:
	var globalized: String = ProjectSettings.globalize_path(dir_path)
	if FileAccess.file_exists(globalized):
		return
	if DirAccess.dir_exists_absolute(globalized):
		_remove_dir_recursive(globalized)
	var blocker: FileAccess = FileAccess.open(globalized, FileAccess.WRITE)
	if blocker != null:
		blocker.store_string("file blocks child path")
		blocker.close()


func _unblock(dir_path: String) -> void:
	var globalized: String = ProjectSettings.globalize_path(dir_path)
	if FileAccess.file_exists(globalized):
		DirAccess.remove_absolute(globalized)


func _wipe_dir_contents(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		_remove_dir_recursive(dir)


func _remove_dir_recursive(path: String) -> void:
	var access: DirAccess = DirAccess.open(path)
	if access != null:
		access.list_dir_begin()
		var name: String = access.get_next()
		while name != "":
			if name != "." and name != "..":
				var full: String = path.path_join(name)
				if access.current_is_dir():
					_remove_dir_recursive(full)
				else:
					access.remove(name)
			name = access.get_next()
		access.list_dir_end()
	DirAccess.remove_absolute(path)


func _list_dir(dir: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var access: DirAccess = DirAccess.open(dir)
	if access == null:
		return result
	access.list_dir_begin()
	var name: String = access.get_next()
	while name != "":
		if name != "." and name != "..":
			result.append(name)
		name = access.get_next()
	access.list_dir_end()
	return result


## Returns "" for an absent file; used only for byte-identical before/after
## comparison of files the caller knows exist.
func _read_file_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _cleanup_paths(paths: Array) -> void:
	for path: Variant in paths:
		var path_string: String = String(path)
		if FileAccess.file_exists(path_string):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path_string))


func _stage_path() -> String:
	return EditorInterface.get_editor_paths().get_project_settings_dir().path_join(STAGE_FILE)


func _read_stage() -> Dictionary:
	var file: FileAccess = FileAccess.open(_stage_path(), FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _delete_stage() -> void:
	if FileAccess.file_exists(_stage_path()):
		DirAccess.remove_absolute(_stage_path())


func _write_stage(value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_stage_path(), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value))
		file.close()


func _dump_visible_windows(node: Node) -> void:
	if node is Window and (node as Window).visible:
		var labels: PackedStringArray = []
		for label_node: Node in node.find_children("*", "Label", true, false):
			var label: Label = label_node as Label
			if label.visible and not label.text.is_empty():
				labels.append(label.text)
		var buttons: PackedStringArray = []
		for button_node: Node in node.find_children("*", "Button", true, false):
			var button: Button = button_node as Button
			if button.visible and not button.text.is_empty():
				buttons.append(button.text)
		print("SMOKE_RECOVERY visible_window class=%s title=%s labels=%s buttons=%s" % [node.get_class(), (node as Window).title, labels, buttons])
	for child: Node in node.get_children():
		_dump_visible_windows(child)


func _find_menu_bar(node: Node) -> MenuBar:
	if node.get_class() == "MenuBar":
		return node as MenuBar
	for child: Node in node.get_children():
		var found: MenuBar = _find_menu_bar(child)
		if found != null:
			return found
	return null


## `{found: bool, popup: PopupMenu, id: int}` for the menu_title item whose
## text is exactly item_text. Looked up by text; MenuBar reassigns ids per
## build/version.
func _find_menu_item_id(bar: MenuBar, menu_title: String, item_text: String) -> Dictionary:
	for i: int in range(bar.get_menu_count()):
		if bar.get_menu_title(i) != menu_title:
			continue
		var popup: PopupMenu = bar.get_menu_popup(i)
		for j: int in range(popup.item_count):
			if popup.get_item_text(j) == item_text:
				return {"found": true, "popup": popup, "id": popup.get_item_id(j)}
	return {"found": false}


func _find_quit_dialog(node: Node) -> ConfirmationDialog:
	if node is ConfirmationDialog:
		var dialog: ConfirmationDialog = node as ConfirmationDialog
		if _find_button(dialog, "Save and Quit") != null or _find_button(dialog, "Save & Quit") != null:
			return dialog
	for child: Node in node.get_children():
		var found: ConfirmationDialog = _find_quit_dialog(child)
		if found != null:
			return found
	return null


## find_children, not get_children(): AcceptDialog's message Label/
## HBoxContainer/Buttons are internal children, which get_children()
## excludes by default.
func _find_button(node: Node, text: String) -> Button:
	for child: Node in node.find_children("*", "Button", true, false):
		var button: Button = child as Button
		if button.visible and button.text == text:
			return button
	return null


func _visible_dialog_text(dialog: ConfirmationDialog) -> String:
	for child: Node in dialog.find_children("*", "Label", true, false):
		var label: Label = child as Label
		if not label.text.is_empty():
			return label.text
	return dialog.dialog_text


func _frames(plugin: EditorPlugin, count: int) -> void:
	for i: int in range(count):
		await plugin.get_tree().process_frame


## Click on button's global-rect center through its own Viewport.
## NOTIFICATION_MOUSE_ENTER is required: BaseButton::on_action_event gates
## on status.hovering, which a synthetic InputEventMouseButton never sets.
## Every await is guarded with is_instance_valid(plugin): clicking "Save and
## Quit" starts the process exit, which frees plugin while this coroutine is
## suspended; resuming would call get_tree() on a freed instance.
func _click_button(plugin: EditorPlugin, button: Button) -> void:
	if button == null or not is_instance_valid(button) or not is_instance_valid(plugin):
		return
	await plugin.get_tree().process_frame
	if not is_instance_valid(plugin):
		return
	var point: Vector2 = button.get_global_rect().get_center()
	button.notification(Control.NOTIFICATION_MOUSE_ENTER)
	_push_mouse(button, point, MOUSE_BUTTON_LEFT, true)
	if not is_instance_valid(plugin):
		return
	await plugin.get_tree().process_frame
	if not is_instance_valid(plugin):
		return
	await plugin.get_tree().process_frame
	if not is_instance_valid(plugin):
		return
	_push_mouse(button, point, MOUSE_BUTTON_LEFT, false)
	if not is_instance_valid(plugin):
		return
	await plugin.get_tree().process_frame
	if not is_instance_valid(plugin):
		return
	await plugin.get_tree().process_frame


func _push_mouse(target: Control, position: Vector2, button_index: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button_index
	event.pressed = pressed
	target.get_viewport().push_input(event, true)


func _check(item: String, ok: bool, detail: String) -> void:
	if ok:
		_pass_count += 1
		print("SMOKE %s PASS %s" % [item, detail])
	else:
		_fail_count += 1
		print("SMOKE %s FAIL %s" % [item, detail])


func _finish(plugin: EditorPlugin) -> void:
	print("SMOKE SUMMARY pass=%d fail=%d" % [_pass_count, _fail_count])
	plugin.get_tree().quit(1 if _fail_count > 0 else 0)
