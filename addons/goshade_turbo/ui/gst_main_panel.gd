@tool
class_name GSTMainPanel
extends VBoxContainer

## Main screen panel (decision 13): three-column layout (stack list,
## inspector column, a phase-5 preview placeholder), an output block docked
## under the stack list, and a message label at the bottom that shows the
## last codegen error or a refused structural edit's reason.
##
## Holds the current GSTStack (a new empty stack on open) and the GSTLibrary
## (scanned once). stack_changed fires after every structural edit so a
## later column (phase 5's preview) can resync.

signal stack_changed

@onready var _stack_list: GSTStackList = %StackList
@onready var _output_block: GSTOutputBlock = %OutputBlock
@onready var _inspector_column: GSTInspectorColumn = %InspectorColumn
@onready var _message_label: Label = %MessageLabel
@onready var _preview_slot: Control = %PreviewSlot

var _stack: GSTStack = null
var _library: GSTLibrary = null
var _undo_redo: EditorUndoRedoManager = null
var _undo: GSTUndo = null


func _ready() -> void:
	_library = GSTLibrary.new()
	_library.scan()
	_stack = GSTStack.new()
	_stack_list.layer_selected.connect(_on_layer_selected)
	_stack_list.structural_edit_refused.connect(_on_refused)
	_inspector_column.edit_refused.connect(_on_refused)


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
	_refresh_codegen_error()


func get_stack() -> GSTStack:
	return _stack


func set_stack(stack: GSTStack) -> void:
	_stack = stack
	_rebuild_undo()
	stack_changed.emit()


func get_library() -> GSTLibrary:
	return _library


func get_undo() -> GSTUndo:
	return _undo


func get_stack_list() -> GSTStackList:
	return _stack_list


func get_output_block() -> GSTOutputBlock:
	return _output_block


func get_inspector_column() -> GSTInspectorColumn:
	return _inspector_column


func get_preview_slot() -> Control:
	return _preview_slot


func get_message_label() -> Label:
	return _message_label


func _on_layer_selected(layer_id: StringName) -> void:
	_inspector_column.edit(layer_id)


func _on_refused(reason: String) -> void:
	_message_label.text = reason


## GSTUndo's on_changed callback: fires after every do and undo.
func _on_stack_changed() -> void:
	_stack_list.refresh()
	_output_block.refresh()
	_inspector_column.edit(_stack_list.get_selected_layer_id())
	stack_changed.emit()
	_refresh_codegen_error()


func _refresh_codegen_error() -> void:
	if _stack == null or _library == null:
		return
	var result: GSTCodegenResult = GSTCodegen.generate_result(_stack, _library)
	_message_label.text = result.error
