@tool
extends RefCounted

## Editor smoke for the shader-tab row: title and dirty-star presentation,
## overflow scrolling, real clicks switching by stable id, selection and
## list-position restoration, canceling a stray picker on switch, finishing
## a pending native gesture on the originating document before switching,
## per-document preview isolation, and the shared SubViewport's render loop
## pausing while the panel is hidden. Loaded by gst_editor_smoke.gd when
## GST_EDITOR_SMOKE is "tabs_ui".
##
## %ShaderTabs is a native TabBar, so there is no per-tab Control to click or
## read. Every real click goes through panel.get_tab_rect(doc) /
## get_tab_close_rect(doc) (gst_main_panel.gd) and a real
## InputEventMouseButton press/release through the viewport (_click_tab).
## TabBar::gui_input (tab_bar.cpp) resolves a click by event position alone,
## with no hover gate, so tab clicks need no NOTIFICATION_MOUSE_ENTER
## workaround. A tab outside %ShaderTabs's current [offset, max_drawn_tab]
## window reports ofs_cache 0 (TabBar::_update_cache), so
## get_tab_rect/get_tab_close_rect are only meaningful for a tab currently
## shown; _click_tab calls TabBar.ensure_tab_visible(index) first.
##
## Non-click document switches (setup steps) call panel.activate_document
## directly, the entry point %ShaderTabs's tab_changed handler
## (_on_tab_bar_tab_changed) calls. Only checks about click mechanics drive
## a real mouse event.
##
## Distinct documents are opened through panel.open_recipe() (independent
## copy every time) except where a check drives the trailing New control,
## which, like File > New, reuses an existing pristine document and opens
## the Add-layer picker; that call site cancels it before any stack mutation.

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

	# The editor's deferred "restore last main screen" from editor_layout.cfg
	# can still be in flight this early and overrides a single
	# set_main_screen_editor call once it finishes. Re-assert every frame
	# until the panel reports visible, bounded to 60 frames.
	# panel.is_visible_in_tree() is a production signal
	# (_on_panel_visibility_changed/_preview.set_active).
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

	var initial_doc: GSTDocument = panel.get_active_document()
	var initial_index: int = panel.get_tab_index(initial_doc)
	var initial_title: String = panel.get_tab_bar().get_tab_title(initial_index) if initial_index != -1 else ""
	_check("initial_tab_present", initial_index != -1 and initial_title == "Untitled 1", "text='%s'" % [initial_title if initial_index != -1 else "<missing>"])

	# Engine warm-up: the first synthetic InputEventMouseButton press in a
	# fresh editor session is consumed by Viewport::_sub_windows_forward_input
	# (scene/main/viewport.cpp, "no window found and clicked, remove focus")
	# before reaching any control's gui_input; every later click is
	# delivered. Absorbed here on the already-active tab (a no-op reclick)
	# before any assertion-bearing click.
	await _click_tab(plugin, panel, initial_doc)

	var saved_doc: GSTDocument = await _run_title_lifecycle(plugin, panel, initial_doc)
	var fire_doc: GSTDocument = await _run_recipe_title(plugin, panel)
	var working_doc: GSTDocument = await _run_stable_id_switching(plugin, panel, saved_doc, fire_doc)
	await _capture_tab_row_evidence(plugin, "GST_TABS_UI_SCREENSHOT_PATH", "tab_row_evidence_screenshot")
	_run_new_tab_button_follows_last_tab(panel)
	await _run_reclick_stays_selected_and_keyboard_undo_focus(plugin, panel, saved_doc, fire_doc)
	await _run_selection_and_scroll_restoration(plugin, panel, working_doc, fire_doc)
	# Runs here rather than at _run_stable_id_switching's three-tab point:
	# working_doc is still pristine there, so open_document's
	# _find_reusable_pristine_document (gst_main_panel.gd) would reuse it
	# instead of allocating a fourth tab, and a reuse never widens
	# %ShaderTabs, so the stale Control.size.x read in TabBar::_update_cache
	# after a content-width change would not be exercised. After
	# _run_selection_and_scroll_restoration, saved_doc (current_path set),
	# fire_doc (dirty), and working_doc (dirty) are all unreusable.
	var below_overflow_three_tabs: Dictionary = await _run_no_offset_buttons_below_overflow_three_tabs(plugin, panel)
	await _run_scroll_state_no_bleed_across_documents(plugin, panel, working_doc, fire_doc, saved_doc)
	await _run_stale_picker_cancelled_on_switch(plugin, panel, working_doc, fire_doc)
	await _run_finish_before_switch(plugin, panel, working_doc, fire_doc)
	await _run_active_only_viewport_updates(plugin, panel)
	await _run_invalid_document_isolation(plugin, panel)
	await _run_long_title_and_overflow(plugin, panel)
	# Real-overflow counterpart to below_overflow_three_tabs:
	# _run_long_title_and_overflow's tab_row_overflow_scrolls check proved
	# get_offset_buttons_visible() true with 24 tabs open; nothing between
	# touches tab content or %ShaderTabs's size.
	_finish_no_offset_buttons_below_overflow(panel, below_overflow_three_tabs)
	# Captured after the 24-tab overflow state and before _run_narrow_layout
	# resizes the window.
	await _capture_tab_row_evidence(plugin, "GST_TABS_UI_OVERFLOW_SCREENSHOT_PATH", "tab_row_overflow_evidence_screenshot")
	await _run_narrow_layout(plugin, panel)
	await _run_twenty_layers_and_rects(plugin, panel)

	_finish(plugin)


## Title updates on the pristine bootstrap document: no star while clean, a
## star once a structural edit makes it dirty (_on_stack_changed's
## _refresh_tabs() call), then the saved filename without extension and no
## star once GSTDocument.mark_baseline() runs (save_to_path's _refresh_tabs()
## call). Returns doc for reuse as a second always-open tab.
func _run_title_lifecycle(plugin: EditorPlugin, panel: GSTMainPanel, doc: GSTDocument) -> GSTDocument:
	panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	var dirty_index: int = panel.get_tab_index(doc)
	var dirty_title: String = panel.get_tab_bar().get_tab_title(dirty_index) if dirty_index != -1 else ""
	_check("tab_title_dirty_star", dirty_index != -1 and dirty_title == "Untitled 1*", "text='%s'" % [dirty_title if dirty_index != -1 else "<missing>"])

	var save_path: String = "user://gst_tabs_ui_title_save.tres"
	_cleanup([save_path])
	panel.save_to_path(save_path)
	await plugin.get_tree().process_frame
	var saved_index: int = panel.get_tab_index(doc)
	var saved_title: String = panel.get_tab_bar().get_tab_title(saved_index) if saved_index != -1 else ""
	var saved_tooltip: String = panel.get_tab_bar().get_tab_tooltip(saved_index) if saved_index != -1 else ""
	var saved_title_ok: bool = saved_index != -1 and saved_title == "gst_tabs_ui_title_save" and saved_tooltip == save_path
	_check("tab_title_saved", saved_title_ok, "text='%s' tooltip='%s' (expect '%s')" % [saved_title, saved_tooltip, save_path])
	return doc


## Recipe-name title, dirty on open: GSTDocument.setup's starts_dirty leaves
## no baseline for recipe content to read clean against.
func _run_recipe_title(plugin: EditorPlugin, panel: GSTMainPanel) -> GSTDocument:
	panel.open_recipe("fire")
	await plugin.get_tree().process_frame
	var fire: GSTDocument = panel.get_active_document()
	var fire_index: int = panel.get_tab_index(fire)
	var fire_title: String = panel.get_tab_bar().get_tab_title(fire_index) if fire_index != -1 else ""
	var fire_tooltip: String = panel.get_tab_bar().get_tab_tooltip(fire_index) if fire_index != -1 else ""
	var recipe_title_ok: bool = fire_index != -1 and fire_title == "Fire*" and fire_tooltip.contains("recipe 'fire'")
	_check("tab_title_recipe", recipe_title_ok, "text='%s' tooltip='%s'" % [fire_title, fire_tooltip])
	return fire


## Stable-id switching driven by real InputEventMouseButton press/release
## through the viewport against %ShaderTabs's tab rects. Drives the trailing
## New control once (the one place this file does): like File > New it
## reuses an existing pristine document and opens the Add-layer picker,
## cancelled before returning so later checks can mutate the returned
## document's stack.
func _run_stable_id_switching(plugin: EditorPlugin, panel: GSTMainPanel, saved_doc: GSTDocument, fire_doc: GSTDocument) -> GSTDocument:
	panel.get_new_tab_button().pressed.emit()
	await plugin.get_tree().process_frame
	if panel.is_picker_open():
		panel.get_picker().cancelled.emit()
		await plugin.get_tree().process_frame
	var working_doc: GSTDocument = panel.get_active_document()
	var created_distinct: bool = working_doc != null and working_doc != saved_doc and working_doc != fire_doc

	await _click_tab(plugin, panel, saved_doc)
	var switched_to_saved: bool = panel.get_active_document() == saved_doc and panel.get_tab_bar().current_tab == panel.get_tab_index(saved_doc)

	await _click_tab(plugin, panel, fire_doc)
	var switched_to_fire: bool = panel.get_active_document() == fire_doc and panel.get_tab_bar().current_tab == panel.get_tab_index(fire_doc)
	_check("stable_id_switch_by_click", created_distinct and switched_to_saved and switched_to_fire, "created_distinct=%s switched_to_saved=%s switched_to_fire=%s" % [created_distinct, switched_to_saved, switched_to_fire])
	return working_doc


## A real click on the already-active tab must keep it selected.
## TabBar::set_current_tab only emits tab_changed when the index moves
## (tab_bar.cpp), so a reclick never reaches _on_tab_bar_tab_changed's
## activate_document call. Checked against %ShaderTabs's current_tab.
##
## %ShaderTabs is never freed or rebuilt (gst_main_panel.gd _refresh_tabs()),
## so focus stays on it across activation. A real click followed by real
## Ctrl+Z/Ctrl+Shift+Z must reach only the document that click activated.
## Both documents get an edit first so a stray undo/redo landing on
## saved_doc is observable.
func _run_reclick_stays_selected_and_keyboard_undo_focus(plugin: EditorPlugin, panel: GSTMainPanel, saved_doc: GSTDocument, fire_doc: GSTDocument) -> void:
	await _click_tab(plugin, panel, fire_doc)
	await _click_tab(plugin, panel, fire_doc)
	var reclick_stays_active: bool = panel.get_active_document() == fire_doc
	var reclick_stays_selected: bool = panel.get_tab_bar().current_tab == panel.get_tab_index(fire_doc)
	_check("active_tab_reclick_stays_selected", reclick_stays_active and reclick_stays_selected, "active=%s selected=%s" % [reclick_stays_active, reclick_stays_selected])

	var history_saved: UndoRedo = saved_doc.undo_redo
	var saved_layers_before: int = saved_doc.stack.layers.size()

	await _click_tab(plugin, panel, saved_doc)
	panel.get_stack_list().add_layer_by_entry_id("generative/hash")
	await plugin.get_tree().process_frame
	var saved_layers_after_add: int = saved_doc.stack.layers.size()
	# UndoRedo.get_history_count() is actions.size() (core/object/undo_redo.cpp),
	# the total of committed actions; it never changes on undo()/redo().
	# get_current_action() is the undo-position counter.
	var saved_position_after_add: int = history_saved.get_current_action()

	# Viewport's click-to-focus grab is gated on gui.mouse_over_hierarchy
	# (scene/main/viewport.cpp), which a synthetic press/release never
	# populates without a real DisplayServer mouse-enter. grab_focus()
	# supplies that one piece of state; the click below still runs
	# TabBar::gui_input's set_current_tab and _on_tab_bar_tab_changed's
	# activate_document.
	panel.get_tab_bar().grab_focus()

	await _click_tab(plugin, panel, fire_doc)
	var history_fire: UndoRedo = fire_doc.undo_redo
	panel.get_stack_list().add_layer_by_entry_id("generative/hash")
	await plugin.get_tree().process_frame
	var fire_layers_after_add: int = fire_doc.stack.layers.size()
	var fire_position_after_add: int = history_fire.get_current_action()

	var focus_owner: Control = panel.get_viewport().gui_get_focus_owner()
	var focus_on_active_tab: bool = focus_owner == panel.get_tab_bar()

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


## Builds enough layers on working_doc to scroll, selects and scrolls away
## from the top, switches to fire_doc and back through
## panel.activate_document, and checks selection and list position survive
## by stable id.
func _run_selection_and_scroll_restoration(plugin: EditorPlugin, panel: GSTMainPanel, working_doc: GSTDocument, fire_doc: GSTDocument) -> void:
	await panel.activate_document(working_doc)
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

	await panel.activate_document(fire_doc)
	await plugin.get_tree().process_frame
	await panel.activate_document(working_doc)
	await plugin.get_tree().process_frame

	var restored_list: GSTStackList = panel.get_stack_list()
	var selection_restored: bool = panel.get_active_document() == working_doc and restored_list.get_selected_layer_id() == target_id
	var anchor_restored: bool = restored_list.get_scroll_anchor_id() == anchor_before
	var offset_restored: bool = is_equal_approx(restored_list.get_scroll_offset(), offset_before)
	_check("selection_and_list_position_restored", layers_built_ok and selection_restored and anchor_restored and offset_restored, "layers_built=%s selection_restored=%s anchor=%s/%s offset=%.3f/%.3f" % [layers_built_ok, selection_restored, anchor_before, restored_list.get_scroll_anchor_id(), offset_before, restored_list.get_scroll_offset()])


## Reproduces "after pressing the + new-tab button, with only two or three
## tabs open, %ShaderTabs showed its overflow scroll arrows" through the real
## controls: %NewTabButton (a plain Button, needing the
## NOTIFICATION_MOUSE_ENTER workaround in _click_new_tab_button) and the new
## tab's close icon (_click_tab_close). get_offset_buttons_visible() is read
## once right after each click settles (everything from _on_new_pressed
## through _refresh_tabs()/_apply_tab_bar_width() runs synchronously inside
## the release-event dispatch, gst_main_panel.gd) and once a frame later,
## for both add and close. Returns a Dictionary the caller folds into the
## combined "no_offset_buttons_below_overflow" check via
## _finish_no_offset_buttons_below_overflow.
func _run_no_offset_buttons_below_overflow_three_tabs(plugin: EditorPlugin, panel: GSTMainPanel) -> Dictionary:
	var tab_bar: TabBar = panel.get_tab_bar()
	var before_count: int = panel.get_documents().size()

	await _click_new_tab_button(plugin, panel.get_new_tab_button())
	var added_doc: GSTDocument = panel.get_active_document()
	var added_distinct: bool = added_doc != null and panel.get_documents().size() == before_count + 1
	var no_arrows_same_frame_after_add: bool = not tab_bar.get_offset_buttons_visible()
	var arrows_path: String = OS.get_environment("GST_TABS_UI_ARROWS_SCREENSHOT_PATH")
	if not arrows_path.is_empty():
		var error: Error = plugin.get_viewport().get_texture().get_image().save_png(arrows_path)
		_check("tab_row_arrows_evidence_screenshot", error == OK, "path='%s' error=%d" % [arrows_path, error])
	await plugin.get_tree().process_frame
	var no_arrows_next_frame_after_add: bool = not tab_bar.get_offset_buttons_visible()
	if panel.is_picker_open():
		panel.get_picker().cancelled.emit()
		await plugin.get_tree().process_frame

	await _click_tab_close(plugin, panel, added_doc)
	var closed_back_down: bool = panel.get_documents().size() == before_count
	var no_arrows_same_frame_after_close: bool = not tab_bar.get_offset_buttons_visible()
	await plugin.get_tree().process_frame
	var no_arrows_next_frame_after_close: bool = not tab_bar.get_offset_buttons_visible()

	return {
		"ok": added_distinct and closed_back_down and no_arrows_same_frame_after_add and no_arrows_next_frame_after_add and no_arrows_same_frame_after_close and no_arrows_next_frame_after_close,
		"detail": "added_distinct=%s closed_back_down=%s no_arrows_same_add=%s no_arrows_next_add=%s no_arrows_same_close=%s no_arrows_next_close=%s" % [added_distinct, closed_back_down, no_arrows_same_frame_after_add, no_arrows_next_frame_after_add, no_arrows_same_frame_after_close, no_arrows_next_frame_after_close],
	}


## Combines the three-tab result (three_tab_phase) with the 24-tab overflow
## state _run_long_title_and_overflow left (get_offset_buttons_visible()
## true) into one "no_offset_buttons_below_overflow" check. Nothing between
## that call and this one touches tab content or %ShaderTabs's size.
func _finish_no_offset_buttons_below_overflow(panel: GSTMainPanel, three_tab_phase: Dictionary) -> void:
	var overflow_true_at_24_tabs: bool = panel.get_tab_bar().get_offset_buttons_visible()
	var ok: bool = bool(three_tab_phase.get("ok", false)) and overflow_true_at_24_tabs
	_check("no_offset_buttons_below_overflow", ok, "%s overflow_true_at_24_tabs=%s tab_count=%d" % [String(three_tab_phase.get("detail", "")), overflow_true_at_24_tabs, panel.get_documents().size()])


## A document that has never had its scroll state captured must open at its
## top, never inherit the previous document's scrolled position because both
## stacks' layer ids overlap. Every GSTStack's next_id starts at 0
## (gst_stack_ops.gd), so two documents built to the same layer count share
## the same id set. working_doc's 12 layers get 40 more so
## scroll_to_fraction(0.6) lands on a non-top row (at 12 the anchor stayed
## on the top row). A new document is built to the same layer count through
## its own GSTUndo while inactive, so its id set overlaps working_doc's while
## its list_scroll_anchor_id stays &"": gst_stack_list.gd's refresh() only
## captures/restores the currently installed rows, so background mutation
## never touches it. Switching from working_doc's scrolled tab to that tab is
## the first-activation-with-content case restore_scroll_state's
## anchor_id == &"" branch (gst_stack_list.gd) covers. Both switch
## directions are checked afterward for bleed.
func _run_scroll_state_no_bleed_across_documents(plugin: EditorPlugin, panel: GSTMainPanel, working_doc: GSTDocument, fire_doc: GSTDocument, saved_doc: GSTDocument) -> void:
	await panel.activate_document(working_doc)
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

	# Switch away from fresh_doc while its list is empty (get_scroll_anchor_id()
	# returns &"" for an empty list, so the outgoing capture stays &"") and
	# back to working_doc so the population below runs while fresh_doc is
	# inactive.
	await panel.activate_document(working_doc)
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

	await panel.activate_document(fresh_doc)
	await plugin.get_tree().process_frame
	var fresh_list: GSTStackList = panel.get_stack_list()
	var fresh_top_id: StringName = fresh_list.get_item_id(0)
	var fresh_starts_at_top: bool = fresh_list.get_item_count() == working_total and fresh_list.get_scroll_anchor_id() == fresh_top_id and is_equal_approx(fresh_list.get_scroll_offset(), 0.0)

	fresh_list.scroll_to_fraction(0.3)
	await plugin.get_tree().process_frame
	var fresh_anchor_before: StringName = fresh_list.get_scroll_anchor_id()
	var fresh_offset_before: float = fresh_list.get_scroll_offset()
	var fresh_scroll_moved: bool = fresh_anchor_before != fresh_top_id

	await panel.activate_document(working_doc)
	await plugin.get_tree().process_frame
	var restored_working_list: GSTStackList = panel.get_stack_list()
	var working_restored_ok: bool = restored_working_list.get_scroll_anchor_id() == working_anchor_before and is_equal_approx(restored_working_list.get_scroll_offset(), working_offset_before)

	await panel.activate_document(fresh_doc)
	await plugin.get_tree().process_frame
	var restored_fresh_list: GSTStackList = panel.get_stack_list()
	var fresh_restored_ok: bool = restored_fresh_list.get_scroll_anchor_id() == fresh_anchor_before and is_equal_approx(restored_fresh_list.get_scroll_offset(), fresh_offset_before)

	var ok: bool = fresh_distinct and fresh_layers_ok and overlapping_ids and fresh_anchor_still_unset and working_scroll_moved and fresh_starts_at_top and fresh_scroll_moved and working_restored_ok and fresh_restored_ok
	_check("scroll_state_no_bleed_across_documents", ok, "fresh_distinct=%s fresh_layers_ok=%s overlapping_ids=%s fresh_anchor_still_unset=%s working_scroll_moved=%s(anchor=%s) fresh_starts_at_top=%s(top=%s) fresh_scroll_moved=%s working_restored=%s fresh_restored=%s" % [fresh_distinct, fresh_layers_ok, overlapping_ids, fresh_anchor_still_unset, working_scroll_moved, working_anchor_before, fresh_starts_at_top, fresh_top_id, fresh_scroll_moved, working_restored_ok, fresh_restored_ok])


## An open chooser on the document being left must be cancelled, not left
## open against a stack the shared UI is about to point away from.
func _run_stale_picker_cancelled_on_switch(plugin: EditorPlugin, panel: GSTMainPanel, working_doc: GSTDocument, fire_doc: GSTDocument) -> void:
	await panel.activate_document(working_doc)
	await plugin.get_tree().process_frame
	var history: UndoRedo = working_doc.undo_redo
	var count_before: int = history.get_history_count()
	panel.get_stack_list().get_node("%AddButton").pressed.emit()
	await plugin.get_tree().process_frame
	var picker_was_open: bool = panel.is_picker_open()

	await panel.activate_document(fire_doc)
	await plugin.get_tree().process_frame
	var picker_cancelled: bool = not panel.is_picker_open()
	var no_stale_mutation: bool = history.get_history_count() == count_before
	var switched: bool = panel.get_active_document() == fire_doc
	_check("stale_picker_cancelled_on_switch", picker_was_open and picker_cancelled and no_stale_mutation and switched, "picker_was_open=%s cancelled=%s no_mutation=%s switched=%s" % [picker_was_open, picker_cancelled, no_stale_mutation, switched])


## A numeric gesture in flight on the document being left must commit there,
## never reach the document the switch moves to. Mirrors
## tests/gst_editor_documents_smoke.gd's numeric_pending_edit check
## (synthetic EditorSpinSlider.grabbed + EditorProperty.emit_changed, not a
## mid-drag mouse interaction), driven through panel.activate_document.
func _run_finish_before_switch(plugin: EditorPlugin, panel: GSTMainPanel, working_doc: GSTDocument, fire_doc: GSTDocument) -> void:
	await panel.activate_document(working_doc)
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

		await panel.activate_document(fire_doc)
		await plugin.get_tree().process_frame
		var switched: bool = panel.get_active_document() == fire_doc
		finish_before_switch_ok = origin_history.get_history_count() == count_before + 1 and is_equal_approx(float(fbm.get(&"gain")), mid_gesture_value) and not is_equal_approx(mid_gesture_value, original_gain) and switched
	_check("finish_before_switch", finish_before_switch_ok, "gain_spin_found=%s" % [gain_spin_found])


## Hiding the panel (a main-screen switch away from GoShade) pauses the
## shared SubViewport's render loop; showing it again resumes it.
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


## A codegen error forced onto one document must never appear on, nor clear
## from, another, and must be the same message when switching back.
## broken_doc is built and broken first, while it is the only pristine
## document, so clean_doc is a distinct new document rather than
## open_document's pristine reuse landing on broken_doc.
##
## Also asserts material identity. broken_doc never reaches a successful
## compile (GSTMaterialSync.has_successful_preview() stays false;
## sync_preview leaves the material's shader and uniforms untouched on a
## codegen failure, and reset_installation() installed only
## GSTMaterialSync.SAFE_TRANSPARENT_SHADER_CODE), so its material can never
## carry clean_doc's compiled shader, and the reverse.
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

	await panel.activate_document(broken_doc)
	await plugin.get_tree().process_frame
	var restored_message: String = panel.get_message_label().text
	var restored_material: ShaderMaterial = panel.get_shader_material()
	var restored_material_is_broken_own: bool = restored_material == broken_doc.material and restored_material != clean_doc.material
	var restored_shader_still_safe: bool = restored_material != null and restored_material.shader != null and restored_material.shader.code == GSTMaterialSync.SAFE_TRANSPARENT_SHADER_CODE

	var ok: bool = created_distinct and broken_message_present and clean_message_empty and restored_message == broken_message and broken_never_succeeded and broken_material_is_own and broken_shader_is_safe and clean_has_success and distinct_material_instances and clean_shader_differs_from_safe and restored_material_is_broken_own and restored_shader_still_safe
	_check("invalid_document_no_previous_effect", ok, "distinct=%s broken_present=%s clean_empty=%s restored='%s' (expect '%s') broken_never_succeeded=%s broken_material_own=%s broken_shader_safe=%s clean_has_success=%s distinct_materials=%s clean_shader_differs=%s restored_material_own=%s restored_shader_safe=%s" % [created_distinct, broken_message_present, clean_message_empty, restored_message, broken_message, broken_never_succeeded, broken_material_is_own, broken_shader_is_safe, clean_has_success, distinct_material_instances, clean_shader_differs_from_safe, restored_material_is_broken_own, restored_shader_still_safe])


## Saves the active document under a long filename: its tab stays bounded at
## %ShaderTabs's max_tab_width (gst_main_panel.tscn) while the tooltip
## carries the full path. Then opens enough independent recipe copies to
## exceed the row's visible width and checks
## TabBar.get_offset_buttons_visible().
func _run_long_title_and_overflow(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var long_doc: GSTDocument = panel.get_active_document()
	var long_name: String = "a_deliberately_long_shader_filename_for_the_tab_overflow_measurement"
	var long_path: String = "user://%s.tres" % long_name
	_cleanup([long_path])
	panel.save_to_path(long_path)
	await plugin.get_tree().process_frame
	var long_index: int = panel.get_tab_index(long_doc)
	var long_rect: Rect2 = panel.get_tab_rect(long_doc) if long_index != -1 else Rect2()
	var long_tooltip: String = panel.get_tab_bar().get_tab_tooltip(long_index) if long_index != -1 else ""
	var bounded_width: bool = long_index != -1 and long_rect.size.x <= 200.0
	var full_tooltip: bool = long_index != -1 and long_tooltip == long_path
	_check("long_title_bounded_and_tooltip_full", bounded_width and full_tooltip, "width=%.1f tooltip='%s'" % [long_rect.size.x if long_index != -1 else -1.0, long_tooltip])
	_cleanup([long_path])

	for i: int in range(18):
		panel.open_recipe("fire")
		await plugin.get_tree().process_frame
	var tab_bar: TabBar = panel.get_tab_bar()
	var overflowed: bool = tab_bar.get_offset_buttons_visible()
	_check("tab_row_overflow_scrolls", overflowed, "offset_buttons_visible=%s tab_offset=%d tab_count=%d" % [tab_bar.get_offset_buttons_visible(), tab_bar.get_tab_offset(), panel.get_documents().size()])

	# Once the tab content does not fit, _apply_tab_bar_width's
	# available-width clamp (gst_main_panel.gd) pins %ShaderTabs, and
	# %NewTabButton as its fixed sibling in ShaderTabRow, at the row's right
	# edge, with %ShaderTabs scrolling its content internally.
	var row: HBoxContainer = panel.get_tab_row()
	var new_tab_button: Button = panel.get_new_tab_button()
	var row_right_edge: float = row.get_global_rect().position.x + row.get_global_rect().size.x
	var button_right_edge: float = new_tab_button.get_global_rect().position.x + new_tab_button.get_global_rect().size.x
	var button_at_row_edge: bool = absf(button_right_edge - row_right_edge) <= 2.0
	_check("new_tab_button_pinned_at_row_edge_when_overflowing", overflowed and button_at_row_edge, "button_right=%.1f row_right=%.1f tab_count=%d" % [button_right_edge, row_right_edge, panel.get_documents().size()])


## The tab row stays visible and functional at the narrow width that
## collapses Layers/Layer settings into tabs; the preview/output allocation
## measured through get_layout_measurements() is covered by ui_layout_smoke.
##
## Measures the wide breakpoint and tab-row height first, resizes below that
## breakpoint, and requires the crossing to have happened. With the ~21 tabs
## open from _run_long_title_and_overflow the row overflows at every width,
## so %ShaderTabs's offset buttons must stay visible, the row height must be
## unchanged by the narrower main split, and the active tab must stay
## scrolled into view through gst_main_panel.gd's _on_tab_scroll_resized
## alone (no ensure_tab_visible call is made here).
func _run_narrow_layout(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var original_window_size: Vector2i = DisplayServer.window_get_size()
	# Known wide baseline (ui_layout_smoke.gd's 1366x768): this selector never
	# otherwise sets a window size, and the isolated profile's start size is
	# not guaranteed to be above the measured breakpoint.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1366, 768))
	for i: int in range(8):
		await plugin.get_tree().process_frame
	var wide_measured: Dictionary = panel.get_layout_measurements()
	var row: HBoxContainer = panel.get_tab_row()
	var tab_bar: TabBar = panel.get_tab_bar()
	var row_height_wide: float = row.size.y
	var narrow_threshold: float = float(wide_measured["tab_breakpoint"])

	# A window resize alone does not reliably cross the breakpoint (measured:
	# 1366->1024 barely moved editing_rect.size.x at this editor's docked
	# panel proportions). ui_layout_smoke.gd's responsive_tabs check also
	# drags %MainSplit when the resize is not enough; same drag mechanics here
	# (tests/gst_editor_ui_layout_smoke.gd's _drag_splitter).
	DisplayServer.window_set_size(Vector2i(720, 600))
	for i: int in range(8):
		await plugin.get_tree().process_frame
	if float(panel.get_layout_measurements()["editing_rect"].size.x) >= narrow_threshold:
		var main_split: HSplitContainer = panel.get_node("%MainSplit") as HSplitContainer
		var overshoot: float = float(panel.get_layout_measurements()["editing_rect"].size.x) - narrow_threshold + 24.0
		await _drag_main_split(plugin, main_split, -overshoot)
	# At a scaled editor content factor (150%), _on_tab_scroll_resized's
	# deferred re-scroll needs more than one frame after the window/splitter
	# changes land.
	for i: int in range(6):
		await plugin.get_tree().process_frame

	var measured: Dictionary = panel.get_layout_measurements()
	var crossed_breakpoint: bool = bool(measured["narrow"]) and float(measured["editing_rect"].size.x) <= narrow_threshold + 0.5
	var row_visible: bool = row.is_visible_in_tree()
	var active_doc: GSTDocument = panel.get_active_document()
	var active_index: int = panel.get_tab_index(active_doc)
	var active_tab_present: bool = active_index != -1
	var row_height_narrow: float = row.size.y
	var row_height_unchanged: bool = is_equal_approx(row_height_narrow, row_height_wide)
	var scrollbar_visible_under_narrow: bool = tab_bar.get_offset_buttons_visible()
	var tab_bar_rect: Rect2 = tab_bar.get_global_rect()
	var active_rect: Rect2 = panel.get_tab_rect(active_doc) if active_tab_present else Rect2()
	var active_scrolled_into_view: bool = active_tab_present and active_rect.position.x >= tab_bar_rect.position.x - 2.0 and (active_rect.position.x + active_rect.size.x) <= tab_bar_rect.position.x + tab_bar_rect.size.x + 2.0
	print("TABS_UI NARROW narrow_threshold=%.1f wide_editing_x=%.1f narrow_editing_x=%.1f row_height_wide=%.1f row_height_narrow=%.1f tab_offset=%d offset_buttons_visible=%s active_pos_x=%.1f tab_bar=[%.1f,%.1f] measure=%s" % [narrow_threshold, float(wide_measured["editing_rect"].size.x), float(measured["editing_rect"].size.x), row_height_wide, row_height_narrow, tab_bar.get_tab_offset(), tab_bar.get_offset_buttons_visible(), active_rect.position.x if active_tab_present else -1.0, tab_bar_rect.position.x, tab_bar_rect.position.x + tab_bar_rect.size.x, measured])

	var ok: bool = crossed_breakpoint and row_visible and active_tab_present and row_height_unchanged and scrollbar_visible_under_narrow and active_scrolled_into_view
	_check("narrow_layout_tab_row_usable", ok, "crossed_breakpoint=%s(%.1f) row_visible=%s active_present=%s height_unchanged=%s(%.1f/%.1f) scrollbar_visible=%s scrolled_into_view=%s" % [crossed_breakpoint, narrow_threshold, row_visible, active_tab_present, row_height_unchanged, row_height_wide, row_height_narrow, scrollbar_visible_under_narrow, active_scrolled_into_view])

	DisplayServer.window_set_size(original_window_size)
	for i: int in range(4):
		await plugin.get_tree().process_frame


## The shared preview_rect/output_rect from get_layout_measurements must not
## move because the active document changed. doc is opened fresh here: no
## pristine document remains at this point, so open_document's reuse check
## cannot land on an existing one.
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
	await panel.activate_document(doc)
	await plugin.get_tree().process_frame

	var preview_after: Rect2 = panel.get_layout_measurements()["preview_rect"]
	var output_after: Rect2 = panel.get_layout_measurements()["output_rect"]
	var list_after_switch: GSTStackList = panel.get_stack_list()
	print("TABS_UI TWENTY_LAYERS preview_before=%s preview_after=%s output_before=%s output_after=%s" % [preview_before, preview_after, output_before, output_after])
	_check("twenty_layers_preview_output_rects_stable", item_count_ok and preview_before.is_equal_approx(preview_after) and output_before.is_equal_approx(output_after) and list_after_switch.get_item_count() == 20, "item_count=%d preview=%s/%s output=%s/%s" % [list_after_switch.get_item_count(), preview_before, preview_after, output_before, output_after])


## Real click on doc's tab: press then release InputEventMouseButton at its
## global-rect center. TabBar.ensure_tab_visible(index) runs first and is
## awaited a frame: a tab outside %ShaderTabs's current
## [offset, max_drawn_tab] window reports ofs_cache 0 (tab_bar.cpp
## TabBar::_update_cache), so panel.get_tab_rect(doc) is only meaningful for
## a tab currently shown.
##
## TabBar::gui_input (Godot 4.4 scene/gui/tab_bar.cpp) resolves a click by
## event position alone (tabs[i].cb_rect.has_point(pos) or the tab-body
## range check); unlike BaseButton::on_action_event there is no
## status.hovering gate, so no NOTIFICATION_MOUSE_ENTER workaround is needed.
func _click_tab(plugin: EditorPlugin, panel: GSTMainPanel, doc: GSTDocument) -> void:
	var index: int = panel.get_tab_index(doc)
	if index == -1:
		return
	panel.get_tab_bar().ensure_tab_visible(index)
	await plugin.get_tree().process_frame
	var point: Vector2 = panel.get_tab_rect(doc).get_center()
	_push_mouse(plugin, point, MOUSE_BUTTON_LEFT, true)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame
	_push_mouse(plugin, point, MOUSE_BUTTON_LEFT, false)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame


## Drags split's divider by delta through real mouse press/motion/release
## via Input.parse_input_event, matching
## tests/gst_editor_ui_layout_smoke.gd's _drag_splitter. Independent of
## _push_mouse (Viewport.push_input) because parse_input_event is the
## mechanism verified to drag %MainSplit.
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
## tests/gst_editor_ui_complete_smoke.gd's _activate_numeric_line_edit.
func _push_mouse(plugin: EditorPlugin, position: Vector2, button: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	plugin.get_viewport().push_input(event, true)


## Real click on %NewTabButton's global-rect center (never
## Button.pressed.emit()). NOTIFICATION_MOUSE_ENTER supplies the hover state
## a synthetic InputEventMouseButton never establishes
## (BaseButton::on_action_event gates a mouse-button event on
## status.hovering; Viewport's hover tracking needs a real DisplayServer
## mouse-enter). Matches tests/gst_editor_document_close_smoke.gd's
## _click_button. Tab clicks go through _click_tab/_click_tab_close and need
## no such workaround.
func _click_new_tab_button(plugin: EditorPlugin, button: Button) -> void:
	await plugin.get_tree().process_frame
	var point: Vector2 = button.get_global_rect().get_center()
	button.notification(Control.NOTIFICATION_MOUSE_ENTER)
	_push_mouse(plugin, point, MOUSE_BUTTON_LEFT, true)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame
	_push_mouse(plugin, point, MOUSE_BUTTON_LEFT, false)
	await plugin.get_tree().process_frame


## Real click on doc's tab close icon: press then release
## InputEventMouseButton at panel.get_tab_close_rect(doc)'s center (never
## panel.close_document()). Warps the OS cursor to the close icon first and
## restores it after, matching tests/gst_editor_document_close_smoke.gd's
## _click_tab_close: TabBar::gui_input's cb_pressing branch (tab_bar.cpp)
## calls _update_hover(), which reads the real OS cursor position for the
## root Viewport rather than the synthetic event's position.
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
	_push_mouse(plugin, point, MOUSE_BUTTON_LEFT, true)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame
	_push_mouse(plugin, point, MOUSE_BUTTON_LEFT, false)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame
	DisplayServer.warp_mouse(Vector2i(original_mouse))


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


## With three tabs open (not overflowing), %ShaderTabs does not stretch
## across ShaderTabRow (size_flags_horizontal SIZE_SHRINK_BEGIN,
## gst_main_panel.tscn); GSTMainPanel._apply_tab_bar_width sizes it to its
## tab content, so %NewTabButton's global left edge sits at the last tab's
## global right edge plus the row's separation.
func _run_new_tab_button_follows_last_tab(panel: GSTMainPanel) -> void:
	var tab_bar: TabBar = panel.get_tab_bar()
	var row: HBoxContainer = panel.get_tab_row()
	var new_tab_button: Button = panel.get_new_tab_button()
	var last_index: int = tab_bar.get_tab_count() - 1
	var last_tab_right: float = -1.0
	if last_index >= 0:
		var local: Rect2 = tab_bar.get_tab_rect(last_index)
		last_tab_right = tab_bar.get_global_rect().position.x + local.position.x + local.size.x
	var separation: float = float(row.get_theme_constant("separation"))
	var expected_x: float = last_tab_right + separation
	var actual_x: float = new_tab_button.get_global_rect().position.x
	var ok: bool = last_index >= 0 and absf(actual_x - expected_x) <= 2.0
	_check("new_tab_button_follows_last_tab", ok, "expected_x=%.1f actual_x=%.1f last_tab_right=%.1f tab_count=%d" % [expected_x, actual_x, last_tab_right, tab_bar.get_tab_count()])


## Screenshot hook parameterized by env_var/check_name, mirroring
## gst_editor_ui_complete_smoke.gd's GST_UI_COMPLETE_SCREENSHOT pattern: a
## no-op unless the env var is set, so it adds nothing to the SMOKE SUMMARY
## count on an ordinary run. Called after _run_stable_id_switching (three
## tabs) and after _run_long_title_and_overflow (24 tabs, overflowing).
func _capture_tab_row_evidence(plugin: EditorPlugin, env_var: String, check_name: String) -> void:
	var path: String = OS.get_environment(env_var)
	if path.is_empty():
		return
	var error: Error = plugin.get_viewport().get_texture().get_image().save_png(path)
	_check(check_name, error == OK, "path='%s' error=%d" % [path, error])


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
