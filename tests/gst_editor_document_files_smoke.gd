@tool
extends RefCounted

## GST_EDITOR_SMOKE=tabs_files. Binds Save, Save As, Export, overwrite
## confirmation, preview-image selection, and delayed Open/Reopen Shader
## dialog responses to the document that opened the dialog. Drives the
## *_pressed handlers and the *_file_selected/_on_overwrite_confirmed seams
## directly, switching the active document between each open and its
## response. Every write is verified by reloading the file (GSTStackIO.load /
## GSTExport.build) against the originating document's stack.
##
## Closed targets are simulated by erasing the document from _documents and
## tearing it down; _run_real_close_then_stale_save_as_rejected covers the
## same shape through panel.close_document.

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

	# doc_a (fire, 6 layers) and doc_b (dissolve, 10 layers): distinct layer
	# counts so reloaded content identifies which document wrote it.
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


## Save As opened on doc_a, active switched to doc_b before the response.
## Asserts: write lands on doc_a, doc_b untouched, panel mirrors
## (get_active_document/get_current_path) still show doc_b.
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
	# _on_save_as_file_selected bypasses the dialog's own close; hide it or a
	# later popup_centered*() on another dialog fails with Window's "already
	# has another exclusive child".
	panel._save_as_dialog.hide()

	var doc_a_ok: bool = doc_a.current_path == save_path and not doc_a.is_dirty()
	var doc_b_untouched: bool = doc_b.current_path.is_empty() and doc_b.is_dirty()
	var active_unaffected: bool = panel.get_active_document() == doc_b and panel.get_current_path().is_empty()
	var loaded: Dictionary = GSTStackIO.load(save_path, panel.get_library())
	var content_is_doc_a: bool = loaded["ok"] and GSTDocument.compute_fingerprint(loaded["stack"]) == fingerprint_a
	_check("save_as_switch_writes_originating_document", doc_a_ok and doc_b_untouched and active_unaffected and content_is_doc_a, "doc_a_path='%s' (expect '%s') doc_a_dirty=%s doc_b_path='%s' doc_b_dirty=%s active_is_b=%s current_path='%s' loaded_ok=%s content_is_doc_a=%s" % [doc_a.current_path, save_path, doc_a.is_dirty(), doc_b.current_path, doc_b.is_dirty(), panel.get_active_document() == doc_b, panel.get_current_path(), loaded["ok"], content_is_doc_a])


## doc_a is saved at save_path by the check above. Save As from doc_b to the
## same canonical path must refuse rather than overwrite doc_a's file.
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


## Exports doc_a, hand-edits the file, then opens Export on doc_a, switches to
## doc_b, and resolves against the same path: GSTOverwriteCheck finds the
## on-disk body differs from a fresh codegen of its header and requires
## confirmation. Switches to doc_b again before confirming;
## _on_overwrite_confirmed must target doc_a. doc_a carries a structural edit
## throughout so both writes are proven to leave it dirty.
func _run_export_second_confirmation(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument, doc_b: GSTDocument) -> void:
	var export_path: String = "user://gst_tabs_files_export.gdshader"
	_cleanup([export_path])
	panel.activate_document(doc_a)
	await plugin.get_tree().process_frame
	# doc_a is clean after _run_save_as_switch; a structural edit makes it
	# dirty so a stray mark_baseline() in the export path would be detected.
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	var dirty_before_export: bool = doc_a.is_dirty()
	var expected_code: String = GSTExport.build(doc_a.stack, panel.get_library()).code

	# A real EditorFileDialog closes before _export_stack_to_path runs; the
	# direct _on_export_file_selected call skips that, so hide the dialog
	# first (Window's "already has another exclusive child" otherwise).
	panel._on_export_pressed()
	# abandon=false keeps the pending request for the _on_export_file_selected
	# call below; the default clears it.
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


## doc_c captures a Save As request, then is erased from _documents and torn
## down before the response arrives. Asserts: no file written, active
## document untouched, closed-target diagnostic on doc_a.operation_messages.
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


## Same bypass shape for Export: doc_c captures the request, is erased and
## torn down, _resolve_pending_document returns null, and the diagnostic must
## land on doc_a (active when the response resolves).
func _run_stale_closed_export_rejected(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument) -> void:
	var doc_c: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	panel._on_export_pressed()
	# abandon=false keeps the pending request for the _on_export_file_selected
	# call below.
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


## Same shape through panel.close_document: doc_c is clean, so it closes
## with no dialog. Asserts close teardown invalidates the pending Save As.
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


## Preview-image dialog opened on doc_a, resolved with doc_b active. Asserts
## doc_a.preview_image_path updates and doc_b's does not.
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


## Open dialog opened on doc_a (captured for message routing only; Open
## creates or reactivates its own document), resolved with doc_b active and a
## missing path. Asserts the failure message lands on doc_a, not doc_b.
func _run_open_message_routing(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument, doc_b: GSTDocument) -> void:
	var missing_path: String = "res://sandbox/stacks/gst_tabs_files_missing.tres"
	# Clears leftover messages from earlier checks on both documents; they
	# would otherwise make panel.get_message_label().text nonempty here.
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


## Same routing proof for the Reopen Shader dialog with a headerless .gdshader.
func _run_reopen_message_routing(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument, doc_b: GSTDocument) -> void:
	var headerless_path: String = "user://gst_tabs_files_headerless.gdshader"
	_write_file(headerless_path, "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0); }\n")
	# Clears leftover messages from earlier checks on both documents.
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


## EditorFileDialog.canceled on the Save As dialog must clear the pending
## request so no later response can resolve against it.
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


## Save to a path whose parent directory does not exist fails in
## ResourceSaver.save. Asserts the document keeps its path and dirty state
## and the failure reason lands on operation_messages["Save"]. A structural
## edit (panel.get_undo().add_layer) first makes doc_a dirty so dirty_before
## is true.
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


## A pristine document takes a failed Open's diagnostic (_open_path_for routes
## it onto _active_document), then _on_new_pressed reuses that same clean
## document (_find_reusable_pristine_document). Asserts New clears the "Open"
## entry from GSTDocument.operation_messages, not only _message_label.text;
## otherwise the next _refresh_operation_message_label() re-shows it.
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

	# A later message on the same document (a failed Save) must not resurrect
	# the cleared "Open" entry.
	var bad_path: String = "user://gst_tabs_files_missing_dir/gst_tabs_files_new_pristine_bad.tres"
	var result: Dictionary = await panel.save_to_path(bad_path)
	var later_message_is_save_only: bool = not result["ok"] and not pristine.operation_messages.has("Open") and panel.get_message_label().text.contains("Save") and not panel.get_message_label().text.contains("Open")
	_check("new_stale_open_message_does_not_reappear_on_later_message", later_message_is_save_only, "shown='%s' has_open_entry=%s" % [panel.get_message_label().text, pristine.operation_messages.has("Open")])


## open_document's await _finish_pending_edits() suspends open_path while a
## pending native color-popup commit resolves; the delayed Open message must
## route to the document open_path installs, not the one still active before
## the suspension. Setup mirrors tests/gst_editor_documents_smoke.gd's
## color_pending_edit_finishes_before_document_activation: a popped
## ColorPickerButton with typed, uncommitted hex text on a color/palette
## layer, a stale "Open" entry seeded on color_doc, then a fire-and-forget
## open_path on a second .tres. Polls (bounded) until activation completes:
## the native color popup's close handler is CONNECT_DEFERRED and can span
## more than one frame.
func _run_open_path_finishes_pending_color_edit(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	# _run_new_clears_stale_open_message leaves the "Add Layer" picker open
	# (_on_new_pressed calls _on_chooser_requested); open_document below
	# returns null while is_picker_open().
	if panel.is_picker_open():
		panel.get_picker().cancelled.emit()
		await plugin.get_tree().process_frame
	# "fire" carries a color/palette layer fed by generative/fbm;
	# add_layer_by_entry_id("color/palette") on an empty GSTStack.new()
	# refuses (GSTUndo.add_layer_for_ui: first layer must not need an input).
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
		# Not awaited: matches _on_open_file_selected's signal dispatch and
		# reproduces the suspension inside open_document's await
		# _finish_pending_edits().
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


## Real-popup color-edit helpers, same as tests/gst_editor_documents_smoke.gd's.
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


## Types text into edit without Enter or a focus change, leaving a pending
## uncommitted entry (the close path commits hex text on focus exit).
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


## Appends a trailing space to the first non-empty line after the header
## line: a body mutation that leaves the header JSON intact.
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
