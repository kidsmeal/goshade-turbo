@tool
class_name GSTUndo
extends RefCounted

## Wraps a standalone UndoRedo for every stack edit: structural edits (add,
## remove, reorder, slot change, warp slot change, output color change,
## output alpha change), coord-space edits, Randomize, and native property
## edits (decision superseding 20: property edits no longer come free from an
## embedded EditorInspector; gst_inspector_column.gd finishes each native
## gesture and routes the result here).
##
## Pattern: every front-door method applies the mutation directly (via
## GSTStackOps where one exists), registers a do/undo pair of bound Callables
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
##
## Phase 2 (docs/SHADER_TABS_reviewed-plan.md): the shared, abstract
## EditorUndoRedoManager and its path-less history-anchor Resource are gone.
## _undo_redo is a plain UndoRedo the panel owns directly (one per document
## from phase 3 on; one panel-owned instance in this interim phase). A
## standalone UndoRedo has exactly one history bucket, so no custom_context
## routing or get_object_history_id() lookup is needed at all: every action
## created here always lands in the one bucket _undo_redo already is.
## add_do_method/add_undo_method take bound Callables (self._method.bind(...))
## rather than the manager's (object, method_name, *varargs) overload.
var _undo_redo: UndoRedo
var _stack: GSTStack
var _library: GSTLibrary
## Called after every do and undo of a structural edit, coord-space edit,
## Randomize, or "Replace stack" action, so the panel can rebuild its columns
## (a layer's own identity, slots, or manifest can change under these).
var _on_changed: Callable
## Called after every do and undo of a native property edit specifically
## (commit_property_change). Deliberately lighter than _on_changed: a
## property edit never changes which layer is selected or what it
## references, so this must only resync the material, never rebuild/free the
## row gst_inspector_column.gd's own commit (or a later undo/redo of it) is
## running on.
var _on_property_changed: Callable


func _init(undo_redo: UndoRedo, stack: GSTStack, library: GSTLibrary, on_changed: Callable, on_property_changed: Callable) -> void:
	_undo_redo = undo_redo
	_stack = stack
	_library = library
	_on_changed = on_changed
	_on_property_changed = on_property_changed


func _create_action(name: String) -> void:
	_undo_redo.create_action(name, UndoRedo.MERGE_DISABLE)


## Creates a new layer with the next monotonic id and appends it to the top
## of the stack (decision 22). Returns the new layer.
func add_layer(entry_id: String, kind_out: GSTLayer.Kind, is_generator: bool) -> GSTLayer:
	var layer: GSTLayer = GSTStackOps.add_layer(_stack, entry_id, kind_out, is_generator)
	layer.manifest = _library.get_entry(entry_id)
	_create_action("GST: add %s" % entry_id)
	_undo_redo.add_do_method(_redo_add.bind(layer))
	_undo_redo.add_undo_method(_undo_add.bind(layer.id))
	_undo_redo.add_do_method(_notify)
	_undo_redo.add_undo_method(_notify)
	_undo_redo.commit_action(false)
	_notify()
	return layer


## UI Add Layer operation (redesign decisions 17 and 19). The low-level
## add_layer method above stays unchanged for fixtures and existing saved
## stacks; this path initializes declared inputs and assigns output_color in
## the same history action as creation.
func add_layer_for_ui(entry_id: String) -> Dictionary:
	var entry: GSTManifestEntry = _library.get_entry(entry_id)
	if entry == null:
		return {"ok": false, "reason": "entry %s not found in library" % entry_id, "layer": null}
	if _stack.layers.is_empty() and not entry.inputs.is_empty():
		return {"ok": false, "reason": "The first layer must work without another layer as input.", "layer": null}
	var old_output_color: StringName = _stack.output_color
	var layer: GSTLayer = GSTStackOps.add_layer(_stack, entry_id, entry.kind_out, entry.coord)
	layer.manifest = entry
	GSTStackOps.initialize_inputs_from_immediate_below(_stack, layer.id, _library)
	_stack.output_color = layer.id
	_create_action("GST: add %s" % entry_id)
	_undo_redo.add_do_method(_redo_add_for_ui.bind(layer))
	_undo_redo.add_undo_method(_undo_add_for_ui.bind(layer.id, old_output_color))
	_undo_redo.add_do_method(_notify)
	_undo_redo.add_undo_method(_notify)
	_undo_redo.commit_action(false)
	_notify()
	return {"ok": true, "reason": "", "layer": layer}


func _redo_add_for_ui(layer: GSTLayer) -> void:
	_stack.layers.append(layer)
	_stack.output_color = layer.id


func _undo_add_for_ui(layer_id: StringName, old_output_color: StringName) -> void:
	var idx: int = GSTStackOps.find_index(_stack, layer_id)
	if idx != -1:
		_stack.layers.remove_at(idx)
	_stack.output_color = old_output_color


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
## from the instance its own native property rows already point at (phase 4
## fix pass 3, item 1): a property edit made before a remove, undone after
## that remove is itself undone, must still land on the same
## GSTLayer/GSTCoordBlock the inspector column is editing.
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
	_undo_redo.add_do_method(_redo_remove.bind(removed_layer))
	_undo_redo.add_undo_method(_undo_remove.bind(removed_layer, removed_index, slot_snapshot, warp_snapshot, output_color_snapshot, output_alpha_snapshot))
	_undo_redo.add_do_method(_notify)
	_undo_redo.add_undo_method(_notify)
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
	_undo_redo.add_do_method(_raw_reorder.bind(layer_id, applied_index))
	_undo_redo.add_undo_method(_raw_reorder.bind(layer_id, old_index))
	_undo_redo.add_do_method(_notify)
	_undo_redo.add_undo_method(_notify)
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
	_undo_redo.add_do_method(_raw_set_slot.bind(layer_id, slot_name, target_id))
	_undo_redo.add_undo_method(_raw_set_slot.bind(layer_id, slot_name, old_target))
	_undo_redo.add_do_method(_notify)
	_undo_redo.add_undo_method(_notify)
	_undo_redo.commit_action(false)
	_notify()
	return result


func _raw_set_slot(layer_id: StringName, slot_name: String, target_id: StringName) -> void:
	var layer: GSTLayer = GSTStackOps.find_layer(_stack, layer_id)
	if layer != null:
		layer.slots[slot_name] = target_id


## Assigns target_id to a generator's coord.warp_x or coord.warp_y.
## Warp slots expect fields, and color targets are legal through decision
## 2's automatic luminance conversion. No
## GSTStackOps entry point exists for coord warp slots (they are not
## GSTLayer.slots entries), so no-forward-reference eligibility is checked
## here directly.
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

	_raw_set_warp(layer_id, axis, target_id)
	_create_action("GST: warp_%s %s" % [axis, String(layer_id)])
	_undo_redo.add_do_method(_raw_set_warp.bind(layer_id, axis, target_id))
	_undo_redo.add_undo_method(_raw_set_warp.bind(layer_id, axis, old_target))
	_undo_redo.add_do_method(_notify)
	_undo_redo.add_undo_method(_notify)
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
	_undo_redo.add_do_method(_raw_set_output_color.bind(layer_id))
	_undo_redo.add_undo_method(_raw_set_output_color.bind(old_value))
	_undo_redo.add_do_method(_notify)
	_undo_redo.add_undo_method(_notify)
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
	_undo_redo.add_do_method(_raw_set_output_alpha.bind(value))
	_undo_redo.add_undo_method(_raw_set_output_alpha.bind(old_value))
	_undo_redo.add_do_method(_notify)
	_undo_redo.add_undo_method(_notify)
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
	_undo_redo.add_do_method(_raw_set_coord_space.bind(space))
	_undo_redo.add_undo_method(_raw_set_coord_space.bind(old_value))
	_undo_redo.add_do_method(_notify)
	_undo_redo.add_undo_method(_notify)
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
	var anchor: GSTLayer = GSTStackOps.find_layer(_stack, anchor_id)
	var anchor_entry: GSTManifestEntry = _library.get_entry(anchor.entry)
	if anchor_entry == null:
		return {"ok": false, "reason": "layer %s has unresolved entry %s" % [String(anchor_id), anchor.entry]}
	var slot_declared: bool = false
	for input: Dictionary in anchor_entry.inputs:
		if String(input["name"]) == slot_name:
			slot_declared = true
			break
	if not slot_declared:
		return {"ok": false, "reason": "slot %s is not declared by layer %s entry %s" % [slot_name, String(anchor_id), anchor.entry]}
	if anchor_entry.samples_source and entry.id != "source/texture" and entry.id != "source/screen":
		return {"ok": false, "reason": "slot %s on layer %s requires a texture or screen source layer; entry %s is not a source" % [slot_name, String(anchor_id), entry_id]}

	var layer: GSTLayer = GSTStackOps.add_layer(_stack, entry_id, entry.kind_out, entry.coord)
	layer.manifest = entry
	_raw_reorder(layer.id, anchor_index)
	GSTStackOps.initialize_inputs_from_immediate_below(_stack, layer.id, _library)
	var old_slot_present: bool = anchor.slots.has(slot_name)
	var old_target: StringName = anchor.slots.get(slot_name, &"")
	_raw_set_slot(anchor_id, slot_name, layer.id)

	_create_action("GST: add %s below %s" % [entry_id, String(anchor_id)])
	_undo_redo.add_do_method(_redo_add_below.bind(layer, anchor_index, anchor_id, slot_name))
	_undo_redo.add_undo_method(_undo_add_below.bind(layer.id, anchor_id, slot_name, old_slot_present, old_target))
	_undo_redo.add_do_method(_notify)
	_undo_redo.add_undo_method(_notify)
	_undo_redo.commit_action(false)
	_notify()
	return {"ok": true, "reason": ""}


func _redo_add_below(layer: GSTLayer, target_index: int, anchor_id: StringName, slot_name: String) -> void:
	_stack.layers.append(layer)
	_raw_reorder(layer.id, target_index)
	_raw_set_slot(anchor_id, slot_name, layer.id)


func _undo_add_below(layer_id: StringName, anchor_id: StringName, slot_name: String, old_slot_present: bool, old_target: StringName) -> void:
	var anchor: GSTLayer = GSTStackOps.find_layer(_stack, anchor_id)
	if anchor != null:
		if old_slot_present:
			anchor.slots[slot_name] = old_target
		else:
			anchor.slots.erase(slot_name)
	var idx: int = GSTStackOps.find_index(_stack, layer_id)
	if idx != -1:
		_stack.layers.remove_at(idx)


func _notify() -> void:
	if _on_changed.is_valid():
		_on_changed.call()


## Adds and connects a distortion source in one action, retaining output.
func add_layer_below_and_wire_warp(anchor_id: StringName, entry_id: String, axis: String) -> Dictionary:
	var anchor: GSTLayer = GSTStackOps.find_layer(_stack, anchor_id)
	if anchor == null or anchor.coord == null or axis not in ["x", "y"]:
		return {"ok": false, "reason": "The distortion destination is unavailable."}
	var entry: GSTManifestEntry = _library.get_entry(entry_id)
	if entry == null:
		return {"ok": false, "reason": "entry %s not found in library" % entry_id}
	var index: int = GSTStackOps.find_index(_stack, anchor_id)
	var old_target: StringName = anchor.coord.warp_x if axis == "x" else anchor.coord.warp_y
	var layer: GSTLayer = GSTStackOps.add_layer(_stack, entry_id, entry.kind_out, entry.coord)
	layer.manifest = entry
	_raw_reorder(layer.id, index)
	GSTStackOps.initialize_inputs_from_immediate_below(_stack, layer.id, _library)
	_raw_set_warp(anchor_id, axis, layer.id)
	_create_action("GST: add %s for distortion" % entry_id)
	_undo_redo.add_do_method(_redo_add_warp.bind(layer, index, anchor_id, axis))
	_undo_redo.add_undo_method(_undo_add_warp.bind(layer.id, anchor_id, axis, old_target))
	_undo_redo.add_do_method(_notify)
	_undo_redo.add_undo_method(_notify)
	_undo_redo.commit_action(false)
	_notify()
	return {"ok": true, "reason": ""}


func _redo_add_warp(layer: GSTLayer, index: int, anchor_id: StringName, axis: String) -> void:
	_stack.layers.insert(index, layer)
	_raw_set_warp(anchor_id, axis, layer.id)


func _undo_add_warp(layer_id: StringName, anchor_id: StringName, axis: String, old_target: StringName) -> void:
	_raw_set_warp(anchor_id, axis, old_target)
	_undo_add(layer_id)


## Commits one finished native property gesture (decision superseding 20):
## gst_inspector_column.gd applies new_value to target directly as the
## gesture progresses (so the widget and material stay live during a drag),
## then calls this once the gesture finishes, mutation-first like every
## other method here. A no-op (the value round-tripped back to old_value)
## registers nothing. Registers plain Callables, not add_do_property/
## add_undo_property: those call Resource.emit_changed() on replay, which
## this file has no watcher for and does not need.
##
## old_present is whether target held an explicit params entry for
## property_name before the gesture began (phase 2 review round 1 fix pass:
## a target with no method for this, e.g. GSTCoordBlock's real @export
## fields, is always treated as present). A no-op gesture (final value
## round-tripped back to old_value) restores that exact absence directly,
## without registering an action, since gst_inspector_column.gd's own live
## application during the gesture may already have written an explicit
## params entry equal to the default. A genuine change whose old value was
## implicit erases the params entry on undo instead of writing the default
## back explicitly, so undo reproduces the identical pre-edit serialization.
##
## on_replayed, when valid, is bound by the caller to the specific row it
## owns (by a stable key, not the row/editor Nodes themselves) and runs
## alongside _on_property_changed on this commit and every later undo/redo,
## so that one row's own displayed value refreshes (EditorProperty.
## update_property()) without gst_inspector_column.gd rebuilding any row --
## rebuilding here would free the very control a live gesture, an open
## native color popup, or a test still holds a reference to mid-interaction.
func commit_property_change(target: Object, property_name: StringName, old_value: Variant, new_value: Variant, on_replayed: Callable = Callable(), old_present: bool = true) -> void:
	if _values_equal(old_value, new_value):
		if not old_present:
			_restore_absent_param(target, property_name)
		return
	_create_action("GST: edit %s" % property_name)
	var undo_method: Callable = target.set.bind(property_name, old_value)
	if not old_present and target.has_method(&"erase_param_value"):
		undo_method = target.erase_param_value.bind(property_name)
	_undo_redo.add_do_method(target.set.bind(property_name, new_value))
	_undo_redo.add_undo_method(undo_method)
	if on_replayed.is_valid():
		_undo_redo.add_do_method(on_replayed)
		_undo_redo.add_undo_method(on_replayed)
	_undo_redo.add_do_method(_notify_property)
	_undo_redo.add_undo_method(_notify_property)
	_undo_redo.commit_action(false)
	if on_replayed.is_valid():
		on_replayed.call()
	_notify_property()


## Public so gst_inspector_column.gd can restore an absent params entry
## directly for a no-op gesture finish, without ever routing that no-op
## through commit_property_change (which would need a real old/new value
## pair to register or skip an action).
static func restore_absent_param(target: Object, property_name: StringName) -> void:
	_restore_absent_param(target, property_name)


static func _restore_absent_param(target: Object, property_name: StringName) -> void:
	if target.has_method(&"erase_param_value"):
		target.call(&"erase_param_value", property_name)


## Notifies material synchronization for an intermediate (still-active)
## native property change, without registering any history action (phase 2
## review round 1 fix pass): a live drag applies its value directly to the
## resource for immediate visual feedback, but only commit_property_change's
## own do/undo pair notifies material sync by default, leaving the preview
## stale until the gesture finishes. gst_inspector_column.gd calls this once
## per intermediate value while a gesture is active.
func notify_property_changed() -> void:
	_notify_property()


func _notify_property() -> void:
	if _on_property_changed.is_valid():
		_on_property_changed.call()


## Public so gst_inspector_column.gd can apply the same no-op definition
## when deciding whether a finished gesture needs to reach
## commit_property_change at all.
static func values_equal(a: Variant, b: Variant) -> bool:
	return _values_equal(a, b)


static func _values_equal(a: Variant, b: Variant) -> bool:
	if a is float and b is float:
		return is_equal_approx(a, b)
	if a is Vector2 and b is Vector2:
		return (a as Vector2).is_equal_approx(b as Vector2)
	if a is Vector3 and b is Vector3:
		return (a as Vector3).is_equal_approx(b as Vector3)
	if a is Color and b is Color:
		return (a as Color).is_equal_approx(b as Color)
	return a == b


## Randomizes every slider on the open recipe (decision 16, docs/PLAN.md
## Phase 8 Build item 3), routed through GSTUndo like every other mutation
## (phase 2: previously registered directly on the shared
## EditorUndoRedoManager by gst_main_panel.gd, paired with an explicit
## _refresh_inspector do/undo call because GSTRandomize.apply's writes were
## external to whatever EditorProperty widgets the inspector column had
## already built). commit_action(false)'s do/undo _notify pair now covers
## that refresh the same way it covers every other GSTUndo action, since
## _notify already rebuilds the inspector column's rows for the selected
## layer. `old_changes` mirrors `changes`' shape with each layer's
## pre-randomize values; `unset_params` records which of those values were
## implicit defaults (not yet written into layer.params) so undo can erase
## them again rather than leaving an explicit default that would change the
## serialized header (decision: absent parameter keys survive undo).
func apply_randomize(changes: Dictionary, old_changes: Dictionary, unset_params: Dictionary) -> void:
	GSTRandomize.apply(_stack, changes)
	_create_action("GST: randomize sliders")
	_undo_redo.add_do_method(_apply_randomize_changes.bind(changes))
	_undo_redo.add_undo_method(_undo_randomize_changes.bind(old_changes, unset_params))
	_undo_redo.add_do_method(_notify)
	_undo_redo.add_undo_method(_notify)
	_undo_redo.commit_action(false)
	_notify()


func _apply_randomize_changes(changes: Dictionary) -> void:
	GSTRandomize.apply(_stack, changes)


## Restores pre-randomize values and erases any param key that was an
## implicit default before the randomize action ran (kept as one undo
## method, paired 1:1 with apply_randomize's own do method, matching every
## other GSTUndo action's do/undo balance).
func _undo_randomize_changes(old_changes: Dictionary, unset_params: Dictionary) -> void:
	GSTRandomize.apply(_stack, old_changes)
	_restore_unset_params(unset_params)


## Explicit defaults change the serialized header even when values match.
func _restore_unset_params(unset_params: Dictionary) -> void:
	for layer_id: Variant in unset_params:
		var layer: GSTLayer = GSTStackOps.find_layer(_stack, StringName(layer_id))
		if layer != null:
			for param_name: String in unset_params[layer_id]:
				layer.params.erase(param_name)
