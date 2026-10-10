@tool
extends RefCounted

var _pass_count: int = 0
var _fail_count: int = 0


class _ImageHolder extends Resource:
	@export var image: Texture2D


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

	var resource: _ImageHolder = _ImageHolder.new()

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

	editor_property.set_object_and_property(resource, "image")
	await plugin.get_tree().process_frame
	_check("set_object", editor_property.get_edited_object() == resource, "set_object_and_property sets edited object")

	panel.add_child(editor_property)
	await plugin.get_tree().process_frame

	editor_property.update_property()
	await plugin.get_tree().process_frame
	var picker: EditorResourcePicker = null
	for child in editor_property.find_children("*", "EditorResourcePicker", true, false):
		picker = child as EditorResourcePicker
		break
	var initial_ok: bool = picker != null and picker.edited_resource == null
	_check("update_initial", initial_ok, "initial value null picker.edited_resource=%s" % picker.edited_resource if picker != null else "picker not found")

	var texture_path: String = "res://addons/goshade_turbo/assets/preview_default.png"
	var texture: Texture2D = load(texture_path) as Texture2D
	_check("texture_load", texture != null, "preview_default.png loads")

	var property_changed_fired: bool = false
	var property_changed_name: StringName = &""
	var property_changed_value: Variant = null
	var signal_connection = editor_property.property_changed.connect(func(prop: StringName, value: Variant) -> void:
		property_changed_fired = true
		property_changed_name = prop
		property_changed_value = value
		resource.set(prop, value)
	)

	editor_property.emit_changed(&"image", texture)
	await plugin.get_tree().process_frame
	var emit_ok: bool = property_changed_fired and property_changed_name == &"image" and property_changed_value == texture
	_check("property_changed_emitted", emit_ok, "emit_changed fired property_changed signal with image and texture")

	editor_property.update_property()
	await plugin.get_tree().process_frame
	var updated_picker: EditorResourcePicker = null
	for child in editor_property.find_children("*", "EditorResourcePicker", true, false):
		updated_picker = child as EditorResourcePicker
		break
	var updated_ok: bool = updated_picker != null and updated_picker.edited_resource == texture
	_check("update_after_set", updated_ok, "update_property shows the set texture picker.edited_resource=%s (expect %s)" % [updated_picker.edited_resource if updated_picker != null else null, texture])

	property_changed_fired = false
	editor_property.emit_changed(&"image", null)
	await plugin.get_tree().process_frame
	var cleared_ok: bool = property_changed_fired and property_changed_name == &"image" and property_changed_value == null
	_check("property_changed_cleared", cleared_ok, "emit_changed(null) fired property_changed with null")

	editor_property.update_property()
	await plugin.get_tree().process_frame
	var cleared_picker: EditorResourcePicker = null
	for child in editor_property.find_children("*", "EditorResourcePicker", true, false):
		cleared_picker = child as EditorResourcePicker
		break
	var cleared_display_ok: bool = cleared_picker != null and cleared_picker.edited_resource == null
	_check("update_after_clear", cleared_display_ok, "update_property shows cleared texture picker.edited_resource=%s (expect null)" % cleared_picker.edited_resource if cleared_picker != null else "picker not found")

	var no_inspector_ancestor: bool = true
	var n: Node = editor_property.get_parent()
	while n != null:
		if n is EditorInspector:
			no_inspector_ancestor = false
			break
		n = n.get_parent()
	var outside_ok: bool = editor_property.get_parent() == panel and editor_property.get_edited_object() != null and no_inspector_ancestor
	_check("outside_inspector", outside_ok, "editor exists outside EditorInspector parent=%s has_inspector_ancestor=%s" % [editor_property.get_parent() == panel, not no_inspector_ancestor])

	editor_property.disconnect(signal_connection)
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
