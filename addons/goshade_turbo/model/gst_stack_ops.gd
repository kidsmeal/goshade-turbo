@tool
class_name GSTStackOps
extends RefCounted

## Structural mutations on a GSTStack: add, remove, reorder, slot assign.
## Enforces decision 3 (no forward references) and decision 22 (stable ids,
## reorder-above-referencer refusal, delete resets pointing slots to the
## below default). Design: docs/DESIGN.md, decisions 3 and 22.
##
## Phase 4 wraps every call here with EditorUndoRedoManager (decision 20).
## This file never touches undo; it only mutates the GSTStack in place.


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
## of the stack. `is_generator` allocates a coord block (decision 4).
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


## Initializes every declared manifest input from the layer immediately
## below `layer_id`. Ordinary kind differences are legal because codegen
## converts them. A samples_source entry initializes only from an immediate
## texture/screen source and never searches farther down the stack.
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
	if entry.samples_source and not _is_source_layer(stack, lower.id):
		return {"ok": true, "reason": ""}
	for input: Dictionary in entry.inputs:
		layer.slots[String(input["name"])] = lower.id
	return {"ok": true, "reason": ""}


## Removes a layer by id. Every slot and coord warp reference that pointed at
## it resets to the below default (decision 3: below is the default
## selection).
##
## `library` resolves a referencing layer's own entry to check
## `samples_source` (B10, B6). When the reset target for a `samples_source`
## slot is not a "source/texture" or "source/screen" layer, the slot is left
## empty instead of pointing a filter at a non-source (the plan's
## "Unwired filter rule": codegen then refuses that layer with an
## invocation-local error rather than silently sampling the wrong thing).
## `library` is required: a null library is a caller bug and the call
## returns an empty list without deleting anything. An unresolved entry
## keeps the below-default behavior; coord warp refs are never
## samples_source slots and are unaffected. Returns the ids of the layers
## whose references changed.
static func remove_layer(stack: GSTStack, layer_id: StringName, library: GSTLibrary) -> Array[StringName]:
	var changed: Array[StringName] = []
	var idx: int = find_index(stack, layer_id)
	if idx == -1 or library == null:
		return changed
	stack.layers.remove_at(idx)
	for layer: GSTLayer in stack.layers:
		var layer_changed: bool = false
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		for slot_name: Variant in layer.slots.keys():
			if layer.slots[slot_name] == layer_id:
				var reset_id: StringName = _below_default(stack, layer.id)
				if entry != null and entry.samples_source and not _is_source_layer(stack, reset_id):
					layer.slots[slot_name] = &""
				else:
					layer.slots[slot_name] = reset_id
				layer_changed = true
		if layer.coord != null:
			if layer.coord.warp_x == layer_id:
				layer.coord.warp_x = _below_default(stack, layer.id)
				layer_changed = true
			if layer.coord.warp_y == layer_id:
				layer.coord.warp_y = _below_default(stack, layer.id)
				layer_changed = true
		if layer_changed:
			changed.append(layer.id)
	return changed


## The below default for `referencer_id`: the id of the layer immediately
## below it in the current stack order, or "" when it is now the bottom.
static func _below_default(stack: GSTStack, referencer_id: StringName) -> StringName:
	var idx: int = find_index(stack, referencer_id)
	if idx <= 0:
		return &""
	return stack.layers[idx - 1].id


## True when `target_id` names a layer in `stack` whose entry is
## "source/texture" or "source/screen" (decision 21, B6). Empty or unknown
## ids are not a source.
static func _is_source_layer(stack: GSTStack, target_id: StringName) -> bool:
	if target_id == &"":
		return false
	var target_layer: GSTLayer = find_layer(stack, target_id)
	if target_layer == null:
		return false
	return target_layer.entry == "source/texture" or target_layer.entry == "source/screen"


## Every layer id `layer` reads from: slot values plus coord warp inputs.
## Empty ids are omitted.
static func _references_of(layer: GSTLayer) -> Array[StringName]:
	var refs: Array[StringName] = []
	for slot_name: Variant in layer.slots.keys():
		var ref_id: StringName = layer.slots[slot_name]
		if ref_id != &"":
			refs.append(ref_id)
	if layer.coord != null:
		if layer.coord.warp_x != &"":
			refs.append(layer.coord.warp_x)
		if layer.coord.warp_y != &"":
			refs.append(layer.coord.warp_y)
	return refs


## Moves the layer to `new_index`. Refused, with a reason, when the move
## would leave any layer referencing something at or above its own position
## (decision 22: reordering a layer above a layer that references it, and
## its mirror, moving a layer below something it itself references, are
## both forward references and both refused).
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
		for ref_id: StringName in _references_of(l):
			var ref_idx: Variant = index_of.get(ref_id, -1)
			if ref_idx == -1:
				continue
			if ref_idx >= i:
				return {
					"ok": false,
					"reason": "layer %s references layer %s, which would be at or above it after this move" % [String(l.id), String(ref_id)],
				}

	stack.layers = sim
	return {"ok": true, "reason": ""}


## Assigns `target_id` to `slot_name` on `layer_id`. Refused, with a reason,
## when the target is not an earlier layer in the stack (decision 3: no
## forward references).
##
## `library` is required: the assigning layer's own manifest entry must
## resolve through `library` to check `samples_source` (decision 21, B6). If
## it does not resolve, the assignment is refused: an unresolved entry must
## never silently bypass the source-only rule. A `samples_source` slot
## additionally refuses a target that is not a "source/texture" or
## "source/screen" layer; filter-of-filter is refused because a filter
## layer's `entry` is neither. A `null` library is a caller bug: the
## assignment is refused and the slot is left unchanged.
##
## Passing an empty target clears the slot, except a `samples_source` slot
## cannot be cleared this way (plan Cross-cutting concern "Manifest `code`
## contracts (B10)"): a filter always samples a wired source or none at all
## by construction, never a slot the caller emptied out from under it. Only
## `remove_layer`'s decision-22 reset may leave a `samples_source` slot
## empty, when no source remains below.
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
				"reason": "slot %s on layer %s samples a source and cannot be cleared directly (decision 21, B6)" % [slot_name, String(layer_id)],
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

	if entry.samples_source:
		var target_layer: GSTLayer = stack.layers[target_idx]
		if target_layer.entry != "source/texture" and target_layer.entry != "source/screen":
			return {
				"ok": false,
				"reason": "slot %s on layer %s requires a texture or screen source layer; layer %s (%s) is not a source (decision 21, B6)" % [slot_name, String(layer_id), String(target_id), target_layer.entry],
			}
	return {"ok": true, "reason": ""}


static func _manifest_has_input(entry: GSTManifestEntry, slot_name: String) -> bool:
	for input: Dictionary in entry.inputs:
		if String(input["name"]) == slot_name:
			return true
	return false
