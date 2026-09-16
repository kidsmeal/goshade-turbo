@tool
class_name GSTDocument
extends RefCounted

## Runtime ownership for one open shader: its stack, private UndoRedo/GSTUndo
## history, save/origin identity, selected layer, and preview/diagnostic
## state, independent of every other open document. gst_main_panel.gd holds
## every open GSTDocument and activates one at a time into the shared UI.
## GSTUndo registers on this UndoRedo directly; no GLOBAL_HISTORY lookup or
## editor-manager context applies.

## Stable across the document's lifetime; never reused, never derived from
## array position or display order.
var session_id: int = -1

var stack: GSTStack = null
## One standalone UndoRedo per document. Freed explicitly by teardown(): a
## plain Object, so nothing frees it automatically.
var undo_redo: UndoRedo = UndoRedo.new()
var undo: GSTUndo = null

## "" for a never-saved stack or one reopened from a .gdshader header. A
## non-empty path is this document's identity for reuse
## (find_document_by_path in gst_main_panel.gd).
var current_path: String = ""
## True only right after this document was installed from a shipped recipe;
## gates the Randomize button.
var recipe_open: bool = false
## Name of the shipped recipe this document was opened from, or "".
var recipe_name: String = ""
## True only right after this document was rebuilt from an exported
## .gdshader header: unsaved import content with no recipe name and no path.
var reopened_import: bool = false
## Stable layer id last selected in this document's own stack list.
var selected_layer_id: StringName = &""

## Stack-list scroll position, captured by stable layer id when this document
## stops being active (gst_main_panel.gd _activate_document); rows are
## rebuilt on every activation, so a raw scrollbar offset is not stable. ""
## means no captured position.
var list_scroll_anchor_id: StringName = &""
var list_scroll_offset: float = 0.0

## Document-local preview/diagnostic state, restored on activation.
var preview_preset: String = ""
var preview_image_path: String = ""
## Diagnostic solo-preview layer id (gst_main_panel.gd's _preview_layer_id).
var preview_layer_id: StringName = &""

## Each document renders through its own GSTMaterialSync/ShaderMaterial pair
## so an inactive document's last successful preview survives switching.
var preview_sync: GSTMaterialSync = GSTMaterialSync.new()
var material: ShaderMaterial = preview_sync.get_material()

## compute_fingerprint(stack) at the last successful open or save; is_dirty()
## compares the current fingerprint against it.
var saved_fingerprint: String = ""

## "" when this document holds no shutdown recovery record; otherwise the
## record's id (GSTDocumentRecovery). gst_main_panel.gd reuses this id on
## every later shutdown while the document stays dirty and clears it, removing
## the on-disk record, once the document is saved or discarded.
var recovery_record_id: String = ""

## compute_fingerprint(stack) when recovery_record_id's on-disk record last
## captured this content; "" whenever recovery_record_id is "". Godot's
## "Save and Quit" handler re-evaluates every plugin's _get_unsaved_status("")
## after _save_external_data() and never exits while it reports anything, so
## a recovered document that stays is_dirty() would hold the quit dialog open
## forever. needs_shutdown_attention() excludes a document only once its
## current content equals the content captured on disk.
var recovery_fingerprint: String = ""

## True while Godot's confirmed-quit/scene-close status should name this
## document: it is dirty and either holds no recovery record or that record's
## content is stale against the live stack. is_dirty() itself stays true
## until the user saves or discards.
func needs_shutdown_attention() -> bool:
	if not is_dirty():
		return false
	if recovery_record_id.is_empty():
		return true
	return compute_fingerprint(stack) != recovery_fingerprint


## Latest file-operation diagnostic per control ("Open", "Save", "Export",
## "Reopen Shader", "Recipes", "Preview"; Save As failures write "Save").
## An absent key means no current message for that control. gst_main_panel.gd
## _set_operation_message_for writes it and rebuilds the shared label only
## when this document is active; _install_stack reads it back on activation.
var operation_messages: Dictionary = {}


static var _next_session_id: int = 0


func _init() -> void:
	session_id = _next_session_id
	_next_session_id += 1


## Installs new_stack as this document's content and builds its GSTUndo bound
## to this document's undo_redo. The panel binds on_changed/on_property_changed
## to this document (Callable.bind(self)) so an inactive document's replay
## never touches the active panel UI.
##
## starts_dirty=false marks the current content as the saved baseline (New,
## or loaded from disk). true (recipe, .gdshader header import) leaves
## saved_fingerprint at "", which compute_fingerprint never produces for a
## real stack, so the document reads dirty immediately.
func setup(new_stack: GSTStack, library: GSTLibrary, on_changed: Callable, on_property_changed: Callable, starts_dirty: bool = false) -> void:
	stack = new_stack
	undo = GSTUndo.new(undo_redo, stack, library, on_changed, on_property_changed)
	if not starts_dirty:
		mark_baseline()


## Frees this document's UndoRedo and releases every bound Callable its
## recorded actions held. Called by gst_main_panel.gd _exit_tree for every
## open document and by the close lifecycle for a discarded document.
func teardown() -> void:
	if undo_redo != null and is_instance_valid(undo_redo):
		undo_redo.free()
	undo_redo = null
	undo = null


func mark_baseline() -> void:
	saved_fingerprint = compute_fingerprint(stack)


## True when the stack's content differs from the last open/save baseline.
func is_dirty() -> bool:
	return compute_fingerprint(stack) != saved_fingerprint


## Deterministic content fingerprint: every field of the on-disk schema
## (coord_space, next_id, output_color, output_alpha, each layer's
## id/entry/kind_out/slots/params/coord), keys sorted. Excludes paths, layout,
## selection, history position, and session metadata. Never uses
## ResourceSaver's text: it assigns each sub_resource id a fresh random suffix
## on every save. Includes next_id (ids are never reused, so undoing an add
## can leave a different next_id with identical layers) and raw params-key
## presence (absent keys read as absent, matching gst_undo.gd
## commit_property_change).
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
