@tool
extends RefCounted

## GST_EDITOR_SMOKE=tabs_host. Multi-document host-scene isolation: structural
## and native edits on two documents, a real scene switch away from and back
## to GoShade, Save As bound to the document that opened the dialog, and
## alternating focused Undo/Redo including a native color popup's keyboard
## boundary, with the second document as a negative control.
## tests/gst_editor_native_undo_smoke.gd's _check_host_scene_isolation covers
## the single-document case.
##
## Save As is driven through _on_save_as_pressed()/_on_save_as_file_selected
## so the request captures the document active when the dialog opens.

var _pass_count: int = 0
var _fail_count: int = 0

const HOST_SCENE_PATH: String = "res://tests/fixtures/shader_tabs_host.tscn"
const GOSHADE_MAIN_SCENE_PATH: String = "res://addons/goshade_turbo/ui/gst_main_panel.tscn"
const SAVE_AS_PATH: String = "user://gst_tabs_host_smoke_save_as.tres"


func run(plugin: EditorPlugin) -> void:
	for i: int in range(5):
		await plugin.get_tree().process_frame
	var panel: GSTMainPanel = plugin.get_panel() as GSTMainPanel
	_check("panel", panel != null, "panel present=%s" % [panel != null])
	if panel == null:
		_finish(plugin)
		return

	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await _frames(plugin, 3)
	if panel.is_start_screen_visible():
		panel.get_create_empty_button().pressed.emit()
		await plugin.get_tree().process_frame
		panel.get_picker().cancelled.emit()
		await plugin.get_tree().process_frame

	_cleanup([SAVE_AS_PATH])

	var docs: Dictionary = await _setup_two_documents(plugin, panel)
	if docs.is_empty():
		_finish(plugin)
		return
	var doc_a: GSTDocument = docs["a"]
	var doc_b: GSTDocument = docs["b"]

	var host_scene: Node = await _run_scene_switch_and_host_undo(plugin, panel, doc_a, doc_b)
	await _run_return_to_goshade(plugin, panel, doc_a, doc_b)
	await _run_save_as_on_initiating_document(plugin, panel, doc_a, doc_b)
	await _run_alternating_undo_redo_with_popup(plugin, panel, doc_a, doc_b)

	if host_scene != null and is_instance_valid(host_scene):
		EditorInterface.open_scene_from_path(GOSHADE_MAIN_SCENE_PATH)
		await _frames(plugin, 2)
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await _frames(plugin, 2)
	_cleanup([SAVE_AS_PATH])
	_finish(plugin)


## doc_a: a recipe, untouched from here on as the negative control. doc_b: a
## fresh document dirtied by one structural edit (add_layer) and one native
## property edit (EditorProperty.emit_changed) before the scene switch.
func _setup_two_documents(plugin: EditorPlugin, panel: GSTMainPanel) -> Dictionary:
	await panel.open_recipe("glow")
	await _frames(plugin, 2)
	var doc_a: GSTDocument = panel.get_active_document()
	if doc_a == null:
		_check("setup_two_documents", false, "open_recipe('glow') produced no active document")
		return {}

	var doc_b: GSTDocument = await panel.open_document(GSTStack.new(), "", false)
	await _frames(plugin, 2)
	panel.get_undo().add_layer("generative/fbm", GSTLayer.Kind.FIELD, true)
	await _frames(plugin, 2)
	var fbm: GSTLayer = doc_b.stack.layers[doc_b.stack.layers.size() - 1]
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	inspector.edit(fbm.id)
	var gain_property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var original_gain: float = float(fbm.get("gain"))
	if gain_property != null:
		gain_property.emit_changed(&"gain", original_gain + 0.1)
		await _frames(plugin, 2)

	var distinct: bool = doc_a != doc_b and doc_a.session_id != doc_b.session_id
	var both_dirty: bool = doc_a.is_dirty() and doc_b.is_dirty()
	var native_edit_applied: bool = gain_property != null and is_equal_approx(float(fbm.get("gain")), original_gain + 0.1)
	_check("setup_two_documents", distinct and both_dirty and native_edit_applied, "distinct=%s doc_a_dirty=%s doc_b_dirty=%s native_edit_applied=%s" % [distinct, doc_a.is_dirty(), doc_b.is_dirty(), native_edit_applied])
	if not (distinct and both_dirty):
		return {}
	return {"a": doc_a, "b": doc_b}


## Opens the host scene, asserts the tab row hides with GoShade, then commits
## an editor action on the host scene and presses Ctrl+Z with focus in that
## scene. Asserts the scene undo touches neither document's UndoRedo.
func _run_scene_switch_and_host_undo(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument, doc_b: GSTDocument) -> Node:
	var a_layers_before: int = doc_a.stack.layers.size()
	var b_layers_before: int = doc_b.stack.layers.size()
	var a_position_before: int = doc_a.undo_redo.get_current_action()
	var b_position_before: int = doc_b.undo_redo.get_current_action()

	var stale_focus: Control = plugin.get_viewport().gui_get_focus_owner()
	if stale_focus != null:
		stale_focus.release_focus()
	EditorInterface.open_scene_from_path(HOST_SCENE_PATH)
	await _frames(plugin, 5)
	var host_scene: Node = plugin.get_tree().edited_scene_root
	var scene_opened: bool = host_scene != null and host_scene.scene_file_path == HOST_SCENE_PATH
	var stacks_unchanged_after_switch: bool = doc_a.stack.layers.size() == a_layers_before and doc_b.stack.layers.size() == b_layers_before
	# open_scene_from_path does not reliably switch the main screen away from
	# GoShade (the 2D/3D auto-switch depends on the scene root type). Panel
	# visibility is driven only by plugin.gd's _make_visible, so force the
	# main-screen switch directly.
	EditorInterface.set_main_screen_editor("Script")
	await _frames(plugin, 3)
	var tab_row_hidden: bool = not panel.visible
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await _frames(plugin, 2)
	var tab_row_shown_again: bool = panel.visible
	_check("scene_switch_preserves_documents", scene_opened and tab_row_hidden and tab_row_shown_again and stacks_unchanged_after_switch, "scene_opened=%s tab_row_hidden=%s tab_row_shown_again=%s stacks_unchanged=%s" % [scene_opened, tab_row_hidden, tab_row_shown_again, stacks_unchanged_after_switch])
	if not scene_opened:
		return null

	plugin.get_undo_redo().create_action("tabs_host smoke: host scene edit", UndoRedo.MERGE_DISABLE, host_scene)
	plugin.get_undo_redo().add_do_method(host_scene, &"set_meta", &"gst_tabs_host_smoke_value", 1)
	plugin.get_undo_redo().add_undo_method(host_scene, &"set_meta", &"gst_tabs_host_smoke_value", 0)
	plugin.get_undo_redo().commit_action()
	await _frames(plugin, 2)
	var host_set: bool = int(host_scene.get_meta(&"gst_tabs_host_smoke_value", -1)) == 1

	_push_key(EditorInterface.get_base_control(), KEY_Z, true)
	await _frames(plugin, 3)
	var host_undone: bool = int(host_scene.get_meta(&"gst_tabs_host_smoke_value", -1)) == 0
	var a_untouched: bool = doc_a.undo_redo.get_current_action() == a_position_before and doc_a.stack.layers.size() == a_layers_before
	var b_untouched: bool = doc_b.undo_redo.get_current_action() == b_position_before and doc_b.stack.layers.size() == b_layers_before
	_check("scene_undo_outside_goshade", host_set and host_undone and a_untouched and b_untouched, "host_set=%s host_undone=%s doc_a_untouched=%s doc_b_untouched=%s" % [host_set, host_undone, a_untouched, b_untouched])
	return host_scene


## Ctrl+Shift+Z with focus in the host scene restores the host-scene meta and
## touches neither document. Then switches back to GoShade and asserts both
## documents are still open and the tab row is visible.
func _run_return_to_goshade(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument, doc_b: GSTDocument) -> void:
	var host_scene: Node = plugin.get_tree().edited_scene_root
	var a_position_before: int = doc_a.undo_redo.get_current_action()
	var b_position_before: int = doc_b.undo_redo.get_current_action()
	if host_scene != null and host_scene.scene_file_path == HOST_SCENE_PATH:
		_push_key(EditorInterface.get_base_control(), KEY_Z, true, true)
		await _frames(plugin, 3)
	var host_redone: bool = host_scene != null and int(host_scene.get_meta(&"gst_tabs_host_smoke_value", -1)) == 1
	var docs_untouched_by_host_redo: bool = doc_a.undo_redo.get_current_action() == a_position_before and doc_b.undo_redo.get_current_action() == b_position_before

	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await _frames(plugin, 4)
	var tab_row_visible: bool = panel.visible
	var still_both_open: bool = panel.get_documents().has(doc_a) and panel.get_documents().has(doc_b)
	_check("return_to_goshade_preserves_state", host_redone and docs_untouched_by_host_redo and tab_row_visible and still_both_open, "host_redone=%s docs_untouched=%s tab_row_visible=%s still_both_open=%s" % [host_redone, docs_untouched_by_host_redo, tab_row_visible, still_both_open])


## Save As through the dialog handler pair must land on doc_b (active when
## the dialog opened) and leave doc_a's path and dirty state unchanged.
func _run_save_as_on_initiating_document(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument, doc_b: GSTDocument) -> void:
	panel.activate_document(doc_b)
	await _frames(plugin, 2)
	var a_path_before: String = doc_a.current_path
	var a_dirty_before: bool = doc_a.is_dirty()
	var b_expected_fingerprint: String = GSTDocument.compute_fingerprint(doc_b.stack)

	panel._on_save_as_pressed()
	panel._on_save_as_file_selected(SAVE_AS_PATH)
	# The direct handler call bypasses the dialog's file_selected auto-hide.
	# A visible EditorFileDialog absorbs input before gst_main_panel's
	# _input(), so the next check's Ctrl+Z/Ctrl+Shift+Z would reach nothing.
	panel._save_as_dialog.hide()
	await _frames(plugin, 2)

	var b_saved: bool = doc_b.current_path == SAVE_AS_PATH and not doc_b.is_dirty()
	var loaded: Dictionary = GSTStackIO.load(SAVE_AS_PATH, panel.get_library())
	var content_matches: bool = bool(loaded.get("ok", false)) and GSTDocument.compute_fingerprint(loaded["stack"]) == b_expected_fingerprint
	var a_unaffected: bool = doc_a.current_path == a_path_before and doc_a.is_dirty() == a_dirty_before
	_check("save_as_on_initiating_document", b_saved and content_matches and a_unaffected, "b_saved=%s content_matches=%s doc_a_unaffected=%s doc_a_path='%s'" % [b_saved, content_matches, a_unaffected, doc_a.current_path])


## Focused Ctrl+Z/Ctrl+Shift+Z on doc_b's native property row, then a second
## edit finished through the native RGB popup's keyboard boundary
## (gst_inspector_column.gd color_popup_undo_redo_requested), with doc_a open
## as a sibling tab. A cross-document leak shows as doc_a's history position
## or layer count moving.
## Keyboard events are delivered, not doc_b.undo_redo.undo()/redo() or
## inspector.finish_pending_edits(). The numeric half focuses the row's
## EditorSpinSlider and pushes keys at the root viewport. The popup half
## pushes keys at the popup's own Window (_push_popup_key): a focused native
## popup does not reliably receive a root-viewport delivery.
func _run_alternating_undo_redo_with_popup(plugin: EditorPlugin, panel: GSTMainPanel, doc_a: GSTDocument, doc_b: GSTDocument) -> void:
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var a_layers_snapshot: int = doc_a.stack.layers.size()
	var a_position_snapshot: int = doc_a.undo_redo.get_current_action()

	var fbm: GSTLayer = doc_b.stack.layers[0]
	inspector.edit(fbm.id)
	# The row's EditorSpinSlider is visible_in_tree only while the "Layer
	# settings" narrow tab is selected; grab_focus() and keyboard delivery
	# need that.
	panel.set_narrow_tab(1)
	await _frames(plugin, 3)
	var gain_property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	var gain_spin: EditorSpinSlider = _find_range(gain_property) as EditorSpinSlider
	var original_gain: float = float(fbm.get("gain"))
	var dragged_gain: float = original_gain + 0.2
	# commit_property_change registers the action without re-executing the do
	# method (gst_undo.gd), so the mutation must be applied before the call.
	fbm.set(&"gain", dragged_gain)
	panel.get_undo().commit_property_change(fbm, &"gain", original_gain, dragged_gain)
	await _frames(plugin, 2)
	var changed: bool = is_equal_approx(float(fbm.get("gain")), dragged_gain)

	var position_after_drag: int = doc_b.undo_redo.get_current_action()
	var undo_attempts: int = 0
	while gain_spin != null and undo_attempts < 5 and doc_b.undo_redo.get_current_action() == position_after_drag:
		undo_attempts += 1
		EditorInterface.set_main_screen_editor("GoShade Turbo")
		gain_spin.grab_focus()
		await plugin.get_tree().create_timer(0.2).timeout
		_push_key(EditorInterface.get_base_control(), KEY_Z, true)
		await _frames(plugin, 3)
	var undone: bool = is_equal_approx(float(fbm.get("gain")), original_gain)

	var position_after_undo: int = doc_b.undo_redo.get_current_action()
	var redo_attempts: int = 0
	while gain_spin != null and redo_attempts < 5 and doc_b.undo_redo.get_current_action() == position_after_undo:
		redo_attempts += 1
		EditorInterface.set_main_screen_editor("GoShade Turbo")
		gain_spin.grab_focus()
		await plugin.get_tree().create_timer(0.2).timeout
		_push_key(EditorInterface.get_base_control(), KEY_Z, true, true)
		await _frames(plugin, 3)
	var redone: bool = is_equal_approx(float(fbm.get("gain")), dragged_gain)
	var doc_a_untouched_by_alternation: bool = doc_a.stack.layers.size() == a_layers_snapshot and doc_a.undo_redo.get_current_action() == a_position_snapshot
	_check("alternating_focused_undo_redo", gain_spin != null and changed and undone and redone and doc_a_untouched_by_alternation, "changed=%s undone=%s redone=%s doc_a_untouched=%s undo_attempts=%d redo_attempts=%d" % [changed, undone, redone, doc_a_untouched_by_alternation, undo_attempts, redo_attempts])

	var palette: GSTLayer = panel.get_undo().add_layer("color/palette", GSTLayer.Kind.COLOR, false)
	await _frames(plugin, 2)
	inspector.edit(palette.id)
	# The settings tab must be the selected _editing_tabs page before a
	# popup/focus interaction with a property row.
	panel.set_narrow_tab(1)
	await _frames(plugin, 2)
	var actions_before_popup: int = doc_b.undo_redo.get_history_count()
	var position_before_popup: int = doc_b.undo_redo.get_current_action()
	var original_palette_color: Color = palette.get(&"a")
	var pending: Dictionary = await _start_pending_color_edit(plugin, inspector, palette, &"a", "223344")
	if not bool(pending.get("ok", false)):
		_check("popup_focused_undo_in_tabs", false, "pending color edit not reachable (hex_found=%s)" % [pending.get("hex_edit", null) != null])
		return
	var button: ColorPickerButton = pending["button"]
	var hex_edit: LineEdit = pending["hex_edit"]
	var popup: Window = button.get_popup()
	# Loops on get_history_count(), not get_current_action(): commit then
	# undo nets back to position_before_popup, indistinguishable from no
	# activity by position alone.
	var popup_attempts: int = 0
	while popup_attempts < 5 and doc_b.undo_redo.get_history_count() == actions_before_popup:
		popup_attempts += 1
		if is_instance_valid(hex_edit):
			hex_edit.grab_focus()
		await plugin.get_tree().create_timer(0.2).timeout
		_push_popup_key(popup, KEY_Z, true)
		await _frames(plugin, 4)
	var committed_then_undone: bool = doc_b.undo_redo.get_history_count() == actions_before_popup + 1 and doc_b.undo_redo.get_current_action() == position_before_popup
	var popup_closed: bool = is_instance_valid(button) and not button.get_popup().visible
	var popup_undone: bool = palette.get(&"a") is Color and (palette.get(&"a") as Color).is_equal_approx(original_palette_color)
	var doc_a_untouched_by_popup: bool = doc_a.stack.layers.size() == a_layers_snapshot and doc_a.undo_redo.get_current_action() == a_position_snapshot
	_check("popup_focused_undo_in_tabs", committed_then_undone and popup_closed and popup_undone and doc_a_untouched_by_popup, "attempts=%d committed_then_undone=%s popup_closed=%s popup_undone=%s doc_a_untouched=%s color=%s" % [popup_attempts, committed_then_undone, popup_closed, popup_undone, doc_a_untouched_by_popup, palette.get(&"a")])


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


## Delivers a key event to a native color popup's own Window instead of the
## root viewport. Window extends Viewport, so push_input() works for both a
## non-embedded popup subwindow and an embedded one (single_window_mode).
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


func _frames(plugin: EditorPlugin, count: int) -> void:
	for i: int in range(count):
		await plugin.get_tree().process_frame


func _cleanup(paths: Array[String]) -> void:
	for path: String in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(item: String, ok: bool, detail: String) -> void:
	if ok:
		_pass_count += 1
		print("SMOKE tabs_host_%s PASS %s" % [item, detail])
	else:
		_fail_count += 1
		print("SMOKE tabs_host_%s FAIL %s" % [item, detail])


func _finish(plugin: EditorPlugin) -> void:
	print("SMOKE SUMMARY pass=%d fail=%d" % [_pass_count, _fail_count])
	plugin.get_tree().quit(1 if _fail_count > 0 else 0)
