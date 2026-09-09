@tool
extends RefCounted

var _pass_count: int = 0
var _fail_count: int = 0
var _plugin: EditorPlugin = null
var _last_numeric_activation: Dictionary = {}


func run(plugin: EditorPlugin) -> void:
	_plugin = plugin
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1366, 768))
	await _frames(5)
	await plugin.get_tree().create_timer(2.0).timeout
	var panel: GSTMainPanel = plugin.get_panel() as GSTMainPanel
	_check("panel", panel != null, "panel present=%s" % [panel != null])
	if panel == null:
		_finish()
		return

	EditorInterface.set_main_screen_editor("GoShade Turbo")
	plugin.get_window().grab_focus()
	await _frames(3)
	var required_methods: Array[StringName] = [
		&"is_start_screen_visible",
		&"get_start_recipe_button",
		&"get_create_empty_button",
		&"get_start_open_button",
		&"get_layer_menu",
		&"get_return_to_effect_button",
		&"get_preview_layer_id",
		&"get_preview_status_label",
		&"get_codegen_message_label",
	]
	var missing: Array[StringName] = []
	for method: StringName in required_methods:
		if not panel.has_method(method):
			missing.append(method)
	var solo_compatibility_present: bool = panel.has_method(&"get_solo_check")
	var api_ready: bool = missing.is_empty() and not solo_compatibility_present
	_check("phase5_api", api_ready, "missing=%s obsolete_get_solo_check=%s" % [missing, solo_compatibility_present])
	if not api_ready:
		_finish()
		return

	var metadata_before: Dictionary = panel.get_layout_metadata_snapshot()
	panel.restore_layout_metadata_snapshot({"main_ratio": 0.6, "inner_ratio": 0.42, "narrow_tab": 0, "sections": {}})
	await _frames(3)
	var picker: GSTPicker = panel.get_picker()
	var library: GSTLibrary = panel.get_library()
	var history: UndoRedo = panel.get_watched_history()
	var start_history_count: int = history.get_history_count()
	var recipe_names: Array[String] = _recipe_names()
	var cards_ok: bool = not recipe_names.is_empty()
	for recipe_name: String in recipe_names:
		var recipe_button: Button = panel.get_start_recipe_button(recipe_name)
		cards_ok = cards_ok and recipe_button != null and recipe_button.is_visible_in_tree()
	var start_controls_ok: bool = panel.get_start_open_button().is_visible_in_tree() and panel.get_create_empty_button().is_visible_in_tree()
	var initial_status_ok: bool = panel.get_preview_status_label().text == "No effect yet" and panel.get_codegen_message_label().text.is_empty()
	_check("initial_start", panel.is_start_screen_visible() and cards_ok and start_controls_ok and initial_status_ok, "recipes=%d controls=%s status='%s' codegen='%s'" % [recipe_names.size(), start_controls_ok, panel.get_preview_status_label().text, panel.get_codegen_message_label().text])
	_capture("initial")

	var entry_variant: String = OS.get_environment("GST_UI_COMPLETE_ENTRY").to_lower()
	if entry_variant.is_empty():
		entry_variant = "recipe"
	var entry_stack_path: String = "user://gst_ui_complete_entry_stack.tres"
	_cleanup([entry_stack_path])
	match entry_variant:
		"recipe":
			panel.get_start_recipe_button("fire").pressed.emit()
			await _frames(6)
			var entry_image: Image = panel.get_preview().get_viewport_image()
			_check("entry_recipe", not panel.is_start_screen_visible() and panel.get_stack().layers.size() == 5 and history.get_history_count() == start_history_count + 1 and GSTShaderCompile.compiles(panel.get_shader_material().shader.code) and _image_is_nonuniform(entry_image), "start=%s layers=%d history=%d compile=%s nonuniform=%s" % [panel.is_start_screen_visible(), panel.get_stack().layers.size(), history.get_history_count(), GSTShaderCompile.compiles(panel.get_shader_material().shader.code), _image_is_nonuniform(entry_image)])
		"empty":
			panel.get_create_empty_button().pressed.emit()
			await _frames(3)
			var empty_started: bool = not panel.is_start_screen_visible() and panel.is_picker_open() and panel.get_stack().layers.is_empty() and history.get_history_count() == start_history_count + 1
			_check("entry_empty", empty_started and panel.get_preview_status_label().text == "No effect yet" and panel.get_codegen_message_label().text.is_empty(), "start=%s picker=%s history=%d status='%s'" % [panel.is_start_screen_visible(), panel.is_picker_open(), history.get_history_count(), panel.get_preview_status_label().text])
			_key(KEY_ESCAPE)
			await _frames(3)
		"open":
			var entry_loaded: Dictionary = GSTStackIO.load("res://addons/goshade_turbo/recipes/fire.tres", library)
			var entry_saved: Dictionary = GSTStackIO.save(entry_loaded["stack"], entry_stack_path) if entry_loaded["ok"] else {"ok": false}
			panel.get_start_open_button().pressed.emit()
			await _frames(2)
			var dialog_visible: bool = panel._open_dialog.visible
			panel._open_dialog.hide()
			panel._open_dialog.file_selected.emit(entry_stack_path)
			await _frames(6)
			_check("entry_open", entry_saved["ok"] and dialog_visible and not panel.is_start_screen_visible() and panel.get_stack().layers.size() == 5 and panel.get_current_path() == entry_stack_path and history.get_history_count() == start_history_count + 1 and GSTShaderCompile.compiles(panel.get_shader_material().shader.code), "saved=%s dialog=%s start=%s layers=%d path='%s' history=%d" % [entry_saved["ok"], dialog_visible, panel.is_start_screen_visible(), panel.get_stack().layers.size(), panel.get_current_path(), history.get_history_count()])
		_:
			_check("entry_variant", false, "GST_UI_COMPLETE_ENTRY must be recipe, empty, or open; got '%s'" % entry_variant)
			_cleanup([entry_stack_path])
			_finish()
			return

	if panel.is_picker_open():
		_key(KEY_ESCAPE)
		await _frames(2)
	history.undo()
	await _frames(5)
	var empty_stack: GSTStack = panel.get_stack()
	var add_button: Button = panel.get_stack_list().get_node("%AddButton") as Button
	_check("entry_undo_ordinary_empty", empty_stack.layers.is_empty() and not panel.is_start_screen_visible() and not history.has_undo() and add_button.is_visible_in_tree() and not add_button.disabled and panel.get_preview_status_label().text == "No effect yet", "variant='%s' start=%s has_undo=%s add=%s/%s status='%s'" % [entry_variant, panel.is_start_screen_visible(), history.has_undo(), add_button.is_visible_in_tree(), add_button.disabled, panel.get_preview_status_label().text])
	_cleanup([entry_stack_path])

	var before_new: GSTStack = panel.get_stack()
	(panel.get_node("%FileMenu") as MenuButton).get_popup().id_pressed.emit(0)
	await _frames(2)
	_check("file_new_library", panel.get_stack() != before_new and panel.get_stack().layers.is_empty() and panel.is_picker_open(), "new_instance=%s picker=%s" % [panel.get_stack() != before_new, panel.is_picker_open()])
	picker.cancelled.emit()
	await _frames(2)
	empty_stack = panel.get_stack()
	_check("cancelled_first_library", not panel.is_picker_open() and empty_stack.layers.is_empty() and add_button.is_visible_in_tree() and not add_button.disabled and panel.get_preview_status_label().text == "No effect yet", "picker=%s add_visible=%s add_disabled=%s status='%s'" % [panel.is_picker_open(), add_button.is_visible_in_tree(), add_button.disabled, panel.get_preview_status_label().text])

	var recipe_history_before: int = history.get_history_count()
	(panel.get_node("%RecipesButton") as Button).pressed.emit()
	await _frames(2)
	picker.activate_value("fire")
	await _frames(6)
	var recipe_stack: GSTStack = panel.get_stack()
	var first_image: Image = panel.get_preview().get_viewport_image()
	var recipe_rendered: bool = recipe_stack.layers.size() == 5 and not panel.is_start_screen_visible() and not panel.is_picker_open() and panel.get_shader_material().shader != null and GSTShaderCompile.compiles(panel.get_shader_material().shader.code) and _image_is_nonuniform(first_image)
	_check("recipe_first_render", recipe_rendered and history.get_history_count() == recipe_history_before + 1, "layers=%d history=%d->%d compile=%s nonuniform=%s" % [recipe_stack.layers.size(), recipe_history_before, history.get_history_count(), panel.get_shader_material().shader != null and GSTShaderCompile.compiles(panel.get_shader_material().shader.code), _image_is_nonuniform(first_image)])
	history.undo()
	await _frames(4)
	_check("recipe_one_action_undo", panel.get_stack() == empty_stack and panel.get_stack().layers.is_empty() and not panel.is_start_screen_visible() and panel.get_preview_status_label().text == "No effect yet", "same_empty=%s start=%s status='%s'" % [panel.get_stack() == empty_stack, panel.is_start_screen_visible(), panel.get_preview_status_label().text])
	history.redo()
	await _frames(5)
	recipe_stack = panel.get_stack()
	_check("recipe_redo", recipe_stack.layers.size() == 5 and panel.get_codegen_message_label().text.is_empty() and not panel.get_randomize_button().disabled, "layers=%d codegen='%s' randomize_disabled=%s" % [recipe_stack.layers.size(), panel.get_codegen_message_label().text, panel.get_randomize_button().disabled])

	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	inspector.set_section_states({})
	var fbm: GSTLayer = _find_layer(recipe_stack, "generative/fbm")
	panel.get_stack_list().select_layer(fbm.id)
	panel.set_narrow_tab(1)
	await _frames(4)
	var settings_scroll: ScrollContainer = inspector.get_settings_scroll()
	var gain_property: EditorProperty = inspector.find_editor_property(&"gain", fbm)
	if gain_property != null:
		settings_scroll.ensure_control_visible(gain_property)
		await _frames(2)
	var old_gain: float = float(fbm.get("gain"))
	var new_gain: float = 0.61
	var gain_edit: LineEdit = await _activate_numeric_line_edit(gain_property)
	var gain_visible: bool = gain_edit != null and gain_edit.is_visible_in_tree() and gain_edit.has_focus() and _inside(gain_edit.get_global_rect(), settings_scroll.get_global_rect())
	if gain_edit != null:
		await _replace_line_edit(gain_edit, str(new_gain))
	await _frames(3)
	var gain_uniform: String = GSTUniformNames.param_uniform(fbm.id, "fbm", "gain")
	var gain_history: UndoRedo = _history_for(fbm)
	var gain_applied: bool = gain_property != null and gain_visible and is_equal_approx(float(fbm.get("gain")), new_gain) and is_equal_approx(float(panel.get_shader_material().get_shader_parameter(gain_uniform)), new_gain) and gain_history.has_undo()
	_capture("recipe-edit")
	if gain_applied:
		gain_history.undo()
	await _frames(3)
	_check("native_param_undo", gain_applied and is_equal_approx(float(fbm.get("gain")), old_gain) and is_equal_approx(float(panel.get_shader_material().get_shader_parameter(gain_uniform)), old_gain), "applied=%s value=%s uniform=%s expected=%s" % [gain_applied, fbm.get("gain"), panel.get_shader_material().get_shader_parameter(gain_uniform), old_gain])

	var offset_property: EditorProperty = inspector.find_coord_editor_property(&"offset")
	if offset_property != null:
		settings_scroll.ensure_control_visible(offset_property)
		await _frames(2)
	var old_offset: Vector2 = fbm.coord.offset
	var new_offset: Vector2 = Vector2(0.17, old_offset.y)
	var offset_edit: LineEdit = await _activate_numeric_line_edit(offset_property)
	var offset_visible: bool = offset_edit != null and offset_edit.is_visible_in_tree() and offset_edit.has_focus() and _inside(offset_edit.get_global_rect(), settings_scroll.get_global_rect())
	if offset_edit != null:
		await _replace_line_edit(offset_edit, str(new_offset.x))
	await _frames(3)
	var offset_uniform: String = GSTUniformNames.coord_offset(fbm.id)
	var offset_history: UndoRedo = _history_for(fbm.coord)
	var offset_model_after: Vector2 = fbm.coord.offset
	var offset_uniform_after: Vector2 = panel.get_shader_material().get_shader_parameter(offset_uniform) as Vector2
	var offset_has_undo: bool = offset_history.has_undo()
	var offset_applied: bool = offset_property != null and offset_visible and offset_model_after.is_equal_approx(new_offset) and offset_uniform_after.is_equal_approx(new_offset) and offset_has_undo
	var offset_edit_after: String = offset_edit.text if offset_edit != null else "missing"
	if offset_applied:
		offset_history.undo()
	await _frames(3)
	_check("native_coord_undo", offset_applied and fbm.coord.offset.is_equal_approx(old_offset) and (panel.get_shader_material().get_shader_parameter(offset_uniform) as Vector2).is_equal_approx(old_offset), "applied=%s visible=%s activation=%s typed='%s' before=%s requested=%s applied_model=%s applied_uniform=%s has_undo=%s final_model=%s final_uniform=%s" % [offset_applied, offset_visible, _last_numeric_activation, offset_edit_after, old_offset, new_offset, offset_model_after, offset_uniform_after, offset_has_undo, fbm.coord.offset, panel.get_shader_material().get_shader_parameter(offset_uniform)])

	var params_before: Dictionary = _snapshot_params(recipe_stack, library)
	var raw_params_before: Dictionary = _snapshot_raw_params(recipe_stack)
	var random_code_before: String = panel.get_shader_material().shader.code
	var uniforms_before: Dictionary = _snapshot_param_uniforms(recipe_stack, panel.get_shader_material(), library)
	var random_history_before: int = history.get_history_count()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 55291
	panel.set_randomize_rng(rng)
	panel.get_randomize_button().pressed.emit()
	await _frames(3)
	var randomized: bool = _snapshot_params(recipe_stack, library) != params_before
	var one_random_action: bool = history.get_history_count() == random_history_before + 1
	if randomized and one_random_action and history.has_undo():
		history.undo()
	await _frames(3)
	var random_values_restored: bool = _snapshot_params(recipe_stack, library) == params_before
	var raw_params_after: Dictionary = _snapshot_raw_params(recipe_stack)
	var random_code_after: String = panel.get_shader_material().shader.code
	var random_raw_restored: bool = raw_params_after == raw_params_before
	var random_code_restored: bool = random_code_after == random_code_before
	var random_uniforms_restored: bool = _snapshot_param_uniforms(recipe_stack, panel.get_shader_material(), library) == uniforms_before
	var code_difference: Dictionary = _first_differing_line(random_code_before, random_code_after)
	_check("randomize_undo", randomized and one_random_action and random_values_restored and random_raw_restored and random_code_restored and random_uniforms_restored, "randomized=%s one_action=%s values=%s raw=%s code=%s uniforms=%s first_difference=%s" % [randomized, one_random_action, random_values_restored, random_raw_restored, random_code_restored, random_uniforms_restored, code_difference])

	var multiply: GSTLayer = _find_layer(recipe_stack, "fieldops/multiply")
	var gradient: GSTLayer = _find_layer(recipe_stack, "generative/linear_gradient")
	panel.get_stack_list().select_layer(multiply.id)
	await _frames(3)
	inspector.get_input_button("a").pressed.emit()
	await _frames(2)
	panel._on_picker_choice({"value": String(multiply.id)})
	await _frames(2)
	var refusal_reason: String = (picker.get_node("%Refusal") as Label).text
	var refusal_open: bool = panel.is_picker_open() and not refusal_reason.is_empty()
	picker.cancelled.emit()
	await _frames(2)
	_check("local_refusal", refusal_open and _visible_text(inspector, refusal_reason) and panel.get_codegen_message_label().text.is_empty(), "reason='%s' local=%s codegen='%s'" % [refusal_reason, _visible_text(inspector, refusal_reason), panel.get_codegen_message_label().text])
	panel.get_output_block().get_alpha_button().pressed.emit()
	await _frames(1)
	picker.activate_value("none")
	await _frames(3)
	_check("unrelated_success_keeps_refusal", _visible_text(inspector, refusal_reason) and panel.get_codegen_message_label().text.is_empty(), "local=%s codegen='%s'" % [_visible_text(inspector, refusal_reason), panel.get_codegen_message_label().text])
	inspector.get_input_button("a").pressed.emit()
	await _frames(1)
	picker.activate_value(String(gradient.id))
	await _frames(3)
	_check("valid_retry_clears_refusal", multiply.slots.get("a", &"") == gradient.id and not _visible_text(inspector, refusal_reason) and not panel.is_picker_open(), "wired='%s' refusal_visible=%s" % [String(multiply.slots.get("a", &"")), _visible_text(inspector, refusal_reason)])

	var retained_material: ShaderMaterial = panel.get_shader_material()
	var retained_code: String = retained_material.shader.code
	var retained_gain: Variant = retained_material.get_shader_parameter(gain_uniform)
	var broken_layer: GSTLayer = GSTStackOps.add_layer(recipe_stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	panel.stack_changed.emit()
	await _frames(3)
	var failure_after_success: bool = not panel.get_codegen_message_label().text.is_empty() and panel.get_preview_status_label().text == "Showing last successful preview" and panel.get_shader_material() == retained_material and panel.get_shader_material().shader.code == retained_code and panel.get_shader_material().get_shader_parameter(gain_uniform) == retained_gain
	_check("failure_after_success", failure_after_success, "error='%s' status='%s' same_material=%s code_retained=%s uniform_retained=%s" % [panel.get_codegen_message_label().text, panel.get_preview_status_label().text, panel.get_shader_material() == retained_material, panel.get_shader_material().shader.code == retained_code, panel.get_shader_material().get_shader_parameter(gain_uniform) == retained_gain])
	_capture("recovery")
	panel.get_output_block().get_alpha_button().pressed.emit()
	await _frames(1)
	picker.activate_value("")
	await _frames(3)
	_check("successful_edit_keeps_codegen_error", not panel.get_codegen_message_label().text.is_empty() and panel.get_preview_status_label().text == "Showing last successful preview", "error='%s' status='%s'" % [panel.get_codegen_message_label().text, panel.get_preview_status_label().text])
	GSTStackOps.remove_layer(recipe_stack, broken_layer.id, library)
	panel.stack_changed.emit()
	await _frames(4)
	_check("repair_clears_codegen_error", panel.get_codegen_message_label().text.is_empty() and panel.get_preview_status_label().text.is_empty() and panel.get_shader_material() == retained_material, "error='%s' status='%s' same_material=%s" % [panel.get_codegen_message_label().text, panel.get_preview_status_label().text, panel.get_shader_material() == retained_material])

	var successful_image: Image = panel.get_preview().get_viewport_image()
	var successful_material: ShaderMaterial = panel.get_shader_material()
	var broken_stack: GSTStack = GSTStack.new()
	var long_broken_layer: GSTLayer = GSTStackOps.add_layer(broken_stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	long_broken_layer.id = &"this_is_an_intentionally_long_stable_layer_id_that_verifies_codegen_error_wrapping_inside_the_preview_column_without_expanding_or_covering_the_final_output_controls"
	panel.replace_stack(broken_stack, "", false)
	await _frames(5)
	var blank_image: Image = panel.get_preview().get_viewport_image()
	var codegen_label: Label = panel.get_codegen_message_label()
	var error_scroll: ScrollContainer = panel.get_node("%ErrorScroll") as ScrollContainer
	var preview_area: Control = panel.get_node("%PreviewArea") as Control
	var output_block: Control = panel.get_output_block()
	var measurements: Dictionary = panel.get_layout_measurements()
	var preview_minimum: Vector2 = measurements["preview_minimum"]
	var preview_rect: Rect2 = measurements["preview_rect"]
	var wrapped_lines_fit: bool = _smart_wrapped_lines_fit(codegen_label)
	var long_error_geometry: bool = codegen_label.text.length() >= 120 and codegen_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and wrapped_lines_fit and codegen_label.is_visible_in_tree() and codegen_label.size.x <= error_scroll.size.x + 2.0 and _inside(panel.get_global_rect(), measurements["host_rect"]) and _inside(error_scroll.get_global_rect(), preview_area.get_global_rect()) and _inside(output_block.get_global_rect(), preview_area.get_global_rect()) and not error_scroll.get_global_rect().intersects(output_block.get_global_rect()) and preview_rect.size.x >= preview_minimum.x and preview_rect.size.y >= preview_minimum.y
	var fresh_failure: bool = panel.get_shader_material() != successful_material and panel.get_shader_material().shader.code.contains("COLOR = vec4(0.0)") and not codegen_label.text.is_empty() and panel.get_preview_status_label().text != "Showing last successful preview" and not _images_equal(successful_image, blank_image)
	_check("broken_installation_cache", fresh_failure, "new_material=%s safe_code=%s error_length=%d status='%s' image_changed=%s" % [panel.get_shader_material() != successful_material, panel.get_shader_material().shader.code.contains("COLOR = vec4(0.0)"), codegen_label.text.length(), panel.get_preview_status_label().text, not _images_equal(successful_image, blank_image)])
	_check("long_error_geometry", long_error_geometry, "label=%s scroll=%s preview=%s output=%s wrap=%d lines=%d lines_fit=%s" % [codegen_label.get_global_rect(), error_scroll.get_global_rect(), preview_area.get_global_rect(), output_block.get_global_rect(), codegen_label.autowrap_mode, codegen_label.get_line_count(), wrapped_lines_fit])
	_capture("long-error")
	history.undo()
	await _frames(5)
	recipe_stack = panel.get_stack()
	_check("broken_installation_undo", recipe_stack.layers.size() == 5 and panel.get_codegen_message_label().text.is_empty() and not panel.is_start_screen_visible() and GSTShaderCompile.compiles(panel.get_shader_material().shader.code), "layers=%d error='%s' start=%s" % [recipe_stack.layers.size(), panel.get_codegen_message_label().text, panel.is_start_screen_visible()])

	var stack_path: String = "user://gst_ui_complete_stack.tres"
	var export_path: String = "user://gst_ui_complete_shader.gdshader"
	_cleanup([stack_path, export_path])
	var saved: Dictionary = GSTStackIO.save(recipe_stack, stack_path)
	fbm = _find_layer(recipe_stack, "generative/fbm")
	multiply = _find_layer(recipe_stack, "fieldops/multiply")
	panel.get_stack_list().select_layer(fbm.id)
	await _frames(2)
	var finished_code: String = GSTCodegen.generate(recipe_stack, library)
	var output_color_before: StringName = recipe_stack.output_color
	var output_alpha_before: StringName = recipe_stack.output_alpha
	var diagnostic_history: int = history.get_history_count()
	panel.get_layer_menu().get_popup().id_pressed.emit(0)
	await _frames(3)
	var diagnostic_id: StringName = panel.get_preview_layer_id()
	var heading: Label = panel.get_node("%PreviewHeading") as Label
	panel.get_stack_list().select_layer(multiply.id)
	await _frames(2)
	var stable_selection: bool = panel.get_preview_layer_id() == diagnostic_id
	(panel.get_node("%ExportButton") as Button).pressed.emit()
	await _frames(2)
	var export_dialog_visible: bool = panel._export_dialog.visible
	panel._export_dialog.hide()
	panel._export_dialog.file_selected.emit(export_path)
	await _frames(2)
	var exported_text: String = _read_file(export_path)
	var reopened_export: Dictionary = GSTExport.reopen(export_path, library)
	var diagnostic_ok: bool = diagnostic_id == fbm.id and panel.get_return_to_effect_button().is_visible_in_tree() and heading.text.contains(String(fbm.id)) and stable_selection and recipe_stack.output_color == output_color_before and recipe_stack.output_alpha == output_alpha_before and history.get_history_count() == diagnostic_history
	var export_unchanged: bool = export_dialog_visible and not exported_text.is_empty() and GSTShaderCompile.compiles(exported_text) and reopened_export["ok"] and (reopened_export["stack"] as GSTStack).output_color == output_color_before and (reopened_export["stack"] as GSTStack).output_alpha == output_alpha_before and exported_text.contains(_output_line(finished_code))
	_check("diagnostic_view", diagnostic_ok, "preview_id='%s' heading='%s' stable=%s output='%s'/'%s' history=%d" % [String(diagnostic_id), heading.text, stable_selection, String(recipe_stack.output_color), String(recipe_stack.output_alpha), history.get_history_count()])
	_check("diagnostic_export_unchanged", export_unchanged, "saved=%s bytes=%d compile=%s outputs='%s'/'%s'" % [saved["ok"], exported_text.length(), GSTShaderCompile.compiles(exported_text), String((reopened_export["stack"] as GSTStack).output_color) if reopened_export["ok"] else "missing", String((reopened_export["stack"] as GSTStack).output_alpha) if reopened_export["ok"] else "missing"])
	_capture("diagnostic")
	panel.get_return_to_effect_button().pressed.emit()
	await _frames(3)
	_check("return_to_effect", panel.get_preview_layer_id() == &"" and not panel.get_return_to_effect_button().visible and panel.get_shader_material().shader.code == finished_code and history.get_history_count() == diagnostic_history, "preview_id='%s' return_visible=%s code_restored=%s history=%d" % [String(panel.get_preview_layer_id()), panel.get_return_to_effect_button().visible, panel.get_shader_material().shader.code == finished_code, history.get_history_count()])
	panel.get_stack_list().select_layer(fbm.id)
	panel.get_layer_menu().get_popup().id_pressed.emit(0)
	await _frames(2)

	var material_before_reopen: ShaderMaterial = panel.get_shader_material()
	(panel.get_node("%FileMenu") as MenuButton).get_popup().id_pressed.emit(3)
	await _frames(2)
	var reopen_dialog_visible: bool = panel._reopen_shader_dialog.visible
	panel._reopen_shader_dialog.hide()
	panel._reopen_shader_dialog.file_selected.emit(export_path)
	await _frames(5)
	_check("reopen_compiles", reopen_dialog_visible and panel.get_preview_layer_id() == &"" and panel.get_shader_material() != material_before_reopen and GSTShaderCompile.compiles(panel.get_shader_material().shader.code) and panel.get_codegen_message_label().text.is_empty(), "dialog=%s preview_id='%s' new_material=%s compile=%s error='%s'" % [reopen_dialog_visible, String(panel.get_preview_layer_id()), panel.get_shader_material() != material_before_reopen, GSTShaderCompile.compiles(panel.get_shader_material().shader.code), panel.get_codegen_message_label().text])
	(panel.get_node("%FileMenu") as MenuButton).get_popup().id_pressed.emit(1)
	await _frames(2)
	var saved_open_dialog_visible: bool = panel._open_dialog.visible
	panel._open_dialog.hide()
	panel._open_dialog.file_selected.emit(stack_path)
	await _frames(5)
	_check("open_saved_stack", saved_open_dialog_visible and panel.get_stack().layers.size() == 5 and panel.get_current_path() == stack_path and GSTShaderCompile.compiles(panel.get_shader_material().shader.code) and not panel.is_start_screen_visible(), "dialog=%s layers=%d path='%s' compile=%s start=%s" % [saved_open_dialog_visible, panel.get_stack().layers.size(), panel.get_current_path(), GSTShaderCompile.compiles(panel.get_shader_material().shader.code), panel.is_start_screen_visible()])

	fbm = _find_layer(panel.get_stack(), "generative/fbm")
	panel.get_stack_list().select_layer(fbm.id)
	await _frames(2)
	panel.get_layer_menu().get_popup().id_pressed.emit(0)
	await _frames(2)
	panel.get_undo().remove_layer(fbm.id)
	await _frames(4)
	_check("diagnostic_deletion", panel.get_preview_layer_id() == &"" and not panel.get_return_to_effect_button().visible, "preview_id='%s' return_visible=%s" % [String(panel.get_preview_layer_id()), panel.get_return_to_effect_button().visible])

	panel._on_new_pressed()
	await _frames(2)
	var new_material: ShaderMaterial = panel.get_shader_material()
	var installation_cleared: bool = panel.get_preview_layer_id() == &"" and panel.get_stack().layers.is_empty() and panel.get_preview_status_label().text == "No effect yet" and new_material != material_before_reopen
	_check("new_installation", installation_cleared and panel.is_picker_open(), "preview_id='%s' layers=%d status='%s' new_material=%s picker=%s" % [String(panel.get_preview_layer_id()), panel.get_stack().layers.size(), panel.get_preview_status_label().text, new_material != material_before_reopen, panel.is_picker_open()])
	picker.cancelled.emit()
	await _frames(2)

	_cleanup([stack_path, export_path])
	panel.restore_layout_metadata_snapshot(metadata_before)
	_finish()


func _frames(count: int) -> void:
	for i: int in range(count):
		await _plugin.get_tree().process_frame


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


func _replace_line_edit(edit: LineEdit, text: String) -> void:
	edit.grab_focus()
	await _frames(1)
	_key(KEY_A, true)
	for index: int in range(text.length()):
		var event: InputEventKey = InputEventKey.new()
		event.unicode = text.unicode_at(index)
		event.pressed = true
		event.window_id = _plugin.get_window().get_window_id()
		_plugin.get_viewport().push_input(event, true)
		event = event.duplicate()
		event.pressed = false
		_plugin.get_viewport().push_input(event, true)
	_key(KEY_ENTER)
	await _frames(2)


func _activate_numeric_line_edit(root: Node) -> LineEdit:
	_last_numeric_activation = {
		"property_class": root.get_class() if root != null else "missing",
		"property_rect": (root as Control).get_global_rect() if root is Control else Rect2(),
	}
	if root == null:
		return null
	var spin: Control = _first_editor_spin(root)
	_last_numeric_activation["spin_class"] = spin.get_class() if spin != null else "missing"
	_last_numeric_activation["spin_rect"] = spin.get_global_rect() if spin != null else Rect2()
	if spin == null or not spin.is_visible_in_tree() or spin.size.x <= 0.0 or spin.size.y <= 0.0:
		return null
	var point: Vector2 = spin.get_global_rect().get_center()
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_plugin.get_viewport().push_input(press, true)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	_plugin.get_viewport().push_input(release, true)
	await _frames(2)
	var focus: Control = _plugin.get_viewport().gui_get_focus_owner()
	_last_numeric_activation["focus_class"] = focus.get_class() if focus != null else "missing"
	_last_numeric_activation["focus_rect"] = focus.get_global_rect() if focus != null else Rect2()
	_last_numeric_activation["focus_text"] = (focus as LineEdit).text if focus is LineEdit else ""
	_last_numeric_activation["focus_visible"] = focus.is_visible_in_tree() if focus != null else false
	return focus as LineEdit if focus is LineEdit and focus.is_visible_in_tree() else null


func _first_editor_spin(root: Node) -> Control:
	if root is Control and root.get_class() == "EditorSpinSlider" and (root as Control).is_visible_in_tree():
		return root as Control
	for child: Node in root.get_children(true):
		var found: Control = _first_editor_spin(child)
		if found != null:
			return found
	return null


func _capture(suffix: String) -> void:
	var base_path: String = OS.get_environment("GST_UI_COMPLETE_SCREENSHOT")
	if base_path.is_empty():
		return
	var path: String = "%s-%s.png" % [base_path.get_basename(), suffix]
	var error: Error = _plugin.get_viewport().get_texture().get_image().save_png(path)
	_check("screenshot_" + suffix, error == OK, "path='%s' error=%d" % [path, error])


func _recipe_names() -> Array[String]:
	var names: Array[String] = []
	var dir: DirAccess = DirAccess.open("res://addons/goshade_turbo/recipes")
	if dir == null:
		return names
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while not entry_name.is_empty():
		if not dir.current_is_dir() and entry_name.ends_with(".tres"):
			names.append(entry_name.get_basename())
		entry_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


func _find_layer(stack: GSTStack, entry_id: String) -> GSTLayer:
	for layer: GSTLayer in stack.layers:
		if layer.entry == entry_id:
			return layer
	return null


func _history_for(object: Object) -> UndoRedo:
	var manager: EditorUndoRedoManager = _plugin.get_undo_redo()
	return manager.get_history_undo_redo(manager.get_object_history_id(object))


func _snapshot_params(stack: GSTStack, library: GSTLibrary) -> Dictionary:
	var snapshot: Dictionary = {}
	for layer: GSTLayer in stack.layers:
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		if entry == null or entry.params.is_empty():
			continue
		var values: Dictionary = {}
		for param: Dictionary in entry.params:
			var param_name: StringName = StringName(param["name"])
			values[param_name] = layer.get(param_name)
		snapshot[layer.id] = values
	return snapshot


func _snapshot_param_uniforms(stack: GSTStack, material: ShaderMaterial, library: GSTLibrary) -> Dictionary:
	var snapshot: Dictionary = {}
	for layer: GSTLayer in stack.layers:
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		if entry == null:
			continue
		for param: Dictionary in entry.params:
			var param_name: String = String(param["name"])
			var uniform_name: String = GSTUniformNames.param_uniform(layer.id, entry.function, param_name)
			snapshot[uniform_name] = material.get_shader_parameter(uniform_name)
	return snapshot


func _snapshot_raw_params(stack: GSTStack) -> Dictionary:
	var snapshot: Dictionary = {}
	for layer: GSTLayer in stack.layers:
		snapshot[layer.id] = layer.params.duplicate(true)
	return snapshot


func _first_differing_line(before: String, after: String) -> Dictionary:
	var before_lines: PackedStringArray = before.split("\n")
	var after_lines: PackedStringArray = after.split("\n")
	var line_count: int = maxi(before_lines.size(), after_lines.size())
	for index: int in range(line_count):
		var before_line: String = before_lines[index] if index < before_lines.size() else "<missing>"
		var after_line: String = after_lines[index] if index < after_lines.size() else "<missing>"
		if before_line != after_line:
			return {"line": index + 1, "before": before_line, "after": after_line}
	return {}


func _smart_wrapped_lines_fit(label: Label) -> bool:
	if label == null or label.size.x <= 0.0:
		return false
	var paragraph: TextParagraph = TextParagraph.new()
	paragraph.set_width(label.size.x)
	paragraph.set_break_flags(TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	paragraph.add_string(label.text, label.get_theme_font("font"), label.get_theme_font_size("font_size"))
	if paragraph.get_line_count() < 2:
		return false
	for line: int in range(paragraph.get_line_count()):
		if paragraph.get_line_width(line) > label.size.x + 1.0:
			return false
	return true


func _visible_text(root: Node, text: String) -> bool:
	if text.is_empty():
		return false
	for node: Node in root.find_children("*", "Label", true, false):
		if node is Label and node.is_visible_in_tree() and node.text == text:
			return true
	return false


func _image_is_nonuniform(image: Image) -> bool:
	if image == null or image.get_width() == 0 or image.get_height() == 0:
		return false
	var first: Color = image.get_pixel(0, 0)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if not image.get_pixel(x, y).is_equal_approx(first):
				return true
	return false


func _images_equal(a: Image, b: Image) -> bool:
	return a != null and b != null and a.get_size() == b.get_size() and a.get_data() == b.get_data()


func _inside(inner: Rect2, outer: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 1.0 and inner.position.y >= outer.position.y - 1.0 and inner.end.x <= outer.end.x + 1.0 and inner.end.y <= outer.end.y + 1.0


func _output_line(code: String) -> String:
	for line: String in code.split("\n"):
		if line.strip_edges().begins_with("COLOR ="):
			return line.strip_edges()
	return ""


func _read_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _cleanup(paths: Array[String]) -> void:
	for path: String in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(item: String, passed: bool, detail: String) -> void:
	if passed:
		_pass_count += 1
	else:
		_fail_count += 1
	print("UI_COMPLETE %s %s %s" % [item, "PASS" if passed else "FAIL", detail])


func _finish() -> void:
	print("UI_COMPLETE SUMMARY pass=%d fail=%d" % [_pass_count, _fail_count])
	_plugin.get_tree().quit(1 if _fail_count > 0 else 0)
