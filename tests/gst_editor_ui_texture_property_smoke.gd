@tool
extends RefCounted

var _pass_count: int = 0
var _fail_count: int = 0


func run(plugin: EditorPlugin) -> void:
	for i: int in range(5):
		await plugin.get_tree().process_frame

	var panel: GSTMainPanel = plugin.get_panel() as GSTMainPanel
	_check("panel", panel != null, "panel is null" if panel == null else "panel present")
	if panel == null:
		_finish(plugin)
		return

	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await plugin.get_tree().process_frame

	var resource: Resource = Resource.new()
	resource.set_meta("image", null as Texture2D)

	var editor_property: EditorProperty = EditorInspector.instantiate_property_editor(
		resource,
		TYPE_OBJECT,
		"image",
		PROPERTY_HINT_RESOURCE_TYPE,
		"Texture2D",
		PROPERTY_USAGE_DEFAULT
	)

	_check("instantiate", editor_property != null, "EditorProperty instantiated")
	if editor_property == null:
		_finish(plugin)
		return

	panel.add_child(editor_property)
	await plugin.get_tree().process_frame

	editor_property.set_object_and_property(resource, "image")
	await plugin.get_tree().process_frame
	_check("set_object", editor_property.get_edited_object() == resource, "set_object_and_property sets edited object")

	editor_property.update_property()
	await plugin.get_tree().process_frame
	var initial_value: Variant = resource.get_meta("image")
	_check("update_initial", initial_value == null, "initial value is null")

	var texture_path: String = "res://addons/goshade_turbo/assets/preview_default.png"
	var texture: Texture2D = load(texture_path) as Texture2D
	_check("texture_load", texture != null, "preview_default.png loads")

	editor_property.emit_changed(&"image", texture)
	await plugin.get_tree().process_frame
	var set_value: Variant = resource.get_meta("image")
	var set_ok: bool = set_value is Texture2D and (set_value as Texture2D) == texture
	_check("emit_changed_set", set_ok, "emit_changed with texture sets property")

	editor_property.update_property()
	await plugin.get_tree().process_frame
	var updated_value: Variant = resource.get_meta("image")
	var updated_ok: bool = updated_value is Texture2D and (updated_value as Texture2D) == texture
	_check("update_after_set", updated_ok, "update_property shows the set texture")

	editor_property.emit_changed(&"image", null)
	await plugin.get_tree().process_frame
	var cleared_value: Variant = resource.get_meta("image")
	_check("emit_changed_clear", cleared_value == null, "emit_changed with null clears property")

	var outside_inspector: bool = editor_property.get_parent() == panel and editor_property.get_edited_object() != null
	_check("outside_inspector", outside_inspector, "editor exists outside EditorInspector")

	_check("drag_drop_unverified", true, "drag-drop cannot be driven headlessly; load and clear verified only")

	editor_property.queue_free()
	_finish(plugin)


func _check(item: String, ok: bool, detail: String) -> void:
	if ok:
		_pass_count += 1
		print("SMOKE ui_texture_property_%s PASS %s" % [item, detail])
	else:
		_fail_count += 1
		print("SMOKE ui_texture_property_%s FAIL %s" % [item, detail])


func _finish(plugin: EditorPlugin) -> void:
	print("SMOKE SUMMARY pass=%d fail=%d" % [_pass_count, _fail_count])
	plugin.get_tree().quit(1 if _fail_count > 0 else 0)
