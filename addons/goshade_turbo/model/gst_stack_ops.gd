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


## Removes a layer by id. Every slot and coord warp reference that pointed at
## it resets to the below default (decision 3: below is the default
## selection). Returns the ids of the layers whose references changed.
static func remove_layer(stack: GSTStack, layer_id: StringName) -> Array[StringName]:
	var changed: Array[StringName] = []
	var idx: int = find_index(stack, layer_id)
	if idx == -1:
		return changed
	stack.layers.remove_at(idx)
	for layer: GSTLayer in stack.layers:
		var layer_changed: bool = false
		for slot_name: Variant in layer.slots.keys():
			if layer.slots[slot_name] == layer_id:
				layer.slots[slot_name] = _below_default(stack, layer.id)
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
## forward references). Passing an empty target clears the slot.
static func assign_slot(stack: GSTStack, layer_id: StringName, slot_name: String, target_id: StringName) -> Dictionary:
	var layer: GSTLayer = find_layer(stack, layer_id)
	if layer == null:
		return {"ok": false, "reason": "layer %s not found" % String(layer_id)}
	if target_id == &"":
		layer.slots[slot_name] = &""
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

	layer.slots[slot_name] = target_id
	return {"ok": true, "reason": ""}
