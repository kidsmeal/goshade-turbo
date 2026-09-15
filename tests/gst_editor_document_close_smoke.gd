@tool
extends RefCounted

## Phase 6 (docs/SHADER_TABS_reviewed-plan.md): document-bound close
## lifecycle (decision 9, docs/SHADER_TABS_reviewed.md) -- clean-close,
## dirty Save/Discard/Cancel through gst_main_panel.gd's own native
## _close_dialog, untitled Save As on close, failed-save/cancel preserving
## the dirty document, Discard releasing only the selected document's own
## resources/history, adjacent-tab selection, the last close restoring the
## entry surface, and a stale close continuation rejected after closure.
##
## 2026-09-15 TabBar pass: %ShaderTabs is now a native Godot TabBar instead
## of a row of per-document title/close Buttons (gst_main_panel.gd/.tscn), so
## a tab's own close gesture is a click at panel.get_tab_close_rect(doc) (a
## global-coordinate seam reconstructed from TabBar's own public theme items,
## since its internal cb_rect has no getter) rather than a click on a
## Button.pressed()-wired close Button. _click_tab_close below drives that
## click with a real InputEventMouseButton press/release through the
## viewport, matching this file's own established real-click convention
## (never Button.pressed.emit(), never panel._on_close_save_requested()/
## _on_close_custom_action() called directly) -- unlike a Button, TabBar's
## own gui_input (tab_bar.cpp) resolves a click by the event's own position
## alone, with no BaseButton-style status.hovering gate, so no
## NOTIFICATION_MOUSE_ENTER workaround is needed for the click itself to
## register. Buttons inside a popped-up ConfirmationDialog (Save/Discard/
## Cancel) are unchanged real Buttons in that dialog's own embedded
## Window/Viewport, still driven by _click_button exactly as before.
##
## Distinct dirty documents are opened through panel.open_recipe() (phase 3:
## never reused) where a check needs more than one open document at once;
## single-document checks use panel.open_document(GSTStack.new(), "", false)
## and dirty it immediately with a real structural edit
## (panel.get_undo().add_layer), since an untouched pristine document would
## otherwise be silently reused by open_document's own "Reuse the initial
## pristine empty document" rule (decision 2) instead of producing a fresh
## one for the next check.

var _pass_count: int = 0
var _fail_count: int = 0


func run(plugin: EditorPlugin) -> void:
	for i: int in range(5):
		await plugin.get_tree().process_frame
	var panel: GSTMainPanel = plugin.get_panel() as GSTMainPanel
	_check("panel", panel != null, "panel present=%s" % [panel != null])
	if panel == null:
		_finish(plugin)
		return

	# Matches tests/gst_editor_tabs_smoke.gd's own bootstrap fix (2026-09-15
	# TabBar pass): the editor's own deferred "restore last main screen from
	# saved window layout" can still be in flight this early in a session and
	# overrides a single set_main_screen_editor call once it finishes
	# loading. Re-asserting it every frame until the panel actually reports
	# visible (bounded to 60 frames) survives that race.
	for i: int in range(60):
		EditorInterface.set_main_screen_editor("GoShade Turbo")
		await plugin.get_tree().process_frame
		if panel.is_visible_in_tree():
			break
	_check("main_screen_visible", panel.is_visible_in_tree(), "visible=%s" % [panel.is_visible_in_tree()])
	if panel.is_start_screen_visible():
		panel.get_create_empty_button().pressed.emit()
		await plugin.get_tree().process_frame
		panel.get_picker().cancelled.emit()
		await plugin.get_tree().process_frame

	# One-time engine warm-up (matches tests/gst_editor_tabs_smoke.gd's own
	# documented precedent): the very first synthetic InputEventMouseButton
	# press delivered in a fresh editor session hits Viewport's own
	# stale-subwindow-focus-clearing path once (scene/main/viewport.cpp
	# Viewport::_sub_windows_forward_input, "no window found and clicked,
	# remove focus") and never reaches a control's own gui_input; every
	# click after the first behaves normally. Absorbed here on the initial
	# document's own already-active tab (a harmless no-op reclick), before
	# any assertion-bearing click below.
	var warm_up_doc: GSTDocument = panel.get_active_document()
	if warm_up_doc != null:
		await _click_tab(plugin, panel, warm_up_doc)

	await _run_clean_close_immediate(plugin, panel)
	await _run_dirty_named_close_save(plugin, panel)
	await _run_dirty_named_close_discard(plugin, panel)
	await _run_undo_cannot_reopen_closed_document(plugin, panel)
	await _run_dirty_close_cancel(plugin, panel)
	await _run_untitled_close_save_as_success(plugin, panel)
	await _run_untitled_close_save_as_failure(plugin, panel)
	await _run_untitled_close_save_as_cancel(plugin, panel)
	await _run_inactive_document_close(plugin, panel)
	await _run_adjacent_tab_selected_after_close(plugin, panel)
	await _run_stale_close_continuation_cannot_close_replacement(plugin, panel)
	await _run_last_close_restores_entry_surface(plugin, panel)

	_finish(plugin)


## Clean (never-dirtied) document closes the instant its own tab close icon is
## clicked, with no Save/Discard/Cancel prompt at all (decision 9: "unmodified
## saved documents close immediately").
func _run_clean_close_immediate(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	var was_open: bool = panel.get_documents().has(doc)
	var was_clean: bool = not doc.is_dirty()
	var tab_found: bool = panel.get_tab_index(doc) != -1
	if tab_found:
		await _click_tab_close(plugin, panel, doc)
	await plugin.get_tree().process_frame
	var closed: bool = not panel.get_documents().has(doc)
	var no_dialog: bool = not panel.is_close_dialog_visible()
	_check("clean_close_immediate", was_open and was_clean and tab_found and closed and no_dialog, "was_open=%s was_clean=%s tab_found=%s closed=%s no_dialog=%s" % [was_open, was_clean, tab_found, closed, no_dialog])


## A dirty, already-named document (a real current_path) closes through the
## Save/Discard/Cancel prompt's own "Save" button, saving directly to its
## existing path (no Save As involved) and closing only after that write
## actually lands.
func _run_dirty_named_close_save(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var save_path: String = "user://gst_tabs_close_named_save.tres"
	_cleanup([save_path])
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	var save_result: Dictionary = await panel.save_to_path(save_path)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	var dirty_before: bool = doc.is_dirty()
	var expected_fingerprint: String = GSTDocument.compute_fingerprint(doc.stack)

	await _click_tab_close(plugin, panel, doc)
	var dialog_shown: bool = panel.is_close_dialog_visible()
	await _click_button(plugin, panel.get_close_dialog().get_ok_button())
	await plugin.get_tree().process_frame

	var closed: bool = not panel.get_documents().has(doc)
	var dialog_hidden: bool = not panel.is_close_dialog_visible()
	var loaded: Dictionary = GSTStackIO.load(save_path, panel.get_library())
	var content_matches: bool = loaded["ok"] and GSTDocument.compute_fingerprint(loaded["stack"]) == expected_fingerprint
	_check("dirty_named_close_save", bool(save_result.get("ok", false)) and dirty_before and dialog_shown and closed and dialog_hidden and content_matches, "save_ok=%s dirty_before=%s dialog_shown=%s closed=%s dialog_hidden=%s content_matches=%s" % [save_result.get("ok", false), dirty_before, dialog_shown, closed, dialog_hidden, content_matches])
	_cleanup([save_path])


## Discard on a dirty, already-named document closes it without writing --
## the on-disk file keeps its last saved content -- and releases only that
## document's own resources/history (Cross-cutting "Discard releases only
## the selected document's resources/history").
func _run_dirty_named_close_discard(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var save_path: String = "user://gst_tabs_close_named_discard.tres"
	_cleanup([save_path])
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	await panel.save_to_path(save_path)
	await plugin.get_tree().process_frame
	var saved_fingerprint: String = GSTDocument.compute_fingerprint(doc.stack)
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	var dirty_before: bool = doc.is_dirty()
	var history: UndoRedo = doc.undo_redo

	await _click_tab_close(plugin, panel, doc)
	var dialog_shown: bool = panel.is_close_dialog_visible()
	await _click_button(plugin, panel.get_close_dialog_discard_button())
	await plugin.get_tree().process_frame

	var closed: bool = not panel.get_documents().has(doc)
	var dialog_hidden: bool = not panel.is_close_dialog_visible()
	var history_freed: bool = not is_instance_valid(history)
	var loaded: Dictionary = GSTStackIO.load(save_path, panel.get_library())
	var disk_unchanged: bool = loaded["ok"] and GSTDocument.compute_fingerprint(loaded["stack"]) == saved_fingerprint
	_check("dirty_named_close_discard", dirty_before and dialog_shown and closed and dialog_hidden and history_freed and disk_unchanged, "dirty_before=%s dialog_shown=%s closed=%s dialog_hidden=%s history_freed=%s disk_unchanged=%s" % [dirty_before, dialog_shown, closed, dialog_hidden, history_freed, disk_unchanged])
	_cleanup([save_path])


## Close/navigation never register a stack undo action (Cross-cutting "Keep
## closing and entry navigation outside stack undo"): a real Ctrl+Z pressed
## right after closing a dirty document cannot reopen it, since no action
## anywhere ever referenced it and its own UndoRedo was already freed by
## teardown() above. Whatever document is active afterward (a sibling
## document's own history, if it has one) is the only thing an undo can
## possibly reach.
func _run_undo_cannot_reopen_closed_document(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	# A second, independent document guarantees at least one other real
	# document survives the close below, so "closed" is proven by doc's own
	# absence rather than relying on whether _close_document_now's own
	# last-document replacement happens to fire.
	await panel.open_recipe("fire")
	await plugin.get_tree().process_frame
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame

	await _click_tab_close(plugin, panel, doc)
	await _click_button(plugin, panel.get_close_dialog_discard_button())
	await plugin.get_tree().process_frame
	var closed: bool = not panel.get_documents().has(doc)
	var documents_after_close: int = panel.get_documents().size()

	_push_key(panel, KEY_Z, true, false)
	await plugin.get_tree().process_frame
	_push_key(panel, KEY_Z, true, false)
	await plugin.get_tree().process_frame

	var still_closed: bool = not panel.get_documents().has(doc)
	var count_unchanged_by_undo: bool = panel.get_documents().size() == documents_after_close
	_check("undo_cannot_reopen_closed_document", closed and still_closed and count_unchanged_by_undo, "closed=%s documents_after_close=%d still_closed=%s count_after_undo=%d" % [closed, documents_after_close, still_closed, panel.get_documents().size()])


## Cancel on a dirty document's close prompt leaves it exactly as it was:
## still open, still dirty, its tab still present, no content lost.
func _run_dirty_close_cancel(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	var dirty_before: bool = doc.is_dirty()
	var layers_before: int = doc.stack.layers.size()

	await _click_tab_close(plugin, panel, doc)
	var dialog_shown: bool = panel.is_close_dialog_visible()
	await _click_button(plugin, panel.get_close_dialog().get_cancel_button())
	await plugin.get_tree().process_frame

	var still_open: bool = panel.get_documents().has(doc)
	var still_dirty: bool = doc.is_dirty()
	var dialog_hidden: bool = not panel.is_close_dialog_visible()
	var tab_still_present: bool = panel.get_tab_index(doc) != -1
	var layers_unchanged: bool = doc.stack.layers.size() == layers_before
	_check("dirty_close_cancel_preserves_document", dirty_before and dialog_shown and still_open and still_dirty and dialog_hidden and tab_still_present and layers_unchanged, "dirty_before=%s dialog_shown=%s still_open=%s still_dirty=%s dialog_hidden=%s tab_present=%s layers_unchanged=%s" % [dirty_before, dialog_shown, still_open, still_dirty, dialog_hidden, tab_still_present, layers_unchanged])


## Save on an untitled (never-saved) document's close prompt routes through
## the real Save As dialog (decision 9: "Save on an untitled document runs
## Save As and closes only after success"); resolving it with a real path
## closes doc only after that write actually lands.
func _run_untitled_close_save_as_success(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	var dirty_before: bool = doc.is_dirty()
	var untitled_before: bool = doc.current_path.is_empty()
	var expected_fingerprint: String = GSTDocument.compute_fingerprint(doc.stack)

	await _click_tab_close(plugin, panel, doc)
	var dialog_shown: bool = panel.is_close_dialog_visible()
	await _click_button(plugin, panel.get_close_dialog().get_ok_button())
	await plugin.get_tree().process_frame
	var save_as_opened: bool = panel._save_as_dialog.visible and bool(panel._pending_save_as.get("close_after", false)) and int(panel._pending_save_as.get("doc_id", -1)) == doc.session_id

	var save_path: String = "user://gst_tabs_close_untitled_save_as.tres"
	_cleanup([save_path])
	panel._save_as_dialog.hide()
	panel._on_save_as_file_selected(save_path)
	await plugin.get_tree().process_frame

	var closed: bool = not panel.get_documents().has(doc)
	var loaded: Dictionary = GSTStackIO.load(save_path, panel.get_library())
	var content_matches: bool = loaded["ok"] and GSTDocument.compute_fingerprint(loaded["stack"]) == expected_fingerprint
	_check("untitled_close_save_as_success", dirty_before and untitled_before and dialog_shown and save_as_opened and closed and content_matches, "dirty_before=%s untitled_before=%s dialog_shown=%s save_as_opened=%s closed=%s content_matches=%s" % [dirty_before, untitled_before, dialog_shown, save_as_opened, closed, content_matches])
	_cleanup([save_path])


## A failed Save As write (a missing parent directory) during a close leaves
## the untitled document exactly as it was -- open, dirty, its own failure
## message set -- never closed on a failed save (Cross-cutting "Preserve
## dirty documents after failed saves").
func _run_untitled_close_save_as_failure(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	var dirty_before: bool = doc.is_dirty()

	await _click_tab_close(plugin, panel, doc)
	await _click_button(plugin, panel.get_close_dialog().get_ok_button())
	await plugin.get_tree().process_frame
	var save_as_opened: bool = panel._save_as_dialog.visible

	var bad_path: String = "user://gst_tabs_close_missing_dir/gst_tabs_close_bad.tres"
	panel._save_as_dialog.hide()
	panel._on_save_as_file_selected(bad_path)
	await plugin.get_tree().process_frame

	var still_open: bool = panel.get_documents().has(doc)
	var still_dirty: bool = doc.is_dirty()
	var message_present: bool = not String(doc.operation_messages.get("Save", "")).is_empty()
	var tab_still_present: bool = panel.get_tab_index(doc) != -1
	_check("untitled_close_save_as_failure_preserves_document", dirty_before and save_as_opened and still_open and still_dirty and message_present and tab_still_present, "dirty_before=%s save_as_opened=%s still_open=%s still_dirty=%s message='%s' tab_present=%s" % [dirty_before, save_as_opened, still_open, still_dirty, doc.operation_messages.get("Save", ""), tab_still_present])


## Cancelling the Save As dialog itself (the real EditorFileDialog's own
## Cancel/Esc path -- canceled.emit(), not a direct .hide() -- matching
## tests/gst_editor_document_files_smoke.gd's own save_as_cancellation
## precedent) during a close leaves the untitled document exactly as it was
## and clears the captured close-continuation request (Cross-cutting
## "Preserve dirty documents after ... either dialog cancellation").
func _run_untitled_close_save_as_cancel(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	var dirty_before: bool = doc.is_dirty()
	var layers_before: int = doc.stack.layers.size()

	await _click_tab_close(plugin, panel, doc)
	await _click_button(plugin, panel.get_close_dialog().get_ok_button())
	await plugin.get_tree().process_frame
	var save_as_opened: bool = panel._save_as_dialog.visible
	var pending_before_cancel: bool = not panel._pending_save_as.is_empty()

	panel._save_as_dialog.hide()
	panel._save_as_dialog.canceled.emit()
	await plugin.get_tree().process_frame

	var still_open: bool = panel.get_documents().has(doc)
	var still_dirty: bool = doc.is_dirty()
	var pending_cleared: bool = panel._pending_save_as.is_empty()
	var tab_still_present: bool = panel.get_tab_index(doc) != -1
	_check("untitled_close_save_as_cancel_preserves_document", dirty_before and save_as_opened and pending_before_cancel and still_open and still_dirty and pending_cleared and tab_still_present and doc.stack.layers.size() == layers_before, "dirty_before=%s save_as_opened=%s pending_before=%s still_open=%s still_dirty=%s pending_cleared=%s tab_present=%s" % [dirty_before, save_as_opened, pending_before_cancel, still_open, still_dirty, pending_cleared, tab_still_present])


## Closing a dirty document that is not the active one still prompts its own
## Save/Discard/Cancel dialog and, on Discard, removes only that document --
## the active document's own identity, stack instance, and shared UI mirrors
## are never touched.
func _run_inactive_document_close(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	await panel.open_recipe("fire")
	await plugin.get_tree().process_frame
	var doc_a: GSTDocument = panel.get_active_document()
	await panel.open_recipe("dissolve")
	await plugin.get_tree().process_frame
	var doc_b: GSTDocument = panel.get_active_document()
	var distinct: bool = doc_a != null and doc_b != null and doc_a != doc_b
	var doc_a_dirty: bool = doc_a != null and doc_a.is_dirty()
	var active_is_b: bool = panel.get_active_document() == doc_b

	await _click_tab_close(plugin, panel, doc_a)
	var dialog_shown_for_inactive: bool = panel.is_close_dialog_visible()
	await _click_button(plugin, panel.get_close_dialog_discard_button())
	await plugin.get_tree().process_frame

	var a_closed: bool = not panel.get_documents().has(doc_a)
	var b_still_active_untouched: bool = panel.get_active_document() == doc_b and panel.get_stack() == doc_b.stack and panel.get_current_path() == doc_b.current_path
	_check("inactive_document_close_leaves_active_untouched", distinct and doc_a_dirty and active_is_b and dialog_shown_for_inactive and a_closed and b_still_active_untouched, "distinct=%s doc_a_dirty=%s active_is_b=%s dialog_shown=%s a_closed=%s b_untouched=%s" % [distinct, doc_a_dirty, active_is_b, dialog_shown_for_inactive, a_closed, b_still_active_untouched])


## Closing the active middle tab of three selects the tab that shifts into
## its old position; closing the new last tab afterward selects the
## remaining, earlier tab (decision 9: "Closing selects the adjacent
## remaining tab").
func _run_adjacent_tab_selected_after_close(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	await panel.open_recipe("fire")
	await plugin.get_tree().process_frame
	var doc1: GSTDocument = panel.get_active_document()
	await panel.open_recipe("dissolve")
	await plugin.get_tree().process_frame
	var doc2: GSTDocument = panel.get_active_document()
	await panel.open_recipe("fire")
	await plugin.get_tree().process_frame
	var doc3: GSTDocument = panel.get_active_document()

	await panel.activate_document(doc2)
	await plugin.get_tree().process_frame
	var doc2_dirty: bool = doc2.is_dirty()
	await _click_tab_close(plugin, panel, doc2)
	await _click_button(plugin, panel.get_close_dialog_discard_button())
	await plugin.get_tree().process_frame
	var doc2_closed: bool = not panel.get_documents().has(doc2)
	var adjacent_after_middle_close: bool = panel.get_active_document() == doc3

	await _click_tab_close(plugin, panel, doc3)
	await _click_button(plugin, panel.get_close_dialog_discard_button())
	await plugin.get_tree().process_frame
	var doc3_closed: bool = not panel.get_documents().has(doc3)
	var adjacent_after_last_close: bool = panel.get_active_document() == doc1

	_check("adjacent_tab_selected_after_close", doc2_dirty and doc2_closed and adjacent_after_middle_close and doc3_closed and adjacent_after_last_close, "doc2_dirty=%s doc2_closed=%s after_middle=%s doc3_closed=%s after_last=%s" % [doc2_dirty, doc2_closed, adjacent_after_middle_close, doc3_closed, adjacent_after_last_close])

	# Leaves doc1 open and active for the checks below.
	await panel.activate_document(doc1)
	await plugin.get_tree().process_frame


## A close-continuation response (the untitled Save-As-on-close request)
## must not act on a replacement tab that opened after the original target
## closed through a completely different path while that response was still
## pending (Cross-cutting "prevent stale close continuation from closing a
## replacement tab"). doc_x closes via the same direct
## _documents.erase/teardown bypass tests/gst_editor_document_files_smoke.gd
## already uses for a stale target, isolating this check to the resolution
## guard itself rather than re-exercising the close dialog a second time.
func _run_stale_close_continuation_cannot_close_replacement(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var doc_x: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame

	await _click_tab_close(plugin, panel, doc_x)
	var dialog_shown: bool = panel.is_close_dialog_visible()
	await _click_button(plugin, panel.get_close_dialog().get_ok_button())
	await plugin.get_tree().process_frame
	var pending_captured_for_x: bool = int(panel._pending_save_as.get("doc_id", -1)) == doc_x.session_id and bool(panel._pending_save_as.get("close_after", false))
	panel._save_as_dialog.hide()

	# Switches away from doc_x before the bypass below, matching
	# tests/gst_editor_document_files_smoke.gd's own established convention
	# for a stale-target simulation: doc_x must not be the active document
	# when its own UndoRedo is torn down out from under it, since nothing
	# reinstalls a different one until the "replacement" open below.
	await panel.open_recipe("fire")
	await plugin.get_tree().process_frame

	# doc_x closes through a different path entirely while its own Save As
	# response is still pending -- the stale-continuation scenario.
	panel._documents.erase(doc_x)
	doc_x.teardown()

	# A replacement tab opens and becomes active in the meantime.
	var replacement: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	if replacement == null:
		_check("stale_close_continuation_cannot_close_replacement_tab", false, "replacement open_document returned null (picker_open=%s)" % panel.is_picker_open())
		return
	var replacement_layers_before: int = replacement.stack.layers.size()
	var replacement_path_before: String = replacement.current_path

	var save_path: String = "user://gst_tabs_close_stale_continuation.tres"
	_cleanup([save_path])
	panel._on_save_as_file_selected(save_path)
	await plugin.get_tree().process_frame

	var replacement_untouched: bool = panel.get_active_document() == replacement and replacement.current_path == replacement_path_before and replacement.stack.layers.size() == replacement_layers_before
	var nothing_written: bool = not FileAccess.file_exists(save_path)
	var message_surfaced_on_replacement: bool = String(replacement.operation_messages.get("Save", "")).contains("no longer open")
	_check("stale_close_continuation_cannot_close_replacement_tab", dialog_shown and pending_captured_for_x and replacement_untouched and nothing_written and message_surfaced_on_replacement, "dialog_shown=%s pending_for_x=%s replacement_untouched=%s nothing_written=%s message='%s'" % [dialog_shown, pending_captured_for_x, replacement_untouched, nothing_written, replacement.operation_messages.get("Save", "")])
	_cleanup([save_path])


## Drains every remaining open document (including any left open, dirty, by
## earlier cancel/failure checks above) down to exactly one, then closes
## that last one: the entry surface (recipe grid, Open, Create Empty Stack)
## reappears, and a fresh, distinct, pristine document is already installed
## behind it (mirrors _ready()'s own bootstrap condition) instead of leaving
## the panel with zero documents (decision 9: "Closing the last tab restores
## the existing recipe/Open/Create Empty Stack entry surface").
func _run_last_close_restores_entry_surface(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var drain_iterations: int = 0
	while panel.get_documents().size() > 1 and drain_iterations < 30:
		drain_iterations += 1
		var doc: GSTDocument = panel.get_active_document()
		if doc == null or panel.get_tab_index(doc) == -1:
			break
		await _click_tab_close(plugin, panel, doc)
		var dialog_visible_after_click: bool = panel.is_close_dialog_visible()
		if dialog_visible_after_click:
			await _click_button(plugin, panel.get_close_dialog_discard_button())
		await plugin.get_tree().process_frame
	var drained_to_one: bool = panel.get_documents().size() == 1

	var last_doc: GSTDocument = panel.get_active_document()
	var entry_hidden_before: bool = not panel.is_start_screen_visible()
	await _click_tab_close(plugin, panel, last_doc)
	if panel.is_close_dialog_visible():
		await _click_button(plugin, panel.get_close_dialog_discard_button())
	await plugin.get_tree().process_frame

	var entry_restored: bool = panel.is_start_screen_visible()
	var replacement_doc: GSTDocument = panel.get_active_document()
	var replacement_ok: bool = replacement_doc != null and replacement_doc != last_doc and not replacement_doc.is_dirty() and panel.get_documents().size() == 1
	var replacement_tab_present: bool = replacement_doc != null and panel.get_tab_index(replacement_doc) != -1
	_check("last_close_restores_entry_surface", drained_to_one and entry_hidden_before and entry_restored and replacement_ok and replacement_tab_present, "drained_to_one=%s entry_hidden_before=%s entry_restored=%s replacement_ok=%s replacement_tab_present=%s" % [drained_to_one, entry_hidden_before, entry_restored, replacement_ok, replacement_tab_present])


## Real click on doc's own tab body (its title/selection area, not its close
## icon): press then release InputEventMouseButton at
## panel.get_tab_rect(doc)'s own global-rect center. Used only for this
## file's own warm-up reclick (run(), above) -- every close gesture below
## goes through _click_tab_close instead. TabBar.ensure_tab_visible(index)
## runs first and is awaited a frame, matching
## tests/gst_editor_tabs_smoke.gd's own _click_tab precedent exactly (see
## that file for the ofs_cache-outside-the-visible-window rationale).
func _click_tab(plugin: EditorPlugin, panel: GSTMainPanel, doc: GSTDocument) -> void:
	var index: int = panel.get_tab_index(doc)
	if index == -1:
		return
	panel.get_tab_bar().ensure_tab_visible(index)
	await plugin.get_tree().process_frame
	var point: Vector2 = panel.get_tab_rect(doc).get_center()
	_push_mouse(panel.get_tab_bar(), point, MOUSE_BUTTON_LEFT, true)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame
	_push_mouse(panel.get_tab_bar(), point, MOUSE_BUTTON_LEFT, false)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame


## Real click on doc's own tab close icon: press then release
## InputEventMouseButton at panel.get_tab_close_rect(doc)'s own global-rect
## center, delivered through %ShaderTabs's own Viewport (never
## Button.pressed.emit(), never panel.close_document() called directly).
## TabBar.ensure_tab_visible(index) runs first and is awaited a frame, for
## the same reason _click_tab above documents.
##
## Warps the real OS cursor to the close icon first (restored to its own
## prior position after the click) -- unlike a tab body click, TabBar's own
## close-button press handling (tab_bar.cpp TabBar::gui_input's cb_pressing
## branch) calls _update_hover() to populate the cb_hover index the release
## handler later reads, and _update_hover() reads
## Control::get_local_mouse_position(), which for this panel's own root
## (non-embedded) Viewport resolves through
## DisplayServer::mouse_get_position() (scene/main/viewport.cpp
## Viewport::get_mouse_position) -- the real OS cursor position -- not the
## synthetic event's own .position field a tab body click already resolves
## against directly. Verified directly in this session: an identical press/
## release with no cursor warp reached TabBar's own gui_input (confirmed via
## its gui_input signal) and correctly set cb_pressing on press, but cb_hover
## stayed unset because the real cursor never moved, so tab_close_pressed
## never emitted regardless of click position; warping first reproduces
## tab_close_pressed reliably. Matches this project's own established
## precedent for native-control tests needing the real cursor
## (tests/gst_editor_native_undo_smoke.gd's own EditorSpinSlider drag, which
## documents the same Input/DisplayServer distinction from the opposite
## direction).
func _click_tab_close(plugin: EditorPlugin, panel: GSTMainPanel, doc: GSTDocument) -> void:
	var index: int = panel.get_tab_index(doc)
	if index == -1:
		return
	panel.get_tab_bar().ensure_tab_visible(index)
	await plugin.get_tree().process_frame
	var point: Vector2 = panel.get_tab_close_rect(doc).get_center()
	var original_mouse: Vector2 = DisplayServer.mouse_get_position()
	DisplayServer.warp_mouse(Vector2i(point))
	await plugin.get_tree().process_frame
	_push_mouse(panel.get_tab_bar(), point, MOUSE_BUTTON_LEFT, true)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame
	_push_mouse(panel.get_tab_bar(), point, MOUSE_BUTTON_LEFT, false)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame
	DisplayServer.warp_mouse(Vector2i(original_mouse))


## Real click on target's own global-rect center, delivered through target's
## own Viewport (a popped-up ConfirmationDialog's own embedded Window for its
## Save/Discard/Cancel Buttons) -- never Button.pressed.emit().
## NOTIFICATION_MOUSE_ENTER supplies the one piece of engine state a
## synthetic InputEventMouseButton never establishes on its own in this
## session (BaseButton::on_action_event gates a mouse-button event behind
## status.hovering; Viewport's own hover tracking requires a real
## DisplayServer mouse-enter), matching
## tests/gst_editor_tabs_smoke.gd's own _click_tab precedent from the
## Button-row era. Only used for real Buttons now (2026-09-15 TabBar pass):
## every tab title/close click goes through _click_tab/_click_tab_close
## instead, which need no such workaround (TabBar's own gui_input resolves a
## click by the event's own position alone, tab_bar.cpp).
func _click_button(plugin: EditorPlugin, button: Button) -> void:
	if button == null or not is_instance_valid(button):
		return
	await plugin.get_tree().process_frame
	var point: Vector2 = button.get_global_rect().get_center()
	button.notification(Control.NOTIFICATION_MOUSE_ENTER)
	_push_mouse(button, point, MOUSE_BUTTON_LEFT, true)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame
	_push_mouse(button, point, MOUSE_BUTTON_LEFT, false)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame


func _push_mouse(target: Control, position: Vector2, button_index: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button_index
	event.pressed = pressed
	target.get_viewport().push_input(event, true)


## Real Ctrl(+Shift)+<keycode> key press/release, matching
## tests/gst_editor_tabs_smoke.gd's own _push_key precedent.
func _push_key(target: Control, keycode: Key, ctrl: bool = false, shift: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.window_id = target.get_window().get_window_id()
	target.get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	target.get_viewport().push_input(event, true)


func _cleanup(paths: Array[String]) -> void:
	for path: String in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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
