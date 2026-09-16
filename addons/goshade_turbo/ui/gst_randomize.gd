@tool
class_name GSTRandomize
extends RefCounted

## Slider randomization inside each manifest param's range. Slider-only:
## coord-block fields (scale/offset/rotation/scroll/warp) are never touched.
## Candidates are each layer's manifest params, the set
## GSTLayer._get_property_list exposes.


## Every param on every layer, resolved against `library`, mapped to a
## uniform-random value inside the manifest min/max: int inclusive, float
## continuous, color random RGB with alpha 1, vec2/vec3 per component within
## the manifest range or [0, 1] when none is declared. A layer whose entry
## does not resolve or declares no params contributes nothing. Returns
## {layer_id: {param_name: new_value}}.
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
## Object.set() so GSTLayer._set runs (the inspector's write path), then
## calls layer.emit_changed() once per touched layer. This is the undo/redo
## writer for the randomize action (gst_main_panel.gd _on_randomize_pressed);
## emit_changed() does not rebuild open inspector rows, so the panel's
## _refresh_inspector is registered on the same action. A layer_id absent
## from `stack` is skipped: `changes` may be stale after a structural edit.
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


## One component of a vec2/vec3 param: the manifest min/max when declared,
## else [0, 1].
static func _random_component(param: Dictionary, rng: RandomNumberGenerator) -> float:
	var min_value: float = float(param.get("min", 0.0))
	var max_value: float = float(param.get("max", 1.0))
	return rng.randf_range(min_value, max_value)
