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
	# EditorInspector assigns its default property tooltip after parsing.
	editor.call_deferred("set_tooltip_text", description)
	return true
