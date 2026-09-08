@tool
class_name GSTHeader
extends RefCounted

## Serializes and parses the one-line JSON stack header embedded in every
## exported .gdshader (design decision 8, docs/PLAN.md Cross-cutting concern
## "Header JSON schema"). GSTCodegen's single header call site
## (gst_codegen.gd::_header_lines) calls header_line() directly.
##
## Schema: {schema: int, coord_space: String, output_color: String,
## output_alpha: String, next_id: int, layers: [{id, entry, kind_out, slots,
## params, coord}]}. coord_space is "uv" | "screen_uv" | "local". Vectors
## serialize as [x, y] / [x, y, z]; colors as [r, g, b, a]. coord is null for
## an operator layer. The JSON never contains a newline (JSON.stringify with
## an empty indent string never inserts one); the header is always exactly
## one line.
##
## Reopen refusals (design B8, docs/PLAN.md Blocker B8): a missing
## "// stack: " prefix, unparsable JSON, or an unknown schema version are
## each refused with a reason naming the failure. No new empty stack is
## offered on any of these; the caller (gst_export.gd) surfaces the reason.

const HEADER_PREFIX: String = "// stack: "
const SCHEMA_VERSION: int = 1


## The full header line: "// stack: " plus the one-line JSON for `stack`.
static func header_line(stack: GSTStack) -> String:
	return "%s%s" % [HEADER_PREFIX, serialize(stack)]


## The one-line JSON body only (no "// stack: " prefix).
static func serialize(stack: GSTStack) -> String:
	var data: Dictionary = {
		"schema": SCHEMA_VERSION,
		"coord_space": _coord_space_to_string(stack.coord_space),
		"output_color": String(stack.output_color),
		"output_alpha": String(stack.output_alpha),
		"next_id": stack.next_id,
		"layers": _layers_to_json(stack.layers),
	}
	return JSON.stringify(data)


## Parses a full header line (including the "// stack: " prefix) back into a
## GSTStack. `{ok, stack, reason}`. `library` resolves each layer's
## `manifest` for the inspector and material sync; a layer whose `entry` does
## not resolve is left with `manifest == null` here (a caller that requires
## every entry to resolve, e.g. gst_stack_io.gd, checks that itself).
static func parse(line: String, library: GSTLibrary) -> Dictionary:
	if not line.begins_with(HEADER_PREFIX):
		return {"ok": false, "stack": null, "reason": "missing '%s' header prefix" % HEADER_PREFIX}

	var json_text: String = line.substr(HEADER_PREFIX.length())
	# JSON.parse_string() prints an engine ERROR: line on malformed input
	# (verified), which the headless test wrapper treats as a hard failure
	# even on this expected-refusal path (never push_error/print an error on
	# an expected path). The instance API's parse() returns an Error code
	# silently instead.
	var json: JSON = JSON.new()
	if json.parse(json_text) != OK or not (json.get_data() is Dictionary):
		return {"ok": false, "stack": null, "reason": "stack header JSON is unparsable"}

	var data: Dictionary = json.get_data()
	var schema: int = int(data.get("schema", -1))
	if schema != SCHEMA_VERSION:
		return {"ok": false, "stack": null, "reason": "unknown stack header schema %d (expected %d)" % [schema, SCHEMA_VERSION]}

	var stack: GSTStack = GSTStack.new()
	stack.coord_space = _coord_space_from_string(String(data.get("coord_space", "uv")))
	stack.output_color = StringName(String(data.get("output_color", "")))
	stack.output_alpha = StringName(String(data.get("output_alpha", "")))
	stack.next_id = int(data.get("next_id", 0))
	stack.layers = _layers_from_json(data.get("layers", []), library)
	return {"ok": true, "stack": stack, "reason": ""}


static func _coord_space_to_string(space: GSTStack.CoordSpace) -> String:
	match space:
		GSTStack.CoordSpace.SCREEN_UV:
			return "screen_uv"
		GSTStack.CoordSpace.LOCAL:
			return "local"
		_:
			return "uv"


static func _coord_space_from_string(text: String) -> GSTStack.CoordSpace:
	match text:
		"screen_uv":
			return GSTStack.CoordSpace.SCREEN_UV
		"local":
			return GSTStack.CoordSpace.LOCAL
		_:
			return GSTStack.CoordSpace.UV


static func _layers_to_json(layers: Array[GSTLayer]) -> Array:
	var out: Array = []
	for layer: GSTLayer in layers:
		out.append(_layer_to_json(layer))
	return out


static func _layer_to_json(layer: GSTLayer) -> Dictionary:
	return {
		"id": String(layer.id),
		"entry": layer.entry,
		"kind_out": int(layer.kind_out),
		"slots": _slots_to_json(layer.slots),
		"params": _params_to_json(layer.params),
		"coord": _coord_to_json(layer.coord) if layer.coord != null else null,
	}


static func _slots_to_json(slots: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for slot_name: Variant in slots.keys():
		out[String(slot_name)] = String(slots[slot_name])
	return out


static func _params_to_json(params: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for param_name: Variant in params.keys():
		out[String(param_name)] = _param_value_to_json(params[param_name])
	return out


## Type is read from the value's own Variant type, not the manifest: a bare
## GSTStack built without ever attaching a manifest (most codegen tests, and
## any stack whose entry no longer resolves) must still serialize correctly.
static func _param_value_to_json(value: Variant) -> Variant:
	match typeof(value):
		TYPE_COLOR:
			var c: Color = value
			return [c.r, c.g, c.b, c.a]
		TYPE_VECTOR3:
			var v3: Vector3 = value
			return [v3.x, v3.y, v3.z]
		TYPE_VECTOR2:
			var v2: Vector2 = value
			return [v2.x, v2.y]
		TYPE_INT:
			return int(value)
		_:
			return float(value)


static func _coord_to_json(coord: GSTCoordBlock) -> Dictionary:
	return {
		"scale": _vec2_to_json(coord.scale),
		"offset": _vec2_to_json(coord.offset),
		"rotation": coord.rotation,
		"scroll": _vec2_to_json(coord.scroll),
		"warp_x": String(coord.warp_x),
		"warp_y": String(coord.warp_y),
		"warp_strength": coord.warp_strength,
	}


static func _vec2_to_json(v: Vector2) -> Array:
	return [v.x, v.y]


static func _layers_from_json(layers_data: Variant, library: GSTLibrary) -> Array[GSTLayer]:
	var layers: Array[GSTLayer] = []
	if not (layers_data is Array):
		return layers
	for layer_data: Variant in (layers_data as Array):
		if layer_data is Dictionary:
			layers.append(_layer_from_json(layer_data as Dictionary, library))
	return layers


static func _layer_from_json(data: Dictionary, library: GSTLibrary) -> GSTLayer:
	var layer: GSTLayer = GSTLayer.new()
	layer.id = StringName(String(data.get("id", "")))
	layer.entry = String(data.get("entry", ""))
	layer.kind_out = int(data.get("kind_out", 0)) as GSTLayer.Kind
	layer.manifest = library.get_entry(layer.entry) if library != null else null
	layer.slots = _slots_from_json(data.get("slots", {}))
	layer.params = _params_from_json(data.get("params", {}), layer.manifest)
	var coord_data: Variant = data.get("coord", null)
	layer.coord = _coord_from_json(coord_data as Dictionary) if coord_data is Dictionary else null
	return layer


static func _slots_from_json(data: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (data is Dictionary):
		return out
	for slot_name: Variant in (data as Dictionary).keys():
		out[String(slot_name)] = StringName(String((data as Dictionary)[slot_name]))
	return out


## Param values decode from JSON as float or Array (JSON has no int/Color/
## Vector distinction, verified: JSON.parse_string("4") returns a float).
## `manifest` supplies the real type per param name so an int param (e.g.
## fbm's octaves) round-trips as int rather than staying a float. A param
## whose manifest cannot be resolved (manifest == null, or the name is not in
## manifest.params) keeps its raw decoded JSON shape.
static func _params_from_json(data: Variant, manifest: GSTManifestEntry) -> Dictionary:
	var out: Dictionary = {}
	if not (data is Dictionary):
		return out
	for param_name: Variant in (data as Dictionary).keys():
		var raw_value: Variant = (data as Dictionary)[param_name]
		var param_type: String = _param_type(manifest, String(param_name))
		out[String(param_name)] = _param_value_from_json(raw_value, param_type)
	return out


static func _param_type(manifest: GSTManifestEntry, param_name: String) -> String:
	if manifest == null:
		return ""
	for param: Dictionary in manifest.params:
		if String(param["name"]) == param_name:
			return String(param["type"])
	return ""


static func _param_value_from_json(raw_value: Variant, param_type: String) -> Variant:
	match param_type:
		"color":
			var c: Array = raw_value
			return Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
		"vec3":
			var v3: Array = raw_value
			return Vector3(float(v3[0]), float(v3[1]), float(v3[2]))
		"vec2":
			var v2: Array = raw_value
			return Vector2(float(v2[0]), float(v2[1]))
		"int":
			return int(raw_value)
		"float":
			return float(raw_value)
		_:
			return raw_value


static func _coord_from_json(data: Dictionary) -> GSTCoordBlock:
	var coord: GSTCoordBlock = GSTCoordBlock.new()
	coord.scale = _vec2_from_json(data.get("scale", [1.0, 1.0]))
	coord.offset = _vec2_from_json(data.get("offset", [0.0, 0.0]))
	coord.rotation = float(data.get("rotation", 0.0))
	coord.scroll = _vec2_from_json(data.get("scroll", [0.0, 0.0]))
	coord.warp_x = StringName(String(data.get("warp_x", "")))
	coord.warp_y = StringName(String(data.get("warp_y", "")))
	coord.warp_strength = float(data.get("warp_strength", 0.0))
	return coord


static func _vec2_from_json(raw_value: Variant) -> Vector2:
	var arr: Array = raw_value
	return Vector2(float(arr[0]), float(arr[1]))
