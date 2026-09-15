@tool
extends RefCounted

## Phase 7 (docs/SHADER_TABS_reviewed-plan.md): confirmed-shutdown save and
## project-local recovery (decision 10, docs/SHADER_TABS_reviewed.md).
## GSTMainPanel.get_recovery_dir() always resolves under *this running
## project's own* settings directory, never a real user's stack/export path
## (Cross-cutting "Recovery files never use a user's original stack/export as
## their destination"); running this whole selector against the isolated
## project under .now/tabs-validation/ (the same convention every earlier
## Shader tabs phase's own evidence already uses, not a separate override
## knob in production) is what keeps every write in this file off a real
## project's own recovery records.
##
## Mirrors tests/gst_editor_document_proof.gd's own two-stage pattern for the
## one check that needs the real, actual confirmed quit to really exit and
## reopen the editor process: a small JSON stage file directly under the
## project's own settings directory (a sibling of goshade_turbo/recovery
## itself, so it is never mistaken for a real record) records which half of
## that real Save-and-Quit round trip this process is. Every other check
## (mixed named/untitled/failed documents, metadata-write failure, retained
## dirty markers, Save/Discard cleanup, nonempty for_scene) runs entirely
## within a single editor session by calling plugin._get_unsaved_status/
## _save_external_data directly -- the exact production callbacks Godot's
## own quit confirmation and scene-close call -- and needs no process
## boundary at all.
##
## The shutdown probe plugin fixture from phase 1
## (tests/fixtures/shader_tabs_shutdown_plugin.cfg/.gd) is deliberately left
## disabled for this whole selector: this phase implements the real thing in
## the production plugin.gd/gst_main_panel.gd, so the probe has nothing left
## to prove and must not also answer the same confirmed-quit dialog.

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


## First (and, in the common no-recovery-record case, only) process: every
## check that fits inside one editor session, ending by preparing two real
## dirty documents and handing off to the real confirmed Ctrl+Shift+Q quit.
func _run_initial(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	# Defensive: a prior aborted run's own leftover recovery record would
	# otherwise have already reopened as its own dirty document during this
	# fresh process's _ready() (production working exactly as intended),
	# before this script ever got control to wipe the on-disk directory
	# below -- discard any such document up front so this run's own record
	# counts start deterministic regardless of a previous run's leftovers.
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

	# A successful recovery write must satisfy Godot's own re-check of every
	# plugin's _get_unsaved_status("") after _save_external_data() returns
	# (confirmed against the real editor: the real confirmed-quit dialog
	# never actually exits the process while that status still reports
	# anything, even though a recovered document is deliberately still
	# is_dirty() for its own tab star/close-confirmation) -- so a document
	# whose recovery record now matches its current content must stop
	# appearing here, while doc_ok (never recovered, just saved normally)
	# was never listed to begin with and still is not.
	var status_after_round1: String = plugin._get_unsaved_status("")
	var status_after_round1_ok: bool = not status_after_round1.contains(doc_failed.current_path.get_file().get_basename()) and doc_failed.is_dirty() and doc_untitled.is_dirty()
	_check("recovered_document_stops_blocking_shutdown_status", status_after_round1_ok, "status='%s' doc_failed_dirty=%s doc_untitled_dirty=%s" % [status_after_round1, doc_failed.is_dirty(), doc_untitled.is_dirty()])

	# --- round 2: repeated shutdown against still-dirty documents updates the
	# same record in place instead of duplicating it (decision 10). ---
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

	# --- Save cleanup removes doc_failed's own record. ---
	var fixed_path: String = "user://gst_recovery_named_failed_fixed.tres"
	_cleanup_paths([fixed_path])
	var save_result: Dictionary = await panel._save_stack_to_path(doc_failed, fixed_path)
	var save_cleanup_ok: bool = bool(save_result.get("ok", false)) and not doc_failed.is_dirty() and doc_failed.recovery_record_id.is_empty()
	_check("save_removes_recovery_record", save_cleanup_ok, "save_result=%s recovery_record_id='%s'" % [save_result, doc_failed.recovery_record_id])

	# --- Discard cleanup removes doc_untitled's own record. ---
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

	# --- Prepare the real confirmed-quit scenario: two fresh dirty documents,
	# one untitled and one whose own current_path is unwritable, identified by
	# a stack.next_id marker a fresh process can look up without depending on
	# any in-memory identity of this one. ---
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

	# Written as "confirmed_quit_complete" directly, not a separate
	# "awaiting" stage: this same process both writes this file and drives
	# the real quit immediately below in the same call chain (no probe
	# fixture's own _save_external_data() to advance a stage on our behalf,
	# unlike tests/gst_editor_document_proof.gd's phase 1 pattern) -- the
	# only process that will ever read this file back is the fresh one
	# after this one actually exits.
	_write_stage({
		"stage": "confirmed_quit_complete",
		"untitled_marker": QUIT_UNTITLED_MARKER,
		"named_failed_marker": QUIT_NAMED_FAILED_MARKER,
		"named_failed_path": QUIT_NAMED_FAILED_PATH,
	})
	print("SMOKE_RECOVERY READY_FOR_CONFIRMED_QUIT")
	await _drive_confirmed_quit(plugin)


## Fix-now round 2, note 2: two dirty untitled documents must render as two
## distinct lines in get_unsaved_status_text(""), matching the tab row's own
## per-document "Untitled %d" numbering (_tab_title, gst_main_panel.gd:1055)
## -- previously both fell through _describe_document's identical "This
## shader" literal, observed verbatim: "unsaved_status_before_quit_lists_
## both PASS status='This shader\nquit_named_failed'" (both untitled lines
## collapsed to the same text with no way to tell the two documents apart).
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
	# A prior run's own last-open scene (Godot's own "reopen scenes on
	# startup") can already have one open before this check ever runs; close
	# it too so the real confirmed-quit dispatch later in this run is never
	# left racing Godot's own separate "save this open scene" handling for a
	# scene GoShade never opened itself. Uses the same MenuBar id_pressed
	# technique as _drive_confirmed_quit's own "Scene > Quit", for the same
	# reason: a synthetic Ctrl+Shift+W InputEventKey stopped reaching this
	# shortcut in this environment exactly like Ctrl+Shift+Q did.
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


## Unit-style round trip of GSTDocumentRecovery's own record schema
## (version, record identity, stack filename resolution, original path, and
## recipe/import origin fields) isolated from the live document graph above,
## in its own throwaway directory.
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


## Decision 10's dual-failure case: a named document whose own save just
## failed AND whose recovery write also fails must never be treated as
## resolved (its own recovery_record_id/recovery_fingerprint stay unset, so
## needs_shutdown_attention() keeps reporting it) -- _recover_document's own
## push_error wording ("could not save %s (%s) or recover it to %s: %s.
## _save_external_data() is void and cannot veto editor shutdown") was
## observed verbatim in stderr during interactive development of this
## selector (both exact paths present); this check exercises the same
## _recover_document production call directly, in its own throwaway
## directory, and asserts the behavioral side effect a test script can
## actually read back.
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


## Fix-now round 2, note 1 (write-time half, exercised through the real
## production call site rather than write_record directly): when a
## document's own confirmed-quit recovery write hits a pre-existing
## unreadable index.json, _recover_document (gst_main_panel.gd:1486-1497)
## must still report the write as recovered (write_record's own quarantine-
## then-fresh-write behavior) AND push_error the quarantined path at that
## same call, so the orphaned index is never silently retained with nothing
## naming it. The push_error text itself is not asserted here (GDScript has
## no script-side stderr capture); observed verbatim in this pass's own
## stderr instead, the same convention the dual-failure check above already
## documents in its own doc comment.
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


## Fix-now round 6, note 1 (S2): an index.json this engine cannot open at all
## must never be treated the same as an absent index.json (no record ever
## written here). Plants that shape as a directory literally named
## "index.json" -- FileAccess.open on a directory fails identically on
## Windows and Linux, the same failure round 3's own metadata-write-failure
## check already reproduces for a blocked .tmp path -- and confirmed directly
## against this engine that FileAccess.file_exists() alone still reads false
## against that same directory, so _load_index also checks DirAccess.
## dir_exists_absolute() before ever calling this a confirmed absence.
## Exercises all three read paths this same planted directory reaches:
## load_all (must report failures by the index's own path, never zero
## records), write_record's own existing-id path (must return ok=false naming
## the index path, writing neither a stack file nor a fresh index.json --
## the pre-fix defect this replaces: silently falling back to "no index has
## ever been written" would have let a fresh write_record call proceed to
## quarantine nothing, since _quarantine_unreadable_index's own rename never
## touches a directory it was never asked to rename, and then attempt to
## write a brand new index.json at a path a directory already occupies), and
## the real _recover_document production call site (must leave doc's own
## recovery identity unset and needs_shutdown_attention() true, matching the
## same shape fix-now round 4's record-id-traversal check already asserts).
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


## Fix-now round 6, note 2 (S2), stack-deletion half: a record whose own
## stack file cannot actually be deleted (its path replaced by a non-empty
## directory -- DirAccess.remove_absolute confirmed directly against this
## engine to fail outright against a non-empty directory, never partially
## succeed) must never be treated as removed. Before this fix, remove_record
## discarded that call's own result outright and dropped the index entry
## regardless -- an orphaned stack a later load_all()/write_record() call had
## no way to rediscover, since nothing in the index named it any more.
## Exercises both the real production call site (_forget_recovery_record)
## and the underlying remove_record directly against the panel's own real
## recovery dir (get_recovery_dir(), the same directory the real confirmed-
## quit flow uses -- _forget_recovery_record itself takes no dir argument),
## asserting the index entry and the blocked path both survive untouched and
## doc's own recovery identity is never cleared.
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


## Fix-now round 6, note 2 (S2), index-replacement half: a metadata rewrite
## that fails after its own stack deletion already succeeded (index.json's
## own .tmp path blocked by a directory, the same technique round 3's own
## write_record metadata-failure check already uses) must be reported too,
## never silently treated as a successful removal. Exercises the real
## _forget_recovery_record production call site against the panel's own real
## recovery dir: doc's own recovery identity must stay set and the real
## index.json's own bytes must stay exactly as they were before this call
## (_write_index's own write-through-a-temp-file-then-rename never touches
## the real file on failure) -- the record's own stack file is a known,
## accepted residual of this exact failure order (deletion already committed
## before the metadata rewrite is attempted; Cross-cutting/this note's own
## framing: "successful Save/Discard already resolves the user's content;
## the defect concerns failed cleanup" -- reporting the failure, not making
## two independent filesystem operations atomic, is this S2 fix's own scope),
## so it is documented here rather than asserted unchanged. Once the .tmp
## block is lifted, closing doc with Discard drives _forget_recovery_record
## a second time and this time it succeeds, leaving the recovery dir clean
## for every check that runs after this one.
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


## write_record's own directory-creation failure (a plain file blocking the
## recovery directory's own ancestor) must report ok=false with a reason
## instead of silently claiming success.
func _check_write_record_directory_failure(panel: GSTMainPanel) -> void:
	var blocked_base: String = ProjectSettings.globalize_path("user://gst_recovery_dir_blocked")
	_make_blocked_parent(blocked_base)
	var dir: String = GSTDocumentRecovery.recovery_dir(blocked_base)
	var result: Dictionary = GSTDocumentRecovery.write_record(dir, GSTStack.new(), "", false, "", false, false)
	_check("write_record_reports_directory_failure", not bool(result.get("ok", false)) and not String(result.get("reason", "")).is_empty(), "result=%s" % [result])
	_unblock(blocked_base)


## Review round 3 required fix (S1): _write_index now writes through
## index.json.tmp then renames it over the real index.json, so a write that
## fails partway must never touch -- and so never truncate -- an index.json a
## prior successful write_record call already produced. Blocking the exact
## temp path with a directory reproduces a real write failure deterministically
## (FileAccess.open on the temp path returns null) while the real index.json
## stays a normal file throughout, so this reads its bytes back unchanged
## instead of only inferring preservation from ok=false.
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


## Review round 3 required fix (S1): a metadata-write failure exercised
## through the real _recover_document production call site (not write_record
## directly) must leave doc without a recovery record, still reporting
## needs_shutdown_attention() -- a failed metadata write can never be treated
## as a successful recovery.
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


## Review round 3 required fix (S1): an index.json (or one of its own record
## entries) carrying an unsupported/unknown version must never be treated as
## readable. load_all reports it as one failure by the index's own path
## (never silently resolving zero records); write_record quarantines it
## (rename, never overwrite) instead of replacing its version with
## SCHEMA_VERSION. The stack file the unknown-version record referenced must
## survive untouched throughout, since it is never loaded, rewritten, or
## deleted for an invalid record.
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


## Review round 3 required fix (S1): an index entry whose own stack_file
## attempts path traversal (here escaping the recovery directory entirely,
## the exact "../x.tres" shape cited by the reviewer) must be rejected by
## both load_all (reported, never loaded) and remove_record (reported, never
## deleted) -- the planted file the traversal targets, and the invalid index
## entry itself, must both survive untouched by either call.
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


## Fix-now round 4, S1: a record whose own `id` ("../victim") does not match
## its `stack_file` ("safe.tres") passed round 3's `_validate_record` (each
## field was individually safe) but then let `id` reach `write_record` as
## `existing_id` on the very next confirmed-shutdown write, which derives a
## *fresh* `stack_file` from `id` alone ("%s.tres" % id) -- writing
## "../victim.tres" outside the recovery directory before this fix. Plants
## exactly that shape, a real file one directory above `dir` at the path that
## record's own derived stack_file would resolve to, and a real `safe.tres`
## the entry's own (valid) `stack_file` field names. Runs `load_all` first
## (must reject, reporting by path, without touching either planted file),
## then replays the real `_recover_document` production call site with a
## document carrying that same unsafe id as its own `recovery_record_id` --
## the exact path a previously-loaded (pre-fix) record's id took to reach
## `write_record` -- and asserts the outside file stays byte-identical and
## the planted index.json is untouched.
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


## Fix-now round 4, S1: `_is_supported_version` previously computed
## `int(value) == SCHEMA_VERSION`, and `int()` truncates -- an index-level
## `float` version of `1.5` silently passed for `SCHEMA_VERSION == 1` before
## this fix. Plants that exact shape and asserts `load_all` rejects it by the
## index's own path (the same unreadable-index route malformed JSON already
## uses), leaving the planted stack file untouched.
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


## Same defect, record level: a per-entry `version` of `1.5` must be rejected
## by `_validate_record` (shared by `load_all` and `remove_record`) even
## though the index's own top-level version is valid, leaving the planted
## stack file untouched and reporting the failure by the invalid entry's own
## id.
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


## Guards the exact legitimate case a stricter float comparison could
## overcorrect against: `1.0` (a JSON number with a decimal point, which
## Godot's `JSON.parse` always resolves to a `float`, never an `int`) must
## still resolve to a valid record at both the index level and the record
## level -- `_is_supported_version`'s own float branch compares against
## `float(SCHEMA_VERSION)` directly rather than requiring an `int`.
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


## Review round 5 required fix (S1): write_record's own existing_id overwrite
## path must validate the *currently indexed* record before touching its
## stack file or its index entry -- the reviewer's own reproduction: an
## indexed record shaped id="planted", stack_file="planted.tres", a version
## of 1.5, was silently overwritten by write_record(..., "planted") before
## this fix, discarding its own (invalid, but still on-disk) content and
## metadata without reporting anything. Three planted shapes, each in its own
## throwaway directory: (a) the record's own "version" is 1.5; (b) the
## index's own top-level "version" is 1.5 (record-level version valid); (c)
## the record's own "stack_file" ("other.tres") no longer agrees with its
## "id" ("planted"), the same identity mismatch fix-now round 4 already
## rejects on load. Each case calls write_record directly with that id and a
## fresh stack (asserting ok=false, the reason names both the index path and
## the record id, and both planted files stay byte-identical), then replays
## the real _recover_document production call site with a document carrying
## that same id as its own recovery_record_id (asserting the same
## byte-identical preservation plus needs_shutdown_attention() staying true,
## since a rejected write never sets recovery_fingerprint). Also re-confirms
## the settled fresh-record quarantine path (no existing_id, unreadable
## index) still quarantines and reports -- this fix's own unconditional
## existing-id index read must never disturb that unrelated branch.
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


## Shared body for the three planted shapes above: plants `index_json` and a
## real `stack_file_name` under a fresh directory, snapshots both files'
## bytes, calls write_record directly with existing id "planted" and a fresh
## overwrite stack, then replays the real _recover_document call site with a
## document carrying "planted" as its own recovery_record_id -- asserting
## both planted files stayed byte-identical across both calls and neither
## call ever claimed success.
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


## Review round 1 required fix: three planted on-disk corruption cases
## load_all() must report by path instead of either silently resolving to
## zero records (a truncated/malformed index.json, observed silent before
## this fix) or throwing a script error out of _ready() (a non-array
## "records" field, observed verbatim: "Invalid cast: could not convert
## value to 'Array'. at: load_all"). Each runs in its own throwaway
## directory, never the live flow above, and never calls write_record for
## the index.json itself -- the point is what a real corrupted file on disk
## reads back as, not what write_record produces.
func _check_read_side_failures(panel: GSTMainPanel) -> void:
	_check_corrupt_stack_with_valid_index_entry(panel)
	_check_unparseable_index_json(panel)
	_check_non_array_records_field(panel)
	_check_quarantine_reported_at_write_time(panel)
	_check_preexisting_quarantine_reported_on_load(panel)


## Baseline case: passed before this fix pass and must keep passing. A
## corrupt .tres with an otherwise-valid index entry is reported by its own
## stack path; the corrupt file and the valid index.json are both left on
## disk untouched.
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


## An index.json this engine cannot parse as JSON at all (e.g. truncated
## mid-write) must be reported by its own path, not silently read back as an
## empty/absent index (the defect this fix corrects: previously zero records
## restored, nothing reported).
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


## A well-formed JSON object whose own "records" field is not an Array (the
## defect this fix corrects: previously threw "Invalid cast: could not
## convert value to 'Array'" out of load_all(), which _ready() calls
## unguarded) must be reported by the index's own path instead of throwing.
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


## Fix-now round 2, note 1 (write-time half): an unreadable index.json
## already present when write_record runs must be quarantined and its own
## quarantined path returned in the result, not just retained silently --
## the planted case this replays: a truncated index.json plus an
## orphan.tres a lost index entry used to reference, both left on disk after
## a fresh write_record call reports ok=true. reason: "REVIEW
## caseD_after_reload records=1 failures=[]" observed index.json.unreadable-
## 1789198480 and orphan.tres both still on disk and never named anywhere in
## that result.
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
	# write_record succeeds overall: quarantining the unreadable index clears
	# the way for a fresh index.json to be written right after, holding just
	# this call's own new entry -- so index_path itself exists again by the
	# time this assertion runs, this time as a valid fresh index rather than
	# the unreadable one quarantined_path now names.
	var quarantine_ok: bool = (
		bool(write_result.get("ok", false)) and not quarantined_path.is_empty()
		and quarantined_path.begins_with(index_path) and quarantined_path.contains(".unreadable-")
		and quarantined_path != index_path
		and FileAccess.file_exists(quarantined_path) and FileAccess.file_exists(index_path)
		and FileAccess.file_exists(orphan_stack_path)
	)
	_check("quarantine_reported_at_write_time", quarantine_ok, "write_result=%s orphan_preserved=%s" % [write_result, FileAccess.file_exists(orphan_stack_path)])
	_wipe_dir_contents(dir)


## Fix-now round 2, note 1 (read-time half): a pre-existing
## index.json.unreadable-* file (quarantined by some earlier write_record
## call, per the check above) must be reported by load_all -- and, since
## nothing here ever removes it, on every later call too, not just the
## first, matching "no migration may silently delete it".
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


## write_record's own metadata-write failure (index.json replaced by a
## directory, after a first successful write) must report ok=false and never
## silently claim success -- checked in its own throwaway directory, never
## the live one _run_initial's own recovery flow uses, so a directory-swap
## trick here can never leave that flow's own records in an inconsistent
## state regardless of filesystem timing.
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


## Godot 4.4's own editor top bar is a MenuBar (EditorTitleBar), not a plain
## MenuButton row: "Quit" is item id 15 of its "Scene" menu, the exact same
## PopupMenu.id_pressed EditorNode's own _menu_option connects to for a real
## click or the Ctrl+Shift+Q shortcut alike. A synthetic InputEventKey
## delivered through push_input (tests/gst_editor_document_proof.gd's own
## phase 1 technique) stopped reaching that shortcut in this environment;
## firing the menu's own id_pressed signal directly is this codebase's
## established convention for driving a menu handler without a real
## OS-level click (gst_main_panel.gd's own file/layer MenuButtons; every
## existing *_smoke.gd that drives one), and reaches the identical
## EditorNode handler a real click or shortcut would.
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
	# Emitted once: EditorNode builds/reuses this exact ConfirmationDialog on
	# every "Quit" activation, so a retry loop that keeps re-emitting while
	# still waiting for the first one to appear risks re-triggering the same
	# handler mid-build instead of just waiting longer for it.
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
	# A real simulated click through the dialog's own embedded Window/
	# Viewport (tests/gst_editor_document_close_smoke.gd's own established
	# convention: "Buttons inside a popped-up ConfirmationDialog live in
	# that dialog's own embedded Window/Viewport, not the root one"). Both a
	# focused Enter keypress and a direct pressed.emit() reliably reached
	# this exact point (dialog found, button located, and a temporary print
	# inside plugin.gd's own _save_external_data() confirmed it genuinely
	# ran) but the dialog never actually closed and the process never
	# exited across repeated real runs; only a real click through the
	# dialog's own viewport, with the same NOTIFICATION_MOUSE_ENTER
	# workaround that convention documents, is proven reliable here.
	await _click_button(plugin, save_quit)
	print("SMOKE_RECOVERY SAVE_AND_QUIT_ACTIVATION_DISPATCHED")


## Second process: the real editor session reopened after the first process
## actually exited through the confirmed quit above. load_recovery_records()
## already ran, unconditionally, from this panel's own _ready() before this
## script ever gets control.
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
	# Self-resetting stage protocol (review round 3 required fix): a
	# successful stage 2 run consumes its own marker, so a third invocation
	# against the same isolated project starts as stage 1 again instead of
	# reading a stale marker left over from this run. A failed run leaves the
	# marker in place for diagnosis, matching this file's own "report,
	# never silently delete" convention for on-disk recovery state.
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


## "" for an absent file, distinguishable here only by the caller already
## knowing the planted file must exist -- used solely for a byte-identical
## before/after comparison, never to distinguish absent from empty content.
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


## `{found: bool, popup: PopupMenu, id: int}` for menu_title's own item whose
## displayed text is exactly item_text -- looked up by text, not a hardcoded
## id, since MenuBar reassigns ids per build/version.
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


## find_children (not a plain get_children() recursion): AcceptDialog's own
## message Label/HBoxContainer/Buttons are added as internal children, which
## get_children() excludes by default; find_children reaches them, matching
## tests/gst_editor_document_proof.gd's own established precedent.
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


## Real click on target's own global-rect center, delivered through target's
## own Viewport, matching tests/gst_editor_document_close_smoke.gd's own
## established _click_button precedent exactly (including the
## NOTIFICATION_MOUSE_ENTER workaround BaseButton::on_action_event's own
## status.hovering gate requires for a synthetic InputEventMouseButton).
## Guards every await against a plugin already freed mid-continuation (phase
## 8 review round 1 fix 10): clicking "Save and Quit" here is this stage's
## own real quit trigger, so the mouse-up push below can make the process
## start exiting -- freeing plugin -- while this coroutine is still
## suspended on a later await. Resuming that suspended await then called
## plugin.get_tree() on an already-freed instance, printing
## "SCRIPT ERROR: Cannot call method 'get_tree' on a previously freed
## instance" after an otherwise-successful confirmed quit. Returning before
## each await once plugin is no longer valid lets this stage exit cleanly
## instead of continuing a callback chain the process is already tearing
## down for.
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
