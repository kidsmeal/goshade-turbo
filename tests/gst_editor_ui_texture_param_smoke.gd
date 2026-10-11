@tool
extends RefCounted

## Texture param row (decision 27), driven through the native Texture2D
## property editor's EditorResourcePicker on a source/image layer: assign
## preview_default.png, undo, refuse a built-in GradientTexture2D, and reopen
## a header whose texture path is missing. With a display, saves the
## inspector row and preview with the texture assigned to
## GST_UI_SCREENSHOT_PATH, or DEFAULT_SCREENSHOT_PATH when it is unset.

const DEFAULT_SCREENSHOT_PATH: String = "res://.godot/texture-param.png"
const TEXTURE_PATH: String = "res://addons/goshade_turbo/assets/preview_default.png"
const MISSING_TEXTURE_PATH: String = "res://gst_smoke_missing_texture.png"
const HEADER_FIXTURE_PATH: String = "res://.godot/gst_texture_param_smoke.gdshader"

var _pass_count: int = 0
var _fail_count: int = 0


func run(plugin: EditorPlugin) -> void:
	for i: int in range(5):
		await plugin.get_tree().process_frame
	var panel: GSTMainPanel = plugin.get_panel() as GSTMainPanel
	_check("panel", panel != null, "panel present=%s" % [panel != null])
	if panel == null:
		_finish(plugin)
		return

	EditorInterface.set_main_screen_editor("GoShade Turbo")
	await plugin.get_tree().process_frame
	panel.get_create_empty_button().pressed.emit()
	await plugin.get_tree().process_frame
	panel.get_picker().cancelled.emit()
	await plugin.get_tree().process_frame

	var image: GSTLayer = panel.get_stack_list().add_layer_by_entry_id("source/image")
	var texture: Texture2D = load(TEXTURE_PATH) as Texture2D
	_check("setup", image != null and texture != null, "image=%s texture=%s" % [image, texture])
	if image == null or texture == null:
		_finish(plugin)
		return
	await _select(plugin, panel, image)

	await _run_assign(plugin, panel, image, texture)
	await _run_undo(plugin, panel, image)
	await _run_builtin_refused(plugin, panel, image)
	panel.get_watched_history().redo()
	for i: int in range(3):
		await plugin.get_tree().process_frame
	await _save_screenshot(plugin, panel, image)
	await _run_reopen_missing(plugin, panel)
	_finish(plugin)


## Assigning through the picker writes the param with one history entry, and
## the preview material's sampler holds the texture.
func _run_assign(plugin: EditorPlugin, panel: GSTMainPanel, image: GSTLayer, texture: Texture2D) -> void:
	var history: UndoRedo = panel.get_watched_history()
	var count: int = history.get_history_count()
	var picker: EditorResourcePicker = _picker(panel, image)
	_check("row_is_texture_editor", picker != null and picker.base_type == "Texture2D", "picker=%s base_type='%s'" % [picker != null, picker.base_type if picker != null else ""])
	if picker == null:
		return
	picker.edited_resource = texture
	picker.resource_changed.emit(texture)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var sampler: Variant = panel.get_shader_material().get_shader_parameter(_uniform(image))
	var shown: Resource = _picker(panel, image).edited_resource if _picker(panel, image) != null else null
	_check("assign", is_same(image.get(&"image"), texture) and history.get_history_count() == count + 1 and is_same(shown, texture), "value=%s history=%d->%d shown=%s" % [image.get(&"image"), count, history.get_history_count(), shown])
	_check("assign_preview_sampler", is_same(sampler, texture), "sampler=%s" % [sampler])


## Undo removes the param entry and unsets the sampler.
func _run_undo(plugin: EditorPlugin, panel: GSTMainPanel, image: GSTLayer) -> void:
	panel.get_watched_history().undo()
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var sampler: Variant = panel.get_shader_material().get_shader_parameter(_uniform(image))
	var picker: EditorResourcePicker = _picker(panel, image)
	var shown: Resource = picker.edited_resource if picker != null else null
	_check("undo_clears", not image.has_param_value(&"image") and image.get(&"image") == null and sampler == null and shown == null, "present=%s value=%s sampler=%s shown=%s" % [image.has_param_value(&"image"), image.get(&"image"), sampler, shown])


## A GradientTexture2D has no resource_path: refused, value and history
## unchanged, reason shown beside the row.
func _run_builtin_refused(plugin: EditorPlugin, panel: GSTMainPanel, image: GSTLayer) -> void:
	var inspector: GSTInspectorColumn = panel.get_inspector_column()
	var history: UndoRedo = panel.get_watched_history()
	var count: int = history.get_history_count()
	var picker: EditorResourcePicker = _picker(panel, image)
	if picker == null:
		_check("builtin_refused", false, "picker missing")
		return
	var builtin: GradientTexture2D = GradientTexture2D.new()
	picker.edited_resource = builtin
	picker.resource_changed.emit(builtin)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var label: Label = inspector.get_texture_refusal_label("image")
	var label_ok: bool = label != null and label.is_visible_in_tree() and label.text == GSTInspectorColumn.TEXTURE_NO_PATH_REASON
	var shown: Resource = _picker(panel, image).edited_resource if _picker(panel, image) != null else null
	_check("builtin_refused", image.get(&"image") == null and not image.has_param_value(&"image") and history.get_history_count() == count and shown == null and label_ok, "value=%s history=%d->%d shown=%s label='%s'" % [image.get(&"image"), count, history.get_history_count(), shown, label.text if label != null else "<none>"])


## Reopening a header whose texture path does not exist opens the stack and
## lists the path in the document message label.
func _run_reopen_missing(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "source/image", GSTLayer.Kind.COLOR, true)
	stack.output_color = layer.id
	# A texture value never reaches the generated body, so the export of the
	# unset stack with the path spliced into its header matches a fresh
	# codegen and no hand-edit warning joins the message.
	var library: GSTLibrary = GSTLibrary.new()
	library.scan()
	var built: GSTCodegenResult = GSTExport.build(stack, library)
	var header: String = GSTHeader.header_line(stack)
	var code: String = built.code.replace(header, header.replace("\"params\":{}", "\"params\":{\"image\":\"%s\"}" % MISSING_TEXTURE_PATH))
	var file: FileAccess = FileAccess.open(HEADER_FIXTURE_PATH, FileAccess.WRITE)
	if not built.ok() or not code.contains(MISSING_TEXTURE_PATH) or file == null:
		_check("reopen_missing_texture", false, "fixture build ok=%s spliced=%s file=%s" % [built.ok(), code.contains(MISSING_TEXTURE_PATH), file != null])
		return
	file.store_string(code)
	file.close()
	await panel.reopen_shader_path(HEADER_FIXTURE_PATH)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var reopened: GSTStack = panel.get_stack()
	var opened_ok: bool = reopened != null and reopened.layers.size() == 1 and reopened.layers[0].entry == "source/image" and not reopened.layers[0].has_param_value(&"image")
	var text: String = panel.get_message_label().text
	var path_lines: int = 0
	for message_line: String in text.split("\n"):
		if message_line.contains(MISSING_TEXTURE_PATH):
			path_lines += 1
	_check("reopen_missing_texture", opened_ok and path_lines == 1 and panel.get_message_label().visible, "opened=%s path_lines=%d message='%s'" % [opened_ok, path_lines, text])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HEADER_FIXTURE_PATH))


func _picker(panel: GSTMainPanel, image: GSTLayer) -> EditorResourcePicker:
	var editor: EditorProperty = panel.get_inspector_column().find_editor_property(&"image", image)
	if editor == null:
		return null
	for node: Node in editor.find_children("*", "EditorResourcePicker", true, false):
		return node as EditorResourcePicker
	return null


func _uniform(image: GSTLayer) -> String:
	return GSTUniformNames.param_uniform(image.id, "image", "image")


func _select(plugin: EditorPlugin, panel: GSTMainPanel, layer: GSTLayer) -> void:
	panel.get_stack_list().select_layer(layer.id)
	# Narrow layouts show one pane at a time; tab 1 is the settings pane.
	panel.set_narrow_tab(1)
	for i: int in range(3):
		await plugin.get_tree().process_frame


func _save_screenshot(plugin: EditorPlugin, panel: GSTMainPanel, image: GSTLayer) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var path: String = OS.get_environment("GST_UI_SCREENSHOT_PATH")
	if path.is_empty():
		path = ProjectSettings.globalize_path(DEFAULT_SCREENSHOT_PATH)
	var editor: EditorProperty = panel.get_inspector_column().find_editor_property(&"image", image)
	if editor != null:
		panel.get_inspector_column().get_settings_scroll().ensure_control_visible(editor)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var screenshot_error: Error = plugin.get_tree().root.get_texture().get_image().save_png(path)
	_check("screenshot_assigned", screenshot_error == OK, "path='%s' error=%d" % [path, screenshot_error])


func _check(item: String, ok: bool, detail: String) -> void:
	if ok:
		_pass_count += 1
		print("SMOKE %s PASS %s" % [item, detail])
	else:
		_fail_count += 1
		print("SMOKE %s FAIL %s" % [item, detail])


func _finish(plugin: EditorPlugin) -> void:
	print("SMOKE SUMMARY pass=%d fail=%d" % [_pass_count, _fail_count])
	plugin.get_tree().quit(1 if _fail_count > 0 else 0)
