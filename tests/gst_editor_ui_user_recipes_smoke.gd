@tool
extends RefCounted

## User recipes folder and File > Save as Recipe (decision 33), driven
## through the Recipes picker, the start-screen buttons and %FileMenu's
## id_pressed. Points `goshade_turbo/recipes_dir` at an isolated user://
## folder for the run and restores the prior value before quitting.

const TEMP_DIR: String = "user://gst_user_recipes_smoke"

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
	var setting: String = GSTMainPanel.RECIPES_DIR_SETTING
	var original: Variant = ProjectSettings.get_setting(setting)
	_check("setting_registered", ProjectSettings.has_setting(setting) and ProjectSettings.property_get_revert(setting) == GSTMainPanel.USER_RECIPES_DIR_DEFAULT, "value='%s' revert='%s'" % [original, ProjectSettings.property_get_revert(setting)])
	_clear_temp_dir()
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	ProjectSettings.set_setting(setting, TEMP_DIR)
	panel.refresh_recipe_lists()

	var user_path: String = TEMP_DIR.path_join("glow.tres")
	await _run_empty_folder(plugin, panel)
	await _run_save_as_recipe(plugin, panel, user_path)
	await _run_user_glow_opens_user_file(plugin, panel, user_path)

	ProjectSettings.set_setting(setting, original)
	panel.refresh_recipe_lists()
	_clear_temp_dir()
	_check("setting_restored", ProjectSettings.get_setting(setting) == original and panel.get_start_recipe_button_for_path(user_path) == null, "value='%s'" % [ProjectSettings.get_setting(setting)])
	_finish(plugin)


## An empty user folder lists the bundled recipes only, in the picker and on
## the start screen.
func _run_empty_folder(plugin: EditorPlugin, panel: GSTMainPanel) -> void:
	var bundled: Array[String] = _bundled_paths()
	panel.get_recipes_button().pressed.emit()
	await plugin.get_tree().process_frame
	var picker: GSTPicker = panel.get_picker()
	var values: Array[String] = picker.get_all_entry_ids()
	var categories: Dictionary = {}
	for row: Dictionary in picker.get_visible_rows():
		categories[String(row.get("category", ""))] = true
	picker.cancelled.emit()
	await plugin.get_tree().process_frame
	var buttons_ok: bool = true
	for path: String in bundled:
		buttons_ok = buttons_ok and panel.get_start_recipe_button_for_path(path) != null
	_check("empty_folder_bundled_only", not bundled.is_empty() and values == bundled and categories.keys() == ["Recipes"] and buttons_ok, "values=%d bundled=%d categories=%s buttons=%s" % [values.size(), bundled.size(), categories.keys(), buttons_ok])


## Save as Recipe writes <dir>/glow.tres from the open bundled glow plus one
## added layer, opens nothing, and lists the file. A second save prompts
## before overwriting; confirming rewrites it.
func _run_save_as_recipe(plugin: EditorPlugin, panel: GSTMainPanel, user_path: String) -> void:
	await panel.open_recipe("glow")
	await plugin.get_tree().process_frame
	var doc: GSTDocument = panel.get_active_document()
	var added: GSTLayer = panel.get_stack_list().add_layer_by_entry_id("generative/hash")
	await plugin.get_tree().process_frame
	var doc_count: int = panel.get_documents().size()
	_press_file_menu(panel, GSTMainPanel.FILE_SAVE_AS_RECIPE)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var written: bool = FileAccess.file_exists(user_path)
	var nothing_opened: bool = panel.get_documents().size() == doc_count and panel.get_active_document() == doc and doc.current_path.is_empty()
	var listed: bool = panel.get_start_recipe_button_for_path(user_path) != null
	_check("save_as_recipe_writes", added != null and written and nothing_opened and listed and not panel.is_overwrite_dialog_visible(), "added=%s written=%s nothing_opened=%s listed=%s dialog=%s" % [added != null, written, nothing_opened, listed, panel.is_overwrite_dialog_visible()])

	var first_text: String = FileAccess.get_file_as_string(user_path)
	panel.get_stack_list().add_layer_by_entry_id("generative/hash")
	await plugin.get_tree().process_frame
	_press_file_menu(panel, GSTMainPanel.FILE_SAVE_AS_RECIPE)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var prompted: bool = panel.is_overwrite_dialog_visible() and FileAccess.get_file_as_string(user_path) == first_text
	_check("second_save_prompts", prompted, "dialog=%s file_unchanged=%s" % [panel.is_overwrite_dialog_visible(), FileAccess.get_file_as_string(user_path) == first_text])
	await panel._on_overwrite_confirmed()
	await plugin.get_tree().process_frame
	var overwritten: bool = not panel.is_overwrite_dialog_visible() and FileAccess.get_file_as_string(user_path) != first_text and panel.get_documents().size() == doc_count
	_check("confirmed_overwrite_writes", overwritten, "dialog=%s file_changed=%s documents=%d" % [panel.is_overwrite_dialog_visible(), FileAccess.get_file_as_string(user_path) != first_text, panel.get_documents().size()])


## A user recipe named glow lists beside the bundled glow under "User
## recipes" and opens the user file from both the picker and the start
## screen, with Randomize enabled like a bundled recipe.
func _run_user_glow_opens_user_file(plugin: EditorPlugin, panel: GSTMainPanel, user_path: String) -> void:
	var library: GSTLibrary = GSTLibrary.new()
	library.scan()
	var bundled_path: String = GSTMainPanel.RECIPES_DIR.path_join("glow.tres")
	var bundled_layers: int = (GSTStackIO.load(bundled_path, library)["stack"] as GSTStack).layers.size()
	var user_layers: int = (GSTStackIO.load(user_path, library)["stack"] as GSTStack).layers.size()

	panel.get_recipes_button().pressed.emit()
	await plugin.get_tree().process_frame
	var picker: GSTPicker = panel.get_picker()
	var user_category: String = ""
	for row: Dictionary in picker.get_visible_rows():
		if String(row.get("value", "")) == user_path:
			user_category = String(row.get("category", ""))
	var both_listed: bool = picker.get_all_entry_ids().has(bundled_path) and user_category == "User recipes"
	var activated: bool = picker.activate_value(user_path)
	for i: int in range(3):
		await plugin.get_tree().process_frame
	var picker_layers: int = panel.get_stack().layers.size()
	_check("picker_opens_user_glow", both_listed and activated and not panel.is_picker_open() and picker_layers == user_layers and user_layers != bundled_layers and not panel.get_randomize_button().disabled, "both_listed=%s category='%s' activated=%s layers=%d user=%d bundled=%d randomize_disabled=%s" % [both_listed, user_category, activated, picker_layers, user_layers, bundled_layers, panel.get_randomize_button().disabled])

	var button: Button = panel.get_start_recipe_button_for_path(user_path)
	if button != null:
		button.pressed.emit()
	for i: int in range(3):
		await plugin.get_tree().process_frame
	_check("start_button_opens_user_glow", button != null and panel.get_stack().layers.size() == user_layers and panel.get_active_document().recipe_name == "glow", "button=%s layers=%d user=%d" % [button != null, panel.get_stack().layers.size(), user_layers])


func _bundled_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir: DirAccess = DirAccess.open(GSTMainPanel.RECIPES_DIR)
	if dir == null:
		return paths
	for file_name: String in dir.get_files():
		if file_name.ends_with(".tres"):
			paths.append(GSTMainPanel.RECIPES_DIR.path_join(file_name))
	paths.sort()
	return paths


func _clear_temp_dir() -> void:
	if not DirAccess.dir_exists_absolute(TEMP_DIR):
		return
	for file_name: String in DirAccess.get_files_at(TEMP_DIR):
		DirAccess.remove_absolute(TEMP_DIR.path_join(file_name))
	DirAccess.remove_absolute(TEMP_DIR)


func _press_file_menu(panel: GSTMainPanel, id: int) -> void:
	panel.get_file_menu().get_popup().id_pressed.emit(id)


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
