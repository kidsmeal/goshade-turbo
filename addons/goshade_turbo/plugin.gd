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


## Godot's confirmed-quit/scene-close status list (decision 10, phase 7,
## docs/SHADER_TABS_reviewed-plan.md): lists every dirty shader document by
## name for an empty for_scene (the editor's own quit confirmation), and
## reports none for a nonempty one -- GoShade's documents are session-scoped,
## never scene-owned, so closing a game scene must never treat them as if
## they belonged to it.
func _get_unsaved_status(for_scene: String) -> String:
	if _panel == null:
		return ""
	return (_panel as GSTMainPanel).get_unsaved_status_text(for_scene)


## Godot's own "Save and Quit" callback (decision 10): void, unawaited, and
## unable to veto shutdown. Delegates synchronously to the panel, which
## saves every dirty named document and recovers every untitled or failed-
## path one into a project-local record before the process actually exits.
func _save_external_data() -> void:
	if _panel == null:
		return
	(_panel as GSTMainPanel).save_external_data()
