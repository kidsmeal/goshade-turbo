@tool
extends RefCounted

## Smoke selector GST_EDITOR_SMOKE=tabs_native (dispatched by
## tests/gst_editor_smoke.gd): native property-edit undo routing.
## Drives real GSTLayer/GSTCoordBlock rows in the production
## GSTInspectorColumn and asserts on panel.get_watched_history().
## Mouse-driven checks push InputEventMouse* through Input.parse_input_event
## at the row's global rect. Text-focus checks focus the row's
## EditorSpinSlider and push key events, which route on Viewport key focus
## rather than a screen-position hit test.
## Prints one "SMOKE tabs_native_<item> PASS|FAIL <detail>" line per check
## and "SMOKE SUMMARY pass=N fail=M"; exit code 1 on any failure.

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

	# Without a re-assert directly before a check, is_visible_in_tree() can
	# resolve false on an in-tree, focused EditorSpinSlider.
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
	await _reassert_main_screen(plugin)
	await _check_color_popup_subunit_edit_preserved(plugin, panel, inspector, history, stack_list)
	await _reassert_main_screen(plugin)
	await _check_color_popup_field_shortcut_single_connection(plugin, panel, inspector, history, stack_list)
	await _check_forced_finish_color_save(plugin, panel, inspector, history, stack_list)
	await _reassert_main_screen(plugin)
	await _check_forced_finish_color_save_as(plugin, panel, inspector, history, stack_list)
	await _reassert_main_screen(plugin)
	await _check_forced_finish_color_rebind(plugin, panel, inspector, history, stack_list)
	await _reassert_main_screen(plugin)
	await _check_color_popup_subunit_pending_forced_finish(plugin, panel, inspector, history, stack_list)
	await _reassert_main_screen(plugin)
	await _check_popup_focused_shortcut(plugin, panel, inspector, history, stack_list)
	await _check_host_scene_isolation(plugin, panel, history)
	await _check_teardown_destroys_history(plugin, panel, history)

	_finish(plugin)


func _reassert_main_screen(plugin: EditorPlugin) -> void:
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await _frames(plugin, 2)


## Asserts a multi-motion mouse drag on the gain EditorSpinSlider applies
## at least 2 distinct intermediate values (recorded from
## EditorProperty.property_changed) and registers exactly one action whose
## undo/redo restore the original/final values.
## Retries the drag up to 3 times; mouse capture on a freshly opened editor
## window is inconsistent in this environment.
## Does not call Input.warp_mouse: EditorSpinSlider warps the OS cursor
## during a drag, and an external warp can prevent the drag from registering.
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


## Asserts two typed-entry gestures on the same control register two
## separate actions, each undone to its own prior value.
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


## Asserts a mouse drag on the coord.offset row's x-axis EditorSpinSlider
## (EditorPropertyVectorN spin_sliders[0], which emits property_changed with
## the full merged Vector2 and field "x") applies at least 2 distinct
## intermediate values, registers one action, and preserves the y component.
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


## Asserts a text entry on the gain row (ui_accept key focuses the internal
## LineEdit, typed characters, Enter) registers exactly one action with
## correct undo/redo.
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


## Asserts a grab released with no motion and no typed value registers no
## action and leaves the stack's serialized content unchanged.
## An action-count check alone misses a live intermediate write that
## rewrote an explicit key with a value GSTUndo.values_equal reads as
## unchanged; _stack_snapshot's exact comparison catches it.
## "gain" carries an explicit params key from _check_real_text_focus's
## commit, so this exercises the existing-key case.
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


## Asserts opening and closing a color popup with no edit (about_to_popup/
## popup_closed begin/finish path) registers no action and leaves serialized
## content unchanged.
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


## Asserts a color edit whose final value is within one 1/255 step of the
## original still registers one action and is preserved;
## _gesture_values_equal's quantization tolerance must only discard a popup
## opened and closed with no edit.
## Types "7f7f7f": the nearest 8-bit neighbor below the manifest default
## Color(0.5, 0.5, 0.5, 1.0) (0x7f/255 = 0.498039). "808080" is what the
## popup already displays, and ColorPicker's hex commit skips a submitted
## string identical to the displayed one, so it would never reach
## property_changed.
## Commits with Enter, so color_changed is not routed through the column's
## forced-finish release_focus()/hide() path.
func _check_color_popup_subunit_edit_preserved(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, stack_list: GSTStackList) -> void:
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
		_check("color_popup_subunit_edit_present", false, "no ColorPickerButton row found for color/palette 'a'")
		return
	var original: Color = button.color
	var actions_before: int = history.get_history_count()
	button.grab_focus()
	button.get_popup().popup()
	await _frames(plugin, 2)
	var hex_edit: LineEdit = _find_hex_line_edit(button.get_picker())
	if hex_edit != null:
		await _replace_line_edit(plugin, hex_edit, "7f7f7f")
	if hex_edit != null and hex_edit.has_focus():
		hex_edit.release_focus()
		await _frames(plugin, 2)
	if button.get_popup().visible:
		button.get_popup().hide()
	await _frames(plugin, 3)
	var expected: Color = Color(0x7f / 255.0, 0x7f / 255.0, 0x7f / 255.0, 1.0)
	var within_one_step: bool = absf(expected.r - original.r) < (1.0 / 255.0)
	var committed_as_change: bool = history.get_history_count() == actions_before + 1
	var value_preserved: bool = palette.get(&"a") is Color and (palette.get(&"a") as Color).is_equal_approx(expected) and not (palette.get(&"a") as Color).is_equal_approx(original)
	_check("color_popup_subunit_edit_preserved", hex_edit != null and within_one_step and committed_as_change and value_preserved, "hex_found=%s within_one_step=%s original=%s expected=%s actions=%d->%d final=%s" % [hex_edit != null, within_one_step, original, expected, actions_before, history.get_history_count(), palette.get(&"a")])
	if not (committed_as_change and value_preserved):
		return
	history.undo()
	await _frames(plugin, 2)
	var undo_ok: bool = palette.get(&"a") is Color and (palette.get(&"a") as Color).is_equal_approx(original)
	history.redo()
	await _frames(plugin, 2)
	var redo_ok: bool = palette.get(&"a") is Color and (palette.get(&"a") as Color).is_equal_approx(expected)
	_check("color_popup_subunit_edit_undo_redo", undo_ok and redo_ok, "undo_ok=%s redo_ok=%s" % [undo_ok, redo_ok])


## Asserts gst_inspector_column.gd's _connect_color_popup_field_shortcuts
## (connected on every about_to_popup) leaves exactly one gui_input
## connection on the hex LineEdit after the first open and after each reopen.
## Checked after each open: a single check after the last open cannot
## distinguish one connection from the first open from one made only on the
## last.
func _check_color_popup_field_shortcut_single_connection(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, stack_list: GSTStackList) -> void:
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
		_check("color_popup_field_shortcut_single_connection", false, "no ColorPickerButton row found for color/palette 'a'")
		return
	for open_index: int in range(3):
		button.grab_focus()
		button.get_popup().popup()
		await _frames(plugin, 3)
		var hex_edit: LineEdit = _find_hex_line_edit(button.get_picker())
		var check_name: String = "color_popup_field_shortcut_single_connection_open_%d" % [open_index + 1]
		if hex_edit == null:
			_check(check_name, false, "hex LineEdit not found on open %d" % [open_index + 1])
			return
		var matching: int = 0
		for connection: Dictionary in hex_edit.gui_input.get_connections():
			var callable: Callable = connection["callable"] as Callable
			if callable.get_method() == &"_on_color_popup_field_gui_input":
				matching += 1
		_check(check_name, matching == 1, "open=%d matching_connections=%d" % [open_index + 1, matching])
		if button.get_popup().visible:
			button.get_popup().hide()
		await _frames(plugin, 2)


## Saves the open stack to `path`, reloads it, and returns every serialized
## field (stack header, layer ids, params, slots, coord) as a Dictionary
## for exact `==` comparison.
## Not a byte comparison of the saved file: ResourceSaver.save assigns a
## fresh random id suffix to each ext_resource/sub_resource on every save,
## so two saves of an unchanged stack are never byte-identical.
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


## Asserts a typed but unsubmitted numeric value (no Enter, no focus change)
## is delivered by panel._finish_pending_edits() alone, the shared boundary
## every forced-finish call site awaits.
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
	# line_edit.text is asserted directly: a typing miss leaves fbm.get("gain")
	# at its pre-edit value, which also satisfies pending_before_finish.
	var typed_text: String = line_edit.text
	var text_delivered: bool = typed_text == "0.44"
	var pending_before_finish: bool = not is_equal_approx(float(fbm.get("gain")), 0.44)
	await panel._finish_pending_edits()
	await _frames(plugin, 2)
	var one_action: bool = history.get_history_count() == actions_before + 1
	var delivered: bool = is_equal_approx(float(fbm.get("gain")), 0.44)
	_check("forced_finish_pending_text", text_delivered and pending_before_finish and one_action and delivered, "line_edit_text=%s pending_before_finish=%s actions=%d->%d value=%s" % [typed_text, pending_before_finish, actions_before, history.get_history_count(), fbm.get("gain")])
	if not delivered:
		return
	history.undo()
	await _frames(plugin, 2)
	var undo_ok: bool = is_equal_approx(float(fbm.get("gain")), original)
	history.redo()
	await _frames(plugin, 2)
	_check("forced_finish_pending_text_undo_redo", undo_ok and is_equal_approx(float(fbm.get("gain")), 0.44), "undo_ok=%s" % undo_ok)


## Asserts switching the selected layer mid-drag finishes the pending
## gesture on the original layer before the rebind.
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


## Asserts a typed but unsubmitted numeric value reaches the resource and
## the saved file before panel.save_to_path returns.
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
	# line_edit.text asserted directly; see _check_forced_finish_pending_text.
	var typed_text: String = line_edit.text
	var text_delivered: bool = typed_text == "0.28"
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
	_check("forced_finish_before_save", text_delivered and pending_before_save and reloaded != null and saved_layer != null and is_equal_approx(delivered_value, 0.28) and is_equal_approx(saved_gain, delivered_value), "line_edit_text=%s pending_before_save=%s delivered=%s saved=%s" % [typed_text, pending_before_save, delivered_value, saved_gain])
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## Asserts a typed but unsubmitted numeric value reaches the resource and
## the saved file through panel._on_save_as_file_selected, the handler the
## Save As dialog invokes.
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
	# line_edit.text asserted directly; see _check_forced_finish_pending_text.
	var typed_text: String = line_edit.text
	var text_delivered: bool = typed_text == "0.71"
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
	_check("forced_finish_before_save_as", text_delivered and pending_before_save and reloaded != null and saved_layer != null and is_equal_approx(delivered_value, 0.71) and is_equal_approx(saved_gain, delivered_value), "line_edit_text=%s pending_before_save=%s delivered=%s saved=%s" % [typed_text, pending_before_save, delivered_value, saved_gain])
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


## Asserts keyboard Undo during a drag finishes the gesture first, so the
## undo applies to the just-finished action.
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


## Asserts finishing a pending drag while a redo is queued commits a new
## action and discards the stale redo (UndoRedo::create_action semantics).
## Drives a real Ctrl+Shift+Z; no embedded subwindow is open, so the key
## reaches gst_main_panel._input() through the root viewport.
## Asserts on get_current_action(), not get_history_count(): a commit after
## an undo first discards the stale redo entry, then appends, so the array
## size can stay unchanged while the position advances.
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


## Asserts a signal emitted from a row captured before a rebind writes
## nothing to fbm and registers no action: gst_inspector_column.gd's rebuild
## erases the row's _property_rows entry synchronously, before the freed
## Nodes are destroyed.
## The signal is emitted in the same call frame as the rebind, before any
## await runs the queued frees, so the captured editor/spin are still valid
## and the rejection comes from the dictionary lookup.
func _check_stale_target_rejection(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, fbm: GSTLayer) -> void:
	var stale_property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var stale_spin: EditorSpinSlider = _find_range(stale_property) as EditorSpinSlider
	var fbm_value_before: float = float(fbm.get("gain"))
	# add_layer_by_entry_id selects the new layer (rebind) and registers its
	# own add action; history_before is captured after it.
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


## Asserts a color popup's final property_changed(changing=false) on close
## registers one action with correct undo/redo (color/palette "a").
## Drives the popup through its hex LineEdit.
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
	# Release hex focus before hiding, matching gst_inspector_column.gd's
	# _force_close_color_popups; hide only if the popup is still open.
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


## Opens the ColorPickerButton popup for property_name on layer and types
## hex_text into its hex LineEdit without submitting (no Enter).
## Returns {"ok", "button", "hex_edit"}.
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


## Asserts a pending, unsubmitted hex edit reaches the original layer
## instance and the saved file before panel.save_to_path returns.
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


## Same as _check_forced_finish_color_save, through
## panel._on_save_as_file_selected.
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


## Asserts switching the selected layer while a color popup holds a pending
## hex edit finishes it on the original layer first.
## actions_before_switch is captured after the second layer's add action, so
## + 1 measures only the color commit.
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


## Asserts a forced finish (Save, document-switch rebind, keyboard Undo)
## commits a pending hex edit within one 1/255 step of the row's current
## value instead of discarding it via _gesture_values_equal's quantization
## tolerance (gst_inspector_column.gd _flush_pending_row_text/
## _force_close_color_popups/_on_color_live_changed).
## Never submits the typed text; only the forced finish can deliver it.
func _check_color_popup_subunit_pending_forced_finish(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, history: UndoRedo, stack_list: GSTStackList) -> void:
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	var palette: GSTLayer = stack_list.add_layer_by_entry_id("color/palette")
	stack_list.select_layer(palette.id)
	panel.set_narrow_tab(1)
	await _frames(plugin, 4)

	var original_save: Color = palette.get(&"a")
	var expected_save: Color = Color(0x7f / 255.0, 0x7f / 255.0, 0x7f / 255.0, 1.0)
	var actions_before_save: int = history.get_history_count()
	var pending_save: Dictionary = await _start_pending_color_edit(plugin, inspector, palette, &"a", "7f7f7f")
	if not bool(pending_save["ok"]):
		_check("color_popup_subunit_pending_forced_finish_save", false, "pending color edit not reachable (hex_found=%s)" % [pending_save["hex_edit"] != null])
		return
	var pending_before_save: bool = not (palette.get(&"a") as Color).is_equal_approx(expected_save)
	var save_path: String = "user://gst_native_undo_smoke_subunit_forced_save.tres"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	await panel.save_to_path(save_path)
	await _frames(plugin, 2)
	var one_action_save: bool = history.get_history_count() == actions_before_save + 1
	var delivered_save: Color = palette.get(&"a")
	_check("color_popup_subunit_pending_forced_finish_save", pending_before_save and one_action_save and delivered_save.is_equal_approx(expected_save) and not delivered_save.is_equal_approx(original_save), "pending_before_save=%s actions=%d->%d delivered=%s" % [pending_before_save, actions_before_save, history.get_history_count(), delivered_save])
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	if not one_action_save:
		return

	var other: GSTLayer = stack_list.add_layer_by_entry_id("fieldops/invert")
	stack_list.select_layer(palette.id)
	await _frames(plugin, 3)
	var original_switch: Color = palette.get(&"a")
	var expected_switch: Color = Color(0x7e / 255.0, 0x7e / 255.0, 0x7e / 255.0, 1.0)
	var pending_switch: Dictionary = await _start_pending_color_edit(plugin, inspector, palette, &"a", "7e7e7e")
	if not bool(pending_switch["ok"]):
		_check("color_popup_subunit_pending_forced_finish_switch", false, "pending color edit not reachable (hex_found=%s)" % [pending_switch["hex_edit"] != null])
		return
	var actions_before_switch: int = history.get_history_count()
	stack_list.select_layer(other.id)
	await _frames(plugin, 4)
	var one_action_switch: bool = history.get_history_count() == actions_before_switch + 1
	var delivered_switch: Color = palette.get(&"a")
	_check("color_popup_subunit_pending_forced_finish_switch", one_action_switch and delivered_switch.is_equal_approx(expected_switch) and not delivered_switch.is_equal_approx(original_switch), "actions=%d->%d delivered=%s original=%s" % [actions_before_switch, history.get_history_count(), delivered_switch, original_switch])
	stack_list.select_layer(palette.id)
	await _frames(plugin, 3)
	if not one_action_switch:
		return

	var original_undo: Color = palette.get(&"a")
	var actions_before_undo: int = history.get_history_count()
	var position_before_undo: int = history.get_current_action()
	var pending_undo: Dictionary = await _start_pending_color_edit(plugin, inspector, palette, &"a", "7d7d7d")
	if not bool(pending_undo["ok"]):
		_check("color_popup_subunit_pending_forced_finish_undo", false, "pending color edit not reachable (hex_found=%s)" % [pending_undo["hex_edit"] != null])
		return
	var undo_button: ColorPickerButton = pending_undo["button"]
	var undo_hex_edit: LineEdit = pending_undo["hex_edit"]
	var undo_popup: Window = undo_button.get_popup()
	var attempts: int = 0
	while attempts < 5 and history.get_history_count() == actions_before_undo:
		attempts += 1
		if is_instance_valid(undo_hex_edit):
			undo_hex_edit.grab_focus()
		await plugin.get_tree().create_timer(0.2).timeout
		_push_popup_key(undo_popup, KEY_Z, true)
		await _frames(plugin, 4)
	var committed_then_undone: bool = history.get_history_count() == actions_before_undo + 1 and history.get_current_action() == position_before_undo
	var restored_to_original: bool = (palette.get(&"a") as Color).is_equal_approx(original_undo)
	_check("color_popup_subunit_pending_forced_finish_undo", committed_then_undone and restored_to_original, "attempts=%d actions=%d->%d position=%d->%d value=%s original=%s" % [attempts, actions_before_undo, history.get_history_count(), position_before_undo, history.get_current_action(), palette.get(&"a"), original_undo])
	if history.has_redo():
		history.redo()
		await _frames(plugin, 2)


## Asserts Ctrl+Z, delivered while a color popup holds focus with a pending
## hex edit, reaches gst_inspector_column.gd's popup window_input handler,
## commits the edit as one action, and undoes it.
## Viewport::push_input (scene/main/viewport.cpp) forwards any event to
## gui.subwindow_focused->_window_input(event) and returns before the root
## viewport's "_vp_input<id>" group (gst_main_panel among them) is notified
## while an embedded subwindow holds focus. Window::_window_input
## (scene/main/window.cpp) emits window_input before push_input() on itself,
## so the hex LineEdit cannot consume the Ctrl+Z as text-undo first.
## Window.popup() registers the window as the focused embedded subwindow
## (Viewport::_sub_window_register); no extra focus call is needed.
## The redo half reopens the popup with _start_pending_color_edit(..., "")
## (no typed characters, so about_to_popup captures original == final and
## values_equal registers no action, leaving the redo intact), then pushes
## Ctrl+Shift+Z through the popup's window_input. get_history_count()
## unchanged from before the reopen proves the position advanced by
## _apply_keyboard_undo_redo(true) calling redo(), not by a new commit.
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
	# Delivered to the popup's Window, not the root viewport: Godot 4.6.2/4.7
	# (unlike 4.4) drop a root-viewport push while a native, non-embedded
	# popup holds focus. Window extends Viewport, so push_input() is the same
	# call when the popup is embedded (single_window_mode).
	var popup: Window = button.get_popup()
	var attempts: int = 0
	# Loops on get_history_count(), not get_current_action(): commit then undo
	# nets the position back to position_before, and a second Ctrl+Z would
	# undo the preceding action. The array size grows only on a commit.
	while attempts < 5 and history.get_history_count() == actions_before:
		attempts += 1
		if is_instance_valid(hex_edit):
			hex_edit.grab_focus()
		await plugin.get_tree().create_timer(0.2).timeout
		_push_popup_key(popup, KEY_Z, true)
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
	var redo_popup: Window = redo_button.get_popup()
	var redo_attempts: int = 0
	# A redo advances the position, so this loops on get_current_action().
	while redo_attempts < 5 and history.get_current_action() == position_before:
		redo_attempts += 1
		if is_instance_valid(redo_hex_edit):
			redo_hex_edit.grab_focus()
		await plugin.get_tree().create_timer(0.2).timeout
		_push_popup_key(redo_popup, KEY_Z, true, true)
		await _frames(plugin, 4)
	var redo_landed: bool = history.get_current_action() == position_before + 1 and history.get_history_count() == redo_history_count_before
	var redo_value_ok: bool = palette.get(&"a") is Color and (palette.get(&"a") as Color).is_equal_approx(final_color)
	var redo_popup_closed: bool = is_instance_valid(redo_button) and not redo_button.get_popup().visible
	_check("popup_focused_shortcut_redo", redo_pending_before and redo_landed and redo_value_ok and redo_popup_closed, "attempts=%d redo_pending_before=%s position=%d->%d history_count=%d->%d color=%s popup_visible=%s" % [redo_attempts, redo_pending_before, position_before, history.get_current_action(), redo_history_count_before, history.get_history_count(), palette.get(&"a"), is_instance_valid(redo_button) and redo_button.get_popup().visible])


## Asserts undoing an edit to a property with no prior explicit params key
## restores the manifest default and removes the params key entirely: the
## dirty fingerprint includes serialized params keys, so an explicit entry
## equal to the default would change it.
## Also asserts a no-op gesture returning to the absent-backed original
## restores the absence even though the live intermediate write created an
## explicit key.
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


## Asserts keyboard Undo/Redo is scoped to GoShade focus: with focus in a
## host scene, neither the host scene's Undo nor GoShade's Redo touches the
## other's history.
func _check_host_scene_isolation(plugin: EditorPlugin, panel: GSTMainPanel, history: UndoRedo) -> void:
	# Godot does not clear GUI focus when an ancestor becomes inactive;
	# release the GoShade row's focus before opening the host scene.
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
	# get_history_count() is the recorded-action array size, which an undo
	# never changes (core/object/undo_redo.cpp); get_current_action() moves.
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


## Asserts gst_main_panel.gd _exit_tree() frees its standalone UndoRedo (a
## plain Object with no Node owner).
## Must run last: it frees the production panel. Nulls plugin.gd's `_panel`
## after freeing, as its _exit_tree() does after queue_free(); otherwise
## plugin.gd calls queue_free() on a freed instance at editor exit.
func _check_teardown_destroys_history(plugin: EditorPlugin, panel: GSTMainPanel, history: UndoRedo) -> void:
	panel.queue_free()
	await _frames(plugin, 4)
	var panel_freed: bool = not is_instance_valid(panel)
	var history_freed: bool = not is_instance_valid(history)
	plugin.set("_panel", null)
	_check("teardown_destroys_history", panel_freed and history_freed, "panel_freed=%s history_freed=%s" % [panel_freed, history_freed])


## Focuses spin's internal numeric LineEdit via a key press:
## EditorSpinSlider::gui_input calls _focus_entered() for any ui_accept key
## while spin holds keyboard focus, regardless of grab state
## (editor/gui/editor_spin_slider.cpp). Key dispatch routes on the
## Viewport's key-focus control, not a screen-position hit test.
## _focus_entered() shows and focuses the LineEdit through deferred calls,
## so this awaits frames before returning.
func _focus_spin_text(plugin: EditorPlugin, spin: EditorSpinSlider) -> LineEdit:
	spin.grab_focus()
	await plugin.get_tree().process_frame
	_push_key(spin, KEY_ENTER)
	await _frames(plugin, 3)
	return _find_focused_line_edit(spin)


## ui_accept key press (_focus_spin_text), typed characters, Enter
## (_replace_line_edit). Returns the committed float, or null if no focused
## LineEdit appeared.
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


## Types text into edit without submitting (no Enter, no focus change).
## EditorSpinSlider evaluates typed text only on value_focus_exited
## (editor/gui/editor_spin_slider.cpp::_evaluate_input_text).
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


## Step size exceeds EditorSpinSlider's drag-start threshold
## (editor/gui/editor_spin_slider.cpp: 4 * grabbing_spinner_speed * EDSCALE)
## so the first motion event clears it regardless of drag-speed setting or
## editor scale.
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


## Delivers a key event to a color popup's own Window instead of the root
## viewport (_push_key), matching OS routing to the focused window. Window
## extends Viewport, so push_input() reaches
## gst_inspector_column.gd's _on_color_popup_window_input.
func _push_popup_key(popup: Window, keycode: Key, ctrl: bool = false, shift: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.window_id = popup.get_window_id()
	popup.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	popup.push_input(event, true)


## Delivered through Input.parse_input_event rather than
## target.get_viewport().push_input: push_input on a Viewport skips Input's
## mouse-position/button-mask bookkeeping that engine paths read
## independently of the event's fields.
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
