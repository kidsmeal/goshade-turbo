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


## Saves `stack` to `path`. `{ok, reason}`.
static func save(stack: GSTStack, path: String) -> Dictionary:
	var err: Error = ResourceSaver.save(stack, path)
	if err != OK:
		return {"ok": false, "reason": "failed to save stack to %s: %s" % [path, error_string(err)]}
	return {"ok": true, "reason": ""}


## Loads a GSTStack from `path`. `{ok, stack, reason}`.
##
## CACHE_MODE_IGNORE: a reload must return a fresh instance, never one a
## previous load() or the open editor stack already holds.
##
## Every layer's `entry` must resolve against `library` or the load is
## refused naming the entry and layer; downstream codegen and inspector calls
## cannot report the cause. On success every layer's `manifest` is set.
static func load(path: String, library: GSTLibrary) -> Dictionary:
	if library == null:
		return {"ok": false, "stack": null, "reason": "GSTStackIO.load requires a library to resolve layer manifests (caller bug)"}

	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		return {"ok": false, "stack": null, "reason": "failed to load stack from %s" % path}
	if not (res is GSTStack):
		return {"ok": false, "stack": null, "reason": "%s did not load as a GSTStack" % path}

	var stack: GSTStack = res as GSTStack
	_normalize_stringnames(stack)
	for layer: GSTLayer in stack.layers:
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		if entry == null:
			return {
				"ok": false,
				"stack": null,
				"reason": "%s references unresolved entry %s (layer %s)" % [path, layer.entry, String(layer.id)],
			}
		layer.manifest = entry

	return {"ok": true, "stack": stack, "reason": ""}


## ResourceLoader coerces a typed @export StringName (GSTStack.output_color/
## output_alpha, GSTCoordBlock.warp_x/warp_y) to its declared type on load.
## GSTLayer.slots is an untyped Dictionary, so its values may come back as
## String; this re-wraps them.
static func _normalize_stringnames(stack: GSTStack) -> void:
	stack.output_color = StringName(stack.output_color)
	stack.output_alpha = StringName(stack.output_alpha)
	for layer: GSTLayer in stack.layers:
		for slot_name: Variant in layer.slots.keys():
			var value: Variant = layer.slots[slot_name]
			if typeof(value) == TYPE_STRING:
				layer.slots[slot_name] = StringName(value)
		if layer.coord != null:
			if typeof(layer.coord.warp_x) == TYPE_STRING:
				layer.coord.warp_x = StringName(layer.coord.warp_x)
			if typeof(layer.coord.warp_y) == TYPE_STRING:
				layer.coord.warp_y = StringName(layer.coord.warp_y)
