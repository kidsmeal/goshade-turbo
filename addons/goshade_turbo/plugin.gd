@tool
extends EditorPlugin

## Registers the main screen tab (decision 13, phase 1 spike item a). Phase 2
## (docs/SHADER_TABS_reviewed-plan.md) routes structural and native property
## edits through a standalone UndoRedo the panel owns itself
## (GSTMainPanel._ready installs it directly): this plugin no longer hands
## the panel an EditorUndoRedoManager, and no longer registers an
## EditorInspectorPlugin, since gst_inspector_column.gd builds its own
## native property rows directly instead of routing GSTLayer/GSTCoordBlock
## through a real EditorInspector. Phase 5 mounts the preview column into
## the panel's PreviewSlot; this file does not reach into it.

var _panel: Control = null


func _enter_tree() -> void:
	_panel = load("res://addons/goshade_turbo/ui/gst_main_panel.tscn").instantiate()
	get_editor_interface().get_editor_main_screen().add_child(_panel)
	_panel.set_editor_plugin(self)
	_panel.hide()
	var smoke_flag: String = OS.get_environment("GST_EDITOR_SMOKE")
	if not smoke_flag.is_empty():
		var smoke: RefCounted = load("res://tests/gst_editor_smoke.gd").new()
		await smoke.run(self)


func _exit_tree() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null


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
