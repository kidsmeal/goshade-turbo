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
	await plugin.get_tree().process_frame
	var stack: GSTStack = panel.get_stack()
	var stack_list: GSTStackList = panel.get_stack_list()
	var undo: GSTUndo = panel.get_undo()
	var history: UndoRedo = panel.get_watched_history()

	var invalid_layers: Array[GSTLayer] = stack.layers.duplicate()
	var invalid_next_id: int = stack.next_id
	var invalid_history: int = history.get_history_count()
	var invalid_add: Dictionary = undo.add_layer_for_ui("missing/entry")
	_check("invalid_top_add", not invalid_add["ok"] and stack.layers == invalid_layers and stack.next_id == invalid_next_id and history.get_history_count() == invalid_history, "ok=%s next_id=%d history=%d reason='%s'" % [invalid_add["ok"], stack.next_id, history.get_history_count(), invalid_add["reason"]])

	var first_count: int = history.get_history_count()
	var texture: GSTLayer = stack_list.add_layer_by_entry_id("source/texture")
	await plugin.get_tree().process_frame
	_check("first_add", texture != null and stack.layers.size() == 1 and stack.output_color == texture.id and history.get_history_count() == first_count + 1, "layers=%d output='%s' id='%s' history=%d->%d" % [stack.layers.size(), String(stack.output_color), String(texture.id) if texture != null else "null", first_count, history.get_history_count()])

	var filter_count: int = history.get_history_count()
	var filter: GSTLayer = stack_list.add_layer_by_entry_id("filter/pixelate")
	await plugin.get_tree().process_frame
	var filter_ok: bool = filter != null and filter.slots.get("source", &"") == texture.id and stack.output_color == filter.id
	_check("source_filter_default", filter_ok and history.get_history_count() == filter_count + 1, "source='%s' output='%s' history=%d->%d" % [String(filter.slots.get("source", &"")) if filter != null else "null", String(stack.output_color), filter_count, history.get_history_count()])

	history.undo()
	await plugin.get_tree().process_frame
	var undo_filter_ok: bool = GSTStackOps.find_layer(stack, filter.id) == null and stack.output_color == texture.id and stack.next_id == 2
	_check("top_add_undo", undo_filter_ok, "filter_gone=%s output='%s' next_id=%d" % [GSTStackOps.find_layer(stack, filter.id) == null, String(stack.output_color), stack.next_id])
	history.redo()
	await plugin.get_tree().process_frame
	_check("top_add_redo", GSTStackOps.find_layer(stack, filter.id) == filter and stack.output_color == filter.id and filter.slots.get("source", &"") == texture.id, "same_instance=%s output='%s' source='%s'" % [GSTStackOps.find_layer(stack, filter.id) == filter, String(stack.output_color), String(filter.slots.get("source", &""))])

	var mix: GSTLayer = stack_list.add_layer_by_entry_id("color/mix")
	await plugin.get_tree().process_frame
	var multi_ok: bool = mix != null and mix.slots.get("a", &"") == filter.id and mix.slots.get("b", &"") == filter.id and mix.slots.get("mask", &"") == filter.id and stack.output_color == mix.id
	_check("multi_input_default", multi_ok, "a='%s' b='%s' mask='%s' output='%s'" % [String(mix.slots.get("a", &"")), String(mix.slots.get("b", &"")), String(mix.slots.get("mask", &"")), String(stack.output_color)])

	var before_insert_count: int = history.get_history_count()
	mix.slots.erase("mask")
	var insert_result: Dictionary = undo.add_layer_below_and_wire(mix.id, "fieldops/invert", "mask")
	await plugin.get_tree().process_frame
	var inserted: GSTLayer = stack.layers[GSTStackOps.find_index(stack, mix.id) - 1]
	var insert_ok: bool = insert_result["ok"] and inserted.entry == "fieldops/invert" and inserted.slots.get("x", &"") == filter.id and mix.slots.get("mask", &"") == inserted.id and stack.output_color == mix.id
	_check("add_for_input", insert_ok and history.get_history_count() == before_insert_count + 1, "entry='%s' own_x='%s' mask='%s' output='%s' history=%d->%d" % [inserted.entry, String(inserted.slots.get("x", &"")), String(mix.slots.get("mask", &"")), String(stack.output_color), before_insert_count, history.get_history_count()])

	history.undo()
	await plugin.get_tree().process_frame
	_check("add_for_input_undo", GSTStackOps.find_layer(stack, inserted.id) == null and not mix.slots.has("mask") and stack.output_color == mix.id, "inserted_gone=%s mask_present=%s output='%s'" % [GSTStackOps.find_layer(stack, inserted.id) == null, mix.slots.has("mask"), String(stack.output_color)])
	history.redo()
	await plugin.get_tree().process_frame
	_check("add_for_input_redo", GSTStackOps.find_layer(stack, inserted.id) == inserted and inserted.slots.get("x", &"") == filter.id and mix.slots.get("mask", &"") == inserted.id and stack.output_color == mix.id, "same_instance=%s own_x='%s' mask='%s' output='%s'" % [GSTStackOps.find_layer(stack, inserted.id) == inserted, String(inserted.slots.get("x", &"")), String(mix.slots.get("mask", &"")), String(stack.output_color)])

	var layers_before_refusal: Array[GSTLayer] = stack.layers.duplicate()
	var output_before_refusal: StringName = stack.output_color
	var next_id_before_refusal: int = stack.next_id
	var history_before_refusal: int = history.get_history_count()
	var refusal: Dictionary = undo.add_layer_below_and_wire(filter.id, "color/fill", "source")
	_check("refusal_atomic", not refusal["ok"] and stack.layers == layers_before_refusal and stack.output_color == output_before_refusal and stack.next_id == next_id_before_refusal and history.get_history_count() == history_before_refusal, "ok=%s layers_same=%s output='%s' next_id=%d history=%d" % [refusal["ok"], stack.layers == layers_before_refusal, String(stack.output_color), stack.next_id, history.get_history_count()])

	var unknown_refusal: Dictionary = undo.add_layer_below_and_wire(mix.id, "color/fill", "missing")
	_check("unknown_slot_atomic", not unknown_refusal["ok"] and stack.layers == layers_before_refusal and stack.output_color == output_before_refusal and stack.next_id == next_id_before_refusal and history.get_history_count() == history_before_refusal, "ok=%s reason='%s' next_id=%d history=%d" % [unknown_refusal["ok"], unknown_refusal["reason"], stack.next_id, history.get_history_count()])

	var field: GSTLayer = stack_list.add_layer_by_entry_id("generative/hash")
	await plugin.get_tree().process_frame
	var warp_button: Button = panel.get_inspector_column().get_warp_button("x")
	warp_button.pressed.emit()
	await plugin.get_tree().process_frame
	var warp_rows: Array[Dictionary] = panel.get_picker().get_visible_rows()
	var color_warp_candidate: bool = false
	for row: Dictionary in warp_rows:
		if String(row.get("value", "")) == String(mix.id) and String(row.get("conversion", "")) == "color -> field: luminance":
			color_warp_candidate = true
	_check("color_warp_candidate", color_warp_candidate, "warp chooser rows=%s include color layer='%s' with luminance conversion=%s" % [panel.get_picker().get_visible_entry_ids(), String(mix.id), color_warp_candidate])
	panel._close_picker()
	await plugin.get_tree().process_frame
	var illegal_filter: GSTLayer = stack_list.add_layer_by_entry_id("filter/pixelate")
	await plugin.get_tree().process_frame
	_check("illegal_filter_default", field != null and illegal_filter != null and not illegal_filter.slots.has("source") and stack.output_color == illegal_filter.id, "source_present=%s output='%s'" % [illegal_filter.slots.has("source"), String(stack.output_color)])
	history.undo()
	await plugin.get_tree().process_frame
	_check("illegal_filter_undo", GSTStackOps.find_layer(stack, illegal_filter.id) == null and stack.output_color == field.id, "filter_gone=%s output='%s'" % [GSTStackOps.find_layer(stack, illegal_filter.id) == null, String(stack.output_color)])

	var warp_result: Dictionary = undo.assign_warp(field.id, "x", mix.id)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var shader_code: String = GSTCodegen.generate(stack, panel.get_library())
	var preview_image: Image = panel.get_preview().get_viewport_image()
	var render_ok: bool = preview_image != null and not _image_is_uniform(preview_image)
	_check("color_warp", warp_result["ok"] and field.coord.warp_x == mix.id and shader_code.contains("luma(l%s)" % mix.id) and shader_code.contains("float luma(vec4 c)") and panel.get_message_label().text.is_empty() and render_ok, "ok=%s warp='%s' luma=%s message='%s' nonuniform=%s" % [warp_result["ok"], String(field.coord.warp_x), shader_code.contains("luma(l%s)" % mix.id), panel.get_message_label().text, render_ok])

	history.undo()
	await plugin.get_tree().process_frame
	_check("color_warp_undo", field.coord.warp_x == &"", "warp='%s'" % String(field.coord.warp_x))
	history.redo()
	await plugin.get_tree().process_frame
	_check("color_warp_redo", field.coord.warp_x == mix.id, "warp='%s'" % String(field.coord.warp_x))

	history.undo()
	await plugin.get_tree().process_frame
	history.undo()
	await plugin.get_tree().process_frame
	var id_before_branch: int = stack.next_id
	var replacement: GSTLayer = stack_list.add_layer_by_entry_id("color/fill")
	await plugin.get_tree().process_frame
	_check("ids_not_reused", replacement != null and int(String(replacement.id)) == id_before_branch and stack.next_id == id_before_branch + 1, "replacement_id='%s' expected=%d next_id=%d" % [String(replacement.id) if replacement != null else "null", id_before_branch, stack.next_id])
	for i: int in range(5):
		await plugin.get_tree().process_frame
	var final_image: Image = panel.get_preview().get_viewport_image()
	_check("final_settle", final_image != null and final_image.get_width() > 0 and final_image.get_height() > 0 and panel.get_message_label().text.is_empty(), "image=%s message='%s'" % [final_image.get_size() if final_image != null else Vector2i.ZERO, panel.get_message_label().text])

	_finish(plugin)


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


func _image_is_uniform(image: Image) -> bool:
	if image == null or image.get_width() == 0 or image.get_height() == 0:
		return true
	var first: Color = image.get_pixel(0, 0)
	var step: int = maxi(1, mini(image.get_width(), image.get_height()) / 16)
	for y: int in range(0, image.get_height(), step):
		for x: int in range(0, image.get_width(), step):
			if not image.get_pixel(x, y).is_equal_approx(first):
				return false
	return true
