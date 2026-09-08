@tool
extends RefCounted

## Runs inside a real editor session (godot --editor --path .) when
## GST_EDITOR_SMOKE is set, driven by plugin.gd's _enter_tree. Performs the
## phase 4 verification steps programmatically, prints one
## "SMOKE <item> PASS|FAIL <detail>" line per item, then quits the editor.
## Never fabricates a pass: every assertion below is a real check against
## the running panel. Design: docs/PLAN.md Phase 4 Verification (amended).

var _pass_count: int = 0
var _fail_count: int = 0


func run(plugin: EditorPlugin) -> void:
	# Let the main screen tab registration and panel _ready() settle.
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

	var stack_list: GSTStackList = panel.get_stack_list()
	var undo: GSTUndo = panel.get_undo()
	var library: GSTLibrary = panel.get_library()
	var stack: GSTStack = panel.get_stack()
	var history: UndoRedo = _get_history(stack)

	var fbm: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	var invert: GSTLayer = stack_list.add_layer_by_entry_id("fieldops/invert")
	var hash_layer: GSTLayer = stack_list.add_layer_by_entry_id("generative/hash")
	_check("2", fbm != null and invert != null and hash_layer != null, "fbm=%s invert=%s hash=%s" % [fbm, invert, hash_layer])

	await plugin.get_tree().process_frame
	_check_output_defaults("3", panel, "after the adds, before any output-block or color-layer state exists")

	await _run_palette_inspector_check(plugin, panel, stack_list, history)
	await _run_color_alpha_default_excursion(plugin, panel, stack_list, library, history)
	await _run_add_for_slot_excursion(plugin, panel, stack_list, library, history, invert)

	# fbm(idx0) and invert(idx1) are still adjacent (hash has not moved yet):
	# a single Up step on fbm swaps it with invert directly, so decision 22's
	# forward-reference check (invert references fbm) refuses it. This must
	# run before the hash-down move below, which would otherwise separate
	# fbm and invert and make a single Up step land short of invert.
	var wire_result: Dictionary = undo.assign_slot(invert.id, "x", fbm.id)
	_check("6", wire_result["ok"], "wire invert.x -> fbm: %s" % [wire_result["reason"]])

	var order_before_attempt: Array[StringName] = _layer_ids(stack)
	stack_list.select_layer(fbm.id)
	stack_list._on_up_pressed()
	await plugin.get_tree().process_frame
	var order_after_attempt: Array[StringName] = _layer_ids(stack)
	var refusal_reason: String = panel.get_message_label().text
	var refused_as_expected: bool = refusal_reason.contains("references layer %s, which would be at or above it after this move" % String(fbm.id))
	_check("7", refused_as_expected and order_after_attempt == order_before_attempt, "up-press fbm above invert message='%s' order_unchanged=%s" % [refusal_reason, order_after_attempt == order_before_attempt])

	# hash references nothing and nothing references hash, so moving it is
	# always safe regardless of position. Same GSTUndo call the stack list's
	# Down button uses: idx + (-1).
	var hash_original_index: int = GSTStackOps.find_index(stack, hash_layer.id)
	var down_result: Dictionary = undo.reorder_layer(hash_layer.id, hash_original_index - 1)
	var hash_index_after_move: int = GSTStackOps.find_index(stack, hash_layer.id)
	_check("8", down_result["ok"] and hash_index_after_move == hash_original_index - 1, "hash move down: ok=%s index %d -> %d" % [down_result["ok"], hash_original_index, hash_index_after_move])

	# invert is now the top-most layer (highest array index); asking to move
	# it one past the top clamps to its own index, a no-op that must not
	# register an undo action (fix 5).
	var top_layer_id: StringName = stack.layers[stack.layers.size() - 1].id
	var count_before_noop: int = history.get_history_count()
	var noop_result: Dictionary = undo.reorder_layer(top_layer_id, stack.layers.size())
	var count_after_noop: int = history.get_history_count()
	_check("9", noop_result["ok"] and count_after_noop == count_before_noop, "boundary move at top: ok=%s history_count %d -> %d (expect unchanged)" % [noop_result["ok"], count_before_noop, count_after_noop])

	var output_color_result: Dictionary = undo.set_output_color(invert.id)
	_check("10", output_color_result["ok"] and stack.output_color == invert.id, "set output color to invert: ok=%s applied='%s' (expect '%s')" % [output_color_result["ok"], String(stack.output_color), String(invert.id)])

	var output_alpha_result: Dictionary = undo.set_output_alpha(&"none")
	var alpha_applied: bool = stack.output_alpha == &"none" and panel.get_output_block().get_selected_alpha_text() == "none"
	_check("11", output_alpha_result["ok"] and alpha_applied, "set output alpha to none: ok=%s applied='%s' selected_text='%s' (expect 'none')" % [output_alpha_result["ok"], String(stack.output_alpha), panel.get_output_block().get_selected_alpha_text()])

	# Selecting the output block's default row (fix pass 2, item 5) must be
	# undoable, driven through the same private handler the OptionButton's
	# item_selected signal calls (same pattern as stack_list._on_up_pressed()
	# above). Undone immediately after the check so _run_undo_sequence below
	# still finds exactly the 7 actions its own comment documents.
	var count_before_default_pick: int = history.get_history_count()
	panel.get_output_block()._on_alpha_selected(0)
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


func _get_history(stack: GSTStack) -> UndoRedo:
	var undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	var history_id: int = undo_redo.get_object_history_id(stack)
	return undo_redo.get_history_undo_redo(history_id)


func _layer_ids(stack: GSTStack) -> Array[StringName]:
	var ids: Array[StringName] = []
	for layer: GSTLayer in stack.layers:
		ids.append(layer.id)
	return ids


## Output block defaults (decision 12, docs/PLAN.md Phase 4 amendment): with
## no color layer in the stack, the color option shows "(none)"; with no
## source/texture layer, the alpha option shows "(default) none".
func _check_output_defaults(item: String, panel: GSTMainPanel, context: String) -> void:
	var color_text: String = panel.get_output_block().get_selected_color_text()
	var alpha_text: String = panel.get_output_block().get_selected_alpha_text()
	var ok: bool = color_text == "(none)" and alpha_text == "(default) none"
	_check(item, ok, "%s: color option='%s' alpha option='%s' (expect '(none)' and '(default) none')" % [context, color_text, alpha_text])


## color/palette (fix pass 2, item 1): a real shipped manifest whose a, b, c,
## d params are declared "vec3", not scalar approximations. GSTLayer must map
## "vec3" to TYPE_VECTOR3 in its dynamic property list so the inspector
## column shows four Vector3 fields, not four bare floats, against the real
## on-disk manifest rather than a synthetic fixture. Self-canceling like the
## excursion below: undone here, before any other real action commits.
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
	var expected_names: Array[String] = ["a", "b", "c", "d"]
	_check("15a", vec3_names == expected_names, "color/palette TYPE_VECTOR3 property names: %s (expect %s)" % [vec3_names, expected_names])

	var a_value: Variant = palette_layer.get("a")
	_check("15b", a_value is Vector3, "layer.get('a') type: %s (expect Vector3)" % [typeof(a_value)])

	inspector.edit(&"")
	history.undo()
	await plugin.get_tree().process_frame
	_check("15c", GSTStackOps.find_index(panel.get_stack(), palette_layer.id) == -1, "undo the palette add: layer gone=%s" % [GSTStackOps.find_index(panel.get_stack(), palette_layer.id) == -1])


## Adds color/fill then source/texture through the same panel path the Add
## button uses, checks the output block's defaults pick them up, then undoes
## both through the real EditorUndoRedoManager history. Both adds are
## reverted here, so this excursion is self-canceling: the next real action
## committed after it (the invert.x wire below) truncates them permanently
## from the redo tail, leaving the persistent action count unaffected (fix 6).
func _run_color_alpha_default_excursion(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, library: GSTLibrary, history: UndoRedo) -> void:
	var fill: GSTLayer = stack_list.add_layer_by_entry_id("color/fill")
	await plugin.get_tree().process_frame
	var fill_entry: GSTManifestEntry = library.get_entry("color/fill")
	var expect_color: String = "(default) l%s %s" % [String(fill.id), fill_entry.function]
	_check("4a", panel.get_output_block().get_selected_color_text() == expect_color, "color default after adding fill: '%s' (expect '%s')" % [panel.get_output_block().get_selected_color_text(), expect_color])

	stack_list.add_layer_by_entry_id("source/texture")
	await plugin.get_tree().process_frame
	_check("4b", panel.get_output_block().get_selected_alpha_text() == "(default) texture", "alpha default after adding texture: '%s' (expect '(default) texture')" % [panel.get_output_block().get_selected_alpha_text()])

	history.undo()
	await plugin.get_tree().process_frame
	_check("4c", panel.get_output_block().get_selected_alpha_text() == "(default) none", "alpha default after undoing texture add: '%s' (expect '(default) none')" % [panel.get_output_block().get_selected_alpha_text()])

	history.undo()
	await plugin.get_tree().process_frame
	_check("4d", panel.get_output_block().get_selected_color_text() == "(none)", "color default after undoing fill add: '%s' (expect '(none)')" % [panel.get_output_block().get_selected_color_text()])


## Drives the inspector column's "Add for slot" button on invert's field
## slot "x" rather than calling GSTPicker.open_for_slot() directly (fix 3):
## presses the button, checks the resulting picker is field-kind-only and
## search-filters within that set, picks an entry, checks the compound add +
## wire landed directly below invert, then undoes it. This excursion is also
## self-canceling for the same reason as the one above.
func _run_add_for_slot_excursion(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, library: GSTLibrary, history: UndoRedo, invert: GSTLayer) -> void:
	var stack: GSTStack = panel.get_stack()
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	stack_list.select_layer(invert.id)
	await plugin.get_tree().process_frame

	inspector._on_add_for_slot_pressed("x", GSTLayer.Kind.FIELD)
	var picker: GSTPicker = inspector.get_slot_picker()
	var all_ids: Array[String] = picker.get_all_entry_ids()
	var all_field: bool = not all_ids.is_empty()
	for entry_id: String in all_ids:
		if library.get_entry(entry_id).kind_out != GSTLayer.Kind.FIELD:
			all_field = false
	_check("5a", all_field, "add-for-slot picker listed %d entries, all field kind=%s" % [all_ids.size(), all_field])

	picker.set_search_text("checker")
	var visible_ids: Array[String] = picker.get_visible_entry_ids()
	var only_checker: bool = visible_ids.size() == 1 and visible_ids[0] == "generative/checker"
	_check("5b", only_checker, "search 'checker' visible=%s (expect ['generative/checker'])" % [visible_ids])

	var count_before_pick: int = stack.layers.size()
	picker.entry_picked.emit("generative/checker")
	await plugin.get_tree().process_frame
	var invert_idx_now: int = GSTStackOps.find_index(stack, invert.id)
	var new_layer: GSTLayer = stack.layers[invert_idx_now - 1] if invert_idx_now > 0 else null
	var placed_below: bool = new_layer != null and new_layer.entry == "generative/checker"
	var slot_wired: bool = new_layer != null and invert.slots.get("x", &"") == new_layer.id
	var count_after_pick: int = stack.layers.size()
	_check("5c", placed_below and slot_wired and count_after_pick == count_before_pick + 1, "picked generative/checker: placed_below=%s slot_wired=%s count %d -> %d" % [placed_below, slot_wired, count_before_pick, count_after_pick])

	history.undo()
	await plugin.get_tree().process_frame
	var slot_cleared: bool = String(invert.slots.get("x", &"")).is_empty()
	var count_after_undo: int = stack.layers.size()
	_check("5d", slot_cleared and count_after_undo == count_before_pick, "undo add-for-slot: invert.slots['x']='%s' (expect empty), count=%d (expect %d)" % [String(invert.slots.get("x", &"")), count_after_undo, count_before_pick])

	picker.hide()


## GSTUndo registers each action on EditorUndoRedoManager's history for
## _stack (decision 20: "shared with every other editor action" family;
## custom_context = _stack is required, see gst_undo.gd's _create_action
## comment, so get_object_history_id(stack) stays a stable bucket instead of
## whatever object the editor last inspected).
##
## The refused up-press registered no action, the boundary no-op reorder
## registered no action, and the two excursions above were undone before the
## next real action truncated them from the redo tail, so exactly 7 actions
## exist to undo: add fbm, add invert, add hash, wire the slot, reorder
## hash, set output color, set output alpha.
func _run_undo_sequence(plugin: EditorPlugin, stack: GSTStack, stack_list: GSTStackList, panel: GSTMainPanel, fbm: GSTLayer, invert: GSTLayer, hash_layer: GSTLayer, hash_original_index: int) -> void:
	var history: UndoRedo = _get_history(stack)

	history.undo()
	await plugin.get_tree().process_frame
	_check("12a", stack.output_alpha == &"" and stack_list.get_item_count() == 3, "output_alpha after undo 1: '%s' (expect empty), row_count=%s (expect 3)" % [String(stack.output_alpha), stack_list.get_item_count()])

	history.undo()
	await plugin.get_tree().process_frame
	_check("12b", stack.output_color == &"" and stack_list.get_item_count() == 3, "output_color after undo 2: '%s' (expect empty), row_count=%s (expect 3)" % [String(stack.output_color), stack_list.get_item_count()])

	history.undo()
	await plugin.get_tree().process_frame
	var hash_index_now: int = GSTStackOps.find_index(stack, hash_layer.id)
	_check("12c", hash_index_now == hash_original_index and stack_list.get_item_count() == 3, "hash index after undo 3: %d (expect original %d), row_count=%s (expect 3)" % [hash_index_now, hash_original_index, stack_list.get_item_count()])

	history.undo()
	await plugin.get_tree().process_frame
	var invert_after: GSTLayer = GSTStackOps.find_layer(stack, invert.id)
	var slot_cleared: bool = invert_after != null and String(invert_after.slots.get("x", &"")).is_empty()
	_check("12d", slot_cleared and stack_list.get_item_count() == 3, "invert.slots['x'] after undo 4: '%s' (expect empty), row_count=%s (expect 3)" % [String(invert_after.slots.get("x", &"")) if invert_after != null else "invert missing", stack_list.get_item_count()])

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


## Output-referenced removal (fix pass 2, item 2): removing a layer that
## stack.output_color or stack.output_alpha points at must clear that field
## to &"" rather than leave a dangling reference codegen cannot resolve.
## Runs on the panel's stack right after _run_undo_sequence has brought it
## back to empty, so it starts clean and unwinds itself back to empty at the
## end, self-canceling like the two excursions earlier in run().
func _run_output_referenced_removal_excursion(plugin: EditorPlugin, panel: GSTMainPanel, undo: GSTUndo, library: GSTLibrary) -> void:
	var stack: GSTStack = panel.get_stack()
	var history: UndoRedo = _get_history(stack)

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

	# Unwind: remove(color) redo, remove(alpha) redo, set_output_alpha,
	# set_output_color, add alpha_layer, add color_layer -- 6 actions total.
	for i: int in range(6):
		history.undo()
		await plugin.get_tree().process_frame
	_check("14h", not history.has_undo() and stack.layers.is_empty() and stack.output_color == &"" and stack.output_alpha == &"", "excursion fully unwound: has_undo=%s layers=%d output_color='%s' output_alpha='%s'" % [history.has_undo(), stack.layers.size(), String(stack.output_color), String(stack.output_alpha)])


## Regression for phase 4 fix pass 3, item 1: an inspector slider edit
## registers a property-undo action pointed at the layer's own GSTLayer
## instance (the same path EditorInspector uses, decision 20's "slider edits
## come from the inspector" carve-out). A structural remove committed after
## it, then undone, must reinsert that same instance rather than a duplicate,
## so the earlier slider undo still lands on it, and the EditorInspector must
## still edit that instance after the remove-undo. Self-canceling: unwinds
## back to an empty stack like the excursions above.
func _run_slider_remove_undo_identity_excursion(plugin: EditorPlugin, panel: GSTMainPanel, undo: GSTUndo) -> void:
	var stack: GSTStack = panel.get_stack()
	var history: UndoRedo = _get_history(stack)
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var editor_undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()

	var layer: GSTLayer = undo.add_layer("generative/fbm", GSTLayer.Kind.FIELD, true)
	await plugin.get_tree().process_frame
	inspector.edit(layer.id)

	var old_gain: float = float(layer.get("gain"))
	var new_gain: float = 0.75
	editor_undo_redo.create_action("slider", UndoRedo.MERGE_DISABLE, stack)
	editor_undo_redo.add_do_property(layer, "gain", new_gain)
	editor_undo_redo.add_undo_property(layer, "gain", old_gain)
	editor_undo_redo.commit_action()
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
