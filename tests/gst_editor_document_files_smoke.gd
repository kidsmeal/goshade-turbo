@tool
extends RefCounted

## Phase 5 (docs/SHADER_TABS_reviewed-plan.md): binds Save, Save As, Export,
## overwrite confirmation, preview-image selection, and delayed Open/Reopen
## Shader dialog responses to the document that initiated them, not
## whichever document happens to be active by the time the response arrives.
## Drives the real dialog-opening "_pressed" handlers (which now capture a
## stable document id + request identity) and the same *_file_selected/
## _on_overwrite_confirmed seams a real EditorFileDialog/ConfirmationDialog
## signal would call, switching the active document in between every open
## and its response -- exactly the race decision 20's own file operations
## never had to consider before tabs existed. Every write is verified by
## reloading the file (GSTStackIO.load / GSTExport.build) and comparing
## GSTDocument.compute_fingerprint / exact generated text against the
## originating document's own stack, never by trusting current_path/message
## state alone.
##
## "Stale/closed target" is mostly simulated here by removing a document from
## _documents (and tearing it down) directly, the same bypass-the-guarded-UI
## technique tests/gst_editor_ui_picker_smoke.gd already uses for a stale
## picker-context installation (real document close landed in phase 6:
## _run_real_close_then_stale_save_as_rejected below covers the same shape
## through panel.close_document itself, plan Blockers: "Closed-document
## callbacks receive their full runtime check after phase 6 adds closure").

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

	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await plugin.get_tree().process_frame
	if panel.is_start_screen_visible():
		panel.get_create_empty_button().pressed.emit()
		await plugin.get_tree().process_frame
		panel.get_picker().cancelled.emit()
		await plugin.get_tree().process_frame

	# doc_a (fire, 5 layers) and doc_b (dissolve, 10 layers) are independent
	# recipe copies (phase 3: "Repeated recipes create independent
	# layer/coord instances") with structurally distinct content, used
	# throughout below as the two documents every check switches between.
	panel.open_recipe("fire")
	await plugin.get_tree().process_frame
	var doc_a: GSTDocument = panel.get_active_document()
	panel.open_recipe("dissolve")
	await plugin.get_tree().process_frame
	var doc_b: GSTDocument = panel.get_active_document()
	var setup_ok: bool = doc_a != null and doc_b != null and doc_a != doc_b and doc_a.stack.layers.size() != doc_b.stack.layers.size()
	_check("setup_two_distinct_documents", setup_ok, "doc_a_layers=%d doc_b_layers=%d" % [doc_a.stack.layers.size() if doc_a != null else -1, doc_b.stack.layers.size() if doc_b != null else -1])
	if not setup_ok:
		_finish(plugin)
		return

	var fingerprint_a: String = GSTDocument.compute_fingerprint(doc_a.stack)

	await _run_save_as_switch(plugin, panel, doc_a, doc_b, fingerprint_a)
	await _run_save_as_path_conflict(plugin, panel, doc_a, doc_b, fingerprint_a)
	await _run_export_second_confirmation(plugin, panel, doc_a, doc_b)
	await _run_stale_closed_save_as_rejected(plugin, panel, doc_a)
	await _run_real_close_then_stale_save_as_rejected(plugin, panel, doc_a)
	await _run_stale_closed_export_rejected(plugin, panel, doc_a)
	await _run_delayed_preview_image(plugin, panel, doc_a, doc_b)
	await _run_open_message_routing(plugin, panel, doc_a, doc_b)
	await _run_reopen_message_routing(plugin, panel, doc_a, doc_b)
	await _run_save_as_cancellation(plugin, panel, doc_a)
	await _run_failed_save(plugin, panel, doc_a)
	await _run_failed_export(plugin, panel, doc_a)
	await _run_new_clears_stale_open_message(plugin, panel)
	await _run_open_path_finishes_pending_color_edit(plugin, panel)

	_finish(plugin)


## Opens Save As while doc_a is active (capturing doc_a's own stable id and
## request identity), switches the active document to doc_b before the
## dialog's own file-selected response arrives, then resolves it: the write
## must still land on doc_a, doc_b must be completely untouched, and the
## panel's own shared mirrors (get_active_document/get_current_path) must
## keep showing doc_b, not doc_a, since doc_b is what the user is actually
## looking at when the response resolves.
func _run_save_as_switch(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument, doc_b: GSTDocument, fingerprint_a: String) -> void:
	var save_path: String = "user://gst_tabs_files_save_as.tres"
	_cleanup([save_path])
	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	panel._on_save_as_pressed()
	panel.activate_document(doc_b)
	await plugin.get_tree().process_frame
	panel._on_save_as_file_selected(save_path)
	await plugin.get_tree().process_frame
	# A real EditorFileDialog closes itself once its own embedded selection
	# flow runs; calling _on_save_as_file_selected directly (this test's own
	# stand-in for a real dialog click) bypasses that, so the popped window
	# stays open unless hidden explicitly -- otherwise a later check's own
	# popup_centered*() call on a different dialog trips Window's "already
	# has another exclusive child" error against this one.
	panel._save_as_dialog.hide()

	var doc_a_ok: bool = doc_a.current_path == save_path and not doc_a.is_dirty()
	var doc_b_untouched: bool = doc_b.current_path.is_empty() and doc_b.is_dirty()
	var active_unaffected: bool = panel.get_active_document() == doc_b and panel.get_current_path().is_empty()
	var loaded: Dictionary = GSTStackIO.load(save_path, panel.get_library())
	var content_is_doc_a: bool = loaded["ok"] and GSTDocument.compute_fingerprint(loaded["stack"]) == fingerprint_a
	_check("save_as_switch_writes_originating_document", doc_a_ok and doc_b_untouched and active_unaffected and content_is_doc_a, "doc_a_path='%s' (expect '%s') doc_a_dirty=%s doc_b_path='%s' doc_b_dirty=%s active_is_b=%s current_path='%s' loaded_ok=%s content_is_doc_a=%s" % [doc_a.current_path, save_path, doc_a.is_dirty(), doc_b.current_path, doc_b.is_dirty(), panel.get_active_document() == doc_b, panel.get_current_path(), loaded["ok"], content_is_doc_a])


## With doc_a already saved at save_path (by the check above) and doc_b
## active, Save As to that same canonical path must refuse instead of
## overwriting doc_a's own file with doc_b's content (Cross-cutting "Refuse
## Save As to a canonical path owned by another open document").
func _run_save_as_path_conflict(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument, doc_b: GSTDocument, fingerprint_a: String) -> void:
	var save_path: String = "user://gst_tabs_files_save_as.tres"
	panel.activate_document(doc_b)
	await plugin.get_tree().process_frame
	panel._on_save_as_pressed()
	panel._on_save_as_file_selected(save_path)
	await plugin.get_tree().process_frame
	panel._save_as_dialog.hide()

	var doc_b_unchanged: bool = doc_b.current_path.is_empty()
	var message_present: bool = String(doc_b.operation_messages.get("Save", "")).contains("already open")
	var shown_on_active: bool = panel.get_message_label().text.contains("already open")
	var loaded: Dictionary = GSTStackIO.load(save_path, panel.get_library())
	var file_still_doc_a: bool = loaded["ok"] and GSTDocument.compute_fingerprint(loaded["stack"]) == fingerprint_a
	_check("save_as_path_conflict_refused", doc_b_unchanged and message_present and shown_on_active and file_still_doc_a, "doc_b_path='%s' message='%s' shown='%s' file_still_doc_a=%s" % [doc_b.current_path, doc_b.operation_messages.get("Save", ""), panel.get_message_label().text, file_still_doc_a])
	_cleanup([save_path])


## Exports doc_a once (clean write), hand-edits the file on disk, then opens
## Export again while doc_a is active (capturing it), switches to doc_b, and
## resolves the file-selected response against the same export_path: the
## overwrite gate's own hand-edit check (GSTOverwriteCheck, decision 9) finds
## the on-disk body no longer matches a fresh codegen of its own embedded
## header and requires confirmation. Switches to doc_b again before
## confirming: _on_overwrite_confirmed must still re-target doc_a (Cross-
## cutting "bind its second confirmation to the original request"), not
## doc_b, which was never involved in this export at all. doc_a carries a
## real structural edit throughout (fix-now, phase 5 review round 2, note 3)
## so both the clean write and the confirmed overwrite are proven to leave
## it dirty (Cross-cutting "Export never clears dirty state").
func _run_export_second_confirmation(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument, doc_b: GSTDocument) -> void:
	var export_path: String = "user://gst_tabs_files_export.gdshader"
	_cleanup([export_path])
	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	# Fix-now (phase 5 review round 2, note 3): doc_a is already clean here
	# (_run_save_as_switch above just saved it), so nothing in this function
	# could have caught a stray mark_baseline() in the export path -- the
	# same blind spot round-1 note 2 found in _run_failed_save. A real
	# structural edit (the same panel.get_undo().add_layer primitive
	# _run_failed_save uses) makes doc_a genuinely dirty first, so the
	# assertions below can actually prove Export never clears dirty state
	# (Cross-cutting; docs/SHADER_TABS_reviewed.md decision 8) across both the
	# clean write and the confirmed overwrite.
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	var dirty_before_export: bool = doc_a.is_dirty()
	var expected_code: String = GSTExport.build(doc_a.stack, panel.get_library()).code

	# hide_export_dialog() runs immediately after each _on_export_pressed()
	# below, before resolving: a real EditorFileDialog closes itself the
	# instant the user actually picks a file, before _export_stack_to_path
	# ever runs (production order); this test's own direct
	# _on_export_file_selected call is that same production handler with no
	# real dialog interaction in front of it, so the window is closed here to
	# match that same order instead of leaving it open under a second
	# dialog's own popup_centered*() call (Window's "already has another
	# exclusive child" otherwise).
	panel._on_export_pressed()
	# abandon=false (phase 6): this call's own request must survive into the
	# _on_export_file_selected call immediately below, not be cleared here --
	# unlike a genuine abandonment (no resolution coming), which is
	# hide_export_dialog()'s own default.
	panel.hide_export_dialog(false)
	panel._on_export_file_selected(export_path)
	await plugin.get_tree().process_frame
	var first_write_ok: bool = _read_file(export_path) == expected_code
	_check("export_first_write_matches_originating_document", first_write_ok, "export_path='%s' matches=%s" % [export_path, first_write_ok])
	_check("export_clean_write_preserves_dirty_state", dirty_before_export and doc_a.is_dirty(), "dirty_before=%s dirty_after_clean_write=%s" % [dirty_before_export, doc_a.is_dirty()])

	_write_file(export_path, _mutate_body_line(_read_file(export_path)))
	var mutated_text: String = _read_file(export_path)

	panel._on_export_pressed()
	panel.hide_export_dialog(false)
	panel.activate_document(doc_b)
	await plugin.get_tree().process_frame
	panel._on_export_file_selected(export_path)
	await plugin.get_tree().process_frame
	var confirmation_pending: bool = panel.is_overwrite_dialog_visible() and _read_file(export_path) == mutated_text and panel.get_active_document() == doc_b
	_check("export_confirmation_pending_without_writing", confirmation_pending, "dialog_visible=%s file_unchanged=%s active_is_b=%s" % [panel.is_overwrite_dialog_visible(), _read_file(export_path) == mutated_text, panel.get_active_document() == doc_b])

	panel._on_overwrite_confirmed()
	await plugin.get_tree().process_frame
	var confirmed_ok: bool = not panel.is_overwrite_dialog_visible() and _read_file(export_path) == expected_code and panel.get_active_document() == doc_b
	_check("export_second_confirmation_targets_originating_document", confirmed_ok, "dialog_hidden=%s file_matches_doc_a=%s active_is_b=%s" % [not panel.is_overwrite_dialog_visible(), _read_file(export_path) == expected_code, panel.get_active_document() == doc_b])
	_check("export_confirmed_overwrite_preserves_dirty_state", dirty_before_export and doc_a.is_dirty(), "dirty_before=%s dirty_after_confirmed_overwrite=%s" % [dirty_before_export, doc_a.is_dirty()])
	_cleanup([export_path])


## Simulates a closed target via the same low-level bypass
## tests/gst_editor_ui_picker_smoke.gd already uses for a stale
## picker-context installation (a throwaway document captures a Save As
## request, is then removed from _documents and torn down before the
## dialog's response arrives), exercising _resolve_pending_document's own
## rejection directly. _run_real_close_then_stale_save_as_rejected below
## covers the same shape through the real, now-existing close path (phase 6).
## The response must be rejected outright -- no file written, the active
## document's own identity/content left untouched -- but (deferred note,
## phase 5 review round 1, resolved phase 6) its own operation_messages now
## does carry the closed-target diagnostic, surfaced instead of silently
## discarded.
func _run_stale_closed_save_as_rejected(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument) -> void:
	var doc_c: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel._on_save_as_pressed()
	panel._save_as_dialog.hide()
	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	doc_a.operation_messages.clear()
	panel._documents.erase(doc_c)
	doc_c.teardown()

	var stale_path: String = "user://gst_tabs_files_stale.tres"
	_cleanup([stale_path])
	panel._on_save_as_file_selected(stale_path)
	await plugin.get_tree().process_frame

	var nothing_written: bool = not FileAccess.file_exists(stale_path)
	var active_untouched: bool = panel.get_active_document() == doc_a
	var message_surfaced: bool = String(doc_a.operation_messages.get("Save", "")).contains("no longer open")
	_check("stale_closed_save_as_rejected", nothing_written and active_untouched and message_surfaced, "file_exists=%s active_is_a=%s doc_a_message='%s'" % [FileAccess.file_exists(stale_path), panel.get_active_document() == doc_a, doc_a.operation_messages.get("Save", "")])


## Regression (phase 6 review round 1, fix-now note 2): _on_export_file_
## selected's own doc == null branch (gst_main_panel.gd, reached when
## _resolve_pending_document finds no match for _pending_export) was
## unexecuted by any test, even though docs/CURRENTNESS_AUDIT.md ticks it
## alongside the runtime-verified Save As branch above. Same bypass shape as
## _run_stale_closed_save_as_rejected: doc_c (opened, and so already active)
## captures the Export request, is then removed from _documents and torn
## down before the dialog's response arrives, so _resolve_pending_document
## resolves null and the diagnostic must land on doc_a (active when the
## response resolves), not be silently discarded.
func _run_stale_closed_export_rejected(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument) -> void:
	var doc_c: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel._on_export_pressed()
	# abandon=false: this call's own request must survive into the
	# _on_export_file_selected call below (same reasoning as
	# _run_export_second_confirmation's own hide_export_dialog(false) call).
	panel.hide_export_dialog(false)
	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	doc_a.operation_messages.clear()
	panel._documents.erase(doc_c)
	doc_c.teardown()

	var stale_path: String = "user://gst_tabs_files_export_stale.gdshader"
	_cleanup([stale_path])
	panel._on_export_file_selected(stale_path)
	await plugin.get_tree().process_frame

	var nothing_written: bool = not FileAccess.file_exists(stale_path)
	var active_untouched: bool = panel.get_active_document() == doc_a
	var message_surfaced: bool = String(doc_a.operation_messages.get("Export", "")).contains("no longer open")
	_check("stale_closed_export_rejected", nothing_written and active_untouched and message_surfaced, "file_exists=%s active_is_a=%s doc_a_message='%s'" % [FileAccess.file_exists(stale_path), panel.get_active_document() == doc_a, doc_a.operation_messages.get("Export", "")])


## Same shape as above, through the real close path (phase 6) instead of the
## direct _documents.erase/teardown bypass: doc_c is pristine (clean), so
## panel.close_document closes it immediately with no dialog. Proves the
## close lifecycle's own teardown invalidates a pending Save As request the
## same way the bypass above does, without a separate invalidation pass
## (Cross-cutting "Invalidate pending file/picker/property callbacks for a
## closed document").
func _run_real_close_then_stale_save_as_rejected(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument) -> void:
	var doc_c: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel._on_save_as_pressed()
	panel._save_as_dialog.hide()
	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	doc_a.operation_messages.clear()
	var doc_c_was_open: bool = panel.get_documents().has(doc_c)
	await panel.close_document(doc_c)
	var doc_c_closed: bool = not panel.get_documents().has(doc_c)

	var stale_path: String = "user://gst_tabs_files_close_stale.tres"
	_cleanup([stale_path])
	panel._on_save_as_file_selected(stale_path)
	await plugin.get_tree().process_frame

	var nothing_written: bool = not FileAccess.file_exists(stale_path)
	var active_untouched: bool = panel.get_active_document() == doc_a
	var message_surfaced: bool = String(doc_a.operation_messages.get("Save", "")).contains("no longer open")
	_check("real_close_then_stale_save_as_rejected", doc_c_was_open and doc_c_closed and nothing_written and active_untouched and message_surfaced, "doc_c_was_open=%s doc_c_closed=%s file_exists=%s active_is_a=%s doc_a_message='%s'" % [doc_c_was_open, doc_c_closed, FileAccess.file_exists(stale_path), panel.get_active_document() == doc_a, doc_a.operation_messages.get("Save", "")])
	_cleanup([stale_path])


## Opens the preview-image dialog while doc_a is active, switches to doc_b,
## then resolves it: doc_a's own preview_image_path must update, doc_b's own
## field (and the live preview it is currently showing) must not.
func _run_delayed_preview_image(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument, doc_b: GSTDocument) -> void:
	var image_path: String = "res://addons/goshade_turbo/assets/preview_default.png"
	doc_a.preview_image_path = ""
	doc_b.preview_image_path = ""
	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	panel._on_image_button_pressed()
	panel._file_dialog.hide()
	panel.activate_document(doc_b)
	await plugin.get_tree().process_frame
	panel._on_preview_image_selected(image_path)
	await plugin.get_tree().process_frame

	var doc_a_ok: bool = doc_a.preview_image_path == image_path
	var doc_b_untouched: bool = doc_b.preview_image_path.is_empty()
	_check("delayed_preview_image_targets_originating_document", doc_a_ok and doc_b_untouched and panel.get_active_document() == doc_b, "doc_a_image='%s' (expect '%s') doc_b_image='%s' (expect '') active_is_b=%s" % [doc_a.preview_image_path, image_path, doc_b.preview_image_path, panel.get_active_document() == doc_b])

	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	var restored_ok: bool = doc_a.preview_image_path == image_path
	_check("delayed_preview_image_survives_reactivation", restored_ok, "doc_a_image='%s'" % [doc_a.preview_image_path])


## Opens the Open dialog while doc_a is active (capturing it for message
## routing only -- Open always creates/reactivates its own document
## independent of which one is active), switches to doc_b, then resolves
## with a missing path: the failure message must land on doc_a, not on
## doc_b (currently active and otherwise untouched).
func _run_open_message_routing(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument, doc_b: GSTDocument) -> void:
	var missing_path: String = "res://sandbox/stacks/gst_tabs_files_missing.tres"
	# Clears every earlier check's own leftover messages (e.g. doc_b's own
	# "Save" path-conflict message from _run_save_as_path_conflict above),
	# not just "Open": those are real, correctly-attributed diagnostics on
	# their own document, but they would otherwise make
	# panel.get_message_label().text nonempty here for a reason unrelated to
	# what this check is actually proving.
	doc_a.operation_messages.clear()
	doc_b.operation_messages.clear()
	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	panel._on_open_pressed()
	panel._open_dialog.hide()
	panel.activate_document(doc_b)
	await plugin.get_tree().process_frame
	panel._on_open_file_selected(missing_path)
	await plugin.get_tree().process_frame

	var doc_a_has_message: bool = not String(doc_a.operation_messages.get("Open", "")).is_empty()
	var doc_b_clean: bool = not doc_b.operation_messages.has("Open") and panel.get_message_label().text.is_empty()
	_check("open_dialog_message_routes_to_originating_document", doc_a_has_message and doc_b_clean and panel.get_active_document() == doc_b, "doc_a_message='%s' doc_b_message='%s' shown='%s' active_is_b=%s" % [doc_a.operation_messages.get("Open", ""), doc_b.operation_messages.get("Open", ""), panel.get_message_label().text, panel.get_active_document() == doc_b])

	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	var redisplayed: bool = not panel.get_message_label().text.is_empty()
	_check("open_dialog_message_redisplays_on_reactivation", redisplayed, "shown='%s'" % [panel.get_message_label().text])


## Same routing proof as Open above, using the Reopen Shader dialog and a
## headerless .gdshader (B8's own refusal: "no new empty stack is offered").
func _run_reopen_message_routing(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument, doc_b: GSTDocument) -> void:
	var headerless_path: String = "user://gst_tabs_files_headerless.gdshader"
	_write_file(headerless_path, "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0); }\n")
	# Clears every earlier check's own leftover messages (e.g. doc_a's own
	# "Open" failure message from _run_open_message_routing above), the same
	# reason _run_open_message_routing itself clears both documents first.
	doc_a.operation_messages.clear()
	doc_b.operation_messages.clear()
	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	panel._on_reopen_shader_pressed()
	panel._reopen_shader_dialog.hide()
	panel.activate_document(doc_b)
	await plugin.get_tree().process_frame
	panel._on_reopen_shader_file_selected(headerless_path)
	await plugin.get_tree().process_frame

	var doc_a_has_message: bool = String(doc_a.operation_messages.get("Reopen Shader", "")).contains("header")
	var doc_b_clean: bool = not doc_b.operation_messages.has("Reopen Shader") and panel.get_message_label().text.is_empty()
	_check("reopen_dialog_message_routes_to_originating_document", doc_a_has_message and doc_b_clean and panel.get_active_document() == doc_b, "doc_a_message='%s' doc_b_message='%s' shown='%s' active_is_b=%s" % [doc_a.operation_messages.get("Reopen Shader", ""), doc_b.operation_messages.get("Reopen Shader", ""), panel.get_message_label().text, panel.get_active_document() == doc_b])
	_cleanup([headerless_path])


## Save As's own EditorFileDialog.canceled -- the real Cancel button/Esc
## path, not a direct .hide() -- must clear the captured pending request so
## no later, unrelated response can resolve against it (defense-in-depth;
## Cross-cutting "reject closed/stale targets").
func _run_save_as_cancellation(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument) -> void:
	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	panel._on_save_as_pressed()
	var captured_before_cancel: bool = not panel._pending_save_as.is_empty()
	panel._save_as_dialog.hide()
	panel._save_as_dialog.canceled.emit()
	await plugin.get_tree().process_frame
	var cleared_after_cancel: bool = panel._pending_save_as.is_empty()
	_check("save_as_cancellation_clears_pending_request", captured_before_cancel and cleared_after_cancel, "captured_before=%s cleared_after=%s" % [captured_before_cancel, cleared_after_cancel])


## A Save to a path whose parent directory does not exist fails at
## FileAccess.open (GSTStackIO.save's own "cannot open ... for writing"
## branch has no equivalent here -- ResourceSaver.save fails the same way):
## the document must stay exactly as it was, with the failure reason on its
## own operation_messages.
## Fix-now (phase 5 review round 1, note 2): the original draft captured
## dirty_before from doc_a while it was already clean (doc_a's own
## _run_save_as_switch above left it saved/clean, and nothing between there
## and here edits it), so dirty_after == dirty_before proved only that a
## clean document stays clean, not that dirtiness survives a failed write --
## the actual exit criterion this check covers. Adds a real structural edit
## (panel.get_undo().add_layer, the same primitive
## tests/gst_editor_documents_smoke.gd's own baseline_dirty_after_
## structural_add check uses) to doc_a first so dirty_before is genuinely
## true, and the check now asserts that directly instead of only comparing
## before/after.
func _run_failed_save(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument) -> void:
	var bad_path: String = "user://gst_tabs_files_missing_dir/gst_tabs_files_bad.tres"
	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	var path_before: String = doc_a.current_path
	var dirty_before: bool = doc_a.is_dirty()
	var result: Dictionary = await panel.save_to_path(bad_path)
	var failed_ok: bool = dirty_before and not result["ok"] and doc_a.current_path == path_before and doc_a.is_dirty() == dirty_before and not String(doc_a.operation_messages.get("Save", "")).is_empty()
	_check("failed_save_invalid_path", failed_ok, "ok=%s current_path='%s' (expect unchanged '%s') dirty_before=%s (expect true) dirty_after=%s message='%s'" % [result["ok"], doc_a.current_path, path_before, dirty_before, doc_a.is_dirty(), doc_a.operation_messages.get("Save", "")])


## Same shape as failed_save above, for Export.
func _run_failed_export(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument) -> void:
	var bad_path: String = "user://gst_tabs_files_missing_dir/gst_tabs_files_bad.gdshader"
	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	var result: Dictionary = await panel.export_to_path(bad_path, false)
	var failed_ok: bool = not result["ok"] and not FileAccess.file_exists(bad_path) and not String(doc_a.operation_messages.get("Export", "")).is_empty()
	_check("failed_export_invalid_path", failed_ok, "ok=%s file_exists=%s message='%s'" % [result["ok"], FileAccess.file_exists(bad_path), doc_a.operation_messages.get("Export", "")])


## Regression (phase 5 review round 1, fix-now note 1): a fresh pristine
## document takes a failed Open's diagnostic (open_path routes a refusal's
## message onto _active_document -- gst_main_panel.gd's _open_path_for), then
## _on_new_pressed reuses that same still-pristine, still-clean document
## (_find_reusable_pristine_document: a failed Open never touches the
## document's stack, so it stays clean) instead of allocating a new one.
## Before the fix, _on_new_pressed blanked only _message_label.text, leaving
## the stale "Open" entry in GSTDocument.operation_messages, so the very next
## _refresh_operation_message_label() call (a tab switch back, or any later
## message on that document) re-showed it even though New had just run.
func _run_new_clears_stale_open_message(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var missing_path: String = "res://sandbox/stacks/gst_tabs_files_missing.tres"
	var pristine: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel.open_path(missing_path)
	await plugin.get_tree().process_frame
	var stale_message_present: bool = not String(pristine.operation_messages.get("Open", "")).is_empty() and not panel.get_message_label().text.is_empty()
	_check("new_regression_setup_stale_open_message_present", stale_message_present, "message='%s' shown='%s'" % [pristine.operation_messages.get("Open", ""), panel.get_message_label().text])

	panel._on_new_pressed()
	await plugin.get_tree().process_frame
	var reused_same_document: bool = panel.get_active_document() == pristine
	var label_empty_after_new: bool = panel.get_message_label().text.is_empty()
	var no_open_entry_after_new: bool = not pristine.operation_messages.has("Open")
	_check("new_clears_stale_open_message", reused_same_document and label_empty_after_new and no_open_entry_after_new, "reused_same_doc=%s label='%s' has_open_entry=%s" % [reused_same_document, panel.get_message_label().text, pristine.operation_messages.has("Open")])

	# A later message on this same document (a failed Save here; the fix-now
	# note's own reproduction also covers a plain tab switch back) must not
	# resurrect the "Open" entry operation_messages.clear() already removed.
	var bad_path: String = "user://gst_tabs_files_missing_dir/gst_tabs_files_new_pristine_bad.tres"
	var result: Dictionary = await panel.save_to_path(bad_path)
	var later_message_is_save_only: bool = not result["ok"] and not pristine.operation_messages.has("Open") and panel.get_message_label().text.contains("Save") and not panel.get_message_label().text.contains("Open")
	_check("new_stale_open_message_does_not_reappear_on_later_message", later_message_is_save_only, "shown='%s' has_open_entry=%s" % [panel.get_message_label().text, pristine.operation_messages.has("Open")])


## Regression (fix-now, phase 5 review round 3, note 1): reproduces the
## forced-finish suspension path that used to route a delayed Open success
## message onto whichever document was still active before a pending native
## color-popup commit resolved, instead of the document open_path actually
## installs -- reachable through open_document's own await
## _finish_pending_edits() (gst_main_panel.gd _open_path_for/
## _reopen_shader_path_for/open_recipe/_on_picker_choice's "recipe" case all
## shared this shape). Mirrors tests/gst_editor_documents_smoke.gd's own
## color_pending_edit_finishes_before_document_activation setup (a real
## popped ColorPickerButton with typed, uncommitted hex text on a
## color/palette layer), seeds color_doc with a stale "Open" diagnostic (as
## if an earlier failed Open had landed on it), then calls open_path
## fire-and-forget on a second, distinct .tres while that commit is still in
## flight -- exactly how the real Open dialog's own file_selected signal
## dispatches _on_open_file_selected. Polls (bounded) until activation
## completes rather than a fixed frame count: closing a native color popup's
## own close handler is CONNECT_DEFERRED and can span more than one frame
## (tests/gst_editor_documents_smoke.gd's own comment on this same setup).
func _run_open_path_finishes_pending_color_edit(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	# _run_new_clears_stale_open_message above leaves the "Add Layer" picker
	# open (_on_new_pressed's own trailing _on_chooser_requested call, never
	# closed by that check since save_to_path -- unlike open_document -- carries
	# no is_picker_open() guard): open_document below would otherwise return
	# null here.
	if panel.is_picker_open():
		panel.get_picker().cancelled.emit()
		await plugin.get_tree().process_frame
	# "fire" already carries a color/palette layer (fed by generative/fbm):
	# add_layer_by_entry_id("color/palette") on a bare GSTStack.new() refuses
	# ("The first layer must work without another layer as input.",
	# GSTUndo.add_layer_for_ui) since the entry has inputs and the stack
	# would be empty.
	await panel.open_recipe("fire")
	await plugin.get_tree().process_frame
	var color_doc: GSTDocument = panel.get_active_document()
	color_doc.operation_messages["Open"] = "stale message on document A"
	var stack_list: GSTStackList = panel.get_stack_list()
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var palette: GSTLayer = _find_layer_by_entry(color_doc.stack, "color/palette")
	stack_list.select_layer(palette.id)
	await plugin.get_tree().process_frame
	var color_property: EditorProperty = inspector.find_editor_property(&"a", palette)
	if color_property != null:
		inspector.get_settings_scroll().ensure_control_visible(color_property)
		await plugin.get_tree().process_frame
	var color_button: ColorPickerButton = _find_color_button(color_property)
	var color_button_found: bool = color_button != null
	var hex_edit_found: bool = false
	var new_doc: GSTDocument = null
	var history_before: int = -1
	var routing_ok: bool = false
	if color_button != null:
		history_before = color_doc.undo_redo.get_history_count()
		color_button.grab_focus()
		color_button.get_popup().popup()
		await plugin.get_tree().process_frame
		await plugin.get_tree().process_frame
		var hex_edit: LineEdit = _find_hex_line_edit(color_button.get_picker())
		hex_edit_found = hex_edit != null
		if hex_edit != null:
			await _type_into_line_edit(plugin, hex_edit, "336699")
		var new_path: String = "res://addons/goshade_turbo/recipes/fire.tres"
		# Fire-and-forget, matching a real Open dialog's own file_selected
		# signal dispatch (_on_open_file_selected) -- not awaited here, so
		# this reproduces the exact suspension path open_document's own
		# await _finish_pending_edits() creates instead of relying on
		# open_path's own internal await to block this test.
		panel.open_path(new_path)
		var deadline: int = Time.get_ticks_msec() + 3000
		while Time.get_ticks_msec() < deadline and panel.get_active_document() == color_doc:
			await plugin.get_tree().process_frame
		new_doc = panel.get_active_document()
		var expected_color: Color = Color(0x33 / 255.0, 0x66 / 255.0, 0x99 / 255.0, 1.0)
		routing_ok = hex_edit_found and new_doc != null and new_doc != color_doc and history_before + 1 == color_doc.undo_redo.get_history_count() and (palette.get(&"a") as Color).is_equal_approx(expected_color) and String(color_doc.operation_messages.get("Open", "")) == "stale message on document A"
	_check("open_path_finishes_pending_color_edit_before_switch", color_button_found and routing_ok, "color_button_found=%s hex_edit_found=%s new_doc_distinct=%s history=%d->%d color_a='%s' doc_a_message='%s' (expect unchanged)" % [color_button_found, hex_edit_found, new_doc != color_doc if new_doc != null else false, history_before, color_doc.undo_redo.get_history_count(), palette.get(&"a"), color_doc.operation_messages.get("Open", "")])


func _find_layer_by_entry(stack: GSTStack, entry_id: String) -> GSTLayer:
	for layer: GSTLayer in stack.layers:
		if layer.entry == entry_id:
			return layer
	return null


## Real-popup color-edit helpers (mirrors tests/gst_editor_documents_smoke.gd's
## own helpers of the same name), needed here only for
## open_path_finishes_pending_color_edit_before_switch above.
func _find_color_button(node: Node) -> ColorPickerButton:
	if node == null:
		return null
	if node is ColorPickerButton:
		return node as ColorPickerButton
	for child: Node in node.get_children():
		var found: ColorPickerButton = _find_color_button(child)
		if found != null:
			return found
	return null


func _find_hex_line_edit(picker: ColorPicker) -> LineEdit:
	var expected: String = picker.color.to_html(false).to_lower()
	for node: Node in picker.find_children("*", "LineEdit", true, false):
		var edit: LineEdit = node as LineEdit
		if edit.is_visible_in_tree() and edit.editable and edit.text.strip_edges().trim_prefix("#").to_lower() == expected:
			return edit
	return null


## Types text into edit without submitting it (no Enter, no focus change): a
## real pending, unevaluated entry, matching the production close path's own
## hex-text-commit-on-focus-exit contract.
func _type_into_line_edit(plugin: EditorPlugin, edit: LineEdit, text: String) -> void:
	edit.grab_focus()
	await plugin.get_tree().process_frame
	_push_key(edit, KEY_A, true)
	for index: int in range(text.length()):
		var event: InputEventKey = InputEventKey.new()
		event.unicode = text.unicode_at(index)
		event.pressed = true
		event.window_id = edit.get_window().get_window_id()
		edit.get_viewport().push_input(event, true)
		event = event.duplicate()
		event.pressed = false
		edit.get_viewport().push_input(event, true)
	await plugin.get_tree().process_frame


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


func _read_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _write_file(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Appends a trailing space to the first non-empty line strictly after the
## header line -- a real one-byte body mutation that never touches the
## header's own JSON (mirrors tests/gst_editor_smoke.gd's/
## tests/gst_editor_documents_smoke.gd's own _mutate_body_line).
func _mutate_body_line(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	for i: int in range(lines.size()):
		if lines[i].begins_with(GSTHeader.HEADER_PREFIX):
			for j: int in range(i + 1, lines.size()):
				if not lines[j].is_empty():
					lines[j] = lines[j] + " "
					return "\n".join(lines)
	return text


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
