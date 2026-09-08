@tool
class_name GSTMainPanel
extends VBoxContainer

## Main screen panel (decision 13): three-column layout (stack list,
## inspector column, the phase-5 preview column), an output block docked
## under the stack list, a coord-space selector above it, and a message
## label at the bottom that shows the last codegen error or a refused
## structural edit's reason.
##
## Holds the current GSTStack (a new empty stack on open) and the GSTLibrary
## (scanned once). stack_changed fires after every structural edit so this
## panel's own preview material stays in sync (self-connected below) and so
## a caller that mutates the stack directly, bypassing GSTUndo (e.g. an
## invocation-local codegen-error excursion), can re-emit it to force a
## resync (docs/PLAN.md Phase 5 Files, tests/gst_editor_smoke.gd item 8).
##
## Phase 5 material sync (decision 7, GSTMaterialSync) resyncs on five
## triggers: (1) stack_changed, self-connected here, covering every GSTUndo
## structural edit plus any caller-forced re-emission; (2)
## gst_inspector_column.gd's param_edited signal, the direct relay of a real
## EditorInspector-driven property edit (a slider via EditorInspector's own
## property_edited, or a GSTCoordBlock field via GSTCoordBlock.changed) --
## decision 20's "slider edits come free from the inspector" never goes
## through GSTUndo at all, so this relay is the only path such an edit
## reaches the preview (fix pass 2, item 1: the shared
## EditorUndoRedoManager history's version_changed signal alone is not
## sufficient here, since a real inspector-driven create_action() call binds
## to whatever object the editor's undo manager currently treats as context,
## not necessarily this stack's own history bucket -- only a
## GSTUndo-authored action or a caller that explicitly passes
## custom_context = the stack is guaranteed to land there); (3) that same
## version_changed signal, kept for undo/redo replay of a property edit,
## which sets the value straight through Object.set() and fires neither
## property_edited nor Resource.changed; (4) layer selection while the solo
## toggle is on; (5) a preset or preview-image change. A sixth path,
## GSTPreview.target_rect_changed (an editor-window or splitter resize), does
## not run this full resync: it writes only gst_rect_size via
## GSTMaterialSync.write_rect_size, since it can fire once per frame during a
## drag (B5).

signal stack_changed

@onready var _stack_list: GSTStackList = %StackList
@onready var _output_block: GSTOutputBlock = %OutputBlock
@onready var _inspector_column: GSTInspectorColumn = %InspectorColumn
@onready var _message_label: Label = %MessageLabel
@onready var _preview: GSTPreview = %Preview
@onready var _preset_option: OptionButton = %PresetOption
@onready var _image_button: Button = %ImageButton
@onready var _solo_check: CheckButton = %SoloCheck
@onready var _coord_space_option: OptionButton = %CoordSpaceOption
@onready var _new_button: Button = %NewButton
@onready var _open_button: Button = %OpenButton
@onready var _save_button: Button = %SaveButton
@onready var _save_as_button: Button = %SaveAsButton
@onready var _export_button: Button = %ExportButton
@onready var _reopen_shader_button: Button = %ReopenShaderButton
@onready var _recipes_button: MenuButton = %RecipesButton

const COORD_SPACE_NAMES: Array[String] = ["uv", "screen_uv", "local"]
## docs/PLAN.md Phase 7 Files: the Recipes MenuButton lists every .tres here.
const RECIPES_DIR: String = "res://addons/goshade_turbo/recipes"

var _stack: GSTStack = null
var _library: GSTLibrary = null
var _undo_redo: EditorUndoRedoManager = null
var _undo: GSTUndo = null
## A dedicated, never-persisted, never-installed Resource used only as
## EditorUndoRedoManager's custom_context for "Replace stack" actions and for
## resolving the watched history (docs/PLAN.md Phase 7 finding): a GSTStack
## loaded from a real res:// path -- as GSTStackIO.load produces for Open,
## Reopen Shader, and open_recipe -- routes to a different
## EditorUndoRedoManager history bucket than a bare, path-less
## GSTStack.new() does on 4.6.2 (empirically verified: chaining
## open_recipe -> New -> build -> undo-to-end -> redo-to-end left the panel's
## material on the prior recipe's codegen, because the New action's
## custom_context was old_stack, the just-loaded path-bearing recipe stack,
## which landed outside the bucket _get_history() resolved and drove). This
## anchor is always a bare, path-less Resource, so replace_stack's own action
## and _get_history()'s lookup both stay in the one shared bucket regardless
## of what was opened in between.
var _history_context: Resource = Resource.new()
var _material: ShaderMaterial = ShaderMaterial.new()
var _watched_history: UndoRedo = null
## Guards _coord_space_option.select() calls made to reflect stack state from
## re-triggering _on_coord_space_selected (mirrors gst_output_block.gd's own
## _syncing guard for the same reason).
var _syncing_coord_space: bool = false
var _file_dialog: EditorFileDialog = null

## The .tres this stack was last opened from or saved to; "" for a new,
## never-saved stack, or after a reopen-from-.gdshader (decision 8: a
## reopened stack has no .tres of its own to "Save" back onto, so it starts
## unsaved like a new stack).
var _current_path: String = ""
var _open_dialog: EditorFileDialog = null
var _save_as_dialog: EditorFileDialog = null
var _export_dialog: EditorFileDialog = null
var _reopen_shader_dialog: EditorFileDialog = null
var _overwrite_dialog: ConfirmationDialog = null
## The export target awaiting the overwrite confirmation dialog's answer.
var _pending_export_path: String = ""


func _ready() -> void:
	_library = GSTLibrary.new()
	_library.scan()
	_stack = GSTStack.new()
	_stack_list.layer_selected.connect(_on_layer_selected)
	_stack_list.structural_edit_refused.connect(_on_refused)
	_inspector_column.edit_refused.connect(_on_refused)
	_inspector_column.param_edited.connect(_on_param_edited)
	stack_changed.connect(_resync_material)

	# _resync_material runs before the material is ever handed to the preview
	# node: GSTMaterialSync.sync() creates _material.shader itself and sets
	# its code to a real, non-empty value in the same call. Assigning a
	# ShaderMaterial to a CanvasItem's `material` while its Shader still has
	# empty code, then mutating `.code` afterward on that same Shader object,
	# leaves the render stuck showing the node's unshaded appearance forever
	# after -- confirmed by an isolated repro (a second TextureRect whose
	# shader code was set 3 frames after first being assigned rendered black,
	# never green, across 8 further frames; a material created with real code
	# before ever being assigned rendered correctly immediately). Every
	# _resync_material() call after this first one is safe either way, since
	# by then the shader already carries real code. _install_stack() (called by
	# set_undo_redo_manager right after this node enters the tree) resyncs
	# again once the stack is actually editable, so no further call is needed
	# here.
	_resync_material()
	_preview.set_shader_material(_material)
	_preview.target_rect_changed.connect(_on_target_rect_changed)

	for preset_name: String in GSTPreviewPresets.PRESET_NAMES:
		_preset_option.add_item(preset_name)
	_preset_option.item_selected.connect(_on_preset_selected)
	_image_button.pressed.connect(_on_image_button_pressed)
	_solo_check.toggled.connect(_on_solo_toggled)

	for space_name: String in COORD_SPACE_NAMES:
		_coord_space_option.add_item(space_name)
	_coord_space_option.item_selected.connect(_on_coord_space_selected)

	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.add_filter("*.png, *.jpg, *.jpeg, *.webp, *.svg", "Images")
	_file_dialog.file_selected.connect(_on_preview_image_selected)
	add_child(_file_dialog)

	_new_button.pressed.connect(_on_new_pressed)
	_open_button.pressed.connect(_on_open_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_save_as_button.pressed.connect(_on_save_as_pressed)
	_export_button.pressed.connect(_on_export_pressed)
	_reopen_shader_button.pressed.connect(_on_reopen_shader_pressed)

	_refresh_recipes_menu()
	_recipes_button.get_popup().index_pressed.connect(_on_recipe_index_pressed)

	_open_dialog = EditorFileDialog.new()
	_open_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_open_dialog.add_filter("*.tres", "GoShade Turbo Stack")
	_open_dialog.file_selected.connect(_on_open_file_selected)
	add_child(_open_dialog)

	_save_as_dialog = EditorFileDialog.new()
	_save_as_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_save_as_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_save_as_dialog.add_filter("*.tres", "GoShade Turbo Stack")
	_save_as_dialog.file_selected.connect(_on_save_as_file_selected)
	add_child(_save_as_dialog)

	_export_dialog = EditorFileDialog.new()
	_export_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_export_dialog.add_filter("*.gdshader", "GoShade Turbo Shader")
	_export_dialog.file_selected.connect(_on_export_file_selected)
	add_child(_export_dialog)

	_reopen_shader_dialog = EditorFileDialog.new()
	_reopen_shader_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_reopen_shader_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_reopen_shader_dialog.add_filter("*.gdshader", "GoShade Turbo Shader")
	_reopen_shader_dialog.file_selected.connect(_on_reopen_shader_file_selected)
	add_child(_reopen_shader_dialog)

	_overwrite_dialog = ConfirmationDialog.new()
	_overwrite_dialog.confirmed.connect(_on_overwrite_confirmed)
	add_child(_overwrite_dialog)


## Called once by plugin.gd right after instantiation (decision 20's
## EditorUndoRedoManager is only reachable through the EditorPlugin, not a
## plain Control). Installs the initial, never-saved stack with no undo action
## registered around it: there is nothing before the first stack to undo back
## to.
func set_undo_redo_manager(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo
	_install_stack(_stack, GSTUndo.new(_undo_redo, _stack, _library, _on_stack_changed, _history_context))


## Wires the stack-list/output-block/inspector columns, the watched undo
## history, and the coord-space dropdown to `stack`/`undo`, and resyncs the
## material. This is the do/undo primitive for a stack replacement (phase 6
## fix pass 2, item 1; docs/PLAN.md Cross-cutting "EditorUndoRedoManager
## integration"): replace_stack below registers this method as both the do
## and the undo method of a "Replace stack" EditorUndoRedoManager action
## (alongside a second do/undo pair for _current_path), so undo reinstalls the
## exact previous GSTStack instance and its previous GSTUndo instance -- not a
## freshly constructed one -- and every action already recorded through that
## GSTUndo's own add_do_method(self, ...) bindings keeps landing on the
## GSTStack/GSTLayer instances it actually closed over. Also called directly,
## with no action registered, by set_undo_redo_manager for the very first
## stack.
func _install_stack(stack: GSTStack, undo: GSTUndo) -> void:
	_stack = stack
	_undo = undo
	_stack_list.setup(_stack, _library, _undo)
	_output_block.setup(_stack, _library, _undo)
	_inspector_column.setup(_stack, _library, _undo)
	_rewatch_history()
	_syncing_coord_space = true
	_coord_space_option.select(int(_stack.coord_space))
	_syncing_coord_space = false
	_resync_material()


func _raw_set_current_path(path: String) -> void:
	_current_path = path


func _notify_replace() -> void:
	stack_changed.emit()


## Wired-by: none (editor smoke seam)
func get_stack() -> GSTStack:
	return _stack


## Installs new_stack (and new_path as the new _current_path) as an undoable
## "Replace stack" action in the shared editor history, rather than mutating
## _stack/_current_path directly: a structural edit made before New, Open, or
## Reopen Shader now stays undoable afterward instead of being discarded
## along with the replaced GSTStack (docs/PLAN.md Cross-cutting
## "EditorUndoRedoManager integration", phase 6 fix pass 2 item 1).
## custom_context is _history_context, the panel's path-less anchor Resource:
## on 4.6.2, get_object_history_id routes a Resource with a res:// path to a
## different history than a path-less one (verified: tests/gst_editor_smoke.gd
## phase 7 run 2), so the stack instance is never used as context.
## _on_new_pressed, open_path, and reopen_shader_path call this instead of
## mutating _stack/_current_path directly.
func replace_stack(new_stack: GSTStack, new_path: String) -> void:
	var old_stack: GSTStack = _stack
	var old_undo: GSTUndo = _undo
	var old_path: String = _current_path
	var new_undo: GSTUndo = GSTUndo.new(_undo_redo, new_stack, _library, _on_stack_changed, _history_context)
	_install_stack(new_stack, new_undo)
	_raw_set_current_path(new_path)
	_undo_redo.create_action("GST: Replace stack", UndoRedo.MERGE_DISABLE, _history_context)
	_undo_redo.add_do_method(self, "_install_stack", new_stack, new_undo)
	_undo_redo.add_undo_method(self, "_install_stack", old_stack, old_undo)
	_undo_redo.add_do_method(self, "_raw_set_current_path", new_path)
	_undo_redo.add_undo_method(self, "_raw_set_current_path", old_path)
	_undo_redo.add_do_method(self, "_notify_replace")
	_undo_redo.add_undo_method(self, "_notify_replace")
	_undo_redo.commit_action(false)
	_notify_replace()


## Wired-by: none (editor smoke seam)
func get_library() -> GSTLibrary:
	return _library


## Wired-by: none (editor smoke seam)
func get_undo() -> GSTUndo:
	return _undo


## Wired-by: none (editor smoke seam)
func get_stack_list() -> GSTStackList:
	return _stack_list


## Wired-by: none (editor smoke seam)
func get_output_block() -> GSTOutputBlock:
	return _output_block


## Wired-by: none (editor smoke seam)
func get_inspector_column() -> GSTInspectorColumn:
	return _inspector_column


## Wired-by: none (editor smoke seam)
func get_preview() -> GSTPreview:
	return _preview


## Not named get_material: Control (CanvasItem) already declares
## get_material() -> Material for its own `material` property; a narrowed
## ShaderMaterial return type is legal (covariant), but the rename keeps this
## unambiguous alongside gst_preview.gd's own set_shader_material rename.
## Wired-by: none (editor smoke seam)
func get_shader_material() -> ShaderMaterial:
	return _material


## Wired-by: none (editor smoke seam)
func get_solo_check() -> CheckButton:
	return _solo_check


## Wired-by: none (editor smoke seam)
func get_message_label() -> Label:
	return _message_label


## The UndoRedo bucket _watched_history currently points at (the same one
## _get_history()/_history_context resolve to). Lets the phase 7 smoke drive
## undo()/redo() directly against the exact history this panel watches,
## instead of recomputing a bucket the smoke's own stack argument might not
## share with GSTUndo's actions (docs/PLAN.md Cross-cutting
## "EditorUndoRedoManager integration", "History anchor (phase 7)").
## Wired-by: none (editor smoke seam)
func get_watched_history() -> UndoRedo:
	return _watched_history


## The .tres this stack was last opened from or saved to, or "" for a new or
## reopened-from-.gdshader stack (see _current_path).
## Wired-by: none (editor smoke seam)
func get_current_path() -> String:
	return _current_path


## Wired-by: none (editor smoke seam)
func is_overwrite_dialog_visible() -> bool:
	return _overwrite_dialog != null and _overwrite_dialog.visible


## Wired-by: none (editor smoke seam)
func is_export_dialog_visible() -> bool:
	return _export_dialog != null and _export_dialog.visible


## Wired-by: none (editor smoke seam)
func hide_export_dialog() -> void:
	if _export_dialog != null:
		_export_dialog.hide()


func _on_new_pressed() -> void:
	replace_stack(GSTStack.new(), "")
	_message_label.text = ""


func _on_open_pressed() -> void:
	_open_dialog.popup_centered_ratio()


func _on_open_file_selected(path: String) -> void:
	open_path(path)


## Loads `path` through GSTStackIO and installs it via replace_stack (decision
## 20: an undoable "Replace stack" action, same as New). A refusal (a missing
## file or an unresolved entry) leaves the current stack untouched and shows
## the reason in the message label. This is the Open button's own
## file-selected handler (_on_open_file_selected calls it directly); public
## so tests/gst_editor_smoke.gd can drive the same path without popping the
## file dialog (docs/PLAN.md Phase 4 Files precedent, gst_stack_list.gd's
## add_layer_by_entry_id).
func open_path(path: String) -> void:
	var result: Dictionary = GSTStackIO.load(path, _library)
	if not result["ok"]:
		_message_label.text = result["reason"]
		return
	replace_stack(result["stack"], path)
	_message_label.text = ""


## Rebuilds the Recipes MenuButton's popup from every .tres under
## RECIPES_DIR, by file name (docs/PLAN.md Phase 7 Files). Called once from
## _ready(); the recipe roster is fixed at edit time in this phase (no
## structural add/remove path adds one during a session), so no further
## refresh trigger exists yet.
func _refresh_recipes_menu() -> void:
	var popup: PopupMenu = _recipes_button.get_popup()
	popup.clear()
	for recipe_name: String in _recipe_names():
		popup.add_item(recipe_name)


func _recipe_names() -> Array[String]:
	var names: Array[String] = []
	var dir: DirAccess = DirAccess.open(RECIPES_DIR)
	if dir == null:
		return names
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and entry_name.ends_with(".tres"):
			names.append(entry_name.get_basename())
		entry_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


## PopupMenu.add_item() auto-assigns each item's id equal to its own index
## (no explicit id was ever passed above), so index_pressed's index maps
## directly onto _recipe_names()'s own sorted order without a second lookup.
func _on_recipe_index_pressed(index: int) -> void:
	var names: Array[String] = _recipe_names()
	if index < 0 or index >= names.size():
		return
	open_recipe(names[index])


## Loads RECIPES_DIR/<name>.tres and installs it via replace_stack (decision
## 20: an undoable "Replace stack" action, same as New/Open/Reopen Shader),
## with the new current_path left empty rather than set to the recipe's own
## path: a recipe is a template, so Save falls back to Save As instead of
## silently overwriting the shipped recipe file (docs/PLAN.md Phase 7 Files).
## This is the Recipes menu's own handler; public so
## tests/gst_editor_smoke.gd can drive the same path directly.
func open_recipe(name: String) -> void:
	var path: String = "%s/%s.tres" % [RECIPES_DIR, name]
	var result: Dictionary = GSTStackIO.load(path, _library)
	if not result["ok"]:
		_message_label.text = result["reason"]
		return
	replace_stack(result["stack"], "")
	_message_label.text = ""


func _on_save_pressed() -> void:
	if _current_path.is_empty():
		_on_save_as_pressed()
		return
	save_to_path(_current_path)


func _on_save_as_pressed() -> void:
	_save_as_dialog.popup_centered_ratio()


func _on_save_as_file_selected(path: String) -> void:
	save_to_path(path)


## Saves the open stack to `path` through GSTStackIO. This is both the Save
## button's own handler (when a current path already exists) and Save As's
## file-selected handler; public so the smoke can drive it directly too.
func save_to_path(path: String) -> void:
	var result: Dictionary = GSTStackIO.save(_stack, path)
	if not result["ok"]:
		_message_label.text = result["reason"]
		return
	_current_path = path
	_message_label.text = ""


func _on_export_pressed() -> void:
	_export_dialog.popup_centered_ratio()


func _on_export_file_selected(path: String) -> void:
	export_to_path(path, false)


## Exports the open stack to `path` through GSTExport.write (decision 9: the
## overwrite gate). When the target exists with a differing body and
## `confirm` is false, shows the overwrite confirmation dialog and performs
## no write; confirming it re-calls this with `confirm = true`. This is the
## Export button's file-selected handler and the confirmation dialog's own
## confirmed handler; public so the smoke can drive it directly too.
func export_to_path(path: String, confirm: bool) -> void:
	var result: Dictionary = GSTExport.write(_stack, _library, path, confirm)
	if result["needs_confirmation"]:
		_pending_export_path = path
		_overwrite_dialog.dialog_text = "%s already holds a body that differs from this stack's codegen. Overwrite it?" % path
		_overwrite_dialog.popup_centered()
		return
	# Any other outcome resolves the question the dialog was asking (a
	# confirmed write, or a write that turned out not to need confirmation
	# at all): closes it explicitly rather than relying on AcceptDialog's
	# own auto-hide-on-confirmed, which only fires for an actual button
	# press, not a direct confirm=true call (the smoke's own path here).
	if _overwrite_dialog.visible:
		_overwrite_dialog.hide()
	if not result["ok"]:
		_message_label.text = result["reason"]
		return
	_message_label.text = ""


func _on_overwrite_confirmed() -> void:
	export_to_path(_pending_export_path, true)
	_pending_export_path = ""


func _on_reopen_shader_pressed() -> void:
	_reopen_shader_dialog.popup_centered_ratio()


func _on_reopen_shader_file_selected(path: String) -> void:
	reopen_shader_path(path)


## Reopens a stack from an exported .gdshader's embedded header through
## GSTExport.reopen (decision 8). A refusal (no header, unparsable header, or
## an unknown schema -- B8) shows the reason in the message label and leaves
## the current stack untouched; no new empty stack is offered. On success,
## installs the rebuilt stack via replace_stack (an undoable "Replace stack"
## action, same as New/Open) with an empty _current_path (a reopened stack has
## no .tres of its own). When the file's body differs from a fresh codegen of
## its own header
## (decision 8's stale-body warning), that is shown instead of the plain
## success clear. This is the Reopen Shader button's own file-selected
## handler; public so the smoke can drive it directly too.
func reopen_shader_path(path: String) -> void:
	var result: Dictionary = GSTExport.reopen(path, _library)
	if not result["ok"]:
		_message_label.text = result["reason"]
		return
	replace_stack(result["stack"], "")
	if result["body_differs"]:
		_message_label.text = "%s reopened: its body differs from a fresh codegen of the header (hand edits detected, decision 8)" % path
	else:
		_message_label.text = ""


func _on_layer_selected(layer_id: StringName) -> void:
	_inspector_column.edit(layer_id)
	if _solo_check.button_pressed:
		_resync_material()


func _on_refused(reason: String) -> void:
	_message_label.text = reason


## GSTUndo's on_changed callback: fires after every do and undo.
func _on_stack_changed() -> void:
	_stack_list.refresh()
	_output_block.refresh()
	_inspector_column.edit(_stack_list.get_selected_layer_id())
	_syncing_coord_space = true
	_coord_space_option.select(int(_stack.coord_space))
	_syncing_coord_space = false
	stack_changed.emit()


## _resync_material runs first and always sets _message_label to the current
## codegen error (or "" on success): the screen_uv suggestion below is only
## applied on top of a clean sync, so a real codegen error is never masked
## by it.
func _on_preset_selected(index: int) -> void:
	var preset_name: String = GSTPreviewPresets.PRESET_NAMES[index]
	_preview.set_preset(preset_name)
	_resync_material()
	if _message_label.text.is_empty() and GSTPreviewPresets.suggests_screen_uv(preset_name, _stack.coord_space):
		_message_label.text = "text preset: coord space is uv; screen_uv reads more consistently on text (decision 11)"


func _on_image_button_pressed() -> void:
	_file_dialog.popup_centered_ratio()


func _on_preview_image_selected(path: String) -> void:
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		return
	_preview.set_image(texture)
	_resync_material()


func _on_solo_toggled(_pressed: bool) -> void:
	_resync_material()


## GSTPreview.target_rect_changed (an editor-window or splitter resize, or a
## preset swap to a differently-sized target). Writes only gst_rect_size
## (B5), never a full GSTMaterialSync.sync() codegen pass, since this can
## fire once per frame during a drag.
func _on_target_rect_changed(size: Vector2) -> void:
	GSTMaterialSync.write_rect_size(_material, size)


func _on_coord_space_selected(index: int) -> void:
	if _syncing_coord_space:
		return
	_undo.set_coord_space(index as GSTStack.CoordSpace)


## The shared EditorUndoRedoManager history for _stack (same one GSTUndo's
## _create_action commits to). version_changed on this history catches undo
## and redo of a GSTUndo-authored structural action (stack_changed already
## covers its initial do) and, when one lands here, undo/redo of an
## inspector-driven property edit too: Object.set() during undo/redo fires
## neither EditorInspector.property_edited nor Resource.changed, so
## gst_inspector_column.gd's param_edited relay (the live-edit path) cannot
## see it, and this is the only remaining hook for that case (fix pass 2,
## item 1).
func _get_history() -> UndoRedo:
	if _undo_redo == null:
		return null
	var history_id: int = _undo_redo.get_object_history_id(_history_context)
	return _undo_redo.get_history_undo_redo(history_id)


func _rewatch_history() -> void:
	if _watched_history != null and _watched_history.version_changed.is_connected(_on_history_version_changed):
		_watched_history.version_changed.disconnect(_on_history_version_changed)
	_watched_history = _get_history()
	if _watched_history != null:
		_watched_history.version_changed.connect(_on_history_version_changed)


func _on_history_version_changed() -> void:
	_resync_material()


## gst_inspector_column.gd's param_edited relay (fix pass 2, item 1): the
## direct path for a real, live EditorInspector-driven edit, independent of
## which EditorUndoRedoManager history bucket its create_action() call landed
## in.
func _on_param_edited(_property: String) -> void:
	_resync_material()


## Solo (decision 13) previews the selected layer instead of the stack's own
## output, without mutating the stack; the codegen error, if any, keeps the
## last good material and shows in the message label (GSTMaterialSync never
## touches the material on a failed sync).
func _resync_material() -> void:
	if _stack == null or _library == null or _preview == null or _material == null:
		return
	var solo_id: StringName = _stack_list.get_selected_layer_id() if _solo_check.button_pressed else &""
	var rect_size: Vector2 = _preview.get_target_rect_size()
	var result: GSTCodegenResult = GSTMaterialSync.sync(_stack, _library, _material, solo_id, rect_size)
	_message_label.text = result.error
