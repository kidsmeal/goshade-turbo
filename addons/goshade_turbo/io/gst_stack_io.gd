@tool
class_name GSTStackIO
extends RefCounted

## Saves and loads a GSTStack .tres (design decision 8: ".tres Resource per
## stack" is the source of truth). Layers and coord blocks are embedded
## sub-resources, never external .tres files: a plain GSTLayer.new()/
## GSTCoordBlock.new() carries no resource_path, and ResourceSaver embeds any
## sub-resource without one.
##
## GSTManifestEntry is never saved by this file (decision 5, planning
## decision "Manifests are never re-saved"): manifests are load-only and
## resolved fresh from `library` on every load(), never carried through the
## .tres itself.


## Saves `stack` to `path`. `{ok, reason}`.
static func save(stack: GSTStack, path: String) -> Dictionary:
	var err: Error = ResourceSaver.save(stack, path)
	if err != OK:
		return {"ok": false, "reason": "failed to save stack to %s: %s" % [path, error_string(err)]}
	return {"ok": true, "reason": ""}


## Loads a GSTStack from `path`. `{ok, stack, reason}`.
##
## CACHE_MODE_IGNORE: a reload must never hand back the same cached instance
## a previous load() (or the still-open editor stack) already holds, so
## mutating the loaded copy can never leak back into another caller's stack.
##
## Every layer's `entry` must resolve against `library`, or the load is
## refused naming the unresolved entry and layer: a layer whose manifest can
## never be set would otherwise silently fail every downstream codegen and
## inspector call instead of failing here, at the one point that knows why.
## On success, every layer's `manifest` is set from `library` (GSTLayer.gd:
## "a runtime convenience the panel re-resolves through GSTLibrary after
## loading a stack (phase 6)").
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


## Godot's .tres text format round-trips a StringName inside a typed @export
## var (GSTStack.output_color/output_alpha, GSTCoordBlock.warp_x/warp_y)
## correctly by construction: ResourceLoader coerces the loaded value to the
## exported property's declared type. GSTLayer.slots is a plain untyped
## Dictionary, so its values carry no such guarantee; this defensively
## re-wraps any that came back as a bare String (docs/PLAN.md Phase 6 Build:
## "if StringName values come back as String, normalize on load").
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
