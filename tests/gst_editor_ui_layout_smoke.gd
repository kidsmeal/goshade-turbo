@tool
extends RefCounted

var _pass_count: int = 0
var _fail_count: int = 0


func run(plugin: EditorPlugin) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1366, 768))
	for i: int in range(5):
		await plugin.get_tree().process_frame
	EditorInterface.set_main_screen_editor("GoShade Turbo")
	for i: int in range(4):
		await plugin.get_tree().process_frame

	var panel: GSTMainPanel = plugin.get_panel() as GSTMainPanel
	_check("panel", panel != null and panel.visible, "active GoShade Turbo panel is visible")
	if panel == null:
		_finish(plugin)
		return
	panel.get_create_empty_button().pressed.emit()
	await plugin.get_tree().process_frame
	panel.get_picker().cancelled.emit()
	await plugin.get_tree().process_frame
	var metadata_before: Dictionary = panel.get_layout_metadata_snapshot()
	panel.restore_layout_metadata_snapshot({"main_ratio": 0.6, "inner_ratio": 0.42, "narrow_tab": 0, "sections": {}})
	for i: int in range(5):
		await plugin.get_tree().process_frame

	var host: Control = panel.get_parent() as Control
	var baseline_preview: Control = panel.get_node("%Preview") as Control
	var baseline_output: Control = panel.get_node("%OutputBlock") as Control
	print("UI_LAYOUT BASELINE window=%s host=%s root=%s flags=%d/%d preview=%s output=%s" % [DisplayServer.window_get_size(), host.get_global_rect(), panel.get_global_rect(), panel.size_flags_horizontal, panel.size_flags_vertical, baseline_preview.get_global_rect(), baseline_output.get_global_rect()])
	var baseline_full_height: bool = absf(host.size.y - panel.size.y) <= 2.0 and panel.size_flags_vertical == Control.SIZE_EXPAND_FILL
	_check("baseline_full_height", baseline_full_height, "host=%s root=%s flags=%d/%d" % [host.get_global_rect(), panel.get_global_rect(), panel.size_flags_horizontal, panel.size_flags_vertical])
	if not panel.has_method("get_layout_measurements"):
		_check("layout_api", false, "phase 1 layout measurement API is absent")
		_finish(plugin)
		return

	var measured: Dictionary = panel.get_layout_measurements()
	_print_measurements(measured)
	_check_full_height(panel, measured)
	_check_default_allocation(measured)
	_check_preview_and_output(measured)
	await _check_file_menu(plugin, panel)
	await _check_section_persistence(plugin, panel)
	await _check_split_persistence(plugin, panel)
	await _check_responsive_tabs(plugin, panel, measured)
	await _check_long_stack(plugin, panel)
	await _check_long_content(plugin, panel)
	await _check_native_preview_edit(plugin, panel)
	panel.restore_layout_metadata_snapshot(metadata_before)
	_finish(plugin)


func _check_full_height(panel: GSTMainPanel, measured: Dictionary) -> void:
	var host_rect: Rect2 = measured["host_rect"]
	var root_rect: Rect2 = measured["root_rect"]
	var height_matches: bool = absf(host_rect.size.y - root_rect.size.y) <= 2.0
	var top_matches: bool = absf(host_rect.position.y - root_rect.position.y) <= 2.0
	var flags_match: bool = panel.size_flags_horizontal == Control.SIZE_EXPAND_FILL and panel.size_flags_vertical == Control.SIZE_EXPAND_FILL
	_check("full_height", height_matches and top_matches and flags_match, "host=%s root=%s flags=%d/%d" % [host_rect, root_rect, panel.size_flags_horizontal, panel.size_flags_vertical])


func _check_default_allocation(measured: Dictionary) -> void:
	var editing_rect: Rect2 = measured["editing_rect"]
	var preview_area_rect: Rect2 = measured["preview_area_rect"]
	var divider: float = measured["main_divider_width"]
	var available: float = editing_rect.size.x + preview_area_rect.size.x
	var expected: float = available * 0.6
	var ratio_ok: bool = not measured["main_minimums_permit_default"] or absf(editing_rect.size.x - expected) <= divider + 2.0
	_check("default_60_40", ratio_ok, "editing=%.1f preview=%.1f expected_editing=%.1f divider=%.1f minimums_permit=%s" % [editing_rect.size.x, preview_area_rect.size.x, expected, divider, measured["main_minimums_permit_default"]])


func _check_preview_and_output(measured: Dictionary) -> void:
	var preview_rect: Rect2 = measured["preview_rect"]
	var output_rect: Rect2 = measured["output_rect"]
	var minimum: Vector2 = measured["preview_minimum"]
	var large_enough: bool = preview_rect.size.x >= minimum.x and preview_rect.size.y >= minimum.y
	var old_failure_absent: bool = preview_rect.size.y > 74.0
	var below_preview: bool = output_rect.position.y >= preview_rect.end.y - 1.0
	_check("preview_allocation", large_enough and old_failure_absent, "preview=%s measured_minimum=%s historical=488x74" % [preview_rect, minimum])
	_check("output_below_preview", below_preview and output_rect.size.y > 0.0, "preview=%s output=%s" % [preview_rect, output_rect])


func _check_file_menu(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var file_menu: MenuButton = panel.get_node("%FileMenu") as MenuButton
	var popup: PopupMenu = file_menu.get_popup()
	var labels: Array[String] = []
	for i: int in range(popup.item_count):
		if not popup.is_item_separator(i):
			labels.append(popup.get_item_text(i))
	var old_stack: GSTStack = panel.get_stack()
	popup.id_pressed.emit(0)
	await plugin.get_tree().process_frame
	var direct_buttons: bool = (panel.get_node("%SaveButton") as Button).visible and (panel.get_node("%ExportButton") as Button).visible
	_check("file_menu", labels == ["New", "Open...", "Save As...", "Reopen Shader..."] and panel.get_stack() != old_stack and panel.get_stack().layers.is_empty() and direct_buttons, "items=%s new_installed=%s save_export_visible=%s" % [labels, panel.get_stack() != old_stack, direct_buttons])
	panel.get_picker().cancelled.emit()
	await plugin.get_tree().process_frame
	panel.set_narrow_tab(1)
	await plugin.get_tree().process_frame
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var editor_ready: bool = not panel.is_picker_open() and (panel.get_node("%EditingContent") as Control).is_visible_in_tree() and inspector.is_visible_in_tree() and inspector.size.x > 0.0 and inspector.size.y > 0.0
	_check("post_new_editor", editor_ready, "picker_open=%s editing_visible=%s inspector_visible=%s inspector_size=%s" % [panel.is_picker_open(), (panel.get_node("%EditingContent") as Control).is_visible_in_tree(), inspector.is_visible_in_tree(), inspector.size])


func _check_section_persistence(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var inputs_button: Button = null
	for node: Node in inspector.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button.text == "Inputs":
			inputs_button = button
			break
	if inputs_button == null:
		_check("section_persistence", false, "Inputs section heading is absent")
		return
	inputs_button.button_pressed = true
	await plugin.get_tree().process_frame
	var content: Control = inputs_button.get_parent().get_child(2) as Control
	var stored: Dictionary = panel.get_layout_metadata_snapshot()
	inputs_button.button_pressed = false
	panel.restore_layout_metadata_snapshot(stored)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var restored: bool = inputs_button.button_pressed and not content.visible
	_check("section_persistence", restored, "collapsed=%s content_visible=%s metadata=%s" % [inputs_button.button_pressed, content.visible, stored["sections"]])
	inputs_button.button_pressed = false


func _check_split_persistence(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var normal_window_size: Vector2i = DisplayServer.window_get_size()
	DisplayServer.window_set_size(_wide_window_size())
	for i: int in range(6):
		await plugin.get_tree().process_frame
	var main_split: HSplitContainer = panel.get_node("%MainSplit") as HSplitContainer
	var inner_split: HSplitContainer = panel.get_node("%EditingSplit") as HSplitContainer
	var metadata_before: Dictionary = panel.get_layout_metadata_snapshot()
	var before: Dictionary = panel.get_layout_measurements()
	var inner_fixture_visible: bool = not before["narrow"] and inner_split.is_visible_in_tree() and inner_split.get_child_count() == 2 and (inner_split.get_child(0) as Control).size.x > 0.0 and (inner_split.get_child(1) as Control).size.x > 0.0
	await _drag_splitter(plugin, inner_split, 24.0)
	var inner_changed: Dictionary = panel.get_layout_measurements()
	panel.restore_layout_metadata()
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var inner_restored: Dictionary = panel.get_layout_measurements()
	var inner_ok: bool = absf(inner_changed["inner_ratio"] - before["inner_ratio"]) > 0.01 and absf(inner_restored["inner_ratio"] - inner_changed["inner_ratio"]) <= 0.02
	var main_before: Dictionary = panel.get_layout_measurements()
	await _drag_splitter(plugin, main_split, 64.0 * EditorInterface.get_editor_scale())
	var main_changed: Dictionary = panel.get_layout_measurements()
	panel.restore_layout_metadata()
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var main_restored: Dictionary = panel.get_layout_measurements()
	var main_ok: bool = absf(main_changed["main_ratio"] - main_before["main_ratio"]) > 0.01 and absf(main_restored["main_ratio"] - main_changed["main_ratio"]) <= 0.02
	var ratios_bounded: bool = main_changed["main_ratio"] >= main_changed["main_ratio_min"] and main_changed["main_ratio"] <= main_changed["main_ratio_max"] and inner_changed["inner_ratio"] >= inner_changed["inner_ratio_min"] and inner_changed["inner_ratio"] <= inner_changed["inner_ratio_max"]
	_check("split_persistence", inner_fixture_visible and ratios_bounded and inner_ok and main_ok, "fixture_visible=%s inner=%.3f->%.3f->%.3f main=%.3f->%.3f->%.3f" % [inner_fixture_visible, before["inner_ratio"], inner_changed["inner_ratio"], inner_restored["inner_ratio"], main_before["main_ratio"], main_changed["main_ratio"], main_restored["main_ratio"]])
	DisplayServer.window_set_size(normal_window_size)
	panel.restore_layout_metadata_snapshot(metadata_before)
	for i: int in range(5):
		await plugin.get_tree().process_frame


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


func _check_responsive_tabs(plugin: EditorPlugin, panel: GSTMainPanel, _measured: Dictionary) -> void:
	var original_window_size: Vector2i = DisplayServer.window_get_size()
	var metadata_before: Dictionary = panel.get_layout_metadata_snapshot()
	panel._on_new_pressed()
	await plugin.get_tree().process_frame
	panel.get_picker().cancelled.emit()
	var selected_layer: GSTLayer = panel.get_stack_list().add_layer_by_entry_id("generative/fbm")
	panel.get_stack_list().select_layer(selected_layer.id)
	panel.set_narrow_tab(1)
	for i: int in range(5):
		await plugin.get_tree().process_frame
	var inspector_column: GSTInspectorColumn = panel.get_inspector_column()
	var parameter_inspector: EditorInspector = inspector_column.call("get_parameter_inspector") as EditorInspector
	var coord_inspector: EditorInspector = inspector_column.call("get_coord_inspector") as EditorInspector
	var representative_property: EditorProperty = inspector_column.find_editor_property(&"gain", selected_layer)
	var representative_visible: bool = representative_property != null and representative_property.is_visible_in_tree() and representative_property.size.x > 0.0 and representative_property.size.y > 0.0
	var tab_threshold: float = panel.get_layout_measurements()["tab_breakpoint"]
	DisplayServer.window_set_size(Vector2i(720, 600))
	for i: int in range(6):
		await plugin.get_tree().process_frame
	var main_split: HSplitContainer = panel.get_node("%MainSplit") as HSplitContainer
	if panel.get_layout_measurements()["editing_rect"].size.x >= tab_threshold:
		await _drag_splitter(plugin, main_split, -(panel.get_layout_measurements()["editing_rect"].size.x - tab_threshold + 24.0))
	var narrow: Dictionary = panel.get_layout_measurements()
	var same_layer_pane: bool = panel.get_node("%LayerPane").get_parent() == panel.get_node("%EditingTabs")
	var same_settings_pane: bool = panel.get_node("%SettingsPane").get_parent() == panel.get_node("%EditingTabs")
	var inspector_nodes: Array[Node] = panel.find_children("*", "EditorInspector", true, false)
	var two_inspectors: bool = inspector_nodes.size() == 2
	var inspector_targets_ok: bool = parameter_inspector != null and coord_inspector != null and parameter_inspector.get_edited_object() == selected_layer and coord_inspector.get_edited_object() == selected_layer.coord
	var settings_scroll_bounded: bool = false
	if inspector_column.has_method("get_settings_scroll"):
		var settings_scroll: ScrollContainer = inspector_column.call("get_settings_scroll") as ScrollContainer
		settings_scroll_bounded = settings_scroll != null and (panel.get_node("%SettingsPane") as Control).get_global_rect().encloses(settings_scroll.get_global_rect())
	var narrow_enclosed: bool = narrow["host_rect"].encloses(narrow["root_rect"]) and narrow["host_rect"].encloses(narrow["editing_rect"]) and narrow["host_rect"].encloses(narrow["preview_area_rect"])
	var tabs: TabContainer = panel.get_node("%EditingTabs") as TabContainer
	var layer_pane: Control = panel.get_node("%LayerPane") as Control
	var settings_pane: Control = panel.get_node("%SettingsPane") as Control
	panel.set_narrow_tab(1)
	await plugin.get_tree().process_frame
	var saved_tab_metadata: Dictionary = panel.get_layout_metadata_snapshot()
	tabs.current_tab = 0
	await plugin.get_tree().process_frame
	var started_on_different_tab: bool = tabs.current_tab == 0 and layer_pane.visible and not settings_pane.visible
	panel.restore_layout_metadata_snapshot(saved_tab_metadata)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var tab_persisted: bool = panel.get_narrow_tab() == 1 and tabs.current_tab == 1 and not layer_pane.visible and settings_pane.visible
	DisplayServer.window_set_size(_wide_window_size())
	panel.restore_layout_metadata_snapshot(metadata_before)
	for i: int in range(6):
		await plugin.get_tree().process_frame
	var wide: Dictionary = panel.get_layout_measurements()
	var returned_to_split: bool = panel.get_node("%LayerPane").get_parent() == panel.get_node("%EditingSplit") and panel.get_node("%SettingsPane").get_parent() == panel.get_node("%EditingSplit")
	var wide_inspector_nodes: Array[Node] = panel.find_children("*", "EditorInspector", true, false)
	var same_inspectors_and_targets: bool = wide_inspector_nodes.size() == 2 and parameter_inspector in wide_inspector_nodes and coord_inspector in wide_inspector_nodes and parameter_inspector.get_edited_object() == selected_layer and coord_inspector.get_edited_object() == selected_layer.coord
	var wide_enclosed: bool = wide["host_rect"].encloses(wide["root_rect"]) and wide["host_rect"].encloses(wide["editing_rect"]) and wide["host_rect"].encloses(wide["preview_area_rect"])
	var actual_crossing: bool = narrow["editing_rect"].size.x <= tab_threshold + 0.5 and wide["editing_rect"].size.x > tab_threshold + 0.5
	_check("responsive_tabs", representative_visible and actual_crossing and narrow["narrow"] and not wide["narrow"] and same_layer_pane and same_settings_pane and returned_to_split and two_inspectors and inspector_targets_ok and same_inspectors_and_targets and settings_scroll_bounded and narrow_enclosed and wide_enclosed and started_on_different_tab and tab_persisted, "representative_visible=%s breakpoint=%.1f widths=%.1f/%.1f narrow=%s wide=%s enclosed=%s/%s inspectors=%d/%d targets_ok=%s/%s scroll_bounded=%s different_start=%s tab_persisted=%s" % [representative_visible, tab_threshold, narrow["editing_rect"].size.x, wide["editing_rect"].size.x, narrow["narrow"], wide["narrow"], narrow_enclosed, wide_enclosed, inspector_nodes.size(), wide_inspector_nodes.size(), inspector_targets_ok, same_inspectors_and_targets, settings_scroll_bounded, started_on_different_tab, tab_persisted])
	DisplayServer.window_set_size(original_window_size)
	for i: int in range(3):
		await plugin.get_tree().process_frame


func _check_long_stack(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var original_window_size: Vector2i = DisplayServer.window_get_size()
	DisplayServer.window_set_size(Vector2i(1000, 560))
	for i: int in range(5):
		await plugin.get_tree().process_frame
	panel._on_new_pressed()
	await plugin.get_tree().process_frame
	panel.get_picker().cancelled.emit()
	await plugin.get_tree().process_frame
	panel.set_narrow_tab(0)
	await plugin.get_tree().process_frame
	var list: GSTStackList = panel.get_stack_list()
	var list_visible: bool = list.is_visible_in_tree() and list.size.x > 0.0 and list.size.y > 0.0
	for i: int in range(20):
		list.add_layer_by_entry_id("generative/hash")
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var target_id: StringName = panel.get_stack().layers[9].id
	list.select_layer(target_id)
	list.scroll_to_fraction(0.5)
	await plugin.get_tree().process_frame
	var before_anchor: StringName = list.get_scroll_anchor_id()
	var preview_before: Rect2 = panel.get_layout_measurements()["preview_rect"]
	var output_before: Rect2 = panel.get_layout_measurements()["output_rect"]
	var reorder_id: StringName = panel.get_stack().layers[0].id
	var reorder_result: Dictionary = panel.get_undo().reorder_layer(reorder_id, 1)
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var after_reorder_anchor: StringName = list.get_scroll_anchor_id()
	list.refresh()
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var after_refresh_anchor: StringName = list.get_scroll_anchor_id()
	var fixed_rows: bool = list.has_fixed_row_heights()
	var selected_ok: bool = list.get_selected_layer_id() == target_id
	var preview_after: Rect2 = panel.get_layout_measurements()["preview_rect"]
	var output_after: Rect2 = panel.get_layout_measurements()["output_rect"]
	var scrollable: bool = before_anchor != &"" and before_anchor != list.get_item_id(0)
	_check("stable_scroll", list_visible and list.get_item_count() == 20 and selected_ok and reorder_result["ok"] and scrollable and after_reorder_anchor == before_anchor and after_refresh_anchor == before_anchor and fixed_rows, "visible=%s size=%s items=%d selected=%s reorder=%s anchor=%s/%s/%s fixed_rows=%s" % [list_visible, list.size, list.get_item_count(), selected_ok, reorder_result["ok"], before_anchor, after_reorder_anchor, after_refresh_anchor, fixed_rows])
	_check("independent_scroll", preview_before.is_equal_approx(preview_after) and output_before.is_equal_approx(output_after), "preview=%s/%s output=%s/%s" % [preview_before, preview_after, output_before, output_after])
	DisplayServer.window_set_size(original_window_size)
	for i: int in range(3):
		await plugin.get_tree().process_frame


func _check_long_content(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var normal_window_size: Vector2i = DisplayServer.window_get_size()
	DisplayServer.window_set_size(_wide_window_size())
	for i: int in range(6):
		await plugin.get_tree().process_frame
	panel._on_new_pressed()
	await plugin.get_tree().process_frame
	panel.get_picker().cancelled.emit()
	await plugin.get_tree().process_frame
	var list: GSTStackList = panel.get_stack_list()
	list.add_layer_by_entry_id("source/texture")
	list.add_layer_by_entry_id("color/brightness_contrast")
	var mix: GSTLayer = list.add_layer_by_entry_id("color/mix")
	list.select_layer(mix.id)
	var refusal_text: String = "A deliberately long refusal message verifies that layout errors wrap inside the assigned editor column without forcing the active main-screen panel beyond its host rectangle."
	panel.get_inspector_column().set_refusal(mix.id, "a", "input", refusal_text)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var refusal: Label = _find_label_with_text(inspector, refusal_text)
	var layer_pane: Control = panel.get_node("%LayerPane") as Control
	var settings_pane: Control = panel.get_node("%SettingsPane") as Control
	var input_button: Button = inspector.get_input_button("a")
	var panes_visible: bool = layer_pane.is_visible_in_tree() and settings_pane.is_visible_in_tree() and layer_pane.size.x > 0.0 and settings_pane.size.x > 0.0
	var refusal_inside: bool = refusal != null and _rect_inside(refusal.get_global_rect(), settings_pane.get_global_rect())
	var button_inside: bool = input_button != null and input_button.text.contains("brightness_contrast") and _rect_inside(input_button.get_global_rect(), settings_pane.get_global_rect())
	var refusal_wraps: bool = refusal != null and refusal.autowrap_mode != TextServer.AUTOWRAP_OFF
	var stack_refusal_text: String = "A separate stack edit refusal stays beside the layer controls."
	list.set_refusal(stack_refusal_text, "up", mix.id)
	await plugin.get_tree().process_frame
	var stack_refusal: Label = list.get_refusal_label()
	var stack_refusal_inside: bool = stack_refusal.text == stack_refusal_text and _rect_inside(stack_refusal.get_global_rect(), layer_pane.get_global_rect())
	_check("long_content", panes_visible and refusal_inside and button_inside and stack_refusal_inside and refusal_wraps and stack_refusal.autowrap_mode != TextServer.AUTOWRAP_OFF, "panes_visible=%s input_refusal=%s settings=%s input_button=%s stack_refusal=%s layer_pane=%s" % [panes_visible, refusal.get_global_rect() if refusal != null else Rect2(), settings_pane.get_global_rect(), input_button.get_global_rect() if input_button != null else Rect2(), stack_refusal.get_global_rect(), layer_pane.get_global_rect()])
	var removed_id: StringName = mix.id
	panel.get_undo().remove_layer(removed_id)
	list.refresh()
	_check("stack_refusal_pruned", list.get_refusal_label().text.is_empty(), "removed destination='%s' refusal='%s'" % [String(removed_id), list.get_refusal_label().text])
	DisplayServer.window_set_size(normal_window_size)
	for i: int in range(5):
		await plugin.get_tree().process_frame


func _find_label_with_text(root: Node, text: String) -> Label:
	for node: Node in root.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.text == text:
			return label
	return null


func _rect_inside(inner: Rect2, outer: Rect2) -> bool:
	return inner.position.x >= outer.position.x - 1.0 and inner.position.y >= outer.position.y - 1.0 and inner.end.x <= outer.end.x + 1.0 and inner.end.y <= outer.end.y + 1.0


func _check_native_preview_edit(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	panel._on_new_pressed()
	await plugin.get_tree().process_frame
	panel.get_picker().cancelled.emit()
	await plugin.get_tree().process_frame
	var layer: GSTLayer = panel.get_stack_list().add_layer_by_entry_id("color/fill")
	panel.get_undo().set_output_color(layer.id)
	panel.get_stack_list().select_layer(layer.id)
	panel.set_narrow_tab(1)
	for i: int in range(5):
		await plugin.get_tree().process_frame
	var before: Image = panel.get_preview().get_viewport_image()
	var property: EditorProperty = panel.get_inspector_column().find_editor_property(&"color", layer)
	var settings_scroll: ScrollContainer = panel.get_inspector_column().get_settings_scroll()
	if property != null:
		settings_scroll.ensure_control_visible(property)
		for i: int in range(2):
			await plugin.get_tree().process_frame
	var property_visible: bool = property != null and property.is_visible_in_tree() and property.size.x > 0.0 and property.size.y > 0.0 and property.get_global_rect().intersects(settings_scroll.get_global_rect())
	if property != null:
		property.emit_changed(&"color", Color(0.1, 0.8, 0.2, 1.0))
	for i: int in range(5):
		await plugin.get_tree().process_frame
	var after: Image = panel.get_preview().get_viewport_image()
	_check("native_preview_edit", property_visible and before != null and after != null and not _images_equal(before, after), "editor_property=%s visible=%s image_before=%s image_after=%s" % [property != null, property_visible, before.get_size() if before != null else Vector2i.ZERO, after.get_size() if after != null else Vector2i.ZERO])


func _wide_window_size() -> Vector2i:
	var editor_scale: float = EditorInterface.get_editor_scale()
	return Vector2i(roundi(1920.0 * editor_scale), roundi(1080.0 * editor_scale))


func _images_equal(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	var step: int = maxi(1, mini(a.get_width(), a.get_height()) / 16)
	for y: int in range(0, a.get_height(), step):
		for x: int in range(0, a.get_width(), step):
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				return false
	return true


func _print_measurements(measured: Dictionary) -> void:
	print("UI_LAYOUT MEASURE window=%s scale=%.2f host=%s root=%s editing=%s preview_area=%s preview=%s output=%s minimums=%s/%s breakpoint=%.1f" % [DisplayServer.window_get_size(), measured["editor_scale"], measured["host_rect"], measured["root_rect"], measured["editing_rect"], measured["preview_area_rect"], measured["preview_rect"], measured["output_rect"], measured["editing_minimum"], measured["preview_minimum"], measured["tab_breakpoint"]])


func _check(item: String, ok: bool, detail: String) -> void:
	if ok:
		_pass_count += 1
		print("SMOKE ui_layout_%s PASS %s" % [item, detail])
	else:
		_fail_count += 1
		print("SMOKE ui_layout_%s FAIL %s" % [item, detail])


func _finish(plugin: EditorPlugin) -> void:
	print("SMOKE SUMMARY pass=%d fail=%d" % [_pass_count, _fail_count])
	plugin.get_tree().quit(1 if _fail_count > 0 else 0)
