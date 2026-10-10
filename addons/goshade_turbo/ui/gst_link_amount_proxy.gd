@tool
class_name GSTLinkAmountProxy
extends RefCounted

## Exposes one param link's amount (decision 29) as an editable `amount`
## property, so gst_inspector_column.gd builds its native EditorProperty with
## EditorInspector.instantiate_property_editor and tracks its gestures like
## any other row. Reads and writes `layer.param_links[param_name]["amount"]`
## directly; the column routes each finished gesture through
## GSTUndo.set_link_amount. An unlinked param reads LINK_AMOUNT_DEFAULT and
## ignores writes.

const PROPERTY: StringName = &"amount"
## Amount a new link starts at (decision 29).
const LINK_AMOUNT_DEFAULT: float = 1.0
const AMOUNT_STEP: float = 0.01

var layer: GSTLayer = null
var param_name: String = ""


func _init(linked_layer: GSTLayer, linked_param: String) -> void:
	layer = linked_layer
	param_name = linked_param


static func hint_string() -> String:
	return "%s,%s,%s" % [String.num(GSTStackOps.LINK_AMOUNT_MIN, 6), String.num(GSTStackOps.LINK_AMOUNT_MAX, 6), String.num(AMOUNT_STEP, 6)]


func get_property_info() -> Dictionary:
	return {
		"name": String(PROPERTY),
		"type": TYPE_FLOAT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": hint_string(),
		"usage": PROPERTY_USAGE_EDITOR,
	}


func _get_property_list() -> Array[Dictionary]:
	return [get_property_info()]


func _get(property: StringName) -> Variant:
	if property != PROPERTY:
		return null
	var link: Variant = layer.param_links.get(param_name, null)
	if not (link is Dictionary):
		return LINK_AMOUNT_DEFAULT
	return float((link as Dictionary).get("amount", LINK_AMOUNT_DEFAULT))


func _set(property: StringName, value: Variant) -> bool:
	if property != PROPERTY:
		return false
	var link: Variant = layer.param_links.get(param_name, null)
	if link is Dictionary:
		(link as Dictionary)["amount"] = clampf(float(value), GSTStackOps.LINK_AMOUNT_MIN, GSTStackOps.LINK_AMOUNT_MAX)
	return true
