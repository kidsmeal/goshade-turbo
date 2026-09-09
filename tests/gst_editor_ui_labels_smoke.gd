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
	panel.get_create_empty_button().pressed.emit()
	await plugin.get_tree().process_frame
	panel.get_picker().cancelled.emit()
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
		&"rotation": ["Rotation", "Rotates coordinates around the coordinate origin, in radians."],
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
	await _check_inactive_controls(plugin, panel, inspector, layer)
	var screenshot_path: String = OS.get_environment("GST_UI_SCREENSHOT_PATH")
	if not screenshot_path.is_empty():
		await _save_screenshot(plugin, screenshot_path, "screenshot_params")
		var settings_scroll: ScrollContainer = inspector.call("get_settings_scroll") as ScrollContainer
		settings_scroll.scroll_vertical = int(settings_scroll.get_v_scroll_bar().max_value)
		for i: int in range(2):
			await plugin.get_tree().process_frame
		await _save_screenshot(plugin, screenshot_path.get_basename() + "-coords.png", "screenshot_coords")
		settings_scroll.scroll_vertical = 0

	await _check_native_palette_color(plugin, panel, inspector)

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


func _check_inactive_controls(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn, source: GSTLayer) -> void:
	var warp: EditorProperty = inspector.find_coord_editor_property(&"warp_strength")
	var saved_strength: float = source.coord.warp_strength
	_check("unconnected_warp_inactive", warp != null and warp.is_read_only() and _context_contains(warp, "Connect Horizontal distortion"), "readonly=%s hint='%s'" % [warp.is_read_only() if warp != null else false, _context_text(warp)])
	var octaves: EditorProperty = inspector.find_editor_property(&"octaves", source)
	if octaves != null:
		octaves.emit_changed(&"octaves", 1)
	await _wait_context(plugin)
	var gain: EditorProperty = inspector.find_editor_property(&"gain", source)
	_check("single_octave_gain_inactive", int(source.get(&"octaves")) == 1 and gain != null and gain.is_read_only() and _context_contains(gain, "at least 2 Detail layers"), "octaves=%s readonly=%s hint='%s'" % [source.get(&"octaves"), gain.is_read_only() if gain != null else false, _context_text(gain)])
	var screenshot_path: String = OS.get_environment("GST_UI_SCREENSHOT_PATH")
	if not screenshot_path.is_empty() and gain != null:
		inspector.get_settings_scroll().ensure_control_visible(gain)
		await _save_screenshot(plugin, screenshot_path.get_basename() + "-inactive-gain.png", "screenshot_inactive_gain")
	var history: UndoRedo = _history_for(source)
	history.undo()
	await _wait_context(plugin)
	gain = inspector.find_editor_property(&"gain", source)
	_check("gain_enable_undo", int(source.get(&"octaves")) > 1 and gain != null and not gain.is_read_only() and _context_text(gain).is_empty(), "octaves=%s readonly=%s" % [source.get(&"octaves"), gain.is_read_only() if gain != null else true])
	history.redo()
	await _wait_context(plugin)
	gain = inspector.find_editor_property(&"gain", source)
	_check("gain_disable_redo", int(source.get(&"octaves")) == 1 and gain != null and gain.is_read_only(), "octaves=%s readonly=%s" % [source.get(&"octaves"), gain.is_read_only() if gain != null else false])
	history.undo()
	await _wait_context(plugin)

	var target: GSTLayer = panel.get_stack_list().add_layer_by_entry_id("generative/fbm")
	panel.get_stack_list().select_layer(target.id)
	await _wait_context(plugin)
	var assigned: Dictionary = panel.get_undo().assign_warp(target.id, "x", source.id)
	await _wait_context(plugin)
	warp = inspector.find_coord_editor_property(&"warp_strength")
	_check("connected_warp_enabled", assigned["ok"] and target.coord.warp_x == source.id and warp != null and not warp.is_read_only() and _context_text(warp).is_empty(), "assigned=%s readonly=%s" % [assigned["ok"], warp.is_read_only() if warp != null else true])
	history = panel.get_watched_history()
	history.undo()
	await _wait_context(plugin)
	warp = inspector.find_coord_editor_property(&"warp_strength")
	_check("warp_inactive_undo", target.coord.warp_x == &"" and warp != null and warp.is_read_only() and _context_contains(warp, "Connect Horizontal distortion") and source.coord.warp_strength == saved_strength, "reference='%s' readonly=%s source_strength=%s" % [target.coord.warp_x, warp.is_read_only() if warp != null else false, source.coord.warp_strength])
	history.redo()
	await _wait_context(plugin)
	warp = inspector.find_coord_editor_property(&"warp_strength")
	_check("warp_enabled_redo", target.coord.warp_x == source.id and warp != null and not warp.is_read_only(), "reference='%s' readonly=%s" % [target.coord.warp_x, warp.is_read_only() if warp != null else true])

	var stripes: GSTLayer = panel.get_stack_list().add_layer_by_entry_id("generative/stripes")
	panel.get_stack_list().select_layer(stripes.id)
	await _wait_context(plugin)
	panel.get_undo().assign_warp(stripes.id, "y", source.id)
	await _wait_context(plugin)
	var position: EditorProperty = inspector.find_coord_editor_property(&"offset")
	var movement: EditorProperty = inspector.find_coord_editor_property(&"scroll")
	warp = inspector.find_coord_editor_property(&"warp_strength")
	_check("one_axis_help", position != null and not position.is_read_only() and _context_contains(position, "Y Position has no effect") and movement != null and not movement.is_read_only() and _context_contains(movement, "Vertical distortion have no effect") and warp != null and warp.is_read_only(), "position='%s' movement='%s' warp_readonly=%s" % [_context_text(position), _context_text(movement), warp.is_read_only() if warp != null else false])
	panel.get_undo().assign_warp(stripes.id, "x", source.id)
	await _wait_context(plugin)
	warp = inspector.find_coord_editor_property(&"warp_strength")
	_check("one_axis_horizontal_enabled", warp != null and not warp.is_read_only() and _context_text(warp).is_empty(), "readonly=%s" % [warp.is_read_only() if warp != null else true])

	var circle: GSTLayer = panel.get_stack_list().add_layer_by_entry_id("sdf/circle")
	panel.get_stack_list().select_layer(circle.id)
	await _wait_context(plugin)
	var rotation: EditorProperty = inspector.find_coord_editor_property(&"rotation")
	_check("circle_rotation_help", rotation != null and not rotation.is_read_only() and _context_contains(rotation, "Rotation has no effect") and rotation.tooltip_text.contains("coordinate origin"), "hint='%s' tooltip='%s'" % [_context_text(rotation), rotation.tooltip_text if rotation != null else ""])
	position = inspector.find_coord_editor_property(&"offset")
	if position != null:
		position.emit_changed(&"offset", Vector2(0.2, 0.0))
	await _wait_context(plugin)
	rotation = inspector.find_coord_editor_property(&"rotation")
	_check("circle_offset_removes_help", circle.coord.offset == Vector2(0.2, 0.0) and rotation != null and not rotation.is_read_only() and _context_text(rotation).is_empty(), "offset=%s hint='%s'" % [circle.coord.offset, _context_text(rotation)])
	_history_for(circle.coord).undo()
	await _wait_context(plugin)
	rotation = inspector.find_coord_editor_property(&"rotation")
	_check("circle_help_undo", circle.coord.offset == Vector2.ZERO and _context_contains(rotation, "Rotation has no effect"), "offset=%s hint='%s'" % [circle.coord.offset, _context_text(rotation)])
	for entry_id: String in ["generative/radial_gradient", "sdf/ring"]:
		var radial: GSTLayer = panel.get_stack_list().add_layer_by_entry_id(entry_id)
		panel.get_stack_list().select_layer(radial.id)
		await _wait_context(plugin)
		rotation = inspector.find_coord_editor_property(&"rotation")
		_check("%s_rotation_help" % entry_id.get_file(), rotation != null and not rotation.is_read_only() and _context_contains(rotation, "Rotation has no effect on this function"), "entry=%s hint='%s'" % [entry_id, _context_text(rotation)])
		movement = inspector.find_coord_editor_property(&"scroll")
		if movement != null:
			movement.emit_changed(&"scroll", Vector2(0.1, 0.0))
		await _wait_context(plugin)
		rotation = inspector.find_coord_editor_property(&"rotation")
		_check("%s_movement_removes_help" % entry_id.get_file(), radial.coord.scroll == Vector2(0.1, 0.0) and rotation != null and not rotation.is_read_only() and _context_text(rotation).is_empty(), "entry=%s movement=%s hint='%s'" % [entry_id, radial.coord.scroll, _context_text(rotation)])
		_history_for(radial.coord).undo()
		await _wait_context(plugin)
		rotation = inspector.find_coord_editor_property(&"rotation")
		_check("%s_help_undo" % entry_id.get_file(), radial.coord.scroll == Vector2.ZERO and _context_contains(rotation, "Rotation has no effect on this function"), "entry=%s movement=%s hint='%s'" % [entry_id, radial.coord.scroll, _context_text(rotation)])

	var threshold: GSTLayer = panel.get_stack_list().add_layer_by_entry_id("fieldops/smoothstep")
	panel.get_stack_list().select_layer(threshold.id)
	await _wait_context(plugin)
	var upper: EditorProperty = inspector.find_editor_property(&"edge1", threshold)
	if upper != null:
		upper.emit_changed(&"edge1", -0.1)
	await _wait_context(plugin)
	upper = inspector.find_editor_property(&"edge1", threshold)
	_check("clamped_threshold_help", float(threshold.get(&"edge1")) < float(threshold.get(&"edge0")) and upper != null and not upper.is_read_only() and _context_contains(upper, "sharp threshold"), "lower=%s upper=%s hint='%s'" % [threshold.get(&"edge0"), threshold.get(&"edge1"), _context_text(upper)])
	_history_for(threshold).undo()
	await _wait_context(plugin)
	upper = inspector.find_editor_property(&"edge1", threshold)
	_check("threshold_help_undo", _context_text(upper).is_empty() and float(threshold.get(&"edge1")) > float(threshold.get(&"edge0")), "hint='%s'" % _context_text(upper))
	panel.get_undo().set_output_alpha(threshold.id)
	await _wait_context(plugin)
	var lower: EditorProperty = inspector.find_editor_property(&"edge0", threshold)
	_check("alpha_threshold_help", _context_contains(lower, "controls transparency"), "alpha='%s' hint='%s'" % [panel.get_stack().output_alpha, _context_text(lower)])
	panel.get_watched_history().undo()
	await _wait_context(plugin)
	lower = inspector.find_editor_property(&"edge0", threshold)
	_check("alpha_threshold_help_undo", _context_text(lower).is_empty(), "alpha='%s' hint='%s'" % [panel.get_stack().output_alpha, _context_text(lower)])
	panel.get_stack_list().select_layer(source.id)
	await _wait_context(plugin)


func _wait_context(plugin: EditorPlugin) -> void:
	for i: int in range(4):
		await plugin.get_tree().process_frame


func _context_text(property: EditorProperty) -> String:
	if property == null:
		return ""
	var label: Label = property.get_meta(&"gst_context_label", null) as Label
	return label.text if label != null and label.visible else ""


func _context_contains(property: EditorProperty, fragment: String) -> bool:
	if property == null:
		return false
	var label: Label = property.get_meta(&"gst_context_label", null) as Label
	return label != null and label.visible and label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and label.text.contains(fragment)


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


func _check_native_palette_color(plugin: EditorPlugin, panel: GSTMainPanel, inspector: GSTInspectorColumn) -> void:
	panel.open_recipe("sprite_holographic")
	for i: int in range(5):
		await plugin.get_tree().process_frame
	var palette: GSTLayer = _find_layer_by_entry(panel.get_stack(), "color/palette")
	if palette == null:
		_check("palette_color_setup", false, "sprite_holographic palette layer is absent")
		return
	panel.get_stack_list().select_layer(palette.id)
	panel.set_narrow_tab(1)
	for i: int in range(4):
		await plugin.get_tree().process_frame
	var a_info: Dictionary = _find_property_info(palette, "a")
	var vectors: Array[String] = []
	for property_info: Dictionary in palette.get_property_list():
		if int(property_info.get("type", -1)) == TYPE_VECTOR3:
			vectors.append(String(property_info.get("name", "")))
	vectors.sort()
	var property: EditorProperty = inspector.find_editor_property(&"a", palette)
	var settings_scroll: ScrollContainer = inspector.get_settings_scroll()
	if property != null:
		settings_scroll.ensure_control_visible(property)
		for i: int in range(2):
			await plugin.get_tree().process_frame
	var color_button: ColorPickerButton = _find_color_button(property)
	var schema_ok: bool = int(a_info.get("type", -1)) == TYPE_COLOR and int(a_info.get("hint", -1)) == PROPERTY_HINT_COLOR_NO_ALPHA and vectors == ["b", "c", "d"]
	var button_visible: bool = color_button != null and color_button.is_visible_in_tree() and color_button.size.x > 0.0 and color_button.size.y > 0.0 and property.get_global_rect().intersects(settings_scroll.get_global_rect())
	_check("palette_color_native", schema_ok and button_visible and not color_button.edit_alpha, "a_type=%s hint=%s vectors=%s button=%s visible=%s edit_alpha=%s" % [a_info.get("type"), a_info.get("hint"), vectors, color_button != null, button_visible, color_button.edit_alpha if color_button != null else true])
	if color_button == null:
		return

	var screenshot_path: String = OS.get_environment("GST_UI_SCREENSHOT_PATH")
	if not screenshot_path.is_empty():
		await _save_screenshot(plugin, screenshot_path.get_basename() + "-palette-swatch.png", "screenshot_palette_swatch")
	color_button.grab_focus()
	await plugin.get_tree().process_frame
	_push_key(color_button, KEY_SPACE)
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var picker: ColorPicker = color_button.get_picker()
	var popup: PopupPanel = color_button.get_popup()
	var hex_edit: LineEdit = _find_hex_line_edit(picker)
	var popup_ready: bool = popup.visible and picker.visible and not picker.edit_alpha and hex_edit != null and hex_edit.is_visible_in_tree()
	var initial_fields: Array[String] = _visible_line_edit_texts(picker)
	var requested_hex: String = "3366cc"
	var actual_hex_control: bool = false
	var close_state: Dictionary = {"committed": false}
	var commit_observer: Callable = func(path: StringName, _value: Variant, _field: StringName, changing: bool) -> void:
		if path == &"a" and not changing:
			close_state["committed"] = true
	property.property_changed.connect(commit_observer)
	if hex_edit != null:
		hex_edit.grab_focus()
		await plugin.get_tree().process_frame
		actual_hex_control = hex_edit.has_focus() and hex_edit.is_visible_in_tree()
		await _replace_line_edit(plugin, hex_edit, requested_hex)
	popup.hide()
	# Complete the popup's focus exit before invoking editor-level undo.
	# Escape cancels this native picker and would discard the requested color.
	if hex_edit != null:
		hex_edit.release_focus()
	color_button.grab_focus()
	var close_deadline: int = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < close_deadline and (not close_state["committed"] or popup.visible or not color_button.has_focus()):
		await plugin.get_tree().process_frame
	property.property_changed.disconnect(commit_observer)
	var close_complete: bool = close_state["committed"] and not popup.visible and color_button.has_focus() and (hex_edit == null or not hex_edit.has_focus())
	_check("palette_color_close", close_complete, "committed=%s popup=%s button_focus=%s hex_focus=%s" % [close_state["committed"], popup.visible, color_button.has_focus(), hex_edit.has_focus() if hex_edit != null else false])
	var expected_color: Color = Color(0x33 / 255.0, 0x66 / 255.0, 0xcc / 255.0, 1.0)
	var expected_raw: Vector3 = Vector3(expected_color.r, expected_color.g, expected_color.b)
	var uniform_name: String = GSTUniformNames.param_uniform(palette.id, "palette", "a")
	var uniform_value: Variant = panel.get_shader_material().get_shader_parameter(uniform_name)
	var history: UndoRedo = _history_for(palette)
	var edit_applied: bool = close_complete and popup_ready and actual_hex_control and palette.params.get("a") is Vector3 and (palette.params.get("a") as Vector3).is_equal_approx(expected_raw) and palette.get(&"a") is Color and (palette.get(&"a") as Color).is_equal_approx(expected_color) and uniform_value is Vector3 and (uniform_value as Vector3).is_equal_approx(expected_raw) and history.has_undo()
	_check("palette_color_edit", edit_applied, "popup=%s hex=%s initial_fields=%s raw=%s displayed=%s uniform=%s history=%s" % [popup_ready, actual_hex_control, initial_fields, palette.params.get("a"), color_button.color, uniform_value, history.has_undo()])
	if not edit_applied:
		return

	history.undo()
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var undo_button: ColorPickerButton = _find_color_button(inspector.find_editor_property(&"a", palette))
	var undo_displayed: Color = undo_button.color if undo_button != null else Color.TRANSPARENT
	var undo_raw: Variant = palette.params.get("a")
	var undo_uniform: Variant = panel.get_shader_material().get_shader_parameter(uniform_name)
	var undo_ok: bool = undo_button != null and undo_raw is Vector3 and undo_uniform is Vector3 and (undo_button.color as Color).is_equal_approx(Color(0.5, 0.5, 0.5, 1.0)) and (undo_raw as Vector3).is_equal_approx(Vector3(0.5, 0.5, 0.5)) and (undo_uniform as Vector3).is_equal_approx(Vector3(0.5, 0.5, 0.5))
	history.redo()
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var redo_button: ColorPickerButton = _find_color_button(inspector.find_editor_property(&"a", palette))
	var redo_raw: Variant = palette.params.get("a")
	var redo_uniform: Variant = panel.get_shader_material().get_shader_parameter(uniform_name)
	var redo_ok: bool = redo_button != null and redo_raw is Vector3 and redo_uniform is Vector3 and (redo_button.color as Color).is_equal_approx(expected_color) and (redo_raw as Vector3).is_equal_approx(expected_raw) and (redo_uniform as Vector3).is_equal_approx(expected_raw)
	_check("palette_color_undo_redo", undo_ok and redo_ok, "undo=%s/%s/%s redo=%s/%s/%s" % [undo_displayed, undo_raw, undo_uniform, redo_button.color if redo_button != null else Color.TRANSPARENT, redo_raw, redo_uniform])

	var raw_before_randomize: Dictionary = palette.params.duplicate(true)
	var random_history: UndoRedo = panel.get_watched_history()
	panel.get_randomize_button().pressed.emit()
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var randomized_vectors: bool = _palette_raw_params_are_vectors(palette, true)
	if random_history.has_undo():
		random_history.undo()
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var random_undo_ok: bool = randomized_vectors and _palette_raw_params_are_vectors(palette, false) and palette.params == raw_before_randomize
	_check("palette_randomize_vectors", random_undo_ok, "randomized_vectors=%s restored=%s raw=%s" % [randomized_vectors, palette.params == raw_before_randomize, palette.params])

	var path: String = "user://gst_ui_labels_palette_color.tres"
	var saved: Dictionary = GSTStackIO.save(panel.get_stack(), path)
	if saved["ok"]:
		panel.open_path(path)
	for i: int in range(5):
		await plugin.get_tree().process_frame
	var opened: bool = saved["ok"] and panel.get_current_path() == path
	var loaded_palette: GSTLayer = _find_layer_by_entry(panel.get_stack(), "color/palette")
	if loaded_palette != null:
		panel.get_stack_list().select_layer(loaded_palette.id)
		panel.set_narrow_tab(1)
		for i: int in range(3):
			await plugin.get_tree().process_frame
	var loaded_button: ColorPickerButton = _find_color_button(inspector.find_editor_property(&"a", loaded_palette)) if loaded_palette != null else null
	var reopened_ok: bool = opened and loaded_palette != null and loaded_palette.params.get("a") is Vector3 and (loaded_palette.params.get("a") as Vector3).is_equal_approx(expected_raw) and loaded_button != null and loaded_button.color.is_equal_approx(expected_color)
	_check("palette_color_reopen", reopened_ok, "saved=%s opened=%s raw=%s displayed=%s" % [saved["ok"], opened, loaded_palette.params.get("a") if loaded_palette != null else null, loaded_button.color if loaded_button != null else Color.TRANSPARENT])
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _find_color_button(node: Node) -> ColorPickerButton:
	if node == null:
		return null
	if node is ColorPickerButton and (node as ColorPickerButton).is_visible_in_tree():
		return node as ColorPickerButton
	for child: Node in node.get_children(true):
		var found: ColorPickerButton = _find_color_button(child)
		if found != null:
			return found
	return null


func _find_hex_line_edit(picker: ColorPicker) -> LineEdit:
	var expected: String = picker.color.to_html(false).to_lower()
	for node: Node in picker.find_children("*", "LineEdit", true, false):
		var edit: LineEdit = node as LineEdit
		var normalized: String = edit.text.strip_edges().trim_prefix("#").to_lower()
		if edit.is_visible_in_tree() and edit.editable and normalized == expected:
			return edit
	return null


func _visible_line_edit_texts(picker: ColorPicker) -> Array[String]:
	var texts: Array[String] = []
	for node: Node in picker.find_children("*", "LineEdit", true, false):
		var edit: LineEdit = node as LineEdit
		if edit.is_visible_in_tree():
			texts.append(edit.text)
	return texts


func _replace_line_edit(plugin: EditorPlugin, edit: LineEdit, text: String) -> void:
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
	_push_key(edit, KEY_ENTER)
	for i: int in range(2):
		await plugin.get_tree().process_frame


func _push_key(target: Control, keycode: Key, ctrl: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.window_id = target.get_window().get_window_id()
	target.get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	target.get_viewport().push_input(event, true)


func _palette_raw_params_are_vectors(layer: GSTLayer, require_all: bool) -> bool:
	for name: String in ["a", "b", "c", "d"]:
		if require_all and not layer.params.has(name):
			return false
		if layer.params.has(name) and not (layer.params[name] is Vector3):
			return false
	return layer.params.has("a") and layer.params["a"] is Vector3


func _find_layer_by_entry(stack: GSTStack, entry_id: String) -> GSTLayer:
	for layer: GSTLayer in stack.layers:
		if layer.entry == entry_id:
			return layer
	return null


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
