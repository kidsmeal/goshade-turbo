@tool
class_name GSTLayer
extends Resource

## One stack entry: a manifest function instance with its own slots and params.
## Design: docs/DESIGN.md, Data model.

enum Kind {
	FIELD,
	COLOR,
}

## Stable id, assigned once at creation. Never reused (decision 22).
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

## Non-exported: the manifest this layer's `entry` resolves to, set by the
## panel on add and on load (phase 4, docs/PLAN.md Phase 4 Files). Backs the
## dynamic inspector properties below. Never serialized: `entry` (the
## manifest id string) is the saved reference, `manifest` is a runtime
## convenience the panel re-resolves through GSTLibrary after loading a
## stack (phase 6).
var manifest: GSTManifestEntry = null


## One dynamic property per manifest param (decision 13: the inspector
## column is the layer resource's own property editor). float and int
## params get PROPERTY_HINT_RANGE from the manifest's min/max; color, vec2,
## and vec3 params get TYPE_COLOR/TYPE_VECTOR2/TYPE_VECTOR3 with no hint
## (docs/PLAN.md phase 4 fix pass 2, item 1: color/palette's a/b/c/d are
## real "vec3" params). Editor-only usage: params stays the single stored
## source of truth via the @export above, so these are never also written
## to the .tres by ResourceSaver.
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
		if param_type == "float" or param_type == "int":
			prop["hint"] = PROPERTY_HINT_RANGE
			prop["hint_string"] = "%s,%s" % [str(param["min"]), str(param["max"])]
		list.append(prop)
	return list


func _get(property: StringName) -> Variant:
	var param: Variant = _find_param(property)
	if param == null:
		return null
	return params.get(String(property), (param as Dictionary)["default"])


func _set(property: StringName, value: Variant) -> bool:
	if _find_param(property) == null:
		return false
	params[String(property)] = value
	return true


func _find_param(property: StringName) -> Variant:
	if manifest == null:
		return null
	for param: Dictionary in manifest.params:
		if String(param["name"]) == String(property):
			return param
	return null


## Unknown param types are a manifest data bug, not a script error: they fall
## through to TYPE_FLOAT with a push_warning naming the offending entry and
## param, rather than failing the inspector build (docs/PLAN.md phase 4 fix
## pass 2, item 1).
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
