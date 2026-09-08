@tool
class_name GSTUndo
extends RefCounted

## Wraps EditorUndoRedoManager for every structural stack edit (decision 20):
## add, remove, reorder, slot change, warp slot change, output color change,
## output alpha change. Slider edits come free from the inspector and never
## go through this file.
##
## Pattern: every front-door method applies the mutation directly (via
## GSTStackOps where one exists), registers a do/undo pair of raw appliers
## plus a do/undo pair of _notify calls, then commits with
## commit_action(false) since the mutation is already applied. Because
## commit_action(false) never invokes the do methods, each front-door method
## also calls _notify() once directly after commit, so
## GSTMainPanel.stack_changed fires on the initial edit and on every later
## undo/redo alike. A refused edit performs no mutation and registers no undo
## action; a reorder that resolves to the layer's current index likewise
## registers nothing (docs/PLAN.md Phase 4 Verification: "A reorder that
## would move a layer above one it references shows the refusal reason ...
## rather than performing it").
##
## Layer ids are never reused on undo of an add (decision 22): undo removes
## the layer from the array but never touches stack.next_id.

var _undo_redo: EditorUndoRedoManager
var _stack: GSTStack
var _library: GSTLibrary
## Called after every do and undo, so the panel can resync its columns.
var _on_changed: Callable


func _init(undo_redo: EditorUndoRedoManager, stack: GSTStack, library: GSTLibrary, on_changed: Callable) -> void:
	_undo_redo = undo_redo
	_stack = stack
	_library = library
	_on_changed = on_changed


## custom_context = _stack is required: without it, EditorUndoRedoManager
## binds create_action() to whatever object the editor last inspected, not a
## stable bucket, desyncing get_object_history_id(stack) from the actions
## actually created (docs/EDITOR_SMOKE.md phase 4 fail-then-fix note).
func _create_action(name: String) -> void:
	_undo_redo.create_action(name, UndoRedo.MERGE_DISABLE, _stack)


## Creates a new layer with the next monotonic id and appends it to the top
## of the stack (decision 22). Returns the new layer.
func add_layer(entry_id: String, kind_out: GSTLayer.Kind, is_generator: bool) -> GSTLayer:
	var layer: GSTLayer = GSTStackOps.add_layer(_stack, entry_id, kind_out, is_generator)
	layer.manifest = _library.get_entry(entry_id)
	_create_action("GST: add %s" % entry_id)
	_undo_redo.add_do_method(self, "_redo_add", layer)
	_undo_redo.add_undo_method(self, "_undo_add", layer.id)
	_undo_redo.add_do_method(self, "_notify")
	_undo_redo.add_undo_method(self, "_notify")
	_undo_redo.commit_action(false)
	_notify()
	return layer


func _redo_add(layer: GSTLayer) -> void:
	_stack.layers.append(layer)


func _undo_add(layer_id: StringName) -> void:
	var idx: int = GSTStackOps.find_index(_stack, layer_id)
	if idx != -1:
		_stack.layers.remove_at(idx)


## Decision 22: undo reinserts the removed layer's own instance at its own
## index and writes the pre-removal values back onto the surviving layers'
## own slot/coord-warp dictionaries, rather than restoring a duplicated
## snapshot array. A duplicated snapshot would detach every surviving layer
## from the instances EditorInspector's property undo already points at
## (phase 4 fix pass 3, item 1): an inspector slider edit made before a
## remove, undone after that remove is itself undone, must still land on the
## same GSTLayer/GSTCoordBlock the inspector is editing.
##
## Also snapshots stack.output_color and stack.output_alpha: a deleted layer
## id left in either field would make codegen resolve a dangling reference
## instead of falling back to decision 12's default (docs/PLAN.md phase 4 fix
## pass 2, item 2), so removal clears a matching output_color/output_alpha to
## &"" and undo/redo restore or reproduce that clear alongside the layer.
func remove_layer(layer_id: StringName) -> void:
	var removed_index: int = GSTStackOps.find_index(_stack, layer_id)
	if removed_index == -1:
		return
	var removed_layer: GSTLayer = _stack.layers[removed_index]
	var slot_snapshot: Array[Dictionary] = _snapshot_referencing_slots(layer_id)
	var warp_snapshot: Array[Dictionary] = _snapshot_referencing_warps(layer_id)
	var output_color_snapshot: StringName = _stack.output_color
	var output_alpha_snapshot: StringName = _stack.output_alpha
	GSTStackOps.remove_layer(_stack, layer_id, _library)
	_clear_output_refs(layer_id)
	_create_action("GST: remove %s" % String(layer_id))
	_undo_redo.add_do_method(self, "_redo_remove", removed_layer)
	_undo_redo.add_undo_method(self, "_undo_remove", removed_layer, removed_index, slot_snapshot, warp_snapshot, output_color_snapshot, output_alpha_snapshot)
	_undo_redo.add_do_method(self, "_notify")
	_undo_redo.add_undo_method(self, "_notify")
	_undo_redo.commit_action(false)
	_notify()


func _redo_remove(layer: GSTLayer) -> void:
	GSTStackOps.remove_layer(_stack, layer.id, _library)
	_clear_output_refs(layer.id)


func _clear_output_refs(layer_id: StringName) -> void:
	if _stack.output_color == layer_id:
		_stack.output_color = &""
	if _stack.output_alpha == layer_id:
		_stack.output_alpha = &""


## Every (layer, slot_name) pair in the stack, other than layer_id itself,
## whose slot currently points at layer_id, captured before removal so undo
## can write the reference back onto the same GSTLayer instance rather than a
## duplicate. The captured value is always layer_id (that is what "pointing
## at it" means), kept explicit rather than assumed at the write-back site.
func _snapshot_referencing_slots(layer_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for layer: GSTLayer in _stack.layers:
		if layer.id == layer_id:
			continue
		for slot_name: Variant in layer.slots.keys():
			if layer.slots[slot_name] == layer_id:
				out.append({"layer": layer, "slot_name": String(slot_name), "value": layer_id})
	return out


## Same as _snapshot_referencing_slots for coord-block warp_x/warp_y, which
## live on GSTCoordBlock rather than in GSTLayer.slots.
func _snapshot_referencing_warps(layer_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for layer: GSTLayer in _stack.layers:
		if layer.id == layer_id or layer.coord == null:
			continue
		if layer.coord.warp_x == layer_id:
			out.append({"coord": layer.coord, "axis": "x", "value": layer_id})
		if layer.coord.warp_y == layer_id:
			out.append({"coord": layer.coord, "axis": "y", "value": layer_id})
	return out


func _undo_remove(layer: GSTLayer, index: int, slot_snapshot: Array[Dictionary], warp_snapshot: Array[Dictionary], output_color: StringName, output_alpha: StringName) -> void:
	_stack.layers.insert(clampi(index, 0, _stack.layers.size()), layer)
	for ref: Dictionary in slot_snapshot:
		(ref["layer"] as GSTLayer).slots[ref["slot_name"]] = ref["value"]
	for ref: Dictionary in warp_snapshot:
		var coord: GSTCoordBlock = ref["coord"]
		if ref["axis"] == "x":
			coord.warp_x = ref["value"]
		else:
			coord.warp_y = ref["value"]
	_stack.output_color = output_color
	_stack.output_alpha = output_alpha


## Moves layer_id to new_index. Refused, with a reason, when the move would
## leave a forward reference (decision 22); nothing is mutated and no undo
## action is registered on refusal.
func reorder_layer(layer_id: StringName, new_index: int) -> Dictionary:
	var old_index: int = GSTStackOps.find_index(_stack, layer_id)
	var result: Dictionary = GSTStackOps.reorder_layer(_stack, layer_id, new_index)
	if not result["ok"]:
		return result
	var applied_index: int = GSTStackOps.find_index(_stack, layer_id)
	if applied_index == old_index:
		return result
	_create_action("GST: reorder %s" % String(layer_id))
	_undo_redo.add_do_method(self, "_raw_reorder", layer_id, applied_index)
	_undo_redo.add_undo_method(self, "_raw_reorder", layer_id, old_index)
	_undo_redo.add_do_method(self, "_notify")
	_undo_redo.add_undo_method(self, "_notify")
	_undo_redo.commit_action(false)
	_notify()
	return result


func _raw_reorder(layer_id: StringName, target_index: int) -> void:
	var idx: int = GSTStackOps.find_index(_stack, layer_id)
	if idx == -1:
		return
	var moved: GSTLayer = _stack.layers[idx]
	_stack.layers.remove_at(idx)
	_stack.layers.insert(clampi(target_index, 0, _stack.layers.size()), moved)


## Assigns target_id to slot_name on layer_id (decision 3, decision 21/B6).
## Refused, with a reason, and no mutation, per GSTStackOps.assign_slot.
func assign_slot(layer_id: StringName, slot_name: String, target_id: StringName) -> Dictionary:
	var layer: GSTLayer = GSTStackOps.find_layer(_stack, layer_id)
	var old_target: StringName = &""
	if layer != null:
		old_target = layer.slots.get(slot_name, &"")
	var result: Dictionary = GSTStackOps.assign_slot(_stack, layer_id, slot_name, target_id, _library)
	if not result["ok"]:
		return result
	_create_action("GST: wire %s.%s" % [String(layer_id), slot_name])
	_undo_redo.add_do_method(self, "_raw_set_slot", layer_id, slot_name, target_id)
	_undo_redo.add_undo_method(self, "_raw_set_slot", layer_id, slot_name, old_target)
	_undo_redo.add_do_method(self, "_notify")
	_undo_redo.add_undo_method(self, "_notify")
	_undo_redo.commit_action(false)
	_notify()
	return result


func _raw_set_slot(layer_id: StringName, slot_name: String, target_id: StringName) -> void:
	var layer: GSTLayer = GSTStackOps.find_layer(_stack, layer_id)
	if layer != null:
		layer.slots[slot_name] = target_id


## Assigns target_id to a generator's coord.warp_x or coord.warp_y
## (decision 4: warp slots take fields only, no auto-conversion). No
## GSTStackOps entry point exists for coord warp slots (they are not
## GSTLayer.slots entries), so the no-forward-reference and field-kind rules
## are checked here directly, scoped to this file.
func assign_warp(layer_id: StringName, axis: String, target_id: StringName) -> Dictionary:
	var layer: GSTLayer = GSTStackOps.find_layer(_stack, layer_id)
	if layer == null:
		return {"ok": false, "reason": "layer %s not found" % String(layer_id)}
	if layer.coord == null:
		return {"ok": false, "reason": "layer %s has no coord block" % String(layer_id)}
	if axis != "x" and axis != "y":
		return {"ok": false, "reason": "unknown warp axis %s" % axis}

	var old_target: StringName = layer.coord.warp_x if axis == "x" else layer.coord.warp_y

	if target_id != &"":
		var layer_idx: int = GSTStackOps.find_index(_stack, layer_id)
		var target_idx: int = GSTStackOps.find_index(_stack, target_id)
		if target_idx == -1:
			return {"ok": false, "reason": "layer %s not found" % String(target_id)}
		if target_idx >= layer_idx:
			return {
				"ok": false,
				"reason": "layer %s cannot warp from layer %s: not earlier in the stack" % [String(layer_id), String(target_id)],
			}
		var target_layer: GSTLayer = _stack.layers[target_idx]
		if target_layer.kind_out != GSTLayer.Kind.FIELD:
			return {
				"ok": false,
				"reason": "warp_%s on layer %s requires a field-kind layer; layer %s is color" % [axis, String(layer_id), String(target_id)],
			}

	_raw_set_warp(layer_id, axis, target_id)
	_create_action("GST: warp_%s %s" % [axis, String(layer_id)])
	_undo_redo.add_do_method(self, "_raw_set_warp", layer_id, axis, target_id)
	_undo_redo.add_undo_method(self, "_raw_set_warp", layer_id, axis, old_target)
	_undo_redo.add_do_method(self, "_notify")
	_undo_redo.add_undo_method(self, "_notify")
	_undo_redo.commit_action(false)
	_notify()
	return {"ok": true, "reason": ""}


func _raw_set_warp(layer_id: StringName, axis: String, target_id: StringName) -> void:
	var layer: GSTLayer = GSTStackOps.find_layer(_stack, layer_id)
	if layer == null or layer.coord == null:
		return
	if axis == "x":
		layer.coord.warp_x = target_id
	else:
		layer.coord.warp_y = target_id


## Sets stack.output_color. Any layer in the stack is a legal target (a
## field layer is allowed and converts to grayscale, docs/PLAN.md Phase 4
## Files).
func set_output_color(layer_id: StringName) -> Dictionary:
	if layer_id != &"" and GSTStackOps.find_layer(_stack, layer_id) == null:
		return {"ok": false, "reason": "layer %s not found" % String(layer_id)}
	var old_value: StringName = _stack.output_color
	_raw_set_output_color(layer_id)
	_create_action("GST: output color %s" % String(layer_id))
	_undo_redo.add_do_method(self, "_raw_set_output_color", layer_id)
	_undo_redo.add_undo_method(self, "_raw_set_output_color", old_value)
	_undo_redo.add_do_method(self, "_notify")
	_undo_redo.add_undo_method(self, "_notify")
	_undo_redo.commit_action(false)
	_notify()
	return {"ok": true, "reason": ""}


func _raw_set_output_color(layer_id: StringName) -> void:
	_stack.output_color = layer_id


## Sets stack.output_alpha (decision 12): "none", "texture", "color_alpha",
## a field-kind layer id, or "" to explicitly reset to unset (the output
## block's default row, docs/PLAN.md phase 4 fix pass 2, item 5).
func set_output_alpha(value: StringName) -> Dictionary:
	if value != &"" and value != &"none" and value != &"texture" and value != &"color_alpha":
		var layer: GSTLayer = GSTStackOps.find_layer(_stack, value)
		if layer == null:
			return {"ok": false, "reason": "output alpha %s is not a known mode or layer id" % String(value)}
		if layer.kind_out != GSTLayer.Kind.FIELD:
			return {"ok": false, "reason": "output alpha layer %s must be field kind" % String(value)}
	var old_value: StringName = _stack.output_alpha
	_raw_set_output_alpha(value)
	_create_action("GST: output alpha %s" % String(value))
	_undo_redo.add_do_method(self, "_raw_set_output_alpha", value)
	_undo_redo.add_undo_method(self, "_raw_set_output_alpha", old_value)
	_undo_redo.add_do_method(self, "_notify")
	_undo_redo.add_undo_method(self, "_notify")
	_undo_redo.commit_action(false)
	_notify()
	return {"ok": true, "reason": ""}


func _raw_set_output_alpha(value: StringName) -> void:
	_stack.output_alpha = value


## Sets stack.coord_space (decision 11: uv / screen_uv / local, the stack
## column header's coord space dropdown). No slot/reference checks apply:
## coord_space is a stack-level enum, not a layer reference, so this can
## never be refused. A no-op selection (already this space) registers no
## action, same as every other GSTUndo method's no-op guard.
func set_coord_space(space: GSTStack.CoordSpace) -> Dictionary:
	var old_value: GSTStack.CoordSpace = _stack.coord_space
	if old_value == space:
		return {"ok": true, "reason": ""}
	_raw_set_coord_space(space)
	_create_action("GST: coord space %d" % space)
	_undo_redo.add_do_method(self, "_raw_set_coord_space", space)
	_undo_redo.add_undo_method(self, "_raw_set_coord_space", old_value)
	_undo_redo.add_do_method(self, "_notify")
	_undo_redo.add_undo_method(self, "_notify")
	_undo_redo.commit_action(false)
	_notify()
	return {"ok": true, "reason": ""}


func _raw_set_coord_space(space: GSTStack.CoordSpace) -> void:
	_stack.coord_space = space


## Adds a new entry_id layer directly below anchor_id and wires
## anchor_id.slot_name to it, as one compound undoable action (the inspector
## column's per-slot picker button). Ids stay monotonic regardless of the new
## layer's final position, same as every other add.
func add_layer_below_and_wire(anchor_id: StringName, entry_id: String, slot_name: String) -> Dictionary:
	var anchor_index: int = GSTStackOps.find_index(_stack, anchor_id)
	if anchor_index == -1:
		return {"ok": false, "reason": "layer %s not found" % String(anchor_id)}
	var entry: GSTManifestEntry = _library.get_entry(entry_id)
	if entry == null:
		return {"ok": false, "reason": "entry %s not found in library" % entry_id}

	var layer: GSTLayer = GSTStackOps.add_layer(_stack, entry_id, entry.kind_out, entry.coord)
	layer.manifest = entry
	_raw_reorder(layer.id, anchor_index)
	var anchor: GSTLayer = GSTStackOps.find_layer(_stack, anchor_id)
	var old_target: StringName = anchor.slots.get(slot_name, &"")
	var slot_result: Dictionary = GSTStackOps.assign_slot(_stack, anchor_id, slot_name, layer.id, _library)
	if not slot_result["ok"]:
		var idx: int = GSTStackOps.find_index(_stack, layer.id)
		if idx != -1:
			_stack.layers.remove_at(idx)
		return slot_result

	_create_action("GST: add %s below %s" % [entry_id, String(anchor_id)])
	_undo_redo.add_do_method(self, "_redo_add_below", layer, anchor_index, anchor_id, slot_name)
	_undo_redo.add_undo_method(self, "_undo_add_below", layer.id, anchor_id, slot_name, old_target)
	_undo_redo.add_do_method(self, "_notify")
	_undo_redo.add_undo_method(self, "_notify")
	_undo_redo.commit_action(false)
	_notify()
	return {"ok": true, "reason": ""}


func _redo_add_below(layer: GSTLayer, target_index: int, anchor_id: StringName, slot_name: String) -> void:
	_stack.layers.append(layer)
	_raw_reorder(layer.id, target_index)
	_raw_set_slot(anchor_id, slot_name, layer.id)


func _undo_add_below(layer_id: StringName, anchor_id: StringName, slot_name: String, old_target: StringName) -> void:
	_raw_set_slot(anchor_id, slot_name, old_target)
	var idx: int = GSTStackOps.find_index(_stack, layer_id)
	if idx != -1:
		_stack.layers.remove_at(idx)


func _notify() -> void:
	if _on_changed.is_valid():
		_on_changed.call()
