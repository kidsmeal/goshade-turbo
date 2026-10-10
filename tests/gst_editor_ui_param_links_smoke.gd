@tool
extends RefCounted

## Param link controls (decisions 29, 30), driven through the inspector
## column's link and unlink buttons, the shared picker and the native amount
## slider. Stack, bottom to top: color/fill, generative/fbm,
## color/gradient_map (t from that fbm), generative/fbm. Each edit registers
## one history entry and never writes the base slider value. With
## GST_UI_SCREENSHOT_PATH set and a display, saves the linked fbm rows and
## the gradient_map color rows next to that path.

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

	var fill: GSTLayer = stack_list.add_layer_by_entry_id("color/fill")
	var lower_fbm: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	var gradient: GSTLayer = stack_list.add_layer_by_entry_id("color/gradient_map")
	var top_fbm: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	await plugin.get_tree().process_frame
	var setup_ok: bool = fill != null and lower_fbm != null and gradient != null and top_fbm != null
	_check("setup", setup_ok, "fill=%s lower_fbm=%s gradient=%s top_fbm=%s" % [fill, lower_fbm, gradient, top_fbm])
	if not setup_ok:
		_finish(plugin)
		return

	await _run_link_buttons(plugin, panel, gradient, top_fbm)
	await _run_picker_lists_below(plugin, panel, fill, lower_fbm)
	var base_gain: Variant = top_fbm.get(&"gain")
	var gain_present: bool = top_fbm.has_param_value(&"gain")
	await _run_link(plugin, panel, gradient, top_fbm, base_gain)
	await _run_amount(plugin, panel, top_fbm)
	await _save_screenshots(plugin, panel, gradient, top_fbm)
	await _run_reorder_refused(plugin, panel, top_fbm)
	await _run_unlink(plugin, panel, top_fbm, base_gain)
	await _run_undo_chain(plugin, panel, gradient, top_fbm, base_gain, gain_present)
	_finish(plugin)


## float and int rows carry a link button; color rows carry none.
func _run_link_buttons(plugin: EditorPlugin, panel: GSTMainPanel, gradient: GSTLayer, top_fbm: GSTLayer) -> void:
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	await _select(plugin, panel, top_fbm)
	var gain_button: Button = inspector.get_link_button("gain")
	var octaves_button: Button = inspector.get_link_button("octaves")
	var gain_line: bool = gain_button != null and gain_button.get_parent() == inspector.find_editor_property(&"gain", top_fbm).get_parent()
	_check("link_button_float_rows", gain_button != null and octaves_button != null and gain_button.is_visible_in_tree() and gain_line, "gain=%s octaves=%s same_line=%s" % [gain_button != null, octaves_button != null, gain_line])

	await _select(plugin, panel, gradient)
	var color_row: EditorProperty = inspector.find_editor_property(&"color_a", gradient)
	var no_buttons: bool = inspector.get_link_button("color_a") == null and inspector.get_link_button("color_b") == null
	var line_children: int = color_row.get_parent().get_child_count() if color_row != null else -1
	_check("link_button_absent_on_color_rows", color_row != null and no_buttons and line_children == 1, "color_row=%s no_buttons=%s line_children=%d" % [color_row != null, no_buttons, line_children])


## The link picker on the lower fbm lists only fill; cancel changes nothing.
func _run_picker_lists_below(plugin: EditorPlugin, panel: GSTMainPanel, fill: GSTLayer, lower_fbm: GSTLayer) -> void:
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var picker: GSTPicker = panel.get_picker()
	var history: UndoRedo = panel.get_watched_history()
	await _select(plugin, panel, lower_fbm)
	var count: int = history.get_history_count()
	inspector.get_link_button("gain").pressed.emit()
	await plugin.get_tree().process_frame
	var context: Dictionary = panel.get_picker_context()
	var ids: Array[String] = picker.get_all_entry_ids()
	_check("picker_lists_only_below", panel.is_picker_open() and context.get("purpose", "") == "link" and ids == [String(fill.id)], "open=%s purpose=%s ids=%s" % [panel.is_picker_open(), context.get("purpose", ""), ids])

	picker.cancelled.emit()
	await plugin.get_tree().process_frame
	_check("picker_cancel", not panel.is_picker_open() and lower_fbm.param_links.is_empty() and history.get_history_count() == count, "open=%s links=%s history=%d->%d" % [panel.is_picker_open(), lower_fbm.param_links, count, history.get_history_count()])


## Linking the top fbm's gain to gradient_map (a color layer, read through
## luma) adds the second
## line and one history entry; the base slider stays live and unchanged.
func _run_link(plugin: EditorPlugin, panel: GSTMainPanel, gradient: GSTLayer, top_fbm: GSTLayer, base_gain: Variant) -> void:
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var picker: GSTPicker = panel.get_picker()
	var history: UndoRedo = panel.get_watched_history()
	await _select(plugin, panel, top_fbm)
	var count: int = history.get_history_count()
	inspector.get_link_button("gain").pressed.emit()
	await plugin.get_tree().process_frame
	var ids: Array[String] = picker.get_all_entry_ids()
	var conversion: String = ""
	for row: Dictionary in picker.get_visible_rows():
		if row.get("value", "") == String(gradient.id):
			conversion = String(row.get("conversion", ""))
	_check("picker_lists_layers_below_top", ids.size() == 3 and ids[0] == String(gradient.id) and conversion == "color -> field: luminance", "ids=%s conversion='%s'" % [ids, conversion])

	var activated: bool = picker.activate_value(String(gradient.id))
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var link: Dictionary = top_fbm.param_links.get("gain", {})
	var amount_editor: EditorProperty = inspector.get_link_amount_property("gain")
	var unlink: Button = inspector.get_unlink_button("gain")
	var target_text: String = amount_editor.get_label() if amount_editor != null else ""
	var base_editor: EditorProperty = inspector.find_editor_property(&"gain", top_fbm)
	var linked_ok: bool = activated and not panel.is_picker_open() and link.get("target", &"") == gradient.id and is_equal_approx(float(link.get("amount", 0.0)), 1.0)
	var line_ok: bool = amount_editor != null and amount_editor.is_visible_in_tree() and target_text == "l%s gradient_map" % String(gradient.id) and unlink != null and unlink.is_visible_in_tree()
	var base_ok: bool = top_fbm.get(&"gain") == base_gain and base_editor != null and not base_editor.is_read_only()
	_check("link_adds_second_line", linked_ok and line_ok and base_ok and history.get_history_count() == count + 1, "link=%s target_text='%s' unlink=%s base=%s->%s history=%d->%d" % [link, target_text, unlink != null, base_gain, top_fbm.get(&"gain"), count, history.get_history_count()])
	var amount_name: String = GSTUniformNames.param_amount_uniform(top_fbm.id, "fbm", "gain")
	_check("link_shader", panel.get_shader_material().shader.code.contains(amount_name), "amount uniform '%s' declared=%s" % [amount_name, panel.get_shader_material().shader.code.contains(amount_name)])


## A native amount edit registers one entry and writes the amount uniform.
func _run_amount(plugin: EditorPlugin, panel: GSTMainPanel, top_fbm: GSTLayer) -> void:
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var history: UndoRedo = panel.get_watched_history()
	var count: int = history.get_history_count()
	var amount_editor: EditorProperty = inspector.get_link_amount_property("gain")
	if amount_editor == null:
		_check("amount_change", false, "amount editor missing")
		return
	amount_editor.emit_changed(&"amount", 0.25)
	await plugin.get_tree().process_frame
	var amount: float = float((top_fbm.param_links.get("gain", {}) as Dictionary).get("amount", 0.0))
	var uniform: Variant = panel.get_shader_material().get_shader_parameter(GSTUniformNames.param_amount_uniform(top_fbm.id, "fbm", "gain"))
	var same_editor: bool = is_same(inspector.get_link_amount_property("gain"), amount_editor)
	_check("amount_change", is_equal_approx(amount, 0.25) and uniform is float and is_equal_approx(float(uniform), 0.25) and history.get_history_count() == count + 1 and same_editor, "amount=%s uniform=%s history=%d->%d same_editor=%s" % [amount, uniform, count, history.get_history_count(), same_editor])


## Moving the top fbm below its link target is refused; the stack list's refusal
## label names the link and no entry registers.
func _run_reorder_refused(plugin: EditorPlugin, panel: GSTMainPanel, top_fbm: GSTLayer) -> void:
	var stack_list: GSTStackList = panel.get_stack_list()
	var history: UndoRedo = panel.get_watched_history()
	await _select(plugin, panel, top_fbm)
	var index: int = GSTStackOps.find_index(panel.get_stack(), top_fbm.id)
	var count: int = history.get_history_count()
	(stack_list.get_node("%DownButton") as Button).pressed.emit()
	await plugin.get_tree().process_frame
	var label: Label = stack_list.get_refusal_label()
	_check("reorder_refused", GSTStackOps.find_index(panel.get_stack(), top_fbm.id) == index and label.visible and label.text.contains("links gain") and history.get_history_count() == count, "index=%d->%d refusal='%s' history=%d->%d" % [index, GSTStackOps.find_index(panel.get_stack(), top_fbm.id), label.text, count, history.get_history_count()])


## Unlink removes the second line, keeps the base value, one entry.
func _run_unlink(plugin: EditorPlugin, panel: GSTMainPanel, top_fbm: GSTLayer, base_gain: Variant) -> void:
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var history: UndoRedo = panel.get_watched_history()
	var count: int = history.get_history_count()
	var unlink: Button = inspector.get_unlink_button("gain")
	if unlink == null:
		_check("unlink", false, "unlink button missing")
		return
	unlink.pressed.emit()
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var line_gone: bool = inspector.get_link_amount_property("gain") == null and inspector.get_unlink_button("gain") == null and inspector.get_link_button("gain") != null
	_check("unlink", top_fbm.param_links.is_empty() and line_gone and top_fbm.get(&"gain") == base_gain and history.get_history_count() == count + 1, "links=%s line_gone=%s base=%s->%s history=%d->%d" % [top_fbm.param_links, line_gone, base_gain, top_fbm.get(&"gain"), count, history.get_history_count()])


## Undo walks back unlink, amount and link; the base value and its params
## presence never move.
func _run_undo_chain(plugin: EditorPlugin, panel: GSTMainPanel, gradient: GSTLayer, top_fbm: GSTLayer, base_gain: Variant, gain_present: bool) -> void:
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var history: UndoRedo = panel.get_watched_history()
	history.undo()
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var link: Dictionary = top_fbm.param_links.get("gain", {})
	_check("undo_unlink", link.get("target", &"") == gradient.id and is_equal_approx(float(link.get("amount", 0.0)), 0.25) and inspector.get_link_amount_property("gain") != null, "link=%s line=%s" % [link, inspector.get_link_amount_property("gain") != null])

	history.undo()
	await plugin.get_tree().process_frame
	link = top_fbm.param_links.get("gain", {})
	var amount_editor: EditorProperty = inspector.get_link_amount_property("gain")
	var shown: Variant = amount_editor.get_edited_object().get(&"amount") if amount_editor != null else null
	_check("undo_amount", is_equal_approx(float(link.get("amount", 0.0)), 1.0) and shown is float and is_equal_approx(float(shown), 1.0), "link=%s shown=%s" % [link, shown])

	history.undo()
	for i: int in range(2):
		await plugin.get_tree().process_frame
	_check("undo_link", top_fbm.param_links.is_empty() and inspector.get_link_amount_property("gain") == null, "links=%s line=%s" % [top_fbm.param_links, inspector.get_link_amount_property("gain") != null])
	_check("undo_chain_base_unchanged", top_fbm.get(&"gain") == base_gain and top_fbm.has_param_value(&"gain") == gain_present, "base=%s->%s present=%s->%s" % [base_gain, top_fbm.get(&"gain"), gain_present, top_fbm.has_param_value(&"gain")])

	for i: int in range(3):
		history.redo()
	for i: int in range(2):
		await plugin.get_tree().process_frame
	_check("redo_chain", top_fbm.param_links.is_empty() and top_fbm.get(&"gain") == base_gain, "links=%s base=%s" % [top_fbm.param_links, top_fbm.get(&"gain")])


func _save_screenshots(plugin: EditorPlugin, panel: GSTMainPanel, gradient: GSTLayer, top_fbm: GSTLayer) -> void:
	var path: String = OS.get_environment("GST_UI_SCREENSHOT_PATH")
	if path.is_empty() or DisplayServer.get_name() == "headless":
		return
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var amount_editor: EditorProperty = inspector.get_link_amount_property("gain")
	if amount_editor != null:
		inspector.get_settings_scroll().ensure_control_visible(amount_editor)
	await _save_screenshot(plugin, path.get_basename() + "-linked.png", "screenshot_linked")
	await _select(plugin, panel, gradient)
	await _save_screenshot(plugin, path.get_basename() + "-color-rows.png", "screenshot_color_rows")
	await _select(plugin, panel, top_fbm)


func _select(plugin: EditorPlugin, panel: GSTMainPanel, layer: GSTLayer) -> void:
	panel.get_stack_list().select_layer(layer.id)
	# Narrow layouts show one pane at a time; tab 1 is the settings pane.
	panel.set_narrow_tab(1)
	for i: int in range(3):
		await plugin.get_tree().process_frame


func _save_screenshot(plugin: EditorPlugin, path: String, item: String) -> void:
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var screenshot_error: Error = plugin.get_tree().root.get_texture().get_image().save_png(path)
	_check(item, screenshot_error == OK, "path='%s' error=%d" % [path, screenshot_error])


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
