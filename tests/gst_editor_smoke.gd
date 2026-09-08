@tool
extends RefCounted

## Runs inside a real editor session (godot --editor --path .) when
## GST_EDITOR_SMOKE is set, driven by plugin.gd's _enter_tree. Performs the
## phase 4, 5, 6, or 7 verification steps programmatically depending on the
## env var's value ("5" selects phase 5, "6" selects phase 6, "7" selects
## phase 7, anything else keeps running phase 4), prints one "SMOKE <item>
## PASS|FAIL <detail>" line per item, then quits the editor. Never fabricates
## a pass: every assertion below is a real check against the running panel.
## Design: docs/PLAN.md Phase 4 Verification (amended), Phase 5 Verification,
## Phase 6 Verification, Phase 7 Verification.

var _pass_count: int = 0
var _fail_count: int = 0


## Dispatches on the GST_EDITOR_SMOKE value itself (plugin.gd only checks
## whether it is non-empty before instantiating this script), so a phase 5
## run (value "5") exercises the preview column below while any other value
## keeps running the phase 4 checks unchanged.
func run(plugin: EditorPlugin) -> void:
	var flag: String = OS.get_environment("GST_EDITOR_SMOKE")
	if flag == "5":
		await _run_phase5(plugin)
	elif flag == "6":
		await _run_phase6(plugin)
	elif flag == "7":
		await _run_phase7(plugin)
	else:
		await _run_phase4(plugin)


func _run_phase4(plugin: EditorPlugin) -> void:
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


## Phase 5: preview column (docs/PLAN.md Phase 5 Verification). Items 1-8
## match the plan's numbered list; setup checks that are not one of the 8
## use a "setup" prefix so they never collide with an item number.
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

	var stack_list: GSTStackList = panel.get_stack_list()
	var undo: GSTUndo = panel.get_undo()
	var library: GSTLibrary = panel.get_library()
	var stack: GSTStack = panel.get_stack()
	var preview: GSTPreview = panel.get_preview()
	var history: UndoRedo = _get_history(stack)

	var checker: GSTLayer = await _run_phase5_checker_render(plugin, panel, stack_list, undo, preview)
	await _run_phase5_preset_switch(plugin, panel)
	await _run_phase5_solo_toggle(plugin, panel, stack_list, checker)
	var tex_layer: GSTLayer = await _run_phase5_texture_source(plugin, panel, stack_list, undo, preview, checker)
	await _run_phase5_screen_source(plugin, panel, stack_list, undo, preview, tex_layer)
	await _run_phase5_coord_space(plugin, panel, stack_list, undo, history)
	await _run_phase5_codegen_error(plugin, panel, library)

	_finish(plugin)


## Item 1: a generative/checker layer (its own manifest carries no params;
## the hard 0.0/1.0 checkerboard is inherently maximal-contrast, no param
## needed to call it "high contrast") renders non-uniform pixels.
## Item 2 (fix pass 2, item 1): editing checker's only adjustable numeric
## field -- coord.scale, since checker.params is empty -- through a real
## EditorProperty widget's own emit_changed(), the way a real slider drag
## would, exercising gst_inspector_column.gd's GSTCoordBlock.changed relay
## end to end. Not driven through gst_inspector_column.gd's own
## EditorInspector directly: that column shows coord as a collapsed
## EditorPropertyResource row with no nested EditorProperty children built
## at all until a user expands it by hand (confirmed by walking that live
## tree: the row holds only an EditorResourcePicker's own buttons), so a
## throwaway EditorInspector pointed directly at the coord object is used
## instead -- coord is then the top-level edited object, the same
## EditorProperty/property_edited machinery gst_inspector_column.gd's own
## EditorInspector already uses for GSTLayer's own top-level properties,
## with no expand step needed. A prior version of this check forced
## EditorUndoRedoManager.create_action(..., custom_context = stack) directly,
## which artificially bound the action to the stack's own undo history
## bucket and never proved a real inspector-driven edit (whose
## create_action() call does not pass that context) reaches the material at
## all. Asserts the material's uniform and the rendered image both change
## within one frame of the real widget's own edit.
func _run_phase5_checker_render(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, undo: GSTUndo, preview: GSTPreview) -> GSTLayer:
	var checker: GSTLayer = stack_list.add_layer_by_entry_id("generative/checker")
	undo.set_output_color(checker.id)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var img1: Image = preview.get_viewport_image()
	var nonuniform: bool = img1 != null and not _image_is_uniform(img1)
	_check("1", nonuniform, "checker layer renders non-uniform pixels after 3 frames (img_null=%s)" % [img1 == null])

	var coord: GSTCoordBlock = checker.coord
	var old_scale: Vector2 = coord.scale
	var new_scale: Vector2 = old_scale * 6.0
	var found_prop: bool = await _drive_real_property_edit(plugin, coord, &"scale", new_scale)

	var uniform_name: String = GSTUniformNames.coord_scale(checker.id)
	var uniform_value: Variant = panel.get_shader_material().get_shader_parameter(uniform_name)
	var uniform_changed: bool = uniform_value is Vector2 and (uniform_value as Vector2).is_equal_approx(new_scale)
	var img2: Image = preview.get_viewport_image()
	var image_changed: bool = img2 != null and not _images_equal(img1, img2)
	_check("2", found_prop and uniform_changed and image_changed, "checker scale via real EditorProperty widget found=%s coord.scale=%s uniform=%s (expect %s) image_changed=%s" % [found_prop, coord.scale, uniform_value, new_scale, image_changed])
	return checker


## Edits target_object.property_name to value through a real EditorProperty
## widget's own emit_changed(), the same call an EditorProperty subclass
## (e.g. a Vector2 slider) makes internally on an actual drag, via a
## throwaway EditorInspector pointed directly at target_object so the widget
## exists as a top-level property with no fold/expand step needed. Frees the
## throwaway inspector afterward. Returns whether the widget was found.
func _drive_real_property_edit(plugin: EditorPlugin, target_object: Object, property_name: StringName, value: Variant) -> bool:
	var temp_inspector: EditorInspector = EditorInspector.new()
	plugin.get_tree().root.add_child(temp_inspector)
	temp_inspector.edit(target_object)
	await plugin.get_tree().process_frame
	var ep: EditorProperty = GSTInspectorColumn.find_editor_property_in(temp_inspector, property_name, target_object)
	var found: bool = ep != null
	if ep != null:
		ep.emit_changed(property_name, value)
		await plugin.get_tree().process_frame
	temp_inspector.queue_free()
	return found


## Item 3: switching to the text preset keeps the same ShaderMaterial
## instance on the new target node and, since coord_space is still uv,
## shows the screen_uv suggestion, and actually renders a different,
## non-uniform silhouette from the sprite preset it replaced (fix pass 2,
## item 2: a Label's per-glyph quad reads the checker field differently from
## a TextureRect's single full-rect quad, so the two presets' pixels must
## differ, not merely their message label); full_rect and back to sprite
## both keep rendering non-uniform pixels and the same material instance
## throughout.
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


## Item 4: soloing the checker layer replaces the output line with its field
## solo form without touching the stack (layer count, output_color,
## output_alpha unchanged); toggling solo off restores the exact pre-solo
## shader text.
func _run_phase5_solo_toggle(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, checker: GSTLayer) -> void:
	var stack: GSTStack = panel.get_stack()
	stack_list.select_layer(checker.id)
	await plugin.get_tree().process_frame

	var code_before_solo: String = panel.get_shader_material().shader.code
	var layers_before: int = stack.layers.size()
	var output_color_before: StringName = stack.output_color
	var output_alpha_before: StringName = stack.output_alpha

	panel.get_solo_check().button_pressed = true
	await plugin.get_tree().process_frame
	var code_solo: String = panel.get_shader_material().shader.code
	var has_solo_line: bool = code_solo.contains("COLOR = vec4(vec3(l%s), 1.0);" % String(checker.id))
	var stack_unchanged: bool = stack.layers.size() == layers_before and stack.output_color == output_color_before and stack.output_alpha == output_alpha_before
	_check("4a", has_solo_line and stack_unchanged, "solo on: has_solo_line=%s stack_unchanged=%s" % [has_solo_line, stack_unchanged])

	panel.get_solo_check().button_pressed = false
	await plugin.get_tree().process_frame
	var code_after: String = panel.get_shader_material().shader.code
	_check("4b", code_after == code_before_solo, "solo off: code equals pre-solo code byte for byte=%s" % [code_after == code_before_solo])


## Item 5: a lone source/texture layer renders the preview image itself;
## sampled at the viewport's own center against the source PNG's own center
## (both read directly, independent of any import artifact), within a
## tolerance that allows for the render pipeline's own filtering/color
## management, not exact byte equality.
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
		var source_img: Image = Image.new()
		source_img.load("res://addons/goshade_turbo/assets/preview_default.png")
		got = viewport_img.get_pixel(viewport_img.get_width() / 2, viewport_img.get_height() / 2)
		want = source_img.get_pixel(source_img.get_width() / 2, source_img.get_height() / 2)
		close = _colors_close(got, want, 0.12)
	_check("5", close, "texture source center pixel got=%s want=%s" % [got, want])
	return tex_layer


## Item 6: a lone source/screen layer reads the background through
## hint_screen_texture and renders the same image (decision 10).
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
		var source_img: Image = Image.new()
		source_img.load("res://addons/goshade_turbo/assets/preview_default.png")
		got = viewport_img.get_pixel(viewport_img.get_width() / 2, viewport_img.get_height() / 2)
		want = source_img.get_pixel(source_img.get_width() / 2, source_img.get_height() / 2)
		close = _colors_close(got, want, 0.12)
	_check("6", close, "screen source center pixel got=%s want=%s" % [got, want])


## Item 7: switching the stack column's coord space to local through the
## panel (GSTUndo.set_coord_space) declares gst_rect_size equal to the
## preview node's own rect and the vertex()-set varying; undoing restores
## uv. Item 7c/7d (docs/PLAN.md Phase 5 fix round): a resize with no
## structural stack edit in between must still push the new target rect into
## gst_rect_size (the target_rect_changed cheap path, B5), and a scale-1
## checker must render identically under local and uv at that resized rect.
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


## Item 7c: a scale-1 (default GSTCoordBlock.scale) checker is added under
## local space first, so the resize below is the only thing that changes
## afterward -- no GSTUndo structural edit runs between the resize and the
## readback, so gst_rect_size can only be correct here if
## GSTPreview.target_rect_changed -> GSTMainPanel._on_target_rect_changed
## actually caught the resize (every structural edit forces a full resync
## that would otherwise mask a stale-uniform bug by re-reading the live size
## anyway).
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


## Item 7d: proves B5's literal claim ("a coord-block scale of 1.0 matches
## uv", docs/PLAN.md:44) with real per-pixel evidence, at the resized rect
## 7c just produced.
##
## generative/checker.tres carries no manifest params (verified: params =
## Array[Dictionary]([])); cell density is entirely the per-layer
## coord.scale (gst_codegen.gd::_generator_body_lines feeds gst_transform(p,
## scale, rotation, offset) into checker(p) = mod(floor(p.x)+floor(p.y),
## 2.0)). A scale-1 checker with no offset is exactly one cell across the
## whole [0,1) rect (floor(p) == (0,0) everywhere), so it renders uniformly
## and can never distinguish local from uv -- the bug this rewrite fixes.
## Offsetting the single scale-1 cell boundary into view instead produces a
## real four-quadrant pattern without touching scale at all, honoring the
## literal "keep the coord block scale at 1.0" B5 test.
##
## Samples are the rect's four corners, not the x == y diagonal the fix
## request suggested: mod(floor(x)+floor(y), 2) is provably constant along
## that line (floor(x) == floor(y) there, so the sum is always even,
## regardless of scale or offset), so a diagonal sample set would be
## vacuous. The (0.5, 0.5) offset below instead makes the four corners land
## one in each quadrant, giving parities [0, 1, 1, 0] -- genuine, checkable
## evidence.
##
## Preset is switched to full_rect first so every sampled fraction lands
## inside the target node (previously a quarter-rect sample under the
## sprite preset read alpha 0, outside the node, per the fix request).
func _run_phase5_checker_grid_evidence(plugin: EditorPlugin, panel: GSTMainPanel, stack_list: GSTStackList, undo: GSTUndo, preview: GSTPreview) -> void:
	var stack: GSTStack = panel.get_stack()

	panel._on_preset_selected(2) # "full_rect"
	for i: int in range(3):
		await plugin.get_tree().process_frame

	panel._on_coord_space_selected(0) # "uv"
	await plugin.get_tree().process_frame

	var grid: GSTLayer = stack_list.add_layer_by_entry_id("generative/checker")
	undo.set_output_color(grid.id)
	_set_coord_property(grid.coord, stack, &"offset", Vector2(0.5, 0.5))
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

	# Negative control: bumping scale under local only (the uv reference
	# above stays captured at scale 1) proves the four-point comparison can
	# actually fail, not pass regardless of input.
	_set_coord_property(grid.coord, stack, &"scale", Vector2(2.0, 2.0))
	for i: int in range(2):
		await plugin.get_tree().process_frame

	var local_scaled_samples: Array[Color] = _sample_points(preview.get_viewport_image(), fracs)
	var differs_from_uv: bool = not _colors_all_close(local_scaled_samples, uv_samples, 0.05)
	_check("7d3", differs_from_uv, "local scale=2.0 corner samples=%s vs uv reference=%s (expect at least one differs)" % [local_scaled_samples, uv_samples])


## Item 8: mutating the stack directly through GSTStackOps (bypassing
## GSTUndo entirely, the way a future non-undo-routed caller might) and
## manually re-emitting stack_changed is the documented way to force a
## resync outside GSTUndo (docs/PLAN.md Phase 5 Verification). An unwired
## filter/pixelate "source" slot (its default, B10's Unwired filter rule)
## fails codegen; the message label shows the error and the material's code
## stays the last good one; removing the filter recovers.
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


## Phase 6: persistence and export (docs/PLAN.md Phase 6 Verification).
## Builds a three-layer stack through the panel, then round-trips it through
## save/New/open (.tres, GSTStackIO) and export/mutate/confirm/reopen
## (.gdshader, GSTExport), driving every step through the panel's own
## EditorFileDialog/ConfirmationDialog file-selected and confirmed handlers
## (_on_save_as_file_selected, _on_open_file_selected,
## _on_export_file_selected, _on_overwrite_confirmed,
## _on_reopen_shader_file_selected) rather than the plain path-taking
## open_path/save_to_path/export_to_path/reopen_shader_path seams those
## handlers themselves call, so this exercises the exact call chain a real
## dialog interaction produces, including the overwrite ConfirmationDialog
## actually showing (phase 6 fix pass 2, item 3). Files land under
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


## Item 1: a checker generator (output_color, renders a real checkerboard --
## the same proven-non-uniform layer phase 5's own render check uses), an
## fbm generator with a non-default int param, and an invert field op wired
## to fbm. Item 2: the Save As dialog's own file-selected handler,
## _on_save_as_file_selected, writes under sandbox/stacks/.
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


## Item 3 (phase 6 fix pass 2, item 1; docs/PLAN.md Cross-cutting
## "EditorUndoRedoManager integration"): New is itself an undoable "Replace
## stack" action (gst_main_panel.gd's replace_stack), not a history reset, so
## a pre-New structural edit stays undoable afterward instead of being
## discarded along with the replaced GSTStack.
##
## get_object_history_id() does not give a GSTStack its own private bucket
## the moment it exists: verified on 4.6.2, a GSTStack is a bare Resource
## never added to the edited scene, so EditorUndoRedoManager routes every
## custom_context = stack action for every such Resource, across every
## instance, into the one shared "Remote History" bucket for the life of the
## editor session. replace_stack relies on exactly this: the "Replace stack"
## action lands in the same bucket as the old stack's own prior actions, so
## one continuous Ctrl+Z chain walks through both.
##
## Sequence: has_undo() is true right after New; one undo restores the exact
## previous GSTStack instance (is_same), its three layers, and current_path;
## one redo re-applies New (zero layers, empty path); undoing twice more
## reaches the pre-New state of the old stack with its own last committed
## action (set_output_color in _run_phase6_build_and_save) undone too,
## proving the old stack's own GSTUndo instance -- not a freshly constructed
## one -- is still the one driving replay for its actions; redoing twice more
## returns to the New state so _run_phase6_open below continues from there
## unchanged.
func _run_phase6_new(plugin: EditorPlugin, panel: GSTMainPanel, ids: Dictionary) -> void:
	var old_stack: GSTStack = panel.get_stack()
	var old_path: String = panel.get_current_path()
	var old_layer_count: int = old_stack.layers.size()

	panel._on_new_pressed()
	await plugin.get_tree().process_frame
	var new_stack: GSTStack = panel.get_stack()
	var history: UndoRedo = _get_history(new_stack)
	var new_ok: bool = new_stack.layers.is_empty() and panel.get_current_path().is_empty() and not is_same(new_stack, old_stack)
	var has_undo_now: bool = history != null and history.has_undo()
	_check("3a", new_ok and has_undo_now, "New: layers=%d current_path='%s' new_instance=%s has_undo=%s" % [new_stack.layers.size(), panel.get_current_path(), not is_same(new_stack, old_stack), has_undo_now])

	history.undo()
	await plugin.get_tree().process_frame
	var restored_1: GSTStack = panel.get_stack()
	var layer_ids_match: bool = restored_1.layers.size() == 3 and restored_1.layers[0].id == ids["checker"] and restored_1.layers[1].id == ids["fbm"] and restored_1.layers[2].id == ids["invert"]
	var undo1_ok: bool = is_same(restored_1, old_stack) and restored_1.layers.size() == old_layer_count and layer_ids_match and panel.get_current_path() == old_path
	_check("3b", undo1_ok, "undo 1 after New restores the previous stack instance: is_same=%s layers=%d (expect %d) layer_ids_match=%s current_path='%s' (expect '%s')" % [is_same(restored_1, old_stack), restored_1.layers.size(), old_layer_count, layer_ids_match, panel.get_current_path(), old_path])

	history.redo()
	await plugin.get_tree().process_frame
	var restored_2: GSTStack = panel.get_stack()
	var redo1_ok: bool = is_same(restored_2, new_stack) and restored_2.layers.is_empty() and panel.get_current_path().is_empty()
	_check("3c", redo1_ok, "redo 1 re-applies New: is_same=%s layers=%d current_path='%s'" % [is_same(restored_2, new_stack), restored_2.layers.size(), panel.get_current_path()])

	history.undo()
	await plugin.get_tree().process_frame
	history.undo()
	await plugin.get_tree().process_frame
	var restored_3: GSTStack = panel.get_stack()
	var output_color_reverted: bool = restored_3.output_color == &""
	var undo_twice_more_ok: bool = is_same(restored_3, old_stack) and restored_3.layers.size() == old_layer_count and output_color_reverted
	_check("3d", undo_twice_more_ok, "undo twice more reaches the pre-New old stack with its own last action (set_output_color) undone: is_same=%s layers=%d (expect %d) output_color='%s' (expect '')" % [is_same(restored_3, old_stack), restored_3.layers.size(), old_layer_count, String(restored_3.output_color)])

	history.redo()
	await plugin.get_tree().process_frame
	history.redo()
	await plugin.get_tree().process_frame
	var final_stack: GSTStack = panel.get_stack()
	var final_ok: bool = is_same(final_stack, new_stack) and final_stack.layers.is_empty() and panel.get_current_path().is_empty() and final_stack.output_color == &""
	_check("3e", final_ok, "redo twice more returns to the New state: is_same=%s layers=%d current_path='%s'" % [is_same(final_stack, new_stack), final_stack.layers.size(), panel.get_current_path()])


## (phase 6 fix pass 2, item 3): pressing the Export button with no
## current_path (the panel is on the empty New'd stack here) always opens the
## export EditorFileDialog -- Export never silently writes without the user
## picking a target, unlike Save which falls back to the current path when
## one exists.
func _run_phase6_export_dialog_opens(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var path_before: String = panel.get_current_path()
	panel._on_export_pressed()
	await plugin.get_tree().process_frame
	var dialog_visible: bool = panel.is_export_dialog_visible()
	_check("3f", path_before.is_empty() and dialog_visible, "Export press with no current_path opens the export dialog: current_path='%s' (expect '') dialog_visible=%s" % [path_before, dialog_visible])
	panel.hide_export_dialog()


## Item 4: the Open dialog's own file-selected handler, _on_open_file_selected,
## reloads the same three layer ids in the same order, fbm's non-default
## octaves param survives, and the preview (driven from the checker
## output_color) renders non-uniform pixels again.
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


## Item 5: the Export dialog's own file-selected handler, _on_export_file_selected,
## writes a real file with a header line. Items 6-7: mutating one body byte on
## disk makes a re-selected export path trigger the overwrite check and show
## the ConfirmationDialog, leaving the file untouched; the dialog's own
## confirmed handler, _on_overwrite_confirmed, then overwrites it and hides
## the dialog.
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


## Item 8: the Reopen Shader dialog's own file-selected handler,
## _on_reopen_shader_file_selected, rebuilds a stack with the same three layer
## ids the original build produced (decision 22: ids are stable across save,
## export, and reopen).
func _run_phase6_reopen(plugin: EditorPlugin, panel: GSTMainPanel, export_path: String, ids: Dictionary) -> void:
	panel._on_reopen_shader_file_selected(export_path)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var stack: GSTStack = panel.get_stack()
	var ids_match: bool = stack.layers.size() == 3 and stack.layers[0].id == ids["checker"] and stack.layers[1].id == ids["fbm"] and stack.layers[2].id == ids["invert"]
	_check("8", ids_match, "_on_reopen_shader_file_selected rebuilds the same ids: %s (current_path='%s', expect empty)" % [ids_match, panel.get_current_path()])


## Item 9: a hand-written .gdshader with no "// stack:" header is refused
## (B8), the reason lands in the message label, and no new empty stack
## replaces the one reopen() just rebuilt in item 8.
func _run_phase6_headerless_reopen_refusal(plugin: EditorPlugin, panel: GSTMainPanel, headerless_path: String) -> void:
	_write_file(headerless_path, "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0); }\n")
	var stack_before: GSTStack = panel.get_stack()

	panel._on_reopen_shader_file_selected(headerless_path)
	await plugin.get_tree().process_frame
	var refused: bool = panel.get_message_label().text.contains("header")
	var stack_unchanged: bool = panel.get_stack() == stack_before
	_check("9", refused and stack_unchanged, "reopen of a headerless file is refused (B8): message='%s' stack_unchanged=%s" % [panel.get_message_label().text, stack_unchanged])


## Phase 7: three-recipe proof and the rendered-check harness (docs/PLAN.md
## Phase 7 Verification, design build order step 4). For each of the three
## recipes: builds the same stack through GSTUndo's own public actions (add,
## wire, output -- the same calls the picker/stack list/output block use) and
## the same undoable-property pattern items 2 and 16a above already proved
## for slider edits, captures the resulting shader text, undoes back to an
## empty stack, redoes back to the captured text byte for byte with a
## non-uniform preview, then loads the shipped recipe through the Recipes
## menu's own open_recipe() and checks the panel lands on the same codegen
## text a fresh, independent load of that same recipe file produces (ids may
## differ between the panel-built stack and the shipped recipe's own ids, so
## this compares against a fresh codegen of the recipe file, never against
## the earlier capture).
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

	var library: GSTLibrary = panel.get_library()
	# The shared "Remote History" bucket (docs/PLAN.md Cross-cutting
	# "EditorUndoRedoManager integration"): get_object_history_id() resolves
	# to the same UndoRedo regardless of which bare GSTStack instance is
	# passed, so this one reference stays valid across every New/open_recipe
	# replace_stack below.
	var history: UndoRedo = _get_history(panel.get_stack())

	await _run_phase7_dissolve(plugin, panel, history, library)
	await _run_phase7_sprite_holographic(plugin, panel, history, library)
	await _run_phase7_outline(plugin, panel, history, library)
	await _run_phase7_history_anchor(plugin, panel)

	_finish(plugin)


## Alpha path proof (docs/PLAN.md Phase 7 Build): source/texture; fbm; a
## primary smoothstep threshold on the fbm; alpha(texture) times that
## threshold as output alpha; an edge band (a lower-edge smoothstep times the
## inverted primary threshold) masking a color/mix between texture and an
## orange fill for the output color. Mirrors addons/goshade_turbo/recipes/
## dissolve.tres's own construction exactly.
func _run_phase7_dissolve(plugin: EditorPlugin, panel: GSTMainPanel, history: UndoRedo, library: GSTLibrary) -> void:
	panel._on_new_pressed()
	await plugin.get_tree().process_frame
	var undo: GSTUndo = panel.get_undo()

	var texture: GSTLayer = undo.add_layer("source/texture", GSTLayer.Kind.COLOR, false)

	var fbm: GSTLayer = undo.add_layer("generative/fbm", GSTLayer.Kind.FIELD, true)
	_set_coord_property(fbm.coord, panel.get_stack(), &"scale", Vector2(4.0, 4.0))

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


## Color chain with scroll proof (docs/PLAN.md Phase 7 Build): a rotated,
## scrolling stripes field drives the cosine rainbow palette (its default
## a/b/c/d matches Capsule Castle's own SpriteHolographic.gdshader palette()
## constants), screen-blended over the texture source. Mirrors
## addons/goshade_turbo/recipes/sprite_holographic.tres's own construction
## exactly.
func _run_phase7_sprite_holographic(plugin: EditorPlugin, panel: GSTMainPanel, history: UndoRedo, library: GSTLibrary) -> void:
	panel._on_new_pressed()
	await plugin.get_tree().process_frame
	var undo: GSTUndo = panel.get_undo()

	var texture: GSTLayer = undo.add_layer("source/texture", GSTLayer.Kind.COLOR, false)

	var band: GSTLayer = undo.add_layer("generative/stripes", GSTLayer.Kind.FIELD, true)
	_set_coord_property(band.coord, panel.get_stack(), &"scale", Vector2(2.83, 2.83))
	_set_coord_property(band.coord, panel.get_stack(), &"rotation", -0.7853982)
	_set_coord_property(band.coord, panel.get_stack(), &"scroll", Vector2(0.4, 0.0))

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


## Source filter path proof (docs/PLAN.md Phase 7 Build): filter/outline on
## the texture source, a fill color for the outline, color/mix masked by the
## outline layer (auto luma-converted, decision 2), output alpha the mix's
## own color_alpha rather than "texture" so the outline ring drawn outside
## the sprite silhouette stays visible. Mirrors
## addons/goshade_turbo/recipes/outline.tres's own construction exactly.
func _run_phase7_outline(plugin: EditorPlugin, panel: GSTMainPanel, history: UndoRedo, library: GSTLibrary) -> void:
	panel._on_new_pressed()
	await plugin.get_tree().process_frame
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


## Shared tail for all three recipe builders above: capture, undo to empty,
## redo back to the capture (text byte-equal, preview non-uniform), then
## open_recipe(recipe_name) and check the panel lands on the same codegen
## text a fresh, independent GSTStackIO.load of
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


## History anchor regression (docs/PLAN.md Cross-cutting "EditorUndoRedoManager
## integration", "History anchor (phase 7)"): a GSTUndo action committed while
## the open stack carries a real res:// path (open_recipe / reopen_shader_path
## both load through GSTStackIO, which sets resource_path on the returned
## Resource) must land in the same UndoRedo bucket panel.get_watched_history()
## resolves, not a bucket keyed off the path-bearing stack instance itself.
## Drives panel.get_watched_history() directly (rather than the smoke's own
## _get_history(stack) helper, which recomputes get_object_history_id(stack)
## and would silently pass even if GSTUndo's own custom_context landed
## elsewhere, since a fresh lookup off the same stack instance always agrees
## with itself). The layer-gone-and-text-matches-post-open check after undo is
## the real differentiator: add_layer's own commit_action(false) always
## applies the mutation and calls _notify() synchronously regardless of which
## bucket the action registers to, so has_undo()/resync alone would pass even
## on the wrong bucket -- only calling undo() on the panel's actual watched
## history and checking it removes the add (not some other action, e.g.
## re-undoing the open_recipe/reopen_shader_path replace itself) proves the
## anchor is shared.
func _run_phase7_history_anchor(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	await _run_phase7_history_anchor_open_recipe(plugin, panel)
	await _run_phase7_history_anchor_reopen_shader(plugin, panel)


## The comparable part of a synced material's shader text: everything below
## the "// stack: <json>" header line, excluding the header itself. The
## header's next_id never reverts on undo of an add (decision 22: "undo
## removes the layer from the array but never touches stack.next_id"), so a
## full-text comparison across an add-then-undo would legitimately differ by
## the header's next_id field alone, even with the layer content identical
## (same pattern as tests/test_codegen_generator.gd's own header-scoped
## comparison, docs/PLAN.md Phase 6 Files).
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


## Appends a trailing space to the first non-empty line strictly after the
## header line -- a real one-byte body mutation that never touches the
## header's own JSON (mirrors tests/test_overwrite_check.gd's
## _mutate_body_char).
func _mutate_body_line(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	for i: int in range(lines.size()):
		if lines[i].begins_with(GSTHeader.HEADER_PREFIX):
			for j: int in range(i + 1, lines.size()):
				if not lines[j].is_empty():
					lines[j] = lines[j] + " "
					return "\n".join(lines)
	return text


## True when a sparse grid sample of img shows no variation at all (used as
## "the render is blank/uniform" rather than a true per-pixel scan, cheap
## enough to run every frame this script waits on).
func _image_is_uniform(img: Image) -> bool:
	var w: int = img.get_width()
	var h: int = img.get_height()
	if w == 0 or h == 0:
		return true
	var first: Color = img.get_pixel(0, 0)
	# Step off the smaller dimension: the preview viewport tracks the panel's
	# own (frequently non-square, sometimes narrow) column rect, and a step
	# derived only from width would skip past every pattern boundary on a
	# short-and-wide rect.
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


func _colors_close(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) <= tolerance and absf(a.g - b.g) <= tolerance and absf(a.b - b.b) <= tolerance and absf(a.a - b.a) <= tolerance


## Reads img at each fraction in fracs (0..1 of width/height); Color.BLACK
## per point when img is null, so a null viewport read still returns a
## same-length array instead of failing the caller outright.
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


## Sets a GSTCoordBlock property through the same EditorUndoRedoManager
## create_action/add_do_property/commit_action() (default execute = true)
## path item 2 above uses for coord.scale: a real property-undo action, the
## same shape an inspector slider drag registers, that actually applies the
## do value on this initial commit (unlike GSTUndo's own commit_action(false)
## + manual _notify(), which is a different call shape for a different
## purpose -- routing structural edits through GSTUndo's one history bucket).
func _set_coord_property(coord: GSTCoordBlock, stack: GSTStack, property: StringName, value: Variant) -> void:
	var old_value: Variant = coord.get(property)
	var editor_undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	editor_undo_redo.create_action("set coord %s" % property, UndoRedo.MERGE_DISABLE, stack)
	editor_undo_redo.add_do_property(coord, property, value)
	editor_undo_redo.add_undo_property(coord, property, old_value)
	editor_undo_redo.commit_action()


## Sets layer.<property_name> -- a manifest param, dynamic via
## GSTLayer._get/_set -- through a real EditorUndoRedoManager property
## action, the same shape a real inspector slider commit uses (item 2 and
## item 16a above), rather than a raw Dictionary write straight into
## layer.params (docs/PLAN.md Phase 7 Build: "set params via the layer
## resources with undoable property actions"), so the phase 7 recipe builds
## register real, undoable history for every param the same way a live edit
## would.
func _set_layer_param(panel: GSTMainPanel, layer: GSTLayer, property_name: StringName, value: Variant) -> void:
	var old_value: Variant = layer.get(property_name)
	var editor_undo_redo: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	editor_undo_redo.create_action("set %s" % property_name, UndoRedo.MERGE_DISABLE, panel.get_stack())
	editor_undo_redo.add_do_property(layer, property_name, value)
	editor_undo_redo.add_undo_property(layer, property_name, old_value)
	editor_undo_redo.commit_action()


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
