@tool
class_name GSTInspectorPlugin
extends EditorInspectorPlugin

## Replaces only GoShade Turbo model properties with the engine's standard
## EditorProperty for the original path/type/hint, then changes presentation.

var _instantiating_native_editor: bool = false


func _can_handle(object: Object) -> bool:
	return not _instantiating_native_editor and (object is GSTLayer or object is GSTCoordBlock)


func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool) -> bool:
	var metadata: Dictionary = {}
	if object is GSTLayer:
		metadata = (object as GSTLayer).get_param_schema(name)
		if metadata.is_empty():
			return true
	elif object is GSTCoordBlock:
		metadata = GSTCoordBlock.get_editor_metadata(name)
		if metadata.is_empty():
			return true
		if name == "warp_x" or name == "warp_y":
			return true
	else:
		return false

	_instantiating_native_editor = true
	var editor: EditorProperty = EditorInspector.instantiate_property_editor(object, type, name, hint_type, hint_string, usage_flags, wide)
	_instantiating_native_editor = false
	if editor == null:
		return false
	var description: String = String(metadata["description"])
	add_property_editor(name, editor, false, String(metadata["label"]))
	if (object is GSTCoordBlock and name in ["warp_strength", "offset", "scroll", "rotation"]) or (object is GSTLayer and name in ["gain", "edge0", "edge1"]):
		var context: Label = Label.new()
		context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		context.hide()
		context.tree_entered.connect(_on_context_entered.bind(context))
		editor.set_meta(&"gst_context_label", context)
		add_custom_control(context)
	# EditorInspector assigns its default property tooltip after parsing.
	editor.call_deferred("set_tooltip_text", description)
	return true


## Inspector parsing can finish after the column's selection callback.
## Refresh after each actual row enters the inspector, including rebuilds.
func _on_context_entered(label: Label) -> void:
	var parent: Node = label.get_parent()
	while parent != null:
		if parent is GSTInspectorColumn:
			(parent as GSTInspectorColumn).refresh_control_context()
			return
		parent = parent.get_parent()
