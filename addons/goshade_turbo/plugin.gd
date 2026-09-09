@tool
extends EditorPlugin

## Registers the main screen tab (decision 13, phase 1 spike item a) and
## routes structural edits through EditorUndoRedoManager (decision 20,
## phase 1 spike item b). Phase 5 mounts the preview column into the panel's
## PreviewSlot; this file does not reach into it.

var _panel: Control = null
var _inspector_plugin: GSTInspectorPlugin = null


func _enter_tree() -> void:
	_inspector_plugin = GSTInspectorPlugin.new()
	add_inspector_plugin(_inspector_plugin)
	_panel = load("res://addons/goshade_turbo/ui/gst_main_panel.tscn").instantiate()
	get_editor_interface().get_editor_main_screen().add_child(_panel)
	_panel.set_editor_plugin(self)
	_panel.set_undo_redo_manager(get_undo_redo())
	_panel.hide()
	var smoke_flag: String = OS.get_environment("GST_EDITOR_SMOKE")
	if not smoke_flag.is_empty():
		var smoke: RefCounted = load("res://tests/gst_editor_smoke.gd").new()
		await smoke.run(self)


func _exit_tree() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "GoShade Turbo"


func _get_plugin_icon() -> Texture2D:
	return load("res://addons/goshade_turbo/assets/gst_icon.svg") as Texture2D


func _make_visible(visible: bool) -> void:
	if _panel != null:
		_panel.visible = visible


func get_panel() -> Control:
	return _panel
