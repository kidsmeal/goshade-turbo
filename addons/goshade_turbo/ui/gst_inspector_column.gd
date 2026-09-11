@tool
class_name GSTInspectorColumn
extends VBoxContainer

## Selected-layer controls. Manifest params and coordinates use standalone
## native property rows (phase 2, docs/SHADER_TABS_reviewed-plan.md: no
## embedded EditorInspector remains in this column); input and distortion
## references route through GSTUndo via picker buttons, unchanged.
##
## Each row is built directly with EditorInspector.instantiate_property_editor
## (a static factory, independent of any EditorInspector container), the same
## proven mechanism phase 1's tabs_proof used outside a real inspector. This
## column owns gesture tracking for each row's public EditorSpinSlider
## descendants (grabbed/ungrabbed/value_focus_entered/value_focus_exited) and
## the `changing` fallback for controls with no such descendants (native
## color popups), and finishes each completed gesture through
## GSTUndo.commit_property_change -- the only path a native edit reaches the
## stack now (decision superseding 20: edits no longer come free from an
## embedded inspector's own undo integration).

signal edit_refused(reason: String)
signal chooser_requested(purpose: String, layer_id: StringName, slot_name: String, initiator: Control)
signal section_state_changed(states: Dictionary)
## Forwards a real ui_undo/ui_redo keyboard shortcut received while a native
## color popup holds focus (phase 2 review round 3 finding): Godot's
## embedded-subwindow forwarding (scene/main/viewport.cpp) claims a focused
## popup's own key events before gst_main_panel.gd's root-viewport _input()
## ever runs, so the popup's own Window signals it here instead
## (_on_color_popup_window_input below), and gst_main_panel.gd connects this
## straight to its own _apply_keyboard_undo_redo.
signal color_popup_undo_redo_requested(redo: bool)

var _scroll: ScrollContainer = null
var _sections: VBoxContainer = null
var _parameter_rows_box: VBoxContainer = null
var _coord_rows_box: VBoxContainer = null
var _inputs_box: VBoxContainer = null
var _warp_box: VBoxContainer = null
var _slot_picker: GSTPicker = null
var _input_buttons: Dictionary = {}
var _warp_buttons: Dictionary = {}
var _section_buttons: Dictionary = {}
var _section_contents: Dictionary = {}

var _stack: GSTStack = null
var _library: GSTLibrary = null
var _undo: GSTUndo = null
var _layer: GSTLayer = null
var _mutations_blocked: bool = false
var _refusals: Dictionary = {}
## key (see _row_key) -> {"editor": EditorProperty, "target": Object,
## "property": StringName, "state": Dictionary}. Rebuilt wholesale on every
## edit(); a row's state never survives its own rebuild, matching the prior
## embedded-EditorInspector behavior of rebinding fresh widgets per edit().
var _property_rows: Dictionary = {}


func _ready() -> void:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_sections = VBoxContainer.new()
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_scroll.add_child(_sections)

	var inputs: Dictionary = _build_section("inputs", "Inputs")
	_inputs_box = inputs["content"] as VBoxContainer

	var parameters: Dictionary = _build_section("parameters", "Parameters")
	_parameter_rows_box = VBoxContainer.new()
	_parameter_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(parameters["content"] as VBoxContainer).add_child(_parameter_rows_box)

	var position: Dictionary = _build_section("position", "Position and movement")
	var position_content: VBoxContainer = position["content"] as VBoxContainer
	_coord_rows_box = VBoxContainer.new()
	_coord_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	position_content.add_child(_coord_rows_box)
	_warp_box = VBoxContainer.new()
	_warp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	position_content.add_child(_warp_box)


func _build_section(key: String, title: String) -> Dictionary:
	var section: VBoxContainer = VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_sections.add_child(section)
	var heading: Button = Button.new()
	heading.text = title
	heading.flat = true
	heading.toggle_mode = true
	heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
	section.add_child(heading)
	var separator: HSeparator = HSeparator.new()
	section.add_child(separator)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	section.add_child(content)
	heading.toggled.connect(_on_section_toggled.bind(key, content, heading))
	_section_buttons[key] = heading
	_section_contents[key] = content
	return {"section": section, "content": content}


func _on_section_toggled(collapsed: bool, key: String, content: VBoxContainer, heading: Button) -> void:
	content.visible = not collapsed
	heading.tooltip_text = "Expand %s" % heading.text if collapsed else "Collapse %s" % heading.text
	section_state_changed.emit(get_section_states())


func get_section_states() -> Dictionary:
	var states: Dictionary = {}
	for key: Variant in _section_buttons:
		states[key] = (_section_buttons[key] as Button).button_pressed
	return states


func set_section_states(states: Dictionary) -> void:
	for key: Variant in _section_buttons:
		var collapsed: bool = bool(states.get(key, false))
		var button: Button = _section_buttons[key] as Button
		button.set_pressed_no_signal(collapsed)
		(_section_contents[key] as VBoxContainer).visible = not collapsed


func setup(stack: GSTStack, library: GSTLibrary, undo: GSTUndo) -> void:
	_stack = stack
	_library = library
	_undo = undo
	clear_refusals()


## Points the inspector at layer_id's GSTLayer. An empty id clears the
## column (nothing selected). Finishes any pending native gesture and closes
## an open native color popup on the previous layer before rebinding (decision
## superseding 20: a rebind must never leave a pending edit stranded on a row
## about to be freed).
func edit(layer_id: StringName) -> void:
	await finish_pending_edits()
	_layer = GSTStackOps.find_layer(_stack, layer_id)
	_prune_refusals()
	if _layer != null:
		_layer.manifest = _library.get_entry(_layer.entry)
	_rebuild_parameter_rows()
	_rebuild_coord_rows()
	_rebuild_slots()
	_schedule_rows_layout_update(_parameter_rows_box)
	_schedule_rows_layout_update(_coord_rows_box)
	_schedule_context_update()


## Before rebind, Save/Save As, shutdown save, or undo/redo, finishes any
## active numeric gesture and closes any open native color popup, so the
## pending value reaches its original target before the caller continues
## (decision superseding 20; phase 1 tabs_proof "forced_finish_ordering").
## Flushes any pending numeric text first (phase 2 review round 1 fix pass):
## Godot evaluates a typed EditorSpinSlider value only on its internal
## LineEdit's own focus exit, so a cached "final" value can omit a typed
## value that was never submitted; releasing that focus here delivers it
## through the row's own value_focus_exited path (already wired below)
## before this function's own commit loop reads state["final"].
func finish_pending_edits() -> void:
	for entry: Variant in _property_rows.values().duplicate():
		if bool((entry["state"] as Dictionary)["active"]):
			_flush_pending_row_text(entry)
	# An active color-popup row is excluded here and left to
	# _force_close_color_popups below: its true final value is only known
	# once the popup's own close handler has actually run (deferred), so
	# committing it early from whatever state["final"] holds mid-interaction
	# would race that handler's own unconditional restore-then-conditional-
	# commit write.
	var active_keys: Array = []
	for key: String in _property_rows.keys():
		var state: Dictionary = _property_rows[key]["state"]
		if bool(state["active"]) and String(state["boundary"]) != "color_popup":
			active_keys.append(key)
	for key: String in active_keys:
		var entry: Variant = _property_rows.get(key)
		if entry == null:
			continue
		var state: Dictionary = entry["state"]
		if bool(state["active"]):
			_commit_row(key, state["original"], state["final"], bool(state["original_present"]))
	await _force_close_color_popups()


## Releases focus of a row's own numeric text-entry LineEdit, if one is
## currently focused, so Godot commits its typed value synchronously (via
## the row's own value_focus_exited connection) instead of leaving it
## pending. A no-op when the row holds no such focused control.
func _flush_pending_row_text(entry: Dictionary) -> void:
	var editor: EditorProperty = entry["editor"] as EditorProperty
	if editor == null or not is_instance_valid(editor):
		return
	var line_edit: LineEdit = _find_focused_line_edit(editor)
	if line_edit != null:
		line_edit.release_focus()


static func _find_focused_line_edit(node: Node) -> LineEdit:
	if node is LineEdit and (node as LineEdit).has_focus():
		return node as LineEdit
	for child: Node in node.get_children():
		var found: LineEdit = _find_focused_line_edit(child)
		if found != null:
			return found
	return null


## Force-finishes every row whose native color popup is open or whose close
## has been triggered but has not yet delivered its final value: closing the
## popup here only starts that delivery, since EditorPropertyColor connects
## its own close handler CONNECT_DEFERRED (phase 2 review round 2 fix pass).
## Waits for each such row's own gesture state to clear (set by
## _finish_color_popup, itself driven by the popup's own popup_closed
## signal) before returning, so a caller awaiting this is never handed
## control back with a pending native color edit still in flight.
func _force_close_color_popups() -> void:
	for key: String in _property_rows.keys().duplicate():
		var entry: Variant = _property_rows.get(key)
		if entry == null:
			continue
		var state: Dictionary = entry["state"]
		if not bool(state["active"]) or String(state["boundary"]) != "color_popup":
			continue
		var editor: EditorProperty = entry["editor"] as EditorProperty
		var button: ColorPickerButton = _find_color_button(editor) if editor != null and is_instance_valid(editor) else null
		if button != null and is_instance_valid(button) and button.get_popup().visible:
			var picker: ColorPicker = button.get_picker()
			var focused: Control = picker.get_viewport().gui_get_focus_owner()
			if focused is LineEdit and picker.is_ancestor_of(focused):
				focused.release_focus()
				await get_tree().process_frame
			if is_instance_valid(button) and button.get_popup().visible:
				button.get_popup().hide()
		await _await_row_inactive(state)


## Bounded wait for state["active"] to clear, since the deferred handler that
## clears it (_finish_color_popup, via commit) runs on a later idle-frame
## flush rather than synchronously with hide() above.
func _await_row_inactive(state: Dictionary) -> void:
	var attempts: int = 0
	while bool(state["active"]) and attempts < 10:
		attempts += 1
		await get_tree().process_frame


## True if focus is inside a currently open native color popup this column
## owns. Wired-by: gst_main_panel.gd's keyboard Undo/Redo scoping, so a
## popup counts as GoShade focus even though a Popup's own Window sits
## outside this column's Control ancestry.
func owns_popup_focus(focus: Control) -> bool:
	if focus == null:
		return false
	for entry: Dictionary in _property_rows.values():
		var button: ColorPickerButton = _find_color_button(entry["editor"] as Node)
		if button != null and button.get_popup().visible and button.get_popup().is_ancestor_of(focus):
			return true
	return false


static func _find_color_button(node: Node) -> ColorPickerButton:
	if node is ColorPickerButton:
		return node as ColorPickerButton
	for child: Node in node.get_children():
		var found: ColorPickerButton = _find_color_button(child)
		if found != null:
			return found
	return null


## Manifest params (get_param_schema-backed dynamic properties). Skips
## anything the layer's own _validate_property hid from the editor.
func _rebuild_parameter_rows() -> void:
	_clear_rows(_parameter_rows_box)
	if _layer == null:
		return
	for property: Dictionary in _layer.get_property_list():
		if int(property.get("usage", 0)) & PROPERTY_USAGE_EDITOR == 0:
			continue
		var property_name: StringName = StringName(property["name"])
		var metadata: Dictionary = _layer.get_param_schema(property_name)
		if metadata.is_empty():
			continue
		_build_property_row(_parameter_rows_box, "param", _layer, property, String(metadata["label"]), String(metadata["description"]))


## Coord block whitelist (scale/offset/rotation/scroll/warp_strength).
## warp_x/warp_y stay button-based rows in _warp_box (_rebuild_slots), never
## native property rows: GSTCoordBlock._validate_property already strips
## their editor usage.
func _rebuild_coord_rows() -> void:
	_clear_rows(_coord_rows_box)
	if _layer == null or _layer.coord == null:
		return
	var coord: GSTCoordBlock = _layer.coord
	for property: Dictionary in coord.get_property_list():
		if int(property.get("usage", 0)) & PROPERTY_USAGE_EDITOR == 0:
			continue
		var property_name: StringName = StringName(property["name"])
		var metadata: Dictionary = GSTCoordBlock.get_editor_metadata(property_name)
		if metadata.is_empty():
			continue
		_build_property_row(_coord_rows_box, "coord", coord, property, String(metadata["label"]), String(metadata["description"]))


func _clear_rows(box: VBoxContainer) -> void:
	for key: String in _property_rows.keys().duplicate():
		if (_property_rows[key]["row"] as Node).get_parent() == box:
			_property_rows.erase(key)
	for child: Node in box.get_children():
		child.queue_free()


func _build_property_row(box: VBoxContainer, kind: String, target: Object, property: Dictionary, label: String, description: String) -> void:
	var hint: PropertyHint = int(property.get("hint", PROPERTY_HINT_NONE))
	var editor: EditorProperty = EditorInspector.instantiate_property_editor(target, int(property.get("type", TYPE_NIL)), String(property["name"]), hint, String(property.get("hint_string", "")), int(property.get("usage", PROPERTY_USAGE_DEFAULT)), false)
	if editor == null:
		return
	var property_name: StringName = StringName(property["name"])
	editor.set_object_and_property(target, property_name)
	editor.set_label(label)
	editor.set_tooltip_text(description)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.update_property()
	var row: VBoxContainer = VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(editor)
	if (kind == "coord" and property_name in [&"warp_strength", &"offset", &"scroll", &"rotation"]) or (kind == "param" and property_name in [&"gain", &"edge0", &"edge1"]):
		var context: Label = Label.new()
		context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		context.hide()
		editor.set_meta(&"gst_context_label", context)
		row.add_child(context)
	box.add_child(row)

	var key: String = _row_key(target, property_name)
	var state: Dictionary = {"original": target.get(property_name), "final": target.get(property_name), "active": false, "boundary": "", "original_present": _param_present(target, property_name)}
	_property_rows[key] = {"row": row, "editor": editor, "target": target, "property": property_name, "state": state}
	editor.property_changed.connect(_on_bound_property_changed.bind(key))
	for spin_node: Node in editor.find_children("*", "EditorSpinSlider", true, false):
		var spin: EditorSpinSlider = spin_node as EditorSpinSlider
		spin.grabbed.connect(_begin_native_interaction.bind(key, "grabbed"))
		spin.ungrabbed.connect(_finish_native_interaction.bind(key, "ungrabbed"))
		spin.value_focus_entered.connect(_begin_native_interaction.bind(key, "value_focus_entered"))
		spin.value_focus_exited.connect(_finish_native_interaction.bind(key, "value_focus_exited"))
	# EditorPropertyColor's own C++ implementation never reports live preview
	# through property_changed (ColorPicker.color_changed writes the edited
	# object directly, bypassing emit_changed), and its close handler writes
	# the pre-popup color back onto the edited object unconditionally before
	# conditionally emitting the final change -- so old_present read at that
	# point would already see a key that write just created. This row's own
	# lifecycle hooks below capture original/original_present at popup-open,
	# forward every live preview write to material sync, and finish once the
	# popup's own close signal (button.popup_closed) has actually run.
	var color_button: ColorPickerButton = _find_color_button(editor)
	if color_button != null:
		color_button.get_popup().about_to_popup.connect(_begin_native_interaction.bind(key, "color_popup"))
		color_button.color_changed.connect(_on_color_live_changed.bind(key))
		color_button.popup_closed.connect(_finish_color_popup.bind(key), CONNECT_DEFERRED)
		color_button.get_popup().window_input.connect(_on_color_popup_window_input.bind(color_button.get_popup()))


func _row_key(target: Object, property_name: StringName) -> String:
	return "%d:%s" % [target.get_instance_id(), String(property_name)]


## Native property_changed(property, value, field, changing) (phase 1
## evidence): an EditorSpinSlider-backed row's grabbed/ungrabbed/
## value_focus_entered/value_focus_exited pair (below) is the authoritative
## gesture boundary; a control with none of those (a native color popup)
## falls back to the changing flag itself, which for EditorPropertyColor
## already carries a real live-preview/final-commit boundary.
func _on_bound_property_changed(property: StringName, value: Variant, field: StringName, changing: bool, key: String) -> void:
	var entry: Variant = _property_rows.get(key)
	if entry == null:
		return
	var state: Dictionary = entry["state"]
	var target: Object = entry["target"]
	var property_name: StringName = entry["property"]
	if property != property_name:
		return
	var new_value: Variant = _merge_component_value(target.get(property_name), value, field)
	if bool(state["active"]):
		target.set(property_name, new_value)
		state["final"] = new_value
		(entry["editor"] as EditorProperty).update_property()
		# Live preview during an in-progress gesture (phase 2 review round 1
		# fix pass): syncs the material and contextual read-only hints for
		# every intermediate value without rebuilding this or any other row
		# and without registering a history action -- only the eventual
		# finish (below) does that.
		if _undo != null:
			_undo.notify_property_changed()
		_schedule_context_update()
		if not changing and String(state["boundary"]) == "changing":
			_finish_native_interaction(key, "changing_false")
		return
	if changing:
		_begin_native_interaction(key, "changing")
		target.set(property_name, new_value)
		state["final"] = new_value
		if _undo != null:
			_undo.notify_property_changed()
		_schedule_context_update()
		return
	var old_present: bool = _param_present(target, property_name)
	_commit_row(key, target.get(property_name), new_value, old_present)


func _merge_component_value(current: Variant, value: Variant, field: StringName) -> Variant:
	if current is Vector2 and field != &"":
		var vector: Vector2 = current as Vector2
		if field == &"x":
			vector.x = value.x if value is Vector2 else value
		elif field == &"y":
			vector.y = value.y if value is Vector2 else value
		return vector
	if current is Vector3 and field != &"":
		var vector3: Vector3 = current as Vector3
		if field == &"x":
			vector3.x = value.x if value is Vector3 else value
		elif field == &"y":
			vector3.y = value.y if value is Vector3 else value
		elif field == &"z":
			vector3.z = value.z if value is Vector3 else value
		return vector3
	return value


## First begin captures the exact pre-gesture value; a later begin during the
## same interaction retains it (decision superseding 20).
func _begin_native_interaction(key: String, boundary: String) -> void:
	var entry: Variant = _property_rows.get(key)
	if entry == null:
		return
	var state: Dictionary = entry["state"]
	if bool(state["active"]):
		return
	var target: Object = entry["target"]
	var property_name: StringName = entry["property"]
	state["original"] = target.get(property_name)
	state["original_present"] = _param_present(target, property_name)
	state["final"] = state["original"]
	state["active"] = true
	state["boundary"] = boundary


func _finish_native_interaction(key: String, _boundary: String) -> void:
	var entry: Variant = _property_rows.get(key)
	if entry == null:
		return
	var state: Dictionary = entry["state"]
	if not bool(state["active"]):
		return
	_commit_row(key, state["original"], state["final"], bool(state["original_present"]))


## A native color popup's own live preview (ColorPicker.color_changed,
## re-emitted by ColorPickerButton) writes the edited object directly,
## bypassing EditorProperty.property_changed entirely, so it never reaches
## _on_bound_property_changed. Forwards the resulting live value to material
## sync/context the same way an active numeric gesture's intermediate value
## does, without registering any history action.
func _on_color_live_changed(_color: Color, key: String) -> void:
	var entry: Variant = _property_rows.get(key)
	if entry == null:
		return
	var state: Dictionary = entry["state"]
	if not bool(state["active"]):
		return
	var target: Object = entry["target"]
	var property_name: StringName = entry["property"]
	state["final"] = target.get(property_name)
	if _undo != null:
		_undo.notify_property_changed()
	_schedule_context_update()


## Runs once button.popup_closed fires (connected CONNECT_DEFERRED, after
## EditorPropertyColor's own deferred close handler has already run its
## unconditional restore-to-pre-popup write and its conditional final
## property_changed emission), so state["final"] reflects whichever of those
## actually happened before this commits.
func _finish_color_popup(key: String) -> void:
	_finish_native_interaction(key, "popup_closed")


## Window.window_input fires on the popup's own Window before that Window's
## normal GUI input dispatch runs (Window::_window_input emits this signal,
## then calls push_input() itself, per scene/main/window.cpp) -- earlier than
## any Control inside it, including the hex ColorPicker's own LineEdit, could
## consume a Ctrl+Z as its own built-in text-undo. Consumes the event with
## set_input_as_handled() on the popup itself (a Window is a Viewport) before
## any await, per the phase 2 review round 3 fix pass, then emits
## color_popup_undo_redo_requested so gst_main_panel.gd can finish this
## pending color edit and run GoShade's own standalone-history undo/redo --
## the root viewport's own _input() never sees this event at all while the
## popup holds focus (embedded-subwindow forwarding, scene/main/viewport.cpp).
func _on_color_popup_window_input(event: InputEvent, popup: Window) -> void:
	if not event is InputEventKey:
		return
	var redo: bool
	if event.is_action_pressed(&"ui_redo"):
		redo = true
	elif event.is_action_pressed(&"ui_undo"):
		redo = false
	else:
		return
	popup.set_input_as_handled()
	color_popup_undo_redo_requested.emit(redo)


## True if target currently holds an explicit stored entry for property_name
## rather than an implicit manifest default (GSTLayer.has_param_value); a
## target with no such concept (GSTCoordBlock's real @export fields) is
## always present.
static func _param_present(target: Object, property_name: StringName) -> bool:
	if target.has_method(&"has_param_value"):
		return bool(target.call(&"has_param_value", property_name))
	return true


## Registers one mutation-first action only when final content differs
## (old_present-aware no-op guard below); resets gesture state so the next
## begin captures a fresh original value. Passes _refresh_row bound to this
## row's own stable key (never the row/editor Nodes themselves) as
## commit_property_change's on_replayed callback, so this row's own value
## refreshes on every later undo/redo of the action without any row ever
## being rebuilt.
##
## old_present is the presence of property_name's explicit params entry
## before this gesture began; a no-op finish (final value round-tripped back
## to old_value, by GSTUndo.values_equal's approximate comparison) restores
## the exact original content instead of leaving whatever a live intermediate
## write already applied: an explicit key present before restores old_value
## itself (values_equal is approximate, so the live-written value can differ
## from old_value in its low bits even though it reads as unchanged), and an
## absent key restores that exact absence (phase 2 review round 2 fix pass;
## round 1 only handled the absent case).
func _commit_row(key: String, old_value: Variant, new_value: Variant, old_present: bool) -> void:
	var entry: Variant = _property_rows.get(key)
	if entry == null:
		return
	var state: Dictionary = entry["state"]
	var target: Object = entry["target"]
	var property_name: StringName = entry["property"]
	state["active"] = false
	state["boundary"] = ""
	if GSTUndo.values_equal(old_value, new_value):
		if old_present:
			target.set(property_name, old_value)
		else:
			GSTUndo.restore_absent_param(target, property_name)
		state["final"] = target.get(property_name)
		state["original_present"] = _param_present(target, property_name)
		_refresh_row(key)
		return
	target.set(property_name, new_value)
	state["final"] = new_value
	state["original_present"] = true
	if _undo != null:
		_undo.commit_property_change(target, property_name, old_value, new_value, _refresh_row.bind(key), old_present)
	else:
		_refresh_row(key)


## Refreshes one row's displayed value and the shared context hints without
## rebuilding any row (decision superseding 20). Bound by key so a later
## rebuild (a structural edit, a layer switch) that has already freed this
## row safely no-ops here instead of touching a stale Node.
func _refresh_row(key: String) -> void:
	var entry: Variant = _property_rows.get(key)
	if entry == null:
		return
	var editor: EditorProperty = entry["editor"] as EditorProperty
	if editor != null and is_instance_valid(editor):
		editor.update_property()
	_schedule_context_update()


## These explanations depend on exact function inputs, not sampled pixels.
## Read-only state belongs to native widgets and never changes the resource.
## Triggered directly after building rows and after every finished edit
## (decision superseding 20's tree_entered relay, no longer needed now that
## rows are built synchronously by this file, not by an EditorInspectorPlugin
## parsing an embedded EditorInspector).
func _schedule_context_update() -> void:
	if is_inside_tree() and not get_tree().process_frame.is_connected(_update_control_context):
		get_tree().process_frame.connect(_update_control_context, CONNECT_ONE_SHOT)


func _update_control_context() -> void:
	if _layer == null:
		return
	if _layer.entry == "generative/fbm":
		var single_octave: bool = int(_layer.get(&"octaves")) == 1
		_set_control_context(find_editor_property(&"gain", _layer), "Fine detail strength needs at least 2 Detail layers." if single_octave else "", single_octave)
	if _layer.entry == "fieldops/smoothstep":
		var clamped: bool = float(_layer.get(&"edge1")) <= float(_layer.get(&"edge0"))
		_set_control_context(find_editor_property(&"edge1", _layer), "Upper edge is at or below Lower edge. The shader uses a sharp threshold at Lower edge." if clamped else "")
		_set_control_context(find_editor_property(&"edge0", _layer), "This threshold controls transparency. Input values at or below Lower edge disappear." if _threshold_controls_alpha() else "")
	if _layer.coord == null:
		return
	var coord: GSTCoordBlock = _layer.coord
	var no_warp: bool = coord.warp_x == &"" and coord.warp_y == &""
	var x_axis_only: bool = _layer.entry in ["generative/linear_gradient", "generative/stripes"]
	var inactive_warp: bool = no_warp or (x_axis_only and coord.warp_x == &"")
	var warp_hint: String = ""
	if inactive_warp:
		warp_hint = "Connect Horizontal distortion to use Distortion strength with this function." if x_axis_only else "Connect Horizontal distortion or Vertical distortion to use Distortion strength."
	_set_control_context(find_coord_editor_property(&"warp_strength"), warp_hint, inactive_warp)
	_set_control_context(find_coord_editor_property(&"offset"), "This function uses X Position. Y Position has no effect." if x_axis_only else "")
	_set_control_context(find_coord_editor_property(&"scroll"), "This function uses X Movement speed. Y Movement speed and Vertical distortion have no effect." if x_axis_only else "")
	var radial_function: bool = _layer.entry in ["sdf/circle", "sdf/ring", "generative/radial_gradient"]
	var rotation_invariant: bool = radial_function and coord.offset == Vector2.ZERO and coord.scroll == Vector2.ZERO and no_warp
	_set_control_context(find_coord_editor_property(&"rotation"), "Rotation has no effect on this function while Position and Movement speed are zero and distortion is disconnected." if rotation_invariant else "")


func _threshold_controls_alpha() -> bool:
	if _stack.output_alpha == _layer.id:
		return true
	var alpha: GSTLayer = GSTStackOps.find_layer(_stack, _stack.output_alpha)
	return alpha != null and alpha.entry == "fieldops/multiply" and _layer.id in alpha.slots.values()


func _set_control_context(property: EditorProperty, text: String, inactive: bool = false) -> void:
	if property == null:
		return
	property.set_read_only(inactive)
	var label: Label = property.get_meta(&"gst_context_label", null) as Label
	if label != null:
		label.text = text
		label.visible = not text.is_empty()


func _schedule_rows_layout_update(box: VBoxContainer) -> void:
	var callback: Callable = _update_rows_layout.bind(box)
	if not get_tree().process_frame.is_connected(callback):
		get_tree().process_frame.connect(callback, CONNECT_ONE_SHOT)


func _update_rows_layout(box: VBoxContainer) -> void:
	var scale: float = EditorInterface.get_editor_scale()
	var box_minimum: float = 0.0
	for node: Node in box.find_children("*", "EditorProperty", true, false):
		var property: EditorProperty = node as EditorProperty
		var font: Font = property.get_theme_font(&"font", &"Tree")
		var font_size: int = property.get_theme_font_size(&"font_size", &"Tree")
		var label_width: float = font.get_string_size(property.get_label(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var split_ratio: float = maxf(0.05, property.get_name_split_ratio())
		var editor_padding: float = 4.0 * scale
		var font_offset: float = maxf(0.0, float(property.get_theme_constant(&"font_offset")))
		var reload_icon: Texture2D = property.get_theme_icon(&"ReloadSmall", &"EditorIcons")
		var base_spacing: float = float(EditorInterface.get_editor_settings().get_setting(&"interface/theme/base_spacing"))
		var half_padding: float = floorf(floorf(base_spacing * scale) / 2.0)
		var reload_allowance: float = reload_icon.get_width() + half_padding + float(property.get_theme_constant(&"h_separation", &"Tree"))
		var padded_label_width: float = label_width + font_offset + reload_allowance
		var child_minimum: float = property.get_combined_minimum_size().x
		box_minimum = maxf(box_minimum, maxf(
			(padded_label_width + editor_padding) / split_ratio,
			padded_label_width + editor_padding + child_minimum,
		))
	box.set_meta(&"gst_measured_minimum_width", ceilf(box_minimum))
	var content_width: float = maxf(float(_parameter_rows_box.get_meta(&"gst_measured_minimum_width", 0.0)), float(_coord_rows_box.get_meta(&"gst_measured_minimum_width", 0.0)))
	var scrollbar_width: float = _scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var scroll_panel_width: float = _scroll.get_theme_stylebox(&"panel").get_minimum_size().x
	custom_minimum_size.x = content_width + scrollbar_width + scroll_panel_width


func _rebuild_slots() -> void:
	_input_buttons.clear()
	_warp_buttons.clear()
	for box: VBoxContainer in [_inputs_box, _warp_box]:
		for child: Node in box.get_children():
			child.queue_free()
	if _layer == null:
		return
	var entry: GSTManifestEntry = _library.get_entry(_layer.entry)
	if entry == null:
		return
	for input: Dictionary in entry.inputs:
		_add_slot_row(input)
	if _layer.coord != null:
		_add_warp_row("x", _layer.coord.warp_x)
		_add_warp_row("y", _layer.coord.warp_y)


func _add_slot_row(input: Dictionary) -> void:
	var slot_name: String = String(input["name"])
	var slot_kind: GSTLayer.Kind = input["kind"] as GSTLayer.Kind
	var display_label: String = String(input.get("label", slot_name.capitalize()))
	var description: String = String(input.get("description", ""))
	var captured_layer_id: StringName = _layer.id
	var current: StringName = _layer.slots.get(slot_name, &"")
	var row: VBoxContainer = VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label: Label = Label.new()
	label.text = display_label
	label.tooltip_text = description
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var button: Button = Button.new()
	button.text = _reference_text(current)
	button.tooltip_text = description
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = _mutations_blocked
	button.pressed.connect(_on_input_pressed.bind(captured_layer_id, slot_name, button))
	row.add_child(button)
	_input_buttons[slot_name] = button
	var conversion: Label = _build_conversion_label(current, slot_kind)
	row.add_child(conversion)
	var refusal: Label = _build_refusal_label(captured_layer_id, slot_name, "input")
	row.add_child(refusal)
	_inputs_box.add_child(row)


func _add_warp_row(axis: String, current: StringName) -> void:
	var property_name: StringName = &"warp_x" if axis == "x" else &"warp_y"
	var metadata: Dictionary = GSTCoordBlock.get_editor_metadata(property_name)
	var captured_layer_id: StringName = _layer.id
	var row: VBoxContainer = VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label: Label = Label.new()
	label.text = String(metadata["label"])
	label.tooltip_text = String(metadata["description"])
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var button: Button = Button.new()
	button.text = _reference_text(current)
	button.tooltip_text = String(metadata["description"])
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = _mutations_blocked
	button.pressed.connect(_on_warp_pressed.bind(captured_layer_id, axis, button))
	row.add_child(button)
	_warp_buttons[axis] = button
	row.add_child(_build_conversion_label(current, GSTLayer.Kind.FIELD))
	row.add_child(_build_refusal_label(captured_layer_id, axis, "warp"))
	_warp_box.add_child(row)


func _on_input_pressed(layer_id: StringName, slot_name: String, button: Button) -> void:
	if _mutations_blocked:
		return
	chooser_requested.emit("input", layer_id, slot_name, button)


func _on_warp_pressed(layer_id: StringName, axis: String, button: Button) -> void:
	if _mutations_blocked:
		return
	chooser_requested.emit("warp", layer_id, axis, button)


func get_slot_picker() -> GSTPicker:
	return _slot_picker


func set_shared_picker(picker: GSTPicker) -> void:
	_slot_picker = picker


func set_mutations_blocked(blocked: bool) -> void:
	_mutations_blocked = blocked
	for button: Variant in _input_buttons.values():
		(button as Button).disabled = blocked
	for button: Variant in _warp_buttons.values():
		(button as Button).disabled = blocked


func get_input_button(slot_name: String) -> Button:
	return _input_buttons.get(slot_name) as Button


func get_warp_button(axis: String) -> Button:
	return _warp_buttons.get(axis) as Button


func set_refusal(layer_id: StringName, slot_name: String, purpose: String, reason: String) -> void:
	var key: String = _refusal_key(layer_id, slot_name, purpose)
	if reason.is_empty():
		_refusals.erase(key)
	else:
		_refusals[key] = {
			"layer_id": layer_id,
			"slot_name": slot_name,
			"purpose": purpose,
			"reason": reason,
		}
	if _layer != null and _layer.id == layer_id:
		_rebuild_slots()


func clear_refusals() -> void:
	_refusals.clear()
	if _inputs_box != null and _warp_box != null:
		_rebuild_slots()


func _prune_refusals() -> void:
	if _stack == null:
		_refusals.clear()
		return
	for key: Variant in _refusals.keys():
		var refusal: Dictionary = _refusals[key]
		if GSTStackOps.find_layer(_stack, refusal["layer_id"] as StringName) == null:
			_refusals.erase(key)


func _refusal_key(layer_id: StringName, slot_name: String, purpose: String) -> String:
	return "%s\n%s\n%s" % [String(layer_id), purpose, slot_name]


func _build_refusal_label(layer_id: StringName, slot_name: String, purpose: String) -> Label:
	var label: Label = Label.new()
	var refusal: Dictionary = _refusals.get(_refusal_key(layer_id, slot_name, purpose), {})
	label.text = String(refusal.get("reason", ""))
	label.visible = not label.text.is_empty()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _build_conversion_label(reference_id: StringName, target_kind: GSTLayer.Kind) -> Label:
	var label: Label = Label.new()
	var source: GSTLayer = GSTStackOps.find_layer(_stack, reference_id) if reference_id != &"" else null
	if source != null and source.kind_out != target_kind:
		label.text = "field -> color: grayscale" if source.kind_out == GSTLayer.Kind.FIELD else "color -> field: luminance"
	label.visible = not label.text.is_empty()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _reference_text(reference_id: StringName) -> String:
	if reference_id == &"":
		return "(none)"
	var reference: GSTLayer = GSTStackOps.find_layer(_stack, reference_id)
	if reference == null:
		return "Unavailable layer"
	var entry: GSTManifestEntry = _library.get_entry(reference.entry)
	var function_name: String = entry.function if entry != null else reference.entry
	return "l%s %s" % [String(reference.id), function_name]


## The layer this column currently edits, so callers can confirm it still
## points at a specific GSTLayer instance after an undo restores that layer
## (phase 4 fix pass 3, item 2). Every row is always freshly bound to this
## same instance (or its .coord) on each edit(), so this is authoritative.
## Wired-by: none (editor smoke seam)
func get_edited_object() -> Object:
	return _layer


## Wired-by: gst_editor_ui_labels_smoke.gd and ui_layout smoke.
func get_parameter_inspector() -> VBoxContainer:
	return _parameter_rows_box


## Wired-by: gst_editor_ui_labels_smoke.gd and ui_layout smoke.
func get_coord_inspector() -> VBoxContainer:
	return _coord_rows_box


## Wired-by: gst_editor_ui_layout_smoke.gd.
func get_settings_scroll() -> ScrollContainer:
	return _scroll


## Returns the native parameter widget so editor smoke can drive its own
## emit_changed() path and inspect the displayed value.
## Wired-by: none (editor smoke seam)
func find_editor_property(property_name: StringName, edited_object: Object) -> EditorProperty:
	return find_editor_property_in(_parameter_rows_box, property_name, edited_object)


## Wired-by: gst_editor_ui_labels_smoke.gd.
func find_coord_editor_property(property_name: StringName) -> EditorProperty:
	if _layer == null or _layer.coord == null:
		return null
	return find_editor_property_in(_coord_rows_box, property_name, _layer.coord)


## Static so editor smoke can inspect any native EditorInspector tree.
## Wired-by: none (editor smoke seam)
static func find_editor_property_in(root: Node, property_name: StringName, edited_object: Object) -> EditorProperty:
	if root is EditorProperty:
		var prop: EditorProperty = root as EditorProperty
		if prop.get_edited_property() == property_name and prop.get_edited_object() == edited_object:
			return prop
	for child: Node in root.get_children():
		var found: EditorProperty = find_editor_property_in(child, property_name, edited_object)
		if found != null:
			return found
	return null
