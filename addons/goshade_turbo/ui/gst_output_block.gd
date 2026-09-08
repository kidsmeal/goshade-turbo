@tool
class_name GSTOutputBlock
extends HBoxContainer

## Fixed output block at the panel bottom (decision 12). output_color:
## OptionButton over every layer (a field layer converts to grayscale).
## output_alpha: OptionButton over "none", "texture", "color_alpha", plus
## every field layer id. Changes route through GSTUndo.
##
## Row 0 of each OptionButton is a synthetic "default" row, metadata &"":
## for color it shows "(default) l<id> <function>" for the top (highest
## stack index) color layer, or "(none)" when no color layer exists; for
## alpha it shows "(default) texture" when a "source/texture" layer exists
## in the stack, else "(default) none". stack.output_color == &"" and
## stack.output_alpha == &"" mean "unset" and select the default row. An
## explicit pick of "none" is a real value (GSTStack defaults output_alpha
## to &"") and selects the "none" row, so the UI and codegen agree on
## decision 12. Selecting the default row writes &"" through GSTUndo like
## any other pick, so it is undoable, except when the field is already &""
## (docs/PLAN.md phase 4 fix pass 2, item 5): that no-op registers nothing.

@onready var _color_option: OptionButton = %ColorOption
@onready var _alpha_option: OptionButton = %AlphaOption

var _stack: GSTStack = null
var _library: GSTLibrary = null
var _undo: GSTUndo = null
## Guards refresh()'s own selection sync from re-triggering the undo call.
var _syncing: bool = false


func _ready() -> void:
	_color_option.item_selected.connect(_on_color_selected)
	_alpha_option.item_selected.connect(_on_alpha_selected)


func setup(stack: GSTStack, library: GSTLibrary, undo: GSTUndo) -> void:
	_stack = stack
	_library = library
	_undo = undo
	refresh()


func refresh() -> void:
	if _stack == null or _library == null:
		return
	_syncing = true
	_color_option.clear()
	_color_option.add_item(_default_color_text())
	_color_option.set_item_metadata(0, &"")
	var color_select_idx: int = 0
	for layer: GSTLayer in _stack.layers:
		var entry: GSTManifestEntry = _library.get_entry(layer.entry)
		var function_name: String = entry.function if entry != null else layer.entry
		_color_option.add_item("l%s %s" % [String(layer.id), function_name])
		var idx: int = _color_option.item_count - 1
		_color_option.set_item_metadata(idx, layer.id)
		if layer.id == _stack.output_color and _stack.output_color != &"":
			color_select_idx = idx
	_color_option.select(color_select_idx)

	_alpha_option.clear()
	_alpha_option.add_item(_default_alpha_text())
	_alpha_option.set_item_metadata(0, &"")
	var alpha_labels: Array[StringName] = [&"none", &"texture", &"color_alpha"]
	for label: StringName in alpha_labels:
		_alpha_option.add_item(String(label))
		_alpha_option.set_item_metadata(_alpha_option.item_count - 1, label)
	var alpha_is_default: bool = _stack.output_alpha == &""
	var alpha_select_idx: int = 0
	if not alpha_is_default:
		for i: int in range(alpha_labels.size()):
			if alpha_labels[i] == _stack.output_alpha:
				alpha_select_idx = i + 1
	for layer: GSTLayer in _stack.layers:
		if layer.kind_out != GSTLayer.Kind.FIELD:
			continue
		var entry: GSTManifestEntry = _library.get_entry(layer.entry)
		var function_name: String = entry.function if entry != null else layer.entry
		_alpha_option.add_item("l%s %s" % [String(layer.id), function_name])
		var idx: int = _alpha_option.item_count - 1
		_alpha_option.set_item_metadata(idx, layer.id)
		if layer.id == _stack.output_alpha and not alpha_is_default:
			alpha_select_idx = idx
	_alpha_option.select(alpha_select_idx)
	_syncing = false


func _top_color_layer() -> GSTLayer:
	for i: int in range(_stack.layers.size() - 1, -1, -1):
		var layer: GSTLayer = _stack.layers[i]
		if layer.kind_out == GSTLayer.Kind.COLOR:
			return layer
	return null


func _stack_has_texture_source() -> bool:
	for layer: GSTLayer in _stack.layers:
		if layer.entry == "source/texture":
			return true
	return false


func _default_color_text() -> String:
	var top_color: GSTLayer = _top_color_layer()
	if top_color == null:
		return "(none)"
	var entry: GSTManifestEntry = _library.get_entry(top_color.entry)
	var function_name: String = entry.function if entry != null else top_color.entry
	return "(default) l%s %s" % [String(top_color.id), function_name]


func _default_alpha_text() -> String:
	return "(default) texture" if _stack_has_texture_source() else "(default) none"


## Row 0 (metadata &"") is the synthetic default row: selecting it clears
## output_color to &"" through undo, unless it is already &"" (no-op,
## registers no undo action).
func _on_color_selected(index: int) -> void:
	if _syncing:
		return
	var target_id: StringName = _color_option.get_item_metadata(index) as StringName
	if target_id == &"":
		if _stack.output_color == &"":
			refresh()
			return
		_undo.set_output_color(&"")
		refresh()
		return
	_undo.set_output_color(target_id)
	refresh()


## Row 0 (metadata &"") is the synthetic default row: selecting it clears
## output_alpha to &"" through undo, unless it is already &"" (no-op,
## registers no undo action).
func _on_alpha_selected(index: int) -> void:
	if _syncing:
		return
	var target: StringName = _alpha_option.get_item_metadata(index) as StringName
	if target == &"":
		if _stack.output_alpha == &"":
			refresh()
			return
		_undo.set_output_alpha(&"")
		refresh()
		return
	_undo.set_output_alpha(target)
	refresh()


func get_selected_color_text() -> String:
	return _color_option.get_item_text(_color_option.selected)


func get_selected_alpha_text() -> String:
	return _alpha_option.get_item_text(_alpha_option.selected)
