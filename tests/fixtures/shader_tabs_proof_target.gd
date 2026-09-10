@tool
class_name GSTTabsProofTarget
extends Resource

## Standalone proof-only resource for tests/gst_editor_document_proof.gd.
## Replaces a script-local inner class so ResourceSaver/ResourceLoader can
## round-trip a real instance (a script-local class embeds an empty
## GDScript sub-resource ResourceLoader cannot resolve back to a typed
## object). Fields mirror the removed inner ProofTarget exactly.

@export_range(0.0, 1.0, 0.01) var scalar: float = 0.25
@export var vector: Vector3 = Vector3(0.1, 0.2, 0.3)
var rgb_storage: Vector3 = Vector3(0.2, 0.4, 0.6)
var structural_value: int = 0


func _get(property: StringName) -> Variant:
	if property == &"rgb":
		return Color(rgb_storage.x, rgb_storage.y, rgb_storage.z, 1.0)
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == &"rgb" and value is Color:
		var color: Color = value as Color
		rgb_storage = Vector3(color.r, color.g, color.b)
		return true
	return false


func _get_property_list() -> Array[Dictionary]:
	return [{"name": &"rgb", "type": TYPE_COLOR, "hint": PROPERTY_HINT_COLOR_NO_ALPHA, "usage": PROPERTY_USAGE_DEFAULT}]


func set_structural_value(value: int) -> void:
	structural_value = value
