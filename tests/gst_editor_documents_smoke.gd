@tool
extends RefCounted

## Phase 3 (docs/SHADER_TABS_reviewed-plan.md): runtime document ownership.
## Drives the real production panel to prove GSTDocument's own guarantees --
## none of it exposed through visible tab controls yet (phase 4 wires
## those): independent recipe copies, baseline/dirty rules, canonical path
## reuse, failed open, stable ids, alternating undo/redo across inactive
## histories, and inactive-document callback isolation. Drives
## panel.open_document/activate_document/get_documents/get_active_document
## directly, the same seams New/Open/Reopen Shader/Recipes call internally.

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

	var initial_doc: GSTDocument = panel.get_active_document()
	_check("initial_document", initial_doc != null and panel.get_documents().has(initial_doc), "active=%s in_list=%s" % [initial_doc != null, panel.get_documents().has(initial_doc) if initial_doc != null else false])

	# --- Independent recipe copies + stable ids (repeated recipes create
	# independent layer/coord instances, never a shared one). ---
	var docs_before_fire: int = panel.get_documents().size()
	panel.open_recipe("fire")
	await plugin.get_tree().process_frame
	var fire_a: GSTDocument = panel.get_active_document()
	panel.open_recipe("fire")
	await plugin.get_tree().process_frame
	var fire_b: GSTDocument = panel.get_active_document()
	var independent_ok: bool = fire_a != null and fire_b != null and fire_a != fire_b and fire_a.session_id != fire_b.session_id and fire_a.stack != fire_b.stack and panel.get_documents().size() == docs_before_fire + 2
	var same_layer_count: bool = independent_ok and fire_a.stack.layers.size() == fire_b.stack.layers.size() and fire_a.stack.layers.size() > 0
	_check("independent_recipe_copies", independent_ok and same_layer_count, "distinct=%s ids=%s/%s layers=%d/%d docs=%d->%d" % [fire_a != fire_b if fire_a != null and fire_b != null else false, fire_a.session_id if fire_a != null else -1, fire_b.session_id if fire_b != null else -1, fire_a.stack.layers.size() if fire_a != null else -1, fire_b.stack.layers.size() if fire_b != null else -1, docs_before_fire, panel.get_documents().size()])
	if not independent_ok:
		_finish(plugin)
		return

	# --- Unsaved recipe/import content starts dirty (fix pass 1, round 1,
	# item 3): GSTDocument.setup's starts_dirty leaves no saved baseline for
	# content that has nowhere on disk it already matches. ---
	_check("recipe_documents_start_dirty", fire_a.is_dirty() and fire_b.is_dirty(), "fire_a.is_dirty()=%s fire_b.is_dirty()=%s" % [fire_a.is_dirty(), fire_b.is_dirty()])

	var fbm_a: GSTLayer = _find_layer_by_entry(fire_a.stack, "generative/fbm")
	var fbm_b: GSTLayer = _find_layer_by_entry(fire_b.stack, "generative/fbm")
	var distinct_layers: bool = fbm_a != null and fbm_b != null and fbm_a != fbm_b and fbm_a.coord != fbm_b.coord
	var gain_before_a: float = float(fbm_a.get(&"gain")) if fbm_a != null else 0.0
	if fbm_b != null:
		var gain_before_b: float = float(fbm_b.get(&"gain"))
		fbm_b.set(&"gain", 0.77)
		fire_b.undo.commit_property_change(fbm_b, &"gain", gain_before_b, 0.77)
	var isolation_ok: bool = distinct_layers and fbm_a != null and is_equal_approx(float(fbm_a.get(&"gain")), gain_before_a) and fbm_b != null and is_equal_approx(float(fbm_b.get(&"gain")), 0.77)
	_check("independent_layer_instances", isolation_ok, "distinct=%s a_gain=%s (unchanged) b_gain=%s (edited to 0.77)" % [distinct_layers, fbm_a.get(&"gain") if fbm_a != null else null, fbm_b.get(&"gain") if fbm_b != null else null])

	# --- Navigation registers no action anywhere; stable session ids. ---
	panel.activate_document(fire_a)
	await plugin.get_tree().process_frame
	var history_a: UndoRedo = panel.get_watched_history()
	var id_a_before: int = fire_a.session_id
	var fill_a: GSTLayer = panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	var count_a_after_add: int = history_a.get_history_count()

	panel.activate_document(fire_b)
	await plugin.get_tree().process_frame
	var history_b: UndoRedo = panel.get_watched_history()
	var switch_to_b_ok: bool = panel.get_active_document() == fire_b and fire_b.session_id != -1 and history_b.get_history_count() == 1 and history_a.get_history_count() == count_a_after_add

	panel.activate_document(fire_a)
	await plugin.get_tree().process_frame
	var switch_back_ok: bool = panel.get_active_document() == fire_a and fire_a.session_id == id_a_before and panel.get_watched_history() == history_a and history_a.get_history_count() == count_a_after_add and panel.get_stack() == fire_a.stack
	_check("navigation_adds_no_action_and_ids_stable", switch_to_b_ok and switch_back_ok, "b_ok=%s a_back_ok=%s b_count=%d a_count=%d->%d" % [switch_to_b_ok, switch_back_ok, history_b.get_history_count(), count_a_after_add, history_a.get_history_count()])

	# --- Alternating undo/redo: each document's history is independent of
	# navigation in between. ---
	history_a.undo()
	await plugin.get_tree().process_frame
	var fire_a_undone: bool = GSTStackOps.find_layer(fire_a.stack, fill_a.id) == null

	panel.activate_document(fire_b)
	await plugin.get_tree().process_frame
	var fire_b_untouched_by_a_undo: bool = fbm_b != null and is_equal_approx(float(fbm_b.get(&"gain")), 0.77) and panel.get_watched_history().has_undo()
	history_b = panel.get_watched_history()
	history_b.undo()
	await plugin.get_tree().process_frame
	var fire_b_gain_restored: bool = fbm_b != null and is_equal_approx(float(fbm_b.get(&"gain")), gain_before_a)

	panel.activate_document(fire_a)
	await plugin.get_tree().process_frame
	var fire_a_still_undone_after_switching: bool = GSTStackOps.find_layer(fire_a.stack, fill_a.id) == null
	history_a = panel.get_watched_history()
	history_a.redo()
	await plugin.get_tree().process_frame
	var fire_a_redone: bool = GSTStackOps.find_layer(fire_a.stack, fill_a.id) == fill_a
	_check("alternating_undo_redo_independent", fire_a_undone and fire_b_untouched_by_a_undo and fire_b_gain_restored and fire_a_still_undone_after_switching and fire_a_redone, "a_undone=%s b_untouched_by_a=%s b_restored=%s a_still_undone_after_switch=%s a_redone=%s" % [fire_a_undone, fire_b_untouched_by_a_undo, fire_b_gain_restored, fire_a_still_undone_after_switching, fire_a_redone])

	# --- Inactive-document callback isolation: mutating a document that is
	# not active must never call the active-panel mutation callbacks
	# against the wrong stack. ---
	var stack_list_count_before: int = panel.get_stack_list().get_item_count()
	var active_before_inactive_mutation: GSTDocument = panel.get_active_document()
	fire_b.undo.add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	var active_ui_untouched: bool = panel.get_stack_list().get_item_count() == stack_list_count_before and panel.get_active_document() == active_before_inactive_mutation
	_check("inactive_document_mutation_does_not_touch_active_ui", active_ui_untouched, "stack_list_count %d->%d active_unchanged=%s" % [stack_list_count_before, panel.get_stack_list().get_item_count(), panel.get_active_document() == active_before_inactive_mutation])

	# --- Fixture-only replace_stack binds its action and its new adapter's
	# callbacks to the document active when it was called, not to whichever
	# document is active at replay time (fix pass 1, round 1, item 2):
	# undo/redo of that action while a different document is active must
	# rewrite only the owning document, never the active one. ---
	var original_fire_a_stack: GSTStack = fire_a.stack
	var replaced_stack: GSTStack = GSTStack.new()
	panel.replace_stack(replaced_stack, "", false)
	await plugin.get_tree().process_frame
	var replace_applied: bool = fire_a.stack == replaced_stack
	var replace_history: UndoRedo = fire_a.undo_redo
	panel.activate_document(fire_b)
	await plugin.get_tree().process_frame
	var stack_list_count_before_inactive_replay: int = panel.get_stack_list().get_item_count()
	replace_history.undo()
	await plugin.get_tree().process_frame
	var fire_a_reverted: bool = fire_a.stack == original_fire_a_stack
	var active_untouched_by_undo: bool = panel.get_active_document() == fire_b and panel.get_stack_list().get_item_count() == stack_list_count_before_inactive_replay and panel.get_stack() == fire_b.stack
	replace_history.redo()
	await plugin.get_tree().process_frame
	var fire_a_reapplied: bool = fire_a.stack == replaced_stack
	var active_untouched_by_redo: bool = panel.get_active_document() == fire_b and panel.get_stack_list().get_item_count() == stack_list_count_before_inactive_replay and panel.get_stack() == fire_b.stack
	_check("inactive_replacement_undo_redo_does_not_touch_active_document", replace_applied and fire_a_reverted and active_untouched_by_undo and fire_a_reapplied and active_untouched_by_redo, "applied=%s reverted=%s undo_active_ok=%s reapplied=%s redo_active_ok=%s" % [replace_applied, fire_a_reverted, active_untouched_by_undo, fire_a_reapplied, active_untouched_by_redo])
	# Leaves fire_a back on its own original stack (fbm_a's own stack), not
	# replaced_stack's empty one, so every later check below that reads
	# fbm_a through fire_a keeps finding it. Also clears fire_a's own
	# history: undoing here without redoing back to the tip leaves a
	# discarded "GST: Replace stack" redo entry sitting on top of position 1
	# of 2; UndoRedo.commit_action truncates that orphaned entry the next
	# time anything commits a new action on this same history (correct
	# UndoRedo behavior, matching what a real new edit after a real undo
	# does), which would otherwise make the next check below's own
	# count-before/count-after arithmetic land on the wrong number for a
	# reason unrelated to what it is actually testing.
	replace_history.undo()
	await plugin.get_tree().process_frame
	replace_history.clear_history()

	# --- Pending native edits finish on the originating document before
	# activate_document() switches ownership (fix pass 1, round 1, item 1):
	# a numeric drag and a native color popup edit, each still in flight
	# when the switch happens, must land on fire_a and never touch fire_b. ---
	panel.activate_document(fire_a)
	await plugin.get_tree().process_frame
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var stack_list: GSTStackList = panel.get_stack_list()
	stack_list.select_layer(fbm_a.id)
	await plugin.get_tree().process_frame

	var gain_property: EditorProperty = inspector.find_editor_property(&"gain", fbm_a)
	var gain_spin: EditorSpinSlider = null
	if gain_property != null:
		for spin_node: Node in gain_property.find_children("*", "EditorSpinSlider", true, false):
			gain_spin = spin_node as EditorSpinSlider
			break
	# Captured now, not re-read after the switch below: activate_document
	# rebuilds the inspector rows for fire_b, freeing gain_spin/gain_property.
	var gain_spin_found: bool = gain_spin != null
	var numeric_pending_ok: bool = false
	if gain_spin != null:
		var history_a_numeric: UndoRedo = fire_a.undo_redo
		var count_a_before_numeric: int = history_a_numeric.get_history_count()
		var original_gain: float = float(fbm_a.get(&"gain"))
		gain_spin.grabbed.emit()
		gain_property.emit_changed(&"gain", original_gain + 0.11, &"", true)
		await plugin.get_tree().process_frame
		var mid_gesture_value: float = float(fbm_a.get(&"gain"))
		await panel.activate_document(fire_b)
		await plugin.get_tree().process_frame
		# fbm_b's own gain reads gain_before_a here, not the 0.77 it was
		# edited to above: the alternating-undo/redo section already
		# undid that edit on fire_b's own history and never redid it.
		numeric_pending_ok = history_a_numeric.get_history_count() == count_a_before_numeric + 1 and is_equal_approx(float(fbm_a.get(&"gain")), mid_gesture_value) and not is_equal_approx(mid_gesture_value, original_gain) and panel.get_active_document() == fire_b and fbm_b != null and is_equal_approx(float(fbm_b.get(&"gain")), gain_before_a)
	_check("numeric_pending_edit_finishes_before_document_activation", numeric_pending_ok, "gain_spin_found=%s" % [gain_spin_found])

	panel.activate_document(fire_a)
	await plugin.get_tree().process_frame
	var palette_a: GSTLayer = stack_list.add_layer_by_entry_id("color/palette")
	stack_list.select_layer(palette_a.id)
	await plugin.get_tree().process_frame
	var color_property: EditorProperty = inspector.find_editor_property(&"a", palette_a)
	if color_property != null:
		inspector.get_settings_scroll().ensure_control_visible(color_property)
		await plugin.get_tree().process_frame
	var color_button: ColorPickerButton = _find_color_button(color_property)
	# Captured now, not re-read after the switch below (same reason as
	# gain_spin_found above).
	var color_button_found: bool = color_button != null
	var color_pending_ok: bool = false
	var hex_edit_found: bool = false
	if color_button != null:
		var history_a_color: UndoRedo = fire_a.undo_redo
		var count_a_before_color: int = history_a_color.get_history_count()
		color_button.grab_focus()
		color_button.get_popup().popup()
		await _frames(plugin, 2)
		var hex_edit: LineEdit = _find_hex_line_edit(color_button.get_picker())
		hex_edit_found = hex_edit != null
		if hex_edit != null:
			await _type_into_line_edit(plugin, hex_edit, "112233")
		# Genuinely awaited, not fire-and-forget: closing a native color
		# popup's own close handler is connected CONNECT_DEFERRED, so
		# finishing it spans more than one frame and the switch below must
		# not be read as complete until activate_document's own await
		# actually returns.
		await panel.activate_document(fire_b)
		await plugin.get_tree().process_frame
		var expected_color: Color = Color(0x11 / 255.0, 0x22 / 255.0, 0x33 / 255.0, 1.0)
		color_pending_ok = hex_edit_found and history_a_color.get_history_count() == count_a_before_color + 1 and (palette_a.get(&"a") as Color).is_equal_approx(expected_color) and panel.get_active_document() == fire_b
	_check("color_pending_edit_finishes_before_document_activation", color_pending_ok, "color_button_found=%s hex_edit_found=%s" % [color_button_found, hex_edit_found])
	panel.activate_document(fire_a)
	await plugin.get_tree().process_frame

	# --- Baseline/dirty rules. ---
	var docs_before_pristine_new: int = panel.get_documents().size()
	var pristine: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	var pristine_clean: bool = pristine != null and not pristine.is_dirty()
	var fill_layer: GSTLayer = panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	var dirty_after_structural_add: bool = pristine.is_dirty()
	panel.get_watched_history().undo()
	await plugin.get_tree().process_frame
	# Decision 22: undo of an add never reverts stack.next_id (ids are never
	# reused), and the fingerprint includes next_id (phase 3: "Include
	# next_id and raw parameter-key presence"), so this document remains
	# dirty relative to its pristine-empty baseline even after the add is
	# fully undone -- not a bug, the documented fingerprint consequence.
	var still_dirty_after_undoing_the_add: bool = pristine.is_dirty()
	_check("baseline_dirty_after_structural_add", pristine_clean and dirty_after_structural_add and still_dirty_after_undoing_the_add, "pristine_clean=%s dirty_after_add=%s still_dirty_after_undo=%s (decision 22: next_id never reverts)" % [pristine_clean, dirty_after_structural_add, still_dirty_after_undoing_the_add])

	panel.get_watched_history().redo()
	await plugin.get_tree().process_frame
	pristine.mark_baseline()
	var clean_after_marking_new_baseline: bool = not pristine.is_dirty()
	var old_color: Color = fill_layer.get(&"color")
	var old_color_present: bool = fill_layer.has_param_value(&"color")
	var new_color: Color = Color(0.1, 0.2, 0.3, 1.0)
	fill_layer.set(&"color", new_color)
	panel.get_undo().commit_property_change(fill_layer, &"color", old_color, new_color, Callable(), old_color_present)
	var dirty_after_property_edit: bool = pristine.is_dirty()
	panel.get_watched_history().undo()
	await plugin.get_tree().process_frame
	var clean_after_property_undo: bool = not pristine.is_dirty()
	_check("baseline_dirty_rules_property_edit", clean_after_marking_new_baseline and dirty_after_property_edit and clean_after_property_undo, "clean_after_new_baseline=%s dirty_after_edit=%s clean_after_undo=%s" % [clean_after_marking_new_baseline, dirty_after_property_edit, clean_after_property_undo])

	# open_document's own reuse of a still-open, never-edited document (fix
	# pass 1, round 1, item 4): the "New" call above must have reactivated
	# initial_doc -- the only open document with no path and no dirty
	# content at that point -- instead of allocating a second one.
	var pristine_reused_initial_document: bool = pristine == initial_doc and panel.get_documents().size() == docs_before_pristine_new
	_check("pristine_initial_document_reused", pristine_reused_initial_document, "pristine_is_initial_doc=%s docs=%d->%d (expect unchanged)" % [pristine == initial_doc, docs_before_pristine_new, panel.get_documents().size()])

	# --- Save marks a new baseline; canonical path reuse activates the
	# existing document instead of creating a second one. ---
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	var save_path: String = "user://gst_tabs_documents_save.tres"
	_cleanup([save_path])
	panel.save_to_path(save_path)
	await plugin.get_tree().process_frame
	var saved_clean: bool = not pristine.is_dirty() and pristine.current_path == save_path
	_check("save_marks_baseline", saved_clean, "dirty=%s path='%s' (expect '%s')" % [pristine.is_dirty(), pristine.current_path, save_path])

	panel.activate_document(fire_a)
	await plugin.get_tree().process_frame
	var docs_before_reopen_path: int = panel.get_documents().size()
	panel.open_path(save_path)
	await plugin.get_tree().process_frame
	var reused_existing: bool = panel.get_active_document() == pristine and panel.get_documents().size() == docs_before_reopen_path
	_check("canonical_path_reuse", reused_existing, "active_is_pristine=%s docs=%d->%d" % [panel.get_active_document() == pristine, docs_before_reopen_path, panel.get_documents().size()])

	# --- Canonical identity matches filesystem semantics, not just exact
	# spelling (fix pass 1, round 1, item 5): the same file opened again
	# through an upper-cased absolute-path spelling reuses pristine on
	# Windows' case-insensitive filesystem instead of creating a second
	# document. ---
	panel.activate_document(fire_a)
	await plugin.get_tree().process_frame
	var alternate_spelling: String = ProjectSettings.globalize_path(save_path).to_upper()
	var docs_before_alternate_spelling: int = panel.get_documents().size()
	panel.open_path(alternate_spelling)
	await plugin.get_tree().process_frame
	var alternate_spelling_reused: bool = panel.get_active_document() == pristine and panel.get_documents().size() == docs_before_alternate_spelling
	_check("canonical_path_reuse_alternate_spelling", alternate_spelling_reused, "active_is_pristine=%s docs=%d->%d path='%s'" % [panel.get_active_document() == pristine, docs_before_alternate_spelling, panel.get_documents().size(), alternate_spelling])
	_cleanup([save_path])

	# --- _canonical_path_for's case-fold gate, forced independently of the
	# real platform (phase 3 review round 2 fix-now note 1): with
	# case_insensitive=false (a case-sensitive filesystem, e.g. Linux),
	# distinct-case spellings like Fire.tres/fire.tres must stay distinct
	# instead of always collapsing into the same document, the defect fix
	# 5 above introduced by folding unconditionally. With
	# case_insensitive=true they must still fold together, matching the
	# instance method's own real behavior on Windows/macOS already proven
	# above by canonical_path_reuse_alternate_spelling's actual document
	# reuse. ---
	var case_sensitive_fire: String = GSTMainPanel._canonical_path_for("user://Fire.tres", false)
	var case_sensitive_fire_lower: String = GSTMainPanel._canonical_path_for("user://fire.tres", false)
	var case_insensitive_fire: String = GSTMainPanel._canonical_path_for("user://Fire.tres", true)
	var case_insensitive_fire_lower: String = GSTMainPanel._canonical_path_for("user://fire.tres", true)
	var case_fold_gated_ok: bool = case_sensitive_fire != case_sensitive_fire_lower and case_insensitive_fire == case_insensitive_fire_lower
	_check("canonical_path_case_fold_gated_by_platform", case_fold_gated_ok, "case_sensitive: '%s' vs '%s' (expect distinct); case_insensitive: '%s' vs '%s' (expect equal)" % [case_sensitive_fire, case_sensitive_fire_lower, case_insensitive_fire, case_insensitive_fire_lower])

	# --- Failed open creates no document and leaves the active document
	# untouched. ---
	var docs_before_failed_open: int = panel.get_documents().size()
	var active_before_failed_open: GSTDocument = panel.get_active_document()
	panel.open_path("res://sandbox/stacks/gst_tabs_documents_missing.tres")
	await plugin.get_tree().process_frame
	var failed_open_ok: bool = panel.get_documents().size() == docs_before_failed_open and panel.get_active_document() == active_before_failed_open and not panel.get_message_label().text.is_empty()
	_check("failed_open_creates_no_document", failed_open_ok, "docs=%d->%d active_unchanged=%s message='%s'" % [docs_before_failed_open, panel.get_documents().size(), panel.get_active_document() == active_before_failed_open, panel.get_message_label().text])

	# --- Reopen Shader: unsaved origin, body-difference warning preserved,
	# independent of the exporting document. ---
	var export_path: String = "user://gst_tabs_documents_export.gdshader"
	_cleanup([export_path])
	panel.activate_document(fire_a)
	await plugin.get_tree().process_frame
	panel.export_to_path(export_path, false)
	await plugin.get_tree().process_frame
	var mutated: String = _mutate_body_line(_read_file(export_path))
	_write_file(export_path, mutated)
	var docs_before_reopen_shader: int = panel.get_documents().size()
	panel.reopen_shader_path(export_path)
	await plugin.get_tree().process_frame
	var reopened_doc: GSTDocument = panel.get_active_document()
	var reopen_ok: bool = reopened_doc != null and reopened_doc != fire_a and reopened_doc.current_path.is_empty() and panel.get_documents().size() == docs_before_reopen_shader + 1 and panel.get_message_label().text.contains("differs from a fresh codegen")
	_check("reopen_shader_unsaved_origin_and_warning", reopen_ok, "current_path='%s' new_document=%s docs=%d->%d message='%s'" % [reopened_doc.current_path if reopened_doc != null else "missing", reopened_doc != fire_a if reopened_doc != null else false, docs_before_reopen_shader, panel.get_documents().size(), panel.get_message_label().text])

	# --- Unsaved import content starts dirty, a successful save marks a new
	# baseline, and undo after an edit returns to that baseline (fix pass 1,
	# round 1, item 3, import side; the recipe side is covered by
	# recipe_documents_start_dirty above). ---
	var reopened_initially_dirty: bool = reopened_doc != null and reopened_doc.is_dirty()
	_check("reopened_import_starts_dirty", reopened_initially_dirty, "reopened.is_dirty()=%s" % [reopened_doc.is_dirty() if reopened_doc != null else null])
	var reopen_save_path: String = "user://gst_tabs_documents_reopen_save.tres"
	_cleanup([reopen_save_path])
	panel.save_to_path(reopen_save_path)
	await plugin.get_tree().process_frame
	var reopened_clean_after_save: bool = not reopened_doc.is_dirty() and reopened_doc.current_path == reopen_save_path
	# A property edit, not a structural add: decision 22 never reverts
	# stack.next_id on undo, so a structural add stays dirty relative to
	# this baseline even fully undone (documented above at
	# baseline_dirty_after_structural_add) -- proving undo returns to the
	# saved baseline itself needs the same property-edit-then-undo shape
	# baseline_dirty_rules_property_edit already uses.
	var reopened_fbm: GSTLayer = _find_layer_by_entry(reopened_doc.stack, "generative/fbm")
	var reopened_dirty_after_edit: bool = false
	var reopened_clean_after_undo: bool = false
	if reopened_fbm != null:
		var reopened_old_gain: float = float(reopened_fbm.get(&"gain"))
		var reopened_old_gain_present: bool = reopened_fbm.has_param_value(&"gain")
		var reopened_new_gain: float = reopened_old_gain + 0.11
		reopened_fbm.set(&"gain", reopened_new_gain)
		panel.get_undo().commit_property_change(reopened_fbm, &"gain", reopened_old_gain, reopened_new_gain, Callable(), reopened_old_gain_present)
		reopened_dirty_after_edit = reopened_doc.is_dirty()
		panel.get_watched_history().undo()
		await plugin.get_tree().process_frame
		reopened_clean_after_undo = not reopened_doc.is_dirty()
	_check("reopened_import_save_then_undo_returns_to_baseline", reopened_clean_after_save and reopened_fbm != null and reopened_dirty_after_edit and reopened_clean_after_undo, "clean_after_save=%s fbm_found=%s dirty_after_edit=%s clean_after_undo=%s" % [reopened_clean_after_save, reopened_fbm != null, reopened_dirty_after_edit, reopened_clean_after_undo])
	_cleanup([reopen_save_path, export_path])

	_finish(plugin)


func _find_layer_by_entry(stack: GSTStack, entry_id: String) -> GSTLayer:
	for layer: GSTLayer in stack.layers:
		if layer.entry == entry_id:
			return layer
	return null


## Real-popup color-edit helpers (mirrors tests/gst_editor_native_undo_smoke.gd's
## own helpers of the same name), needed here only for the
## color_pending_edit_finishes_before_document_activation check above.
func _frames(plugin: EditorPlugin, count: int) -> void:
	for i: int in range(count):
		await plugin.get_tree().process_frame


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


## Types text into edit without submitting it (no Enter, no focus change):
## a real pending, unevaluated entry, matching the production close path's
## own hex-text-commit-on-focus-exit contract.
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
	await _frames(plugin, 1)


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
## header's own JSON (mirrors tests/gst_editor_smoke.gd's _mutate_body_line).
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
