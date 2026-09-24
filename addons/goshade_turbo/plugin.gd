@tool
extends EditorPlugin

## Registers the main screen tab. The panel owns its own UndoRedo
## (GSTMainPanel._ready installs it); no EditorInspectorPlugin is registered.

var _panel: Control = null


func _enter_tree() -> void:
	_panel = load("res://addons/goshade_turbo/ui/gst_main_panel.tscn").instantiate()
	get_editor_interface().get_editor_main_screen().add_child(_panel)
	_panel.set_editor_plugin(self)
	_panel.hide()
	var smoke_flag: String = OS.get_environment("GST_EDITOR_SMOKE")
	if not smoke_flag.is_empty() and ResourceLoader.exists("res://tests/gst_editor_smoke.gd"):
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


## Godot's quit/scene-close unsaved status. Lists every dirty shader document
## for an empty for_scene (editor quit) and none for a nonempty one:
## documents are session-scoped, never scene-owned.
func _get_unsaved_status(for_scene: String) -> String:
	if _panel == null:
		return ""
	return (_panel as GSTMainPanel).get_unsaved_status_text(for_scene)


## Godot's "Save and Quit" callback: void, unawaited, cannot veto shutdown.
## Delegates synchronously to the panel, which saves every dirty named
## document and records every untitled or failed-path one project-locally
## before exit.
func _save_external_data() -> void:
	if _panel == null:
		return
	(_panel as GSTMainPanel).save_external_data()
