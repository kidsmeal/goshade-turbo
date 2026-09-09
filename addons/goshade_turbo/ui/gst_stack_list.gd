@tool
class_name GSTStackList
extends VBoxContainer

## Ordered stack list (decision 13): rendered top-to-bottom as the stack
## renders, index layers.size()-1 at the top. Add/remove/reorder route
## through GSTUndo (decision 20), never mutate GSTStack directly. A refused
## reorder is reported via structural_edit_refused instead of performed.

signal layer_selected(layer_id: StringName)
signal structural_edit_refused(reason: String)

@onready var _list: ItemList = %List
@onready var _add_button: Button = %AddButton
@onready var _remove_button: Button = %RemoveButton
@onready var _up_button: Button = %UpButton
@onready var _down_button: Button = %DownButton
@onready var _picker: GSTPicker = %Picker

var _stack: GSTStack = null
var _library: GSTLibrary = null
var _undo: GSTUndo = null


func _ready() -> void:
	_add_button.pressed.connect(_on_add_pressed)
	_remove_button.pressed.connect(_on_remove_pressed)
	_up_button.pressed.connect(_on_up_pressed)
	_down_button.pressed.connect(_on_down_pressed)
	_list.item_selected.connect(_on_item_selected)
	_picker.entry_picked.connect(_on_entry_picked)


func setup(stack: GSTStack, library: GSTLibrary, undo: GSTUndo) -> void:
	_stack = stack
	_library = library
	_undo = undo
	refresh()


func get_selected_layer_id() -> StringName:
	var selected: PackedInt32Array = _list.get_selected_items()
	if selected.is_empty():
		return &""
	return _list.get_item_metadata(selected[0]) as StringName


## Rebuilds the list from the current stack, preserving the selected layer
## id across the rebuild when it still exists.
func refresh() -> void:
	if _stack == null or _library == null:
		return
	var selected_id: StringName = get_selected_layer_id()
	var anchor_id: StringName = get_scroll_anchor_id()
	var anchor_offset: float = _scroll_anchor_offset()
	_list.clear()
	for i: int in range(_stack.layers.size() - 1, -1, -1):
		var layer: GSTLayer = _stack.layers[i]
		var entry: GSTManifestEntry = _library.get_entry(layer.entry)
		var kind_label: String = "field" if layer.kind_out == GSTLayer.Kind.FIELD else "color"
		var function_name: String = entry.function if entry != null else layer.entry
		_list.add_item("l%s  %s (%s)" % [String(layer.id), function_name, kind_label])
		_list.set_item_metadata(_list.item_count - 1, layer.id)
	_select_layer_silently(selected_id)
	if anchor_id != &"":
		_restore_scroll_anchor.call_deferred(anchor_id, anchor_offset)


func select_layer(layer_id: StringName) -> void:
	_select_layer_silently(layer_id)
	layer_selected.emit(layer_id)


func _select_layer_silently(layer_id: StringName) -> void:
	if layer_id == &"":
		return
	for i: int in range(_list.item_count):
		if _list.get_item_metadata(i) == layer_id:
			_list.select(i)
			return


func _on_item_selected(index: int) -> void:
	layer_selected.emit(_list.get_item_metadata(index) as StringName)


func get_picker() -> GSTPicker:
	return _picker


func get_item_count() -> int:
	return _list.item_count


## Wired-by: tests/gst_editor_ui_layout_smoke.gd.
func get_item_id(index: int) -> StringName:
	if index < 0 or index >= _list.item_count:
		return &""
	return _list.get_item_metadata(index) as StringName


## Wired-by: refresh() and tests/gst_editor_ui_layout_smoke.gd.
func get_scroll_anchor_id() -> StringName:
	if _list.item_count == 0:
		return &""
	var row_height: float = _row_height()
	var index: int = clampi(int(floor(_list.get_v_scroll_bar().value / row_height)), 0, _list.item_count - 1)
	return get_item_id(index)


func _scroll_anchor_offset() -> float:
	if _list.item_count == 0:
		return 0.0
	var row_height: float = _row_height()
	return fmod(_list.get_v_scroll_bar().value, row_height)


func _restore_scroll_anchor(layer_id: StringName, offset: float) -> void:
	var index: int = _item_index_for_id(layer_id)
	if index == -1:
		return
	_list.get_v_scroll_bar().value = float(index) * _row_height() + offset


func _item_index_for_id(layer_id: StringName) -> int:
	for i: int in range(_list.item_count):
		if get_item_id(i) == layer_id:
			return i
	return -1


func _row_height() -> float:
	if _list.item_count == 0:
		return 1.0
	return maxf(1.0, _list.get_item_rect(0).size.y)


## Wired-by: tests/gst_editor_ui_layout_smoke.gd.
func scroll_to_fraction(fraction: float) -> void:
	var bar: VScrollBar = _list.get_v_scroll_bar()
	bar.value = lerpf(bar.min_value, bar.max_value, clampf(fraction, 0.0, 1.0))


## Wired-by: tests/gst_editor_ui_layout_smoke.gd.
func has_fixed_row_heights() -> bool:
	if _list.item_count < 2:
		return true
	var expected: float = _list.get_item_rect(0).size.y
	for i: int in range(1, _list.item_count):
		if not is_equal_approx(_list.get_item_rect(i).size.y, expected):
			return false
	return true


func _on_add_pressed() -> void:
	_picker.open_for_add(_library)


func _on_entry_picked(entry_id: String) -> void:
	add_layer_by_entry_id(entry_id)


## Adds a layer of entry_id through GSTUndo, the same call the Add button's
## picker callback makes. Public so tests/gst_editor_smoke.gd can drive the
## panel through the same code path the button uses (docs/PLAN.md Phase 4
## Files, gst_editor_smoke.gd).
func add_layer_by_entry_id(entry_id: String) -> GSTLayer:
	var entry: GSTManifestEntry = _library.get_entry(entry_id)
	if entry == null:
		return null
	var result: Dictionary = _undo.add_layer_for_ui(entry_id)
	if not result["ok"]:
		structural_edit_refused.emit(result["reason"])
		return null
	var layer: GSTLayer = result["layer"]
	refresh()
	select_layer(layer.id)
	return layer


func _on_remove_pressed() -> void:
	var layer_id: StringName = get_selected_layer_id()
	if layer_id == &"":
		return
	_undo.remove_layer(layer_id)
	refresh()


func _on_up_pressed() -> void:
	_move_selected(1)


func _on_down_pressed() -> void:
	_move_selected(-1)


func _move_selected(delta: int) -> void:
	var layer_id: StringName = get_selected_layer_id()
	if layer_id == &"":
		return
	var idx: int = GSTStackOps.find_index(_stack, layer_id)
	if idx == -1:
		return
	var result: Dictionary = _undo.reorder_layer(layer_id, idx + delta)
	if not result["ok"]:
		structural_edit_refused.emit(result["reason"])
		return
	refresh()
	select_layer(layer_id)
