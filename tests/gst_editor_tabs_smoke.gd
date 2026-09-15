@tool
extends RefCounted

## Phase 4 (docs/SHADER_TABS_reviewed-plan.md): the visible shader-tab row and
## document activation/restoration it drives. Phase 3's tabs_documents proved
## GSTDocument's own state ownership through panel.open_document/
## activate_document called directly; this selector proves the same
## guarantees now reach the user through the real tab row -- title/dirty-star
## presentation, overflow scrolling, real clicks switching by stable id,
## selection/list-position restoration, canceling a stray picker on switch,
## finishing a pending native gesture on its own originating document before
## switching, per-document preview isolation, and the shared SubViewport's
## own render-loop pausing while the GoShade panel is hidden.
##
## 2026-09-15 TabBar pass: %ShaderTabs is now a native Godot TabBar (matching
## Godot's own scene tabs) instead of a row of per-document Buttons, so there
## is no per-tab Control to click, grab focus onto, or read .text/.tooltip_text
## from. Every real click below goes through panel.get_tab_rect(doc)/
## get_tab_close_rect(doc) (global-coordinate seams derived from TabBar's own
## get_tab_rect and a public-theme-item reconstruction of its private cb_rect,
## gst_main_panel.gd) and a real InputEventMouseButton press/release through
## the viewport (_click_tab), never a synthetic signal emission on a node that
## no longer exists per document. Unlike the old per-tab Button row,
## TabBar::gui_input (tab_bar.cpp) resolves a click by the event's own
## position alone -- no BaseButton-style hover gate -- so, unlike the old
## per-tab Buttons, no NOTIFICATION_MOUSE_ENTER workaround is needed for the
## click itself to register; the Viewport-level "first synthetic click in a
## fresh session" warm-up (run(), below) is a separate, target-independent
## artifact and is kept unchanged. A tab scrolled outside %ShaderTabs's own
## current [offset, max_drawn_tab] window reports ofs_cache 0 (tab_bar.cpp
## TabBar::_update_cache), so get_tab_rect/get_tab_close_rect are only
## meaningful for a tab %ShaderTabs is actually showing right now; _click_tab
## calls TabBar.ensure_tab_visible(index) first for exactly this reason.
##
## Non-click document switches below (building content on a document that is
## not the one under test, restoring focus, etc.) call panel.activate_document
## directly -- the exact same production entry point %ShaderTabs's own
## tab_changed handler calls (_on_tab_bar_tab_changed, gst_main_panel.gd) --
## rather than simulating a click, mirroring the old file's own use of
## Button.pressed.emit() for the same non-mechanics-under-test setup steps.
## Only checks that are actually about click mechanics (_click_tab's own
## callers) drive a real mouse event.
##
## Distinct documents are opened through panel.open_recipe() (phase 3:
## independent copy every time, never reused) except where a check
## specifically drives the trailing New control itself, which -- like the
## File > New handler it shares -- reuses an existing pristine document and
## immediately opens the Add-layer picker; that one call site cancels it
## explicitly before any further stack mutation.

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

	# The editor's own deferred "restore last main screen from saved window
	# layout" (editor_layout.cfg) can still be in flight this early in a
	# session and overrides a single set_main_screen_editor call once it
	# finishes loading, landing back on whatever main screen (e.g. "Script")
	# a prior session left active -- observed directly in this isolated
	# profile via a screenshot: "Loading plugin window layout..." still on
	# screen with "Script" selected right after the single call below
	# returned. Re-asserting it every frame until the panel actually reports
	# visible (bounded to 60 frames, well past every observed settle time)
	# survives that race without weakening what this proves once it exits
	# the loop: panel.is_visible_in_tree() is a real production signal
	# (_on_panel_visibility_changed/_preview.set_active), not a fixture.
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

	# One-time engine warm-up (round 1 fix pass, Button-row era; unchanged by
	# the 2026-09-15 TabBar pass): the very first synthetic
	# InputEventMouseButton press delivered in a fresh editor session hits
	# Viewport's own stale-subwindow-focus-clearing path once
	# (scene/main/viewport.cpp Viewport::_sub_windows_forward_input, "no
	# window found and clicked, remove focus") and is consumed there before
	# reaching any control's own gui_input; every click after the first
	# behaves normally. Observed directly in this same isolated session: an
	# identical real click on the already-active tab failed silently on the
	# very first attempt and succeeded on every later attempt. Absorbed here,
	# on the harmless already-active tab (a no-op reclick), before any
	# assertion-bearing click below -- not a gst_main_panel.gd defect, since
	# no production code runs differently on a first vs. later click.
	await _click_tab(plugin, panel, initial_doc)

	var saved_doc: GSTDocument = await _run_title_lifecycle(plugin, panel, initial_doc)
	var fire_doc: GSTDocument = await _run_recipe_title(plugin, panel)
	var working_doc: GSTDocument = await _run_stable_id_switching(plugin, panel, saved_doc, fire_doc)
	await _capture_tab_row_evidence(plugin, "GST_TABS_UI_SCREENSHOT_PATH", "tab_row_evidence_screenshot")
	_run_new_tab_button_follows_last_tab(panel)
	await _run_reclick_stays_selected_and_keyboard_undo_focus(plugin, panel, saved_doc, fire_doc)
	await _run_selection_and_scroll_restoration(plugin, panel, working_doc, fire_doc)
	# 2026-09-15 offset-arrows fix (user-reported defect): run right here, not
	# at _run_stable_id_switching's own three-tab point, because working_doc
	# is still pristine there (current_path.is_empty() and not is_dirty()) --
	# open_document's own _find_reusable_pristine_document (gst_main_panel.gd)
	# would reuse it instead of allocating a genuinely new fourth tab, and a
	# reuse rebuilds the same three tabs' worth of content, never widening
	# %ShaderTabs, so the bug this proves (TabBar::_update_cache reading a
	# stale, pre-resize Control.size.x right after a real content-width
	# change) would not even be exercised. _run_selection_and_scroll_
	# restoration just above added 12 layers onto working_doc, so by this
	# point saved_doc (current_path set), fire_doc ("Fire*", dirty), and
	# working_doc (now dirty) are all unreusable -- the real click below is
	# guaranteed a genuinely new fourth document, exactly the "only two or
	# three tabs open, far from overflowing" shape from the report.
	var below_overflow_three_tabs: Dictionary = await _run_no_offset_buttons_below_overflow_three_tabs(plugin, panel)
	await _run_scroll_state_no_bleed_across_documents(plugin, panel, working_doc, fire_doc, saved_doc)
	await _run_stale_picker_cancelled_on_switch(plugin, panel, working_doc, fire_doc)
	await _run_finish_before_switch(plugin, panel, working_doc, fire_doc)
	await _run_active_only_viewport_updates(plugin, panel)
	await _run_invalid_document_isolation(plugin, panel)
	await _run_long_title_and_overflow(plugin, panel)
	# Real-overflow counterpart to below_overflow_three_tabs above, combined
	# into one "no_offset_buttons_below_overflow" check: _run_long_title_and_
	# overflow's own tab_row_overflow_scrolls check just proved
	# get_offset_buttons_visible() true with 24 tabs open; nothing below
	# touches tab content or %ShaderTabs's own size before this reads it, so
	# that same true value still holds.
	_finish_no_offset_buttons_below_overflow(panel, below_overflow_three_tabs)
	# Tab row and toolbar follow-up 2026-09-15: captured here, right after the
	# 24-tab overflow state _run_long_title_and_overflow's own
	# tab_row_overflow_scrolls/new_tab_button_pinned_at_row_edge_when_
	# overflowing checks just proved, and before _run_narrow_layout resizes
	# the window out from under it.
	await _capture_tab_row_evidence(plugin, "GST_TABS_UI_OVERFLOW_SCREENSHOT_PATH", "tab_row_overflow_evidence_screenshot")
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


## Recipe-name title, immediately dirty (decision 4: "unsaved nonempty
## recipe/import documents require saving" -- GSTDocument.setup's own
## starts_dirty leaves no baseline for recipe content to read clean against).
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


## Stable-ID switching, driven by real clicks (round 1 fix, Button-row era:
## real InputEventMouseButton press/release through the viewport, not a
## synthetic signal emission -- carried over unchanged by the 2026-09-15
## TabBar pass, just against %ShaderTabs's own tab rects instead of a Button's
## own rect). Exercises the trailing New control once here (the one place
## this file drives it): like File > New, it reuses an existing pristine
## document and immediately opens the Add-layer picker, cancelled explicitly
## before returning so later checks can mutate the returned document's stack
## freely.
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


## Fix 1 (round 1 required fix, Button-row era): a real click on the
## already-active tab must keep it selected. With %ShaderTabs now a native
## TabBar (2026-09-15 pass), this is an engine-level guarantee rather than
## something production code has to maintain itself:
## TabBar::set_current_tab only emits tab_changed when the index actually
## moves (tab_bar.cpp), so a reclick never even reaches
## _on_tab_bar_tab_changed's own activate_document call. Verified here
## directly against %ShaderTabs's own current_tab, not inferred from a
## Button's .button_pressed the way the Button-row era's own version of this
## check had to.
##
## Fix 2 (round 1 required fix, Button-row era): the old per-tab Button row
## froze every tab Button on every activation, dropping keyboard-undo focus
## unless _refresh_tabs() explicitly transferred it. %ShaderTabs is never
## freed or rebuilt (gst_main_panel.gd _refresh_tabs(), 2026-09-15 pass), so
## that transfer no longer exists in production -- this proves a real click
## followed by real Ctrl+Z/Ctrl+Shift+Z still reaches only the document that
## click activated, now via focus staying on %ShaderTabs itself rather than
## being handed between per-tab Buttons: fire_doc gets its own unreverted
## edit first so a stray undo/redo landing on it instead of saved_doc is
## directly observable.
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
	# UndoRedo.get_history_count() is actions.size() (core/object/undo_redo.
	# cpp), the total number of committed actions ever recorded -- it never
	# changes on undo()/redo() (only current_action does). get_current_action()
	# is the real undo-position counter.
	var saved_position_after_add: int = history_saved.get_current_action()

	# Establishes the real-world precondition a genuine click leaves behind
	# (focus on %ShaderTabs itself) before the switch this check actually
	# measures. As with the Button-row era's own precedent this replaces,
	# Viewport's own click-to-focus grab is gated behind a separate
	# hover-hierarchy structure (gui.mouse_over_hierarchy, scene/main/
	# viewport.cpp) a synthetic press/release never populates without a real
	# DisplayServer mouse-enter; this grab_focus() call supplies only that
	# one otherwise-unreachable piece of engine state, so the click below
	# still exercises %ShaderTabs's own real activation path
	# (TabBar::gui_input's own set_current_tab call, then
	# _on_tab_bar_tab_changed's own activate_document call) end to end.
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


## Selection and list-position restoration (phase 4: "restore stable-ID
## layer selection and list position"). Builds enough layers on working_doc
## to scroll, selects and scrolls away from the top, switches to fire_doc and
## back through panel.activate_document (the same production entry point a
## real tab click drives, _on_tab_bar_tab_changed), and checks both survive
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


## 2026-09-15 offset-arrows fix (user-reported defect, tabrow-arrows-2026-09-15):
## reproduces "after pressing the + new-tab button, with only two or three
## tabs open, %ShaderTabs showed its overflow scroll arrows" through the same
## real controls a user drives -- %NewTabButton (a plain Button, needing the
## NOTIFICATION_MOUSE_ENTER workaround _click_new_tab_button below documents,
## matching tests/gst_editor_document_close_smoke.gd's own _click_button
## precedent) and the new tab's own close icon (_click_tab_close below,
## matching that same file's cursor-warp precedent for TabBar's own
## close-button hit test). Checked once right after each real click settles
## (no further process_frame awaited yet: everything from _on_new_pressed's
## own click-driven cascade down through _refresh_tabs()/_apply_tab_bar_width()
## already ran synchronously inside that click's own release-event dispatch,
## gst_main_panel.gd) and once more a frame later, both directions
## (add and close) -- proving get_offset_buttons_visible() never reads true
## across that boundary, not just eventually settling back to false.
## Returns a Dictionary the caller folds into one combined
## "no_offset_buttons_below_overflow" check alongside the real-overflow (24
## tabs) counterpart _run_long_title_and_overflow already proves true, via
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


## Combines below-overflow's own two real-click phases (three_tab_phase,
## captured above right when only three tabs -- soon four, then three again --
## were open) with the real-overflow counterpart _run_long_title_and_overflow
## already proved (24 tabs, get_offset_buttons_visible() true) into the one
## "no_offset_buttons_below_overflow" check this fix pass adds. Nothing
## between that call and this one touches tab content or %ShaderTabs's own
## size, so re-reading get_offset_buttons_visible() here still reflects it.
func _finish_no_offset_buttons_below_overflow(panel: GSTMainPanel, three_tab_phase: Dictionary) -> void:
	var overflow_true_at_24_tabs: bool = panel.get_tab_bar().get_offset_buttons_visible()
	var ok: bool = bool(three_tab_phase.get("ok", false)) and overflow_true_at_24_tabs
	_check("no_offset_buttons_below_overflow", ok, "%s overflow_true_at_24_tabs=%s tab_count=%d" % [String(three_tab_phase.get("detail", "")), overflow_true_at_24_tabs, panel.get_documents().size()])


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

	# Switches away from fresh_doc while its own list is still empty (its
	# outgoing anchor capture is genuinely &"" -- get_scroll_anchor_id()
	# returns &"" for an empty list -- so this does not taint the
	# never-captured precondition the switch below depends on) and lands back
	# on working_doc so the population below runs while fresh_doc is not
	# active.
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


## Stale picker cancellation (decision 5): an open chooser on the document
## being left must be cancelled, not left open against a stack the tab row
## is about to point the shared UI away from.
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


## Finish-before-switch (decision 5, phase 1/2/3 gesture boundary): a numeric
## gesture still in flight on the document being left must commit there,
## never reach the document the switch below moves to. Mirrors
## tests/gst_editor_documents_smoke.gd's own numeric_pending_edit check
## (synthetic EditorSpinSlider.grabbed + EditorProperty.emit_changed, not an
## actual mid-drag mouse interaction -- Shader tabs phase 3 review round 2
## fix-now S3), driven here through panel.activate_document, the same
## production entry point a real tab click drives
## (_on_tab_bar_tab_changed).
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

	await panel.activate_document(broken_doc)
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
## under a deliberately long filename: its tab stays bounded at
## %ShaderTabs's own max_tab_width (gst_main_panel.tscn, 2026-09-15 TabBar
## pass; predecessor: a fixed-width, clip_text Button) while the tooltip
## still carries the full path. Then opens enough independent recipe copies
## (phase 3: never reused) to exceed the row's own visible width, proving
## %ShaderTabs's own overflow scroll controls appear
## (TabBar.get_offset_buttons_visible(); predecessor: an external
## ScrollContainer's own horizontal scrollbar range).
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

	# Tab row and toolbar follow-up 2026-09-15: once the tab content no
	# longer fits, _apply_tab_bar_width's own available-width clamp
	# (gst_main_panel.gd) pins %ShaderTabs -- and therefore %NewTabButton,
	# its fixed sibling in ShaderTabRow -- at the row's own right edge
	# instead of following the (now off-screen) last tab, with %ShaderTabs
	# scrolling its own content internally to reach it.
	var row: HBoxContainer = panel.get_tab_row()
	var new_tab_button: Button = panel.get_new_tab_button()
	var row_right_edge: float = row.get_global_rect().position.x + row.get_global_rect().size.x
	var button_right_edge: float = new_tab_button.get_global_rect().position.x + new_tab_button.get_global_rect().size.x
	var button_at_row_edge: bool = absf(button_right_edge - row_right_edge) <= 2.0
	_check("new_tab_button_pinned_at_row_edge_when_overflowing", overflowed and button_at_row_edge, "button_right=%.1f row_right=%.1f tab_count=%d" % [button_right_edge, row_right_edge, panel.get_documents().size()])


## Narrow layout (docs/DESIGN.md item 22): the tab row stays visible and
## functional at the same narrow width that collapses Layers/Layer settings
## into tabs, and the shared preview/output allocation measured through
## get_layout_measurements() stays governed by the same rules ui_layout_smoke
## already covers -- this only checks the new row does not break them.
##
## Round 1 fix 3 (Button-row era): the prior pass only checked
## row_visible/active_button_present regardless of whether the resize
## actually crossed panel.get_layout_measurements()'s own tab_breakpoint (it
## did not: narrow read false), which proved nothing about narrow layout
## specifically. This measures the wide breakpoint and tab-row height first,
## resizes below that recorded breakpoint, and requires the crossing to have
## actually happened, plus (with the ~21 tabs already open from
## _run_long_title_and_overflow, so the row already overflows at every
## width) that %ShaderTabs's own overflow controls stay visible
## (get_offset_buttons_visible()), the tab row's own height is unchanged by
## the narrower main split, and the active tab stays scrolled into view
## (gst_main_panel.gd's _on_tab_scroll_resized, round 1 fix 3, reproduced
## for TabBar.ensure_tab_visible: a resize alone, with no tab rebuild, must
## still keep it visible). No manual ensure_tab_visible/scroll call is made
## here: the whole point is proving production's own resized-signal handler
## already did it.
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
	var tab_bar: TabBar = panel.get_tab_bar()
	var row_height_wide: float = row.size.y
	var narrow_threshold: float = float(wide_measured["tab_breakpoint"])

	# Round 1 fix 3 (Button-row era): a plain window resize alone does not
	# reliably cross the breakpoint (measured: 1366->1024 actual window width
	# at this editor's own docked-panel/side-panel proportions barely moved
	# editing_rect.size.x at all). ui_layout_smoke.gd's own established
	# responsive_tabs check never relies on the window resize alone either --
	# it additionally drags %MainSplit itself once the window resize is not
	# enough. Mirrored here with the same drag mechanics (real mouse
	# press/motion/release on the splitter, tests/gst_editor_ui_layout_smoke.
	# gd's own _drag_splitter).
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
	await panel.activate_document(doc)
	await plugin.get_tree().process_frame

	var preview_after: Rect2 = panel.get_layout_measurements()["preview_rect"]
	var output_after: Rect2 = panel.get_layout_measurements()["output_rect"]
	var list_after_switch: GSTStackList = panel.get_stack_list()
	print("TABS_UI TWENTY_LAYERS preview_before=%s preview_after=%s output_before=%s output_after=%s" % [preview_before, preview_after, output_before, output_after])
	_check("twenty_layers_preview_output_rects_stable", item_count_ok and preview_before.is_equal_approx(preview_after) and output_before.is_equal_approx(output_after) and list_after_switch.get_item_count() == 20, "item_count=%d preview=%s/%s output=%s/%s" % [list_after_switch.get_item_count(), preview_before, preview_after, output_before, output_after])


## Real click on doc's own tab: press then release InputEventMouseButton at
## its global-rect center, matching the Button-row era's own established real-
## click convention. TabBar.ensure_tab_visible(index) runs first and is
## awaited a frame: a tab outside %ShaderTabs's own current
## [offset, max_drawn_tab] window reports ofs_cache 0 (tab_bar.cpp
## TabBar::_update_cache), so panel.get_tab_rect(doc) is only meaningful for
## a tab %ShaderTabs is actually showing -- this is the click helper's own
## equivalent of the Button-row era's _click_button's own
## ensure_control_visible call for a Button that could otherwise share an
## on-screen position with the row's own fixed trailing New control.
##
## Verified against .now/tabs-validation/godot-4.4-source/scene/gui/
## tab_bar.cpp: TabBar::gui_input resolves a click by the event's own
## position alone (tabs[i].cb_rect.has_point(pos), or the plain tab-body
## range check, both against the event's own transformed pos) -- unlike
## BaseButton::on_action_event, there is no status.hovering gate, so, unlike
## the Button-row era's own _click_tab, no NOTIFICATION_MOUSE_ENTER
## workaround is needed for the click itself to register.
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


## Drags split's own divider by delta.x through real mouse press/motion/
## release (matching tests/gst_editor_ui_layout_smoke.gd's own _drag_splitter
## exactly): the narrow-layout check above uses this to force %MainSplit
## narrower when a window resize alone leaves editing_rect above the
## measured breakpoint.
## Deliberately independent of _push_mouse (which uses Viewport.push_input
## for real tab clicks): this instead matches
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


## Real click on %NewTabButton's own global-rect center (never
## Button.pressed.emit()). NOTIFICATION_MOUSE_ENTER supplies the one piece of
## engine state a synthetic InputEventMouseButton never establishes on its own
## in this session (BaseButton::on_action_event gates a mouse-button event
## behind status.hovering; Viewport's own hover tracking requires a real
## DisplayServer mouse-enter) -- matches
## tests/gst_editor_document_close_smoke.gd's own _click_button exactly, this
## file's only plain-Button click target (every tab title/close click instead
## goes through _click_tab/_click_tab_close, which need no such workaround:
## TabBar's own gui_input resolves a click by the event's own position alone,
## tab_bar.cpp).
func _click_new_tab_button(plugin: EditorPlugin, button: Button) -> void:
	await plugin.get_tree().process_frame
	var point: Vector2 = button.get_global_rect().get_center()
	button.notification(Control.NOTIFICATION_MOUSE_ENTER)
	_push_mouse(plugin, point, MOUSE_BUTTON_LEFT, true)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame
	_push_mouse(plugin, point, MOUSE_BUTTON_LEFT, false)
	await plugin.get_tree().process_frame


## Real click on doc's own tab close icon: press then release
## InputEventMouseButton at panel.get_tab_close_rect(doc)'s own global-rect
## center (never panel.close_document() called directly). Warps the real OS
## cursor to the close icon first (restored after) -- matches
## tests/gst_editor_document_close_smoke.gd's own _click_tab_close exactly:
## unlike a tab body click, TabBar's own close-button press handling
## (tab_bar.cpp TabBar::gui_input's cb_pressing branch) calls _update_hover(),
## which reads the real OS cursor position for this panel's own root
## Viewport, not the synthetic event's own .position field a tab body click
## already resolves against directly.
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


## Tab row and toolbar follow-up 2026-09-15: with three tabs open (none of
## them overflowing the row), %ShaderTabs no longer stretches across
## ShaderTabRow (size_flags_horizontal SIZE_SHRINK_BEGIN, gst_main_panel.tscn)
## so its own width is sized to its tab content by
## GSTMainPanel._apply_tab_bar_width -- proven here directly: %NewTabButton's
## own global left edge sits immediately after the last tab's own global
## right edge plus the row's own separation, not out at the row's far right
## edge the way the old EXPAND-flag %ShaderTabs left it.
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


## Evidence hook (2026-09-15 layout pass; parameterized by env_var/check_name
## in the "Tab row and toolbar follow-up 2026-09-15" pass so the same helper
## captures both the three-tab and the 24-tab-overflow evidence shots),
## mirroring gst_editor_ui_complete_smoke.gd's own
## GST_UI_COMPLETE_SCREENSHOT/_capture pattern: a no-op unless the named env
## var is set, so it adds nothing to the SMOKE SUMMARY count on an ordinary
## run and cannot change any existing baseline. Called right after
## _run_stable_id_switching (three tabs: saved_doc clean, fire_doc dirty,
## working_doc pristine, no dialog or picker in the way) and again right
## after _run_long_title_and_overflow (24 tabs, the row already overflowing).
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
