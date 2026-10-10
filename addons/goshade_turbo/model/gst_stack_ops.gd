@tool
class_name GSTStackOps
extends RefCounted

## Structural mutations on a GSTStack: add, duplicate, remove, reorder, slot
## assign, param links. Enforces no forward references, stable ids, refusal
## of a reorder that would put a layer above its referencer, and reset of
## slots pointing at a deleted layer to the below default.
##
## Never touches undo; mutates the GSTStack in place. GSTUndo wraps the calls.

## Entry ids that read a built-in or an image instead of computing a value
## (decision 28). Shared source predicate: is_source_layer.
const SOURCE_ENTRIES: Array[String] = ["source/texture", "source/screen", "source/image"]
## Param types a param link may drive (decision 29). color, vec3 and texture
## params do not link.
const LINKABLE_PARAM_TYPES: Array[String] = ["float", "int"]
## Range of a param link's amount (decision 29).
const LINK_AMOUNT_MIN: float = -1.0
const LINK_AMOUNT_MAX: float = 1.0


static func find_index(stack: GSTStack, layer_id: StringName) -> int:
	for i: int in range(stack.layers.size()):
		if stack.layers[i].id == layer_id:
			return i
	return -1


static func find_layer(stack: GSTStack, layer_id: StringName) -> GSTLayer:
	var idx: int = find_index(stack, layer_id)
	if idx == -1:
		return null
	return stack.layers[idx]


## Creates a new layer with the next monotonic id and appends it to the top
## of the stack. `is_generator` allocates a coord block.
static func add_layer(stack: GSTStack, entry: String, kind_out: GSTLayer.Kind, is_generator: bool = false) -> GSTLayer:
	var layer: GSTLayer = GSTLayer.new()
	layer.id = StringName(str(stack.next_id))
	stack.next_id += 1
	layer.entry = entry
	layer.kind_out = kind_out
	if is_generator:
		layer.coord = GSTCoordBlock.new()
	stack.layers.append(layer)
	return layer


## Copies `layer_id` into a new layer with the next monotonic id, inserted
## directly above the original (decision 24). `slots`, `params` and
## `param_links` are deep copies; Dictionary.duplicate(true) keeps Object
## values by reference, so a texture param shares the original Texture2D.
## The coord block is copied field by field into a new GSTCoordBlock.
## Label: the original label, or its function name when empty, plus " copy".
## `library` resolves the function name; without it the bound manifest, then
## the entry id, stands in. Returns null for an unknown id.
static func duplicate_layer(stack: GSTStack, layer_id: StringName, library: GSTLibrary = null) -> GSTLayer:
	var idx: int = find_index(stack, layer_id)
	if idx == -1:
		return null
	var original: GSTLayer = stack.layers[idx]
	var copy: GSTLayer = GSTLayer.new()
	copy.id = StringName(str(stack.next_id))
	stack.next_id += 1
	copy.entry = original.entry
	copy.kind_out = original.kind_out
	copy.manifest = original.manifest
	copy.slots = original.slots.duplicate(true)
	copy.params = original.params.duplicate(true)
	copy.param_links = original.param_links.duplicate(true)
	copy.enabled = original.enabled
	copy.label = "%s copy" % display_name(original, library)
	if original.coord != null:
		copy.coord = GSTCoordBlock.new()
		copy.coord.scale = original.coord.scale
		copy.coord.offset = original.coord.offset
		copy.coord.rotation = original.coord.rotation
		copy.coord.scroll = original.coord.scroll
		copy.coord.warp_x = original.coord.warp_x
		copy.coord.warp_y = original.coord.warp_y
		copy.coord.warp_strength = original.coord.warp_strength
	stack.layers.insert(idx + 1, copy)
	return copy


## The name a user sees for `layer`: its label, or its function name when the
## label is empty (decision 25). The function name resolves through
## `library`, then the bound `manifest`, then falls back to the entry id.
static func display_name(layer: GSTLayer, library: GSTLibrary = null) -> String:
	if not layer.label.is_empty():
		return layer.label
	if library != null:
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		if entry != null:
			return entry.function
	if layer.manifest != null:
		return layer.manifest.function
	return layer.entry


## Bypass eligibility (decision 26). Generators, sources and every layer whose
## manifest declares no inputs have nothing to pass through, so they refuse;
## this includes the operators color/fill and generative/clock. The reason is
## shown beside the toggle and names the layer.
static func can_bypass(stack: GSTStack, layer_id: StringName, library: GSTLibrary) -> Dictionary:
	var layer: GSTLayer = find_layer(stack, layer_id)
	if layer == null:
		return {"ok": false, "reason": "This layer no longer exists."}
	if library == null:
		return {"ok": false, "reason": "can_bypass requires a library (caller bug)"}
	var entry: GSTManifestEntry = library.get_entry(layer.entry)
	var layer_name: String = display_name(layer, library)
	if entry == null:
		return {"ok": false, "reason": "%s cannot be bypassed: its function is missing from the library." % layer_name}
	if entry.is_source():
		return {"ok": false, "reason": "%s is a source and has no input to pass through." % layer_name}
	if entry.coord:
		return {"ok": false, "reason": "%s is a generator and has no input to pass through." % layer_name}
	if entry.inputs.is_empty():
		return {"ok": false, "reason": "%s has no input to pass through." % layer_name}
	return {"ok": true, "reason": ""}


## Initializes every declared manifest input from the layer immediately
## below `layer_id`. Ordinary kind differences are legal because codegen
## converts them. A samples_source entry initializes only from an immediate
## source layer (is_source_layer) and never searches farther down the stack.
static func initialize_inputs_from_immediate_below(stack: GSTStack, layer_id: StringName, library: GSTLibrary) -> Dictionary:
	var layer: GSTLayer = find_layer(stack, layer_id)
	if layer == null:
		return {"ok": false, "reason": "layer %s not found" % String(layer_id)}
	if library == null:
		return {"ok": false, "reason": "input initialization requires a library (caller bug)"}
	var entry: GSTManifestEntry = library.get_entry(layer.entry)
	if entry == null:
		return {"ok": false, "reason": "entry %s not found in library" % layer.entry}
	var layer_idx: int = find_index(stack, layer_id)
	if layer_idx <= 0:
		return {"ok": true, "reason": ""}
	var lower: GSTLayer = stack.layers[layer_idx - 1]
	if entry.samples_source and not is_source_layer(stack, lower.id):
		return {"ok": true, "reason": ""}
	for input: Dictionary in entry.inputs:
		layer.slots[String(input["name"])] = lower.id
	return {"ok": true, "reason": ""}


## Removes a layer by id. Every slot and coord warp reference that pointed at
## it resets to the below default; every param link targeting it is cleared,
## which returns that param to its base slider value (decision 29).
##
## `library` resolves each referencing layer's entry to check
## `samples_source`. When the reset target for a `samples_source` slot is not
## a source layer (is_source_layer), the slot is left empty; codegen then
## refuses that layer instead of sampling a non-source. A null library is a
## caller bug: returns an empty list without deleting. An unresolved entry
## keeps the below-default behavior; coord warp refs are unaffected.
##
## Returns the ids of the layers whose references changed (decision 22).
## `report`, when passed, receives one entry per cleared reference in the
## edges_of shape plus the holder: {layer, kind, name, target}, so the caller
## can name the slot, warp or linked param that changed.
static func remove_layer(stack: GSTStack, layer_id: StringName, library: GSTLibrary, report: Array[Dictionary] = []) -> Array[StringName]:
	var changed: Array[StringName] = []
	var idx: int = find_index(stack, layer_id)
	if idx == -1 or library == null:
		return changed
	stack.layers.remove_at(idx)
	for layer: GSTLayer in stack.layers:
		var cleared: Array[Dictionary] = []
		for edge: Dictionary in edges_of(layer):
			if edge["target"] == layer_id:
				cleared.append(edge)
		if cleared.is_empty():
			continue
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		var reset_id: StringName = _below_default(stack, layer.id)
		for edge: Dictionary in cleared:
			match String(edge["kind"]):
				"slot":
					var slot_key: Variant = _slot_key(layer, String(edge["name"]))
					if entry != null and entry.samples_source and not is_source_layer(stack, reset_id):
						layer.slots[slot_key] = &""
					else:
						layer.slots[slot_key] = reset_id
				"warp_x":
					layer.coord.warp_x = reset_id
				"warp_y":
					layer.coord.warp_y = reset_id
				"link":
					layer.param_links.erase(edge["name"])
			var entry_report: Dictionary = {"layer": layer.id}
			entry_report.merge(edge)
			report.append(entry_report)
		changed.append(layer.id)
	return changed


## The below default for `referencer_id`: the id of the layer immediately
## below it in the current stack order, or "" when it is now the bottom.
static func _below_default(stack: GSTStack, referencer_id: StringName) -> StringName:
	var idx: int = find_index(stack, referencer_id)
	if idx <= 0:
		return &""
	return stack.layers[idx - 1].id


## The `slots` key whose String form is `slot_name`. Keys are String after a
## .tres load but may be StringName when set in code; writing back through
## the found key keeps one entry per slot.
static func _slot_key(layer: GSTLayer, slot_name: String) -> Variant:
	for key: Variant in layer.slots.keys():
		if String(key) == slot_name:
			return key
	return slot_name


## True when `target_id` names a layer in `stack` whose entry is in
## SOURCE_ENTRIES: source/texture, source/screen or source/image (decision
## 28). Empty or unknown ids are not a source.
static func is_source_layer(stack: GSTStack, target_id: StringName) -> bool:
	if target_id == &"":
		return false
	var target_layer: GSTLayer = find_layer(stack, target_id)
	if target_layer == null:
		return false
	return target_layer.entry in SOURCE_ENTRIES


## Alias for is_source_layer until the codegen and main panel call sites
## migrate (decision 28 rollout). Remove with the last caller.
static func _is_source_layer(stack: GSTStack, target_id: StringName) -> bool:
	return is_source_layer(stack, target_id)


## Every direct edge `layer` reads through, named (decision 35):
## {kind: "slot" | "warp_x" | "warp_y" | "link", name: String, target}.
## `name` is the slot name, the warp field name, or the linked param name.
## Order: slots, warp_x, warp_y, links. Empty targets are omitted.
static func edges_of(layer: GSTLayer) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	for slot_name: Variant in layer.slots.keys():
		var ref_id: StringName = layer.slots[slot_name]
		if ref_id != &"":
			edges.append({"kind": "slot", "name": String(slot_name), "target": ref_id})
	if layer.coord != null:
		if layer.coord.warp_x != &"":
			edges.append({"kind": "warp_x", "name": "warp_x", "target": layer.coord.warp_x})
		if layer.coord.warp_y != &"":
			edges.append({"kind": "warp_y", "name": "warp_y", "target": layer.coord.warp_y})
	for param_name: Variant in layer.param_links.keys():
		var link: Dictionary = layer.param_links[param_name]
		var link_target: StringName = StringName(link.get("target", &""))
		if link_target != &"":
			edges.append({"kind": "link", "name": String(param_name), "target": link_target})
	return edges


## Every layer id `layer` reads from: the targets of edges_of, in its order.
static func _references_of(layer: GSTLayer) -> Array[StringName]:
	var refs: Array[StringName] = []
	for edge: Dictionary in edges_of(layer):
		refs.append(edge["target"])
	return refs


## Moves the layer to `new_index`. Refused, with a reason, when the move
## would leave any layer referencing something at or above its own position
## (moving a layer above its referencer, or below something it references).
## A param link edge refuses with a reason naming both layers and the param
## (decision 29); slot and warp edges keep the id-based reason.
static func reorder_layer(stack: GSTStack, layer_id: StringName, new_index: int) -> Dictionary:
	var old_idx: int = find_index(stack, layer_id)
	if old_idx == -1:
		return {"ok": false, "reason": "layer %s not found" % String(layer_id)}
	var clamped_index: int = clampi(new_index, 0, stack.layers.size() - 1)
	if clamped_index == old_idx:
		return {"ok": true, "reason": ""}

	var sim: Array[GSTLayer] = stack.layers.duplicate()
	var moved: GSTLayer = sim[old_idx]
	sim.remove_at(old_idx)
	sim.insert(clamped_index, moved)

	var index_of: Dictionary = {}
	for i: int in range(sim.size()):
		index_of[sim[i].id] = i

	for i: int in range(sim.size()):
		var l: GSTLayer = sim[i]
		for edge: Dictionary in edges_of(l):
			var ref_id: StringName = edge["target"]
			var ref_idx: Variant = index_of.get(ref_id, -1)
			if ref_idx == -1:
				continue
			if ref_idx >= i:
				if edge["kind"] == "link":
					var target_layer: GSTLayer = sim[ref_idx]
					return {
						"ok": false,
						"reason": "%s links %s to %s, which would be at or above it after this move" % [display_name(l), String(edge["name"]), display_name(target_layer)],
					}
				return {
					"ok": false,
					"reason": "layer %s references layer %s, which would be at or above it after this move" % [String(l.id), String(ref_id)],
				}

	stack.layers = sim
	return {"ok": true, "reason": ""}


## Assigns `target_id` to `slot_name` on `layer_id`. Refused, with a reason,
## when the target is not an earlier layer in the stack.
##
## The assigning layer's entry must resolve through `library` to check
## `samples_source`; an unresolved entry or a null library refuses and leaves
## the slot unchanged. A `samples_source` slot refuses a target that is not a
## "source/texture" or "source/screen" layer, which also refuses
## filter-of-filter.
##
## An empty target clears the slot, except a `samples_source` slot, which
## only remove_layer's reset may leave empty.
static func assign_slot(stack: GSTStack, layer_id: StringName, slot_name: String, target_id: StringName, library: GSTLibrary) -> Dictionary:
	var validation: Dictionary = validate_slot_assignment(stack, layer_id, slot_name, target_id, library)
	if not validation["ok"]:
		return validation
	var layer: GSTLayer = find_layer(stack, layer_id)
	layer.slots[slot_name] = target_id
	return {"ok": true, "reason": ""}


## Read-only counterpart to assign_slot for callers that need eligibility
## without mutation.
static func validate_slot_assignment(stack: GSTStack, layer_id: StringName, slot_name: String, target_id: StringName, library: GSTLibrary) -> Dictionary:
	var layer: GSTLayer = find_layer(stack, layer_id)
	if layer == null:
		return {"ok": false, "reason": "layer %s not found" % String(layer_id)}
	if library == null:
		return {"ok": false, "reason": "assign_slot requires a library to check samples_source (caller bug)"}

	var entry: GSTManifestEntry = library.get_entry(layer.entry)
	if entry == null:
		return {
			"ok": false,
			"reason": "layer %s has unresolved entry %s: cannot verify samples_source against the given library (assign_slot refused)" % [String(layer_id), layer.entry],
		}
	if not _manifest_has_input(entry, slot_name):
		return {"ok": false, "reason": "slot %s is not declared by layer %s entry %s" % [slot_name, String(layer_id), entry.id]}

	if target_id == &"":
		if entry.samples_source:
			return {
				"ok": false,
				"reason": "slot %s on layer %s samples a source and cannot be cleared directly" % [slot_name, String(layer_id)],
			}
		return {"ok": true, "reason": ""}

	var layer_idx: int = find_index(stack, layer_id)
	var target_idx: int = find_index(stack, target_id)
	if target_idx == -1:
		return {"ok": false, "reason": "layer %s not found" % String(target_id)}
	if target_idx >= layer_idx:
		return {
			"ok": false,
			"reason": "layer %s cannot reference layer %s: not earlier in the stack" % [String(layer_id), String(target_id)],
		}

	if entry.samples_source and not is_source_layer(stack, target_id):
		var target_layer: GSTLayer = stack.layers[target_idx]
		return {
			"ok": false,
			"reason": "slot %s on layer %s requires a texture, screen or image source layer; layer %s (%s) is not a source" % [slot_name, String(layer_id), String(target_id), target_layer.entry],
		}
	return {"ok": true, "reason": ""}


## Read-only eligibility for linking `param_name` on `layer_id` to
## `target_id` (decision 29). Refused when the param is not float or int
## (filter GST_PARAM params are ordinary manifest params and qualify; color,
## vec3 and texture refuse), or when the target is not below the linker.
## A field target drives the param directly; a color target converts via
## luma at codegen (decision 2), so both kinds GSTLayer.Kind has qualify.
## Reasons are user-facing and name layers by display_name.
static func validate_param_link(stack: GSTStack, layer_id: StringName, param_name: String, target_id: StringName, library: GSTLibrary) -> Dictionary:
	var layer: GSTLayer = find_layer(stack, layer_id)
	if layer == null:
		return {"ok": false, "reason": "This layer no longer exists."}
	if library == null:
		return {"ok": false, "reason": "validate_param_link requires a library (caller bug)"}
	var entry: GSTManifestEntry = library.get_entry(layer.entry)
	var layer_name: String = display_name(layer, library)
	if entry == null:
		return {"ok": false, "reason": "%s cannot link: its function is missing from the library." % layer_name}
	var param: Dictionary = {}
	for candidate: Dictionary in entry.params:
		if String(candidate.get("name", "")) == param_name:
			param = candidate
			break
	if param.is_empty():
		return {"ok": false, "reason": "%s has no setting named %s." % [layer_name, param_name]}
	var param_type: String = String(param.get("type", ""))
	if param_type not in LINKABLE_PARAM_TYPES:
		return {"ok": false, "reason": "%s on %s is a %s setting; only number settings can link to a layer." % [param_name, layer_name, param_type]}
	var target_idx: int = find_index(stack, target_id)
	if target_idx == -1:
		return {"ok": false, "reason": "The layer to link to no longer exists."}
	var target_layer: GSTLayer = stack.layers[target_idx]
	if target_idx >= find_index(stack, layer_id):
		return {"ok": false, "reason": "%s can only link to a layer below it; %s is not below." % [layer_name, display_name(target_layer, library)]}
	return {"ok": true, "reason": ""}


## Links `param_name` on `layer_id` to `target_id` with `amount` clamped to
## LINK_AMOUNT_MIN..LINK_AMOUNT_MAX (decision 29). Checks only that both
## layers exist and the target sits below; param type eligibility needs the
## library, so callers run validate_param_link first, the same split as
## validate_slot_assignment. Replaces an existing link on the param.
static func set_param_link(stack: GSTStack, layer_id: StringName, param_name: String, target_id: StringName, amount: float) -> Dictionary:
	var layer_idx: int = find_index(stack, layer_id)
	if layer_idx == -1:
		return {"ok": false, "reason": "This layer no longer exists."}
	var target_idx: int = find_index(stack, target_id)
	if target_idx == -1:
		return {"ok": false, "reason": "The layer to link to no longer exists."}
	var layer: GSTLayer = stack.layers[layer_idx]
	if target_idx >= layer_idx:
		return {"ok": false, "reason": "%s can only link to a layer below it; %s is not below." % [display_name(layer), display_name(stack.layers[target_idx])]}
	layer.param_links[param_name] = {"target": target_id, "amount": clampf(amount, LINK_AMOUNT_MIN, LINK_AMOUNT_MAX)}
	return {"ok": true, "reason": ""}


## Erases the link on `param_name`, leaving the base slider value as the
## param's value (decision 30). Returns true when a link was erased.
static func clear_param_link(stack: GSTStack, layer_id: StringName, param_name: String) -> bool:
	var layer: GSTLayer = find_layer(stack, layer_id)
	if layer == null:
		return false
	return layer.param_links.erase(param_name)


static func _manifest_has_input(entry: GSTManifestEntry, slot_name: String) -> bool:
	for input: Dictionary in entry.inputs:
		if String(input["name"]) == slot_name:
			return true
	return false
