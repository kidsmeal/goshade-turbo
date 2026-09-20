@tool
class_name GSTLayer
extends Resource

## One stack entry: a manifest function instance with its own slots and params.

enum Kind {
	FIELD,
	COLOR,
}

## Stable id, assigned once at creation. Never reused.
@export var id: StringName = &""
## Manifest id, e.g. "generative/fbm".
@export var entry: String = ""
## Copied from the manifest at creation. Fixed for the life of the layer.
@export var kind_out: Kind = Kind.FIELD
## slot_name (String) -> referenced layer id (StringName).
@export var slots: Dictionary = {}
## param_name (String) -> tuned value (Variant, type per manifest param schema).
@export var params: Dictionary = {}
## Generators only. Null for operators.
@export var coord: GSTCoordBlock = null

## The manifest `entry` resolves to, set by the panel on add and on load.
## Backs the dynamic inspector properties below. Never serialized: `entry` is
## the saved reference; the panel re-resolves this through GSTLibrary.
var manifest: GSTManifestEntry = null

const EDITOR_HIDDEN_PROPERTIES: Array[StringName] = [
	&"id",
	&"entry",
	&"kind_out",
	&"slots",
	&"params",
	&"coord",
	&"resource_local_to_scene",
	&"resource_name",
	&"resource_path",
	&"script",
]


## Hides the serialized model fields and inherited categories from the
## inspector while keeping their storage usage. Dynamic manifest params stay
## editor-visible.
func _validate_property(property: Dictionary) -> void:
	var usage: int = int(property.get("usage", 0))
	var property_name: StringName = StringName(property.get("name", &""))
	if property_name in EDITOR_HIDDEN_PROPERTIES or usage & PROPERTY_USAGE_CATEGORY != 0:
		property["usage"] = usage & ~PROPERTY_USAGE_EDITOR


## One dynamic property per manifest param. float and int params get
## PROPERTY_HINT_RANGE from the manifest's min/max. A vec3 with
## editor = color_rgb uses a native RGB picker with Vector3 storage.
## PROPERTY_USAGE_EDITOR only: `params` is the stored source of truth, so
## ResourceSaver never writes these to the .tres.
func _get_property_list() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if manifest == null:
		return list
	for param: Dictionary in manifest.params:
		var param_type: String = String(param.get("type", ""))
		var prop: Dictionary = {
			"name": String(param["name"]),
			"type": _property_type_for(param_type, String(param["name"])),
			"usage": PROPERTY_USAGE_EDITOR,
		}
		if _uses_rgb_editor(param):
			prop["type"] = TYPE_COLOR
			prop["hint"] = PROPERTY_HINT_COLOR_NO_ALPHA
		elif param_type == "float" or param_type == "int":
			prop["hint"] = PROPERTY_HINT_RANGE
			prop["hint_string"] = "%s,%s,or_greater" % [str(param["min"]), str(param["max"])]
		list.append(prop)
	return list


func _get(property: StringName) -> Variant:
	var param: Variant = _find_param(property)
	if param == null:
		return null
	var value: Variant = params.get(String(property), (param as Dictionary)["default"])
	if _uses_rgb_editor(param):
		var rgb: Vector3 = value
		return Color(rgb.x, rgb.y, rgb.z, 1.0)
	return value


func _set(property: StringName, value: Variant) -> bool:
	var param: Variant = _find_param(property)
	if param == null:
		return false
	if _uses_rgb_editor(param) and value is Color:
		value = Vector3(value.r, value.g, value.b)
	params[String(property)] = value
	return true


func _uses_rgb_editor(param: Dictionary) -> bool:
	return param.get("type", "") == "vec3" and param.get("editor", "") == "color_rgb"


func _find_param(property: StringName) -> Variant:
	if manifest == null:
		return null
	for param: Dictionary in manifest.params:
		if String(param["name"]) == String(property):
			return param
	return null


## The manifest param dict for `property`, or {}. gst_inspector_column.gd
## reads label and description from it.
func get_param_schema(property: StringName) -> Dictionary:
	var param: Variant = _find_param(property)
	return param as Dictionary if param is Dictionary else {}


## True when `params` holds an explicit entry for property_name, as opposed
## to _get falling back to the manifest default. Undo must restore this exact
## absence: the dirty fingerprint includes serialized params keys.
func has_param_value(property_name: StringName) -> bool:
	return params.has(String(property_name))


## Erases the explicit params entry so _get falls back to the manifest default.
func erase_param_value(property_name: StringName) -> void:
	params.erase(String(property_name))


## An unknown param type is a manifest data bug: falls back to TYPE_FLOAT
## with a push_warning rather than failing the inspector build.
func _property_type_for(param_type: String, param_name: String) -> int:
	match param_type:
		"int":
			return TYPE_INT
		"float":
			return TYPE_FLOAT
		"color":
			return TYPE_COLOR
		"vec2":
			return TYPE_VECTOR2
		"vec3":
			return TYPE_VECTOR3
		_:
			push_warning("GSTLayer entry %s param %s has unknown type '%s'; falling back to TYPE_FLOAT" % [entry, param_name, param_type])
			return TYPE_FLOAT
