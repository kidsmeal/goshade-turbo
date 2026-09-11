@tool
extends RefCounted

## Phase 2 (docs/SHADER_TABS_reviewed-plan.md): standalone routing for
## structural and native property edits. Phase 1's tabs_proof already proved
## the native gesture mechanism itself (grabbed/ungrabbed/value_focus_entered/
## value_focus_exited boundaries, the changing-flag fallback, forced-finish
## ordering, and that a real mouse drag reaches those public EditorSpinSlider
## signals) in isolation against synthetic proof targets and a standalone
## UndoRedo built by hand. This selector proves the wiring phase 2 actually
## adds: gst_inspector_column.gd's own connections from those same public
## signals into GSTUndo, on real GSTLayer/GSTCoordBlock rows inside the real
## production panel, landing in the real panel.get_watched_history().
##
## Real-mouse-driven checks (float and vector-x drags) push InputEventMouse*
## through Input.parse_input_event (the full engine input path a real
## hardware event takes) at the row's own global rect, with large per-step
## motion so the first event alone clears EditorSpinSlider's own drag-start
## threshold, and a bounded retry on the drag itself (never the assertion)
## for this environment's residual mouse-capture flakiness. Text-focus
## checks (real_text_focus, repeated_gestures, the forced-finish pending-text
## checks) instead focus the row's own EditorSpinSlider directly and push a
## real key event, which routes on Viewport key-focus rather than a
## screen-position hit test, then type real characters: this reaches the
## same real production wiring without depending on mouse/window state at
## all (phase 2 review round 2 fix pass).

const HOST_SCENE_PATH: String = "res://tests/fixtures/shader_tabs_host.tscn"

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
	plugin.get_window().grab_focus()
	await plugin.get_tree().process_frame
	if panel.is_start_screen_visible():
		panel.get_create_empty_button().pressed.emit()
		await plugin.get_tree().process_frame
		panel.get_picker().cancelled.emit()
		await plugin.get_tree().process_frame
		if panel.get_watched_history().has_undo():
			panel.get_watched_history().undo()
			await plugin.get_tree().process_frame

	var stack_list: GSTStackList = panel.get_stack_list()
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var history: UndoRedo = panel.get_watched_history()
	inspector.set_section_states({})

	var fbm: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	stack_list.select_layer(fbm.id)
	panel.set_narrow_tab(1)
	for i: int in range(4):
		await plugin.get_tree().process_frame

	# Re-asserted before each of these (rather than relying on the one call
	# above): the checks that already re-assert it right before their own
	# interaction (rgb_popup, popup_focused_shortcut, forced_finish_undo/redo)
	# reliably find a visible row; the ones that did not were observed
	# resolving is_visible_in_tree() to false on an otherwise-valid,
	# in-tree, focused EditorSpinSlider (phase 2 review round 2 fix pass).
	await _reassert_main_screen(plugin)
	await _check_real_float_drag(plugin, panel, inspector, history, fbm)
	await _reassert_main_screen(plugin)
	await _check_repeated_gestures(plugin, panel, inspector, history, fbm)
	await _reassert_main_screen(plugin)
	await _check_vector_field(plugin, panel, inspector, history, fbm)
	await _reassert_main_screen(plugin)
	await _check_real_text_focus(plugin, panel, inspector, history, fbm)
	await _check_noop_gesture(plugin, panel, inspector, history, fbm)
	await _reassert_main_screen(plugin)
	await _check_forced_finish_pending_text(plugin, panel, inspector, history, fbm)
	await _check_forced_finish_rebind(plugin, panel, inspector, history, stack_list, fbm)
	await _reassert_main_screen(plugin)
	await _check_forced_finish_save(plugin, panel, inspector, history, fbm)
	await _reassert_main_screen(plugin)
	await _check_forced_finish_save_as(plugin, panel, inspector, history, fbm)
	await _check_forced_finish_undo(plugin, panel, inspector, history, fbm)
	await _check_forced_finish_redo(plugin, panel, inspector, history, fbm)
	await _check_stale_target_rejection(plugin, panel, inspector, history, fbm)
	await _check_implicit_default(plugin, panel, inspector, history, fbm)
	await _check_rgb_popup(plugin, panel, inspector, history, stack_list)
	await _check_color_popup_unchanged(plugin, panel, inspector, history, stack_list)
	await _check_forced_finish_color_save(plugin, panel, inspector, history, stack_list)
	await _reassert_main_screen(plugin)
	await _check_forced_finish_color_save_as(plugin, panel, inspector, history, stack_list)
	await _reassert_main_screen(plugin)
	await _check_forced_finish_color_rebind(plugin, panel, inspector, history, stack_list)
	await _reassert_main_screen(plugin)
	await _check_popup_focused_shortcut(plugin, panel, inspector, history, stack_list)
	await _check_host_scene_isolation(plugin, panel, history)
	await _check_teardown_destroys_history(plugin, panel, history)

	_finish(plugin)


func _reassert_main_screen(plugin: EditorPlugin) -> void:
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await _frames(plugin, 2)


## Item: an actual multi-motion mouse drag on the real EditorSpinSlider
## applies more than one distinct intermediate value live (recorded straight
## off the row's own EditorProperty.property_changed signal, the same
## authoritative source gst_inspector_column.gd itself listens to -- not
## inferred from a single before/after resource read, which a drag that
## silently failed to register at all could satisfy vacuously), then
## registers exactly one undoable action whose undo/redo exactly restores
## the original/final values. Retries the drag itself (never the assertion)
## up to 3 times: real mouse capture on a freshly opened, automated editor
## window is inconsistent in this environment independent of the row's own
## wiring. Does not call Input.warp_mouse: EditorSpinSlider's own drag
## handling warps the real OS cursor to sustain an infinite drag, and an
## external warp call here fights that internal mechanism and can prevent
## the drag from registering at all.
func _check_real_float_drag(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, fbm: GSTLayer) -> void:
	var property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	if property != null:
		inspector.get_settings_scroll().ensure_control_visible(property)
		await _frames(plugin, 2)
	var range_control: Range = _find_range(property)
	var original: float = float(fbm.get("gain"))
	var actions_before: int = history.get_history_count()
	var recorded: Array = []
	var recorder: Callable = func(prop: StringName, value: Variant, _field: StringName, _changing: bool) -> void:
		if prop == &"gain":
			recorded.append(value)
	if property != null:
		property.property_changed.connect(recorder)
	var final_value: float = original
	var value_count: int = 0
	var attempts: int = 0
	while attempts < 3 and value_count < 2:
		attempts += 1
		recorded.clear()
		await _drag_spin(plugin, range_control)
		await _frames(plugin, 3)
		final_value = float(fbm.get("gain"))
		value_count = _distinct_value_count(recorded)
	if property != null:
		property.property_changed.disconnect(recorder)
	var one_action: bool = history.get_history_count() == actions_before + 1
	var multi_change: bool = value_count >= 2
	_check("real_float_drag_multi_change", multi_change and one_action and history.has_undo(), "attempts=%d values=%s original=%s final=%s actions=%d->%d" % [attempts, recorded, original, final_value, actions_before, history.get_history_count()])
	if not multi_change:
		return
	history.undo()
	await _frames(plugin, 2)
	var undo_ok: bool = is_equal_approx(float(fbm.get("gain")), original)
	history.redo()
	await _frames(plugin, 2)
	var redo_ok: bool = is_equal_approx(float(fbm.get("gain")), final_value)
	_check("real_float_drag_undo_redo", undo_ok and redo_ok, "undo_ok=%s redo_ok=%s" % [undo_ok, redo_ok])


## Distinct values (is_equal_approx-grouped) among the values recorded from
## a real drag's own property_changed emissions.
func _distinct_value_count(values: Array) -> int:
	var distinct: Array = []
	for value: Variant in values:
		var seen: bool = false
		for existing: Variant in distinct:
			if value is float and existing is float and is_equal_approx(value, existing):
				seen = true
				break
			elif value == existing:
				seen = true
				break
		if not seen:
			distinct.append(value)
	return distinct.size()


## Item: two later gestures on the same control each restore their own first
## value separately -- they must not merge into one action. Drives the exact
## public boundary signals a real non-drag grab followed by typed entry
## produces (gst_inspector_column.gd's own connections, decision superseding
## 20), proving the wiring without depending on synthetic mouse-capture
## timing (already proven reachable from a real drag in _check_real_float_drag
## and in phase 1's tabs_proof).
func _check_repeated_gestures(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, fbm: GSTLayer) -> void:
	var property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var spin: EditorSpinSlider = _find_range(property) as EditorSpinSlider
	if spin != null:
		inspector.get_settings_scroll().ensure_control_visible(property)
		await _frames(plugin, 2)
	var original: float = float(fbm.get("gain"))
	var actions_before: int = history.get_history_count()
	var first_result: Variant = await _drive_real_text_entry(plugin, spin, "0.7")
	var second_result: Variant = await _drive_real_text_entry(plugin, spin, "0.3")
	if first_result == null or second_result == null:
		_check("repeated_gestures_separate_actions", false, "real keyboard entry failed: first_found=%s second_found=%s" % [first_result != null, second_result != null])
		return
	var after_first: float = float(first_result)
	var after_second: float = float(second_result)
	var two_actions: bool = history.get_history_count() == actions_before + 2
	var distinct: bool = not is_equal_approx(after_first, after_second)
	history.undo()
	await _frames(plugin, 2)
	var undo_to_first: bool = is_equal_approx(float(fbm.get("gain")), after_first)
	history.undo()
	await _frames(plugin, 2)
	var undo_to_original: bool = is_equal_approx(float(fbm.get("gain")), original)
	history.redo()
	await _frames(plugin, 2)
	history.redo()
	await _frames(plugin, 2)
	var redo_to_second: bool = is_equal_approx(float(fbm.get("gain")), after_second)
	_check("repeated_gestures_separate_actions", two_actions and distinct and undo_to_first and undo_to_original and redo_to_second, "two_actions=%s after_first=%s after_second=%s undo_to_first=%s undo_to_original=%s redo_to_second=%s" % [two_actions, after_first, after_second, undo_to_first, undo_to_original, redo_to_second])


## Item: a real Vector2 field commit (coord.offset's x component only)
## applies 2 distinct intermediate values live, registers one action, and
## preserves the untouched y component (the same _merge_component_value
## path a real per-axis EditorSpinSlider drag uses).
## Drives a real mouse drag on the offset row's own x-axis EditorSpinSlider
## sub-widget (EditorPropertyVectorN's spin_sliders[0]; editor/
## editor_properties_vector.cpp confirms it emits property_changed with the
## full merged Vector2 and field "x"), the same real gesture
## _check_real_float_drag exercises, rather than synthetic emit_changed
## calls (phase 2 review round 2 fix pass).
func _check_vector_field(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, fbm: GSTLayer) -> void:
	var property: EditorProperty = inspector.find_coord_editor_property(&"offset")
	_check("vector_row_present", property != null, "coord offset row present=%s" % [property != null])
	if property == null:
		return
	inspector.get_settings_scroll().ensure_control_visible(property)
	await _frames(plugin, 2)
	var spins: Array = property.find_children("*", "EditorSpinSlider", true, false)
	var x_spin: EditorSpinSlider = spins[0] as EditorSpinSlider if not spins.is_empty() else null
	if x_spin == null:
		_check("vector_field_one_action", false, "no x-axis EditorSpinSlider found on offset row")
		return
	var original: Vector2 = fbm.coord.offset
	var actions_before: int = history.get_history_count()
	var recorded: Array = []
	var recorder: Callable = func(prop: StringName, value: Variant, field: StringName, _changing: bool) -> void:
		if prop == &"offset" and field == &"x":
			recorded.append(value)
	property.property_changed.connect(recorder)
	var value_count: int = 0
	var attempts: int = 0
	while attempts < 3 and value_count < 2:
		attempts += 1
		recorded.clear()
		await _drag_spin(plugin, x_spin)
		await _frames(plugin, 3)
		value_count = _distinct_value_count(recorded)
	property.property_changed.disconnect(recorder)
	var final_value: Vector2 = fbm.coord.offset
	var one_action: bool = history.get_history_count() == actions_before + 1
	var x_changed: bool = not is_equal_approx(final_value.x, original.x)
	var y_preserved: bool = is_equal_approx(final_value.y, original.y)
	_check("vector_field_one_action", value_count >= 2 and x_changed and y_preserved and one_action and history.has_undo(), "attempts=%d values=%s original=%s final=%s actions=%d->%d" % [attempts, recorded, original, final_value, actions_before, history.get_history_count()])
	if value_count < 2:
		return
	history.undo()
	await _frames(plugin, 2)
	var undo_ok: bool = fbm.coord.offset.is_equal_approx(original)
	history.redo()
	await _frames(plugin, 2)
	var redo_ok: bool = fbm.coord.offset.is_equal_approx(final_value)
	_check("vector_field_undo_redo", undo_ok and redo_ok, "undo_ok=%s redo_ok=%s" % [undo_ok, redo_ok])


## Item: a real non-drag grab (a mouse press/release with no motion in
## between -- EditorSpinSlider::_grab_end calls _focus_entered() directly for
## that case, per phase 1's tabs_proof, which shows and focuses the internal
## LineEdit via a deferred call) followed by real typed keystrokes and a real
## Enter is one interaction, finished once, exercising actual numeric focus
## rather than synthetic grabbed/value_focus_entered/value_focus_exited
## signal emission (phase 2 review round 1 fix pass).
func _check_real_text_focus(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, fbm: GSTLayer) -> void:
	var property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var spin: EditorSpinSlider = _find_range(property) as EditorSpinSlider
	if spin != null:
		inspector.get_settings_scroll().ensure_control_visible(property)
		await _frames(plugin, 2)
	var original: float = float(fbm.get("gain"))
	var actions_before: int = history.get_history_count()
	if spin == null:
		_check("real_text_focus_commit", false, "no EditorSpinSlider row found for gain")
		return
	var line_edit: LineEdit = await _focus_spin_text(plugin, spin)
	if line_edit == null:
		_check("real_text_focus_commit", false, "no focused numeric LineEdit found after a real ui_accept key press")
		return
	await _replace_line_edit(plugin, line_edit, "0.62")
	await _frames(plugin, 2)
	var final_value: float = float(fbm.get("gain"))
	var one_action: bool = history.get_history_count() == actions_before + 1
	_check("real_text_focus_commit", one_action and is_equal_approx(final_value, 0.62), "original=%s final=%s actions=%d->%d" % [original, final_value, actions_before, history.get_history_count()])
	if not one_action:
		return
	history.undo()
	await _frames(plugin, 2)
	var undo_ok: bool = is_equal_approx(float(fbm.get("gain")), original)
	history.redo()
	await _frames(plugin, 2)
	_check("real_text_focus_undo_redo", undo_ok and is_equal_approx(float(fbm.get("gain")), 0.62), "undo_ok=%s" % undo_ok)


static func _find_focused_line_edit(node: Node) -> LineEdit:
	if node is LineEdit and (node as LineEdit).has_focus():
		return node as LineEdit
	for child: Node in node.get_children():
		var found: LineEdit = _find_focused_line_edit(child)
		if found != null:
			return found
	return null


## Item: a grab released with no motion and no typed value is a discrete
## no-op -- it must register no action and leave the stack's own serialized
## content exactly unchanged (fix pass, round 3 item 3: an action-count check
## alone cannot catch a live intermediate write during the gesture that
## rewrote an explicit key with a value GSTUndo.values_equal's approximate
## comparison still reads as unchanged). "gain" already carries an explicit
## params key from _check_real_text_focus's own commit just before this, so
## this exercises the existing-key case specifically. Uses the same path for
## both snapshots (see _stack_snapshot): the reload -- not the raw file --
## is what makes this exact.
func _check_noop_gesture(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, fbm: GSTLayer) -> void:
	var property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var spin: EditorSpinSlider = _find_range(property) as EditorSpinSlider
	var actions_before: int = history.get_history_count()
	var had_key_before: bool = fbm.params.has("gain")
	var snapshot_path: String = "user://gst_native_undo_smoke_noop.tres"
	var snapshot_before: Dictionary = _stack_snapshot(panel, snapshot_path)
	spin.grabbed.emit()
	await plugin.get_tree().process_frame
	spin.ungrabbed.emit()
	await _frames(plugin, 3)
	var snapshot_after: Dictionary = _stack_snapshot(panel, snapshot_path)
	var serialization_unchanged: bool = not snapshot_before.is_empty() and snapshot_before == snapshot_after
	_check("noop_gesture_no_action", history.get_history_count() == actions_before and had_key_before and serialization_unchanged, "actions=%d->%d had_key_before=%s serialization_unchanged=%s" % [actions_before, history.get_history_count(), had_key_before, serialization_unchanged])


## Item (fix pass, round 3 item 3): opening a native color popup and closing
## it again without ever typing or dragging inside it is the same kind of
## no-op as the numeric case above, exercised through about_to_popup/
## popup_closed's own begin/finish bookkeeping instead of grabbed/ungrabbed --
## must register no action and leave serialized content exactly unchanged.
func _check_color_popup_unchanged(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, stack_list: GSTStackList) -> void:
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	var palette: GSTLayer = stack_list.add_layer_by_entry_id("color/palette")
	stack_list.select_layer(palette.id)
	panel.set_narrow_tab(1)
	await _frames(plugin, 4)
	var property: EditorProperty = inspector.find_editor_property(&"a", palette)
	if property != null:
		inspector.get_settings_scroll().ensure_control_visible(property)
		await _frames(plugin, 2)
	var button: ColorPickerButton = _find_color_button(property)
	if button == null:
		_check("color_popup_unchanged_present", false, "no ColorPickerButton row found for color/palette 'a'")
		return
	var actions_before: int = history.get_history_count()
	var snapshot_path: String = "user://gst_native_undo_smoke_color_noop.tres"
	var snapshot_before: Dictionary = _stack_snapshot(panel, snapshot_path)
	button.grab_focus()
	button.get_popup().popup()
	await _frames(plugin, 2)
	button.get_popup().hide()
	await _frames(plugin, 3)
	var snapshot_after: Dictionary = _stack_snapshot(panel, snapshot_path)
	var serialization_unchanged: bool = not snapshot_before.is_empty() and snapshot_before == snapshot_after
	_check("color_popup_unchanged_serialization", history.get_history_count() == actions_before and serialization_unchanged, "actions=%d->%d serialization_unchanged=%s" % [actions_before, history.get_history_count(), serialization_unchanged])


## Exact serialization for the no-op checks above (fix pass, round 3 item 3):
## saves the open stack to `path`, reloads it, and returns a Dictionary of
## every field the .tres schema actually carries (docs/SHADER_TABS_reviewed-
## plan.md Cross-cutting "Serialization and recovery format": stack/header
## schema, stable layer ids, parameter keys, shader text contracts), compared
## by callers with plain `==` (exact Variant equality, not
## GSTUndo.values_equal's approximate one): a no-op whose live intermediate
## write left a value that differs from the original in its low bits but
## still reads as unchanged must still be caught here. Not a raw byte-text
## comparison of the saved file: ResourceSaver.save assigns each
## ext_resource/sub_resource a fresh random id suffix on every save
## (confirmed against a real recipe .tres's own `id="1_xxxxx"` fields), so two
## saves of the identical, unchanged stack are never byte-identical even
## though their actual data is.
func _stack_snapshot(panel: GSTMainPanel, path: String) -> Dictionary:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var save_result: Dictionary = GSTStackIO.save(panel.get_stack(), path)
	if not save_result["ok"]:
		return {}
	var load_result: Dictionary = GSTStackIO.load(path, panel.get_library())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not load_result["ok"]:
		return {}
	var stack: GSTStack = load_result["stack"]
	var layers: Array = []
	for layer: GSTLayer in stack.layers:
		layers.append({
			"id": layer.id,
			"entry": layer.entry,
			"kind_out": layer.kind_out,
			"params": layer.params.duplicate(true),
			"slots": layer.slots.duplicate(true),
			"coord": _coord_snapshot(layer.coord),
		})
	return {
		"next_id": stack.next_id,
		"output_color": stack.output_color,
		"output_alpha": stack.output_alpha,
		"coord_space": stack.coord_space,
		"layers": layers,
	}


func _coord_snapshot(coord: GSTCoordBlock) -> Variant:
	if coord == null:
		return null
	return {
		"scale": coord.scale,
		"offset": coord.offset,
		"rotation": coord.rotation,
		"scroll": coord.scroll,
		"warp_x": coord.warp_x,
		"warp_y": coord.warp_y,
		"warp_strength": coord.warp_strength,
	}


## Item: a real numeric value typed but never submitted (no Enter, no focus
## change -- still genuinely pending when this starts) is delivered by
## panel._finish_pending_edits() alone, the exact shared boundary every
## forced-finish call site here awaits and the one phase 7 will reuse for
## the confirmed-shutdown save callback (phase 2 review round 2 fix pass:
## "shutdown-boundary coverage is absent").
func _check_forced_finish_pending_text(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, fbm: GSTLayer) -> void:
	var property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var spin: EditorSpinSlider = _find_range(property) as EditorSpinSlider
	if spin != null:
		inspector.get_settings_scroll().ensure_control_visible(property)
		await _frames(plugin, 2)
	var original: float = float(fbm.get("gain"))
	var actions_before: int = history.get_history_count()
	if spin == null:
		_check("forced_finish_pending_text", false, "no EditorSpinSlider row found for gain")
		return
	var line_edit: LineEdit = await _focus_spin_text(plugin, spin)
	if line_edit == null:
		_check("forced_finish_pending_text", false, "no focused numeric LineEdit found after a real ui_accept key press")
		return
	await _type_into_line_edit(plugin, line_edit, "0.44")
	var pending_before_finish: bool = not is_equal_approx(float(fbm.get("gain")), 0.44)
	await panel._finish_pending_edits()
	await _frames(plugin, 2)
	var one_action: bool = history.get_history_count() == actions_before + 1
	var delivered: bool = is_equal_approx(float(fbm.get("gain")), 0.44)
	_check("forced_finish_pending_text", pending_before_finish and one_action and delivered, "pending_before_finish=%s actions=%d->%d value=%s" % [pending_before_finish, actions_before, history.get_history_count(), fbm.get("gain")])
	if not delivered:
		return
	history.undo()
	await _frames(plugin, 2)
	var undo_ok: bool = is_equal_approx(float(fbm.get("gain")), original)
	history.redo()
	await _frames(plugin, 2)
	_check("forced_finish_pending_text_undo_redo", undo_ok and is_equal_approx(float(fbm.get("gain")), 0.44), "undo_ok=%s" % undo_ok)


## Item: switching the selected layer mid-drag (a rebind) finishes the
## pending gesture on the original layer first; the new selection starts
## clean.
func _check_forced_finish_rebind(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, stack_list: GSTStackList, fbm: GSTLayer) -> void:
	var property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var spin: EditorSpinSlider = _find_range(property) as EditorSpinSlider
	var original: float = float(fbm.get("gain"))
	spin.grabbed.emit()
	property.emit_changed(&"gain", 0.66, &"", true)
	await plugin.get_tree().process_frame
	var mid_value: float = float(fbm.get("gain"))
	var second: GSTLayer = stack_list.add_layer_by_entry_id("fieldops/invert")
	stack_list.select_layer(second.id)
	await _frames(plugin, 3)
	var finished_before_switch: bool = is_equal_approx(mid_value, 0.66) and not is_equal_approx(mid_value, original)
	var fbm_value_after_switch: float = float(fbm.get("gain"))
	_check("forced_finish_before_rebind", finished_before_switch and is_equal_approx(fbm_value_after_switch, mid_value) and history.has_undo(), "original=%s mid=%s after_switch=%s" % [original, mid_value, fbm_value_after_switch])
	stack_list.select_layer(fbm.id)
	await _frames(plugin, 3)


## Item: a real numeric value typed but never submitted (no Enter, no focus
## exit -- genuinely pending, unevaluated text, not an already-applied
## changing=true value) must still reach the resource, and the saved file,
## before Save returns (phase 2 review round 2 fix pass: a forced-save check
## that only re-saves a value the model already holds does not establish
## pending-text delivery).
func _check_forced_finish_save(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, fbm: GSTLayer) -> void:
	var property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var spin: EditorSpinSlider = _find_range(property) as EditorSpinSlider
	if spin != null:
		inspector.get_settings_scroll().ensure_control_visible(property)
		await _frames(plugin, 2)
	if spin == null:
		_check("forced_finish_before_save", false, "no EditorSpinSlider row found for gain")
		return
	var line_edit: LineEdit = await _focus_spin_text(plugin, spin)
	if line_edit == null:
		_check("forced_finish_before_save", false, "no focused numeric LineEdit found after a real ui_accept key press")
		return
	await _type_into_line_edit(plugin, line_edit, "0.28")
	var pending_before_save: bool = not is_equal_approx(float(fbm.get("gain")), 0.28)
	var save_path: String = "user://gst_native_undo_smoke_forced_save.tres"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	await panel.save_to_path(save_path)
	await _frames(plugin, 2)
	var delivered_value: float = float(fbm.get("gain"))
	var load_result: Dictionary = GSTStackIO.load(save_path, panel.get_library())
	var reloaded: GSTStack = load_result["stack"] as GSTStack if load_result["ok"] else null
	var saved_layer: GSTLayer = GSTStackOps.find_layer(reloaded, fbm.id) if reloaded != null else null
	var saved_gain: float = float(saved_layer.get("gain")) if saved_layer != null else -1.0
	_check("forced_finish_before_save", pending_before_save and reloaded != null and saved_layer != null and is_equal_approx(delivered_value, 0.28) and is_equal_approx(saved_gain, delivered_value), "pending_before_save=%s delivered=%s saved=%s" % [pending_before_save, delivered_value, saved_gain])
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## Item: a real numeric value typed but never submitted, then Save As's own
## file-selected handler (the same handler the real Save As dialog invokes,
## per tests/gst_editor_smoke.gd's own precedent of calling it directly),
## must still finish the gesture and write the delivered value (phase 2
## review round 2 fix pass: same pending-text requirement as
## forced_finish_before_save above).
func _check_forced_finish_save_as(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, fbm: GSTLayer) -> void:
	var property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var spin: EditorSpinSlider = _find_range(property) as EditorSpinSlider
	if spin != null:
		inspector.get_settings_scroll().ensure_control_visible(property)
		await _frames(plugin, 2)
	if spin == null:
		_check("forced_finish_before_save_as", false, "no EditorSpinSlider row found for gain")
		return
	var line_edit: LineEdit = await _focus_spin_text(plugin, spin)
	if line_edit == null:
		_check("forced_finish_before_save_as", false, "no focused numeric LineEdit found after a real ui_accept key press")
		return
	await _type_into_line_edit(plugin, line_edit, "0.71")
	var pending_before_save: bool = not is_equal_approx(float(fbm.get("gain")), 0.71)
	var save_path: String = "user://gst_native_undo_smoke_forced_save_as.tres"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	panel._on_save_as_file_selected(save_path)
	await _frames(plugin, 3)
	var delivered_value: float = float(fbm.get("gain"))
	var load_result: Dictionary = GSTStackIO.load(save_path, panel.get_library())
	var reloaded: GSTStack = load_result["stack"] as GSTStack if load_result["ok"] else null
	var saved_layer: GSTLayer = GSTStackOps.find_layer(reloaded, fbm.id) if reloaded != null else null
	var saved_gain: float = float(saved_layer.get("gain")) if saved_layer != null else -1.0
	_check("forced_finish_before_save_as", pending_before_save and reloaded != null and saved_layer != null and is_equal_approx(delivered_value, 0.71) and is_equal_approx(saved_gain, delivered_value), "pending_before_save=%s delivered=%s saved=%s" % [pending_before_save, delivered_value, saved_gain])
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## Item: starting a drag, then triggering keyboard Undo, finishes the
## gesture first, so the undo it performs is of the just-finished action, not
## of whatever preceded it, and the final dragged value is never lost.
func _check_forced_finish_undo(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, fbm: GSTLayer) -> void:
	var property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var spin: EditorSpinSlider = _find_range(property) as EditorSpinSlider
	var original: float = float(fbm.get("gain"))
	var actions_before: int = history.get_history_count()
	spin.grabbed.emit()
	property.emit_changed(&"gain", 0.36, &"", true)
	await plugin.get_tree().process_frame
	var attempts: int = 0
	while attempts < 5 and history.get_history_count() == actions_before:
		attempts += 1
		EditorInterface.set_main_screen_editor("GoShade Turbo")
		spin.grab_focus()
		await plugin.get_tree().create_timer(0.2).timeout
		_push_key(EditorInterface.get_base_control(), KEY_Z, true)
		await _frames(plugin, 3)
	var one_action_then_undone: bool = history.get_history_count() == actions_before + 1 and is_equal_approx(float(fbm.get("gain")), original)
	_check("forced_finish_before_undo", one_action_then_undone, "actions=%d->%d value=%s original=%s" % [actions_before, history.get_history_count(), fbm.get("gain"), original])
	history.redo()
	await _frames(plugin, 2)


## Item: finishing a pending drag while a redo is queued commits it as a new
## action, which discards that stale redo per UndoRedo's own create_action
## semantics -- so it can never silently overwrite the value the drag just
## landed. Drives a real Ctrl+Shift+Z key event (phase 2 review round 2 fix
## pass: previously called panel._finish_pending_edits() directly, which the
## reviewer flagged as not exercising the real shortcut's own keyboard path)
## with the same retry pattern _check_forced_finish_undo's real plain Ctrl+Z
## already uses successfully; unlike the color-popup case elsewhere in this
## file, no embedded subwindow is open here, so this key event reaches
## gst_main_panel._input() through the normal root-viewport path.
##
## Asserts on get_current_action(), not get_history_count(): a commit
## made right after an undo first discards that undo's now-stale redo
## array entry (UndoRedo::create_action's own discard_redo), then appends
## the new one, so the total array size can stay unchanged even though a
## real new action replaced the discarded one (docs/EDITOR_SMOKE.md
## "Shader tabs phase 2" root cause for an identical `randomize_undo`
## measurement bug; get_current_action() is the position, which does
## advance).
func _check_forced_finish_redo(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, fbm: GSTLayer) -> void:
	var property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var spin: EditorSpinSlider = _find_range(property) as EditorSpinSlider
	var baseline: float = float(fbm.get("gain"))
	spin.grabbed.emit()
	property.emit_changed(&"gain", clampf(baseline + 0.05, 0.2, 0.8), &"", true)
	await plugin.get_tree().process_frame
	spin.ungrabbed.emit()
	await _frames(plugin, 2)
	history.undo()
	await _frames(plugin, 2)
	var redo_pending_before: bool = history.has_redo()
	var position_before: int = history.get_current_action()
	var drag_final: float = clampf(baseline + 0.1, 0.2, 0.8)
	spin.grabbed.emit()
	property.emit_changed(&"gain", drag_final, &"", true)
	await plugin.get_tree().process_frame
	var attempts: int = 0
	while attempts < 5 and history.get_current_action() == position_before:
		attempts += 1
		EditorInterface.set_main_screen_editor("GoShade Turbo")
		spin.grab_focus()
		await plugin.get_tree().create_timer(0.2).timeout
		_push_key(EditorInterface.get_base_control(), KEY_Z, true, true)
		await _frames(plugin, 3)
	var gesture_finished_first: bool = history.get_current_action() == position_before + 1 and is_equal_approx(float(fbm.get("gain")), drag_final)
	var stale_redo_discarded: bool = not history.has_redo()
	_check("forced_finish_before_redo", redo_pending_before and gesture_finished_first and stale_redo_discarded, "attempts=%d redo_pending_before=%s position=%d->%d value=%s expected=%s stale_redo_discarded=%s" % [attempts, redo_pending_before, position_before, history.get_current_action(), fbm.get("gain"), drag_final, stale_redo_discarded])
	if history.has_redo():
		history.redo()
		await _frames(plugin, 2)


## Item: a late signal delivered from a row captured just before a rebind --
## the exact instant a real EditorSpinSlider mid-air during a real rebind
## could still emit one -- must never write to fbm nor register a history
## action, because gst_inspector_column.gd's own rebuild already erased that
## row's _property_rows entry synchronously (before the freed Nodes
## themselves are actually destroyed). Delivers the signal in the same call
## frame as the rebind, before any await lets the queued frees run, so the
## captured editor/spin are still valid Objects (is_instance_valid) able to
## actually emit -- proving the rejection comes from the dictionary lookup,
## not from the signal never reaching anything.
func _check_stale_target_rejection(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, fbm: GSTLayer) -> void:
	var stale_property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var stale_spin: EditorSpinSlider = _find_range(stale_property) as EditorSpinSlider
	var fbm_value_before: float = float(fbm.get("gain"))
	# add_layer_by_entry_id already selects its new layer (rebinding the
	# inspector column and rebuilding rows), registering its own legitimate
	# add-layer action; history_before is captured after that settles, so
	# only the stale signal delivered below is under measurement.
	var other: GSTLayer = panel.get_stack_list().add_layer_by_entry_id("generative/hash")
	var history_before: int = history.get_history_count()
	var late_signal_reachable: bool = stale_property != null and is_instance_valid(stale_property) and stale_spin != null and is_instance_valid(stale_spin)
	if late_signal_reachable:
		stale_property.emit_changed(&"gain", 0.91, &"", true)
		stale_property.emit_changed(&"gain", 0.91, &"", false)
		stale_spin.grabbed.emit()
		stale_spin.ungrabbed.emit()
	await _frames(plugin, 3)
	var fbm_unaffected: bool = is_equal_approx(float(fbm.get("gain")), fbm_value_before)
	var no_new_action: bool = history.get_history_count() == history_before
	_check("stale_target_late_signal_rejected", late_signal_reachable and fbm_unaffected and no_new_action, "late_signal_reachable=%s before=%s after=%s actions=%d->%d" % [late_signal_reachable, fbm_value_before, fbm.get("gain"), history_before, history.get_history_count()])
	panel.get_stack_list().select_layer(fbm.id)
	await _frames(plugin, 3)
	var restored_property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	_check("stale_target_rebinds_on_reselect", restored_property != null and is_equal_approx(float(fbm.get("gain")), fbm_value_before), "restored=%s value=%s" % [restored_property != null, fbm.get("gain")])


## Item: a native RGB popup's final property_changed(changing=false) on close
## finishes once, undoes to the original color, and redoes to the final one
## (Color center: color/palette's "a" param). Drives the real popup through
## its actual hex LineEdit; the popup does not depend on the outer dock's
## mouse-capture path _check_real_float_drag works around.
func _check_rgb_popup(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, stack_list: GSTStackList) -> void:
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	var palette: GSTLayer = stack_list.add_layer_by_entry_id("color/palette")
	stack_list.select_layer(palette.id)
	panel.set_narrow_tab(1)
	await _frames(plugin, 4)
	var property: EditorProperty = inspector.find_editor_property(&"a", palette)
	if property != null:
		inspector.get_settings_scroll().ensure_control_visible(property)
		await _frames(plugin, 2)
	var button: ColorPickerButton = _find_color_button(property)
	if button == null:
		_check("rgb_popup_present", false, "no ColorPickerButton row found for color/palette 'a'")
		return
	var original: Color = button.color
	var actions_before: int = history.get_history_count()
	button.grab_focus()
	button.get_popup().popup()
	await _frames(plugin, 2)
	var hex_edit: LineEdit = _find_hex_line_edit(button.get_picker())
	if hex_edit != null:
		await _replace_line_edit(plugin, hex_edit, "3366cc")
	# Release the hex LineEdit's own focus before hiding, matching
	# gst_inspector_column.gd's own _force_close_color_popups (the
	# production close path _check_popup_focused_shortcut below drives
	# through finish_pending_edits), and only hide if Godot has not
	# already closed the popup on its own. Neither this nor the
	# focus-release below fully resolved the "rgb_popup_undo_redo" flake
	# documented as unresolved in docs/EDITOR_SMOKE.md for this fix pass;
	# both are still correct practice and kept as partial hardening.
	if hex_edit != null and hex_edit.has_focus():
		hex_edit.release_focus()
		await _frames(plugin, 2)
	if button.get_popup().visible:
		button.get_popup().hide()
	await _frames(plugin, 3)
	var final_color: Color = Color(0x33 / 255.0, 0x66 / 255.0, 0xcc / 255.0, 1.0)
	var one_action: bool = history.get_history_count() == actions_before + 1
	var applied: bool = palette.get(&"a") is Color and (palette.get(&"a") as Color).is_equal_approx(final_color)
	_check("rgb_popup_commit", hex_edit != null and one_action and applied, "hex_found=%s actions=%d->%d applied=%s color=%s" % [hex_edit != null, actions_before, history.get_history_count(), applied, palette.get(&"a")])
	if not applied:
		return
	history.undo()
	await _frames(plugin, 2)
	var undo_ok: bool = palette.get(&"a") is Color and (palette.get(&"a") as Color).is_equal_approx(original)
	history.redo()
	await _frames(plugin, 2)
	var redo_ok: bool = palette.get(&"a") is Color and (palette.get(&"a") as Color).is_equal_approx(final_color)
	_check("rgb_popup_undo_redo", undo_ok and redo_ok, "undo_ok=%s redo_ok=%s" % [undo_ok, redo_ok])


## Opens property's own ColorPickerButton popup and types a pending
## (unsubmitted -- no Enter) hex value into its hex LineEdit, the same real
## popup + real keystrokes technique _check_rgb_popup uses above, factored
## out for the forced-boundary color checks below (fix pass, round 3 item 2:
## color Save/Save As/rebind boundary coverage was absent).
## {"ok", "button", "hex_edit"}.
func _start_pending_color_edit(plugin: EditorPlugin, inspector: GSTInspectorColumn, layer: GSTLayer, property_name: StringName, hex_text: String) -> Dictionary:
	var property: EditorProperty = inspector.find_editor_property(property_name, layer)
	if property != null:
		inspector.get_settings_scroll().ensure_control_visible(property)
		await _frames(plugin, 2)
	var button: ColorPickerButton = _find_color_button(property)
	if button == null:
		return {"ok": false, "button": null, "hex_edit": null}
	button.grab_focus()
	button.get_popup().popup()
	await _frames(plugin, 2)
	var hex_edit: LineEdit = _find_hex_line_edit(button.get_picker())
	if hex_edit == null:
		button.get_popup().hide()
		return {"ok": false, "button": button, "hex_edit": null}
	await _type_into_line_edit(plugin, hex_edit, hex_text)
	return {"ok": true, "button": button, "hex_edit": hex_edit}


## Item (fix pass, round 3 item 2): a pending, unsubmitted native color popup
## hex edit must still finish and reach Save's own write to the original
## edited layer instance, the same color forced-boundary coverage the
## numeric _check_forced_finish_save above already proves.
func _check_forced_finish_color_save(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, stack_list: GSTStackList) -> void:
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	var palette: GSTLayer = stack_list.add_layer_by_entry_id("color/palette")
	stack_list.select_layer(palette.id)
	panel.set_narrow_tab(1)
	await _frames(plugin, 4)
	var actions_before: int = history.get_history_count()
	var pending: Dictionary = await _start_pending_color_edit(plugin, inspector, palette, &"a", "445566")
	if not bool(pending["ok"]):
		_check("forced_finish_before_save_color", false, "pending color edit not reachable (hex_found=%s)" % [pending["hex_edit"] != null])
		return
	var expected: Color = Color(0x44 / 255.0, 0x55 / 255.0, 0x66 / 255.0, 1.0)
	var pending_before_save: bool = not (palette.get(&"a") as Color).is_equal_approx(expected)
	var save_path: String = "user://gst_native_undo_smoke_forced_save_color.tres"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	await panel.save_to_path(save_path)
	await _frames(plugin, 2)
	var delivered: Color = palette.get(&"a")
	var one_action: bool = history.get_history_count() == actions_before + 1
	var load_result: Dictionary = GSTStackIO.load(save_path, panel.get_library())
	var reloaded: GSTStack = load_result["stack"] as GSTStack if load_result["ok"] else null
	var saved_layer: GSTLayer = GSTStackOps.find_layer(reloaded, palette.id) if reloaded != null else null
	var saved_color: Color = saved_layer.get(&"a") if saved_layer != null else Color()
	_check("forced_finish_before_save_color", pending_before_save and one_action and delivered.is_equal_approx(expected) and reloaded != null and saved_layer != null and saved_color.is_equal_approx(expected), "pending_before_save=%s actions=%d->%d delivered=%s saved=%s" % [pending_before_save, actions_before, history.get_history_count(), delivered, saved_color])
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## Item (fix pass, round 3 item 2): same pending-color-edit requirement as
## above, through Save As's own file-selected handler (the same handler the
## real Save As dialog invokes, per this file's own precedent for the
## numeric case in _check_forced_finish_save_as).
func _check_forced_finish_color_save_as(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, stack_list: GSTStackList) -> void:
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	var palette: GSTLayer = stack_list.add_layer_by_entry_id("color/palette")
	stack_list.select_layer(palette.id)
	panel.set_narrow_tab(1)
	await _frames(plugin, 4)
	var actions_before: int = history.get_history_count()
	var pending: Dictionary = await _start_pending_color_edit(plugin, inspector, palette, &"a", "778899")
	if not bool(pending["ok"]):
		_check("forced_finish_before_save_as_color", false, "pending color edit not reachable (hex_found=%s)" % [pending["hex_edit"] != null])
		return
	var expected: Color = Color(0x77 / 255.0, 0x88 / 255.0, 0x99 / 255.0, 1.0)
	var pending_before_save: bool = not (palette.get(&"a") as Color).is_equal_approx(expected)
	var save_path: String = "user://gst_native_undo_smoke_forced_save_as_color.tres"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	panel._on_save_as_file_selected(save_path)
	await _frames(plugin, 3)
	var delivered: Color = palette.get(&"a")
	var one_action: bool = history.get_history_count() == actions_before + 1
	var load_result: Dictionary = GSTStackIO.load(save_path, panel.get_library())
	var reloaded: GSTStack = load_result["stack"] as GSTStack if load_result["ok"] else null
	var saved_layer: GSTLayer = GSTStackOps.find_layer(reloaded, palette.id) if reloaded != null else null
	var saved_color: Color = saved_layer.get(&"a") if saved_layer != null else Color()
	_check("forced_finish_before_save_as_color", pending_before_save and one_action and delivered.is_equal_approx(expected) and reloaded != null and saved_layer != null and saved_color.is_equal_approx(expected), "pending_before_save=%s actions=%d->%d delivered=%s saved=%s" % [pending_before_save, actions_before, history.get_history_count(), delivered, saved_color])
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## Item (fix pass, round 3 item 2): switching the selected layer while a
## native color popup holds a pending hex edit finishes it on the original
## layer instance first -- same forced-finish-before-rebind requirement
## _check_forced_finish_rebind proves for a numeric drag, isolated to just
## the finish's own action (actions_before_switch is captured after adding
## the second layer's own add action, so + 1 measures only the color commit).
func _check_forced_finish_color_rebind(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, stack_list: GSTStackList) -> void:
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	var palette: GSTLayer = stack_list.add_layer_by_entry_id("color/palette")
	stack_list.select_layer(palette.id)
	panel.set_narrow_tab(1)
	await _frames(plugin, 4)
	var pending: Dictionary = await _start_pending_color_edit(plugin, inspector, palette, &"a", "aabbcc")
	if not bool(pending["ok"]):
		_check("forced_finish_before_rebind_color", false, "pending color edit not reachable (hex_found=%s)" % [pending["hex_edit"] != null])
		return
	var expected: Color = Color(0xaa / 255.0, 0xbb / 255.0, 0xcc / 255.0, 1.0)
	var other: GSTLayer = stack_list.add_layer_by_entry_id("fieldops/invert")
	var actions_before_switch: int = history.get_history_count()
	stack_list.select_layer(other.id)
	await _frames(plugin, 4)
	var finished_before_switch: bool = palette.get(&"a") is Color and (palette.get(&"a") as Color).is_equal_approx(expected)
	var one_action: bool = history.get_history_count() == actions_before_switch + 1
	_check("forced_finish_before_rebind_color", finished_before_switch and one_action and history.has_undo(), "expected=%s final=%s actions=%d->%d" % [expected, palette.get(&"a"), actions_before_switch, history.get_history_count()])
	stack_list.select_layer(palette.id)
	await _frames(plugin, 3)


## Item (fix pass, round 3 item 1): a real Ctrl+Z sent through the root
## viewport, while a native color popup currently holds embedded-subwindow
## focus and a hex edit is genuinely pending (typed, not submitted), reaches
## gst_inspector_column.gd's own popup-local window_input handler and finishes
## that edit into one action, then undoes it -- proving the real production
## keyboard path, not a direct panel._finish_pending_edits() call standing in
## for it (the reviewer's own round 3 finding: the direct call at this site
## previously proved nothing about the popup's own key-event wiring).
##
## Confirmed against the engine source, not assumed: Viewport::push_input
## (scene/main/viewport.cpp) forwards any event -- key or mouse -- to
## gui.subwindow_focused->_window_input(event) and returns before the root
## viewport's own per-viewport "_vp_input<id>" group (gst_main_panel among
## them) is ever notified, whenever an embedded subwindow (this popup)
## currently holds focus; Window::_window_input (scene/main/window.cpp)
## emits its own window_input signal before calling push_input() on itself,
## i.e. before the popup's own GUI dispatch could let the hex LineEdit
## consume the same Ctrl+Z as its built-in text-undo. Window.popup()
## registers the window as the embedder's focused embedded subwindow
## automatically (Viewport::_sub_window_register), so no extra focus call is
## needed beyond the popup already being open with hex_edit focused.
##
## Item (review round 4 fix-now): the redo half below previously called
## history.redo() directly, proving nothing about the popup's own ui_redo
## routing (Ctrl+Shift+Z could have been silently misrouted to
## _apply_keyboard_undo_redo(false) without this test noticing, since
## history.redo() would still land on final_color regardless). It now
## reopens the same color popup and holds focus in its hex field via
## _start_pending_color_edit(..., "") -- no characters typed, so
## about_to_popup's own state["original"] == state["final"] capture makes
## this a genuine no-op gesture (gst_inspector_column.gd's own values_equal
## check skips registering an action), leaving the redo left by the undo
## above untouched -- then pushes a real Ctrl+Shift+Z through the popup's
## own window_input while it holds embedded-subwindow focus. Asserting
## get_history_count() is unchanged from immediately before this reopen
## proves the position only advanced because _apply_keyboard_undo_redo(true)
## actually called _undo_redo.redo() (a genuine redo), not because finishing
## a pending edit pushed a coincidental new action that happened to match
## final_color.
func _check_popup_focused_shortcut(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, stack_list: GSTStackList) -> void:
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	var palette: GSTLayer = stack_list.add_layer_by_entry_id("color/palette")
	stack_list.select_layer(palette.id)
	panel.set_narrow_tab(1)
	await _frames(plugin, 4)
	var original: Color = palette.get(&"a")
	var actions_before: int = history.get_history_count()
	var position_before: int = history.get_current_action()
	var pending: Dictionary = await _start_pending_color_edit(plugin, inspector, palette, &"a", "112233")
	if not bool(pending["ok"]):
		_check("popup_focused_shortcut_present", false, "pending color edit not reachable (hex_found=%s)" % [pending["hex_edit"] != null])
		return
	var button: ColorPickerButton = pending["button"]
	var hex_edit: LineEdit = pending["hex_edit"]
	var focused: Control = hex_edit.get_viewport().gui_get_focus_owner()
	var owns_focus_ok: bool = inspector.owns_popup_focus(focused)
	var final_color: Color = Color(0x11 / 255.0, 0x22 / 255.0, 0x33 / 255.0, 1.0)
	var attempts: int = 0
	# Loops on get_history_count(), not get_current_action(): committing the
	# pending edit then immediately undoing it (this function's own expected
	# outcome) nets back to position_before, indistinguishable from "nothing
	# happened yet" if the loop condition read position instead -- a second,
	# spurious Ctrl+Z would then undo the action before this one. The total
	# array size only ever grows on a genuine commit, regardless of any undo
	# that follows it.
	while attempts < 5 and history.get_history_count() == actions_before:
		attempts += 1
		if is_instance_valid(hex_edit):
			hex_edit.grab_focus()
		await plugin.get_tree().create_timer(0.2).timeout
		_push_key(EditorInterface.get_base_control(), KEY_Z, true)
		await _frames(plugin, 4)
	var committed_then_undone: bool = history.get_history_count() == actions_before + 1 and history.get_current_action() == position_before
	var restored_to_original: bool = palette.get(&"a") is Color and (palette.get(&"a") as Color).is_equal_approx(original)
	var popup_closed_by_finish: bool = is_instance_valid(button) and not button.get_popup().visible
	_check("popup_focused_shortcut_recognized_and_finished", owns_focus_ok and committed_then_undone and restored_to_original and popup_closed_by_finish, "attempts=%d owns_focus=%s actions=%d->%d position=%d->%d restored=%s popup_visible=%s color=%s" % [attempts, owns_focus_ok, actions_before, history.get_history_count(), position_before, history.get_current_action(), restored_to_original, is_instance_valid(button) and button.get_popup().visible, palette.get(&"a")])
	if not committed_then_undone:
		return
	var redo_pending_before: bool = history.has_redo()
	var redo_history_count_before: int = history.get_history_count()
	var pending_redo: Dictionary = await _start_pending_color_edit(plugin, inspector, palette, &"a", "")
	if not bool(pending_redo["ok"]):
		_check("popup_focused_shortcut_redo", false, "pending color edit not reachable for redo (hex_found=%s)" % [pending_redo["hex_edit"] != null])
		return
	var redo_button: ColorPickerButton = pending_redo["button"]
	var redo_hex_edit: LineEdit = pending_redo["hex_edit"]
	var redo_attempts: int = 0
	# Genuine redo advances the position (unlike the undo case above's
	# commit-then-undo, which nets back to the same position), so this loops
	# on get_current_action() the same way _check_forced_finish_redo does.
	while redo_attempts < 5 and history.get_current_action() == position_before:
		redo_attempts += 1
		if is_instance_valid(redo_hex_edit):
			redo_hex_edit.grab_focus()
		await plugin.get_tree().create_timer(0.2).timeout
		_push_key(EditorInterface.get_base_control(), KEY_Z, true, true)
		await _frames(plugin, 4)
	var redo_landed: bool = history.get_current_action() == position_before + 1 and history.get_history_count() == redo_history_count_before
	var redo_value_ok: bool = palette.get(&"a") is Color and (palette.get(&"a") as Color).is_equal_approx(final_color)
	var redo_popup_closed: bool = is_instance_valid(redo_button) and not redo_button.get_popup().visible
	_check("popup_focused_shortcut_redo", redo_pending_before and redo_landed and redo_value_ok and redo_popup_closed, "attempts=%d redo_pending_before=%s position=%d->%d history_count=%d->%d color=%s popup_visible=%s" % [redo_attempts, redo_pending_before, position_before, history.get_current_action(), redo_history_count_before, history.get_history_count(), palette.get(&"a"), is_instance_valid(redo_button) and redo_button.get_popup().visible])


## Item: undoing a property edit that had no prior explicit params key
## reverts the read value back to the manifest default and, per fix pass 1,
## reverts the params key back to fully absent (not an explicit entry that
## merely equals the default) -- the dirty fingerprint includes serialized
## params keys, so leaving one behind after undo would change it even
## though the read value is unchanged. Also proves a no-op gesture (a real
## drag that returns to its own original absent-backed value) restores that
## same absence, even though the live intermediate mutation wrote an
## explicit key along the way.
func _check_implicit_default(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, fbm: GSTLayer) -> void:
	var octaves_property: EditorProperty = inspector.find_editor_property(&"octaves", fbm)
	var octaves_spin: EditorSpinSlider = _find_range(octaves_property) as EditorSpinSlider
	if octaves_property == null:
		_check("implicit_default_row", false, "no octaves row found on generative/fbm")
		return
	var had_key_before: bool = fbm.params.has("octaves")
	var original: int = int(fbm.get("octaves"))
	octaves_property.emit_changed(&"octaves", original + 1)
	await _frames(plugin, 3)
	var changed_ok: bool = int(fbm.get("octaves")) == original + 1 and fbm.params.has("octaves")
	history.undo()
	await _frames(plugin, 3)
	var restored_value_ok: bool = int(fbm.get("octaves")) == original
	var restored_absence_ok: bool = fbm.params.has("octaves") == had_key_before
	_check("implicit_default_undo", changed_ok and restored_value_ok and restored_absence_ok, "had_key_before=%s original=%s after=%s restored_value=%s key_present_after_undo=%s" % [had_key_before, original, fbm.get("octaves"), restored_value_ok, fbm.params.has("octaves")])

	if had_key_before or octaves_spin == null:
		return
	var noop_actions_before: int = history.get_history_count()
	octaves_spin.grabbed.emit()
	octaves_property.emit_changed(&"octaves", original + 1, &"", true)
	await plugin.get_tree().process_frame
	octaves_property.emit_changed(&"octaves", original, &"", true)
	await plugin.get_tree().process_frame
	octaves_spin.ungrabbed.emit()
	await _frames(plugin, 2)
	var noop_no_action: bool = history.get_history_count() == noop_actions_before
	var noop_absence_restored: bool = not fbm.params.has("octaves")
	_check("noop_gesture_restores_param_absence", noop_no_action and noop_absence_restored, "actions=%d->%d value=%s key_present_after=%s" % [noop_actions_before, history.get_history_count(), fbm.get("octaves"), fbm.params.has("octaves")])


## Item: keyboard Undo/Redo is scoped to GoShade focus. Pressed with focus
## inside GoShade, it drives panel.get_watched_history() only; pressed with
## focus outside GoShade (in a real host scene), it must never touch
## panel.get_watched_history(), and the host scene's own Undo must never
## touch it either.
func _check_host_scene_isolation(plugin: EditorPlugin, panel: GSTMainPanel, history: UndoRedo) -> void:
	# A real user operating the host scene has already clicked into it,
	# moving GUI focus away from whatever GoShade row it last held (Godot
	# does not clear focus on its own when an ancestor becomes inactive).
	var stale_focus: Control = plugin.get_viewport().gui_get_focus_owner()
	if stale_focus != null:
		stale_focus.release_focus()
	EditorInterface.open_scene_from_path(HOST_SCENE_PATH)
	await _frames(plugin, 5)
	var host_scene: Node = plugin.get_tree().edited_scene_root
	if host_scene == null or host_scene.scene_file_path != HOST_SCENE_PATH:
		_check("host_scene_open", false, "scene=%s" % [host_scene.scene_file_path if host_scene != null else "null"])
		return
	plugin.get_undo_redo().create_action("host scene proof", UndoRedo.MERGE_DISABLE, host_scene)
	plugin.get_undo_redo().add_do_method(host_scene, &"set_meta", &"gst_native_undo_smoke_value", 1)
	plugin.get_undo_redo().add_undo_method(host_scene, &"set_meta", &"gst_native_undo_smoke_value", 0)
	plugin.get_undo_redo().commit_action()
	var host_history_before: int = plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(host_scene)).get_history_count()
	# get_history_count() is the total recorded-action array size, which an
	# undo never changes (core/object/undo_redo.cpp); the position that
	# actually moves is get_current_action() (phase 2 review round 1
	# fix pass: this comparison previously proved nothing about isolation).
	var gst_position_before: int = history.get_current_action()
	var gst_redo_available_before: bool = history.has_redo()
	_push_key(EditorInterface.get_base_control(), KEY_Z, true)
	await _frames(plugin, 3)
	var gst_unaffected_by_host_undo: bool = history.get_current_action() == gst_position_before and history.has_redo() == gst_redo_available_before
	var host_undone: bool = host_scene.get_meta(&"gst_native_undo_smoke_value", -1) == 0
	EditorInterface.open_scene_from_path("res://addons/goshade_turbo/ui/gst_main_panel.tscn")
	await _frames(plugin, 3)
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await _frames(plugin, 3)
	if not panel.get_stack().layers.is_empty():
		panel.get_stack_list().select_layer(panel.get_stack().layers[0].id)
	await _frames(plugin, 2)
	var focus: Control = panel.get_stack_list().get_node("%AddButton") as Control
	if focus != null:
		focus.grab_focus()
	await _frames(plugin, 2)
	_push_key(panel, KEY_Z, true, true)
	await _frames(plugin, 3)
	var host_unaffected_by_gst_redo: bool = host_scene.get_meta(&"gst_native_undo_smoke_value", -1) == 0
	_check("host_scene_isolation", host_history_before >= 1 and gst_unaffected_by_host_undo and host_undone and host_unaffected_by_gst_redo, "host_history=%d gst_unaffected=%s host_undone=%s host_unaffected_by_redo=%s" % [host_history_before, gst_unaffected_by_host_undo, host_undone, host_unaffected_by_gst_redo])


## Item (fix pass, round 3 item 3): the panel's own teardown (gst_main_panel.gd
## _exit_tree()) frees its standalone UndoRedo -- a plain Object with no Node
## owner to free it automatically -- rather than leaking it. Must run last:
## it destroys the real production panel every other check in this file
## drives, so nothing after this can use `panel` or `history` again. Nulls
## plugin.gd's own `_panel` field after freeing, matching what its real
## `_exit_tree()` does after its own `queue_free()` call: otherwise plugin.gd
## would call `queue_free()` again on an already-freed instance once the
## editor process actually exits below, printing a spurious freed-instance
## error that would not reflect any real defect.
func _check_teardown_destroys_history(plugin: EditorPlugin, panel: GSTMainPanel, history: UndoRedo) -> void:
	panel.queue_free()
	await _frames(plugin, 4)
	var panel_freed: bool = not is_instance_valid(panel)
	var history_freed: bool = not is_instance_valid(history)
	plugin.set("_panel", null)
	_check("teardown_destroys_history", panel_freed and history_freed, "panel_freed=%s history_freed=%s" % [panel_freed, history_freed])


## Focuses spin's own internal numeric LineEdit via a real key press rather
## than a real mouse press/release: EditorSpinSlider::gui_input calls its
## private _focus_entered() for any ui_accept-mapped key press while spin
## itself holds keyboard focus, regardless of grab state (editor/gui/
## editor_spin_slider.cpp). Key-event dispatch routes on Viewport's own
## tracked key-focus control, not a hit test against a screen position, so
## it does not depend on this environment's real OS mouse/window state the
## way a synthetic mouse press does (phase 2 review round 2 fix pass: the
## prior real-mouse non-drag-grab technique did not reliably reach a
## focused LineEdit in the reviewer's own environment). _focus_entered()
## shows and focuses the internal LineEdit through deferred calls, so this
## awaits a few frames for those to land before returning.
func _focus_spin_text(plugin: EditorPlugin, spin: EditorSpinSlider) -> LineEdit:
	spin.grab_focus()
	await plugin.get_tree().process_frame
	_push_key(spin, KEY_ENTER)
	await _frames(plugin, 3)
	return _find_focused_line_edit(spin)


## Real keyboard-driven interaction end to end: a real ui_accept key press
## opens spin's own numeric text entry (_focus_spin_text above), then real
## typed characters and a real Enter (_replace_line_edit) commit value_text.
## Returns the committed float, or null if no focused LineEdit ever
## appeared (a real, reportable failure the caller checks explicitly, not a
## sentinel silently treated as success).
func _drive_real_text_entry(plugin: EditorPlugin, spin: EditorSpinSlider, value_text: String) -> Variant:
	var line_edit: LineEdit = await _focus_spin_text(plugin, spin)
	if line_edit == null:
		return null
	await _replace_line_edit(plugin, line_edit, value_text)
	await plugin.get_tree().process_frame
	return float(value_text)


func _find_range(node: Node) -> Range:
	if node == null:
		return null
	if node is Range:
		return node as Range
	for child: Node in node.get_children():
		var found: Range = _find_range(child)
		if found != null:
			return found
	return null


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
## a real pending, unevaluated numeric entry, since EditorSpinSlider only
## evaluates typed text on its own value_focus_exited (editor/gui/
## editor_spin_slider.cpp::_evaluate_input_text).
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


func _replace_line_edit(plugin: EditorPlugin, edit: LineEdit, text: String) -> void:
	await _type_into_line_edit(plugin, edit, text)
	_push_key(edit, KEY_ENTER)
	await _frames(plugin, 2)


## Step size is large relative to EditorSpinSlider's own drag-start threshold
## (editor/gui/editor_spin_slider.cpp: 4 * grabbing_spinner_speed * EDSCALE)
## so the first motion event alone clears it regardless of this project's
## drag-speed setting or editor scale, instead of relying on cumulative
## sub-threshold steps to cross it partway through the sequence.
func _drag_spin(plugin: EditorPlugin, spin: Control, direction: float = 1.0) -> void:
	if spin == null:
		return
	var rect: Rect2 = spin.get_global_rect()
	var start: Vector2 = rect.get_center()
	_push_mouse(spin, start, MOUSE_BUTTON_LEFT, true)
	await _frames(plugin, 2)
	var position: Vector2 = start
	for step: int in range(5):
		var delta: Vector2 = Vector2(40.0 * direction, 0.0)
		position += delta
		_push_drag(spin, position, delta)
		await plugin.get_tree().process_frame
	_push_mouse(spin, position, MOUSE_BUTTON_LEFT, false)
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


## Delivered through Input.parse_input_event (the full engine input path a
## real hardware event takes) rather than target.get_viewport().push_input
## directly, per the reviewer's own suggested alternative (phase 2 review
## round 2 fix pass): push_input on a specific Viewport skips Input's own
## internal mouse-position/button-mask bookkeeping that some engine-internal
## paths read independently of the event's own fields.
func _push_mouse(target: Control, position: Vector2, button: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	event.window_id = target.get_window().get_window_id()
	Input.parse_input_event(event)


func _push_drag(target: Control, position: Vector2, relative: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.window_id = target.get_window().get_window_id()
	Input.parse_input_event(event)


func _frames(plugin: EditorPlugin, count: int) -> void:
	for i: int in range(count):
		await plugin.get_tree().process_frame


func _check(item: String, ok: bool, detail: String) -> void:
	if ok:
		_pass_count += 1
		print("SMOKE tabs_native_%s PASS %s" % [item, detail])
	else:
		_fail_count += 1
		print("SMOKE tabs_native_%s FAIL %s" % [item, detail])


func _finish(plugin: EditorPlugin) -> void:
	print("SMOKE SUMMARY pass=%d fail=%d" % [_pass_count, _fail_count])
	plugin.get_tree().quit(1 if _fail_count > 0 else 0)
