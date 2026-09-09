@tool
class_name GSTInspectorColumn
extends VBoxContainer

## Selected-layer controls. Manifest params and coordinates use separate
## native inspectors; input and distortion references route through GSTUndo.

signal edit_refused(reason: String)
## Real EditorInspector-driven param edit (a slider or a GSTCoordBlock
## field), relayed so GSTMainPanel can resync the preview material.
## Decision 20 excludes these from GSTUndo entirely, so this signal is the
## only path a live inspector edit reaches the panel.
signal param_edited(property: String)
signal section_state_changed(states: Dictionary)

const PICKER_SCENE: PackedScene = preload("res://addons/goshade_turbo/ui/gst_picker.tscn")

var _scroll: ScrollContainer = null
var _sections: VBoxContainer = null
var _parameter_inspector: EditorInspector = null
var _coord_inspector: EditorInspector = null
var _inputs_box: VBoxContainer = null
var _warp_box: VBoxContainer = null
var _slot_picker: GSTPicker = null
var _section_buttons: Dictionary = {}
var _section_contents: Dictionary = {}

var _stack: GSTStack = null
var _library: GSTLibrary = null
var _undo: GSTUndo = null
var _layer: GSTLayer = null
## Guards row rebuilds from re-triggering the undo call while populating.
var _syncing: bool = false
## Slot the open _slot_picker's next entry_picked should wire.
var _pending_slot_name: String = ""


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
	position_content.add_child(_coord_inspector)
	_warp_box = VBoxContainer.new()
	_warp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	position_content.add_child(_warp_box)
	_slot_picker = PICKER_SCENE.instantiate()
	add_child(_slot_picker)
	_slot_picker.entry_picked.connect(_on_slot_entry_picked)


func _build_section(key: String, title: String) -> Dictionary:
	var section: VBoxContainer = VBoxContainer.new()
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


## Points the inspector at layer_id's GSTLayer. An empty id clears the
## column (nothing selected).
func edit(layer_id: StringName) -> void:
	if _layer != null and _layer.coord != null and _layer.coord.changed.is_connected(_on_coord_changed):
		_layer.coord.changed.disconnect(_on_coord_changed)
	_layer = GSTStackOps.find_layer(_stack, layer_id)
	if _layer != null:
		_layer.manifest = _library.get_entry(_layer.entry)
	_parameter_inspector.edit(_layer)
	_coord_inspector.edit(_layer.coord if _layer != null else null)
	_schedule_inspector_layout_update(_parameter_inspector)
	_schedule_inspector_layout_update(_coord_inspector)
	if _layer != null and _layer.coord != null:
		_layer.coord.changed.connect(_on_coord_changed)
	_rebuild_slots()


## The engine emits Resource.changed on the GSTCoordBlock object its native
## editor wrote, so coordinate edits use this relay independently of the
## parameter inspector's property_edited signal.
func _on_coord_changed() -> void:
	param_edited.emit("coord")


func _on_property_edited(property: String) -> void:
	param_edited.emit(property)


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
		var padding: float = float(property.get_theme_constant(&"h_separation", &"Tree")) + 8.0 * scale
		var child_minimum: float = property.get_combined_minimum_size().x
		inspector_minimum = maxf(inspector_minimum, maxf(label_width / split_ratio, label_width + child_minimum + padding))
	inspector.set_meta(&"gst_measured_minimum_width", ceilf(inspector_minimum))
	custom_minimum_size.x = maxf(float(_parameter_inspector.get_meta(&"gst_measured_minimum_width", 0.0)), float(_coord_inspector.get_meta(&"gst_measured_minimum_width", 0.0)))


func _rebuild_slots() -> void:
	for box: VBoxContainer in [_inputs_box, _warp_box]:
		for child: Node in box.get_children():
			child.queue_free()
	if _layer == null:
		return
	var entry: GSTManifestEntry = _library.get_entry(_layer.entry)
	if entry == null:
		return
	var layer_idx: int = GSTStackOps.find_index(_stack, _layer.id)
	for input: Dictionary in entry.inputs:
		_add_slot_row(input, entry.samples_source, layer_idx)
	if _layer.coord != null:
		_add_warp_row("x", _layer.coord.warp_x, layer_idx)
		_add_warp_row("y", _layer.coord.warp_y, layer_idx)


func _add_slot_row(input: Dictionary, samples_source: bool, layer_idx: int) -> void:
	var slot_name: String = String(input["name"])
	var slot_kind: GSTLayer.Kind = input["kind"] as GSTLayer.Kind
	var display_label: String = String(input.get("label", slot_name.capitalize()))
	var description: String = String(input.get("description", ""))
	var row: VBoxContainer = VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label: Label = Label.new()
	label.text = display_label
	label.tooltip_text = description
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var choice_row: HBoxContainer = HBoxContainer.new()
	choice_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(choice_row)
	var option: OptionButton = OptionButton.new()
	option.tooltip_text = description
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.fit_to_longest_item = false
	option.clip_text = true
	option.add_item("(none)")
	option.set_item_metadata(0, &"")
	var select_idx: int = 0
	var current: StringName = _layer.slots.get(slot_name, &"")
	for i: int in range(layer_idx):
		var candidate: GSTLayer = _stack.layers[i]
		if samples_source and candidate.entry != "source/texture" and candidate.entry != "source/screen":
			continue
		var candidate_entry: GSTManifestEntry = _library.get_entry(candidate.entry)
		var function_name: String = candidate_entry.function if candidate_entry != null else candidate.entry
		option.add_item("l%s %s" % [String(candidate.id), function_name])
		var idx: int = option.item_count - 1
		option.set_item_metadata(idx, candidate.id)
		if candidate.id == current:
			select_idx = idx
	_syncing = true
	option.select(select_idx)
	_syncing = false
	option.item_selected.connect(_on_slot_selected.bind(slot_name, option))
	choice_row.add_child(option)
	var add_button: Button = Button.new()
	add_button.text = "+"
	add_button.tooltip_text = "Add a new layer for slot %s" % slot_name
	add_button.pressed.connect(_on_add_for_slot_pressed.bind(slot_name, slot_kind))
	choice_row.add_child(add_button)
	_inputs_box.add_child(row)


func _add_warp_row(axis: String, current: StringName, layer_idx: int) -> void:
	var property_name: StringName = &"warp_x" if axis == "x" else &"warp_y"
	var metadata: Dictionary = GSTCoordBlock.get_editor_metadata(property_name)
	var row: VBoxContainer = VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label: Label = Label.new()
	label.text = String(metadata["label"])
	label.tooltip_text = String(metadata["description"])
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option: OptionButton = OptionButton.new()
	option.tooltip_text = String(metadata["description"])
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.fit_to_longest_item = false
	option.clip_text = true
	option.add_item("(none)")
	option.set_item_metadata(0, &"")
	var select_idx: int = 0
	for i: int in range(layer_idx):
		var candidate: GSTLayer = _stack.layers[i]
		var candidate_entry: GSTManifestEntry = _library.get_entry(candidate.entry)
		var function_name: String = candidate_entry.function if candidate_entry != null else candidate.entry
		option.add_item("l%s %s" % [String(candidate.id), function_name])
		var idx: int = option.item_count - 1
		option.set_item_metadata(idx, candidate.id)
		if candidate.id == current:
			select_idx = idx
	_syncing = true
	option.select(select_idx)
	_syncing = false
	option.item_selected.connect(_on_warp_selected.bind(axis, option))
	row.add_child(option)
	_warp_box.add_child(row)


func _on_slot_selected(index: int, slot_name: String, option: OptionButton) -> void:
	if _syncing:
		return
	var target_id: StringName = option.get_item_metadata(index) as StringName
	var result: Dictionary = _undo.assign_slot(_layer.id, slot_name, target_id)
	if not result["ok"]:
		edit_refused.emit(result["reason"])
	_rebuild_slots()


func _on_warp_selected(index: int, axis: String, option: OptionButton) -> void:
	if _syncing:
		return
	var target_id: StringName = option.get_item_metadata(index) as StringName
	var result: Dictionary = _undo.assign_warp(_layer.id, axis, target_id)
	if not result["ok"]:
		edit_refused.emit(result["reason"])
	_rebuild_slots()


func _on_add_for_slot_pressed(slot_name: String, slot_kind: GSTLayer.Kind) -> void:
	if _layer == null:
		return
	_pending_slot_name = slot_name
	_slot_picker.open_for_slot(_library, slot_kind)


func _on_slot_entry_picked(entry_id: String) -> void:
	if _layer == null or _pending_slot_name.is_empty():
		return
	var slot_name: String = _pending_slot_name
	_pending_slot_name = ""
	var result: Dictionary = _undo.add_layer_below_and_wire(_layer.id, entry_id, slot_name)
	if not result["ok"]:
		edit_refused.emit(result["reason"])


func get_slot_picker() -> GSTPicker:
	return _slot_picker


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
