@tool
extends RefCounted

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
	panel._on_new_pressed()
	for i: int in range(3):
		await plugin.get_tree().process_frame
	panel.set_narrow_tab(1)
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	if not inspector.has_method("get_parameter_inspector") or not inspector.has_method("get_coord_inspector"):
		_check("inspector_api", false, "parameter and coordinate inspector accessors are absent")
		_finish(plugin)
		return
	var saved_section_states: Dictionary = inspector.get_section_states().duplicate(true)
	inspector.set_section_states({})
	for i: int in range(2):
		await plugin.get_tree().process_frame

	var layer: GSTLayer = panel.get_stack_list().add_layer_by_entry_id("generative/fbm")
	panel.get_stack_list().select_layer(layer.id)
	for i: int in range(4):
		await plugin.get_tree().process_frame
	panel.set_narrow_tab(1)
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var entry: GSTManifestEntry = panel.get_library().get_entry(layer.entry)
	var parameter_inspector: EditorInspector = inspector.call("get_parameter_inspector") as EditorInspector
	var coord_inspector: EditorInspector = inspector.call("get_coord_inspector") as EditorInspector
	_check("inspector_targets", parameter_inspector.get_edited_object() == layer and coord_inspector.get_edited_object() == layer.coord, "parameter_target=%s coord_target=%s" % [parameter_inspector.get_edited_object() == layer, coord_inspector.get_edited_object() == layer.coord])

	var gain_schema: Dictionary = _find_schema(entry.params, "gain")
	var gain_property: EditorProperty = inspector.find_editor_property(&"gain", layer)
	var gain_label: String = String(gain_schema.get("label", ""))
	var gain_description: String = String(gain_schema.get("description", ""))
	var minimum_label_room: float = gain_property.get_theme_font(&"font", &"Tree").get_string_size(gain_label, HORIZONTAL_ALIGNMENT_LEFT, -1, gain_property.get_theme_font_size(&"font_size", &"Tree")).x + 90.0 * EditorInterface.get_editor_scale() if gain_property != null else INF
	_check("param_native_label", gain_property != null and gain_property.get_edited_property() == &"gain" and gain_property.get_label() == gain_label and gain_property.is_visible_in_tree() and gain_property.size.y > 0.0 and gain_property.size.x >= minimum_label_room, "path='%s' native_label='%s' expected='%s' visible=%s size=%s required_width=%.1f" % [gain_property.get_edited_property() if gain_property != null else &"", gain_property.get_label() if gain_property != null else "", gain_label, gain_property.is_visible_in_tree() if gain_property != null else false, gain_property.size if gain_property != null else Vector2.ZERO, minimum_label_room])
	_check("param_tooltip", gain_property != null and gain_property.tooltip_text == gain_description and gain_property.get_tooltip(Vector2.ZERO) == gain_description, "tooltip='%s' hover='%s' expected='%s'" % [gain_property.tooltip_text if gain_property != null else "", gain_property.get_tooltip(Vector2.ZERO) if gain_property != null else "", gain_description])
	var gain_property_info: Dictionary = _find_property_info(layer, "gain")
	_check("param_native_hint", int(gain_property_info.get("type", -1)) == TYPE_FLOAT and int(gain_property_info.get("hint", -1)) == PROPERTY_HINT_RANGE and String(gain_property_info.get("hint_string", "")) == "%s,%s" % [str(gain_schema.get("min")), str(gain_schema.get("max"))], "type=%s hint=%s hint_string='%s'" % [gain_property_info.get("type"), gain_property_info.get("hint"), gain_property_info.get("hint_string")])

	var bookkeeping_hidden: bool = true
	for property_name: StringName in [&"id", &"entry", &"kind_out", &"slots", &"params", &"coord"]:
		if GSTInspectorColumn.find_editor_property_in(parameter_inspector, property_name, layer) != null:
			bookkeeping_hidden = false
	_check("bookkeeping_hidden", bookkeeping_hidden, "id/entry/kind_out/slots/params/coord native rows hidden=%s" % bookkeeping_hidden)

	var coord_expected: Dictionary = {
		&"scale": ["Scale", "Multiplies coordinates before the function runs. Higher values repeat and shrink features."],
		&"offset": ["Position", "Offsets coordinates in the selected coordinate space."],
		&"rotation": ["Rotation", "Rotates coordinates around the center, in radians."],
		&"scroll": ["Movement speed", "Moves coordinates over time, in coordinate units per second."],
		&"warp_strength": ["Distortion strength", "Scales the horizontal and vertical distortion inputs."],
	}
	var coord_labels_ok: bool = true
	var coord_details: Array[String] = []
	for property_name: StringName in coord_expected:
		var property: EditorProperty = GSTInspectorColumn.find_editor_property_in(coord_inspector, property_name, layer.coord)
		var expected: Array = coord_expected[property_name]
		var matches: bool = property != null and property.get_label() == expected[0] and property.tooltip_text == expected[1] and property.get_tooltip(Vector2.ZERO) == expected[1] and property.is_visible_in_tree() and property.size.y > 0.0
		coord_labels_ok = coord_labels_ok and matches
		coord_details.append("%s=%s/%s" % [property_name, property.get_label() if property != null else "missing", property.tooltip_text if property != null else "missing"])
	var native_warp_hidden: bool = GSTInspectorColumn.find_editor_property_in(coord_inspector, &"warp_x", layer.coord) == null and GSTInspectorColumn.find_editor_property_in(coord_inspector, &"warp_y", layer.coord) == null
	var coord_bookkeeping_hidden: bool = true
	for property_name: StringName in [&"resource_local_to_scene", &"resource_name", &"script"]:
		if GSTInspectorColumn.find_editor_property_in(coord_inspector, property_name, layer.coord) != null:
			coord_bookkeeping_hidden = false
	var visible_resource_headers: int = _visible_text_count(parameter_inspector, "Resource") + _visible_text_count(coord_inspector, "Resource")
	_check("coord_native_labels", coord_labels_ok and native_warp_hidden and coord_bookkeeping_hidden and visible_resource_headers == 0, "labels=%s warp_native_hidden=%s bookkeeping_hidden=%s visible_resource_headers=%d" % [coord_details, native_warp_hidden, coord_bookkeeping_hidden, visible_resource_headers])
	_check("warp_labels", _has_label(inspector, "Horizontal distortion", "Selects an earlier layer that distorts horizontal coordinates.") and _has_label(inspector, "Vertical distortion", "Selects an earlier layer that distorts vertical coordinates."), "readable horizontal and vertical distortion rows present")

	await _check_native_param_edit(plugin, panel, inspector, layer, entry)
	await _check_native_coord_edit(plugin, panel, inspector, layer)
	var screenshot_path: String = OS.get_environment("GST_UI_SCREENSHOT_PATH")
	if not screenshot_path.is_empty():
		await _save_screenshot(plugin, screenshot_path, "screenshot_params")
		var settings_scroll: ScrollContainer = inspector.call("get_settings_scroll") as ScrollContainer
		settings_scroll.scroll_vertical = int(settings_scroll.get_v_scroll_bar().max_value)
		for i: int in range(2):
			await plugin.get_tree().process_frame
		await _save_screenshot(plugin, screenshot_path.get_basename() + "-coords.png", "screenshot_coords")
		settings_scroll.scroll_vertical = 0

	var mix: GSTLayer = panel.get_stack_list().add_layer_by_entry_id("color/mix")
	panel.get_stack_list().select_layer(mix.id)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	panel.set_narrow_tab(1)
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var mix_entry: GSTManifestEntry = panel.get_library().get_entry(mix.entry)
	var input_rows_ok: bool = true
	for input: Dictionary in mix_entry.inputs:
		input_rows_ok = input_rows_ok and _has_label(inspector, String(input["label"]), String(input["description"]))
	_check("input_labels", input_rows_ok, "color/mix input labels and descriptions visible=%s" % input_rows_ok)

	var max_layer: GSTLayer = panel.get_stack_list().add_layer_by_entry_id("fieldops/max")
	panel.get_stack_list().select_layer(max_layer.id)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	panel.set_narrow_tab(1)
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var long_label: Label = _find_label(inspector, "Second comparison value")
	var long_row: Control = long_label.get_parent() as Control if long_label != null else null
	var input_button: Button = inspector.get_input_button("b")
	var row_bounded: bool = long_row != null and inspector.get_global_rect().encloses(long_row.get_global_rect())
	var readable_button: bool = input_button != null and input_button.size.x >= 48.0 and input_button.text == _reference_text(panel, max_layer.slots.get("b", &"") as StringName)
	var input_controls_visible: bool = long_label != null and long_label.is_visible_in_tree() and input_button != null and input_button.is_visible_in_tree()
	_check("long_input_label", input_controls_visible and not long_label.clip_text and long_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and row_bounded and readable_button, "label=%s visible=%s lines=%d row=%s inspector=%s button_visible=%s button_width=%.1f" % [long_label.text if long_label != null else "missing", long_label.is_visible_in_tree() if long_label != null else false, long_label.get_line_count() if long_label != null else 0, long_row.get_global_rect() if long_row != null else Rect2(), inspector.get_global_rect(), input_button.is_visible_in_tree() if input_button != null else false, input_button.size.x if input_button != null else 0.0])

	if not screenshot_path.is_empty():
		await _save_screenshot(plugin, screenshot_path.get_basename() + "-inputs.png", "screenshot_inputs")

	inspector.set_section_states(saved_section_states)
	_finish(plugin)


func _check_native_param_edit(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, layer: GSTLayer, entry: GSTManifestEntry) -> void:
	var old_value: float = float(layer.get("gain"))
	var new_value: float = 0.63
	var id_before: StringName = layer.id
	var entry_before: String = layer.entry
	var property: EditorProperty = inspector.find_editor_property(&"gain", layer)
	var property_found_before_edit: bool = property != null
	if property_found_before_edit:
		property.emit_changed(&"gain", new_value)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var uniform_name: String = GSTUniformNames.param_uniform(layer.id, entry.function, "gain")
	var uniform_value: Variant = panel.get_shader_material().get_shader_parameter(uniform_name)
	var history: UndoRedo = _history_for(layer)
	var value_ok: bool = is_equal_approx(float(layer.get("gain")), new_value)
	var uniform_ok: bool = uniform_value is float and is_equal_approx(float(uniform_value), new_value)
	var identity_ok: bool = layer.id == id_before and layer.entry == entry_before
	var key_ok: bool = layer.params.has("gain")
	var applied: bool = property_found_before_edit and value_ok and uniform_ok and identity_ok and key_ok
	_check("native_param_edit", applied and history.has_undo(), "property_before_edit=%s value=%s value_ok=%s uniform=%s uniform_ok=%s key='%s' identity_ok=%s params_key=%s history_has_undo=%s" % [property_found_before_edit, layer.get("gain"), value_ok, uniform_value, uniform_ok, uniform_name, identity_ok, key_ok, history.has_undo()])
	history.undo()
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var after_undo_property: EditorProperty = inspector.find_editor_property(&"gain", layer)
	var undone_uniform: Variant = panel.get_shader_material().get_shader_parameter(uniform_name)
	_check("native_param_undo", is_equal_approx(float(layer.get("gain")), old_value) and is_equal_approx(_range_value(after_undo_property), old_value) and undone_uniform is float and is_equal_approx(float(undone_uniform), old_value), "value=%s displayed=%s uniform=%s expected=%s" % [layer.get("gain"), _range_value(after_undo_property), undone_uniform, old_value])


func _check_native_coord_edit(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, layer: GSTLayer) -> void:
	var property: EditorProperty = inspector.find_coord_editor_property(&"offset") if inspector.has_method("find_coord_editor_property") else null
	var old_value: Vector2 = layer.coord.offset
	var new_value: Vector2 = Vector2(0.2, -0.3)
	if property != null:
		property.emit_changed(&"offset", new_value)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var uniform_name: String = GSTUniformNames.coord_offset(layer.id)
	var uniform_value: Variant = panel.get_shader_material().get_shader_parameter(uniform_name)
	var history: UndoRedo = _history_for(layer.coord)
	_check("native_coord_edit", property != null and layer.coord.offset.is_equal_approx(new_value) and uniform_value is Vector2 and (uniform_value as Vector2).is_equal_approx(new_value) and history.has_undo(), "property=%s value=%s uniform=%s history_has_undo=%s" % [property != null, layer.coord.offset, uniform_value, history.has_undo()])
	history.undo()
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var undone_uniform: Variant = panel.get_shader_material().get_shader_parameter(uniform_name)
	_check("native_coord_undo", layer.coord.offset.is_equal_approx(old_value) and undone_uniform is Vector2 and (undone_uniform as Vector2).is_equal_approx(old_value), "value=%s uniform=%s expected=%s" % [layer.coord.offset, undone_uniform, old_value])


func _history_for(object: Object) -> UndoRedo:
	var manager: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	return manager.get_history_undo_redo(manager.get_object_history_id(object))


func _find_schema(schema: Array[Dictionary], name: String) -> Dictionary:
	for item: Dictionary in schema:
		if String(item.get("name", "")) == name:
			return item
	return {}


func _reference_text(panel: GSTMainPanel, layer_id: StringName) -> String:
	if layer_id == &"":
		return "(none)"
	var layer: GSTLayer = GSTStackOps.find_layer(panel.get_stack(), layer_id)
	var entry: GSTManifestEntry = panel.get_library().get_entry(layer.entry) if layer != null else null
	var function_name: String = ""
	if entry != null:
		function_name = entry.function
	elif layer != null:
		function_name = layer.entry
	return "l%s %s" % [String(layer_id), function_name]


func _find_property_info(object: Object, name: String) -> Dictionary:
	for property: Dictionary in object.get_property_list():
		if String(property.get("name", "")) == name:
			return property
	return {}


func _has_label(root: Node, text: String, tooltip: String) -> bool:
	var label: Label = _find_label(root, text)
	return label != null and label.is_visible_in_tree() and label.size.x > 0.0 and label.size.y > 0.0 and label.tooltip_text == tooltip


func _find_label(root: Node, text: String) -> Label:
	for node: Node in root.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.text == text:
			return label
	return null


func _range_value(property: EditorProperty) -> float:
	var range: Range = _find_range(property)
	return range.value if range != null else NAN


func _find_range(node: Node) -> Range:
	if node is Range:
		return node as Range
	if node == null:
		return null
	for child: Node in node.get_children():
		var found: Range = _find_range(child)
		if found != null:
			return found
	return null


func _visible_text_count(node: Node, text: String) -> int:
	var count: int = 0
	if node is Control and (node as Control).is_visible_in_tree():
		if node is Label and (node as Label).text == text:
			count += 1
		elif node is Button and (node as Button).text == text:
			count += 1
	for child: Node in node.get_children():
		count += _visible_text_count(child, text)
	return count


func _save_screenshot(plugin: EditorPlugin, path: String, item: String) -> void:
	await plugin.get_tree().process_frame
	var screenshot_error: Error = plugin.get_tree().root.get_texture().get_image().save_png(path)
	_check(item, screenshot_error == OK, "path='%s' error=%d" % [path, screenshot_error])


func _check(item: String, ok: bool, detail: String) -> void:
	if ok:
		_pass_count += 1
		print("SMOKE ui_labels_%s PASS %s" % [item, detail])
	else:
		_fail_count += 1
		print("SMOKE ui_labels_%s FAIL %s" % [item, detail])


func _finish(plugin: EditorPlugin) -> void:
	print("SMOKE SUMMARY pass=%d fail=%d" % [_pass_count, _fail_count])
	plugin.get_tree().quit(1 if _fail_count > 0 else 0)
