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

const COORD_SPACE_NAMES: Array[String] = ["uv", "screen_uv", "local"]

var _stack: GSTStack = null
var _library: GSTLibrary = null
var _undo_redo: EditorUndoRedoManager = null
var _undo: GSTUndo = null
var _material: ShaderMaterial = ShaderMaterial.new()
var _watched_history: UndoRedo = null
## Guards _coord_space_option.select() calls made to reflect stack state from
## re-triggering _on_coord_space_selected (mirrors gst_output_block.gd's own
## _syncing guard for the same reason).
var _syncing_coord_space: bool = false
var _file_dialog: EditorFileDialog = null


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
	# by then the shader already carries real code. _rebuild_undo() (called by
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


## Called once by plugin.gd right after instantiation (decision 20's
## EditorUndoRedoManager is only reachable through the EditorPlugin, not a
## plain Control).
func set_undo_redo_manager(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo
	_rebuild_undo()


func _rebuild_undo() -> void:
	if _undo_redo == null:
		return
	_undo = GSTUndo.new(_undo_redo, _stack, _library, _on_stack_changed)
	_stack_list.setup(_stack, _library, _undo)
	_output_block.setup(_stack, _library, _undo)
	_inspector_column.setup(_stack, _library, _undo)
	_rewatch_history()
	_syncing_coord_space = true
	_coord_space_option.select(int(_stack.coord_space))
	_syncing_coord_space = false
	_resync_material()


## Wired-by: none (editor smoke seam)
func get_stack() -> GSTStack:
	return _stack


func set_stack(stack: GSTStack) -> void:
	_stack = stack
	_rebuild_undo()
	stack_changed.emit()


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
	if _undo_redo == null or _stack == null:
		return null
	var history_id: int = _undo_redo.get_object_history_id(_stack)
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
