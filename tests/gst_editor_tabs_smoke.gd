@tool
extends RefCounted

## Phase 4 (docs/SHADER_TABS_reviewed-plan.md): the visible shader-tab row and
## document activation/restoration it drives. Phase 3's tabs_documents proved
## GSTDocument's own state ownership through panel.open_document/
## activate_document called directly; this selector proves the same
## guarantees now reach the user through the real tab row -- title/dirty-star
## presentation, overflow scrolling, real Button.pressed clicks switching by
## stable id, selection/list-position restoration, canceling a stray picker
## on switch, finishing a pending native gesture on its own originating
## document before switching, per-document preview isolation, and the shared
## SubViewport's own render-loop pausing while the GoShade panel is hidden.
##
## Every real tab-button click below is followed by re-fetching that
## document's own Button through panel.get_tab_button() rather than reusing a
## Button captured before the click: _refresh_tabs() (gst_main_panel.gd)
## frees and rebuilds every tab Button on every activation, and a reference
## captured before a switch is queued for deletion by that same switch's own
## synchronous call chain -- reading it again after an awaited frame reads a
## freed object. Distinct documents are opened through panel.open_recipe()
## (phase 3: independent copy every time, never reused) except where a check
## specifically drives the trailing New control itself, which -- like the
## File > New handler it shares -- reuses an existing pristine document and
## immediately opens the Add-layer picker; that one call site cancels it
## explicitly before any further stack mutation.
##
## Round 1 fix pass: stable-ID switching and the reclick/keyboard-undo-focus
## checks below (_click_tab, _run_reclick_stays_selected_and_keyboard_undo_
## focus) drive real InputEventMouseButton press/release and InputEventKey
## Ctrl+Z/Ctrl+Shift+Z through the viewport (Input.parse_input_event /
## Viewport.push_input), matching the established pattern in
## tests/gst_editor_native_undo_smoke.gd's own _push_mouse/_push_key, instead
## of calling Button.pressed.emit() directly -- emitting the signal bypasses
## BaseButton's own on_action_event entirely, so it can neither reproduce nor
## catch a toggle-mode/button_group regression (fix 1) or a focus-transfer
## regression (fix 2), both of which only exist in that engine-side path.

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
	var initial_button: Button = panel.get_tab_button(initial_doc)
	_check("initial_tab_present", initial_button != null and initial_button.text == "Untitled 1", "text='%s'" % [initial_button.text if initial_button != null else "<missing>"])

	# One-time engine warm-up (round 1 fix pass): the very first synthetic
	# InputEventMouseButton press delivered in a fresh editor session hits
	# Viewport's own stale-subwindow-focus-clearing path once
	# (scene/main/viewport.cpp Viewport::_sub_windows_forward_input, "no
	# window found and clicked, remove focus") and is consumed there without
	# reaching on_action_event; every click after the first behaves
	# normally. Observed directly in this same isolated session: an
	# identical real click on the already-active tab failed silently on the
	# very first attempt and succeeded on every later attempt. Absorbed
	# here, on the harmless already-active tab (a no-op reclick per fix 1),
	# before any assertion-bearing click below -- not a gst_main_panel.gd
	# defect, since no production code runs differently on a first vs. later
	# click.
	await _click_tab(plugin, panel, initial_doc)

	var saved_doc: GSTDocument = await _run_title_lifecycle(plugin, panel, initial_doc)
	var fire_doc: GSTDocument = await _run_recipe_title(plugin, panel)
	var working_doc: GSTDocument = await _run_stable_id_switching(plugin, panel, saved_doc, fire_doc)
	await _capture_tab_row_evidence(plugin)
	await _run_reclick_stays_selected_and_keyboard_undo_focus(plugin, panel, saved_doc, fire_doc)
	await _run_selection_and_scroll_restoration(plugin, panel, working_doc, fire_doc)
	await _run_scroll_state_no_bleed_across_documents(plugin, panel, working_doc, fire_doc, saved_doc)
	await _run_stale_picker_cancelled_on_switch(plugin, panel, working_doc, fire_doc)
	await _run_finish_before_switch(plugin, panel, working_doc, fire_doc)
	await _run_active_only_viewport_updates(plugin, panel)
	await _run_invalid_document_isolation(plugin, panel)
	await _run_long_title_and_overflow(plugin, panel)
	await _run_narrow_layout(plugin, panel)
	await _run_twenty_layers_and_rects(plugin, panel)

	_finish(plugin)


## Title updates (decision 4) on the pristine bootstrap document: no star
## while clean, a star the instant a structural edit makes it dirty
## (_on_stack_changed's own _refresh_tabs() call), then the saved filename
## without extension and no star once GSTDocument.mark_baseline() runs
## (save_to_path's own _refresh_tabs() call). Returns doc for later reuse as
## a second, always-open tab distinct from the working documents built below.
func _run_title_lifecycle(plugin: EditorPlugin, panel: GSTMainPanel, doc: GSTDocument) -> GSTDocument:
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	var dirty_button: Button = panel.get_tab_button(doc)
	_check("tab_title_dirty_star", dirty_button != null and dirty_button.text == "Untitled 1*", "text='%s'" % [dirty_button.text if dirty_button != null else "<missing>"])

	var save_path: String = "user://gst_tabs_ui_title_save.tres"
	_cleanup([save_path])
	panel.save_to_path(save_path)
	await plugin.get_tree().process_frame
	var saved_button: Button = panel.get_tab_button(doc)
	var saved_title_ok: bool = saved_button != null and saved_button.text == "gst_tabs_ui_title_save" and saved_button.tooltip_text == save_path
	_check("tab_title_saved", saved_title_ok, "text='%s' tooltip='%s' (expect '%s')" % [saved_button.text if saved_button != null else "<missing>", saved_button.tooltip_text if saved_button != null else "", save_path])
	return doc


## Recipe-name title, immediately dirty (decision 4: "unsaved nonempty
## recipe/import documents require saving" -- GSTDocument.setup's own
## starts_dirty leaves no baseline for recipe content to read clean against).
func _run_recipe_title(plugin: EditorPlugin, panel: GSTMainPanel) -> GSTDocument:
	panel.open_recipe("fire")
	await plugin.get_tree().process_frame
	var fire: GSTDocument = panel.get_active_document()
	var fire_button: Button = panel.get_tab_button(fire)
	var recipe_title_ok: bool = fire_button != null and fire_button.text == "Fire*" and fire_button.tooltip_text.contains("recipe 'fire'")
	_check("tab_title_recipe", recipe_title_ok, "text='%s' tooltip='%s'" % [fire_button.text if fire_button != null else "<missing>", fire_button.tooltip_text if fire_button != null else ""])
	return fire


## Stable-ID switching, driven by real Button.pressed clicks (round 1 fix:
## real InputEventMouseButton press/release through the viewport, not
## Button.pressed.emit()). Exercises the trailing New control once here (the
## one place this file drives it): like File > New, it reuses an existing
## pristine document and immediately opens the Add-layer picker, cancelled
## explicitly before returning so later checks can mutate the returned
## document's stack freely.
func _run_stable_id_switching(plugin: EditorPlugin, panel: GSTMainPanel, saved_doc: GSTDocument, fire_doc: GSTDocument) -> GSTDocument:
	panel.get_new_tab_button().pressed.emit()
	await plugin.get_tree().process_frame
	if panel.is_picker_open():
		panel.get_picker().cancelled.emit()
		await plugin.get_tree().process_frame
	var working_doc: GSTDocument = panel.get_active_document()
	var created_distinct: bool = working_doc != null and working_doc != saved_doc and working_doc != fire_doc

	await _click_tab(plugin, panel, saved_doc)
	var saved_button_after: Button = panel.get_tab_button(saved_doc)
	var switched_to_saved: bool = panel.get_active_document() == saved_doc and saved_button_after != null and saved_button_after.button_pressed

	await _click_tab(plugin, panel, fire_doc)
	var fire_button_after: Button = panel.get_tab_button(fire_doc)
	var saved_button_now: Button = panel.get_tab_button(saved_doc)
	var switched_to_fire: bool = panel.get_active_document() == fire_doc and fire_button_after != null and fire_button_after.button_pressed and saved_button_now != null and not saved_button_now.button_pressed
	_check("stable_id_switch_by_click", created_distinct and switched_to_saved and switched_to_fire, "created_distinct=%s switched_to_saved=%s switched_to_fire=%s" % [created_distinct, switched_to_saved, switched_to_fire])
	return working_doc


## Fix 1 (round 1 required fix): a real click on the already-active tab must
## keep it selected, not un-press it. base_button.cpp's on_action_event
## unconditionally toggles status.pressed, then _unpress_group() only forces
## it back to true when a button_group is present (verified against
## .now/tabs-validation/godot-4.4-source/scene/gui/base_button.cpp); without
## one, a synthetic pressed.emit() can never observe this, since it skips
## on_action_event/_unpress_group entirely.
##
## Fix 2 (round 1 required fix): _refresh_tabs() frees every tab Button on
## every activation, including whichever one the click above just focused;
## without an explicit transfer, the next Ctrl+Z has no live focus target
## left inside GoShade and fails _owns_undo_focus()'s gate. Proves a real
## click followed by real Ctrl+Z/Ctrl+Shift+Z reaches only the document that
## click activated: fire_doc gets its own unreverted edit first so a stray
## undo/redo landing on it instead of saved_doc is directly observable.
func _run_reclick_stays_selected_and_keyboard_undo_focus(plugin: EditorPlugin, panel: GSTMainPanel, saved_doc: GSTDocument, fire_doc: GSTDocument) -> void:
	await _click_tab(plugin, panel, fire_doc)
	await _click_tab(plugin, panel, fire_doc)
	var reclicked_button: Button = panel.get_tab_button(fire_doc)
	var reclick_stays_active: bool = panel.get_active_document() == fire_doc
	var reclick_stays_pressed: bool = reclicked_button != null and reclicked_button.button_pressed
	_check("active_tab_reclick_stays_selected", reclick_stays_active and reclick_stays_pressed, "active=%s pressed=%s" % [reclick_stays_active, reclick_stays_pressed])

	var history_saved: UndoRedo = saved_doc.undo_redo
	var saved_layers_before: int = saved_doc.stack.layers.size()

	await _click_tab(plugin, panel, saved_doc)
	panel.get_stack_list().add_layer_by_entry_id("generative/hash")
	await plugin.get_tree().process_frame
	var saved_layers_after_add: int = saved_doc.stack.layers.size()
	# UndoRedo.get_history_count() is actions.size() (core/object/undo_redo.
	# cpp), the total number of committed actions ever recorded -- it never
	# changes on undo()/redo() (only current_action does). get_current_action()
	# is the real undo-position counter.
	var saved_position_after_add: int = history_saved.get_current_action()

	# Establishes the real-world precondition a genuine click leaves behind
	# (focus on the just-activated tab's own Button) before the switch this
	# check actually measures. Verified in this isolated session: Viewport's
	# own click-to-focus grab is gated behind a separate hover-hierarchy
	# structure (gui.mouse_over_hierarchy, scene/main/viewport.cpp) that a
	# synthetic press/release never populates without a real DisplayServer
	# mouse-enter, so _click_tab's own NOTIFICATION_MOUSE_ENTER workaround
	# (which only supplies BaseButton's own status.hovering) reliably drives
	# the real toggle/activation click but not this separate focus grab. A
	# real hardware click always grants both; this grab_focus() call supplies
	# only the one piece this session cannot otherwise reproduce, so the
	# fix under test -- gst_main_panel.gd's _refresh_tabs() transferring that
	# focus onto the new active Button across its own rebuild -- is still
	# exercised for real by the click below.
	panel.get_tab_button(saved_doc).grab_focus()

	await _click_tab(plugin, panel, fire_doc)
	var history_fire: UndoRedo = fire_doc.undo_redo
	panel.get_stack_list().add_layer_by_entry_id("generative/hash")
	await plugin.get_tree().process_frame
	var fire_layers_after_add: int = fire_doc.stack.layers.size()
	var fire_position_after_add: int = history_fire.get_current_action()

	var focus_owner: Control = panel.get_viewport().gui_get_focus_owner()
	var active_button: Button = panel.get_tab_button(fire_doc)
	var focus_on_active_tab: bool = focus_owner == active_button

	_push_key(panel, KEY_Z, true, false)
	await plugin.get_tree().process_frame
	var undo_reached_fire: bool = fire_doc.stack.layers.size() == fire_layers_after_add - 1 and history_fire.get_current_action() == fire_position_after_add - 1
	var saved_untouched_by_undo: bool = saved_doc.stack.layers.size() == saved_layers_after_add and history_saved.get_current_action() == saved_position_after_add

	_push_key(panel, KEY_Z, true, true)
	await plugin.get_tree().process_frame
	var redo_reached_fire: bool = fire_doc.stack.layers.size() == fire_layers_after_add and history_fire.get_current_action() == fire_position_after_add
	var saved_untouched_by_redo: bool = saved_doc.stack.layers.size() == saved_layers_after_add and history_saved.get_current_action() == saved_position_after_add

	var ok: bool = focus_on_active_tab and undo_reached_fire and saved_untouched_by_undo and redo_reached_fire and saved_untouched_by_redo
	_check("click_then_keyboard_undo_redo_only_activated_document", ok, "focus_on_active_tab=%s undo_reached_fire=%s saved_untouched_undo=%s redo_reached_fire=%s saved_untouched_redo=%s saved_layers_before=%d" % [focus_on_active_tab, undo_reached_fire, saved_untouched_by_undo, redo_reached_fire, saved_untouched_by_redo, saved_layers_before])


## Selection and list-position restoration (phase 4: "restore stable-ID
## layer selection and list position"). Builds enough layers on working_doc
## to scroll, selects and scrolls away from the top, switches to fire_doc and
## back through real tab clicks, and checks both survive by stable id.
func _run_selection_and_scroll_restoration(plugin: EditorPlugin, panel: GSTMainPanel, working_doc: GSTDocument, fire_doc: GSTDocument) -> void:
	panel.get_tab_button(working_doc).pressed.emit()
	await plugin.get_tree().process_frame
	var list: GSTStackList = panel.get_stack_list()
	for i: int in range(12):
		list.add_layer_by_entry_id("generative/hash")
	await plugin.get_tree().process_frame
	var layers_built_ok: bool = panel.get_stack().layers.size() == 12
	var target_id: StringName = panel.get_stack().layers[3].id if layers_built_ok else &""
	list.select_layer(target_id)
	list.scroll_to_fraction(0.6)
	await plugin.get_tree().process_frame
	var anchor_before: StringName = list.get_scroll_anchor_id()
	var offset_before: float = list.get_scroll_offset()

	panel.get_tab_button(fire_doc).pressed.emit()
	await plugin.get_tree().process_frame
	panel.get_tab_button(working_doc).pressed.emit()
	await plugin.get_tree().process_frame

	var restored_list: GSTStackList = panel.get_stack_list()
	var selection_restored: bool = panel.get_active_document() == working_doc and restored_list.get_selected_layer_id() == target_id
	var anchor_restored: bool = restored_list.get_scroll_anchor_id() == anchor_before
	var offset_restored: bool = is_equal_approx(restored_list.get_scroll_offset(), offset_before)
	_check("selection_and_list_position_restored", layers_built_ok and selection_restored and anchor_restored and offset_restored, "layers_built=%s selection_restored=%s anchor=%s/%s offset=%.3f/%.3f" % [layers_built_ok, selection_restored, anchor_before, restored_list.get_scroll_anchor_id(), offset_before, restored_list.get_scroll_offset()])


## Fix-now S2 (phase 4 review round 2): a document that has never had its own
## scroll state captured must open at its own top, never bleed the previous
## document's own scrolled position just because both stacks' layer ids
## overlap -- ordinary, since every GSTStack's own next_id starts at 0
## (gst_stack_ops.gd), so any two documents built to the same layer count
## share the exact same id set. working_doc's own 12 layers from
## _run_selection_and_scroll_restoration above get 40 more (past what this
## editor window's own list area shows without a scrollbar -- confirmed in
## this session: that sibling check's own anchor stayed pinned to the top row
## before and after its round trip at only 12) so scroll_to_fraction(0.6)
## below lands on a real, non-top row. A brand-new document is then built to
## that exact same layer count by mutating its own GSTUndo directly while it
## is not the active document (mirrors _run_reclick_stays_selected_and_
## keyboard_undo_focus's own background-history pattern), so its own id set
## fully overlaps working_doc's -- including whichever id working_doc's own
## scroll landed on -- while its list_scroll_anchor_id stays at its true
## default (&"") through population: gst_stack_list.gd's refresh() only ever
## captures/restores this list's own currently-installed rows, so background
## mutation of an inactive document's stack never touches it. Switching
## directly from working_doc's scrolled tab to that new tab is then the exact
## first-activation-with-content case restore_scroll_state's own anchor_id ==
## &"" branch (gst_stack_list.gd) exists to cover. Checks both switch
## directions afterward: working_doc's own restore must not pick up the new
## document's later scroll, and the new document's own later scroll must not
## bleed back into working_doc either.
func _run_scroll_state_no_bleed_across_documents(plugin: EditorPlugin, panel: GSTMainPanel, working_doc: GSTDocument, fire_doc: GSTDocument, saved_doc: GSTDocument) -> void:
	panel.get_tab_button(working_doc).pressed.emit()
	await plugin.get_tree().process_frame
	var working_list: GSTStackList = panel.get_stack_list()
	for i: int in range(40):
		working_list.add_layer_by_entry_id("generative/hash")
	await plugin.get_tree().process_frame
	working_list.scroll_to_fraction(0.6)
	await plugin.get_tree().process_frame
	var working_anchor_before: StringName = working_list.get_scroll_anchor_id()
	var working_offset_before: float = working_list.get_scroll_offset()
	var working_scroll_moved: bool = working_anchor_before != working_list.get_item_id(0)
	var working_total: int = working_doc.stack.layers.size()

	panel.get_new_tab_button().pressed.emit()
	await plugin.get_tree().process_frame
	if panel.is_picker_open():
		panel.get_picker().cancelled.emit()
		await plugin.get_tree().process_frame
	var fresh_doc: GSTDocument = panel.get_active_document()
	var fresh_distinct: bool = fresh_doc != null and fresh_doc != working_doc and fresh_doc != fire_doc and fresh_doc != saved_doc

	# Switches away from fresh_doc while its own list is still empty (its
	# outgoing anchor capture is genuinely &"" -- get_scroll_anchor_id()
	# returns &"" for an empty list -- so this does not taint the
	# never-captured precondition the switch below depends on) and lands back
	# on working_doc so the population below runs while fresh_doc is not
	# active.
	panel.get_tab_button(working_doc).pressed.emit()
	await plugin.get_tree().process_frame

	for i: int in range(working_total):
		fresh_doc.undo.add_layer_for_ui("generative/hash")
	var fresh_layers_ok: bool = fresh_doc.stack.layers.size() == working_total
	var overlapping_ids: bool = false
	for layer: GSTLayer in fresh_doc.stack.layers:
		if layer.id == working_anchor_before:
			overlapping_ids = true
			break
	var fresh_anchor_still_unset: bool = fresh_doc.list_scroll_anchor_id == &""

	panel.get_tab_button(fresh_doc).pressed.emit()
	await plugin.get_tree().process_frame
	var fresh_list: GSTStackList = panel.get_stack_list()
	var fresh_top_id: StringName = fresh_list.get_item_id(0)
	var fresh_starts_at_top: bool = fresh_list.get_item_count() == working_total and fresh_list.get_scroll_anchor_id() == fresh_top_id and is_equal_approx(fresh_list.get_scroll_offset(), 0.0)

	fresh_list.scroll_to_fraction(0.3)
	await plugin.get_tree().process_frame
	var fresh_anchor_before: StringName = fresh_list.get_scroll_anchor_id()
	var fresh_offset_before: float = fresh_list.get_scroll_offset()
	var fresh_scroll_moved: bool = fresh_anchor_before != fresh_top_id

	panel.get_tab_button(working_doc).pressed.emit()
	await plugin.get_tree().process_frame
	var restored_working_list: GSTStackList = panel.get_stack_list()
	var working_restored_ok: bool = restored_working_list.get_scroll_anchor_id() == working_anchor_before and is_equal_approx(restored_working_list.get_scroll_offset(), working_offset_before)

	panel.get_tab_button(fresh_doc).pressed.emit()
	await plugin.get_tree().process_frame
	var restored_fresh_list: GSTStackList = panel.get_stack_list()
	var fresh_restored_ok: bool = restored_fresh_list.get_scroll_anchor_id() == fresh_anchor_before and is_equal_approx(restored_fresh_list.get_scroll_offset(), fresh_offset_before)

	var ok: bool = fresh_distinct and fresh_layers_ok and overlapping_ids and fresh_anchor_still_unset and working_scroll_moved and fresh_starts_at_top and fresh_scroll_moved and working_restored_ok and fresh_restored_ok
	_check("scroll_state_no_bleed_across_documents", ok, "fresh_distinct=%s fresh_layers_ok=%s overlapping_ids=%s fresh_anchor_still_unset=%s working_scroll_moved=%s(anchor=%s) fresh_starts_at_top=%s(top=%s) fresh_scroll_moved=%s working_restored=%s fresh_restored=%s" % [fresh_distinct, fresh_layers_ok, overlapping_ids, fresh_anchor_still_unset, working_scroll_moved, working_anchor_before, fresh_starts_at_top, fresh_top_id, fresh_scroll_moved, working_restored_ok, fresh_restored_ok])


## Stale picker cancellation (decision 5): an open chooser on the document
## being left must be cancelled, not left open against a stack the tab row
## is about to point the shared UI away from.
func _run_stale_picker_cancelled_on_switch(plugin: EditorPlugin, panel: GSTMainPanel, working_doc: GSTDocument, fire_doc: GSTDocument) -> void:
	panel.get_tab_button(working_doc).pressed.emit()
	await plugin.get_tree().process_frame
	var history: UndoRedo = working_doc.undo_redo
	var count_before: int = history.get_history_count()
	panel.get_stack_list().get_node("%AddButton").pressed.emit()
	await plugin.get_tree().process_frame
	var picker_was_open: bool = panel.is_picker_open()

	panel.get_tab_button(fire_doc).pressed.emit()
	await plugin.get_tree().process_frame
	var picker_cancelled: bool = not panel.is_picker_open()
	var no_stale_mutation: bool = history.get_history_count() == count_before
	var switched: bool = panel.get_active_document() == fire_doc
	_check("stale_picker_cancelled_on_switch", picker_was_open and picker_cancelled and no_stale_mutation and switched, "picker_was_open=%s cancelled=%s no_mutation=%s switched=%s" % [picker_was_open, picker_cancelled, no_stale_mutation, switched])


## Finish-before-switch (decision 5, phase 1/2/3 gesture boundary): a numeric
## gesture still in flight on the document being left must commit there,
## never reach the document the tab click switches to. Mirrors
## tests/gst_editor_documents_smoke.gd's own numeric_pending_edit check
## (synthetic EditorSpinSlider.grabbed + EditorProperty.emit_changed, not an
## actual mid-drag mouse interaction -- Shader tabs phase 3 review round 2
## fix-now S3), driven here through a real tab-button click instead of
## panel.activate_document called directly.
func _run_finish_before_switch(plugin: EditorPlugin, panel: GSTMainPanel, working_doc: GSTDocument, fire_doc: GSTDocument) -> void:
	panel.get_tab_button(working_doc).pressed.emit()
	await plugin.get_tree().process_frame
	var fbm: GSTLayer = panel.get_stack_list().add_layer_by_entry_id("generative/fbm")
	panel.get_stack_list().select_layer(fbm.id)
	await plugin.get_tree().process_frame

	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var gain_property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var gain_spin: EditorSpinSlider = null
	if gain_property != null:
		for spin_node: Node in gain_property.find_children("*", "EditorSpinSlider", true, false):
			gain_spin = spin_node as EditorSpinSlider
			break
	var gain_spin_found: bool = gain_spin != null
	var finish_before_switch_ok: bool = false
	if gain_spin != null:
		var origin_history: UndoRedo = working_doc.undo_redo
		var count_before: int = origin_history.get_history_count()
		var original_gain: float = float(fbm.get(&"gain"))
		gain_spin.grabbed.emit()
		gain_property.emit_changed(&"gain", original_gain + 0.13, &"", true)
		await plugin.get_tree().process_frame
		var mid_gesture_value: float = float(fbm.get(&"gain"))

		panel.get_tab_button(fire_doc).pressed.emit()
		await plugin.get_tree().process_frame
		var switched: bool = panel.get_active_document() == fire_doc
		finish_before_switch_ok = origin_history.get_history_count() == count_before + 1 and is_equal_approx(float(fbm.get(&"gain")), mid_gesture_value) and not is_equal_approx(mid_gesture_value, original_gain) and switched
	_check("finish_before_switch", finish_before_switch_ok, "gain_spin_found=%s" % [gain_spin_found])


## Active-only viewport updates (Cross-cutting "Explicitly control GSTPreview
## update mode so only active, visible GoShade content renders"): hiding the
## panel (a main-screen switch away from GoShade) pauses the shared
## SubViewport's own render loop; showing it again resumes it. Document
## material/state (proven isolated by tabs_documents/_run_invalid_document_
## isolation below) is untouched either way.
func _run_active_only_viewport_updates(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var preview: GSTPreview = panel.get_preview()
	var active_mode: int = preview.get_update_mode()
	panel.hide()
	await plugin.get_tree().process_frame
	var hidden_mode: int = preview.get_update_mode()
	panel.show()
	await plugin.get_tree().process_frame
	var restored_mode: int = preview.get_update_mode()
	_check("active_only_viewport_updates", active_mode == SubViewport.UPDATE_ALWAYS and hidden_mode == SubViewport.UPDATE_DISABLED and restored_mode == SubViewport.UPDATE_ALWAYS, "active=%d hidden=%d restored=%d (expect %d/%d/%d)" % [active_mode, hidden_mode, restored_mode, SubViewport.UPDATE_ALWAYS, SubViewport.UPDATE_DISABLED, SubViewport.UPDATE_ALWAYS])


## Per-document preview/error isolation across a switch: a codegen error
## forced onto one document must never appear, nor clear, on another, and
## must still be exactly the same message when switching back to the
## document that actually has it (docs/SHADER_TABS_reviewed.md "A
## deliberately invalid stack in one tab must not leak errors or
## last-successful preview into another tab"). broken_doc is built and
## broken first, while it is still the only pristine document, so the
## clean_doc opened afterward is guaranteed a distinct new document rather
## than open_document's own pristine-reuse landing back on broken_doc.
##
## Round 1 fix 4: also asserts actual material/render identity, not messages
## alone. broken_doc never reaches a successful compile (its own
## GSTMaterialSync.has_successful_preview() stays false: sync_preview's own
## contract on a codegen failure is "the material's shader and every uniform
## are left exactly as they were before the call", and reset_installation()
## installed only GSTMaterialSync.SAFE_TRANSPARENT_SHADER_CODE), so this
## initially-invalid document's own material can never carry clean_doc's
## compiled shader, and the reverse.
func _run_invalid_document_isolation(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var broken_doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	var stack: GSTStack = panel.get_stack()
	GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	panel.stack_changed.emit()
	await plugin.get_tree().process_frame
	var broken_message: String = panel.get_message_label().text
	var broken_message_present: bool = not broken_message.is_empty()
	var broken_material: ShaderMaterial = panel.get_shader_material()
	var broken_never_succeeded: bool = not broken_doc.preview_sync.has_successful_preview()
	var broken_material_is_own: bool = broken_material == broken_doc.material
	var broken_shader_is_safe: bool = broken_material != null and broken_material.shader != null and broken_material.shader.code == GSTMaterialSync.SAFE_TRANSPARENT_SHADER_CODE

	var clean_doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	var created_distinct: bool = clean_doc != broken_doc
	var clean_message_empty: bool = panel.get_message_label().text.is_empty()
	panel.get_stack_list().add_layer_by_entry_id("generative/hash")
	await plugin.get_tree().process_frame
	var clean_material: ShaderMaterial = panel.get_shader_material()
	var clean_has_success: bool = clean_doc.preview_sync.has_successful_preview()
	var distinct_material_instances: bool = clean_material != broken_material
	var clean_shader_differs_from_safe: bool = clean_material != null and clean_material.shader != null and clean_material.shader.code != GSTMaterialSync.SAFE_TRANSPARENT_SHADER_CODE

	panel.get_tab_button(broken_doc).pressed.emit()
	await plugin.get_tree().process_frame
	var restored_message: String = panel.get_message_label().text
	var restored_material: ShaderMaterial = panel.get_shader_material()
	var restored_material_is_broken_own: bool = restored_material == broken_doc.material and restored_material != clean_doc.material
	var restored_shader_still_safe: bool = restored_material != null and restored_material.shader != null and restored_material.shader.code == GSTMaterialSync.SAFE_TRANSPARENT_SHADER_CODE

	var ok: bool = created_distinct and broken_message_present and clean_message_empty and restored_message == broken_message and broken_never_succeeded and broken_material_is_own and broken_shader_is_safe and clean_has_success and distinct_material_instances and clean_shader_differs_from_safe and restored_material_is_broken_own and restored_shader_still_safe
	_check("invalid_document_no_previous_effect", ok, "distinct=%s broken_present=%s clean_empty=%s restored='%s' (expect '%s') broken_never_succeeded=%s broken_material_own=%s broken_shader_safe=%s clean_has_success=%s distinct_materials=%s clean_shader_differs=%s restored_material_own=%s restored_shader_safe=%s" % [created_distinct, broken_message_present, clean_message_empty, restored_message, broken_message, broken_never_succeeded, broken_material_is_own, broken_shader_is_safe, clean_has_success, distinct_material_instances, clean_shader_differs_from_safe, restored_material_is_broken_own, restored_shader_still_safe])


## Long titles (decision 4: "Beat: fixed-width tabs shrinking titles
## indefinitely") and horizontal overflow scrolling. Saves the currently
## active document (whatever _run_invalid_document_isolation left active)
## under a deliberately long filename: its tab stays clipped at a bounded
## width (never grows to fit, never shrinks below its floor) while the
## tooltip still carries the full path. Then opens enough independent recipe
## copies (phase 3: never reused) to exceed the row's own visible width,
## proving the scroll container's horizontal range becomes nonzero.
func _run_long_title_and_overflow(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var long_doc: GSTDocument = panel.get_active_document()
	var long_name: String = "a_deliberately_long_shader_filename_for_the_tab_overflow_measurement"
	var long_path: String = "user://%s.tres" % long_name
	_cleanup([long_path])
	panel.save_to_path(long_path)
	await plugin.get_tree().process_frame
	var long_button: Button = panel.get_tab_button(long_doc)
	var bounded_width: bool = long_button != null and long_button.size.x <= 200.0
	var full_tooltip: bool = long_button != null and long_button.tooltip_text == long_path
	_check("long_title_bounded_and_tooltip_full", bounded_width and full_tooltip, "width=%.1f tooltip='%s'" % [long_button.size.x if long_button != null else -1.0, long_button.tooltip_text if long_button != null else ""])
	_cleanup([long_path])

	for i: int in range(18):
		panel.open_recipe("fire")
		await plugin.get_tree().process_frame
	var scroll: ScrollContainer = panel.get_tab_scroll()
	var row: HBoxContainer = panel.get_tab_row()
	var h_scroll: HScrollBar = scroll.get_h_scroll_bar()
	var overflowed: bool = row.size.x > scroll.size.x and h_scroll.max_value > h_scroll.page
	_check("tab_row_overflow_scrolls", overflowed, "row_width=%.1f scroll_width=%.1f h_max=%.1f h_page=%.1f tab_count=%d" % [row.size.x, scroll.size.x, h_scroll.max_value, h_scroll.page, panel.get_documents().size()])


## Narrow layout (docs/DESIGN.md item 22): the tab row stays visible and
## functional at the same narrow width that collapses Layers/Layer settings
## into tabs, and the shared preview/output allocation measured through
## get_layout_measurements() stays governed by the same rules ui_layout_smoke
## already covers -- this only checks the new row does not break them.
##
## Round 1 fix 3: the prior pass only checked row_visible/active_button_present
## regardless of whether the resize actually crossed panel.get_layout_
## measurements()'s own tab_breakpoint (it did not: narrow read false), which
## proved nothing about narrow layout specifically. This measures the wide
## breakpoint and tab-row height first, resizes below that recorded
## breakpoint, and requires the crossing to have actually happened, plus
## (with the ~21 tabs already open from _run_long_title_and_overflow, so the
## row already overflows at every width) that the overflow scrollbar stays
## visible, the tab row's own height is unchanged by the narrower main split,
## and the active tab stays scrolled into view (gst_main_panel.gd's
## _on_tab_scroll_resized, round 1 fix 3: a resize alone, with no tab
## rebuild, must still keep it visible).
func _run_narrow_layout(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var original_window_size: Vector2i = DisplayServer.window_get_size()
	# Establishes a known wide baseline first (matching ui_layout_smoke.gd's
	# own 1366x768 baseline): this selector never otherwise sets an explicit
	# window size, so "wide" would otherwise mean whatever size the isolated
	# editor profile happened to start at, which is not guaranteed to be
	# above the measured breakpoint at all.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1366, 768))
	for i: int in range(8):
		await plugin.get_tree().process_frame
	var wide_measured: Dictionary = panel.get_layout_measurements()
	var row: HBoxContainer = panel.get_tab_row()
	var scroll: ScrollContainer = panel.get_tab_scroll()
	var row_height_wide: float = row.size.y
	var narrow_threshold: float = float(wide_measured["tab_breakpoint"])

	# Round 1 fix 3: a plain window resize alone does not reliably cross the
	# breakpoint (measured: 1366->1024 actual window width at this editor's
	# own docked-panel/side-panel proportions barely moved editing_rect.size.x
	# at all). ui_layout_smoke.gd's own established responsive_tabs check
	# never relies on the window resize alone either -- it additionally drags
	# %MainSplit itself once the window resize is not enough. Mirrored here
	# with the same drag mechanics (real mouse press/motion/release on the
	# splitter, tests/gst_editor_ui_layout_smoke.gd's own _drag_splitter).
	DisplayServer.window_set_size(Vector2i(720, 600))
	for i: int in range(8):
		await plugin.get_tree().process_frame
	if float(panel.get_layout_measurements()["editing_rect"].size.x) >= narrow_threshold:
		var main_split: HSplitContainer = panel.get_node("%MainSplit") as HSplitContainer
		var overshoot: float = float(panel.get_layout_measurements()["editing_rect"].size.x) - narrow_threshold + 24.0
		await _drag_main_split(plugin, main_split, -overshoot)
	# Extra settle margin: at a scaled editor content factor (150% runs),
	# _on_tab_scroll_resized's own deferred re-scroll needs more than one
	# frame after the window/splitter changes above finish landing.
	for i: int in range(6):
		await plugin.get_tree().process_frame

	var measured: Dictionary = panel.get_layout_measurements()
	var crossed_breakpoint: bool = bool(measured["narrow"]) and float(measured["editing_rect"].size.x) <= narrow_threshold + 0.5
	var row_visible: bool = row.is_visible_in_tree()
	var active_doc: GSTDocument = panel.get_active_document()
	var active_button: Button = panel.get_tab_button(active_doc)
	var active_button_present: bool = active_button != null
	var row_height_narrow: float = row.size.y
	var row_height_unchanged: bool = is_equal_approx(row_height_narrow, row_height_wide)
	var h_scroll: HScrollBar = scroll.get_h_scroll_bar()
	var scrollbar_visible_under_narrow: bool = h_scroll.max_value > h_scroll.page
	# 2026-09-15 layout pass: each tab's title Button now sits inside its own
	# per-tab wrapper container (gst_main_panel.gd _refresh_tabs, "tab x
	# inside the tab"), so its local .position is relative to that wrapper,
	# not the scrolling row directly -- global rects compared against the
	# scroll container's own global rect measure "inside the visible scroll
	# window" correctly regardless of that extra nesting level.
	var scroll_visible_start: float = scroll.get_global_rect().position.x
	var scroll_visible_end: float = scroll_visible_start + scroll.size.x
	var active_global_x: float = active_button.get_global_rect().position.x if active_button_present else 0.0
	var active_scrolled_into_view: bool = active_button_present and active_global_x >= scroll_visible_start - 2.0 and (active_global_x + active_button.size.x) <= scroll_visible_end + 2.0
	print("TABS_UI NARROW narrow_threshold=%.1f wide_editing_x=%.1f narrow_editing_x=%.1f row_height_wide=%.1f row_height_narrow=%.1f h_max=%.1f h_page=%.1f active_pos_x=%.1f visible=[%.1f,%.1f] measure=%s" % [narrow_threshold, float(wide_measured["editing_rect"].size.x), float(measured["editing_rect"].size.x), row_height_wide, row_height_narrow, h_scroll.max_value, h_scroll.page, active_global_x if active_button_present else -1.0, scroll_visible_start, scroll_visible_end, measured])

	var ok: bool = crossed_breakpoint and row_visible and active_button_present and row_height_unchanged and scrollbar_visible_under_narrow and active_scrolled_into_view
	_check("narrow_layout_tab_row_usable", ok, "crossed_breakpoint=%s(%.1f) row_visible=%s active_present=%s height_unchanged=%s(%.1f/%.1f) scrollbar_visible=%s scrolled_into_view=%s" % [crossed_breakpoint, narrow_threshold, row_visible, active_button_present, row_height_unchanged, row_height_wide, row_height_narrow, scrollbar_visible_under_narrow, active_scrolled_into_view])

	DisplayServer.window_set_size(original_window_size)
	for i: int in range(4):
		await plugin.get_tree().process_frame


## 20 layers and fixed preview/output placement across a tab switch: the
## shared editing/preview allocation (get_layout_measurements' own
## preview_rect/output_rect) must not move just because the active document
## changed underneath it (phase 4: "retains the current editing/preview
## width allocation"). doc is opened fresh here (no other pristine document
## remains at this point in the run, so open_document's own reuse check
## cannot land it on an existing one).
func _run_twenty_layers_and_rects(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var doc: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await plugin.get_tree().process_frame
	var list: GSTStackList = panel.get_stack_list()
	for i: int in range(20):
		list.add_layer_by_entry_id("generative/hash")
	await plugin.get_tree().process_frame
	var item_count_ok: bool = list.get_item_count() == 20
	var preview_before: Rect2 = panel.get_layout_measurements()["preview_rect"]
	var output_before: Rect2 = panel.get_layout_measurements()["output_rect"]

	panel.open_recipe("dissolve")
	await plugin.get_tree().process_frame
	panel.get_tab_button(doc).pressed.emit()
	await plugin.get_tree().process_frame

	var preview_after: Rect2 = panel.get_layout_measurements()["preview_rect"]
	var output_after: Rect2 = panel.get_layout_measurements()["output_rect"]
	var list_after_switch: GSTStackList = panel.get_stack_list()
	print("TABS_UI TWENTY_LAYERS preview_before=%s preview_after=%s output_before=%s output_after=%s" % [preview_before, preview_after, output_before, output_after])
	_check("twenty_layers_preview_output_rects_stable", item_count_ok and preview_before.is_equal_approx(preview_after) and output_before.is_equal_approx(output_after) and list_after_switch.get_item_count() == 20, "item_count=%d preview=%s/%s output=%s/%s" % [list_after_switch.get_item_count(), preview_before, preview_after, output_before, output_after])


## Real click on doc's own tab Button: press then release InputEventMouseButton
## at its global-rect center. Re-fetches the Button fresh (never reuses one
## captured before an earlier click in the same check), since _refresh_tabs()
## frees and rebuilds every tab Button on every activation.
##
## Verified against .now/tabs-validation/godot-4.4-source/scene/main/
## viewport.cpp: Viewport::_gui_input_event assigns gui.mouse_focus (the
## actual dispatch target for a press) via its own positional gui_find_
## control(mpos) lookup, independent of hover state -- confirmed working in
## this same isolated editor session by _drag_main_split's own real
## HSplitContainer drag above, which depends on that exact same positional
## dispatch. BaseButton::on_action_event additionally gates a mouse-button
## event behind status.hovering specifically (mouse_button.is_null() ||
## status.hovering), which this session's synthetic Input.parse_input_event/
## Viewport.push_input calls never establish for a Button: Viewport's own
## hover tracking (gui.mouse_over/_update_mouse_over) requires the viewport
## to already believe the OS cursor is inside the window, which no synthetic
## event drives without a real DisplayServer mouse-enter -- confirmed by
## Viewport.gui_get_hovered_control() staying null immediately after an
## injected motion event pushed at the button's own real global-rect center.
## NOTIFICATION_MOUSE_ENTER is public documented API
## (Control.NOTIFICATION_MOUSE_ENTER, Object.notification()); calling it here
## supplies only that one otherwise-unreachable piece of engine state so the
## rest of the click -- on_action_event's real toggle/button_group logic, the
## real activate_document call from Button.pressed, and the real focus grab
## this fix's own gst_main_panel.gd change performs -- all still run through
## their real, un-mocked production code paths.
func _click_tab(plugin: EditorPlugin, panel: GSTMainPanel, doc: GSTDocument) -> void:
	var button: Button = panel.get_tab_button(doc)
	var point: Vector2 = button.get_global_rect().get_center()
	button.notification(Control.NOTIFICATION_MOUSE_ENTER)
	_push_mouse(plugin, point, MOUSE_BUTTON_LEFT, true)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame
	_push_mouse(plugin, point, MOUSE_BUTTON_LEFT, false)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame


## Drags split's own divider by delta.x through real mouse press/motion/
## release (matching tests/gst_editor_ui_layout_smoke.gd's own _drag_splitter
## exactly): the narrow-layout check below uses this to force %MainSplit
## narrower when a window resize alone leaves editing_rect above the
## measured breakpoint.
## Deliberately independent of _push_mouse (which uses Viewport.push_input
## for real Button clicks): this instead matches
## tests/gst_editor_ui_layout_smoke.gd's own _drag_splitter exactly,
## including its Input.parse_input_event pipeline for all three events,
## since that is the already-proven-working mechanism for dragging
## %MainSplit specifically.
func _drag_main_split(plugin: EditorPlugin, split: HSplitContainer, delta: float) -> void:
	var first: Control = split.get_child(0) as Control
	var start: Vector2 = Vector2(first.get_global_rect().end.x + 1.0, split.get_global_rect().get_center().y)
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	press.global_position = start
	Input.parse_input_event(press)
	await plugin.get_tree().process_frame
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = start + Vector2(delta, 0.0)
	motion.global_position = motion.position
	motion.relative = Vector2(delta, 0.0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await plugin.get_tree().process_frame
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	release.global_position = motion.position
	Input.parse_input_event(release)
	for i: int in range(3):
		await plugin.get_tree().process_frame


## Delivered through plugin.get_viewport().push_input(event, true), matching
## tests/gst_editor_ui_complete_smoke.gd's own _activate_numeric_line_edit.
func _push_mouse(plugin: EditorPlugin, position: Vector2, button: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	plugin.get_viewport().push_input(event, true)


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


## Evidence hook (2026-09-15 layout pass), mirroring gst_editor_ui_complete_
## smoke.gd's own GST_UI_COMPLETE_SCREENSHOT/_capture pattern: a no-op unless
## the env var is set, so it adds nothing to the SMOKE SUMMARY count on an
## ordinary run and cannot change any existing baseline. Called right after
## _run_stable_id_switching, the first point three tabs are open at once
## (saved_doc clean, fire_doc dirty, working_doc pristine) with no dialog or
## picker in the way, to capture the tab row and toolbar layout for review.
func _capture_tab_row_evidence(plugin: EditorPlugin) -> void:
	var path: String = OS.get_environment("GST_TABS_UI_SCREENSHOT_PATH")
	if path.is_empty():
		return
	var error: Error = plugin.get_viewport().get_texture().get_image().save_png(path)
	_check("tab_row_evidence_screenshot", error == OK, "path='%s' error=%d" % [path, error])


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
