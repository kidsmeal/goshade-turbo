@tool
class_name GSTStackIO
extends RefCounted

## Saves and loads a GSTStack .tres, the source of truth per stack. Layers
## and coord blocks are embedded sub-resources: GSTLayer.new() and
## GSTCoordBlock.new() carry no resource_path, and ResourceSaver embeds any
## sub-resource without one.
##
## GSTManifestEntry is never saved here: manifests are load-only and resolved
## from `library` on every load().
##
## The .tres carries no schema field (decision 23). A v0.1 file has no
## label, enabled or param_links lines and loads them at their GSTLayer
## defaults; ResourceSaver omits those properties while they are at default.


## Saves `stack` to `path`. `{ok, reason}`.
static func save(stack: GSTStack, path: String) -> Dictionary:
	var err: Error = ResourceSaver.save(stack, path)
	if err != OK:
		return {"ok": false, "reason": "failed to save stack to %s: %s" % [path, error_string(err)]}
	return {"ok": true, "reason": ""}


## Prefix of the string substituted for a missing ExtResource before load;
## the rest of the string is the missing path. See _substitute_missing.
const MISSING_EXT_PREFIX: String = "gst_missing_ext_resource:"
## Temp copy loaded when _substitute_missing rewrote the file text.
const SUBSTITUTED_PATH: String = "user://gst_stack_io_missing_ext.tres"


## Loads a GSTStack from `path`. `{ok, stack, reason, missing_textures}`.
##
## CACHE_MODE_IGNORE: a reload must return a fresh instance, never one a
## previous load() or the open editor stack already holds.
##
## Every layer's `entry` must resolve against `library` or the load is
## refused naming the entry and layer; downstream codegen and inspector calls
## cannot report the cause. On success every layer's `manifest` is set.
##
## A texture ExtResource whose file is missing leaves its param unset and its
## path in `missing_textures`; the load still succeeds (decision 27).
## Verified on Godot 4.6.2 headless: ResourceLoader.load on a .tres with a
## missing `[ext_resource type="Texture2D"]` still returns the resource, with
## the referencing value set to null, but prints two `ERROR:` lines
## ("Resource file not found" and "[ext_resource] referenced non-existent
## resource"). The null also loses the path. So the file text is checked
## first: each missing non-Script ext_resource is replaced by a
## MISSING_EXT_PREFIX string carrying its path, the rewritten text is loaded
## from SUBSTITUTED_PATH, and those params are erased and reported.
static func load(path: String, library: GSTLibrary) -> Dictionary:
	var missing_textures: Array[String] = []
	if library == null:
		return {"ok": false, "stack": null, "reason": "GSTStackIO.load requires a library to resolve layer manifests (caller bug)", "missing_textures": missing_textures}

	var load_path: String = path
	if FileAccess.file_exists(path):
		var text: String = FileAccess.get_file_as_string(path)
		var substituted: String = _substitute_missing(text)
		if substituted != text:
			var temp: FileAccess = FileAccess.open(SUBSTITUTED_PATH, FileAccess.WRITE)
			if temp == null:
				return {"ok": false, "stack": null, "reason": "failed to write %s: %s" % [SUBSTITUTED_PATH, error_string(FileAccess.get_open_error())], "missing_textures": missing_textures}
			temp.store_string(substituted)
			temp.close()
			load_path = SUBSTITUTED_PATH

	var res: Resource = ResourceLoader.load(load_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if load_path != path:
		DirAccess.remove_absolute(load_path)
	if res == null:
		return {"ok": false, "stack": null, "reason": "failed to load stack from %s" % path, "missing_textures": missing_textures}
	if not (res is GSTStack):
		return {"ok": false, "stack": null, "reason": "%s did not load as a GSTStack" % path, "missing_textures": missing_textures}

	var stack: GSTStack = res as GSTStack
	_normalize_stringnames(stack)
	_erase_missing_params(stack, missing_textures)
	for layer: GSTLayer in stack.layers:
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		if entry == null:
			return {
				"ok": false,
				"stack": null,
				"reason": "%s references unresolved entry %s (layer %s)" % [path, layer.entry, String(layer.id)],
				"missing_textures": missing_textures,
			}
		layer.manifest = entry

	return {"ok": true, "stack": stack, "reason": "", "missing_textures": missing_textures}


## `text` with every missing non-Script ext_resource removed and each
## `ExtResource("<id>")` reference to it replaced by the string
## MISSING_EXT_PREFIX + path. Returns `text` unchanged when nothing is
## missing. Script ext_resources are left alone: a missing script keeps
## Godot's own load failure.
static func _substitute_missing(text: String) -> String:
	var line_regex: RegEx = RegEx.create_from_string("(?m)^\\[ext_resource ([^\\]]*)\\]\\r?\\n?")
	var attr_regex: RegEx = RegEx.create_from_string("(\\w+)=\"([^\"]*)\"")
	var out: String = text
	for line_match: RegExMatch in line_regex.search_all(text):
		var attrs: Dictionary = {}
		for attr_match: RegExMatch in attr_regex.search_all(line_match.get_string(1)):
			attrs[attr_match.get_string(1)] = attr_match.get_string(2)
		if String(attrs.get("type", "")) == "Script" or _ext_resource_exists(attrs):
			continue
		var missing_value: String = "\"%s\"" % (MISSING_EXT_PREFIX + String(attrs.get("path", ""))).c_escape()
		out = out.replace(line_match.get_string(0), "")
		out = out.replace("ExtResource(\"%s\")" % String(attrs.get("id", "")), missing_value)
	return out


## Mirrors the text loader's lookup order: a uid that resolves to an existing
## file wins, else the path.
static func _ext_resource_exists(attrs: Dictionary) -> bool:
	var uid_text: String = String(attrs.get("uid", ""))
	if not uid_text.is_empty():
		var uid: int = ResourceUID.text_to_id(uid_text)
		if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid) and ResourceLoader.exists(ResourceUID.get_id_path(uid)):
			return true
	var path: String = String(attrs.get("path", ""))
	return not path.is_empty() and ResourceLoader.exists(path)


## Erases every param _substitute_missing turned into a MISSING_EXT_PREFIX
## string, so _get falls back to null, and appends its path to `missing`.
static func _erase_missing_params(stack: GSTStack, missing: Array[String]) -> void:
	for layer: GSTLayer in stack.layers:
		for param_name: Variant in layer.params.keys():
			var value: Variant = layer.params[param_name]
			if typeof(value) == TYPE_STRING and String(value).begins_with(MISSING_EXT_PREFIX):
				layer.params.erase(param_name)
				missing.append(String(value).substr(MISSING_EXT_PREFIX.length()))


## ResourceLoader coerces a typed @export StringName (GSTStack.output_color/
## output_alpha, GSTCoordBlock.warp_x/warp_y) to its declared type on load.
## GSTLayer.slots and the `target` of each GSTLayer.param_links entry sit in
## untyped Dictionaries, so they may come back as String; this re-wraps them.
static func _normalize_stringnames(stack: GSTStack) -> void:
	stack.output_color = StringName(stack.output_color)
	stack.output_alpha = StringName(stack.output_alpha)
	for layer: GSTLayer in stack.layers:
		for slot_name: Variant in layer.slots.keys():
			var value: Variant = layer.slots[slot_name]
			if typeof(value) == TYPE_STRING:
				layer.slots[slot_name] = StringName(value)
		for param_name: Variant in layer.param_links.keys():
			var link: Variant = layer.param_links[param_name]
			if link is Dictionary and typeof((link as Dictionary).get("target")) == TYPE_STRING:
				(link as Dictionary)["target"] = StringName((link as Dictionary)["target"])
		if layer.coord != null:
			if typeof(layer.coord.warp_x) == TYPE_STRING:
				layer.coord.warp_x = StringName(layer.coord.warp_x)
			if typeof(layer.coord.warp_y) == TYPE_STRING:
				layer.coord.warp_y = StringName(layer.coord.warp_y)
