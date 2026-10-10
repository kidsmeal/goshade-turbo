@tool
extends RefCounted

## Layer menu Duplicate, Rename and Bypass (decisions 24, 25, 26), driven
## through %LayerMenu's id_pressed and the stack list's inline rename edit.
## Each edit registers one history entry and undoes to the prior state; a
## refused bypass registers none and shows its reason in the refusal label.
## The row screenshot comes from tests/capture_layer_rows.gd.

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
	panel.get_create_empty_button().pressed.emit()
	await plugin.get_tree().process_frame
	panel.get_picker().cancelled.emit()
	await plugin.get_tree().process_frame
	var stack_list: GSTStackList = panel.get_stack_list()

	var fbm: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	var invert: GSTLayer = stack_list.add_layer_by_entry_id("fieldops/invert")
	var hash_layer: GSTLayer = stack_list.add_layer_by_entry_id("generative/hash")
	await plugin.get_tree().process_frame
	_check("setup", fbm != null and invert != null and hash_layer != null and invert.slots.get("x", &"") == fbm.id, "fbm=%s invert=%s hash=%s" % [fbm, invert, hash_layer])

	await _run_duplicate(plugin, panel, invert)
	await _run_rename(plugin, panel, fbm)
	await _run_rename_cancel(plugin, panel, invert)
	await _run_bypass(plugin, panel, invert)
	await _run_bypass_refused(plugin, panel, hash_layer)
	_finish(plugin)


## Duplicate inserts the copy directly above with label "<function> copy";
## undo removes it, redo reinserts the same instance.
func _run_duplicate(plugin: EditorPlugin, panel: GSTMainPanel, invert: GSTLayer) -> void:
	var stack: GSTStack = panel.get_stack()
	var stack_list: GSTStackList = panel.get_stack_list()
	var history: UndoRedo = panel.get_watched_history()
	stack_list.select_layer(invert.id)
	await plugin.get_tree().process_frame
	var count: int = history.get_history_count()
	var layer_count: int = stack.layers.size()
	_press_layer_menu(panel, GSTMainPanel.LAYER_DUPLICATE)
	await plugin.get_tree().process_frame
	var invert_index: int = GSTStackOps.find_index(stack, invert.id)
	var copy: GSTLayer = stack.layers[invert_index + 1] if invert_index + 1 < stack.layers.size() else null
	var row: String = stack_list.get_row_text(copy.id) if copy != null else ""
	var ok: bool = copy != null and copy.entry == invert.entry and copy.label == "invert copy" and copy.slots.get("x", &"") == invert.slots.get("x", &"") and row == "l%s  invert copy invert (field)" % String(copy.id)
	_check("duplicate", ok and stack.layers.size() == layer_count + 1 and history.get_history_count() == count + 1 and stack_list.get_selected_layer_id() == copy.id, "label='%s' row='%s' layers=%d->%d history=%d->%d" % [copy.label if copy != null else "null", row, layer_count, stack.layers.size(), count, history.get_history_count()])
	if copy == null:
		return

	history.undo()
	await plugin.get_tree().process_frame
	_check("duplicate_undo", GSTStackOps.find_layer(stack, copy.id) == null and stack.layers.size() == layer_count and stack_list.get_row_text(copy.id).is_empty(), "copy_gone=%s layers=%d" % [GSTStackOps.find_layer(stack, copy.id) == null, stack.layers.size()])
	history.redo()
	await plugin.get_tree().process_frame
	var restored: GSTLayer = GSTStackOps.find_layer(stack, copy.id)
	_check("duplicate_redo", is_same(restored, copy) and GSTStackOps.find_index(stack, copy.id) == GSTStackOps.find_index(stack, invert.id) + 1, "same_instance=%s index=%d" % [is_same(restored, copy), GSTStackOps.find_index(stack, copy.id)])


## Rename through the inline edit: enter commits, the row reads
## "<label> <function>", undo restores the empty label. An empty label commits
## and shows the function name alone.
func _run_rename(plugin: EditorPlugin, panel: GSTMainPanel, fbm: GSTLayer) -> void:
	var stack_list: GSTStackList = panel.get_stack_list()
	var history: UndoRedo = panel.get_watched_history()
	var edit: LineEdit = stack_list.get_rename_edit()
	stack_list.select_layer(fbm.id)
	await plugin.get_tree().process_frame
	var count: int = history.get_history_count()
	_press_layer_menu(panel, GSTMainPanel.LAYER_RENAME)
	await plugin.get_tree().process_frame
	var opened: bool = edit.visible and edit.has_focus() and edit.text.is_empty() and edit.placeholder_text == "fbm"
	edit.text = "base"
	edit.text_submitted.emit(edit.text)
	await plugin.get_tree().process_frame
	var row: String = stack_list.get_row_text(fbm.id)
	_check("rename", opened and not edit.visible and fbm.label == "base" and row == "l%s  base fbm (field)" % String(fbm.id) and history.get_history_count() == count + 1, "opened=%s label='%s' row='%s' history=%d->%d" % [opened, fbm.label, row, count, history.get_history_count()])

	history.undo()
	await plugin.get_tree().process_frame
	row = stack_list.get_row_text(fbm.id)
	_check("rename_undo", fbm.label.is_empty() and row == "l%s  fbm (field)" % String(fbm.id), "label='%s' row='%s'" % [fbm.label, row])
	history.redo()
	await plugin.get_tree().process_frame
	_check("rename_redo", fbm.label == "base", "label='%s'" % fbm.label)

	stack_list.begin_rename(fbm.id)
	await plugin.get_tree().process_frame
	count = history.get_history_count()
	edit.text = ""
	edit.text_submitted.emit(edit.text)
	await plugin.get_tree().process_frame
	row = stack_list.get_row_text(fbm.id)
	_check("rename_empty", fbm.label.is_empty() and row == "l%s  fbm (field)" % String(fbm.id) and history.get_history_count() == count + 1, "label='%s' row='%s' history=%d->%d" % [fbm.label, row, count, history.get_history_count()])
	history.undo()
	await plugin.get_tree().process_frame
	_check("rename_empty_undo", fbm.label == "base", "label='%s'" % fbm.label)


## Escape closes the edit without writing the label or a history entry.
func _run_rename_cancel(plugin: EditorPlugin, panel: GSTMainPanel, invert: GSTLayer) -> void:
	var stack_list: GSTStackList = panel.get_stack_list()
	var history: UndoRedo = panel.get_watched_history()
	var edit: LineEdit = stack_list.get_rename_edit()
	stack_list.select_layer(invert.id)
	await plugin.get_tree().process_frame
	var count: int = history.get_history_count()
	_press_layer_menu(panel, GSTMainPanel.LAYER_RENAME)
	await plugin.get_tree().process_frame
	edit.text = "discarded"
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	edit.gui_input.emit(escape)
	await plugin.get_tree().process_frame
	_check("rename_escape", not edit.visible and invert.label.is_empty() and history.get_history_count() == count, "visible=%s label='%s' history=%d->%d" % [edit.visible, invert.label, count, history.get_history_count()])


## Bypass on an operator toggles the row suffix, the checked item and the
## shader text; undo restores all three.
func _run_bypass(plugin: EditorPlugin, panel: GSTMainPanel, invert: GSTLayer) -> void:
	var stack_list: GSTStackList = panel.get_stack_list()
	var history: UndoRedo = panel.get_watched_history()
	stack_list.select_layer(invert.id)
	await plugin.get_tree().process_frame
	# The rename_empty undo left one redo entry; this commit truncates it, so
	# the history count stays flat and the current action index moves by one.
	var action: int = history.get_current_action()
	var code_before: String = panel.get_shader_material().shader.code
	_press_layer_menu(panel, GSTMainPanel.LAYER_BYPASS)
	await plugin.get_tree().process_frame
	var row: String = stack_list.get_row_text(invert.id)
	var code_changed: bool = panel.get_shader_material().shader.code != code_before
	_check("bypass", not invert.enabled and row == "l%s  invert (field)%s" % [String(invert.id), GSTStackList.BYPASSED_SUFFIX] and _bypass_checked(panel) and code_changed and history.get_current_action() == action + 1 and not history.has_redo(), "enabled=%s row='%s' checked=%s code_changed=%s current_action=%d->%d has_redo=%s" % [invert.enabled, row, _bypass_checked(panel), code_changed, action, history.get_current_action(), history.has_redo()])

	history.undo()
	await plugin.get_tree().process_frame
	row = stack_list.get_row_text(invert.id)
	_check("bypass_undo", invert.enabled and row == "l%s  invert (field)" % String(invert.id) and not _bypass_checked(panel) and panel.get_shader_material().shader.code == code_before, "enabled=%s row='%s' checked=%s" % [invert.enabled, row, _bypass_checked(panel)])
	history.redo()
	await plugin.get_tree().process_frame
	_check("bypass_redo", not invert.enabled and stack_list.get_row_text(invert.id).ends_with(GSTStackList.BYPASSED_SUFFIX), "row='%s'" % stack_list.get_row_text(invert.id))


## generative/hash is a generator: bypass is refused, the item stays
## unchecked, the reason shows in the refusal label, and no entry registers.
func _run_bypass_refused(plugin: EditorPlugin, panel: GSTMainPanel, hash_layer: GSTLayer) -> void:
	var stack_list: GSTStackList = panel.get_stack_list()
	var history: UndoRedo = panel.get_watched_history()
	stack_list.select_layer(hash_layer.id)
	await plugin.get_tree().process_frame
	var count: int = history.get_history_count()
	var action: int = history.get_current_action()
	var expected: String = String(GSTStackOps.can_bypass(panel.get_stack(), hash_layer.id, panel.get_library())["reason"])
	_press_layer_menu(panel, GSTMainPanel.LAYER_BYPASS)
	await plugin.get_tree().process_frame
	var label: Label = stack_list.get_refusal_label()
	var row: String = stack_list.get_row_text(hash_layer.id)
	_check("bypass_refused", hash_layer.enabled and not expected.is_empty() and label.visible and label.text == expected and not _bypass_checked(panel) and not row.ends_with(GSTStackList.BYPASSED_SUFFIX) and history.get_history_count() == count and history.get_current_action() == action, "enabled=%s refusal='%s' expected='%s' checked=%s history=%d->%d current_action=%d->%d" % [hash_layer.enabled, label.text, expected, _bypass_checked(panel), count, history.get_history_count(), action, history.get_current_action()])


func _press_layer_menu(panel: GSTMainPanel, id: int) -> void:
	panel.get_layer_menu().get_popup().id_pressed.emit(id)


func _bypass_checked(panel: GSTMainPanel) -> bool:
	var popup: PopupMenu = panel.get_layer_menu().get_popup()
	return popup.is_item_checked(popup.get_item_index(GSTMainPanel.LAYER_BYPASS))


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
