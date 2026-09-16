@tool
extends RefCounted

## Runs inside a real editor session (godot --editor --path .) when
## GST_EDITOR_SMOKE is set, driven by plugin.gd's _enter_tree. Dispatches on
## the env var's value: "5" preview column, "6" persistence and export, "7"
## recipe proof, "8" randomize, "tabs_*" and "ui_*" load a sibling script,
## any other value runs the stack and undo checks. Prints one
## "SMOKE <item> PASS|FAIL <detail>" line per item, then quits the editor.

var _pass_count: int = 0
var _fail_count: int = 0


## plugin.gd only checks that GST_EDITOR_SMOKE is non-empty; the value is
## dispatched here.
func run(plugin: EditorPlugin) -> void:
	var flag: String = OS.get_environment("GST_EDITOR_SMOKE")
	if flag == "tabs_proof":
		var document_proof: RefCounted = load("res://tests/gst_editor_document_proof.gd").new()
		await document_proof.run(plugin)
	elif flag == "tabs_native":
		var native_undo_smoke: RefCounted = load("res://tests/gst_editor_native_undo_smoke.gd").new()
		await native_undo_smoke.run(plugin)
	elif flag == "tabs_documents":
		var documents_smoke: RefCounted = load("res://tests/gst_editor_documents_smoke.gd").new()
		await documents_smoke.run(plugin)
	elif flag == "tabs_ui":
		var tabs_ui_smoke: RefCounted = load("res://tests/gst_editor_tabs_smoke.gd").new()
		await tabs_ui_smoke.run(plugin)
	elif flag == "tabs_files":
		var files_smoke: RefCounted = load("res://tests/gst_editor_document_files_smoke.gd").new()
		await files_smoke.run(plugin)
	elif flag == "tabs_close":
		var close_smoke: RefCounted = load("res://tests/gst_editor_document_close_smoke.gd").new()
		await close_smoke.run(plugin)
	elif flag == "tabs_recovery":
		var recovery_smoke: RefCounted = load("res://tests/gst_editor_document_recovery_smoke.gd").new()
		await recovery_smoke.run(plugin)
	elif flag == "tabs_host":
		var host_smoke: RefCounted = load("res://tests/gst_editor_tabs_host_smoke.gd").new()
		await host_smoke.run(plugin)
	elif flag == "ui_complete":
		var complete_smoke: RefCounted = load("res://tests/gst_editor_ui_complete_smoke.gd").new()
		await complete_smoke.run(plugin)
	elif flag == "ui_picker":
		var picker_smoke: RefCounted = load("res://tests/gst_editor_ui_picker_smoke.gd").new()
		await picker_smoke.run(plugin)
	elif flag == "ui_layout":
		var layout_smoke: RefCounted = load("res://tests/gst_editor_ui_layout_smoke.gd").new()
		await layout_smoke.run(plugin)
	elif flag == "ui_actions":
		var actions_smoke: RefCounted = load("res://tests/gst_editor_ui_actions_smoke.gd").new()
		await actions_smoke.run(plugin)
	elif flag == "ui_labels":
		var labels_smoke: RefCounted = load("res://tests/gst_editor_ui_labels_smoke.gd").new()
		await labels_smoke.run(plugin)
	elif flag == "5":
		await _run_phase5(plugin)
	elif flag == "6":
		await _run_phase6(plugin)
	elif flag == "7":
		await _run_phase7(plugin)
	elif flag == "8":
		await _run_phase8(plugin)
	else:
		await _run_phase4(plugin)


func _run_phase4(plugin: EditorPlugin) -> void:
	# Wait for main screen tab registration and panel _ready().
	for i: int in range(5):
		await plugin.get_tree().process_frame

	var panel: GSTMainPanel = plugin.get_panel() as GSTMainPanel
	_check("1", panel != null, "panel is null" if panel == null else "panel present")
	if panel == null:
		_finish(plugin)
		return

	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await plugin.get_tree().process_frame
	_check("1", panel.visible, "panel.visible after set_main_screen_editor=%s" % [panel.visible])
	await _dismiss_initial_start(plugin, panel)

	var stack_list: GSTStackList = panel.get_stack_list()
	var undo: GSTUndo = panel.get_undo()
	var library: GSTLibrary = panel.get_library()
	var stack: GSTStack = panel.get_stack()
	var history: UndoRedo = _get_history(panel)

	var fbm: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	var invert: GSTLayer = stack_list.add_layer_by_entry_id("fieldops/invert")
	var hash_layer: GSTLayer = stack_list.add_layer_by_entry_id("generative/hash")
	_check("2", fbm != null and invert != null and hash_layer != null, "fbm=%s invert=%s hash=%s" % [fbm, invert, hash_layer])
	_check("2b", stack.output_color == hash_layer.id and invert.slots.get("x", &"") == fbm.id, "UI adds assign top output='%s' (expect '%s') and initialize invert.x='%s' (expect '%s')" % [String(stack.output_color), String(hash_layer.id), String(invert.slots.get("x", &"")), String(fbm.id)])

	await plugin.get_tree().process_frame
	panel.get_output_block().get_color_button().pressed.emit()
	await plugin.get_tree().process_frame
	panel.get_picker().activate_value("")
	await plugin.get_tree().process_frame
	_check_output_defaults("3", panel, "after the adds, before any output-block or color-layer state exists")
	history.undo()
	await plugin.get_tree().process_frame
	_check("3b", stack.output_color == hash_layer.id, "undoing the explicit default-row excursion restores the top UI-added output '%s'" % String(hash_layer.id))

	await _run_palette_inspector_check(plugin, panel, stack_list, history)
	await _run_color_alpha_default_excursion(plugin, panel, stack_list, library, history)
	await _run_add_for_slot_excursion(plugin, panel, stack_list, library, history, invert)

	# fbm(idx0) and invert(idx1) are adjacent, so one Up step on fbm swaps it
	# with invert and the forward-reference check (invert references fbm)
	# refuses it. Must run before the hash-down move below, which would
	# separate fbm and invert.
	var wire_result: Dictionary = undo.assign_slot(invert.id, "x", fbm.id)
	_check("6", wire_result["ok"], "wire invert.x -> fbm: %s" % [wire_result["reason"]])

	var order_before_attempt: Array[StringName] = _layer_ids(stack)
	stack_list.select_layer(fbm.id)
	stack_list._on_up_pressed()
	await plugin.get_tree().process_frame
	var order_after_attempt: Array[StringName] = _layer_ids(stack)
	var refusal_reason: String = stack_list.get_refusal_label().text
	var refused_as_expected: bool = refusal_reason.contains("references layer %s, which would be at or above it after this move" % String(fbm.id))
	_check("7", refused_as_expected and order_after_attempt == order_before_attempt, "up-press fbm above invert message='%s' order_unchanged=%s" % [refusal_reason, order_after_attempt == order_before_attempt])

	# hash has no references either way, so the move is always legal. Same
	# GSTUndo call the stack list's Down button uses: idx + (-1).
	var hash_original_index: int = GSTStackOps.find_index(stack, hash_layer.id)
	var down_result: Dictionary = undo.reorder_layer(hash_layer.id, hash_original_index - 1)
	var hash_index_after_move: int = GSTStackOps.find_index(stack, hash_layer.id)
	_check("8", down_result["ok"] and hash_index_after_move == hash_original_index - 1, "hash move down: ok=%s index %d -> %d" % [down_result["ok"], hash_original_index, hash_index_after_move])

	# invert is the top-most layer; a move one past the top clamps to its own
	# index and must not register an undo action.
	var top_layer_id: StringName = stack.layers[stack.layers.size() - 1].id
	var count_before_noop: int = history.get_history_count()
	var noop_result: Dictionary = undo.reorder_layer(top_layer_id, stack.layers.size())
	var count_after_noop: int = history.get_history_count()
	_check("9", noop_result["ok"] and count_after_noop == count_before_noop, "boundary move at top: ok=%s history_count %d -> %d (expect unchanged)" % [noop_result["ok"], count_before_noop, count_after_noop])

	var output_color_result: Dictionary = undo.set_output_color(invert.id)
	_check("10", output_color_result["ok"] and stack.output_color == invert.id, "set output color to invert: ok=%s applied='%s' (expect '%s')" % [output_color_result["ok"], String(stack.output_color), String(invert.id)])

	var output_alpha_result: Dictionary = undo.set_output_alpha(&"none")
	var alpha_applied: bool = stack.output_alpha == &"none" and panel.get_output_block().get_selected_alpha_text() == "Opaque"
	_check("11", output_alpha_result["ok"] and alpha_applied, "set output alpha to none: ok=%s applied='%s' selected_text='%s' (expect 'Opaque')" % [output_alpha_result["ok"], String(stack.output_alpha), panel.get_output_block().get_selected_alpha_text()])

	# Selecting the alpha chooser's Automatic row must register one undo
	# action. Undone right after the check so _run_undo_sequence still finds
	# exactly 7 actions.
	var count_before_default_pick: int = history.get_history_count()
	panel.get_output_block().get_alpha_button().pressed.emit()
	await plugin.get_tree().process_frame
	panel.get_picker().activate_value("")
	await plugin.get_tree().process_frame
	var count_after_default_pick: int = history.get_history_count()
	_check("11b", stack.output_alpha == &"" and count_after_default_pick == count_before_default_pick + 1, "select default alpha row after explicit none: output_alpha='%s' (expect empty), history_count %d -> %d (expect +1)" % [String(stack.output_alpha), count_before_default_pick, count_after_default_pick])

	history.undo()
	await plugin.get_tree().process_frame
	_check("11c", stack.output_alpha == &"none", "undo default-row pick restores explicit none: output_alpha='%s' (expect 'none')" % [String(stack.output_alpha)])

	await _run_undo_sequence(plugin, stack, stack_list, panel, fbm, invert, hash_layer, hash_original_index)
	await _run_output_referenced_removal_excursion(plugin, panel, undo, library)
	await _run_slider_remove_undo_identity_excursion(plugin, panel, undo)
	_run_codegen_check()

	_finish(plugin)


func _get_history(panel: GSTMainPanel) -> UndoRedo:
	return panel.get_watched_history()


func _dismiss_initial_start(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var dismissed: bool = false
	if panel.is_start_screen_visible():
		panel.get_create_empty_button().pressed.emit()
		dismissed = true
		await plugin.get_tree().process_frame
	await _cancel_picker(plugin, panel)
	if dismissed and panel.get_watched_history().has_undo():
		panel.get_watched_history().undo()
		await plugin.get_tree().process_frame


func _cancel_picker(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	if panel.is_picker_open():
		panel.get_picker().cancelled.emit()
	await plugin.get_tree().process_frame


func _layer_ids(stack: GSTStack) -> Array[StringName]:
	var ids: Array[StringName] = []
	for layer: GSTLayer in stack.layers:
		ids.append(layer.id)
	return ids


func _property_info(object: Object, property_name: StringName) -> Dictionary:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", &"")) == property_name:
			return property
	return {}


## With no color layer in the stack the color button names the empty
## automatic result; with no source/texture layer, Transparency names
## automatic opaque.
func _check_output_defaults(item: String, panel: GSTMainPanel, context: String) -> void:
	var color_text: String = panel.get_output_block().get_selected_color_text()
	var alpha_text: String = panel.get_output_block().get_selected_alpha_text()
	var ok: bool = color_text == "Automatic: none" and alpha_text == "Automatic: Opaque"
	_check(item, ok, "%s: color='%s' transparency='%s'" % [context, color_text, alpha_text])


## color/palette: params b/c/d stay Vector3 editors; param `a` uses a
## no-alpha Color editor adapter. Undone here before any other action commits.
func _run_palette_inspector_check(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, history: UndoRedo) -> void:
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var palette_layer: GSTLayer = stack_list.add_layer_by_entry_id("color/palette")
	await plugin.get_tree().process_frame
	inspector.edit(palette_layer.id)

	var vec3_names: Array[String] = []
	for prop: Dictionary in palette_layer.get_property_list():
		if int(prop.get("type", -1)) == TYPE_VECTOR3:
			vec3_names.append(String(prop["name"]))
	vec3_names.sort()
	var a_property: Dictionary = _property_info(palette_layer, &"a")
	var editor_schema: Dictionary = palette_layer.get_param_schema(&"a")
	var expected_names: Array[String] = ["b", "c", "d"]
	_check("15a", vec3_names == expected_names and int(a_property.get("type", -1)) == TYPE_COLOR and int(a_property.get("hint", -1)) == PROPERTY_HINT_COLOR_NO_ALPHA and String(editor_schema.get("editor", "")) == "color_rgb", "color/palette vectors=%s a_type=%s a_hint=%s editor='%s'" % [vec3_names, a_property.get("type"), a_property.get("hint"), editor_schema.get("editor")])

	var a_value: Variant = palette_layer.get("a")
	_check("15b", a_value is Color and (a_value as Color).is_equal_approx(Color(0.5, 0.5, 0.5, 1.0)) and not palette_layer.params.has("a"), "layer.get('a')=%s type=%s raw_key=%s" % [a_value, typeof(a_value), palette_layer.params.has("a")])

	inspector.edit(&"")
	history.undo()
	await plugin.get_tree().process_frame
	_check("15c", GSTStackOps.find_index(panel.get_stack(), palette_layer.id) == -1, "undo the palette add: layer gone=%s" % [GSTStackOps.find_index(panel.get_stack(), palette_layer.id) == -1])


## Adds color/fill then source/texture through the Add button path, checks
## the output block defaults, then undoes both. Both adds are reverted, so
## the next committed action (the invert.x wire) truncates them from the redo
## tail and the persistent action count is unaffected.
func _run_color_alpha_default_excursion(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, library: GSTLibrary, history: UndoRedo) -> void:
	var previous_output: StringName = panel.get_stack().output_color
	var fill: GSTLayer = stack_list.add_layer_by_entry_id("color/fill")
	await plugin.get_tree().process_frame
	var fill_entry: GSTManifestEntry = library.get_entry("color/fill")
	var expect_color: String = "Automatic: l%s %s" % [String(fill.id), fill_entry.function]
	_check("4", panel.get_output_block().get_selected_color_text() == "l%s %s" % [String(fill.id), fill_entry.function], "UI add selects fill explicitly: '%s'" % panel.get_output_block().get_selected_color_text())
	panel.get_output_block().get_color_button().pressed.emit()
	await plugin.get_tree().process_frame
	panel.get_picker().activate_value("")
	await plugin.get_tree().process_frame
	_check("4a", panel.get_output_block().get_selected_color_text() == expect_color, "color default after adding fill: '%s' (expect '%s')" % [panel.get_output_block().get_selected_color_text(), expect_color])

	stack_list.add_layer_by_entry_id("source/texture")
	await plugin.get_tree().process_frame
	_check("4b", panel.get_output_block().get_selected_alpha_text() == "Automatic: Texture transparency", "automatic transparency after adding texture: '%s'" % [panel.get_output_block().get_selected_alpha_text()])

	history.undo()
	await plugin.get_tree().process_frame
	_check("4c", panel.get_output_block().get_selected_alpha_text() == "Automatic: Opaque", "automatic transparency after undoing texture add: '%s'" % [panel.get_output_block().get_selected_alpha_text()])

	history.undo()
	await plugin.get_tree().process_frame
	_check("4d", panel.get_stack().output_color == fill.id, "undoing the default-row selection restores the UI add output '%s'" % String(fill.id))

	history.undo()
	await plugin.get_tree().process_frame
	_check("4e", panel.get_stack().output_color == previous_output, "undoing fill add restores the previous UI output '%s' (expect '%s')" % [String(panel.get_stack().output_color), String(previous_output)])


## Drives the inspector column's input button on invert's slot "x", switches
## to Add new, checks automatic-conversion candidates, search-filters, checks
## the compound add + wire landed directly below invert, then undoes it.
func _run_add_for_slot_excursion(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, library: GSTLibrary, history: UndoRedo, invert: GSTLayer) -> void:
	var stack: GSTStack = panel.get_stack()
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	stack_list.select_layer(invert.id)
	await plugin.get_tree().process_frame

	var input_button: Button = inspector.get_input_button("x")
	input_button.pressed.emit()
	await plugin.get_tree().process_frame
	var picker: GSTPicker = inspector.get_slot_picker()
	picker.switch_tab(1)
	await plugin.get_tree().process_frame
	var all_ids: Array[String] = picker.get_all_entry_ids()
	var has_field: bool = false
	var has_color: bool = false
	for entry_id: String in all_ids:
		if library.get_entry(entry_id).kind_out == GSTLayer.Kind.FIELD:
			has_field = true
		else:
			has_color = true
	_check("5a", has_field and has_color, "add-new input chooser listed %d entries, field=%s color=%s" % [all_ids.size(), has_field, has_color])

	picker.set_search_text("checker")
	var visible_ids: Array[String] = picker.get_visible_entry_ids()
	var only_checker: bool = visible_ids.size() == 1 and visible_ids[0] == "generative/checker"
	_check("5b", only_checker, "search 'checker' visible=%s (expect ['generative/checker'])" % [visible_ids])

	var count_before_pick: int = stack.layers.size()
	picker.activate_value("generative/checker")
	await plugin.get_tree().process_frame
	var invert_idx_now: int = GSTStackOps.find_index(stack, invert.id)
	var new_layer: GSTLayer = stack.layers[invert_idx_now - 1] if invert_idx_now > 0 else null
	var placed_below: bool = new_layer != null and new_layer.entry == "generative/checker"
	var slot_wired: bool = new_layer != null and invert.slots.get("x", &"") == new_layer.id
	var count_after_pick: int = stack.layers.size()
	_check("5c", placed_below and slot_wired and count_after_pick == count_before_pick + 1, "picked generative/checker: placed_below=%s slot_wired=%s count %d -> %d" % [placed_below, slot_wired, count_before_pick, count_after_pick])

	history.undo()
	await plugin.get_tree().process_frame
	var slot_restored: bool = invert.slots.get("x", &"") == stack.layers[GSTStackOps.find_index(stack, invert.id) - 1].id
	var count_after_undo: int = stack.layers.size()
	_check("5d", slot_restored and count_after_undo == count_before_pick, "undo add-for-slot: invert.slots['x']='%s' restored to immediate below, count=%d (expect %d)" % [String(invert.slots.get("x", &"")), count_after_undo, count_before_pick])

	picker.hide()


## The refused up-press and the boundary no-op registered no action, and the
## excursions above were undone before the next real action truncated them,
## so exactly 7 actions exist to undo: add fbm, add invert, add hash, wire
## the slot, reorder hash, set output color, set output alpha.
func _run_undo_sequence(plugin: EditorPlugin, stack: GSTStack, stack_list: GSTStackList, panel: GSTMainPanel, fbm: GSTLayer, invert: GSTLayer, hash_layer: GSTLayer, hash_original_index: int) -> void:
	var history: UndoRedo = _get_history(panel)

	history.undo()
	await plugin.get_tree().process_frame
	_check("12a", stack.output_alpha == &"" and stack_list.get_item_count() == 3, "output_alpha after undo 1: '%s' (expect empty), row_count=%s (expect 3)" % [String(stack.output_alpha), stack_list.get_item_count()])

	history.undo()
	await plugin.get_tree().process_frame
	_check("12b", stack.output_color == hash_layer.id and stack_list.get_item_count() == 3, "output_color after undo 2: '%s' (expect top UI-added '%s'), row_count=%s (expect 3)" % [String(stack.output_color), String(hash_layer.id), stack_list.get_item_count()])

	history.undo()
	await plugin.get_tree().process_frame
	var hash_index_now: int = GSTStackOps.find_index(stack, hash_layer.id)
	_check("12c", hash_index_now == hash_original_index and stack_list.get_item_count() == 3, "hash index after undo 3: %d (expect original %d), row_count=%s (expect 3)" % [hash_index_now, hash_original_index, stack_list.get_item_count()])

	history.undo()
	await plugin.get_tree().process_frame
	var invert_after: GSTLayer = GSTStackOps.find_layer(stack, invert.id)
	var slot_restored_to_add_default: bool = invert_after != null and invert_after.slots.get("x", &"") == fbm.id
	_check("12d", slot_restored_to_add_default and stack_list.get_item_count() == 3, "invert.slots['x'] after undo 4: '%s' (expect UI-add default '%s'), row_count=%s (expect 3)" % [String(invert_after.slots.get("x", &"")) if invert_after != null else "invert missing", String(fbm.id), stack_list.get_item_count()])

	history.undo()
	await plugin.get_tree().process_frame
	var hash_gone: bool = GSTStackOps.find_index(stack, hash_layer.id) == -1
	_check("12e", hash_gone and stack_list.get_item_count() == 2, "hash gone=%s row_count=%s (expect gone, 2 rows)" % [hash_gone, stack_list.get_item_count()])

	history.undo()
	await plugin.get_tree().process_frame
	var invert_gone: bool = GSTStackOps.find_index(stack, invert.id) == -1
	_check("12f", invert_gone and stack_list.get_item_count() == 1, "invert gone=%s row_count=%s (expect gone, 1 row)" % [invert_gone, stack_list.get_item_count()])

	history.undo()
	await plugin.get_tree().process_frame
	var fbm_gone: bool = GSTStackOps.find_index(stack, fbm.id) == -1
	_check("12g", fbm_gone and stack_list.get_item_count() == 0, "fbm gone=%s row_count=%s (expect gone, 0 rows)" % [fbm_gone, stack_list.get_item_count()])

	_check("12h", not history.has_undo(), "history.has_undo() after 7 undos: %s (expect false)" % [history.has_undo()])


## Removing a layer that stack.output_color or stack.output_alpha points at
## must clear that field to &"" rather than leave a dangling reference
## codegen cannot resolve. Starts on the empty stack _run_undo_sequence left
## and unwinds back to empty.
func _run_output_referenced_removal_excursion(plugin: EditorPlugin, panel: GSTMainPanel, undo: GSTUndo, library: GSTLibrary) -> void:
	var stack: GSTStack = panel.get_stack()
	var history: UndoRedo = _get_history(panel)

	var color_layer: GSTLayer = undo.add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	await plugin.get_tree().process_frame
	var alpha_layer: GSTLayer = undo.add_layer("generative/hash", GSTLayer.Kind.FIELD, true)
	await plugin.get_tree().process_frame

	var color_result: Dictionary = undo.set_output_color(color_layer.id)
	var alpha_result: Dictionary = undo.set_output_alpha(alpha_layer.id)
	_check("14a", color_result["ok"] and alpha_result["ok"] and stack.output_color == color_layer.id and stack.output_alpha == alpha_layer.id, "wire output color=%s alpha=%s" % [String(stack.output_color), String(stack.output_alpha)])

	undo.remove_layer(alpha_layer.id)
	await plugin.get_tree().process_frame
	var removed_result: GSTCodegenResult = GSTCodegen.generate_result(stack, library)
	_check("14b", stack.output_alpha == &"" and removed_result.ok(), "remove output_alpha's layer: output_alpha='%s' (expect empty) codegen.ok=%s error='%s'" % [String(stack.output_alpha), removed_result.ok(), removed_result.error])

	history.undo()
	await plugin.get_tree().process_frame
	var alpha_layer_present: bool = GSTStackOps.find_index(stack, alpha_layer.id) != -1
	_check("14c", stack.output_alpha == alpha_layer.id and alpha_layer_present, "undo remove alpha layer: output_alpha='%s' (expect '%s'), layer present=%s" % [String(stack.output_alpha), String(alpha_layer.id), alpha_layer_present])

	history.redo()
	await plugin.get_tree().process_frame
	var alpha_layer_gone_again: bool = GSTStackOps.find_index(stack, alpha_layer.id) == -1
	_check("14d", stack.output_alpha == &"" and alpha_layer_gone_again, "redo remove alpha layer: output_alpha='%s' (expect empty), layer present=%s (expect false)" % [String(stack.output_alpha), not alpha_layer_gone_again])

	undo.remove_layer(color_layer.id)
	await plugin.get_tree().process_frame
	var removed_result_2: GSTCodegenResult = GSTCodegen.generate_result(stack, library)
	_check("14e", stack.output_color == &"" and removed_result_2.ok(), "remove output_color's layer: output_color='%s' (expect empty) codegen.ok=%s error='%s'" % [String(stack.output_color), removed_result_2.ok(), removed_result_2.error])

	history.undo()
	await plugin.get_tree().process_frame
	var color_layer_present: bool = GSTStackOps.find_index(stack, color_layer.id) != -1
	_check("14f", stack.output_color == color_layer.id and color_layer_present, "undo remove color layer: output_color='%s' (expect '%s'), layer present=%s" % [String(stack.output_color), String(color_layer.id), color_layer_present])

	history.redo()
	await plugin.get_tree().process_frame
	var color_layer_gone_again: bool = GSTStackOps.find_index(stack, color_layer.id) == -1
	_check("14g", stack.output_color == &"" and color_layer_gone_again, "redo remove color layer: output_color='%s' (expect empty), layer present=%s (expect false)" % [String(stack.output_color), not color_layer_gone_again])

	# Unwind 6 actions: remove(color) redo, remove(alpha) redo,
	# set_output_alpha, set_output_color, add alpha_layer, add color_layer.
	for i: int in range(6):
		history.undo()
		await plugin.get_tree().process_frame
	_check("14h", not history.has_undo() and stack.layers.is_empty() and stack.output_color == &"" and stack.output_alpha == &"", "excursion fully unwound: has_undo=%s layers=%d output_color='%s' output_alpha='%s'" % [history.has_undo(), stack.layers.size(), String(stack.output_color), String(stack.output_alpha)])


## A native property edit registers a property-undo action pointed at the
## layer's own GSTLayer instance (GSTUndo.commit_property_change, the call
## gst_inspector_column.gd's native rows make once a gesture finishes). A
## structural remove committed after it, then undone, must reinsert that same
## instance so the earlier property-edit undo still lands on it, and the
## inspector column must edit that instance after the remove-undo. Unwinds
## back to an empty stack.
func _run_slider_remove_undo_identity_excursion(plugin: EditorPlugin, panel: GSTMainPanel, undo: GSTUndo) -> void:
	var stack: GSTStack = panel.get_stack()
	var history: UndoRedo = _get_history(panel)
	var inspector: GSTInspectorColumn = panel.get_inspector_column()

	var layer: GSTLayer = undo.add_layer("generative/fbm", GSTLayer.Kind.FIELD, true)
	await plugin.get_tree().process_frame
	inspector.edit(layer.id)

	var old_gain: float = float(layer.get("gain"))
	var new_gain: float = 0.75
	layer.set(&"gain", new_gain)
	undo.commit_property_change(layer, &"gain", old_gain, new_gain)
	await plugin.get_tree().process_frame
	_check("16a", is_equal_approx(float(layer.get("gain")), new_gain), "slider commit gain=%s (expect %s)" % [layer.get("gain"), new_gain])

	var layer_instance_id: int = layer.get_instance_id()
	undo.remove_layer(layer.id)
	await plugin.get_tree().process_frame
	_check("16b", GSTStackOps.find_index(stack, layer.id) == -1, "layer removed: present=%s (expect false)" % [GSTStackOps.find_index(stack, layer.id) != -1])

	history.undo()
	await plugin.get_tree().process_frame
	var restored: GSTLayer = GSTStackOps.find_layer(stack, layer.id)
	var same_instance: bool = restored != null and is_same(restored, layer) and restored.get_instance_id() == layer_instance_id
	_check("16c", same_instance, "undo remove restores same instance: is_same=%s restored_id=%s original_id=%s" % [restored != null and is_same(restored, layer), restored.get_instance_id() if restored != null else -1, layer_instance_id])

	history.undo()
	await plugin.get_tree().process_frame
	var restored_after_slider_undo: GSTLayer = GSTStackOps.find_layer(stack, layer.id)
	var gain_reverted: bool = restored_after_slider_undo != null and is_equal_approx(float(restored_after_slider_undo.get("gain")), old_gain)
	_check("16d", gain_reverted, "undo slider after undo remove: gain=%s (expect %s)" % [restored_after_slider_undo.get("gain") if restored_after_slider_undo != null else null, old_gain])

	inspector.edit(layer.id)
	var edited_object: Object = inspector.get_edited_object()
	var inspector_tracks_instance: bool = edited_object != null and edited_object.get_instance_id() == layer_instance_id
	_check("16e", inspector_tracks_instance, "EditorInspector edits the restored instance: edited_id=%s (expect %s)" % [edited_object.get_instance_id() if edited_object != null else -1, layer_instance_id])

	inspector.edit(&"")
	history.undo()
	await plugin.get_tree().process_frame
	_check("16f", GSTStackOps.find_index(stack, layer.id) == -1 and not history.has_undo(), "excursion fully unwound: layer_gone=%s has_undo=%s" % [GSTStackOps.find_index(stack, layer.id) == -1, history.has_undo()])


func _run_codegen_check() -> void:
	var stack: GSTStack = GSTStack.new()
	var library: GSTLibrary = GSTLibrary.new()
	library.scan()
	var fbm: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	var invert: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, invert.id, "x", fbm.id, library)
	stack.output_color = invert.id
	var result: GSTCodegenResult = GSTCodegen.generate_result(stack, library)
	_check("13", result.ok() and not result.code.is_empty(), "codegen of two-layer stack: error='%s' code_len=%d" % [result.error, result.code.length()])


## Preview column checks. Items 1-8 are numbered; setup checks use a "setup"
## prefix so they never collide with an item number.
func _run_phase5(plugin: EditorPlugin) -> void:
	for i: int in range(5):
		await plugin.get_tree().process_frame

	var panel: GSTMainPanel = plugin.get_panel() as GSTMainPanel
	_check("setup1", panel != null, "panel is null" if panel == null else "panel present")
	if panel == null:
		_finish(plugin)
		return

	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await plugin.get_tree().process_frame
	_check("setup2", panel.visible, "panel.visible after set_main_screen_editor=%s" % [panel.visible])
	await _dismiss_initial_start(plugin, panel)

	var stack_list: GSTStackList = panel.get_stack_list()
	var undo: GSTUndo = panel.get_undo()
	var library: GSTLibrary = panel.get_library()
	var stack: GSTStack = panel.get_stack()
	var preview: GSTPreview = panel.get_preview()
	var history: UndoRedo = _get_history(panel)

	var checker: GSTLayer = await _run_phase5_checker_render(plugin, panel, stack_list, undo, preview)
	await _run_phase5_preset_switch(plugin, panel)
	await _run_phase5_layer_preview(plugin, panel, stack_list, checker)
	var tex_layer: GSTLayer = await _run_phase5_texture_source(plugin, panel, stack_list, undo, preview, checker)
	await _run_phase5_screen_source(plugin, panel, stack_list, undo, preview, tex_layer)
	await _run_phase5_coord_space(plugin, panel, stack_list, undo, history)
	await _run_phase5_codegen_error(plugin, panel, library)

	_finish(plugin)


## Item 1: a generative/checker layer renders non-uniform pixels (cells
## defaults to 8, so the default render is not one uniform cell).
## Item 2: editing checker's coord.scale through the production
## gst_inspector_column.gd row's own EditorProperty.emit_changed(), as a
## slider drag would. Selecting checker makes the column build its coord
## rows. Asserts the material's uniform and the rendered image both change
## after the edit.
func _run_phase5_checker_render(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, undo: GSTUndo, preview: GSTPreview) -> GSTLayer:
	var checker: GSTLayer = stack_list.add_layer_by_entry_id("generative/checker")
	undo.set_output_color(checker.id)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var img1: Image = preview.get_viewport_image()
	var nonuniform: bool = img1 != null and not _image_is_uniform(img1)
	var checker_outside_viewport: bool = preview.get_child_count() >= 2 and preview.get_child(0) is ColorRect and preview.get_child(1) is SubViewportContainer
	_check("1", nonuniform and checker_outside_viewport, "checker layer nonuniform=%s UI checker outside viewport=%s img_null=%s" % [nonuniform, checker_outside_viewport, img1 == null])

	var coord: GSTCoordBlock = checker.coord
	var old_scale: Vector2 = coord.scale
	var new_scale: Vector2 = old_scale * 6.0
	stack_list.select_layer(checker.id)
	await plugin.get_tree().process_frame
	await plugin.get_tree().process_frame
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var ep: EditorProperty = inspector.find_coord_editor_property(&"scale")
	var found_prop: bool = ep != null
	if found_prop:
		ep.emit_changed(&"scale", new_scale)
		await plugin.get_tree().process_frame
		await plugin.get_tree().process_frame

	var uniform_name: String = GSTUniformNames.coord_scale(checker.id)
	var uniform_value: Variant = panel.get_shader_material().get_shader_parameter(uniform_name)
	var uniform_changed: bool = uniform_value is Vector2 and (uniform_value as Vector2).is_equal_approx(new_scale)
	var img2: Image = preview.get_viewport_image()
	var image_changed: bool = img2 != null and not _images_equal(img1, img2)
	_check("2", found_prop and uniform_changed and image_changed, "checker scale via real production EditorProperty row found=%s coord.scale=%s uniform=%s (expect %s) image_changed=%s" % [found_prop, coord.scale, uniform_value, new_scale, image_changed])
	return checker


## Item 3: switching to the text preset keeps the same ShaderMaterial
## instance on the new target node, shows the screen_uv suggestion
## (coord_space is still uv), and renders a different non-uniform image than
## the sprite preset (a Label's per-glyph quads read the checker field
## differently from a TextureRect's single quad). full_rect and back to
## sprite keep rendering non-uniform pixels with the same material instance.
func _run_phase5_preset_switch(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var preview: GSTPreview = panel.get_preview()
	var material_before: ShaderMaterial = preview.get_current_target_material()
	var img_sprite: Image = preview.get_viewport_image()

	panel._on_preset_selected(1) # "text"
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var material_after_text: ShaderMaterial = preview.get_current_target_material()
	var same_instance: bool = material_after_text != null and material_after_text == material_before
	var suggests: bool = panel.get_message_label().text.contains("screen_uv")
	var img_text: Image = preview.get_viewport_image()
	var text_nonuniform: bool = img_text != null and not _image_is_uniform(img_text)
	var differs_from_sprite: bool = img_text != null and img_sprite != null and not _images_equal(img_sprite, img_text)
	_check("3a", same_instance and suggests and text_nonuniform and differs_from_sprite, "preset=text material_same=%s message='%s' text_nonuniform=%s differs_from_sprite=%s" % [same_instance, panel.get_message_label().text, text_nonuniform, differs_from_sprite])

	panel._on_preset_selected(2) # "full_rect"
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var img_full: Image = preview.get_viewport_image()
	var full_nonuniform: bool = img_full != null and not _image_is_uniform(img_full)

	panel._on_preset_selected(0) # "sprite"
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var img_sprite_again: Image = preview.get_viewport_image()
	var sprite_nonuniform: bool = img_sprite_again != null and not _image_is_uniform(img_sprite_again)
	var still_same_instance: bool = preview.get_current_target_material() == material_before
	_check("3b", full_nonuniform and sprite_nonuniform and still_same_instance, "full_rect_nonuniform=%s sprite_nonuniform=%s material_still_same=%s" % [full_nonuniform, sprite_nonuniform, still_same_instance])


## Item 4: the selected layer's secondary menu enters diagnostic preview
## without changing stack output or undo history. Return restores the finished
## effect and the exact pre-preview shader text.
func _run_phase5_layer_preview(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, checker: GSTLayer) -> void:
	var stack: GSTStack = panel.get_stack()
	stack_list.select_layer(checker.id)
	await plugin.get_tree().process_frame

	var code_before_preview: String = panel.get_shader_material().shader.code
	var layers_before: int = stack.layers.size()
	var output_color_before: StringName = stack.output_color
	var output_alpha_before: StringName = stack.output_alpha
	var history_count: int = panel.get_watched_history().get_history_count()

	panel.get_layer_menu().get_popup().id_pressed.emit(0)
	await plugin.get_tree().process_frame
	var diagnostic_code: String = panel.get_shader_material().shader.code
	var stack_unchanged: bool = stack.layers.size() == layers_before and stack.output_color == output_color_before and stack.output_alpha == output_alpha_before
	var viewing_ok: bool = panel.get_preview_layer_id() == checker.id and panel.get_return_to_effect_button().visible
	_check("4a", viewing_ok and stack_unchanged and panel.get_watched_history().get_history_count() == history_count and diagnostic_code.contains("COLOR = vec4(vec3(l%s), 1.0);" % String(checker.id)), "preview_id='%s' return_visible=%s stack_unchanged=%s" % [String(panel.get_preview_layer_id()), panel.get_return_to_effect_button().visible, stack_unchanged])

	panel.get_return_to_effect_button().pressed.emit()
	await plugin.get_tree().process_frame
	var code_after: String = panel.get_shader_material().shader.code
	_check("4b", panel.get_preview_layer_id() == &"" and not panel.get_return_to_effect_button().visible and code_after == code_before_preview, "returned_to_effect=%s code_restored=%s" % [panel.get_preview_layer_id() == &"", code_after == code_before_preview])


## Item 5: a lone source/texture layer renders the preview image. The
## viewport center pixel is compared to the source PNG's center pixel within
## a tolerance for render-pipeline filtering and color management.
func _run_phase5_texture_source(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, undo: GSTUndo, preview: GSTPreview, checker: GSTLayer) -> GSTLayer:
	undo.remove_layer(checker.id)
	await plugin.get_tree().process_frame

	var tex_layer: GSTLayer = stack_list.add_layer_by_entry_id("source/texture")
	undo.set_output_color(tex_layer.id)
	for i: int in range(3):
		await plugin.get_tree().process_frame

	var viewport_img: Image = preview.get_viewport_image()
	var close: bool = false
	var got: Color = Color.BLACK
	var want: Color = Color.BLACK
	if viewport_img != null:
		var source_texture: Texture2D = load("res://addons/goshade_turbo/assets/preview_default.png") as Texture2D
		var source_img: Image = source_texture.get_image()
		got = viewport_img.get_pixel(viewport_img.get_width() / 2, viewport_img.get_height() / 2)
		want = source_img.get_pixel(source_img.get_width() / 2, source_img.get_height() / 2)
		close = _colors_close(got, want, 0.12)
	_check("5", close and absf(got.a - want.a) <= 0.02, "texture source center pixel got=%s want=%s alpha_delta=%.4f" % [got, want, absf(got.a - want.a)])
	return tex_layer


## Item 6: a lone source/screen layer reads the background through
## hint_screen_texture and renders the same image.
func _run_phase5_screen_source(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, undo: GSTUndo, preview: GSTPreview, tex_layer: GSTLayer) -> void:
	undo.remove_layer(tex_layer.id)
	await plugin.get_tree().process_frame

	var screen_layer: GSTLayer = stack_list.add_layer_by_entry_id("source/screen")
	undo.set_output_color(screen_layer.id)
	for i: int in range(3):
		await plugin.get_tree().process_frame

	var viewport_img: Image = preview.get_viewport_image()
	var close: bool = false
	var got: Color = Color.BLACK
	var want: Color = Color.BLACK
	if viewport_img != null:
		var source_texture: Texture2D = load("res://addons/goshade_turbo/assets/preview_default.png") as Texture2D
		var source_img: Image = source_texture.get_image()
		got = viewport_img.get_pixel(viewport_img.get_width() / 2, viewport_img.get_height() / 2)
		want = source_img.get_pixel(source_img.get_width() / 2, source_img.get_height() / 2)
		close = _colors_close(got, want, 0.12)
	_check("6", close and absf(got.a - want.a) <= 0.02, "screen source center pixel got=%s want=%s alpha_delta=%.4f" % [got, want, absf(got.a - want.a)])


## Item 7: switching coord space to local through GSTUndo.set_coord_space
## declares gst_rect_size equal to the preview node's rect and the
## vertex()-set varying; undo restores uv. Items 7c/7d: a resize with no
## structural stack edit in between must still push the new target rect into
## gst_rect_size (the target_rect_changed path), and a scale-1 checker must
## render identically under local and uv at that resized rect.
func _run_phase5_coord_space(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, undo: GSTUndo, history: UndoRedo) -> void:
	var stack: GSTStack = panel.get_stack()
	var preview: GSTPreview = panel.get_preview()

	panel._on_coord_space_selected(2) # "local"
	await plugin.get_tree().process_frame
	var rect_uniform: Variant = panel.get_shader_material().get_shader_parameter("gst_rect_size")
	var target_size: Vector2 = preview.get_target_rect_size()
	var rect_ok: bool = rect_uniform is Vector2 and (rect_uniform as Vector2).is_equal_approx(target_size)
	var has_varying: bool = panel.get_shader_material().shader.code.contains("varying vec2 local_pos;")
	_check("7a", rect_ok and has_varying, "gst_rect_size=%s target=%s has_varying=%s" % [rect_uniform, target_size, has_varying])

	history.undo()
	await plugin.get_tree().process_frame
	var restored: bool = stack.coord_space == GSTStack.CoordSpace.UV
	_check("7b", restored, "undo restores coord_space to uv: %s (actual %d)" % [restored, stack.coord_space])

	await _run_phase5_local_resize(plugin, panel, stack_list, undo, preview)


## Item 7c: a scale-1 checker is added under local space before the resize,
## so no GSTUndo structural edit runs between the resize and the readback.
## Every structural edit forces a full resync that re-reads the live size and
## would mask a stale uniform; here only
## GSTPreview.target_rect_changed -> GSTMainPanel._on_target_rect_changed can
## set gst_rect_size correctly.
func _run_phase5_local_resize(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, undo: GSTUndo, preview: GSTPreview) -> void:
	panel._on_coord_space_selected(2) # "local"
	await plugin.get_tree().process_frame

	var checker: GSTLayer = stack_list.add_layer_by_entry_id("generative/checker")
	undo.set_output_color(checker.id)
	for i: int in range(3):
		await plugin.get_tree().process_frame

	var before_size: Vector2 = preview.get_target_rect_size()
	preview.custom_minimum_size = before_size + Vector2(96.0, 64.0)
	for i: int in range(2):
		await plugin.get_tree().process_frame

	var after_size: Vector2 = preview.get_target_rect_size()
	var resized: bool = not after_size.is_equal_approx(before_size)
	var rect_uniform: Variant = panel.get_shader_material().get_shader_parameter("gst_rect_size")
	var rect_ok: bool = rect_uniform is Vector2 and (rect_uniform as Vector2).is_equal_approx(after_size)
	_check("7c", resized and rect_ok, "resized=%s before=%s after=%s gst_rect_size=%s" % [resized, before_size, after_size, rect_uniform])

	await _run_phase5_checker_grid_evidence(plugin, panel, stack_list, undo, preview)

	preview.custom_minimum_size = Vector2.ZERO


## Item 7d: per-pixel evidence that a coord-block scale of 1.0 under local
## matches uv, at the rect 7c resized.
##
## Samples are the rect's four corners. mod(floor(x)+floor(y), 2) is constant
## along the x == y diagonal regardless of scale or offset, so a diagonal
## sample set would be vacuous. The (0.5, 0.5) offset makes the four corners
## land one in each quadrant, parities [0, 1, 1, 0], independent of where the
## 8-cell grid's boundaries fall.
##
## Preset is switched to full_rect first so every sampled fraction lands
## inside the target node (under the sprite preset a corner sample reads
## alpha 0, outside the node).
func _run_phase5_checker_grid_evidence(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, undo: GSTUndo, preview: GSTPreview) -> void:
	panel._on_preset_selected(2) # "full_rect"
	for i: int in range(3):
		await plugin.get_tree().process_frame

	panel._on_coord_space_selected(0) # "uv"
	await plugin.get_tree().process_frame

	var grid: GSTLayer = stack_list.add_layer_by_entry_id("generative/checker")
	undo.set_output_color(grid.id)
	_set_coord_property(panel, grid.coord, &"offset", Vector2(0.5, 0.5))
	for i: int in range(2):
		await plugin.get_tree().process_frame

	var fracs: Array[Vector2] = [Vector2(0.125, 0.125), Vector2(0.125, 0.875), Vector2(0.875, 0.125), Vector2(0.875, 0.875)]

	var uv_samples: Array[Color] = _sample_points(preview.get_viewport_image(), fracs)
	var uv_nonuniform: bool = not _colors_all_equal(uv_samples)
	_check("7d1", uv_nonuniform, "uv checker corner samples=%s (expect not all equal)" % [uv_samples])

	panel._on_coord_space_selected(2) # "local"
	for i: int in range(2):
		await plugin.get_tree().process_frame

	var local_samples: Array[Color] = _sample_points(preview.get_viewport_image(), fracs)
	var matches_uv: bool = _colors_all_close(local_samples, uv_samples, 0.05)
	_check("7d2", uv_nonuniform and matches_uv, "local corner samples=%s match uv corner samples=%s (tolerance 0.05)" % [local_samples, uv_samples])

	# Negative control: changing rotation under local must alter a substantial
	# fraction of the rendered frame. Corner parity is an invalid oracle for a
	# checker because a rotated grid can still produce the same four values.
	var local_unrotated_image: Image = preview.get_viewport_image()
	_set_coord_property(panel, grid.coord, &"rotation", 0.4)
	var local_rotated_image: Image = null
	var changed_fraction: float = 0.0
	for i: int in range(8):
		await plugin.get_tree().process_frame
		local_rotated_image = preview.get_viewport_image()
		changed_fraction = _image_changed_fraction(local_unrotated_image, local_rotated_image, 0.05)
		if changed_fraction >= 0.1:
			break

	var same_frame_size: bool = local_unrotated_image != null and local_rotated_image != null and local_unrotated_image.get_size() == local_rotated_image.get_size()
	_check("7d3", same_frame_size and changed_fraction >= 0.1, "local rotation=0.4 same_frame_size=%s changed_fraction=%.4f (expect >=0.1)" % [same_frame_size, changed_fraction])


## Item 8: mutating the stack directly through GSTStackOps (bypassing
## GSTUndo) and re-emitting stack_changed forces a resync. An unwired
## filter/pixelate "source" slot fails codegen; the message label shows the
## error and the material's code stays the last good one; removing the
## filter recovers.
func _run_phase5_codegen_error(plugin: EditorPlugin, panel: GSTMainPanel, library: GSTLibrary) -> void:
	var stack: GSTStack = panel.get_stack()
	var last_good_code: String = panel.get_shader_material().shader.code

	var filter_layer: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	panel.stack_changed.emit()
	await plugin.get_tree().process_frame
	var error_shown: bool = not panel.get_message_label().text.is_empty()
	var code_unchanged: bool = panel.get_shader_material().shader.code == last_good_code
	_check("8a", error_shown and code_unchanged, "forced codegen error: message='%s' code_unchanged=%s" % [panel.get_message_label().text, code_unchanged])

	GSTStackOps.remove_layer(stack, filter_layer.id, library)
	panel.stack_changed.emit()
	await plugin.get_tree().process_frame
	var recovered: bool = panel.get_message_label().text.is_empty()
	_check("8b", recovered, "recovery after removing the filter: message='%s'" % [panel.get_message_label().text])


## Persistence and export. Builds a three-layer stack through the panel, then
## round-trips it through save/New/open (.tres, GSTStackIO) and
## export/mutate/confirm/reopen (.gdshader, GSTExport). Every step goes
## through the panel's EditorFileDialog/ConfirmationDialog handlers
## (_on_save_as_file_selected, _on_open_file_selected,
## _on_export_file_selected, _on_overwrite_confirmed,
## _on_reopen_shader_file_selected), not the path-taking
## open_path/save_to_path/export_to_path/reopen_shader_path seams they call,
## so the overwrite ConfirmationDialog is exercised. Files land under
## sandbox/stacks/ and sandbox/exports/ and are deleted at the end of the run
## regardless of pass/fail.
func _run_phase6(plugin: EditorPlugin) -> void:
	for i: int in range(5):
		await plugin.get_tree().process_frame

	var panel: GSTMainPanel = plugin.get_panel() as GSTMainPanel
	_check("setup1", panel != null, "panel is null" if panel == null else "panel present")
	if panel == null:
		_finish(plugin)
		return

	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await plugin.get_tree().process_frame
	_check("setup2", panel.visible, "panel.visible after set_main_screen_editor=%s" % [panel.visible])
	await _dismiss_initial_start(plugin, panel)

	var stack_path: String = "res://sandbox/stacks/gst_editor_smoke_phase6.tres"
	var export_path: String = "res://sandbox/exports/gst_editor_smoke_phase6.gdshader"
	var headerless_path: String = "res://sandbox/exports/gst_editor_smoke_phase6_headerless.gdshader"

	var ids: Dictionary = await _run_phase6_build_and_save(plugin, panel, stack_path)
	await _run_phase6_new(plugin, panel, ids)
	await _run_phase6_export_dialog_opens(plugin, panel)
	await _run_phase6_open(plugin, panel, stack_path, ids)
	await _run_phase6_export_and_overwrite_gate(plugin, panel, export_path)
	await _run_phase6_reopen(plugin, panel, export_path, ids)
	await _run_phase6_headerless_reopen_refusal(plugin, panel, headerless_path)

	var smoke_paths: Array[String] = [stack_path, export_path, headerless_path]
	_cleanup_phase6_files(smoke_paths)
	_finish(plugin)


## Item 1: a checker generator (output_color), an fbm generator with a
## non-default int param, and an invert field op wired to fbm. Item 2:
## _on_save_as_file_selected writes under sandbox/stacks/.
func _run_phase6_build_and_save(plugin: EditorPlugin, panel: GSTMainPanel, stack_path: String) -> Dictionary:
	var stack_list: GSTStackList = panel.get_stack_list()
	var undo: GSTUndo = panel.get_undo()

	var checker: GSTLayer = stack_list.add_layer_by_entry_id("generative/checker")
	var fbm: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	var invert: GSTLayer = stack_list.add_layer_by_entry_id("fieldops/invert")
	undo.assign_slot(invert.id, "x", fbm.id)
	fbm.params["octaves"] = 6
	undo.set_output_color(checker.id)
	await plugin.get_tree().process_frame
	_check("1", checker != null and fbm != null and invert != null, "three layers added: checker=%s fbm=%s invert=%s" % [checker, fbm, invert])

	panel._on_save_as_file_selected(stack_path)
	var save_ok: bool = panel.get_current_path() == stack_path and panel.get_message_label().text.is_empty() and FileAccess.file_exists(stack_path)
	_check("2", save_ok, "_on_save_as_file_selected: current_path='%s' (expect '%s') message='%s' file_exists=%s" % [panel.get_current_path(), stack_path, panel.get_message_label().text, FileAccess.file_exists(stack_path)])

	return {"checker": checker.id, "fbm": fbm.id, "invert": invert.id}


## Item 3: New creates and activates a new GSTDocument (gst_main_panel.gd's
## open_document) and registers no undo action; the old document's history
## and content are untouched by navigation.
##
## Sequence: New creates a GSTDocument with its own empty UndoRedo and leaves
## the old history unchanged; activate_document(old) reinstalls the same
## GSTStack instance (is_same), its three layers, and current_path with no
## history change; the old history still undoes/redoes its last action
## (set_output_color in _run_phase6_build_and_save); activate_document(new)
## returns to the empty, actionless state _run_phase6_open continues from.
func _run_phase6_new(plugin: EditorPlugin, panel: GSTMainPanel, ids: Dictionary) -> void:
	var old_doc: GSTDocument = panel.get_active_document()
	var old_stack: GSTStack = panel.get_stack()
	var old_path: String = panel.get_current_path()
	var old_history: UndoRedo = panel.get_watched_history()
	var old_layer_count: int = old_stack.layers.size()
	var old_action_count: int = old_history.get_history_count()

	panel._on_new_pressed()
	await plugin.get_tree().process_frame
	await _cancel_picker(plugin, panel)
	var new_doc: GSTDocument = panel.get_active_document()
	var new_stack: GSTStack = panel.get_stack()
	var new_history: UndoRedo = panel.get_watched_history()
	var new_ok: bool = new_stack.layers.is_empty() and panel.get_current_path().is_empty() and not is_same(new_stack, old_stack) and new_doc != old_doc
	var new_history_own_and_empty: bool = new_history != old_history and not new_history.has_undo()
	var old_history_untouched: bool = old_history.get_history_count() == old_action_count and old_history.has_undo()
	_check("3a", new_ok and new_history_own_and_empty and old_history_untouched, "New creates and activates an independent, actionless document: layers=%d current_path='%s' new_instance=%s new_history_own_empty=%s old_history_untouched=%s" % [new_stack.layers.size(), panel.get_current_path(), not is_same(new_stack, old_stack), new_history_own_and_empty, old_history_untouched])

	panel.activate_document(old_doc)
	var restored_1: GSTStack = panel.get_stack()
	var layer_ids_match: bool = restored_1.layers.size() == 3 and restored_1.layers[0].id == ids["checker"] and restored_1.layers[1].id == ids["fbm"] and restored_1.layers[2].id == ids["invert"]
	var reactivate_ok: bool = is_same(restored_1, old_stack) and restored_1.layers.size() == old_layer_count and layer_ids_match and panel.get_current_path() == old_path and panel.get_watched_history() == old_history and old_history.get_history_count() == old_action_count
	_check("3b", reactivate_ok, "activate_document(old) restores the previous document unchanged, no history change: is_same=%s layers=%d (expect %d) layer_ids_match=%s current_path='%s' (expect '%s')" % [is_same(restored_1, old_stack), restored_1.layers.size(), old_layer_count, layer_ids_match, panel.get_current_path(), old_path])

	old_history.undo()
	await plugin.get_tree().process_frame
	var undo_ok: bool = panel.get_stack() == old_stack and old_stack.output_color == ids["invert"]
	_check("3c", undo_ok, "old document's own history still undoes its last action (set_output_color) independent of navigation: output_color='%s' (expect '%s')" % [String(old_stack.output_color), String(ids["invert"])])

	old_history.redo()
	await plugin.get_tree().process_frame
	var redo_ok: bool = old_stack.output_color == ids["checker"]
	_check("3d", redo_ok, "redo re-applies set_output_color: output_color='%s' (expect '%s')" % [String(old_stack.output_color), String(ids["checker"])])

	panel.activate_document(new_doc)
	var final_stack: GSTStack = panel.get_stack()
	var final_ok: bool = is_same(final_stack, new_stack) and final_stack.layers.is_empty() and panel.get_current_path().is_empty() and final_stack.output_color == &"" and panel.get_watched_history() == new_history and not new_history.has_undo()
	_check("3e", final_ok, "re-activating the New document restores its own empty, actionless state: is_same=%s layers=%d current_path='%s' has_undo=%s" % [is_same(final_stack, new_stack), final_stack.layers.size(), panel.get_current_path(), new_history.has_undo()])


## Pressing Export with no current_path (the panel is on the empty New'd
## stack) opens the export EditorFileDialog. Export never writes without a
## picked target; Save falls back to the current path when one exists.
func _run_phase6_export_dialog_opens(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var path_before: String = panel.get_current_path()
	panel._on_export_pressed()
	await plugin.get_tree().process_frame
	var dialog_visible: bool = panel.is_export_dialog_visible()
	_check("3f", path_before.is_empty() and dialog_visible, "Export press with no current_path opens the export dialog: current_path='%s' (expect '') dialog_visible=%s" % [path_before, dialog_visible])
	# hide_export_dialog() defaults to abandon=true, which clears
	# _pending_export. EditorFileDialog.hide() does not emit "canceled" (only
	# the Cancel button/Esc path does, dialogs.cpp AcceptDialog::
	# _cancel_pressed), so a stale capture left here would redirect
	# _run_phase6_export_and_overwrite_gate's later _on_export_file_selected
	# call onto this empty document.
	panel.hide_export_dialog()


## Item 4: _on_open_file_selected reloads the same three layer ids in the
## same order, fbm's non-default octaves param survives, and the preview
## (driven from the checker output_color) renders non-uniform pixels.
func _run_phase6_open(plugin: EditorPlugin, panel: GSTMainPanel, stack_path: String, ids: Dictionary) -> void:
	panel._on_open_file_selected(stack_path)
	for i: int in range(3):
		await plugin.get_tree().process_frame

	var stack: GSTStack = panel.get_stack()
	var ids_match: bool = stack.layers.size() == 3 and stack.layers[0].id == ids["checker"] and stack.layers[1].id == ids["fbm"] and stack.layers[2].id == ids["invert"]
	var opened_fbm: GSTLayer = stack.layers[1] if stack.layers.size() > 1 else null
	var params_match: bool = opened_fbm != null and int(opened_fbm.params.get("octaves", -1)) == 6
	var img: Image = panel.get_preview().get_viewport_image()
	var nonuniform: bool = img != null and not _image_is_uniform(img)
	_check("4", ids_match and params_match and nonuniform, "_on_open_file_selected: ids_match=%s params_match=%s (octaves=%s) preview_nonuniform=%s current_path='%s' (expect '%s')" % [ids_match, params_match, opened_fbm.params.get("octaves") if opened_fbm != null else null, nonuniform, panel.get_current_path(), stack_path])


## Item 5: _on_export_file_selected writes a file with a header line. Items
## 6-7: mutating one body byte on disk makes a re-selected export path show
## the overwrite ConfirmationDialog and leave the file untouched;
## _on_overwrite_confirmed then overwrites it and hides the dialog.
func _run_phase6_export_and_overwrite_gate(plugin: EditorPlugin, panel: GSTMainPanel, export_path: String) -> void:
	panel._on_export_file_selected(export_path)
	await plugin.get_tree().process_frame
	var export_exists: bool = FileAccess.file_exists(export_path)
	var header_present: bool = export_exists and GSTOverwriteCheck.find_header_line(_read_file(export_path))["found"]
	_check("5", export_exists and header_present, "_on_export_file_selected: exists=%s header_present=%s" % [export_exists, header_present])

	var mutated_text: String = _mutate_body_line(_read_file(export_path))
	_write_file(export_path, mutated_text)

	panel._on_export_file_selected(export_path)
	await plugin.get_tree().process_frame
	var dialog_visible: bool = panel.is_overwrite_dialog_visible()
	var file_unchanged: bool = _read_file(export_path) == mutated_text
	_check("6", dialog_visible and file_unchanged, "re-selecting a differing export target: dialog_visible=%s (expect true) file_unchanged=%s (expect true)" % [dialog_visible, file_unchanged])

	panel._on_overwrite_confirmed()
	await plugin.get_tree().process_frame
	var overwritten: bool = _read_file(export_path) != mutated_text
	var dialog_hidden: bool = not panel.is_overwrite_dialog_visible()
	_check("7", overwritten and dialog_hidden, "_on_overwrite_confirmed overwrites: overwritten=%s (expect true) dialog_hidden=%s (expect true)" % [overwritten, dialog_hidden])


## Item 8: _on_reopen_shader_file_selected rebuilds a stack with the same
## three layer ids the original build produced (ids are stable across save,
## export, and reopen).
func _run_phase6_reopen(plugin: EditorPlugin, panel: GSTMainPanel, export_path: String, ids: Dictionary) -> void:
	panel._on_reopen_shader_file_selected(export_path)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var stack: GSTStack = panel.get_stack()
	var ids_match: bool = stack.layers.size() == 3 and stack.layers[0].id == ids["checker"] and stack.layers[1].id == ids["fbm"] and stack.layers[2].id == ids["invert"]
	_check("8", ids_match, "_on_reopen_shader_file_selected rebuilds the same ids: %s (current_path='%s', expect empty)" % [ids_match, panel.get_current_path()])


## Item 9: a .gdshader with no "// stack:" header is refused, the reason
## lands in the message label, and the stack item 8 rebuilt stays in place.
func _run_phase6_headerless_reopen_refusal(plugin: EditorPlugin, panel: GSTMainPanel, headerless_path: String) -> void:
	_write_file(headerless_path, "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0); }\n")
	var stack_before: GSTStack = panel.get_stack()

	panel._on_reopen_shader_file_selected(headerless_path)
	await plugin.get_tree().process_frame
	var refused: bool = panel.get_message_label().text.contains("header")
	var stack_unchanged: bool = panel.get_stack() == stack_before
	_check("9", refused and stack_unchanged, "reopen of a headerless file is refused (B8): message='%s' stack_unchanged=%s" % [panel.get_message_label().text, stack_unchanged])


## Three-recipe proof. For each recipe: builds the stack through GSTUndo's
## public actions (add, wire, output) and commit_property_change for params,
## captures the shader text, undoes to an empty stack, redoes back to the
## captured text byte for byte with a non-uniform preview, then loads the
## shipped recipe through open_recipe() and checks the panel's codegen text
## equals a fresh GSTStackIO.load plus codegen of the same recipe file. Ids
## may differ between the panel-built stack and the shipped recipe, so the
## open check never compares against the earlier capture.
func _run_phase7(plugin: EditorPlugin) -> void:
	for i: int in range(5):
		await plugin.get_tree().process_frame

	var panel: GSTMainPanel = plugin.get_panel() as GSTMainPanel
	_check("setup1", panel != null, "panel is null" if panel == null else "panel present")
	if panel == null:
		_finish(plugin)
		return

	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await plugin.get_tree().process_frame
	_check("setup2", panel.visible, "panel.visible after set_main_screen_editor=%s" % [panel.visible])
	await _dismiss_initial_start(plugin, panel)

	var library: GSTLibrary = panel.get_library()
	# Each _on_new_pressed() activates a new GSTDocument with its own UndoRedo,
	# so each helper captures its own history after its own New.

	await _run_phase7_dissolve(plugin, panel, library)
	await _run_phase7_sprite_holographic(plugin, panel, library)
	await _run_phase7_outline(plugin, panel, library)
	await _run_phase7_history_anchor(plugin, panel)

	_finish(plugin)


## Randomize. open_recipe("fire") puts a path-bearing GSTStack on the panel
## with no New in between, so undo/redo drive panel.get_watched_history().
## Presses the Randomize handler and checks: at least one param changed,
## every param stays inside its manifest range, the preview renders
## non-uniform, one undo restores the shader body byte for byte to the
## post-open body (next_id never reverts on undo, so the comparison is scoped
## below the "// stack:" header via _codegen_body), one redo re-applies the
## randomized body, and Randomize is disabled after New. The recipe-open flag
## lives on the GSTDocument: activating the fire document re-enables
## Randomize with its content unchanged, activating the New document disables
## it, and the fire document's history still undoes its randomize action back
## to the post-open values.
##
## Items "1b"/"3b"/"4b"/"5b": the fbm layer's "gain" param read off the real
## EditorProperty widget's Range control (SpinBox/EditorSpinSlider on 4.6.2),
## not the GSTLayer model, before randomize, after randomize, after undo, and
## after redo. Proves GSTMainPanel._refresh_inspector makes the built
## inspector column re-read a param GSTRandomize.apply wrote.
##
## Item "1c" and "3b"'s expected(seed=...) value:
## GSTMainPanel.set_randomize_rng seeds _on_randomize_pressed's RNG; an
## independently loaded copy of the recipe run through GSTRandomize.randomize
## with the same seed produces the exact gain value "3b" asserts, so "3b"
## cannot pass or fail by chance.
func _run_phase8(plugin: EditorPlugin) -> void:
	for i: int in range(5):
		await plugin.get_tree().process_frame

	var panel: GSTMainPanel = plugin.get_panel() as GSTMainPanel
	_check("setup1", panel != null, "panel is null" if panel == null else "panel present")
	if panel == null:
		_finish(plugin)
		return

	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await plugin.get_tree().process_frame
	_check("setup2", panel.visible, "panel.visible after set_main_screen_editor=%s" % [panel.visible])
	await _dismiss_initial_start(plugin, panel)

	var library: GSTLibrary = panel.get_library()

	panel.open_recipe("fire")
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var fire_doc: GSTDocument = panel.get_active_document()
	var post_open_body: String = _codegen_body(panel.get_shader_material().shader.code)
	var pre_params: Dictionary = _snapshot_params(panel.get_stack(), library)
	var history: UndoRedo = panel.get_watched_history()
	var randomize_enabled_after_open: bool = not panel.get_randomize_button().disabled

	# Select fire's generative/fbm layer (id "0", param "gain", float,
	# manifest range [0.2, 0.8], fire.tres leaves it at the default 0.5) so
	# the inspector column's EditorProperty widget for it is built. gain is
	# inside its range, which avoids the PROPERTY_HINT_RANGE clamp a param
	# outside its manifest range would cause.
	var stack_list: GSTStackList = panel.get_stack_list()
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var gain_layer: GSTLayer = GSTStackOps.find_layer(panel.get_stack(), &"0")
	stack_list.select_layer(&"0")
	panel.set_narrow_tab(1)
	for i: int in range(4):
		await plugin.get_tree().process_frame
	var pre_ep: EditorProperty = inspector.find_editor_property(&"gain", gain_layer)
	var settings_scroll: ScrollContainer = inspector.get_settings_scroll()
	if pre_ep != null:
		settings_scroll.ensure_control_visible(pre_ep)
		for i: int in range(2):
			await plugin.get_tree().process_frame
	var pre_displayed: float = _range_control_value(pre_ep)
	var pre_layer_value: float = float(gain_layer.get("gain"))
	var pre_visible: bool = pre_ep != null and pre_ep.is_visible_in_tree() and pre_ep.get_global_rect().intersects(settings_scroll.get_global_rect())
	_check("1b", pre_visible and absf(pre_displayed - pre_layer_value) < 0.01, "pre-randomize gain EditorProperty found=%s visible=%s displayed=%s layer=%s" % [pre_ep != null, pre_visible, pre_displayed, pre_layer_value])

	# Seed the handler's RNG so "3b" asserts an exact expected gain. The
	# expectation is GSTRandomize.randomize with an identically seeded
	# RandomNumberGenerator on a fresh load of the same recipe (same pattern
	# as tests/test_randomize_range.gd's test_same_seed_reproduces_same_values);
	# panel.set_randomize_rng feeds the live handler the same seed.
	var randomize_seed: int = 424242
	var expect_load: Dictionary = GSTStackIO.load("res://addons/goshade_turbo/recipes/fire.tres", library)
	_check("1c", expect_load["ok"], "expectation stack for the randomize seed loads: ok=%s" % [expect_load["ok"]])
	var expect_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	expect_rng.seed = randomize_seed
	var expected_changes: Dictionary = GSTRandomize.randomize(expect_load["stack"], library, expect_rng)
	var expected_gain: float = float(expected_changes.get(&"0", {}).get("gain", NAN))
	var apply_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	apply_rng.seed = randomize_seed
	panel.set_randomize_rng(apply_rng)

	panel._on_randomize_pressed()
	for i: int in range(2):
		await plugin.get_tree().process_frame

	var post_params: Dictionary = _snapshot_params(panel.get_stack(), library)
	var any_changed: bool = _any_param_changed(pre_params, post_params)
	_check("1", randomize_enabled_after_open and any_changed, "open_recipe(fire) + Randomize: button_enabled=%s at_least_one_param_changed=%s" % [randomize_enabled_after_open, any_changed])

	var in_range: bool = _every_param_in_range(panel.get_stack(), library)
	_check("2", in_range, "every param on the randomized stack stays inside its manifest range: %s" % [in_range])

	var img: Image = panel.get_preview().get_viewport_image()
	var nonuniform: bool = img != null and not _image_is_uniform(img)
	_check("3", nonuniform, "preview renders non-uniform pixels after randomize (img_null=%s)" % [img == null])

	var post_ep: EditorProperty = inspector.find_editor_property(&"gain", gain_layer)
	var post_displayed: float = _range_control_value(post_ep)
	var post_layer_value: float = float(gain_layer.get("gain"))
	var post_visible: bool = post_ep != null and post_ep.is_visible_in_tree() and post_ep.get_global_rect().intersects(settings_scroll.get_global_rect())
	var post_matches: bool = post_visible and absf(post_displayed - post_layer_value) < 0.01
	var post_matches_expected: bool = absf(post_displayed - expected_gain) < 0.01
	_check("3b", post_matches and post_matches_expected, "post-randomize gain EditorProperty found=%s visible=%s displayed=%s layer=%s expected(seed=%s)=%s matches_expected=%s" % [post_ep != null, post_visible, post_displayed, post_layer_value, randomize_seed, expected_gain, post_matches_expected])

	var randomized_body: String = _codegen_body(panel.get_shader_material().shader.code)

	history.undo()
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var body_after_undo: String = _codegen_body(panel.get_shader_material().shader.code)
	_check("4", body_after_undo == post_open_body, "undo restores every param to the recipe values: body matches post-open body byte for byte=%s" % [body_after_undo == post_open_body])

	var undo_ep: EditorProperty = inspector.find_editor_property(&"gain", gain_layer)
	var undo_displayed: float = _range_control_value(undo_ep)
	var undo_visible: bool = undo_ep != null and undo_ep.is_visible_in_tree() and undo_ep.get_global_rect().intersects(settings_scroll.get_global_rect())
	_check("4b", undo_visible and absf(undo_displayed - pre_layer_value) < 0.01, "undo gain EditorProperty found=%s visible=%s displayed=%s expected=%s" % [undo_ep != null, undo_visible, undo_displayed, pre_layer_value])

	history.redo()
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var body_after_redo: String = _codegen_body(panel.get_shader_material().shader.code)
	_check("5", body_after_redo == randomized_body, "redo re-applies the randomized values: body matches post-randomize body byte for byte=%s" % [body_after_redo == randomized_body])

	var redo_ep: EditorProperty = inspector.find_editor_property(&"gain", gain_layer)
	var redo_displayed: float = _range_control_value(redo_ep)
	var redo_visible: bool = redo_ep != null and redo_ep.is_visible_in_tree() and redo_ep.get_global_rect().intersects(settings_scroll.get_global_rect())
	_check("5b", redo_visible and absf(redo_displayed - post_layer_value) < 0.01, "redo gain EditorProperty found=%s visible=%s displayed=%s expected=%s" % [redo_ep != null, redo_visible, redo_displayed, post_layer_value])

	var doc_before_new: GSTDocument = fire_doc
	panel._on_new_pressed()
	for i: int in range(2):
		await plugin.get_tree().process_frame
	await _cancel_picker(plugin, panel)
	var new_doc: GSTDocument = panel.get_active_document()
	_check("6", panel.get_randomize_button().disabled, "Randomize disabled after New: disabled=%s" % [panel.get_randomize_button().disabled])

	# Recipe-open state lives on the GSTDocument. New activates an independent
	# document, so re-activating the fire document re-enables Randomize and
	# navigating back to the New document disables it. The fire document's
	# history is untouched by navigation, so one undo reaches post_open_body.
	panel.activate_document(doc_before_new)
	for i: int in range(2):
		await plugin.get_tree().process_frame
	_check("7", not panel.get_randomize_button().disabled and panel.get_stack() == doc_before_new.stack, "activating the fire document re-enables Randomize independent of navigation: enabled=%s" % [not panel.get_randomize_button().disabled])

	panel.activate_document(new_doc)
	for i: int in range(2):
		await plugin.get_tree().process_frame
	_check("8", panel.get_randomize_button().disabled and panel.get_stack().layers.is_empty(), "re-activating the New document disables Randomize again: disabled=%s" % [panel.get_randomize_button().disabled])

	panel.activate_document(doc_before_new)
	for i: int in range(2):
		await plugin.get_tree().process_frame
	history = panel.get_watched_history()
	history.undo()
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var body_after_final_undo: String = _codegen_body(panel.get_shader_material().shader.code)
	_check("9", not panel.get_randomize_button().disabled and body_after_final_undo == post_open_body, "the fire document's own history still undoes back through its randomize action, independent of navigation in between: Randomize still enabled=%s body matches post-open body=%s" % [not panel.get_randomize_button().disabled, body_after_final_undo == post_open_body])

	_finish(plugin)


## The value displayed by property_widget's editing control (SpinBox or
## EditorSpinSlider, both Range subclasses on 4.6.2, for a float param under
## PROPERTY_HINT_RANGE), read off that control rather than the GSTLayer
## model. 0.0 when property_widget is null or holds no Range descendant.
func _range_control_value(property_widget: EditorProperty) -> float:
	if property_widget == null:
		return 0.0
	var control: Range = _find_range_control(property_widget)
	if control == null:
		return 0.0
	return control.value


func _find_range_control(node: Node) -> Range:
	if node is Range:
		return node as Range
	for child: Node in node.get_children():
		var found: Range = _find_range_control(child)
		if found != null:
			return found
	return null


## Every param on every layer of `stack`, resolved against `library`:
## {layer_id: {param_name: current_value}}. A layer whose entry does not
## resolve or declares no params contributes nothing (same shape as
## GSTRandomize.randomize's change set).
func _snapshot_params(stack: GSTStack, library: GSTLibrary) -> Dictionary:
	var snapshot: Dictionary = {}
	for layer: GSTLayer in stack.layers:
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		if entry == null or entry.params.is_empty():
			continue
		var layer_params: Dictionary = {}
		for param: Dictionary in entry.params:
			var param_name: String = String(param["name"])
			layer_params[param_name] = layer.get(StringName(param_name))
		snapshot[layer.id] = layer_params
	return snapshot


func _any_param_changed(before: Dictionary, after: Dictionary) -> bool:
	for layer_id: Variant in before.keys():
		var before_params: Dictionary = before[layer_id]
		var after_params: Dictionary = after.get(layer_id, {})
		for param_name: Variant in before_params.keys():
			if after_params.get(param_name) != before_params[param_name]:
				return true
	return false


func _every_param_in_range(stack: GSTStack, library: GSTLibrary) -> bool:
	for layer: GSTLayer in stack.layers:
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		if entry == null:
			continue
		for param: Dictionary in entry.params:
			var value: Variant = layer.params.get(String(param["name"]), param["default"])
			if not _value_in_range(param, value):
				return false
	return true


func _value_in_range(param: Dictionary, value: Variant) -> bool:
	var param_type: String = String(param["type"])
	match param_type:
		"int":
			return typeof(value) == TYPE_INT and int(value) >= int(param["min"]) and int(value) <= int(param["max"])
		"float":
			return typeof(value) == TYPE_FLOAT and float(value) >= float(param["min"]) and float(value) <= float(param["max"])
		"color":
			if typeof(value) != TYPE_COLOR:
				return false
			var c: Color = value
			return c.r >= 0.0 and c.r <= 1.0 and c.g >= 0.0 and c.g <= 1.0 and c.b >= 0.0 and c.b <= 1.0 and is_equal_approx(c.a, 1.0)
		"vec2":
			if typeof(value) != TYPE_VECTOR2:
				return false
			var v2: Vector2 = value
			var min2: float = float(param.get("min", 0.0))
			var max2: float = float(param.get("max", 1.0))
			return v2.x >= min2 and v2.x <= max2 and v2.y >= min2 and v2.y <= max2
		"vec3":
			if typeof(value) != TYPE_VECTOR3:
				return false
			var v3: Vector3 = value
			var min3: float = float(param.get("min", 0.0))
			var max3: float = float(param.get("max", 1.0))
			return v3.x >= min3 and v3.x <= max3 and v3.y >= min3 and v3.y <= max3 and v3.z >= min3 and v3.z <= max3
		_:
			return false


## source/texture; fbm; a primary smoothstep threshold on the fbm;
## alpha(texture) times that threshold as output alpha; an edge band (a
## lower-edge smoothstep times the inverted primary threshold) masking a
## color/mix between texture and an orange fill as output color. Mirrors
## addons/goshade_turbo/recipes/dissolve.tres.
func _run_phase7_dissolve(plugin: EditorPlugin, panel: GSTMainPanel, library: GSTLibrary) -> void:
	panel._on_new_pressed()
	await plugin.get_tree().process_frame
	await _cancel_picker(plugin, panel)
	var history: UndoRedo = panel.get_watched_history()
	var undo: GSTUndo = panel.get_undo()

	var texture: GSTLayer = undo.add_layer("source/texture", GSTLayer.Kind.COLOR, false)

	var fbm: GSTLayer = undo.add_layer("generative/fbm", GSTLayer.Kind.FIELD, true)
	_set_coord_property(panel, fbm.coord, &"scale", Vector2(4.0, 4.0))

	var threshold: GSTLayer = undo.add_layer("fieldops/smoothstep", GSTLayer.Kind.FIELD, false)
	undo.assign_slot(threshold.id, "x", fbm.id)
	_set_layer_param(panel, threshold, &"edge0", 0.0)
	_set_layer_param(panel, threshold, &"edge1", 0.05)

	var tex_alpha: GSTLayer = undo.add_layer("fieldops/alpha", GSTLayer.Kind.FIELD, false)
	undo.assign_slot(tex_alpha.id, "color", texture.id)

	var alpha_out: GSTLayer = undo.add_layer("fieldops/multiply", GSTLayer.Kind.FIELD, false)
	undo.assign_slot(alpha_out.id, "a", tex_alpha.id)
	undo.assign_slot(alpha_out.id, "b", threshold.id)

	var edge_low: GSTLayer = undo.add_layer("fieldops/smoothstep", GSTLayer.Kind.FIELD, false)
	undo.assign_slot(edge_low.id, "x", fbm.id)
	_set_layer_param(panel, edge_low, &"edge0", -0.1)
	_set_layer_param(panel, edge_low, &"edge1", -0.05)

	var threshold_inv: GSTLayer = undo.add_layer("fieldops/invert", GSTLayer.Kind.FIELD, false)
	undo.assign_slot(threshold_inv.id, "x", threshold.id)

	var edge_band: GSTLayer = undo.add_layer("fieldops/multiply", GSTLayer.Kind.FIELD, false)
	undo.assign_slot(edge_band.id, "a", edge_low.id)
	undo.assign_slot(edge_band.id, "b", threshold_inv.id)

	var fill: GSTLayer = undo.add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	_set_layer_param(panel, fill, &"color", Color(1.0, 0.5, 0.0, 1.0))

	var mix: GSTLayer = undo.add_layer("color/mix", GSTLayer.Kind.COLOR, false)
	undo.assign_slot(mix.id, "a", texture.id)
	undo.assign_slot(mix.id, "b", fill.id)
	undo.assign_slot(mix.id, "mask", edge_band.id)

	undo.set_output_color(mix.id)
	undo.set_output_alpha(alpha_out.id)

	for i: int in range(3):
		await plugin.get_tree().process_frame

	await _run_phase7_recipe_checks(plugin, panel, history, library, "dissolve")


## A rotated, scrolling stripes field drives the cosine palette (its default
## a/b/c/d matches Capsule Castle's SpriteHolographic.gdshader palette()
## constants), screen-blended over the texture source. Mirrors
## addons/goshade_turbo/recipes/sprite_holographic.tres.
func _run_phase7_sprite_holographic(plugin: EditorPlugin, panel: GSTMainPanel, library: GSTLibrary) -> void:
	panel._on_new_pressed()
	await plugin.get_tree().process_frame
	await _cancel_picker(plugin, panel)
	var history: UndoRedo = panel.get_watched_history()
	var undo: GSTUndo = panel.get_undo()

	var texture: GSTLayer = undo.add_layer("source/texture", GSTLayer.Kind.COLOR, false)

	var band: GSTLayer = undo.add_layer("generative/stripes", GSTLayer.Kind.FIELD, true)
	_set_coord_property(panel, band.coord, &"scale", Vector2(2.83, 2.83))
	_set_coord_property(panel, band.coord, &"rotation", -0.7853982)
	_set_coord_property(panel, band.coord, &"scroll", Vector2(0.4, 0.0))

	var palette: GSTLayer = undo.add_layer("color/palette", GSTLayer.Kind.COLOR, false)
	undo.assign_slot(palette.id, "t", band.id)

	var screen: GSTLayer = undo.add_layer("color/screen", GSTLayer.Kind.COLOR, false)
	undo.assign_slot(screen.id, "a", texture.id)
	undo.assign_slot(screen.id, "b", palette.id)
	_set_layer_param(panel, screen, &"t", 0.6)

	undo.set_output_color(screen.id)
	undo.set_output_alpha(&"texture")

	for i: int in range(3):
		await plugin.get_tree().process_frame

	await _run_phase7_recipe_checks(plugin, panel, history, library, "sprite_holographic")


## filter/outline on the texture source, a fill color for the outline,
## color/mix masked by the outline layer (auto luma-converted), output alpha
## the mix's color_alpha rather than "texture" so the outline ring outside
## the sprite silhouette stays visible. Mirrors
## addons/goshade_turbo/recipes/outline.tres.
func _run_phase7_outline(plugin: EditorPlugin, panel: GSTMainPanel, library: GSTLibrary) -> void:
	panel._on_new_pressed()
	await plugin.get_tree().process_frame
	await _cancel_picker(plugin, panel)
	var history: UndoRedo = panel.get_watched_history()
	var undo: GSTUndo = panel.get_undo()

	var texture: GSTLayer = undo.add_layer("source/texture", GSTLayer.Kind.COLOR, false)

	var outline: GSTLayer = undo.add_layer("filter/outline", GSTLayer.Kind.COLOR, false)
	undo.assign_slot(outline.id, "source", texture.id)

	var fill: GSTLayer = undo.add_layer("color/fill", GSTLayer.Kind.COLOR, false)
	_set_layer_param(panel, fill, &"color", Color(0.0, 0.0, 0.0, 1.0))

	var mix: GSTLayer = undo.add_layer("color/mix", GSTLayer.Kind.COLOR, false)
	undo.assign_slot(mix.id, "a", texture.id)
	undo.assign_slot(mix.id, "b", fill.id)
	undo.assign_slot(mix.id, "mask", outline.id)

	undo.set_output_color(mix.id)
	undo.set_output_alpha(&"color_alpha")

	for i: int in range(3):
		await plugin.get_tree().process_frame

	await _run_phase7_recipe_checks(plugin, panel, history, library, "outline")


## Shared tail for the three recipe builders: capture, undo to empty, redo
## back to the capture (text byte-equal, preview non-uniform), then
## open_recipe(recipe_name) and check the panel lands on the same codegen
## text a fresh GSTStackIO.load of
## addons/goshade_turbo/recipes/<recipe_name>.tres produces.
func _run_phase7_recipe_checks(plugin: EditorPlugin, panel: GSTMainPanel, history: UndoRedo, library: GSTLibrary, recipe_name: String) -> void:
	var capture: String = panel.get_shader_material().shader.code
	_check("%s_build" % recipe_name, not capture.is_empty(), "%s: built stack produces non-empty shader text (len=%d)" % [recipe_name, capture.length()])

	while history.has_undo():
		history.undo()
	await plugin.get_tree().process_frame
	var stack_after_undo: GSTStack = panel.get_stack()
	var empty_after_undo: bool = stack_after_undo != null and stack_after_undo.layers.is_empty() and not history.has_undo()
	_check("%s_undo_empty" % recipe_name, empty_after_undo, "%s: stack empty and has_undo()=false after undoing to the end: layers=%d has_undo=%s" % [recipe_name, stack_after_undo.layers.size() if stack_after_undo != null else -1, history.has_undo()])

	while history.has_redo():
		history.redo()
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var code_after_redo: String = panel.get_shader_material().shader.code
	var redo_matches: bool = not history.has_redo() and code_after_redo == capture
	_check("%s_redo_match" % recipe_name, redo_matches, "%s: redo-to-end shader text byte-equal to the build capture=%s has_redo=%s" % [recipe_name, code_after_redo == capture, history.has_redo()])

	var img_after_redo: Image = panel.get_preview().get_viewport_image()
	var redo_nonuniform: bool = img_after_redo != null and not _image_is_uniform(img_after_redo)
	_check("%s_redo_render" % recipe_name, redo_nonuniform, "%s: preview renders non-uniform pixels after redo (img_null=%s)" % [recipe_name, img_after_redo == null])

	panel.open_recipe(recipe_name)
	for i: int in range(3):
		await plugin.get_tree().process_frame

	var fresh_load: Dictionary = GSTStackIO.load("res://addons/goshade_turbo/recipes/%s.tres" % recipe_name, library)
	var fresh_ok: bool = fresh_load["ok"]
	var fresh_code: String = ""
	if fresh_ok:
		var fresh_result: GSTCodegenResult = GSTCodegen.generate_result(fresh_load["stack"], library)
		fresh_ok = fresh_result.ok()
		fresh_code = fresh_result.code
	var panel_code_after_open: String = panel.get_shader_material().shader.code
	var open_matches: bool = fresh_ok and panel_code_after_open == fresh_code
	_check("%s_open_match" % recipe_name, open_matches, "%s: open_recipe panel shader text equals a fresh codegen of the recipe file=%s (fresh_ok=%s)" % [recipe_name, open_matches, fresh_ok])

	var img_after_open: Image = panel.get_preview().get_viewport_image()
	var open_nonuniform: bool = img_after_open != null and not _image_is_uniform(img_after_open)
	_check("%s_open_render" % recipe_name, open_nonuniform, "%s: preview renders non-uniform pixels after open_recipe (img_null=%s)" % [recipe_name, img_after_open == null])


## A GSTUndo action committed while the open stack carries a res:// path
## (open_recipe and reopen_shader_path load through GSTStackIO, which sets
## resource_path on the returned Resource) must land in that document's own
## panel.get_watched_history(). The layer-gone-and-body-matches check after
## undo is the differentiator: add_layer's commit_action(false) applies the
## mutation and calls _notify() synchronously, so has_undo() and resync alone
## would pass even if the action had landed in another history.
func _run_phase7_history_anchor(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	await _run_phase7_history_anchor_open_recipe(plugin, panel)
	await _run_phase7_history_anchor_reopen_shader(plugin, panel)


## Everything below the "// stack: <json>" header line, excluding the header.
## The header's next_id never reverts on undo of an add, so a full-text
## comparison across add-then-undo would differ by next_id alone (same
## header-scoped comparison as tests/test_codegen_generator.gd).
func _codegen_body(code: String) -> String:
	var found: Dictionary = GSTOverwriteCheck.find_header_line(code)
	return found["body"] if found["found"] else code


func _run_phase7_history_anchor_open_recipe(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	# No New in between: open_recipe alone puts a path-bearing GSTStack
	# (loaded from res://addons/goshade_turbo/recipes/dissolve.tres) on the
	# panel.
	panel.open_recipe("dissolve")
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var post_open_code: String = panel.get_shader_material().shader.code
	var history: UndoRedo = panel.get_watched_history()

	var layer: GSTLayer = panel.get_undo().add_layer("generative/hash", GSTLayer.Kind.FIELD, true)
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var code_after_add: String = panel.get_shader_material().shader.code
	var has_undo_now: bool = history.has_undo()
	var resynced: bool = code_after_add != post_open_code
	_check("history_open_add", has_undo_now and resynced, "open_recipe(dissolve) + add generative/hash: has_undo=%s resynced=%s" % [has_undo_now, resynced])

	history.undo()
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var layer_gone: bool = GSTStackOps.find_index(panel.get_stack(), layer.id) == -1
	var code_after_undo: String = panel.get_shader_material().shader.code
	var body_matches: bool = _codegen_body(code_after_undo) == _codegen_body(post_open_code)
	_check("history_open_undo", layer_gone and body_matches, "undo the add: layer_gone=%s code_matches_post_open=%s" % [layer_gone, body_matches])

	history.redo()
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var layer_back: bool = GSTStackOps.find_index(panel.get_stack(), layer.id) != -1
	_check("history_open_redo", layer_back, "redo the add: layer_back=%s" % [layer_back])


func _run_phase7_history_anchor_reopen_shader(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var export_path: String = "res://sandbox/exports/gst_editor_smoke_phase7_history.gdshader"

	panel.open_recipe("dissolve")
	for i: int in range(3):
		await plugin.get_tree().process_frame
	panel.export_to_path(export_path, false)

	panel.reopen_shader_path(export_path)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var post_reopen_code: String = panel.get_shader_material().shader.code
	var history: UndoRedo = panel.get_watched_history()

	var layer: GSTLayer = panel.get_undo().add_layer("generative/hash", GSTLayer.Kind.FIELD, true)
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var code_after_add: String = panel.get_shader_material().shader.code
	var has_undo_now: bool = history.has_undo()
	var resynced: bool = code_after_add != post_reopen_code
	_check("history_reopen_add", has_undo_now and resynced, "reopen_shader_path(dissolve export) + add generative/hash: has_undo=%s resynced=%s" % [has_undo_now, resynced])

	history.undo()
	for i: int in range(2):
		await plugin.get_tree().process_frame
	var layer_gone: bool = GSTStackOps.find_index(panel.get_stack(), layer.id) == -1
	var code_after_undo: String = panel.get_shader_material().shader.code
	var body_matches: bool = _codegen_body(code_after_undo) == _codegen_body(post_reopen_code)
	_check("history_reopen_undo", layer_gone and body_matches, "undo the add: layer_gone=%s code_matches_post_reopen=%s" % [layer_gone, body_matches])

	_cleanup_phase6_files([export_path])


func _cleanup_phase6_files(paths: Array[String]) -> void:
	for path: String in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		var uid_path: String = path + ".uid"
		if FileAccess.file_exists(uid_path):
			DirAccess.remove_absolute(uid_path)


func _read_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _write_file(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Appends a trailing space to the first non-empty line after the header
## line: a one-byte body mutation that never touches the header JSON (mirrors
## tests/test_overwrite_check.gd's _mutate_body_char).
func _mutate_body_line(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	for i: int in range(lines.size()):
		if lines[i].begins_with(GSTHeader.HEADER_PREFIX):
			for j: int in range(i + 1, lines.size()):
				if not lines[j].is_empty():
					lines[j] = lines[j] + " "
					return "\n".join(lines)
	return text


## True when a sparse grid sample of img shows no variation. Cheap enough to
## run every frame this script waits on.
func _image_is_uniform(img: Image) -> bool:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w == 0 or h == 0:
		return true
	var first: Color = img.get_pixel(0, 0)
	# Step off the smaller dimension: the preview viewport tracks the panel's
	# column rect, which is often non-square or narrow, and a width-derived
	# step would skip every pattern boundary on a short-and-wide rect.
	var step: int = maxi(1, mini(w, h) / 16)
	for y: int in range(0, h, step):
		for x: int in range(0, w, step):
			if not img.get_pixel(x, y).is_equal_approx(first):
				return false
	return true


func _images_equal(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	var w: int = a.get_width()
	var h: int = a.get_height()
	var step: int = maxi(1, mini(w, h) / 24)
	for y: int in range(0, h, step):
		for x: int in range(0, w, step):
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				return false
	return true


func _image_changed_fraction(a: Image, b: Image, tolerance: float) -> float:
	if a == null or b == null or a.get_size() != b.get_size() or a.get_width() == 0 or a.get_height() == 0:
		return 0.0
	var changed: int = 0
	var total: int = a.get_width() * a.get_height()
	for y: int in range(a.get_height()):
		for x: int in range(a.get_width()):
			if not _colors_close(a.get_pixel(x, y), b.get_pixel(x, y), tolerance):
				changed += 1
	return float(changed) / float(total)


func _colors_close(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) <= tolerance and absf(a.g - b.g) <= tolerance and absf(a.b - b.b) <= tolerance and absf(a.a - b.a) <= tolerance


## Reads img at each fraction in fracs (0..1 of width/height). Color.BLACK
## per point when img is null, so the caller gets a same-length array.
func _sample_points(img: Image, fracs: Array[Vector2]) -> Array[Color]:
	var out: Array[Color] = []
	if img == null:
		for i: int in range(fracs.size()):
			out.append(Color.BLACK)
		return out
	var w: int = img.get_width()
	var h: int = img.get_height()
	for frac: Vector2 in fracs:
		out.append(img.get_pixel(int(frac.x * w), int(frac.y * h)))
	return out


func _colors_all_equal(colors: Array[Color]) -> bool:
	if colors.is_empty():
		return true
	var first: Color = colors[0]
	for c: Color in colors:
		if not c.is_equal_approx(first):
			return false
	return true


func _colors_all_close(a: Array[Color], b: Array[Color], tolerance: float) -> bool:
	if a.size() != b.size():
		return false
	for i: int in range(a.size()):
		if not _colors_close(a[i], b[i], tolerance):
			return false
	return true


## Sets a GSTCoordBlock property through GSTUndo.commit_property_change, the
## call gst_inspector_column.gd's native rows make once a gesture finishes,
## so the edit registers a property-undo action.
func _set_coord_property(panel: GSTMainPanel, coord: GSTCoordBlock, property: StringName, value: Variant) -> void:
	var old_value: Variant = coord.get(property)
	coord.set(property, value)
	panel.get_undo().commit_property_change(coord, property, old_value, value)


## Sets layer.<property_name> (a manifest param, dynamic via
## GSTLayer._get/_set) through GSTUndo.commit_property_change rather than a
## raw write into layer.params, so recipe builds register undoable history
## for every param.
func _set_layer_param(panel: GSTMainPanel, layer: GSTLayer, property_name: StringName, value: Variant) -> void:
	var old_value: Variant = layer.get(property_name)
	layer.set(property_name, value)
	panel.get_undo().commit_property_change(layer, property_name, old_value, value)


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
