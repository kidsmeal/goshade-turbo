@tool
class_name GSTDocument
extends RefCounted

## Runtime ownership for one open shader (phase 3,
## docs/SHADER_TABS_reviewed-plan.md): its stack, private UndoRedo/GSTUndo
## history, save/origin identity, selected layer, and preview/diagnostic
## state -- independent of every other open document. gst_main_panel.gd
## holds every open GSTDocument in its own document list and activates one
## at a time into the shared UI (stack list, inspector column, output
## block, coord-space dropdown, preview); visible tab controls that expose
## switching to the user are wired in phase 4.
##
## Cross-cutting "Shared editor state and history": resource paths and
## active scenes cannot choose a shader history. This UndoRedo instance is
## registered on directly by GSTUndo; no GLOBAL_HISTORY lookup or
## editor-manager context applies.

## Stable across the document's lifetime; never reused, never derived from
## array position or display order (phase 4 activates by this id, not
## index).
var session_id: int = -1

var stack: GSTStack = null
## One standalone UndoRedo per document (decision 20, revised). Freed
## explicitly by teardown(): a plain Object, not a RefCounted or a Node, so
## nothing frees it automatically.
var undo_redo: UndoRedo = UndoRedo.new()
var undo: GSTUndo = null

## "" for a never-saved stack or one reopened from a .gdshader header
## (decision 8: it has no .tres of its own to "Save" back onto). A
## non-empty path is this document's own canonical identity for reuse
## (find_document_by_path in gst_main_panel.gd).
var current_path: String = ""
## True only right after this document was installed from a shipped recipe
## (decision 16): gates the Randomize button. New, Open, and Reopen Shader
## each create their document with this false.
var recipe_open: bool = false
## Name of the shipped recipe this document was opened from, or "" (New,
## Open, Reopen Shader). Phase 4 displays this in the tab title/tooltip;
## phase 3 only stores it.
var recipe_name: String = ""
## True only right after this document was rebuilt from an exported
## .gdshader header (decision 8): unsaved import content with no recipe
## name and no saved path. Phase 4 displays this in the tab tooltip; phase 3
## only stores it.
var reopened_import: bool = false
## Stable layer id last selected in this document's own stack list.
var selected_layer_id: StringName = &""

## Document-local preview/diagnostic state (phase 4 restores these on
## activation; phase 3 only stores them as the active document's own
## selections change).
var preview_preset: String = ""
var preview_image_path: String = ""
## Diagnostic solo-preview layer id (gst_main_panel.gd's _preview_layer_id).
var preview_layer_id: StringName = &""

## Each document renders through its own GSTMaterialSync/ShaderMaterial
## pair so an inactive document's last successful preview survives
## switching away from it (phase 4 renders only the active one; phase 3
## only keeps the state isolated).
var preview_sync: GSTMaterialSync = GSTMaterialSync.new()
var material: ShaderMaterial = preview_sync.get_material()

## Content fingerprint (compute_fingerprint) at the last successful open or
## save. Compared against the stack's current fingerprint to report dirty
## state (consumed by phase 5/6 close/save; established here). A pristine,
## never-edited document (new or freshly opened) is never dirty.
var saved_fingerprint: String = ""


static var _next_session_id: int = 0


func _init() -> void:
	session_id = _next_session_id
	_next_session_id += 1


## Installs new_stack as this document's own content and builds its GSTUndo
## adapter bound to this document's own undo_redo. on_changed/
## on_property_changed are the same GSTUndo callback shape
## gst_main_panel.gd's own _on_stack_changed/_on_property_changed use; the
## panel binds them to this document (Callable.bind(self)) so an inactive
## document's replay never touches the active panel UI (Cross-cutting
## "Public APIs, signals, and callbacks": "capture the owning document in
## action callbacks").
##
## starts_dirty distinguishes a successful open/save baseline from unsaved
## nonempty recipe/import content (phase 3 fix pass 1, round 1): a pristine
## New document or a document just loaded from disk has content that
## matches what marking the baseline here would record, so it starts clean
## (false); a document opened from a shipped recipe or rebuilt from a
## .gdshader header's exported header has real content with nowhere on disk
## it already matches, so it must read dirty immediately (true) instead of
## marking that content as its own saved baseline. true leaves
## saved_fingerprint at its unset "" default, which compute_fingerprint's
## own non-empty format can never produce for a real stack.
func setup(new_stack: GSTStack, library: GSTLibrary, on_changed: Callable, on_property_changed: Callable, starts_dirty: bool = false) -> void:
	stack = new_stack
	undo = GSTUndo.new(undo_redo, stack, library, on_changed, on_property_changed)
	if not starts_dirty:
		mark_baseline()


## Frees this document's own UndoRedo (an Object with no owner to free it
## automatically) and releases every bound Callable its recorded actions
## held. Called by gst_main_panel.gd's _exit_tree for every open document,
## and by phase 6's close lifecycle for a single discarded document.
func teardown() -> void:
	if undo_redo != null and is_instance_valid(undo_redo):
		undo_redo.free()
	undo_redo = null
	undo = null


func mark_baseline() -> void:
	saved_fingerprint = compute_fingerprint(stack)


## True when the stack's current content differs from the last successful
## open/save baseline. A never-saved document with unedited pristine
## content (mark_baseline() at setup()) is not dirty.
func is_dirty() -> bool:
	return compute_fingerprint(stack) != saved_fingerprint


## Deterministic content fingerprint: every field the on-disk schema
## carries (coord_space, next_id, output_color, output_alpha, and each
## layer's id/entry/kind_out/slots/params/coord), sorted so key-insertion
## order can never change the result. Excludes paths, layout, selection,
## history position, and session metadata. Deliberately never uses
## ResourceSaver's own serialized text: ResourceSaver assigns every
## sub_resource id="1_xxxxx" a fresh random suffix on every save (Shader
## tabs phase 2 review round 3 fixes), so two saves of identical content are
## never byte-identical regardless of fingerprinting needs. Includes
## next_id (decision 22: ids are never reused, so undoing an add can leave a
## different next_id even with identical layer content) and raw
## parameter-key presence (a layer's params dict, not a manifest-resolved
## default -- absent keys must read as absent here, matching the undo
## contract in gst_undo.gd's commit_property_change).
static func compute_fingerprint(stack: GSTStack) -> String:
	if stack == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	parts.append("coord_space=%d" % int(stack.coord_space))
	parts.append("next_id=%d" % stack.next_id)
	parts.append("output_color=%s" % String(stack.output_color))
	parts.append("output_alpha=%s" % String(stack.output_alpha))
	for layer: GSTLayer in stack.layers:
		parts.append("layer_id=%s" % String(layer.id))
		parts.append("entry=%s" % layer.entry)
		parts.append("kind_out=%d" % int(layer.kind_out))
		parts.append("slots=%s" % _sorted_pairs(layer.slots))
		parts.append("params=%s" % _sorted_pairs(layer.params))
		if layer.coord != null:
			var coord: GSTCoordBlock = layer.coord
			parts.append("coord=%s|%s|%s|%s|%s|%s|%s" % [var_to_str(coord.scale), var_to_str(coord.offset), var_to_str(coord.rotation), var_to_str(coord.scroll), String(coord.warp_x), String(coord.warp_y), var_to_str(coord.warp_strength)])
	return "\n".join(parts)


static func _sorted_pairs(values: Dictionary) -> String:
	var keys: Array = values.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	var pairs: PackedStringArray = PackedStringArray()
	for key: Variant in keys:
		pairs.append("%s:%s" % [str(key), var_to_str(values[key])])
	return "|".join(pairs)
