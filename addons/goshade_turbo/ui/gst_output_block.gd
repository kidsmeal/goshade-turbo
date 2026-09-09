@tool
class_name GSTOutputBlock
extends VBoxContainer

## Fixed output controls below the preview. Buttons open the shared chooser;
## the main panel owns validation, mutation, undo, and chooser lifetime.

signal chooser_requested(purpose: String, layer_id: StringName, slot_name: String, initiator: Control)

@onready var _color_button: Button = %ColorButton
@onready var _alpha_button: Button = %AlphaButton
@onready var _color_conversion: Label = %ColorConversion
@onready var _color_refusal: Label = %ColorRefusal
@onready var _alpha_refusal: Label = %AlphaRefusal

var _stack: GSTStack = null
var _library: GSTLibrary = null
var _undo: GSTUndo = null
var _picker: GSTPicker = null
var _mutations_blocked: bool = false
var _refusals: Dictionary = {}


func _ready() -> void:
	_color_button.pressed.connect(_on_color_pressed)
	_alpha_button.pressed.connect(_on_alpha_pressed)


func setup(stack: GSTStack, library: GSTLibrary, undo: GSTUndo) -> void:
	_stack = stack
	_library = library
	_undo = undo
	clear_refusals()
	refresh()


func set_shared_picker(picker: GSTPicker) -> void:
	_picker = picker


func get_picker() -> GSTPicker:
	return _picker


func set_mutations_blocked(blocked: bool) -> void:
	_mutations_blocked = blocked
	_color_button.disabled = blocked
	_alpha_button.disabled = blocked


func set_refusal(purpose: String, reason: String) -> void:
	if reason.is_empty():
		_refusals.erase(purpose)
	else:
		_refusals[purpose] = reason
	_update_refusal_labels()


func clear_refusals() -> void:
	_refusals.clear()
	_update_refusal_labels()


func _update_refusal_labels() -> void:
	if _color_refusal == null or _alpha_refusal == null:
		return
	_color_refusal.text = String(_refusals.get("output_color", ""))
	_color_refusal.visible = not _color_refusal.text.is_empty()
	_alpha_refusal.text = String(_refusals.get("output_alpha", ""))
	_alpha_refusal.visible = not _alpha_refusal.text.is_empty()


func refresh() -> void:
	if _stack == null or _library == null:
		return
	_color_button.text = _selected_color_text()
	_color_conversion.text = _selected_color_conversion()
	_color_conversion.visible = not _color_conversion.text.is_empty()
	_alpha_button.text = _selected_alpha_text()


func _selected_color_text() -> String:
	if _stack.output_color == &"":
		return _automatic_color_text()
	var layer: GSTLayer = GSTStackOps.find_layer(_stack, _stack.output_color)
	return _layer_text(layer) if layer != null else "Unavailable layer"


func _selected_alpha_text() -> String:
	match _stack.output_alpha:
		&"":
			return get_automatic_alpha_text()
		&"none":
			return "Opaque"
		&"texture":
			return "Texture transparency"
		&"color_alpha":
			return "Output layer transparency"
		_:
			var layer: GSTLayer = GSTStackOps.find_layer(_stack, _stack.output_alpha)
			return "%s grayscale value" % _layer_text(layer) if layer != null else "Unavailable layer"


func _selected_color_conversion() -> String:
	if _stack.output_color == &"":
		return ""
	var layer: GSTLayer = GSTStackOps.find_layer(_stack, _stack.output_color)
	return "field -> color: grayscale" if layer != null and layer.kind_out == GSTLayer.Kind.FIELD else ""


func _automatic_color_text() -> String:
	var top_color: GSTLayer = _top_color_layer()
	return "Automatic: %s" % _layer_text(top_color) if top_color != null else "Automatic: none"


func get_automatic_color_text() -> String:
	return _automatic_color_text()


func get_automatic_alpha_text() -> String:
	return "Automatic: Texture transparency" if _stack_has_texture_source() else "Automatic: Opaque"


func _layer_text(layer: GSTLayer) -> String:
	var entry: GSTManifestEntry = _library.get_entry(layer.entry)
	var function_name: String = entry.function if entry != null else layer.entry
	return "l%s %s" % [String(layer.id), function_name]


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


func _on_color_pressed() -> void:
	if _mutations_blocked:
		return
	chooser_requested.emit("output_color", &"", "", _color_button)


func _on_alpha_pressed() -> void:
	if _mutations_blocked:
		return
	chooser_requested.emit("output_alpha", &"", "", _alpha_button)


func get_color_button() -> Button:
	return _color_button


func get_alpha_button() -> Button:
	return _alpha_button


func get_selected_color_text() -> String:
	return _color_button.text


func get_selected_alpha_text() -> String:
	return _alpha_button.text
