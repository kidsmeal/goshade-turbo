@tool
class_name GSTHeader
extends RefCounted

## Serializes and parses the one-line JSON stack header embedded in every
## exported .gdshader. GSTCodegen._header_lines calls header_line().
##
## Schema: {schema: int, coord_space: String, output_color: String,
## output_alpha: String, next_id: int, layers: [{id, entry, kind_out, slots,
## params, coord, label?, enabled?, param_links?}]}. coord_space is "uv" |
## "screen_uv" | "local". Vectors serialize as [x, y] / [x, y, z]; colors as
## [r, g, b, a]. A texture param serializes as its resource_path string, an
## unset one as null (decision 27). coord is null for an operator layer. label, enabled and
## param_links are written only when non-default, so a stack using none of
## them differs from its v0.1 header only in `schema` (decision 23).
## param_links serializes as {"<param>": {"target": "<layer id>", "amount":
## <float>}}. JSON.stringify with an empty indent never inserts a newline, so
## the header is always exactly one line.
##
## parse() refuses a missing "// stack: " prefix, unparsable JSON, or a schema
## outside ACCEPTED_SCHEMAS with a reason; no empty stack is offered.

const HEADER_PREFIX: String = "// stack: "
## Written by serialize(). 2 added label, enabled and param_links (decision 23).
const SCHEMA_VERSION: int = 2
## Every schema parse() opens. Schema 1 opens with label, enabled and
## param_links at their defaults (decision 23).
const ACCEPTED_SCHEMAS: Array[int] = [1, 2]


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


## Parses a full header line (prefix included) into a GSTStack.
## `{ok, stack, reason, missing_textures}`. `library` resolves each layer's
## `manifest`; an unresolved `entry` leaves `manifest == null`
## (gst_stack_io.gd enforces resolution itself).
##
## A texture param whose path names no existing file is left unset and its
## path is appended to `missing_textures`; the stack still opens with
## `ok == true` (decision 27).
static func parse(line: String, library: GSTLibrary) -> Dictionary:
	var missing_textures: Array[String] = []
	if not line.begins_with(HEADER_PREFIX):
		return {"ok": false, "stack": null, "reason": "missing '%s' header prefix" % HEADER_PREFIX, "missing_textures": missing_textures}

	var json_text: String = line.substr(HEADER_PREFIX.length())
	# JSON.parse_string() prints an engine ERROR line on malformed input; the
	# instance parse() returns an Error code silently. Expected refusals must
	# not print errors (the headless test wrapper treats any as a failure).
	var json: JSON = JSON.new()
	if json.parse(json_text) != OK or not (json.get_data() is Dictionary):
		return {"ok": false, "stack": null, "reason": "stack header JSON is unparsable", "missing_textures": missing_textures}

	var data: Dictionary = json.get_data()
	var schema: int = int(data.get("schema", -1))
	if not ACCEPTED_SCHEMAS.has(schema):
		return {"ok": false, "stack": null, "reason": "unknown stack header schema %d (expected %d)" % [schema, SCHEMA_VERSION], "missing_textures": missing_textures}

	var stack: GSTStack = GSTStack.new()
	stack.coord_space = _coord_space_from_string(String(data.get("coord_space", "uv")))
	stack.output_color = StringName(String(data.get("output_color", "")))
	stack.output_alpha = StringName(String(data.get("output_alpha", "")))
	stack.next_id = int(data.get("next_id", 0))
	stack.layers = _layers_from_json(data.get("layers", []), library, schema, missing_textures)
	return {"ok": true, "stack": stack, "reason": "", "missing_textures": missing_textures}


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


## label, enabled and param_links are omitted at their defaults so a stack
## using no v0.2 field keeps its v0.1 header keys (decision 23).
static func _layer_to_json(layer: GSTLayer) -> Dictionary:
	var out: Dictionary = {
		"id": String(layer.id),
		"entry": layer.entry,
		"kind_out": int(layer.kind_out),
		"slots": _slots_to_json(layer.slots),
		"params": _params_to_json(layer.params),
		"coord": _coord_to_json(layer.coord) if layer.coord != null else null,
	}
	if not layer.label.is_empty():
		out["label"] = layer.label
	if not layer.enabled:
		out["enabled"] = false
	if not layer.param_links.is_empty():
		out["param_links"] = _param_links_to_json(layer.param_links)
	return out


## {"<param>": {"target": "<layer id>", "amount": <float>}}; amount goes
## through _param_value_to_json like every other param value (decision 29).
static func _param_links_to_json(links: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for param_name: Variant in links.keys():
		var link: Dictionary = links[param_name]
		out[String(param_name)] = {
			"target": String(link.get("target", &"")),
			"amount": _param_value_to_json(float(link.get("amount", 1.0))),
		}
	return out


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


## Type comes from the value's Variant type, not the manifest, so a stack
## with no manifest attached still serializes. A Texture2D writes its
## resource_path; a null (unset texture) writes null (decision 27).
static func _param_value_to_json(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_OBJECT:
			var resource: Resource = value as Resource
			return resource.resource_path if resource != null else null
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


static func _layers_from_json(layers_data: Variant, library: GSTLibrary, schema: int, missing_textures: Array[String]) -> Array[GSTLayer]:
	var layers: Array[GSTLayer] = []
	if not (layers_data is Array):
		return layers
	for layer_data: Variant in (layers_data as Array):
		if layer_data is Dictionary:
			layers.append(_layer_from_json(layer_data as Dictionary, library, schema, missing_textures))
	return layers


## Schema 1 predates label, enabled and param_links: those stay at their
## GSTLayer defaults even if the keys are present (decision 23).
static func _layer_from_json(data: Dictionary, library: GSTLibrary, schema: int, missing_textures: Array[String]) -> GSTLayer:
	var layer: GSTLayer = GSTLayer.new()
	layer.id = StringName(String(data.get("id", "")))
	layer.entry = String(data.get("entry", ""))
	layer.kind_out = int(data.get("kind_out", 0)) as GSTLayer.Kind
	layer.manifest = library.get_entry(layer.entry) if library != null else null
	layer.slots = _slots_from_json(data.get("slots", {}))
	layer.params = _params_from_json(data.get("params", {}), layer.manifest, missing_textures)
	var coord_data: Variant = data.get("coord", null)
	layer.coord = _coord_from_json(coord_data as Dictionary) if coord_data is Dictionary else null
	if schema >= 2:
		layer.label = String(data.get("label", ""))
		layer.enabled = bool(data.get("enabled", true))
		layer.param_links = _param_links_from_json(data.get("param_links", {}))
	return layer


## JSON decodes amount as float already; float() also covers a hand-written
## integer literal. target is re-wrapped as StringName to match slots.
static func _param_links_from_json(data: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (data is Dictionary):
		return out
	for param_name: Variant in (data as Dictionary).keys():
		var link: Variant = (data as Dictionary)[param_name]
		if not (link is Dictionary):
			continue
		out[String(param_name)] = {
			"target": StringName(String((link as Dictionary).get("target", ""))),
			"amount": float((link as Dictionary).get("amount", 1.0)),
		}
	return out


static func _slots_from_json(data: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (data is Dictionary):
		return out
	for slot_name: Variant in (data as Dictionary).keys():
		out[String(slot_name)] = StringName(String((data as Dictionary)[slot_name]))
	return out


## JSON decodes every number as float and every vector/color as Array.
## `manifest` supplies the declared type per param name so int params
## round-trip as int. A param with no resolvable manifest type keeps its raw
## decoded shape. A texture path that loads no Texture2D is left out of the
## result and appended to `missing_textures` (decision 27).
static func _params_from_json(data: Variant, manifest: GSTManifestEntry, missing_textures: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	if not (data is Dictionary):
		return out
	for param_name: Variant in (data as Dictionary).keys():
		var raw_value: Variant = (data as Dictionary)[param_name]
		var param_type: String = _param_type(manifest, String(param_name))
		if param_type == "texture":
			if raw_value == null:
				out[String(param_name)] = null
				continue
			var texture: Texture2D = _texture_from_path(String(raw_value))
			if texture == null:
				missing_textures.append(String(raw_value))
			else:
				out[String(param_name)] = texture
			continue
		out[String(param_name)] = _param_value_from_json(raw_value, param_type)
	return out


## ResourceLoader.exists() first: ResourceLoader.load() on a missing path
## prints "ERROR: Resource file not found" (Godot 4.6.2), which the headless
## test wrapper and the editor log both treat as a failure.
static func _texture_from_path(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path, "Texture2D"):
		return null
	return ResourceLoader.load(path, "Texture2D") as Texture2D


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
