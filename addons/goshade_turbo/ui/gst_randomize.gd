@tool
class_name GSTRandomize
extends RefCounted

## Slider randomization inside an open recipe's ranges (decision 16: v0.1
## randomize is slider-only; structural randomize is an expansion). Design:
## docs/DESIGN.md decision 16, docs/PLAN.md Phase 8 Build item 3.
##
## Coord-block fields (scale/offset/rotation/scroll/warp) are never touched
## here (decision 16: "coord block fields are not randomized ... sliders"):
## only each layer's manifest params, the same set the inspector column
## exposes as GSTLayer's dynamic properties (gst_layer.gd's
## _get_property_list), are candidates.


## Every param on every layer in `stack`, resolved against `library`, mapped
## to a uniform-random value inside the manifest's own min/max (int
## inclusive via RandomNumberGenerator.randi_range, float continuous via
## randf_range, color random RGB with alpha 1, vec2/vec3 each component
## within the manifest range or [0, 1] when the manifest declares no range --
## every real vec3 manifest param, e.g. color/palette's a/b/c/d, carries no
## min/max key at all). A layer whose entry does not resolve, or whose
## manifest declares no params, contributes nothing. Returns
## {layer_id: {param_name: new_value}}; a stack with no randomizable params
## anywhere yields an empty Dictionary.
static func randomize(stack: GSTStack, library: GSTLibrary, rng: RandomNumberGenerator) -> Dictionary:
	var changes: Dictionary = {}
	for layer: GSTLayer in stack.layers:
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		if entry == null or entry.params.is_empty():
			continue
		var layer_changes: Dictionary = {}
		for param: Dictionary in entry.params:
			layer_changes[String(param["name"])] = _random_value(param, rng)
		changes[layer.id] = layer_changes
	return changes


## Writes every {layer_id: {param_name: value}} entry in `changes` through
## the matching layer's own Object.set() (so gst_layer.gd's GSTLayer._set
## runs, the same write path a real inspector slider edit goes through),
## then calls layer.emit_changed() once per touched layer (docs/PLAN.md
## Phase 8 fix pass 2, item 1): GSTRandomize.apply is the live undo/redo
## writer for the randomize action (gst_main_panel.gd's
## _on_randomize_pressed), so its writes are external to whatever
## EditorInspector currently has the layer open, and emit_changed() is the
## same signal GSTCoordBlock.changed relies on for an equivalent external
## write (gst_inspector_column.gd). The panel's own _refresh_inspector,
## registered as a do/undo method alongside this call on the same action,
## is still required to make the already-built EditorProperty widgets
## re-read: emit_changed() alone tells any listener the resource changed,
## it does not by itself force EditorInspector to rebuild its rows for the
## object it already has open. A layer_id absent from `stack` is skipped
## rather than raising: `changes` may be stale against a stack that was
## structurally edited since it was computed.
static func apply(stack: GSTStack, changes: Dictionary) -> void:
	for layer_id: Variant in changes.keys():
		var layer: GSTLayer = GSTStackOps.find_layer(stack, layer_id)
		if layer == null:
			continue
		var layer_changes: Dictionary = changes[layer_id]
		for param_name: Variant in layer_changes.keys():
			layer.set(StringName(param_name), layer_changes[param_name])
		layer.emit_changed()


static func _random_value(param: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var param_type: String = String(param.get("type", ""))
	match param_type:
		"int":
			return rng.randi_range(int(param["min"]), int(param["max"]))
		"float":
			return rng.randf_range(float(param["min"]), float(param["max"]))
		"color":
			return Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
		"vec2":
			return Vector2(_random_component(param, rng), _random_component(param, rng))
		"vec3":
			return Vector3(_random_component(param, rng), _random_component(param, rng), _random_component(param, rng))
		_:
			return rng.randf_range(0.0, 1.0)


## One component of a vec2/vec3 param: the manifest's own min/max when the
## param declares them, else [0, 1] (no real manifest param declares min/max
## on a vec2/vec3 today, e.g. color/palette's a/b/c/d; the fallback keeps
## this correct if one ever does).
static func _random_component(param: Dictionary, rng: RandomNumberGenerator) -> float:
	var min_value: float = float(param.get("min", 0.0))
	var max_value: float = float(param.get("max", 1.0))
	return rng.randf_range(min_value, max_value)
