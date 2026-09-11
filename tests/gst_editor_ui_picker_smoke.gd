@tool
extends RefCounted

var _pass_count: int = 0
var _fail_count: int = 0
var _plugin: EditorPlugin

func run(plugin: EditorPlugin) -> void:
	_plugin = plugin
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1366, 768))
	await _frames(5)
	await plugin.get_tree().create_timer(2.0).timeout
	var panel: GSTMainPanel = plugin.get_panel() as GSTMainPanel
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	plugin.get_window().grab_focus()
	var metadata_before: Dictionary = panel.get_layout_metadata_snapshot()
	panel.restore_layout_metadata_snapshot({"main_ratio": 0.6, "inner_ratio": 0.42, "narrow_tab": 0, "sections": {}})
	await _frames(5)
	var picker: GSTPicker = panel.get_picker()
	panel.get_create_empty_button().pressed.emit()
	await _frames(2)
	picker.cancelled.emit()
	await _frames(2)
	var list: GSTStackList = panel.get_stack_list()
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var output: GSTOutputBlock = panel.get_output_block()
	var stack: GSTStack = panel.get_stack()
	var history: UndoRedo = panel.get_watched_history()
	var initial_count: int = history.get_history_count()
	var invalid_first: Dictionary = panel.get_undo().add_layer_for_ui("fieldops/invert")
	_check("first_add_guard", not invalid_first["ok"] and stack.layers.is_empty() and stack.next_id == 0 and history.get_history_count() == initial_count, "direct UI add cannot bypass first-layer filter")
	(list.get_node("%AddButton") as Button).pressed.emit()
	await _frames(3)
	_check("embedded", picker is PanelContainer and picker.visible and picker.mouse_filter == Control.MOUSE_FILTER_STOP, "embedded chooser open")
	_check("geometry", _inside(picker.get_global_rect(), panel.get_node("%EditingArea").get_global_rect()) and not picker.get_global_rect().intersects(panel.get_preview().get_global_rect()), str(panel.get_layout_measurements()))
	_check("search_focus", picker.get_search_control().has_focus(), "search receives focus")
	var zero_inputs: bool = not picker.get_all_entry_ids().is_empty()
	for id: String in picker.get_all_entry_ids():
		zero_inputs = zero_inputs and panel.get_library().get_entry(id).inputs.is_empty()
	_check("empty_filter", zero_inputs, str(picker.get_all_entry_ids()))
	picker.set_search_text("NOISE")
	_check("description_search", picker.get_visible_entry_ids().has("generative/fbm"), str(picker.get_visible_entry_ids()))
	var first_image: Image = panel.get_preview().get_viewport_image()
	picker.set_search_text("checker")
	await _frames(2)
	_key(KEY_DOWN)
	await _frames(1)
	_check("arrows_no_apply", stack.layers.is_empty() and history.get_history_count() == initial_count, "arrow does not mutate")
	_key(KEY_ENTER)
	await _frames(5)
	_check("enter_first_add", not panel.is_picker_open() and stack.layers.size() == 1 and stack.output_color == stack.layers[0].id and history.get_history_count() == initial_count + 1, "open=%s layers=%d history=%d expected=%d focus=%s" % [panel.is_picker_open(), stack.layers.size(), history.get_history_count(), initial_count + 1, panel.get_viewport().gui_get_focus_owner()])
	if stack.layers.is_empty():
		_finish()
		return
	var field: GSTLayer = stack.layers[0]
	var color: GSTLayer = list.add_layer_by_entry_id("color/fill")
	var consumer: GSTLayer = list.add_layer_by_entry_id("fieldops/invert")
	list.select_layer(consumer.id)
	inspector.set_section_states({})
	panel.set_narrow_tab(1)
	await _frames(4)
	inspector.get_input_button("x").pressed.emit()
	await _frames(3)
	var context: Dictionary = panel.get_picker_context()
	_check("existing_earlier", picker.get_all_entry_ids().has(String(field.id)) and picker.get_all_entry_ids().has(String(color.id)) and not picker.get_all_entry_ids().has(String(consumer.id)), str(picker.get_all_entry_ids()))
	_check("existing_conversion", _row_conversion(picker, String(color.id)) == "color -> field: luminance", "color candidate carries conversion")
	picker.set_search_text("fill")
	picker.switch_tab(1)
	_check("tab_query", picker.get_search_control().text == "fill" and panel.get_picker_context() == context, "query and destination retained")
	_check("new_conversion", _row_conversion(picker, "color/fill") == "color -> field: luminance", "new candidate carries conversion")
	picker.set_search_text("")
	picker.switch_tab(0)
	_click_choice(picker, String(color.id))
	await _frames(3)
	_check("input_apply", consumer.slots.get("x") == color.id and not panel.is_picker_open(), "existing source applied")
	_check("connected_conversion", _visible_text(inspector, "color -> field: luminance"), "connected input conversion persists")
	_check("input_focus", inspector.get_input_button("x").has_focus(), "input button regains focus after rebuild")
	inspector.get_input_button("x").pressed.emit()
	await _frames(2)
	var count_before_cancel: int = history.get_history_count()
	_key(KEY_ESCAPE)
	await _frames(2)
	_check("escape", not panel.is_picker_open() and history.get_history_count() == count_before_cancel and inspector.get_input_button("x").has_focus(), "Escape cancels and restores focus")

	var generator: GSTLayer = list.add_layer_by_entry_id("generative/fbm")
	list.select_layer(generator.id)
	await _frames(3)
	inspector.get_warp_button("x").pressed.emit()
	await _frames(2)
	var warp_context: Dictionary = panel.get_picker_context()
	var editor_scale: float = EditorInterface.get_editor_scale()
	DisplayServer.window_set_size(Vector2i(roundi(1920.0 * editor_scale), roundi(1080.0 * editor_scale)))
	await _frames(7)
	var wide_ok: bool = _inside(picker.get_global_rect(), panel.get_node("%EditingArea").get_global_rect()) and not panel.get_layout_measurements()["narrow"]
	var tab_threshold: float = panel.get_layout_measurements()["tab_breakpoint"]
	DisplayServer.window_set_size(Vector2i(720, 600))
	await _frames(7)
	var main_split: HSplitContainer = panel.get_node("%MainSplit") as HSplitContainer
	if panel.get_layout_measurements()["editing_rect"].size.x >= tab_threshold:
		await _drag_splitter(plugin, main_split, -(panel.get_layout_measurements()["editing_rect"].size.x - tab_threshold + 24.0))
	# The first drag can stop at the wide pane minimum as tab mode activates.
	# A second drag uses the reduced tab minimum to cross below the threshold.
	if panel.get_layout_measurements()["editing_rect"].size.x >= tab_threshold:
		await _drag_splitter(plugin, main_split, -24.0)
	var narrow: Dictionary = panel.get_layout_measurements()
	var crossed_breakpoint: bool = narrow["editing_rect"].size.x < narrow["tab_breakpoint"]
	var context_unchanged: bool = panel.get_picker_context() == warp_context
	var picker_enclosed: bool = _inside(picker.get_global_rect(), panel.get_node("%EditingArea").get_global_rect())
	_check("picker_resize", wide_ok and crossed_breakpoint and narrow["narrow"] and context_unchanged and picker_enclosed, "wide=%s crossed=%s narrow=%s context_unchanged=%s picker_enclosed=%s measurements=%s" % [wide_ok, crossed_breakpoint, narrow["narrow"], context_unchanged, picker_enclosed, narrow])
	DisplayServer.window_set_size(Vector2i(1366, 768))
	await _frames(7)
	var conversion_fits: bool = true
	var conversion_tree: Tree = picker.get_results_tree()
	for folder: TreeItem in conversion_tree.get_root().get_children():
		for item: TreeItem in folder.get_children():
			var row: Dictionary = item.get_metadata(0)
			if String(row.get("conversion", "")).is_empty():
				continue
			for line: String in item.get_text(1).split("\n"):
				var width: float = conversion_tree.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, conversion_tree.get_theme_font_size("font_size")).x
				conversion_fits = conversion_fits and width <= conversion_tree.get_column_width(1)
	var columns_width: float = conversion_tree.get_column_width(0) + conversion_tree.get_column_width(1) + conversion_tree.get_column_width(2)
	_check("columns_fit", columns_width <= conversion_tree.size.x, "columns=%s tree=%s" % [columns_width, conversion_tree.size.x])
	_check("conversion_readable", conversion_fits, "conversion line widths fit visible kind column")
	var conversion_capture: String = OS.get_environment("GST_PICKER_SCREENSHOT")
	if not conversion_capture.is_empty():
		plugin.get_viewport().get_texture().get_image().save_png(conversion_capture.get_basename() + "-conversion.png")
	_check("warp_conversion", _row_conversion(picker, String(color.id)) == "color -> field: luminance", "warp allows color with luminance")
	picker.activate_value(String(color.id))
	await _frames(2)
	_check("warp_apply", generator.coord.warp_x == color.id, "existing warp applied")
	inspector.get_warp_button("y").pressed.emit()
	picker.switch_tab(1)
	var before_warp: int = history.get_history_count()
	var before_output: StringName = stack.output_color
	picker.activate_value("fieldops/invert")
	await _frames(3)
	var added: GSTLayer = GSTStackOps.find_layer(stack, generator.coord.warp_y)
	_check("warp_atomic", added != null and added.entry == "fieldops/invert" and GSTStackOps.find_index(stack, added.id) == GSTStackOps.find_index(stack, generator.id) - 1 and stack.output_color == before_output and history.get_history_count() == before_warp + 1, "new warp inserted below destination, one action, output preserved")
	history.undo()
	await _frames(2)
	_check("warp_undo", generator.coord.warp_y == &"" and GSTStackOps.find_layer(stack, added.id) == null and stack.output_color == before_output, "undo removes and disconnects")
	history.redo()
	await _frames(2)
	_check("warp_redo", generator.coord.warp_y == added.id and GSTStackOps.find_layer(stack, added.id) == added, "redo restores same instance")
	var invalid_count: int = history.get_history_count()
	var invalid_id: int = stack.next_id
	var invalid: Dictionary = panel.get_undo().add_layer_below_and_wire_warp(generator.id, "color/fill", "z")
	_check("warp_refusal_atomic", not invalid["ok"] and history.get_history_count() == invalid_count and stack.next_id == invalid_id, "invalid destination allocates nothing")

	var texture: GSTLayer = list.add_layer_by_entry_id("source/texture")
	var filter: GSTLayer = list.add_layer_by_entry_id("filter/pixelate")
	list.select_layer(filter.id)
	await _frames(3)
	inspector.get_input_button("source").pressed.emit()
	var existing_source_only: bool = true
	for value: String in picker.get_all_entry_ids():
		if not value.is_empty():
			existing_source_only = existing_source_only and GSTStackOps.find_layer(stack, StringName(value)).entry in ["source/texture", "source/screen"]
	picker.switch_tab(1)
	_check("source_only", existing_source_only and picker.get_all_entry_ids().size() == 2 and picker.get_all_entry_ids().has("source/texture") and picker.get_all_entry_ids().has("source/screen"), str(picker.get_all_entry_ids()))
	panel._on_picker_choice({"value": "color/fill"})
	_check("refusal_open", panel.is_picker_open() and not (picker.get_node("%Refusal") as Label).text.is_empty(), "illegal candidate refuses and stays open")
	panel._resync_material()
	_check("refusal_lifetime", not (picker.get_node("%Refusal") as Label).text.is_empty(), "successful codegen does not clear refusal")
	picker.activate_value("source/screen")
	await _frames(3)
	_check("retry", not panel.is_picker_open(), "valid retry applies and closes")

	output.get_color_button().pressed.emit()
	await _frames(2)
	_check("output_color", picker.get_all_entry_ids().has("") and _row_conversion(picker, String(field.id)) == "field -> color: grayscale", "automatic and grayscale output candidates")
	picker.activate_value(String(field.id))
	await _frames(2)
	for mode: String in ["none", "texture", "color_alpha", "", String(field.id)]:
		output.get_alpha_button().pressed.emit()
		picker.activate_value(mode)
		await _frames(2)
		_check("transparency_" + mode, stack.output_alpha == StringName(mode) and not panel.is_picker_open(), output.get_selected_alpha_text())

	(panel.get_node("%RecipesButton") as Button).pressed.emit()
	await _frames(2)
	_check("recipes", picker.get_all_entry_ids().has("fire"), "Recipes uses shared chooser")
	picker.activate_value("fire")
	await _frames(5)
	_check("recipe_apply", panel.get_stack() != stack and panel.get_randomize_button().disabled == false and not panel.is_picker_open(), "recipe replacement applied")
	stack = panel.get_stack()
	# The "fire" pick above activates a brand new GSTDocument with its own
	# fresh UndoRedo (phase 3, docs/SHADER_TABS_reviewed-plan.md): history
	# above pointed at the previous document and would go stale from here on
	# without this recapture.
	history = panel.get_watched_history()
	(panel.get_stack_list().get_node("%AddButton") as Button).pressed.emit()
	await _frames(3)
	var image_before: Image = panel.get_preview().get_viewport_image()
	var blocked_history: int = history.get_history_count()
	var blocked_layers: Array[GSTLayer] = stack.layers.duplicate()
	panel._on_new_pressed()
	panel._on_open_pressed()
	panel.open_path("res://addons/goshade_turbo/recipes/fire.tres")
	panel.open_recipe("dissolve")
	panel._on_reopen_shader_pressed()
	panel.reopen_shader_path("missing.gdshader")
	panel.replace_stack(GSTStack.new(), "", false)
	panel._on_randomize_pressed()
	panel._on_coord_space_selected(1)
	list._on_remove_pressed()
	list._on_up_pressed()
	list._on_down_pressed()
	list.add_layer_by_entry_id("color/fill")
	_key(KEY_Z, true)
	await _frames(3)
	_check("blocked_handlers", panel.get_stack() == stack and stack.layers == blocked_layers and history.get_history_count() == blocked_history, "mutating handlers and undo shortcut blocked")
	_check("blocked_buttons", panel.get_randomize_button().disabled and (list.get_node("%AddButton") as Button).disabled and output.get_color_button().disabled and (panel.get_node("%CoordSpaceOption") as OptionButton).disabled, "mutating buttons disabled")
	panel._on_save_pressed()
	_check("save_available", panel._save_as_dialog.visible and panel.is_picker_open(), "Save opens its file dialog while chooser remains open")
	panel._save_as_dialog.hide()
	panel._on_export_pressed()
	_check("export_available", panel.is_export_dialog_visible() and panel.is_picker_open(), "Export opens its file dialog while chooser remains open")
	panel.hide_export_dialog()
	picker.get_search_control().grab_focus()
	_check("available_controls", not (panel.get_node("%SaveButton") as Button).disabled and not (panel.get_node("%ExportButton") as Button).disabled and not (panel.get_node("%ImageButton") as Button).disabled, "Save Export preview available")
	await _frames(5)
	var image_after: Image = panel.get_preview().get_viewport_image()
	_check("preview_rendering", first_image != null and image_before != null and image_after != null and image_before.get_data() != image_after.get_data(), "animated fire pixels change while chooser open")
	var screenshot: String = OS.get_environment("GST_PICKER_SCREENSHOT")
	if not screenshot.is_empty():
		plugin.get_viewport().get_texture().get_image().save_png(screenshot)
	panel._close_picker()
	await _frames(2)

	# Bypass guarded UI only to simulate a stale installation at activation.
	(list.get_node("%AddButton") as Button).pressed.emit()
	var frozen: Dictionary = panel.get_picker_context()
	var alternate: GSTStack = GSTStack.new()
	var old_undo: GSTUndo = panel.get_undo()
	panel._install_stack(alternate, GSTUndo.new(panel.get_watched_history(), alternate, panel.get_library(), panel._on_stack_changed, panel._on_property_changed))
	var stale_history: int = history.get_history_count()
	picker.activate_value("color/fill")
	_check("stale_stack", panel.is_picker_open() and panel.get_picker_context() == frozen and alternate.layers.is_empty() and history.get_history_count() == stale_history, "stale stack refused without mutation")
	panel._close_picker()
	panel._install_stack(stack, old_undo)
	await _frames(2)
	var stale_dest: GSTLayer = list.add_layer_by_entry_id("fieldops/invert")
	list.select_layer(stale_dest.id)
	await _frames(3)
	inspector.get_input_button("x").pressed.emit()
	var index: int = GSTStackOps.find_index(stack, stale_dest.id)
	stack.layers.remove_at(index)
	stale_history = history.get_history_count()
	panel._on_picker_choice({"value": ""})
	_check("stale_destination", panel.is_picker_open() and history.get_history_count() == stale_history, "removed destination refuses without action")
	stack.layers.insert(index, stale_dest)
	panel._close_picker()
	await _frames(5)
	panel.restore_layout_metadata_snapshot(metadata_before)
	_finish()


func _drag_splitter(plugin: EditorPlugin, split: HSplitContainer, delta: float) -> void:
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


func _frames(count: int) -> void:
	for i: int in range(count):
		await _plugin.get_tree().process_frame

func _click_choice(picker: GSTPicker, value: String) -> void:
	var tree: Tree = picker.get_results_tree()
	for folder: TreeItem in tree.get_root().get_children():
		for item: TreeItem in folder.get_children():
			var data: Dictionary = item.get_metadata(0)
			if data["value"] != value:
				continue
			tree.scroll_to_item(item)
			var rect: Rect2 = tree.get_item_area_rect(item, 0)
			var event: InputEventMouseButton = InputEventMouseButton.new()
			event.position = tree.global_position + rect.get_center()
			event.global_position = event.position
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = true
			_plugin.get_viewport().push_input(event, true)
			event = event.duplicate()
			event.pressed = false
			_plugin.get_viewport().push_input(event, true)
			return

func _key(code: Key, ctrl: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.window_id = _plugin.get_window().get_window_id()
	_plugin.get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	_plugin.get_viewport().push_input(event, true)

func _row_conversion(picker: GSTPicker, value: String) -> String:
	for row: Dictionary in picker.get_visible_rows():
		if row["value"] == value:
			return String(row.get("conversion", ""))
	return ""

func _visible_text(root: Node, text: String) -> bool:
	for node: Node in root.find_children("*", "Label", true, false):
		if node is Label and node.is_visible_in_tree() and node.text == text:
			return true
	return false

func _inside(inner: Rect2, outer: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 1.0 and inner.position.y >= outer.position.y - 1.0 and inner.end.x <= outer.end.x + 1.0 and inner.end.y <= outer.end.y + 1.0

func _check(item: String, passed: bool, detail: String) -> void:
	if passed:
		_pass_count += 1
	else:
		_fail_count += 1
	print("UI_PICKER %s %s %s" % [item, "PASS" if passed else "FAIL", detail])

func _finish() -> void:
	print("UI_PICKER SUMMARY pass=%d fail=%d" % [_pass_count, _fail_count])
	_plugin.get_tree().quit(1 if _fail_count > 0 else 0)
