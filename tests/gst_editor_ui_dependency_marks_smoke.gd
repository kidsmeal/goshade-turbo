@tool
extends RefCounted

## Dependency marks (decision 35) in the stack list. Stack, bottom to top:
## generative/fbm, fieldops/invert (slot x from that fbm), generative/fbm
## labeled "mid" (warp_x from invert), generative/fbm (gain linked to mid).
## Selecting mid marks invert with "  feeds: mid" and the top fbm with
## "  reads: mid", both in the editor accent color; the bottom fbm sits two
## edges away and carries no mark. Selection registers no history entry.

const MID_LABEL: String = "mid"

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
	var undo: GSTUndo = panel.get_undo()

	var bottom: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	var invert: GSTLayer = stack_list.add_layer_by_entry_id("fieldops/invert")
	var mid: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	var top: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	var setup_ok: bool = bottom != null and invert != null and mid != null and top != null
	if setup_ok:
		var slot_ok: bool = invert.slots.get("x", &"") == bottom.id
		var warp_ok: bool = undo.assign_warp(mid.id, "x", invert.id)["ok"]
		var link_ok: bool = undo.set_param_link(top.id, "gain", mid.id)["ok"]
		var label_ok: bool = undo.rename_layer(mid.id, MID_LABEL)["ok"]
		setup_ok = slot_ok and warp_ok and link_ok and label_ok
	await plugin.get_tree().process_frame
	_check("setup", setup_ok, "bottom=%s invert=%s mid=%s top=%s" % [bottom, invert, mid, top])
	if not setup_ok:
		_finish(plugin)
		return

	await _run_select_middle(plugin, panel, bottom, invert, mid, top)
	await _run_select_top(plugin, panel, invert, mid, top)
	await _run_bypassed_keeps_mark(plugin, panel, invert, mid)
	_finish(plugin)


## Selecting mid: invert feeds it, top reads it, both tinted; bottom and mid
## itself unmarked; history count unchanged.
func _run_select_middle(plugin: EditorPlugin, panel: GSTMainPanel, bottom: GSTLayer, invert: GSTLayer, mid: GSTLayer, top: GSTLayer) -> void:
	var stack_list: GSTStackList = panel.get_stack_list()
	var history: UndoRedo = panel.get_watched_history()
	var count: int = history.get_history_count()
	var action: int = history.get_current_action()
	await _select(plugin, stack_list, mid)
	var accent: Color = EditorInterface.get_editor_theme().get_color(&"accent_color", &"Editor")
	var invert_row: String = stack_list.get_row_text(invert.id)
	var top_row: String = stack_list.get_row_text(top.id)
	_check("feeds_mark", invert_row.ends_with(GSTStackList.FEEDS_PREFIX + MID_LABEL) and stack_list.get_row_color(invert.id) == accent, "row='%s' color=%s accent=%s" % [invert_row, stack_list.get_row_color(invert.id), accent])
	_check("reads_mark", top_row.ends_with(GSTStackList.READS_PREFIX + MID_LABEL) and stack_list.get_row_color(top.id) == accent, "row='%s' color=%s accent=%s" % [top_row, stack_list.get_row_color(top.id), accent])
	var bottom_row: String = stack_list.get_row_text(bottom.id)
	_check("two_edges_unmarked", bottom_row == "l%s  fbm (field)" % String(bottom.id) and stack_list.get_row_color(bottom.id) == Color(), "row='%s' color=%s" % [bottom_row, stack_list.get_row_color(bottom.id)])
	var mid_row: String = stack_list.get_row_text(mid.id)
	_check("selected_unmarked", mid_row == "l%s  %s fbm (field)" % [String(mid.id), MID_LABEL] and stack_list.get_row_color(mid.id) == Color(), "row='%s'" % mid_row)
	_check("selection_no_history", history.get_history_count() == count and history.get_current_action() == action, "history=%d->%d current_action=%d->%d" % [count, history.get_history_count(), action, history.get_current_action()])


## Selecting top moves the marks: mid feeds top under top's function name;
## invert loses its mark and tint.
func _run_select_top(plugin: EditorPlugin, panel: GSTMainPanel, invert: GSTLayer, mid: GSTLayer, top: GSTLayer) -> void:
	var stack_list: GSTStackList = panel.get_stack_list()
	await _select(plugin, stack_list, top)
	var mid_row: String = stack_list.get_row_text(mid.id)
	var invert_row: String = stack_list.get_row_text(invert.id)
	_check("feeds_mark_function_name", mid_row.ends_with(GSTStackList.FEEDS_PREFIX + "fbm") and stack_list.get_row_color(mid.id) != Color(), "row='%s'" % mid_row)
	_check("marks_recompute_on_selection", invert_row == "l%s  invert (field)" % String(invert.id) and stack_list.get_row_color(invert.id) == Color(), "row='%s' color=%s" % [invert_row, stack_list.get_row_color(invert.id)])


## Bypassing invert keeps its feeds mark after the bypassed suffix; the
## bypass edit's refresh recomputes the marks.
func _run_bypassed_keeps_mark(plugin: EditorPlugin, panel: GSTMainPanel, invert: GSTLayer, mid: GSTLayer) -> void:
	var stack_list: GSTStackList = panel.get_stack_list()
	await _select(plugin, stack_list, mid)
	var bypassed: bool = stack_list.set_layer_enabled(invert.id, false)
	await plugin.get_tree().process_frame
	var row: String = stack_list.get_row_text(invert.id)
	var expected: String = "l%s  invert (field)%s%s%s" % [String(invert.id), GSTStackList.BYPASSED_SUFFIX, GSTStackList.FEEDS_PREFIX, MID_LABEL]
	_check("bypassed_keeps_mark", bypassed and not invert.enabled and row == expected and stack_list.get_row_color(invert.id) != Color(), "row='%s' expected='%s'" % [row, expected])


func _select(plugin: EditorPlugin, stack_list: GSTStackList, layer: GSTLayer) -> void:
	stack_list.select_layer(layer.id)
	for i: int in range(3):
		await plugin.get_tree().process_frame


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
