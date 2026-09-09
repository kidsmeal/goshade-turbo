@tool
class_name GSTInspectorColumn
extends VBoxContainer

## Selected-layer controls. Manifest params and coordinates use separate
## native inspectors; input and distortion references route through GSTUndo.

signal edit_refused(reason: String)
signal chooser_requested(purpose: String, layer_id: StringName, slot_name: String, initiator: Control)
## Real EditorInspector-driven param edit (a slider or a GSTCoordBlock
## field), relayed so GSTMainPanel can resync the preview material.
## Decision 20 excludes these from GSTUndo entirely, so this signal is the
## only path a live inspector edit reaches the panel.
signal param_edited(property: String)
signal section_state_changed(states: Dictionary)

var _scroll: ScrollContainer = null
var _sections: VBoxContainer = null
var _parameter_inspector: EditorInspector = null
var _coord_inspector: EditorInspector = null
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
var _context_histories: Array[UndoRedo] = []


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
	_parameter_inspector = EditorInspector.new()
	_parameter_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parameter_inspector.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_parameter_inspector.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_parameter_inspector.property_edited.connect(_on_property_edited)
	(parameters["content"] as VBoxContainer).add_child(_parameter_inspector)

	var position: Dictionary = _build_section("position", "Position and movement")
	var position_content: VBoxContainer = position["content"] as VBoxContainer
	_coord_inspector = EditorInspector.new()
	_coord_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_coord_inspector.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_coord_inspector.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_coord_inspector.property_edited.connect(_on_property_edited)
	position_content.add_child(_coord_inspector)
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
## column (nothing selected).
func edit(layer_id: StringName) -> void:
	_unwatch_context_histories()
	if _layer != null and _layer.coord != null and _layer.coord.changed.is_connected(_on_coord_changed):
		_layer.coord.changed.disconnect(_on_coord_changed)
	_layer = GSTStackOps.find_layer(_stack, layer_id)
	_prune_refusals()
	if _layer != null:
		_layer.manifest = _library.get_entry(_layer.entry)
	_parameter_inspector.edit(_layer)
	_coord_inspector.edit(_layer.coord if _layer != null else null)
	_schedule_inspector_layout_update(_parameter_inspector)
	_schedule_inspector_layout_update(_coord_inspector)
	if _layer != null and _layer.coord != null:
		_layer.coord.changed.connect(_on_coord_changed)
	if _layer != null:
		_watch_context_history(_layer)
		if _layer.coord != null:
			_watch_context_history(_layer.coord)
	_rebuild_slots()
	_schedule_context_update()


## Resource.changed remains a secondary relay for coordinate changes outside
## the native EditorInspector.property_edited path.
func _on_coord_changed() -> void:
	_schedule_context_update()
	param_edited.emit("coord")


func _on_property_edited(property: String) -> void:
	_schedule_context_update()
	param_edited.emit(property)


func _exit_tree() -> void:
	_unwatch_context_histories()


func _watch_context_history(object: Object) -> void:
	var manager: EditorUndoRedoManager = EditorInterface.get_editor_undo_redo()
	var history: UndoRedo = manager.get_history_undo_redo(manager.get_object_history_id(object))
	if history != null and history not in _context_histories:
		_context_histories.append(history)
		history.version_changed.connect(_schedule_context_update)


func _unwatch_context_histories() -> void:
	for history: UndoRedo in _context_histories:
		if history.version_changed.is_connected(_schedule_context_update):
			history.version_changed.disconnect(_schedule_context_update)
	_context_histories.clear()


func _schedule_context_update() -> void:
	if is_inside_tree() and not get_tree().process_frame.is_connected(_update_control_context):
		get_tree().process_frame.connect(_update_control_context, CONNECT_ONE_SHOT)


## Wired-by: GSTInspectorPlugin when a contextual row enters the inspector.
func refresh_control_context() -> void:
	_schedule_context_update()


## These explanations depend on exact function inputs, not sampled pixels.
## Read-only state belongs to native widgets and never changes the resource.
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


func _schedule_inspector_layout_update(inspector: EditorInspector) -> void:
	var callback: Callable = _update_inspector_layout.bind(inspector)
	if not get_tree().process_frame.is_connected(callback):
		get_tree().process_frame.connect(callback, CONNECT_ONE_SHOT)


func _update_inspector_layout(inspector: EditorInspector) -> void:
	var scale: float = EditorInterface.get_editor_scale()
	var inspector_minimum: float = 0.0
	for node: Node in inspector.find_children("*", "EditorProperty", true, false):
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
		inspector_minimum = maxf(inspector_minimum, maxf(
			(padded_label_width + editor_padding) / split_ratio,
			padded_label_width + editor_padding + child_minimum,
		))
	inspector.set_meta(&"gst_measured_minimum_width", ceilf(inspector_minimum))
	var inspector_content_width: float = maxf(float(_parameter_inspector.get_meta(&"gst_measured_minimum_width", 0.0)), float(_coord_inspector.get_meta(&"gst_measured_minimum_width", 0.0)))
	var scrollbar_width: float = _scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var scroll_panel_width: float = _scroll.get_theme_stylebox(&"panel").get_minimum_size().x
	custom_minimum_size.x = inspector_content_width + scrollbar_width + scroll_panel_width


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


## External writes such as Randomize do not refresh built EditorProperty
## widgets. Re-edit both objects because EditorInspector has no refresh API.
## Wired-by: gst_main_panel.gd's _refresh_inspector (registered as a do/undo
## method on the randomize action, bracketing GSTRandomize.apply).
func refresh() -> void:
	if _layer == null:
		return
	_parameter_inspector.edit(null)
	_parameter_inspector.edit(_layer)
	_coord_inspector.edit(null)
	_coord_inspector.edit(_layer.coord)
	_schedule_inspector_layout_update(_parameter_inspector)
	_schedule_inspector_layout_update(_coord_inspector)
	_schedule_context_update()


## The object the underlying EditorInspector currently edits, so callers can
## confirm it still points at a specific GSTLayer instance after an undo
## restores that layer (phase 4 fix pass 3, item 2).
## Wired-by: none (editor smoke seam)
func get_edited_object() -> Object:
	return _parameter_inspector.get_edited_object()


## Wired-by: gst_editor_ui_labels_smoke.gd and ui_layout smoke.
func get_parameter_inspector() -> EditorInspector:
	return _parameter_inspector


## Wired-by: gst_editor_ui_labels_smoke.gd and ui_layout smoke.
func get_coord_inspector() -> EditorInspector:
	return _coord_inspector


## Wired-by: gst_editor_ui_layout_smoke.gd.
func get_settings_scroll() -> ScrollContainer:
	return _scroll


## Returns the native parameter widget so editor smoke can drive its own
## emit_changed() path and inspect the displayed value.
## Wired-by: none (editor smoke seam)
func find_editor_property(property_name: StringName, edited_object: Object) -> EditorProperty:
	return find_editor_property_in(_parameter_inspector, property_name, edited_object)


## Wired-by: gst_editor_ui_labels_smoke.gd.
func find_coord_editor_property(property_name: StringName) -> EditorProperty:
	if _layer == null or _layer.coord == null:
		return null
	return find_editor_property_in(_coord_inspector, property_name, _layer.coord)


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
