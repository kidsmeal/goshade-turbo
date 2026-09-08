@tool
class_name GSTInspectorColumn
extends VBoxContainer

## Middle column (decision 13): an EditorInspector created in code, pointed
## at the selected GSTLayer, so the layer's dynamic params (gst_layer.gd
## _get_property_list) show as sliders. Below it, one OptionButton row per
## manifest input (a plain row, not a dynamic property) listing the earlier
## layers whose kind fits or converts, plus two warp rows for a generator's
## coord block. Every slot change routes through GSTUndo.

signal edit_refused(reason: String)
## Real EditorInspector-driven param edit (a slider or a GSTCoordBlock
## field), relayed so GSTMainPanel can resync the preview material.
## Decision 20 excludes these from GSTUndo entirely, so this signal is the
## only path a live inspector edit reaches the panel.
signal param_edited(property: String)

const PICKER_SCENE: PackedScene = preload("res://addons/goshade_turbo/ui/gst_picker.tscn")

var _inspector: EditorInspector = null
var _slots_box: VBoxContainer = null
var _slot_picker: GSTPicker = null

var _stack: GSTStack = null
var _library: GSTLibrary = null
var _undo: GSTUndo = null
var _layer: GSTLayer = null
## Guards row rebuilds from re-triggering the undo call while populating.
var _syncing: bool = false
## Slot the open _slot_picker's next entry_picked should wire.
var _pending_slot_name: String = ""


func _ready() -> void:
	_inspector = EditorInspector.new()
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector.property_edited.connect(_on_property_edited)
	add_child(_inspector)
	_slots_box = VBoxContainer.new()
	add_child(_slots_box)
	_slot_picker = PICKER_SCENE.instantiate()
	add_child(_slot_picker)
	_slot_picker.entry_picked.connect(_on_slot_entry_picked)


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
	_inspector.edit(_layer)
	if _layer != null and _layer.coord != null:
		_layer.coord.changed.connect(_on_coord_changed)
	_rebuild_slots()


## GSTCoordBlock carries no dynamic property list (unlike GSTLayer's manifest
## params via _get_property_list), so its fields show inside the
## EditorInspector as an inline sub-resource panel; editing one there sets
## the value on the GSTCoordBlock object itself, not on the GSTLayer this
## column's _inspector.edit() points at. The engine's own inspector code
## calls Resource.emit_changed() on the object it just wrote a property onto
## for exactly this case, so GSTCoordBlock.changed is the real relay for a
## coord-block edit, parallel to _on_property_edited below for a top-level
## GSTLayer param.
func _on_coord_changed() -> void:
	param_edited.emit("coord")


func _on_property_edited(property: String) -> void:
	param_edited.emit(property)


func _rebuild_slots() -> void:
	for child: Node in _slots_box.get_children():
		child.queue_free()
	if _layer == null:
		return
	var entry: GSTManifestEntry = _library.get_entry(_layer.entry)
	if entry == null:
		return
	var layer_idx: int = GSTStackOps.find_index(_stack, _layer.id)
	for input: Dictionary in entry.inputs:
		_add_slot_row(String(input["name"]), input["kind"] as GSTLayer.Kind, entry.samples_source, layer_idx)
	if _layer.coord != null:
		_add_warp_row("x", _layer.coord.warp_x, layer_idx)
		_add_warp_row("y", _layer.coord.warp_y, layer_idx)


func _add_slot_row(slot_name: String, slot_kind: GSTLayer.Kind, samples_source: bool, layer_idx: int) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = slot_name
	row.add_child(label)
	var option: OptionButton = OptionButton.new()
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
	row.add_child(option)
	var add_button: Button = Button.new()
	add_button.text = "+"
	add_button.tooltip_text = "Add a new layer for slot %s" % slot_name
	add_button.pressed.connect(_on_add_for_slot_pressed.bind(slot_name, slot_kind))
	row.add_child(add_button)
	_slots_box.add_child(row)


func _add_warp_row(axis: String, current: StringName, layer_idx: int) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = "warp_%s" % axis
	row.add_child(label)
	var option: OptionButton = OptionButton.new()
	option.add_item("(none)")
	option.set_item_metadata(0, &"")
	var select_idx: int = 0
	for i: int in range(layer_idx):
		var candidate: GSTLayer = _stack.layers[i]
		if candidate.kind_out != GSTLayer.Kind.FIELD:
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
	option.item_selected.connect(_on_warp_selected.bind(axis, option))
	row.add_child(option)
	_slots_box.add_child(row)


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


## The object the underlying EditorInspector currently edits, so callers can
## confirm it still points at a specific GSTLayer instance after an undo
## restores that layer (phase 4 fix pass 3, item 2).
## Wired-by: none (editor smoke seam)
func get_edited_object() -> Object:
	return _inspector.get_edited_object()


## The real EditorProperty widget currently showing property_name for
## edited_object, found by walking this column's own EditorInspector control
## tree. Lets a test drive the exact widget a real slider drag would, via
## the widget's own emit_changed(), rather than faking the param_edited
## relay by setting the value directly and emitting the signal by hand.
## Only finds a top-level GSTLayer param: a Resource-typed property like
## coord shows as a collapsed EditorPropertyResource row with no nested
## EditorProperty children built at all until a user expands it by hand
## (confirmed by walking this exact tree: coord's row holds only an
## EditorResourcePicker's own buttons, no sub-inspector) -- a test driving a
## GSTCoordBlock field for real uses find_editor_property_in() against its
## own throwaway EditorInspector pointed directly at the coord object
## instead (gst_editor_smoke.gd), which needs no expand step since the
## property is then top-level on that inspector.
## Wired-by: none (editor smoke seam)
func find_editor_property(property_name: StringName, edited_object: Object) -> EditorProperty:
	return find_editor_property_in(_inspector, property_name, edited_object)


## Static so a caller with its own EditorInspector instance can reuse this
## widget-finding logic (gst_editor_smoke.gd, for a GSTCoordBlock field --
## see find_editor_property's own comment above).
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
