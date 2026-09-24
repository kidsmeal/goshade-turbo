@tool
class_name GSTMainPanel
extends VBoxContainer

## Main screen panel: an editing area (Layers and Layer settings in a split
## or tabs) beside a persistent preview area; Final output sits below the
## preview.
##
## Owns the open GSTDocuments and the GSTLibrary (scanned once).
## stack_changed fires after every structural edit; this panel self-connects
## it to _resync_material. A caller that mutates the stack directly,
## bypassing GSTUndo, re-emits it to force a resync.
##
## GSTMaterialSync resyncs on: (1) stack_changed, fired by GSTUndo's bound
## _notify/_notify_replace do/undo pair on every edit, undo, and redo;
## (2) diagnostic preview changes; (3) a preset or preview-image change.
## GSTPreview.target_rect_changed does not run the full resync: it writes
## only gst_rect_size via GSTMaterialSync.write_rect_size, since it can fire
## once per frame during a drag.

signal stack_changed

@onready var _stack_list: GSTStackList = %StackList
@onready var _output_block: GSTOutputBlock = %OutputBlock
@onready var _inspector_column: GSTInspectorColumn = %InspectorColumn
@onready var _message_label: Label = %MessageLabel
@onready var _preview: GSTPreview = %Preview
@onready var _preset_option: OptionButton = %PresetOption
@onready var _image_button: Button = %ImageButton
@onready var _layer_menu: MenuButton = %LayerMenu
@onready var _return_to_effect: Button = %ReturnToEffect
@onready var _preview_heading: Label = %PreviewHeading
@onready var _preview_status: Label = %PreviewStatus
@onready var _error_scroll: ScrollContainer = %ErrorScroll
@onready var _start_screen: VBoxContainer = %StartScreen
@onready var _recipe_grid: GridContainer = %RecipeGrid
@onready var _create_empty: Button = %CreateEmpty
@onready var _start_open: Button = %StartOpen
@onready var _coord_space_option: OptionButton = %CoordSpaceOption
@onready var _save_button: Button = %SaveButton
@onready var _export_button: Button = %ExportButton
@onready var _recipes_button: Button = %RecipesButton
@onready var _randomize_button: Button = %RandomizeButton
@onready var _file_menu: MenuButton = %FileMenu
@onready var _main_split: HSplitContainer = %MainSplit
@onready var _editing_area: PanelContainer = %EditingArea
@onready var _editing_split: HSplitContainer = %EditingSplit
@onready var _editing_tabs: TabContainer = %EditingTabs
@onready var _layer_pane: VBoxContainer = %LayerPane
@onready var _settings_pane: VBoxContainer = %SettingsPane
@onready var _picker: GSTPicker = %EmbeddedPicker
@onready var _codegen_message: Label = %CodegenMessage
@onready var _editing_content: VBoxContainer = %EditingContent
@onready var _preview_area: VBoxContainer = %PreviewArea
@onready var _shader_tab_row: HBoxContainer = %ShaderTabRow
@onready var _shader_tabs: TabBar = %ShaderTabs
@onready var _new_tab_button: Button = %NewTabButton

const COORD_SPACE_NAMES: Array[String] = ["uv", "screen_uv", "local"]
## Every .tres here is listed by the Recipes picker and the start screen.
const RECIPES_DIR: String = "res://addons/goshade_turbo/recipes"
const LAYOUT_METADATA_SECTION: String = "goshade_turbo/layout"
const DEFAULT_MAIN_RATIO: float = 0.6
const DEFAULT_INNER_RATIO: float = 0.42
const PREVIEW_IMAGE_MINIMUM: Vector2 = Vector2(220.0, 180.0)
const FILE_NEW: int = 0
const FILE_OPEN: int = 1
const FILE_SAVE_AS: int = 2
const FILE_REOPEN_SHADER: int = 3

var _stack: GSTStack = null
var _library: GSTLibrary = null
## Every open GSTDocument, in creation order. _close_document_now is the only
## pruner.
var _documents: Array[GSTDocument] = []
## The document bound to the shared UI (stack list, inspector column, output
## block, coord-space dropdown, preview). Set by _activate_document; cleared
## by _exit_tree.
var _active_document: GSTDocument = null
## Mirrors of _active_document.undo_redo/.undo. Kept in sync only by
## _install_stack/_activate_document.
var _undo_redo: UndoRedo = null
var _undo: GSTUndo = null
var _preview_sync: GSTMaterialSync = GSTMaterialSync.new()
var _material: ShaderMaterial = _preview_sync.get_material()
var _preview_layer_id: StringName = &""
var _start_recipe_buttons: Dictionary = {}
## Guards programmatic _coord_space_option.select() calls from re-entering
## _on_coord_space_selected.
var _syncing_coord_space: bool = false
var _file_dialog: EditorFileDialog = null

## The .tres the active stack was last opened from or saved to; "" for a
## never-saved stack or one reopened from a .gdshader (no .tres of its own).
var _current_path: String = ""
var _open_dialog: EditorFileDialog = null
var _save_as_dialog: EditorFileDialog = null
var _export_dialog: EditorFileDialog = null
var _reopen_shader_dialog: EditorFileDialog = null
var _overwrite_dialog: ConfirmationDialog = null
## Save/Discard/Cancel prompt for closing a dirty document. OK is relabeled
## "Save"; "Discard" is added via add_button, whose press never auto-hides the
## dialog (AcceptDialog::_custom_action), so _on_close_custom_action hides it.
var _close_dialog: ConfirmationDialog = null
var _close_discard_button: Button = null

## Each *_pending_* Dictionary below is `{}` (no request captured: the
## dialog-opening handler was never called, e.g. a direct call to
## save_to_path/export_to_path/open_path/reopen_shader_path or a
## *_file_selected seam) or `{"request_id": int, "doc_id": int}`, captured
## when the dialog opened (for _pending_overwrite, when _export_stack_to_path
## found it needs confirmation). request_id is a monotonic stamp from
## _next_file_request_id; resolution depends only on doc_id resolving through
## _find_document_by_session_id. _resolve_pending_document is the only reader.
var _next_file_request_id: int = 0
var _pending_save_as: Dictionary = {}
var _pending_export: Dictionary = {}
## Also carries "path": the export target this confirmation answers.
var _pending_overwrite: Dictionary = {}
var _pending_open: Dictionary = {}
var _pending_reopen: Dictionary = {}
var _pending_image: Dictionary = {}
## The document _close_dialog is asking about, same shape as above. A
## document closed while the prompt was up resolves to null.
var _pending_close: Dictionary = {}

## True only after open_recipe() installs a shipped recipe; gates the
## Randomize button. New, Open, and Reopen Shader clear it.
var _recipe_open: bool = false

## Overrides the RandomNumberGenerator _on_randomize_pressed draws from. null
## means a fresh OS-seeded RandomNumberGenerator on every press.
var _randomize_rng: RandomNumberGenerator = null
var _editor_settings: EditorSettings = null
var _tab_breakpoint: float = 0.0
var _narrow_layout: bool = false
var _restoring_layout: bool = false
var _preferred_narrow_tab: int = 0
var _picker_context: Dictionary = {}
var _picker_focus: WeakRef = null
var _applying_choice: bool = false
var _control_refusals: Dictionary = {}
## Tab index -> GSTDocument.session_id, rebuilt wholesale by _refresh_tabs(),
## 1:1 with %ShaderTabs's tabs. tab_changed/tab_close_pressed resolve a tab
## index to a document through this plus _find_document_by_session_id, so a
## signal delivered after a rebuild never targets the wrong document.
var _tab_session_ids: Array[int] = []
## Guards the programmatic %ShaderTabs.current_tab write in _refresh_tabs():
## TabBar.set_current_tab() emits tab_changed whenever the index moves, which
## must not re-enter _on_tab_bar_tab_changed's activate_document call.
var _syncing_tabs: bool = false
## Guards programmatic _preset_option.select() calls from re-entering
## _on_preset_selected. OptionButton.select() does not emit item_selected;
## the guard is defensive.
var _syncing_preview_controls: bool = false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = PREVIEW_IMAGE_MINIMUM
	_tab_breakpoint = _measure_tab_breakpoint()
	_main_split.dragged.connect(_on_main_split_dragged)
	_main_split.resized.connect(_on_editing_area_resized)
	_editing_split.dragged.connect(_on_inner_split_dragged)
	_editing_area.resized.connect(_on_editing_area_resized)
	_layer_pane.minimum_size_changed.connect(_on_editing_area_resized)
	_settings_pane.minimum_size_changed.connect(_on_editing_area_resized)
	resized.connect(_on_editing_area_resized)
	_editing_tabs.tab_changed.connect(_on_editing_tab_changed)
	_inspector_column.section_state_changed.connect(_on_section_state_changed)
	_inspector_column.color_popup_undo_redo_requested.connect(_apply_keyboard_undo_redo)
	_library = GSTLibrary.new()
	_library.scan()
	_stack = GSTStack.new()
	_stack_list.layer_selected.connect(_on_layer_selected)
	for control: Node in [_stack_list, _inspector_column, _output_block]:
		control.set_shared_picker(_picker)
		control.chooser_requested.connect(_on_chooser_requested)
	_picker.choice_requested.connect(_on_picker_choice)
	_picker.cancelled.connect(_close_picker)
	_picker.tab_changed.connect(_on_picker_tab_changed)
	stack_changed.connect(_resync_material)

	# _resync_material must run before the material is handed to the preview
	# node: GSTMaterialSync.sync() creates _material.shader and sets non-empty
	# code in the same call. Assigning a ShaderMaterial to a CanvasItem while
	# its Shader still has empty code, then setting .code later, leaves the
	# render stuck on the node's unshaded appearance (confirmed by an isolated
	# repro on the same Shader object).
	_resync_material()
	_preview.set_shader_material(_material)
	_preview.target_rect_changed.connect(_on_target_rect_changed)

	for preset_name: String in GSTPreviewPresets.PRESET_NAMES:
		_preset_option.add_item(preset_name)
	_preset_option.item_selected.connect(_on_preset_selected)
	_image_button.pressed.connect(_on_image_button_pressed)
	_layer_menu.get_popup().add_item("Preview this layer", 0)
	_layer_menu.get_popup().id_pressed.connect(_on_layer_menu_pressed)
	_return_to_effect.pressed.connect(_on_return_to_effect_pressed)

	for space_name: String in COORD_SPACE_NAMES:
		_coord_space_option.add_item(space_name)
	_coord_space_option.item_selected.connect(_on_coord_space_selected)

	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.add_filter("*.png, *.jpg, *.jpeg, *.webp, *.svg", "Images")
	_file_dialog.file_selected.connect(_on_preview_image_selected)
	# Cancel/Escape clears the captured request so a later resolution of the
	# same dialog cannot pick it up. hide() alone does not emit canceled
	# (AcceptDialog::_cancel_pressed only); a caller that force-hides a dialog
	# (hide_export_dialog()) clears its own pending capture.
	_file_dialog.canceled.connect(func() -> void: _pending_image = {})
	add_child(_file_dialog)

	_save_button.pressed.connect(_on_save_pressed)
	_export_button.pressed.connect(_on_export_pressed)
	var file_popup: PopupMenu = _file_menu.get_popup()
	file_popup.add_item("New", FILE_NEW)
	file_popup.add_item("Open...", FILE_OPEN)
	file_popup.add_separator()
	file_popup.add_item("Save As...", FILE_SAVE_AS)
	file_popup.add_item("Reopen Shader...", FILE_REOPEN_SHADER)
	file_popup.id_pressed.connect(_on_file_menu_pressed)
	_style_file_menu_as_button()

	_recipes_button.pressed.connect(_on_recipes_pressed)
	_randomize_button.pressed.connect(_on_randomize_pressed)
	_set_recipe_open(false)

	# Matches the editor's scene-tab add button (EditorSceneTabs): flat,
	# icon-only, "Add" icon read from the editor theme at runtime.
	_new_tab_button.flat = true
	_new_tab_button.icon = get_theme_icon(&"Add", &"EditorIcons")
	_new_tab_button.pressed.connect(_on_new_pressed)
	# tab_changed fires only when current_tab moves (TabBar.set_current_tab),
	# so a reclick on the active tab is a no-op. tab_close_pressed fires on the
	# close icon only, independent of tab_changed/tab_clicked.
	_shader_tabs.tab_changed.connect(_on_tab_bar_tab_changed)
	_shader_tabs.tab_close_pressed.connect(_on_tab_bar_close_pressed)
	# Pauses the preview SubViewport while the main-screen tab is hidden
	# (plugin.gd _make_visible(false)) and resumes it when shown.
	visibility_changed.connect(_on_panel_visibility_changed)
	# _refresh_tabs() only calls ensure_tab_visible() on a rebuild. A resize
	# alone (window, editor scale, narrow-layout toggle) can shrink %ShaderTabs
	# and scroll the active tab out of view; its resized signal covers that.
	_shader_tabs.resized.connect(_on_tab_scroll_resized)
	# %ShaderTabs is SIZE_SHRINK_BEGIN (gst_main_panel.tscn), so its width is
	# custom_minimum_size.x, recomputed by _apply_tab_bar_width() on a row
	# resize (here) or a tab content change (_refresh_tabs()).
	_shader_tab_row.resized.connect(_on_tab_row_resized)

	_open_dialog = EditorFileDialog.new()
	_open_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_open_dialog.add_filter("*.tres", "GoShade Turbo Stack")
	_open_dialog.file_selected.connect(_on_open_file_selected)
	_open_dialog.canceled.connect(func() -> void: _pending_open = {})
	add_child(_open_dialog)

	_save_as_dialog = EditorFileDialog.new()
	_save_as_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_save_as_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_save_as_dialog.add_filter("*.tres", "GoShade Turbo Stack")
	_save_as_dialog.file_selected.connect(_on_save_as_file_selected)
	_save_as_dialog.canceled.connect(func() -> void: _pending_save_as = {})
	add_child(_save_as_dialog)

	_export_dialog = EditorFileDialog.new()
	_export_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_export_dialog.add_filter("*.gdshader", "GoShade Turbo Shader")
	_export_dialog.file_selected.connect(_on_export_file_selected)
	_export_dialog.canceled.connect(func() -> void: _pending_export = {})
	add_child(_export_dialog)

	_reopen_shader_dialog = EditorFileDialog.new()
	_reopen_shader_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_reopen_shader_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_reopen_shader_dialog.add_filter("*.gdshader", "GoShade Turbo Shader")
	_reopen_shader_dialog.file_selected.connect(_on_reopen_shader_file_selected)
	_reopen_shader_dialog.canceled.connect(func() -> void: _pending_reopen = {})
	add_child(_reopen_shader_dialog)

	_overwrite_dialog = ConfirmationDialog.new()
	_overwrite_dialog.confirmed.connect(_on_overwrite_confirmed)
	_overwrite_dialog.canceled.connect(func() -> void: _pending_overwrite = {})
	add_child(_overwrite_dialog)

	_close_dialog = ConfirmationDialog.new()
	_close_dialog.ok_button_text = "Save"
	_close_discard_button = _close_dialog.add_button("Discard", true, "discard")
	_close_dialog.confirmed.connect(_on_close_save_requested)
	_close_dialog.canceled.connect(func() -> void: _pending_close = {})
	_close_dialog.custom_action.connect(_on_close_custom_action)
	add_child(_close_dialog)
	_build_start_screen()
	_apply_default_layout.call_deferred()

	# Installs the initial never-saved document with no undo action: there is
	# nothing before the first document to undo back to.
	_activate_document(_create_document(_stack, "", false))
	# Reopens any dirty document a prior save_external_data() call recovered,
	# before the start screen is shown. No-op when no index.json exists.
	load_recovery_records()


## Releases every open document's UndoRedo (an Object with no owner to free
## it) and its GSTUndo adapter, which holds bound Callables closing over this
## panel and the document.
func _exit_tree() -> void:
	for doc: GSTDocument in _documents:
		doc.teardown()
	_documents.clear()
	_active_document = null
	_undo_redo = null
	_undo = null


## Wired-by: visibility_changed (_ready()).
func _on_panel_visibility_changed() -> void:
	_preview.set_active(is_visible_in_tree())


## Wired-by: %ShaderTabs.resized (_ready()).
func _on_tab_scroll_resized() -> void:
	if _active_document == null:
		return
	_await_ensure_active_tab_visible(get_tab_index(_active_document))


## Wired-by: %ShaderTabRow.resized (_ready()).
func _on_tab_row_resized() -> void:
	_apply_tab_bar_width()


## Sizes %ShaderTabs to its tab content, bounded to the row's available width
## minus %NewTabButton and the row separation. %ShaderTabs is
## SIZE_SHRINK_BEGIN with clip_tabs true (gst_main_panel.tscn); clip_tabs
## forces TabBar::get_minimum_size() to 0, so its width is entirely
## custom_minimum_size.x, written here. Called from _refresh_tabs() and
## _on_tab_row_resized.
##
## reset_size(): setting custom_minimum_size.x alone does not resize the
## Control synchronously (Container::queue_sort() is deferred), and
## TabBar::_update_cache decides its overflow arrows from the stale
## get_size().width. reset_size() runs Control::set_size synchronously,
## clamped up to the new minimum, and fires NOTIFICATION_RESIZED in-line.
##
## clip_tabs off/on: TabBar::get_tab_width() uses the wider of
## tab_hovered/tab_unselected for every non-current tab, while
## get_minimum_size() applies tab_hovered only to the hovered tab, so the
## measured content width under-counts and the overflow arrows can flip with
## the real mouse position. The extra toggle forces one more _update_cache
## pass against the corrected size (Godot 4.4, tab_bar.cpp).
func _apply_tab_bar_width() -> void:
	if _shader_tab_row == null or _shader_tabs == null or _new_tab_button == null:
		return
	var content_width: float = _measure_tab_bar_content_width()
	var separation: float = float(_shader_tab_row.get_theme_constant("separation"))
	var available: float = maxf(0.0, _shader_tab_row.size.x - _new_tab_button.size.x - separation)
	_shader_tabs.custom_minimum_size.x = minf(content_width, available)
	_shader_tabs.reset_size()
	_shader_tabs.clip_tabs = false
	_shader_tabs.clip_tabs = true


## %ShaderTabs's unclipped tab content width. TabBar::get_minimum_size sums
## every tab's styled width and zeroes the result when clip_tabs is true, so
## clip_tabs is toggled off for one synchronous read. clip_tabs true is what
## enables the native overflow scroll arrows.
func _measure_tab_bar_content_width() -> float:
	_shader_tabs.clip_tabs = false
	var width: float = _shader_tabs.get_minimum_size().x
	_shader_tabs.clip_tabs = true
	return width


## MenuButton::MenuButton calls set_flat(true) unconditionally (Godot 4.4),
## and the editor theme supplies distinct "MenuButton" styleboxes, so
## gst_main_panel.tscn's flat = false has no effect. Copying "Button"
## styleboxes/font colors onto %FileMenu as per-instance overrides makes it
## draw like the toolbar's plain Buttons. has_theme_stylebox/has_theme_color
## gate each copy so a missing theme item leaves the default.
func _style_file_menu_as_button() -> void:
	for style_name: StringName in [&"normal", &"hover", &"pressed", &"disabled", &"focus", &"hover_pressed"]:
		if has_theme_stylebox(style_name, &"Button"):
			_file_menu.add_theme_stylebox_override(style_name, get_theme_stylebox(style_name, &"Button"))
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_disabled_color", &"font_focus_color"]:
		if has_theme_color(color_name, &"Button"):
			_file_menu.add_theme_color_override(color_name, get_theme_color(color_name, &"Button"))


func _build_start_screen() -> void:
	for recipe_name: String in _recipe_names():
		var button: Button = Button.new()
		button.text = recipe_name.replace("_", " ").capitalize()
		button.tooltip_text = "Open %s as an editable stack." % button.text
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 48.0
		button.clip_text = true
		button.pressed.connect(open_recipe.bind(recipe_name))
		_recipe_grid.add_child(button)
		_start_recipe_buttons[recipe_name] = button
	_create_empty.pressed.connect(_on_new_pressed)
	_start_open.pressed.connect(_on_open_pressed)
	_editing_content.hide()
	_set_picker_modality(false)


func _dismiss_start_screen() -> void:
	_start_screen.hide()
	_editing_content.show()
	_set_picker_modality(is_picker_open())
	update_responsive_layout.call_deferred()


## Wired-by: none (editor smoke seam).
func is_start_screen_visible() -> bool:
	return _start_screen.visible


## Wired-by: none (editor smoke seam).
func get_start_recipe_button(recipe_name: String) -> Button:
	return _start_recipe_buttons.get(recipe_name) as Button


## Wired-by: none (editor smoke seam).
func get_create_empty_button() -> Button:
	return _create_empty


## Wired-by: none (editor smoke seam).
func get_start_open_button() -> Button:
	return _start_open


func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_settings = plugin.get_editor_interface().get_editor_settings()
	restore_layout_metadata.call_deferred()


func _apply_default_layout() -> void:
	_tab_breakpoint = _measure_tab_breakpoint()
	update_responsive_layout()
	_set_split_ratio(_main_split, DEFAULT_MAIN_RATIO)
	_set_split_ratio(_editing_split, DEFAULT_INNER_RATIO)


func _measure_tab_breakpoint() -> float:
	var separation: float = float(_editing_split.get_theme_constant("separation"))
	return _layer_pane.get_combined_minimum_size().x + _settings_pane.get_combined_minimum_size().x + separation


func _on_editing_area_resized() -> void:
	update_responsive_layout.call_deferred()


func update_responsive_layout() -> void:
	if _layer_pane == null or _settings_pane == null:
		return
	_tab_breakpoint = _measure_tab_breakpoint()
	var main_available: float = maxf(0.0, _main_split.size.x - float(_main_split.get_theme_constant("separation")))
	var width: float = minf(_editing_area.size.x, main_available * _current_main_ratio())
	var should_narrow: bool = width <= _tab_breakpoint + 0.5
	if should_narrow == _narrow_layout:
		return
	# Reparenting emits tab_changed before both panes have been installed.
	var preferred_tab: int = _preferred_narrow_tab
	_narrow_layout = should_narrow
	if _narrow_layout:
		_layer_pane.reparent(_editing_tabs)
		_settings_pane.reparent(_editing_tabs)
		_editing_split.hide()
		_editing_tabs.show()
		_editing_tabs.set_tab_title(0, "Layers")
		_editing_tabs.set_tab_title(1, "Layer settings")
		_editing_tabs.current_tab = preferred_tab
	else:
		_layer_pane.reparent(_editing_split)
		_settings_pane.reparent(_editing_split)
		_layer_pane.show()
		_settings_pane.show()
		_editing_tabs.hide()
		_editing_split.show()
		_apply_inner_ratio.call_deferred(_metadata_float("inner_ratio", DEFAULT_INNER_RATIO))
	_preferred_narrow_tab = preferred_tab
	_persist_metadata("narrow_tab", _preferred_narrow_tab)


func _on_main_split_dragged(_offset: int) -> void:
	if _restoring_layout:
		return
	_persist_main_drag.call_deferred()


func _persist_main_drag() -> void:
	_persist_metadata("main_ratio", _current_main_ratio())
	update_responsive_layout()


func _on_inner_split_dragged(_offset: int) -> void:
	if _restoring_layout or _narrow_layout:
		return
	_persist_inner_drag.call_deferred()


func _persist_inner_drag() -> void:
	if _narrow_layout:
		return
	_persist_metadata("inner_ratio", _current_inner_ratio())


func _on_editing_tab_changed(tab: int) -> void:
	if tab < 0:
		return
	_preferred_narrow_tab = tab
	if not _restoring_layout:
		_persist_metadata("narrow_tab", tab)


func _on_section_state_changed(states: Dictionary) -> void:
	if not _restoring_layout:
		_persist_metadata("sections", states)


func _current_main_ratio() -> float:
	return _split_ratio(_main_split)


func _current_inner_ratio() -> float:
	return _split_ratio(_editing_split)


func _split_ratio(split: HSplitContainer) -> float:
	if split.get_child_count() < 2:
		return 0.5
	var first: Control = split.get_child(0) as Control
	var second: Control = split.get_child(1) as Control
	var total: float = first.size.x + second.size.x
	return first.size.x / total if total > 0.0 else 0.5


func _bounded_split_ratio(split: HSplitContainer, ratio: float) -> float:
	if split.get_child_count() < 2 or split.size.x <= 0.0:
		return clampf(ratio, 0.05, 0.95)
	var first: Control = split.get_child(0) as Control
	var second: Control = split.get_child(1) as Control
	var available: float = first.size.x + second.size.x
	if available <= 0.0:
		return clampf(ratio, 0.05, 0.95)
	var first_minimum: float = first.get_combined_minimum_size().x
	var second_minimum: float = second.get_combined_minimum_size().x
	var minimum_ratio: float = minf(0.95, first_minimum / available)
	var maximum_ratio: float = maxf(0.05, 1.0 - second_minimum / available)
	return clampf(ratio, minimum_ratio, maximum_ratio)


func _set_split_ratio(split: HSplitContainer, ratio: float) -> void:
	if split.get_child_count() < 2 or split.size.x <= 0.0:
		return
	var first: Control = split.get_child(0) as Control
	var second: Control = split.get_child(1) as Control
	var available: float = first.size.x + second.size.x
	if available <= 0.0:
		return
	var bounded: float = _bounded_split_ratio(split, ratio)
	var target: float = available * bounded
	split.split_offset += roundi(target - first.size.x)


func _apply_inner_ratio(ratio: float) -> void:
	if not _narrow_layout:
		_set_split_ratio(_editing_split, ratio)


## Wired-by: tests/gst_editor_ui_layout_smoke.gd.
func set_narrow_tab(tab: int) -> void:
	_preferred_narrow_tab = clampi(tab, 0, 1)
	if _editing_tabs.get_tab_count() > _preferred_narrow_tab:
		_editing_tabs.current_tab = _preferred_narrow_tab
	_persist_metadata("narrow_tab", _preferred_narrow_tab)


## Wired-by: tests/gst_editor_ui_layout_smoke.gd.
func get_narrow_tab() -> int:
	return _preferred_narrow_tab


func restore_layout_metadata() -> void:
	if _editor_settings == null:
		return
	_restoring_layout = true
	var sections: Variant = _metadata_value("sections", {})
	_inspector_column.set_section_states(sections as Dictionary if sections is Dictionary else {})
	_preferred_narrow_tab = clampi(int(_metadata_value("narrow_tab", 0)), 0, 1)
	_apply_restored_layout.call_deferred(_metadata_float("main_ratio", DEFAULT_MAIN_RATIO), _metadata_float("inner_ratio", DEFAULT_INNER_RATIO))


func _apply_restored_layout(main_ratio: float, inner_ratio: float) -> void:
	_set_split_ratio(_main_split, main_ratio)
	update_responsive_layout()
	if _narrow_layout and _editing_tabs.get_tab_count() > _preferred_narrow_tab:
		_editing_tabs.current_tab = _preferred_narrow_tab
	_apply_restored_inner.call_deferred(inner_ratio)


func _apply_restored_inner(inner_ratio: float) -> void:
	_apply_inner_ratio(inner_ratio)
	_restoring_layout = false


## Wired-by: tests/gst_editor_ui_layout_smoke.gd.
func get_layout_metadata_snapshot() -> Dictionary:
	return {
		"main_ratio": _metadata_value("main_ratio", DEFAULT_MAIN_RATIO),
		"inner_ratio": _metadata_value("inner_ratio", DEFAULT_INNER_RATIO),
		"narrow_tab": _metadata_value("narrow_tab", 0),
		"sections": _metadata_value("sections", {}),
	}


## Wired-by: tests/gst_editor_ui_layout_smoke.gd.
func restore_layout_metadata_snapshot(snapshot: Dictionary) -> void:
	for key: Variant in snapshot:
		_persist_metadata(String(key), snapshot[key])
	restore_layout_metadata()


func _metadata_value(key: String, fallback: Variant) -> Variant:
	if _editor_settings == null:
		return fallback
	return _editor_settings.get_project_metadata(LAYOUT_METADATA_SECTION, key, fallback)


func _metadata_float(key: String, fallback: float) -> float:
	var value: Variant = _metadata_value(key, fallback)
	return float(value) if value is float or value is int else fallback


func _persist_metadata(key: String, value: Variant) -> void:
	if _editor_settings != null:
		_editor_settings.set_project_metadata(LAYOUT_METADATA_SECTION, key, value)


## Wired-by: tests/gst_editor_ui_layout_smoke.gd.
func get_layout_measurements() -> Dictionary:
	var host: Control = get_parent() as Control
	var main_children_width: float = _editing_area.size.x + _preview_area.size.x
	var inner_children_width: float = _layer_pane.size.x + _settings_pane.size.x
	var editing_minimum: float = maxf(_layer_pane.get_combined_minimum_size().x, _settings_pane.get_combined_minimum_size().x) if _narrow_layout else _tab_breakpoint
	var preview_minimum_width: float = _preview_area.get_combined_minimum_size().x
	var main_min_ratio: float = minf(0.95, editing_minimum / main_children_width) if main_children_width > 0.0 else 0.0
	var main_max_ratio: float = maxf(0.05, 1.0 - preview_minimum_width / main_children_width) if main_children_width > 0.0 else 1.0
	var layer_minimum: float = _layer_pane.get_combined_minimum_size().x
	var settings_minimum: float = _settings_pane.get_combined_minimum_size().x
	var inner_min_ratio: float = minf(0.95, layer_minimum / inner_children_width) if inner_children_width > 0.0 else 0.0
	var inner_max_ratio: float = maxf(0.05, 1.0 - settings_minimum / inner_children_width) if inner_children_width > 0.0 else 1.0
	return {
		"editor_scale": EditorInterface.get_editor_scale(),
		"host_rect": host.get_global_rect(),
		"root_rect": get_global_rect(),
		"editing_rect": _editing_area.get_global_rect(),
		"preview_area_rect": _preview_area.get_global_rect(),
		"preview_rect": _preview.get_global_rect(),
		"output_rect": _output_block.get_global_rect(),
		"editing_minimum": Vector2(editing_minimum, 0.0),
		"preview_minimum": PREVIEW_IMAGE_MINIMUM,
		"main_divider_width": float(_main_split.get_theme_constant("separation")),
		"main_minimums_permit_default": main_children_width * DEFAULT_MAIN_RATIO >= editing_minimum and main_children_width * (1.0 - DEFAULT_MAIN_RATIO) >= preview_minimum_width,
		"main_ratio": _current_main_ratio(),
		"inner_ratio": _current_inner_ratio(),
		"main_ratio_min": main_min_ratio,
		"main_ratio_max": main_max_ratio,
		"inner_ratio_min": inner_min_ratio,
		"inner_ratio_max": inner_max_ratio,
		"tab_breakpoint": _tab_breakpoint,
		"narrow": _narrow_layout,
	}


## Rebinds the stack list, output block, inspector column, and coord-space
## dropdown to `stack`/`undo`, writes them onto _active_document, and resyncs
## the material. replace_stack's do/undo methods reach this through
## _install_document_state_for, so undo reinstalls the exact previous
## GSTStack/GSTUndo instances and every action already recorded through that
## GSTUndo keeps landing on the instances it closed over. Does not touch
## preview_sync/material/preview_layer_id: _activate_document installs those
## once per document.
func _install_stack(stack: GSTStack, undo: GSTUndo) -> void:
	_picker.set_refusal("")
	_control_refusals.clear()
	# _active_document is already the incoming document here
	# (_activate_document sets it before calling this), so the label rebuilds
	# from that document's operation_messages.
	_refresh_operation_message_label()
	_stack_list.clear_refusals()
	_inspector_column.clear_refusals()
	_output_block.clear_refusals()
	_stack = stack
	_undo = undo
	if _active_document != null:
		_active_document.stack = stack
		_active_document.undo = undo
	_stack_list.setup(_stack, _library, _undo)
	_output_block.setup(_stack, _library, _undo)
	_inspector_column.setup(_stack, _library, _undo)
	_inspector_column.edit(_stack_list.get_selected_layer_id())
	_syncing_coord_space = true
	_coord_space_option.select(int(_stack.coord_space))
	_syncing_coord_space = false
	_resync_material()


func _notify_replace() -> void:
	stack_changed.emit()


## Sets the preview material mirrors (and _active_document's matching
## fields) before _install_stack, whose _resync_material() call must already
## see them. One atomic do/undo primitive: registering the two steps as
## separate UndoRedo methods would replay in the wrong order on undo (undo
## methods replay in reverse registration order). Kept separate from
## _install_stack so a fixture can swap only stack/undo in place.
func _install_document_state(stack: GSTStack, undo: GSTUndo, preview_sync: GSTMaterialSync, material: ShaderMaterial, preview_layer_id: StringName) -> void:
	_preview_sync = preview_sync
	_material = material
	_preview_layer_id = preview_layer_id
	if _active_document != null:
		_active_document.preview_sync = preview_sync
		_active_document.material = material
		_active_document.preview_layer_id = preview_layer_id
	_install_stack(stack, undo)


## Document-bound counterpart of _install_document_state, used only by
## replace_stack's action: always writes doc's fields, touches the shared UI
## only when doc is active. Replaying the action for an inactive doc must not
## overwrite whichever document is active.
func _install_document_state_for(doc: GSTDocument, stack: GSTStack, undo: GSTUndo, preview_sync: GSTMaterialSync, material: ShaderMaterial, preview_layer_id: StringName) -> void:
	doc.stack = stack
	doc.undo = undo
	doc.preview_sync = preview_sync
	doc.material = material
	doc.preview_layer_id = preview_layer_id
	if doc != _active_document:
		return
	_preview_sync = preview_sync
	_material = material
	_preview_layer_id = preview_layer_id
	_install_stack(stack, undo)


## Document-bound path setter, shared by replace_stack's action and
## _save_stack_to_path's successful-write branch.
func _raw_set_current_path_for(doc: GSTDocument, path: String) -> void:
	doc.current_path = path
	if doc == _active_document:
		_current_path = path


## Document-bound counterpart of _set_recipe_open, used only by
## replace_stack's action.
func _set_recipe_open_for(doc: GSTDocument, value: bool) -> void:
	doc.recipe_open = value
	if doc != _active_document:
		return
	_recipe_open = value
	_randomize_button.disabled = not value or is_picker_open()


## Document-bound counterpart of _notify_replace, used only by replace_stack's
## action: an inactive document's replay must not emit stack_changed.
func _notify_replace_for(doc: GSTDocument) -> void:
	if doc == _active_document:
		_notify_replace()


## Builds a GSTDocument for new_stack, appends it to _documents, and returns
## it without activating it. GSTUndo's on_changed/on_property_changed
## callbacks are bound to the document so a later replay resolves its owner
## whether or not it is active. A recipe/import origin marks the document
## dirty on setup (GSTDocument.setup's starts_dirty): unsaved recipe/import
## content has no saved baseline.
func _create_document(new_stack: GSTStack, new_path: String, new_recipe_open: bool, new_recipe_name: String = "", new_reopened_import: bool = false) -> GSTDocument:
	var doc: GSTDocument = GSTDocument.new()
	doc.current_path = new_path
	doc.recipe_open = new_recipe_open
	doc.recipe_name = new_recipe_name
	doc.reopened_import = new_reopened_import
	doc.setup(new_stack, _library, _on_document_stack_changed.bind(doc), _on_document_property_changed.bind(doc), new_recipe_open or new_reopened_import)
	_documents.append(doc)
	return doc


## GSTUndo's on_changed callback, bound to the owning document. Only the
## active document's replay may touch the shared UI: an inactive document's
## undo/redo must not rebuild _stack_list/_inspector_column/_output_block
## against a stack they are not bound to.
func _on_document_stack_changed(doc: GSTDocument) -> void:
	if doc != _active_document:
		return
	_on_stack_changed()


## Same isolation as _on_document_stack_changed, for the on_property_changed
## callback.
func _on_document_property_changed(doc: GSTDocument) -> void:
	if doc != _active_document:
		return
	_on_property_changed()


## Points the shared UI at doc: mirrors its stack/undo/current_path/
## recipe_open/preview state into this panel's fields, then _install_stack
## rebinds the columns. Registers no undo action: switching documents is
## navigation; an inactive document's UndoRedo is untouched. Does not touch
## the start screen: _ready()'s bootstrap activation must not dismiss it;
## activate_document/open_document dismiss it themselves.
func _activate_document(doc: GSTDocument) -> void:
	# Captures the previous document's scroll state before the stack list is
	# rebound. selected_layer_id is kept live by _on_layer_selected; scroll
	# position has no signal, so it is captured here.
	if _active_document != null and _active_document != doc:
		_active_document.list_scroll_anchor_id = _stack_list.get_scroll_anchor_id()
		_active_document.list_scroll_offset = _stack_list.get_scroll_offset()
	_active_document = doc
	_undo_redo = doc.undo_redo
	_current_path = doc.current_path
	_set_recipe_open(doc.recipe_open)
	_install_document_state(doc.stack, doc.undo, doc.preview_sync, doc.material, doc.preview_layer_id)
	_restore_document_selection(doc)
	_restore_document_preview_controls(doc)
	_refresh_tabs()


## Restores doc's layer selection and list scroll position after
## _install_stack rebuilt _stack_list. Clears any selection the refresh
## carried over by coincidence (a stale selected_id matching an id in
## doc.stack) before applying doc's remembered selection.
func _restore_document_selection(doc: GSTDocument) -> void:
	_stack_list.clear_selection()
	if doc.selected_layer_id != &"" and GSTStackOps.find_layer(_stack, doc.selected_layer_id) != null:
		_stack_list.select_layer(doc.selected_layer_id)
	else:
		doc.selected_layer_id = &""
		_inspector_column.edit(&"")
	_update_layer_menu()
	_stack_list.restore_scroll_state(doc.list_scroll_anchor_id, doc.list_scroll_offset)


## Restores doc's preview preset/image (preview_layer_id is restored by
## _install_document_state). "" preview_preset/preview_image_path means doc
## never changed them, so both fall back to the _ready()-time defaults.
func _restore_document_preview_controls(doc: GSTDocument) -> void:
	var preset_name: String = doc.preview_preset if not doc.preview_preset.is_empty() else GSTPreviewPresets.SPRITE
	var preset_index: int = GSTPreviewPresets.PRESET_NAMES.find(preset_name)
	if preset_index == -1:
		preset_index = 0
		preset_name = GSTPreviewPresets.PRESET_NAMES[0]
	_syncing_preview_controls = true
	_preset_option.select(preset_index)
	_syncing_preview_controls = false
	_preview.set_preset(preset_name)
	if doc.preview_image_path.is_empty():
		_preview.reset_image()
	else:
		var texture: Texture2D = load(doc.preview_image_path) as Texture2D
		if texture != null:
			_preview.set_image(texture)
		else:
			_preview.reset_image()
	_resync_material()


## Rebuilds %ShaderTabs from _documents wholesale. Called after every
## activation (_activate_document), every active-document edit
## (_on_stack_changed/_on_property_changed), and every successful save
## (_save_stack_to_path), so titles and dirty stars stay current.
## _tab_session_ids is rebuilt 1:1 in the same pass. _new_tab_button is a
## fixed sibling in ShaderTabRow (gst_main_panel.tscn), never touched here.
## _syncing_tabs suppresses _on_tab_bar_tab_changed during the current_tab
## write.
func _refresh_tabs() -> void:
	_syncing_tabs = true
	_shader_tabs.clear_tabs()
	_tab_session_ids.clear()
	var untitled_index: int = 0
	var active_index: int = -1
	for doc: GSTDocument in _documents:
		if doc.current_path.is_empty() and doc.recipe_name.is_empty():
			untitled_index += 1
		_shader_tabs.add_tab(_tab_title(doc, untitled_index))
		var index: int = _shader_tabs.get_tab_count() - 1
		_shader_tabs.set_tab_tooltip(index, _tab_tooltip(doc))
		_tab_session_ids.append(doc.session_id)
		if doc == _active_document:
			active_index = index
	if active_index != -1:
		_shader_tabs.current_tab = active_index
	_syncing_tabs = false
	# _await_ensure_active_tab_visible re-checks active_index after its await:
	# another _refresh_tabs() call can rebuild the tab list before it runs.
	_await_ensure_active_tab_visible(active_index)
	_apply_tab_bar_width()


## %ShaderTabs's laid-out size is not final until the next frame boundary: a
## same-frame ensure_tab_visible read a stale get_size().width and landed
## short (measured at 150% editor scale). Awaits process_frame first.
func _await_ensure_active_tab_visible(index: int) -> void:
	await get_tree().process_frame
	if is_instance_valid(_shader_tabs) and index >= 0 and index < _shader_tabs.get_tab_count():
		_shader_tabs.ensure_tab_visible(index)


## tab_changed fires only when current_tab moves (TabBar::set_current_tab), so
## a reclick on the active tab never reaches here. _syncing_tabs rejects
## _refresh_tabs()'s programmatic current_tab write.
## Wired-by: %ShaderTabs.tab_changed (_ready()).
func _on_tab_bar_tab_changed(tab: int) -> void:
	if _syncing_tabs or tab < 0 or tab >= _tab_session_ids.size():
		return
	var doc: GSTDocument = _find_document_by_session_id(_tab_session_ids[tab])
	if doc == null:
		return
	activate_document(doc)


## Resolves through _tab_session_ids/_find_document_by_session_id rather than
## indexing _documents, so a stale signal delivered after a rebuild resolves
## to null instead of closing whatever document now occupies that index.
## Wired-by: %ShaderTabs.tab_close_pressed (_ready()).
func _on_tab_bar_close_pressed(tab: int) -> void:
	if tab < 0 or tab >= _tab_session_ids.size():
		return
	var doc: GSTDocument = _find_document_by_session_id(_tab_session_ids[tab])
	if doc == null:
		return
	close_document(doc)


## Filename without extension once saved, recipe name before that first save,
## or "Untitled N" for a document with neither. untitled_index is the
## document's 1-based position among open untitled documents, computed by the
## caller iterating _documents in creation order. A trailing `*` marks
## GSTDocument.is_dirty().
func _tab_title(doc: GSTDocument, untitled_index: int) -> String:
	var base: String = ""
	if not doc.current_path.is_empty():
		base = doc.current_path.get_file().get_basename()
	elif not doc.recipe_name.is_empty():
		base = doc.recipe_name.replace("_", " ").capitalize()
	else:
		base = "Untitled %d" % untitled_index
	return base + ("*" if doc.is_dirty() else "")


## Full path, or the unsaved origin.
func _tab_tooltip(doc: GSTDocument) -> String:
	if not doc.current_path.is_empty():
		return doc.current_path
	if not doc.recipe_name.is_empty():
		return "Opened from recipe '%s' (not yet saved)." % doc.recipe_name
	if doc.reopened_import:
		return "Reopened from an exported .gdshader header (not yet saved)."
	return "New shader (not yet saved)."


## Public navigation entry point onto an already-open document. Finishes any
## pending native gesture/color popup on the active document first: a commit
## must not land after _install_document_state/_inspector_column.setup have
## rebound _undo and the inspector column to doc's adapter.
## Wired-by: _on_tab_bar_tab_changed, open_path (canonical-path reuse), and
## editor smoke seams.
func activate_document(doc: GSTDocument) -> void:
	if doc == null or doc == _active_document:
		return
	await _finish_pending_edits()
	# Switching cancels an open picker. restore_focus=false: no deferred
	# grab_focus() may target rows _install_stack is about to free.
	_close_picker(false)
	_dismiss_start_screen()
	_activate_document(doc)


## Wired-by: none (editor smoke seam)
func get_active_document() -> GSTDocument:
	return _active_document


## Wired-by: none (editor smoke seam)
func get_documents() -> Array[GSTDocument]:
	return _documents.duplicate()


## Wired-by: none (editor smoke seam)
func get_tab_bar() -> TabBar:
	return _shader_tabs


## doc's tab index in %ShaderTabs, or -1 if doc is not open.
## Wired-by: none (editor smoke seam)
func get_tab_index(doc: GSTDocument) -> int:
	if doc == null:
		return -1
	return _tab_session_ids.find(doc.session_id)


## doc's tab rect in global coordinates; Rect2() if doc is not open.
## Wired-by: none (editor smoke seam)
func get_tab_rect(doc: GSTDocument) -> Rect2:
	var index: int = get_tab_index(doc)
	if index == -1:
		return Rect2()
	var local: Rect2 = _shader_tabs.get_tab_rect(index)
	return Rect2(_shader_tabs.get_global_rect().position + local.position, local.size)


## doc's tab close-icon hit rect in global coordinates; Rect2() if doc is not
## open. Derivation: _tab_close_rect_local.
## Wired-by: none (editor smoke seam)
func get_tab_close_rect(doc: GSTDocument) -> Rect2:
	var index: int = get_tab_index(doc)
	if index == -1:
		return Rect2()
	var local: Rect2 = _tab_close_rect_local(index)
	return Rect2(_shader_tabs.get_global_rect().position + local.position, local.size)


## Replicates TabBar::_draw_tab's private cb_rect (Godot 4.4, tab_bar.cpp)
## from the same theme items. No shader tab has an icon or right_button, so
## cb_rect's right edge is the tab's right edge minus the tab style's right
## margin plus the close button highlight style's right margin; its size is
## that highlight style's minimum size plus the close icon size. Reads only
## get_tab_rect's final size plus theme items, never text width.
func _tab_close_rect_local(index: int) -> Rect2:
	var tab_rect: Rect2 = _shader_tabs.get_tab_rect(index)
	var tab_style: StyleBox = _shader_tabs.get_theme_stylebox("tab_selected" if index == _shader_tabs.current_tab else "tab_unselected")
	var button_style: StyleBox = _shader_tabs.get_theme_stylebox("button_highlight")
	var close_icon: Texture2D = _shader_tabs.get_theme_icon("close")
	var size: Vector2 = button_style.get_minimum_size() + close_icon.get_size()
	var right: float = tab_rect.position.x + tab_rect.size.x - tab_style.get_margin(SIDE_RIGHT) + button_style.get_margin(SIDE_RIGHT)
	var top: float = tab_style.get_margin(SIDE_TOP) + ((tab_rect.size.y - tab_style.get_minimum_size().y) - size.y) / 2.0
	return Rect2(Vector2(right - size.x, top), size)


## Wired-by: none (editor smoke seam)
func get_new_tab_button() -> Button:
	return _new_tab_button


## The full tab row (%ShaderTabs plus %NewTabButton).
## Wired-by: none (editor smoke seam)
func get_tab_row() -> HBoxContainer:
	return _shader_tab_row


## simplify_path() (dedupes "//", resolves "."/".."), then
## ProjectSettings.globalize_path() so a res:// or user:// path and its
## absolute equivalent compare equal, then case-folds only when
## case_insensitive. Static and parameterized so both filesystem
## case-sensitivity modes can be exercised on any platform.
static func _canonical_path_for(path: String, case_insensitive: bool) -> String:
	var globalized: String = ProjectSettings.globalize_path(path.simplify_path())
	return globalized.to_lower() if case_insensitive else globalized


## Canonical identity for _find_document_by_path: case-insensitive only on
## Windows and macOS (OS.get_name()). Comparison only; doc.current_path keeps
## the caller's spelling.
func _canonical_path(path: String) -> String:
	return _canonical_path_for(path, OS.get_name() in ["Windows", "macOS"])


## An open document whose current_path canonically matches path, or null.
## Empty paths never match: every never-saved document shares "".
func _find_document_by_path(path: String) -> GSTDocument:
	if path.is_empty():
		return null
	var canonical: String = _canonical_path(path)
	for doc: GSTDocument in _documents:
		if not doc.current_path.is_empty() and _canonical_path(doc.current_path) == canonical:
			return doc
	return null


## An open, never-saved, never-edited document, or null. Recipe/import
## documents start dirty (GSTDocument.setup's starts_dirty), so is_dirty()
## alone excludes them. New reuses this instead of adding a blank tab.
func _find_reusable_pristine_document() -> GSTDocument:
	for doc: GSTDocument in _documents:
		if doc.current_path.is_empty() and not doc.is_dirty():
			return doc
	return null


## The open document with this session id, or null once it has closed
## through _close_document_now.
func _find_document_by_session_id(session_id: int) -> GSTDocument:
	for doc: GSTDocument in _documents:
		if doc.session_id == session_id:
			return doc
	return null


## Resolves a delayed dialog response against the document captured when its
## request was issued (see the *_pending_* Dictionaries). Empty `pending`
## (no request captured) falls back to _active_document. A doc_id that no
## longer resolves returns null; the caller must reject the response without
## writing to or messaging any other document.
func _resolve_pending_document(pending: Dictionary) -> GSTDocument:
	if pending.is_empty():
		return _active_document
	return _find_document_by_session_id(int(pending.get("doc_id", -1)))


## Captures _active_document under a fresh request_id, for a dialog-opening
## handler to store into its *_pending_* field before popping its dialog.
## `{}` when there is no active document.
func _capture_active_document_request() -> Dictionary:
	return _capture_document_request(_active_document)


## Same capture shape as _capture_active_document_request, for `doc`: a close
## request binds to the document whose close icon was pressed, which may be
## inactive.
func _capture_document_request(doc: GSTDocument) -> Dictionary:
	if doc == null:
		return {}
	_next_file_request_id += 1
	return {"request_id": _next_file_request_id, "doc_id": doc.session_id}


## Creates a GSTDocument for new_stack and activates it. Registers no undo
## action: switching documents is navigation. new_path "" for a never-saved
## or recipe/reopened document. new_recipe_name/new_reopened_import retain an
## unsaved origin. A plain New call (both defaults) reuses a pristine
## document via _find_reusable_pristine_document. Public for editor smoke.
## Wired-by: _on_new_pressed, open_path, open_recipe, reopen_shader_path,
## and _on_picker_choice's "recipe" case.
func open_document(new_stack: GSTStack, new_path: String, new_recipe_open: bool, new_recipe_name: String = "", new_reopened_import: bool = false) -> GSTDocument:
	if is_picker_open() and not _applying_choice:
		return null
	await _finish_pending_edits()
	_dismiss_start_screen()
	if new_path.is_empty() and not new_recipe_open and not new_reopened_import:
		var reusable: GSTDocument = _find_reusable_pristine_document()
		if reusable != null:
			_activate_document(reusable)
			return reusable
	var doc: GSTDocument = _create_document(new_stack, new_path, new_recipe_open, new_recipe_name, new_reopened_import)
	_activate_document(doc)
	return doc


## Public close entry point. A clean document closes immediately; a dirty one
## is offered Save/Discard/Cancel through _close_dialog. Finishes any active
## native gesture first, only when doc is active (an inactive document holds
## no live gesture: every edit on it was committed before ownership moved
## away), so the pending edit's fingerprint has landed before is_dirty().
## Registers no undo action.
## Wired-by: %ShaderTabs.tab_close_pressed, through _on_tab_bar_close_pressed.
func close_document(doc: GSTDocument) -> void:
	if doc == null or not _documents.has(doc):
		return
	if doc == _active_document:
		await _finish_pending_edits()
	# A stale close continuation (doc closed some other way while the above
	# await suspended) must not fall through to the dialog below.
	if not _documents.has(doc):
		return
	if not doc.is_dirty():
		_close_document_now(doc)
		return
	_pending_close = _capture_document_request(doc)
	_close_dialog.dialog_text = "%s has unsaved changes. Save before closing?" % _describe_document(doc)
	_close_dialog.popup_centered()


## Short display name for _close_dialog's text and get_unsaved_status_text's
## lines; no dirty star. Untitled documents use _tab_title's "Untitled %d"
## numbering (_untitled_index) so two dirty untitled documents stay
## distinguishable.
func _describe_document(doc: GSTDocument) -> String:
	if not doc.current_path.is_empty():
		return doc.current_path.get_file().get_basename()
	if not doc.recipe_name.is_empty():
		return doc.recipe_name.replace("_", " ").capitalize()
	return "Untitled %d" % _untitled_index(doc)


## doc's 1-based position among _documents' untitled bucket (no current_path,
## no recipe_name), in the same creation-order iteration _refresh_tabs uses
## for _tab_title's untitled_index.
func _untitled_index(doc: GSTDocument) -> int:
	var index: int = 0
	for candidate: GSTDocument in _documents:
		if candidate.current_path.is_empty() and candidate.recipe_name.is_empty():
			index += 1
		if candidate == doc:
			return index
	return index


## _close_dialog.confirmed ("Save"). Resolves against the document captured
## when the prompt opened; a stale/closed target does nothing. An untitled
## document routes through the Save As dialog with close_after=true in its
## pending capture, so _on_save_as_file_selected finishes the close on
## success. A named document saves to current_path and closes only if the
## write succeeds; a failed save leaves it dirty and open with the failure
## message set by _save_stack_to_path.
## Wired-by: _close_dialog.confirmed (_ready()).
func _on_close_save_requested() -> void:
	var doc: GSTDocument = _resolve_pending_document(_pending_close)
	_pending_close = {}
	if doc == null:
		return
	if doc.current_path.is_empty():
		var pending: Dictionary = _capture_document_request(doc)
		pending["close_after"] = true
		_pending_save_as = pending
		_save_as_dialog.popup_centered_ratio()
		return
	var result: Dictionary = await _save_stack_to_path(doc, doc.current_path)
	if bool(result.get("ok", false)) and _documents.has(doc):
		_close_document_now(doc)


## _close_dialog.custom_action ("Discard"; other action strings are ignored).
## Wired-by: _close_dialog.custom_action (_ready()).
func _on_close_custom_action(action: String) -> void:
	if action != "discard":
		return
	_close_dialog.hide()
	var doc: GSTDocument = _resolve_pending_document(_pending_close)
	_pending_close = {}
	if doc == null:
		return
	_close_document_now(doc)


## Removes doc from _documents and tears down its UndoRedo/GSTUndo; the only
## place a document detaches from this panel. Every *_pending_* Dictionary
## resolves through _find_document_by_session_id, so in-flight callbacks
## captured against doc resolve to null with no invalidation pass. Closing
## the active document selects the tab at the same index, clamped; closing
## the last document recreates _ready()'s bootstrap condition (one pristine
## document behind the start screen) so an active document always exists.
## Registers no undo action.
func _close_document_now(doc: GSTDocument) -> void:
	if not _documents.has(doc):
		return
	var index: int = _documents.find(doc)
	var was_active: bool = doc == _active_document
	if was_active:
		# A picker open against the closing document must not survive.
		_close_picker(false)
	_documents.remove_at(index)
	# Close and successful save (_save_stack_to_path) are the only two places
	# a recovery record is removed. No-op when doc never held one.
	_forget_recovery_record(doc)
	doc.teardown()
	if not was_active:
		_refresh_tabs()
		return
	if _documents.is_empty():
		_activate_document(_create_document(GSTStack.new(), "", false))
		_start_screen.show()
		_editing_content.hide()
		_set_picker_modality(false)
		return
	_activate_document(_documents[clampi(index, 0, _documents.size() - 1)])


## Finishes any active native gesture and closes any open native color popup
## before a rebind, Save/Save As, Export, or keyboard undo/redo. Resolves
## synchronously when nothing is pending: GSTInspectorColumn only awaits a
## frame while an open color popup's typed text is being committed.
func _finish_pending_edits() -> void:
	await _inspector_column.finish_pending_edits()


## Shutdown recovery storage, always under the running project's settings
## directory, never a user stack/export path.
## Wired-by: none (editor smoke seam).
func get_recovery_dir() -> String:
	return GSTDocumentRecovery.recovery_dir(EditorInterface.get_editor_paths().get_project_settings_dir())


## plugin.gd's _get_unsaved_status(""): lists every dirty shader document by
## _describe_document's short name. A nonempty for_scene returns "": every
## GSTDocument is session-scoped, never scene-owned, so scene-close
## confirmation must not see shader content. No pending-edit finish runs
## here: property_changed already applies a live gesture's value onto the
## target as it happens, so is_dirty() reflects it, and this virtual is
## synchronous.
## Wired-by: plugin.gd's _get_unsaved_status.
func get_unsaved_status_text(for_scene: String) -> String:
	if not for_scene.is_empty():
		return ""
	var names: Array[String] = []
	for doc: GSTDocument in _documents:
		if doc.needs_shutdown_attention():
			names.append(_describe_document(doc))
	return "\n".join(names)


## plugin.gd's _save_external_data(): the confirmed "Save and Quit" callback.
## Godot declares this virtual void and unawaited, so it cannot suspend
## shutdown; _finish_pending_edits() resolves synchronously here. Saves every
## dirty named document to its current_path and recovers every untitled or
## failed-save document into a recovery record. A successful named save
## drops the document's recovery record; a failed save keeps the document
## dirty and recovers it under its original path/origin, reusing its record
## id on a later shutdown.
## Wired-by: plugin.gd's _save_external_data.
func save_external_data() -> void:
	_finish_pending_edits()
	var dir: String = get_recovery_dir()
	for doc: GSTDocument in _documents:
		if not doc.is_dirty():
			continue
		if doc.current_path.is_empty():
			_recover_document(doc, dir, "")
			continue
		var save_result: Dictionary = GSTStackIO.save(doc.stack, doc.current_path)
		if bool(save_result.get("ok", false)):
			doc.mark_baseline()
			_forget_recovery_record(doc)
			continue
		_recover_document(doc, dir, String(save_result.get("reason", "")))


## Writes/updates doc's recovery record. `save_failure_reason` is "" for an
## untitled document or the GSTStackIO.save failure reason for a named one.
## On a recovery-write failure, reports both attempted paths and that
## _save_external_data() cannot veto shutdown, through one push_error. A
## non-empty quarantined_path in write_record's result means an unreadable
## index.json was renamed aside before writing; the stack files it referenced
## are now unindexed, reported through push_error here and again by
## GSTDocumentRecovery.load_all's directory scan on every later startup.
func _recover_document(doc: GSTDocument, dir: String, save_failure_reason: String) -> void:
	var write_result: Dictionary = GSTDocumentRecovery.write_record(dir, doc.stack, doc.current_path, doc.recipe_open, doc.recipe_name, doc.reopened_import, not save_failure_reason.is_empty(), doc.recovery_record_id)
	if bool(write_result.get("ok", false)):
		doc.recovery_record_id = String(write_result.get("record_id", ""))
		doc.recovery_fingerprint = GSTDocument.compute_fingerprint(doc.stack)
		var quarantined_path: String = String(write_result.get("quarantined_path", ""))
		if not quarantined_path.is_empty():
			push_error("GoShade Turbo: recovery index at %s was unreadable and has been quarantined to %s before writing this document's own recovery record; any recovery records it referenced are no longer indexed and must be recovered manually." % [dir.path_join(GSTDocumentRecovery.METADATA_FILE), quarantined_path])
		return
	var stack_path: String = String(write_result.get("stack_path", ""))
	if save_failure_reason.is_empty():
		push_error("GoShade Turbo: could not recover an untitled shader document -- writing its recovery stack to %s failed: %s. _save_external_data() is void and cannot veto editor shutdown." % [stack_path, write_result.get("reason", "")])
	else:
		push_error("GoShade Turbo: could not save %s (%s) or recover it to %s: %s. _save_external_data() is void and cannot veto editor shutdown." % [doc.current_path, save_failure_reason, stack_path, write_result.get("reason", "")])


## Removes doc's recovery record on disk, if any, and clears its tracked id;
## called after a successful save/Save As and after Discard. No-op for a
## document without a record. remove_record's result is checked before
## clearing recovery_record_id/recovery_fingerprint: a failed cleanup leaves
## doc's recovery identity intact and reports through push_error, so an
## unresolved on-disk record keeps its in-memory pointer.
func _forget_recovery_record(doc: GSTDocument) -> void:
	if doc.recovery_record_id.is_empty():
		return
	var remove_result: Dictionary = GSTDocumentRecovery.remove_record(get_recovery_dir(), doc.recovery_record_id)
	if not bool(remove_result.get("ok", false)):
		push_error("GoShade Turbo: could not remove recovery record %s: %s" % [doc.recovery_record_id, remove_result.get("reason", "")])
		return
	doc.recovery_record_id = ""
	doc.recovery_fingerprint = ""


## Reopens every valid recovery record left by a previous save_external_data()
## call as its own dirty document, before the start screen is shown. A
## failed/unreadable record is kept on disk and reported, never deleted; only
## Discard or a successful save removes a record (_forget_recovery_record).
## Each recovered document starts dirty: its content never reached its
## original_path.
## Wired-by: _ready(); an editor smoke seam.
func load_recovery_records() -> void:
	var dir: String = get_recovery_dir()
	var result: Dictionary = GSTDocumentRecovery.load_all(dir, _library)
	for failure: Variant in (result.get("failures", []) as Array):
		var failure_entry: Dictionary = failure as Dictionary
		push_error("GoShade Turbo: recovery record unreadable at %s: %s" % [failure_entry.get("path", ""), failure_entry.get("reason", "")])
	var recovered: Array[GSTDocument] = []
	for raw_entry: Variant in (result.get("records", []) as Array):
		var entry: Dictionary = raw_entry as Dictionary
		var doc: GSTDocument = GSTDocument.new()
		doc.current_path = String(entry.get("original_path", ""))
		doc.recipe_open = bool(entry.get("recipe_open", false))
		doc.recipe_name = String(entry.get("recipe_name", ""))
		doc.reopened_import = bool(entry.get("reopened_import", false))
		doc.recovery_record_id = String(entry.get("id", ""))
		doc.setup(entry["stack"], _library, _on_document_stack_changed.bind(doc), _on_document_property_changed.bind(doc), true)
		doc.recovery_fingerprint = GSTDocument.compute_fingerprint(doc.stack)
		_documents.append(doc)
		recovered.append(doc)
	if recovered.is_empty():
		return
	_dismiss_start_screen()
	_activate_document(recovered[recovered.size() - 1])


## Wired-by: none (editor smoke seam)
func get_stack() -> GSTStack:
	return _stack


## Installs new_stack, new_path, and new_recipe_open as an undoable "Replace
## stack" action on the active document's UndoRedo, in place: the GSTDocument
## instance is retained; only its .stack/.undo swap. Not a production path
## (New/Open/Reopen/Recipes call open_document); a fixture-only primitive
## for an in-place undoable stack swap without a second GSTDocument.
##
## Binds the do/undo methods and new_undo's callbacks to owner_doc, the
## document active at creation: replaying this action while a different
## document is active must rewrite only owner_doc's fields and touch the
## shared UI only when owner_doc is still active.
func replace_stack(new_stack: GSTStack, new_path: String, new_recipe_open: bool) -> void:
	if is_picker_open() and not _applying_choice:
		return
	await _finish_pending_edits()
	_dismiss_start_screen()
	var owner_doc: GSTDocument = _active_document
	if owner_doc == null:
		return
	var old_stack: GSTStack = _stack
	var old_undo: GSTUndo = _undo
	var old_path: String = _current_path
	var old_recipe_open: bool = _recipe_open
	# A fresh GSTMaterialSync/material, as a new GSTDocument carries: a later
	# codegen failure on new_stack must not expose old_stack's last successful
	# preview (GSTMaterialSync.reset_installation).
	var old_preview_sync: GSTMaterialSync = _preview_sync
	var old_material: ShaderMaterial = _material
	var old_preview_layer_id: StringName = _preview_layer_id
	var new_undo: GSTUndo = GSTUndo.new(_undo_redo, new_stack, _library, _on_document_stack_changed.bind(owner_doc), _on_document_property_changed.bind(owner_doc))
	var new_preview_sync: GSTMaterialSync = GSTMaterialSync.new()
	var new_material: ShaderMaterial = new_preview_sync.get_material()
	_install_document_state_for(owner_doc, new_stack, new_undo, new_preview_sync, new_material, &"")
	_raw_set_current_path_for(owner_doc, new_path)
	_set_recipe_open_for(owner_doc, new_recipe_open)
	_undo_redo.create_action("GST: Replace stack", UndoRedo.MERGE_DISABLE)
	_undo_redo.add_do_method(_install_document_state_for.bind(owner_doc, new_stack, new_undo, new_preview_sync, new_material, &""))
	_undo_redo.add_undo_method(_install_document_state_for.bind(owner_doc, old_stack, old_undo, old_preview_sync, old_material, old_preview_layer_id))
	_undo_redo.add_do_method(_raw_set_current_path_for.bind(owner_doc, new_path))
	_undo_redo.add_undo_method(_raw_set_current_path_for.bind(owner_doc, old_path))
	_undo_redo.add_do_method(_set_recipe_open_for.bind(owner_doc, new_recipe_open))
	_undo_redo.add_undo_method(_set_recipe_open_for.bind(owner_doc, old_recipe_open))
	_undo_redo.add_do_method(_notify_replace_for.bind(owner_doc))
	_undo_redo.add_undo_method(_notify_replace_for.bind(owner_doc))
	_undo_redo.commit_action(false)
	_notify_replace()


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


## Not named get_material: Control already declares get_material() -> Material
## for its `material` property.
## Wired-by: none (editor smoke seam)
func get_shader_material() -> ShaderMaterial:
	return _material


## Wired-by: none (editor smoke seam)
func get_layer_menu() -> MenuButton:
	return _layer_menu


## Wired-by: none (editor smoke seam).
func get_return_to_effect_button() -> Button:
	return _return_to_effect


## Wired-by: none (editor smoke seam).
func get_preview_layer_id() -> StringName:
	return _preview_layer_id


## Wired-by: none (editor smoke seam).
func get_preview_status_label() -> Label:
	return _preview_status


## Wired-by: none (editor smoke seam).
func get_codegen_message_label() -> Label:
	return _codegen_message


## Wired-by: none (editor smoke seam)
func get_message_label() -> Label:
	return _codegen_message if not _codegen_message.text.is_empty() else _message_label


## Wired-by: none (editor smoke seam)
func get_randomize_button() -> Button:
	return _randomize_button


## The active document's UndoRedo: the history every GSTUndo action,
## Randomize, and "Replace stack" action commits to.
## Wired-by: none (editor smoke seam)
func get_watched_history() -> UndoRedo:
	return _undo_redo


## See _current_path.
## Wired-by: none (editor smoke seam)
func get_current_path() -> String:
	return _current_path


## Wired-by: none (editor smoke seam)
func is_overwrite_dialog_visible() -> bool:
	return _overwrite_dialog != null and _overwrite_dialog.visible


## Wired-by: none (editor smoke seam)
func is_export_dialog_visible() -> bool:
	return _export_dialog != null and _export_dialog.visible


## abandon=true also clears _pending_export, matching the real dialog's
## canceled path. abandon=false preserves it for a caller that immediately
## resolves the request that opened the dialog (simulating EditorFileDialog's
## auto-hide on file_selected, which never emits canceled).
## Wired-by: none (editor smoke seam)
func hide_export_dialog(abandon: bool = true) -> void:
	if _export_dialog != null:
		_export_dialog.hide()
	if abandon:
		_pending_export = {}


## Wired-by: none (editor smoke seam)
func get_close_dialog() -> ConfirmationDialog:
	return _close_dialog


## Wired-by: none (editor smoke seam)
func is_close_dialog_visible() -> bool:
	return _close_dialog != null and _close_dialog.visible


## Wired-by: none (editor smoke seam)
func get_close_dialog_discard_button() -> Button:
	return _close_discard_button


func _on_new_pressed() -> void:
	if is_picker_open() and not _applying_choice:
		return
	# open_document awaits _finish_pending_edits(), which suspends while a
	# native color popup's typed hex is being committed; without this await
	# the lines below would run against the previous _active_document.
	await open_document(GSTStack.new(), "", false)
	# A pristine document reused by _find_reusable_pristine_document can carry
	# a stale diagnostic (a prior failed Open); clear it on the document, not
	# only on the label, or _refresh_operation_message_label() re-shows it.
	if _active_document != null:
		_active_document.operation_messages.clear()
	_refresh_operation_message_label()
	_on_chooser_requested("add", &"", "", _stack_list.get_node("%AddButton") as Control)


func _on_file_menu_pressed(id: int) -> void:
	match id:
		FILE_NEW:
			_on_new_pressed()
		FILE_OPEN:
			_on_open_pressed()
		FILE_SAVE_AS:
			_on_save_as_pressed()
		FILE_REOPEN_SHADER:
			_on_reopen_shader_pressed()


func _on_open_pressed() -> void:
	if is_picker_open() and not _applying_choice:
		return
	_pending_open = _capture_active_document_request()
	_open_dialog.popup_centered_ratio()


## Routes a failure message to the document active when the Open dialog
## opened (_pending_open): a refusal activates nothing, so there is no new
## document to carry the reason. A success targets the document
## activate_document/open_document installs. A stale/closed captured
## document gets no failure message; the Open still proceeds. Awaited:
## _open_path_for suspends across a native color-popup commit.
func _on_open_file_selected(path: String) -> void:
	var message_doc: GSTDocument = _resolve_pending_document(_pending_open)
	_pending_open = {}
	await _open_path_for(message_doc, path)


## Activates path's already-open document if one exists, checked before
## touching disk, so a document still open reactivates even if its file was
## deleted or edited externally. Otherwise loads `path` through GSTStackIO
## and installs it via open_document. A refusal leaves the active document
## untouched and shows the reason on _active_document. Public for editor
## smoke.
func open_path(path: String) -> void:
	await _open_path_for(_active_document, path)


## Only the failure branch uses message_doc: a refusal activates nothing. A
## success clears the "Open" message on the document
## activate_document/open_document returned, captured from the await rather
## than re-read from _active_document: both await _finish_pending_edits(),
## which suspends across a native color-popup commit. open_document returns
## null under its is_picker_open() guard; a null document gets no message.
func _open_path_for(message_doc: GSTDocument, path: String) -> void:
	if is_picker_open() and not _applying_choice:
		return
	var existing: GSTDocument = _find_document_by_path(path)
	if existing != null:
		await activate_document(existing)
		_set_operation_message_for(existing, "Open", "")
		return
	var result: Dictionary = GSTStackIO.load(path, _library)
	if not result["ok"]:
		_set_operation_message_for(message_doc, "Open", result["reason"])
		return
	var opened: GSTDocument = await open_document(result["stack"], path, false)
	if opened != null:
		_set_operation_message_for(opened, "Open", "")


func _recipe_names() -> Array[String]:
	var names: Array[String] = []
	var dir: DirAccess = DirAccess.open(RECIPES_DIR)
	if dir == null:
		return names
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and entry_name.ends_with(".tres"):
			names.append(entry_name.get_basename())
		entry_name = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names


## Loads RECIPES_DIR/<name>.tres and installs it via open_document with an
## empty current_path: a recipe is a template, so Save falls back to Save As
## instead of overwriting the shipped file. Never reuses another open
## document: the same recipe opened twice yields independent copies. Public
## for editor smoke. Success targets the document open_document returned
## (see _open_path_for); the failure branch has no navigation to await, so
## _active_document is still the document this was called on.
func open_recipe(name: String) -> void:
	if is_picker_open() and not _applying_choice:
		return
	var path: String = "%s/%s.tres" % [RECIPES_DIR, name]
	var result: Dictionary = GSTStackIO.load(path, _library)
	if not result["ok"]:
		_set_operation_message("Recipes", result["reason"])
		return
	var opened: GSTDocument = await open_document(result["stack"], "", true, name)
	if opened != null:
		_set_operation_message_for(opened, "Recipes", "")


func _on_save_pressed() -> void:
	if _active_document == null:
		return
	if _active_document.current_path.is_empty():
		_on_save_as_pressed()
		return
	save_to_path(_active_document.current_path)


func _on_save_as_pressed() -> void:
	_pending_save_as = _capture_active_document_request()
	_save_as_dialog.popup_centered_ratio()


## Resolves against _pending_save_as (the document active when the Save As
## dialog opened). _resolve_pending_document folds "never captured" into
## _active_document, so doc is null only for a closed/stale target; that
## failure is surfaced on the active document. close_after (set only by
## _on_close_save_requested) closes doc once its save succeeds; a failed
## save leaves it dirty and open.
func _on_save_as_file_selected(path: String) -> void:
	var doc: GSTDocument = _resolve_pending_document(_pending_save_as)
	var close_after: bool = bool(_pending_save_as.get("close_after", false))
	_pending_save_as = {}
	var result: Dictionary = await _save_stack_to_path(doc, path)
	if doc == null:
		_set_operation_message("Save", String(result.get("reason", "")))
		return
	if close_after and bool(result.get("ok", false)) and _documents.has(doc):
		_close_document_now(doc)


## Saves the active document's stack to `path`. Save button handler (when a
## current path exists) and the direct-call entry point. Save As resolves
## its own captured document through _on_save_as_file_selected and calls
## _save_stack_to_path directly, so a document switch while the dialog is up
## cannot redirect the write.
func save_to_path(path: String) -> Dictionary:
	return await _save_stack_to_path(_active_document, path)


## Document-bound save. Refuses a stale/closed target (doc not in
## _documents) without writing or messaging elsewhere, and refuses a
## canonical path owned by a different open document with a conflict
## message on doc (doc's own current path resolves back to doc, so a re-save
## is unaffected). Finishes pending native gestures only when doc is active
## (an inactive document holds no live gesture). Marks doc's baseline
## fingerprint and path only on a successful write.
func _save_stack_to_path(doc: GSTDocument, path: String) -> Dictionary:
	if doc == null or not _documents.has(doc):
		return {"ok": false, "reason": "This document is no longer open."}
	var conflict: GSTDocument = _find_document_by_path(path)
	if conflict != null and conflict != doc:
		var result: Dictionary = {"ok": false, "reason": "%s is already open in another tab." % path}
		_set_operation_message_for(doc, "Save", result["reason"])
		return result
	if doc == _active_document:
		await _finish_pending_edits()
	var result: Dictionary = GSTStackIO.save(doc.stack, path)
	if not result["ok"]:
		_set_operation_message_for(doc, "Save", result["reason"])
		return result
	_raw_set_current_path_for(doc, path)
	doc.mark_baseline()
	# Successful save and close are the only two places a recovery record is
	# removed.
	_forget_recovery_record(doc)
	_refresh_tabs()
	_set_operation_message_for(doc, "Save", "")
	return result


func _on_export_pressed() -> void:
	_pending_export = _capture_active_document_request()
	_export_dialog.popup_centered_ratio()


## Resolves against _pending_export (the document active when the Export
## dialog opened). A closed target surfaces its reason on the active document.
func _on_export_file_selected(path: String) -> void:
	var doc: GSTDocument = _resolve_pending_document(_pending_export)
	_pending_export = {}
	var result: Dictionary = await _export_stack_to_path(doc, path, false)
	if doc == null:
		_set_operation_message("Export", String(result.get("reason", "")))


## Exports the active document's stack to `path`; the direct-call entry point.
## The Export dialog resolves its own captured document through
## _on_export_file_selected.
func export_to_path(path: String, confirm: bool) -> Dictionary:
	return await _export_stack_to_path(_active_document, path, confirm)


## Document-bound export. Refuses a stale/closed target like
## _save_stack_to_path. When GSTExport.write reports needs_confirmation,
## captures doc's id and the path into _pending_overwrite so
## _on_overwrite_confirmed re-targets the same document even if another
## becomes active while the dialog is up. Export never marks a baseline.
func _export_stack_to_path(doc: GSTDocument, path: String, confirm: bool) -> Dictionary:
	if doc == null or not _documents.has(doc):
		return {"ok": false, "reason": "This document is no longer open.", "needs_confirmation": false}
	if doc == _active_document:
		await _finish_pending_edits()
	var result: Dictionary = GSTExport.write(doc.stack, _library, path, confirm)
	if result["needs_confirmation"]:
		_next_file_request_id += 1
		_pending_overwrite = {"request_id": _next_file_request_id, "doc_id": doc.session_id, "path": path}
		_overwrite_dialog.dialog_text = "%s already holds a body that differs from this stack's codegen. Overwrite it?" % path
		_overwrite_dialog.popup_centered()
		return result
	# Hides the dialog explicitly: AcceptDialog's auto-hide only fires on a
	# button press, not on a direct confirm=true call.
	if _overwrite_dialog.visible:
		_overwrite_dialog.hide()
	if not result["ok"]:
		_set_operation_message_for(doc, "Export", result["reason"])
		return result
	_refresh_exported_shader(path, result["code"])
	_set_operation_message_for(doc, "Export", "")
	return result


## GSTExport.write only replaces the bytes on disk. A Shader already loaded
## from `path` keeps its old code until reloaded. Pushes the written text into
## the cached Shader (every ShaderMaterial on it recompiles) and notifies
## EditorFileSystem.
func _refresh_exported_shader(path: String, code: String) -> void:
	if ResourceLoader.has_cached(path):
		var cached: Resource = ResourceLoader.load(path)
		if cached is Shader:
			(cached as Shader).code = code
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)


## Re-targets the document _export_stack_to_path captured in
## _pending_overwrite. A stale/closed target only hides the dialog.
func _on_overwrite_confirmed() -> void:
	var doc: GSTDocument = _resolve_pending_document(_pending_overwrite)
	var path: String = String(_pending_overwrite.get("path", ""))
	_pending_overwrite = {}
	if doc == null:
		if _overwrite_dialog.visible:
			_overwrite_dialog.hide()
		return
	await _export_stack_to_path(doc, path, true)


func _on_reopen_shader_pressed() -> void:
	if is_picker_open() and not _applying_choice:
		return
	_pending_reopen = _capture_active_document_request()
	_reopen_shader_dialog.popup_centered_ratio()


## Routes a failure message to the document active when the Reopen Shader
## dialog opened; same reasoning as _on_open_file_selected. Awaited for the
## same suspension reason.
func _on_reopen_shader_file_selected(path: String) -> void:
	var message_doc: GSTDocument = _resolve_pending_document(_pending_reopen)
	_pending_reopen = {}
	await _reopen_shader_path_for(message_doc, path)


## Reopens a stack from an exported .gdshader's embedded header through
## GSTExport.reopen. A refusal (no header, unparsable header, unknown schema)
## shows the reason on the active document and leaves it untouched. On
## success, installs the rebuilt stack via open_document with an empty
## current_path (a reopened stack has no .tres of its own). When the file's
## body differs from a fresh codegen of its header, that warning replaces the
## success clear. Public for editor smoke.
func reopen_shader_path(path: String) -> void:
	await _reopen_shader_path_for(_active_document, path)


## Only the failure branch uses message_doc; a success targets the document
## open_document returned, captured from the await (see _open_path_for). A
## null return gets no message.
func _reopen_shader_path_for(message_doc: GSTDocument, path: String) -> void:
	if is_picker_open() and not _applying_choice:
		return
	var result: Dictionary = GSTExport.reopen(path, _library)
	if not result["ok"]:
		_set_operation_message_for(message_doc, "Reopen Shader", result["reason"])
		return
	var opened: GSTDocument = await open_document(result["stack"], "", false, "", true)
	if opened == null:
		return
	if result["body_differs"]:
		_set_operation_message_for(opened, "Reopen Shader", "%s reopened: its body differs from a fresh codegen of the header (hand edits detected)" % path)
	else:
		_set_operation_message_for(opened, "Reopen Shader", "")


func _on_layer_selected(layer_id: StringName) -> void:
	_inspector_column.edit(layer_id)
	_update_layer_menu()
	if _active_document != null:
		_active_document.selected_layer_id = layer_id


func _on_refused(reason: String) -> void:
	_stack_list.set_refusal(reason)


## GSTUndo's on_changed callback: fires after every do and undo.
func _on_stack_changed() -> void:
	for key: String in _control_refusals.keys():
		if key.begins_with("input:") or key.begins_with("warp:"):
			if GSTStackOps.find_layer(_stack, StringName(key.get_slice(":", 1))) == null:
				_control_refusals.erase(key)
	_stack_list.refresh()
	_output_block.refresh()
	_inspector_column.edit(_stack_list.get_selected_layer_id())
	_syncing_coord_space = true
	_coord_space_option.select(int(_stack.coord_space))
	_syncing_coord_space = false
	stack_changed.emit()
	_refresh_tabs()


## GSTUndo's on_property_changed callback: fires after every do and undo of a
## native property edit. Does not touch _stack_list, _output_block, or
## _inspector_column: a property edit never changes layer identity, slots, or
## references, and rebuilding the inspector column would free the row a live
## gesture or open color popup holds. gst_inspector_column.gd refreshes that
## row's displayed value itself. _refresh_tabs() keeps the dirty star
## current: a property edit changes is_dirty()'s fingerprint without passing
## through _on_stack_changed.
func _on_property_changed() -> void:
	_resync_material()
	_refresh_tabs()


## _resync_material runs first and sets the codegen message; the screen_uv
## suggestion is applied only on top of a clean sync so it never masks a
## codegen error.
func _on_preset_selected(index: int) -> void:
	if _syncing_preview_controls:
		return
	_set_operation_message("Preview", "")
	var preset_name: String = GSTPreviewPresets.PRESET_NAMES[index]
	_preview.set_preset(preset_name)
	if _active_document != null:
		_active_document.preview_preset = preset_name
	_resync_material()
	if _codegen_message.text.is_empty() and GSTPreviewPresets.suggests_screen_uv(preset_name, _stack.coord_space):
		_set_operation_message("Preview", "Text preview: use screen_uv for coordinates across the screen.")


func _on_image_button_pressed() -> void:
	_pending_image = _capture_active_document_request()
	_file_dialog.popup_centered_ratio()


## Resolves against _pending_image (the document active when the image dialog
## opened). Writes doc.preview_image_path unconditionally (restored on a
## later activation) but touches the live _preview/_material only when doc is
## active. A stale/closed target touches nothing.
func _on_preview_image_selected(path: String) -> void:
	var doc: GSTDocument = _resolve_pending_document(_pending_image)
	_pending_image = {}
	if doc == null:
		return
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		return
	doc.preview_image_path = path
	if doc != _active_document:
		return
	_preview.set_image(texture)
	_resync_material()


func _on_layer_menu_pressed(id: int) -> void:
	if id != 0 or is_picker_open():
		return
	var selected: StringName = _stack_list.get_selected_layer_id()
	if GSTStackOps.find_layer(_stack, selected) == null:
		return
	_preview_layer_id = selected
	if _active_document != null:
		_active_document.preview_layer_id = _preview_layer_id
	_resync_material()


func _on_return_to_effect_pressed() -> void:
	_preview_layer_id = &""
	if _active_document != null:
		_active_document.preview_layer_id = _preview_layer_id
	_resync_material()


## GSTPreview.target_rect_changed (window/splitter resize, or a preset swap to
## a different target size). Writes only gst_rect_size, never a full
## GSTMaterialSync.sync() codegen pass: this can fire once per frame during a
## drag.
func _on_target_rect_changed(size: Vector2) -> void:
	GSTMaterialSync.write_rect_size(_material, size)


func _on_coord_space_selected(index: int) -> void:
	if _syncing_coord_space or is_picker_open():
		return
	_undo.set_coord_space(index as GSTStack.CoordSpace)


func _set_recipe_open(value: bool) -> void:
	_recipe_open = value
	if _active_document != null:
		_active_document.recipe_open = value
	_randomize_button.disabled = not value or is_picker_open()


## Injects the RNG _on_randomize_pressed draws from, so a test's change set is
## deterministic.
## Wired-by: none (editor smoke seam)
func set_randomize_rng(rng: RandomNumberGenerator) -> void:
	_randomize_rng = rng


## Randomizes every slider on the open recipe: computes the change set with
## GSTRandomize.randomize, then hands it to GSTUndo.apply_randomize.
## `old_changes` mirrors `changes` with each layer's pre-randomize values so
## undo can restore them. `unset_params` records which values were implicit
## defaults so undo erases them again instead of leaving an explicit default
## that would change the serialized header. An empty change set registers no
## action. _randomize_rng, when set, replaces the fresh OS-seeded generator.
func _on_randomize_pressed() -> void:
	if is_picker_open() and not _applying_choice:
		return
	var rng: RandomNumberGenerator = _randomize_rng
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var changes: Dictionary = GSTRandomize.randomize(_stack, _library, rng)
	if changes.is_empty():
		return
	var old_changes: Dictionary = {}
	var unset_params: Dictionary = {}
	for layer_id: Variant in changes.keys():
		var layer: GSTLayer = GSTStackOps.find_layer(_stack, StringName(layer_id))
		if layer == null:
			continue
		var layer_changes: Dictionary = changes[layer_id]
		var old_layer_changes: Dictionary = {}
		var unset_names: Array[String] = []
		for param_name: Variant in layer_changes.keys():
			old_layer_changes[param_name] = layer.get(StringName(param_name))
			if not layer.params.has(String(param_name)):
				unset_names.append(String(param_name))
		old_changes[layer_id] = old_layer_changes
		unset_params[layer_id] = unset_names
	_undo.apply_randomize(changes, old_changes, unset_params)


## Diagnostic preview captures a stable layer ID without changing output.
## Recovery materials belong only to the current stack installation.
func _resync_material() -> void:
	if _stack == null or _library == null or _preview == null or _material == null:
		return
	var diagnostic_layer: GSTLayer = GSTStackOps.find_layer(_stack, _preview_layer_id)
	if diagnostic_layer == null:
		_preview_layer_id = &""
	var rect_size: Vector2 = _preview.get_target_rect_size()
	var result: GSTCodegenResult = _preview_sync.sync_preview(_stack, _library, _preview_layer_id, rect_size)
	_preview.set_shader_material(_material)
	_codegen_message.text = result.error
	_codegen_message.visible = not result.error.is_empty()
	_error_scroll.visible = not result.error.is_empty()
	_preview_status.text = "No effect yet" if _stack.layers.is_empty() else ""
	if not result.ok() and _preview_sync.has_successful_preview():
		_preview_status.text = "Showing last successful preview"
	_preview_status.visible = not _preview_status.text.is_empty()
	_preview_heading.text = "Preview"
	if diagnostic_layer != null:
		var entry: GSTManifestEntry = _library.get_entry(diagnostic_layer.entry)
		_preview_heading.text = "Preview: %s (l%s)" % [entry.function if entry != null else diagnostic_layer.entry, String(_preview_layer_id)]
	_return_to_effect.visible = diagnostic_layer != null
	_update_layer_menu()


func _update_layer_menu() -> void:
	_layer_menu.disabled = is_picker_open() or _stack == null or GSTStackOps.find_layer(_stack, _stack_list.get_selected_layer_id()) == null


func get_picker() -> GSTPicker:
	return _picker


func is_picker_open() -> bool:
	return not _picker_context.is_empty()


func get_picker_context() -> Dictionary:
	return _picker_context.duplicate()


func _on_recipes_pressed() -> void:
	_on_chooser_requested("recipe", &"", "", _recipes_button)


func _on_chooser_requested(purpose: String, layer_id: StringName, slot_name: String, initiator: Control) -> void:
	if purpose not in ["add", "recipe", "output_color", "output_alpha", "input", "warp"]:
		return
	if is_picker_open():
		return
	_picker_context = {"stack": _stack, "purpose": purpose, "layer_id": layer_id, "slot_name": slot_name}
	_picker_focus = weakref(initiator)
	var title: String = {"add": "Add Layer", "recipe": "Recipes", "output_color": "Output color", "output_alpha": "Transparency", "input": "Choose input", "warp": "Choose distortion"}.get(purpose, "Choose layer")
	if purpose == "input" or purpose == "warp":
		var layer: GSTLayer = GSTStackOps.find_layer(_stack, layer_id)
		if layer != null:
			var entry: GSTManifestEntry = _library.get_entry(layer.entry)
			var label: String = slot_name.capitalize()
			if purpose == "warp":
				label = "Horizontal distortion" if slot_name == "x" else "Vertical distortion"
			elif entry != null:
				for input: Dictionary in entry.inputs:
					if String(input["name"]) == slot_name:
						label = input.get("label", label)
			title = "%s: %s (l%s)" % [label, entry.function if entry != null else layer.entry, String(layer_id)]
	_set_picker_modality(true)
	_picker.open_choices(title, _choice_rows(0), purpose == "input" or purpose == "warp")
	_picker.set_refusal(String(_control_refusals.get(_picker_key(), "")))


func _set_picker_modality(blocked: bool) -> void:
	_stack_list.set_mutations_blocked(blocked)
	_inspector_column.set_mutations_blocked(blocked)
	_output_block.set_mutations_blocked(blocked or _start_screen.visible)
	_coord_space_option.disabled = blocked
	_recipes_button.disabled = blocked
	_randomize_button.disabled = blocked or not _recipe_open
	_create_empty.disabled = blocked
	_start_open.disabled = blocked
	for button: Button in _start_recipe_buttons.values():
		button.disabled = blocked
	_update_layer_menu()
	var popup: PopupMenu = _file_menu.get_popup()
	for id: int in [FILE_NEW, FILE_OPEN, FILE_REOPEN_SHADER]:
		popup.set_item_disabled(popup.get_item_index(id), blocked)


func _input(event: InputEvent) -> void:
	if is_picker_open():
		if not is_visible_in_tree() or not event is InputEventKey:
			return
		var key: InputEventKey = event as InputEventKey
		if not key.pressed:
			return
		# Editor undo/redo is a stack mutation while a destination is captured.
		if key.ctrl_pressed or key.meta_pressed:
			if key.keycode in [KEY_Z, KEY_Y, KEY_N, KEY_O, KEY_DELETE]:
				get_viewport().set_input_as_handled()
		var focus: Control = get_viewport().gui_get_focus_owner()
		if focus != null and _editing_content.is_ancestor_of(focus):
			_picker.get_search_control().grab_focus()
			get_viewport().set_input_as_handled()
		return
	await _handle_undo_redo_shortcut(event)


## Scopes keyboard Undo/Redo to GoShade focus, including a native property
## popup: the panel's standalone UndoRedo is not reachable through the
## editor's Edit > Undo/Redo, which only drives EditorUndoRedoManager
## histories. Outside GoShade focus the event is left alone so scene Undo
## keeps working. On Godot 4.6.2/4.7 a key event never reaches here while a
## native, non-embedded color popup subwindow holds focus;
## gst_inspector_column.gd's color_popup_undo_redo_requested signal
## (connected to _apply_keyboard_undo_redo) is that case's entry point.
func _handle_undo_redo_shortcut(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or not (key.ctrl_pressed or key.meta_pressed) or key.keycode != KEY_Z:
		return
	if not _owns_undo_focus():
		return
	# Consumed before the await: otherwise the event stays unhandled for as
	# long as finish_pending_edits() yields and a later input pass can act on
	# it.
	get_viewport().set_input_as_handled()
	await _apply_keyboard_undo_redo(key.shift_pressed)


## Finishes any pending native edit, then undoes (or redoes, if `redo`) the
## active document's UndoRedo. Shared body of _handle_undo_redo_shortcut and
## gst_inspector_column.gd's color_popup_undo_redo_requested signal.
func _apply_keyboard_undo_redo(redo: bool) -> void:
	await _finish_pending_edits()
	if redo:
		if _undo_redo.has_redo():
			_undo_redo.redo()
	else:
		if _undo_redo.has_undo():
			_undo_redo.undo()


func _owns_undo_focus() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus == null:
		return false
	if is_ancestor_of(focus):
		return true
	return _inspector_column.owns_popup_focus(focus)


## restore_focus=false (activate_document's cancel-on-switch call) skips
## focus restoration: a deferred grab_focus() must not target rows
## _install_stack is about to free.
func _close_picker(restore_focus: bool = true) -> void:
	if not is_picker_open():
		return
	var context: Dictionary = _picker_context
	_picker_context = {}
	_picker.hide()
	_set_picker_modality(false)
	if not restore_focus:
		_picker_focus = null
		return
	var target: Control = _picker_focus.get_ref() as Control if _picker_focus != null else null
	if context["stack"] == _stack:
		if context["purpose"] == "input":
			target = _inspector_column.get_input_button(context["slot_name"])
		elif context["purpose"] == "warp":
			target = _inspector_column.get_warp_button(context["slot_name"])
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		target = _stack_list.get_node("%AddButton") as Control
	if target.is_visible_in_tree():
		target.grab_focus.call_deferred()
	_picker_focus = null


func _picker_key() -> String:
	return "%s:%s:%s" % [_picker_context.get("purpose", ""), _picker_context.get("layer_id", ""), _picker_context.get("slot_name", "")]


func _picker_refusal(reason: String) -> void:
	_control_refusals[_picker_key()] = reason
	_picker.set_refusal(reason)
	var purpose: String = _picker_context["purpose"]
	if purpose == "input" or purpose == "warp":
		_inspector_column.set_refusal(_picker_context["layer_id"], _picker_context["slot_name"], purpose, reason)
	elif purpose.begins_with("output_"):
		_output_block.set_refusal(purpose, reason)
	elif purpose == "add":
		_stack_list.set_refusal(reason)
	elif purpose == "recipe":
		_set_operation_message("Recipes", reason)


func _on_picker_tab_changed(tab: int) -> void:
	if is_picker_open():
		_picker.set_choices(_choice_rows(tab))


func _destination_error() -> String:
	if _picker_context.get("stack") != _stack:
		return "The open stack changed. Close this chooser and choose again."
	var purpose: String = _picker_context["purpose"]
	if purpose != "input" and purpose != "warp":
		return ""
	var layer: GSTLayer = GSTStackOps.find_layer(_stack, _picker_context["layer_id"])
	if layer == null:
		return "This layer was removed. Close this chooser and choose again."
	var name: String = _picker_context["slot_name"]
	if purpose == "warp":
		return "" if layer.coord != null and name in ["x", "y"] else "This distortion input is no longer available."
	var entry: GSTManifestEntry = _library.get_entry(layer.entry)
	if entry != null:
		for input: Dictionary in entry.inputs:
			if String(input["name"]) == name:
				return ""
	return "This input is no longer available."


func _choice_rows(tab: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not _destination_error().is_empty():
		return rows
	var purpose: String = _picker_context["purpose"]
	var dest: GSTLayer = GSTStackOps.find_layer(_stack, _picker_context["layer_id"])
	var wanted_kind: int = GSTLayer.Kind.FIELD if purpose == "warp" else -1
	var source_only: bool = false
	if purpose == "input":
		var manifest: GSTManifestEntry = _library.get_entry(dest.entry)
		source_only = manifest.samples_source
		for input: Dictionary in manifest.inputs:
			if String(input["name"]) == _picker_context["slot_name"]:
				wanted_kind = int(input["kind"])
	if purpose == "add" or (purpose in ["input", "warp"] and tab == 1):
		var ids: Array = _library.entries.keys()
		ids.sort()
		for id: String in ids:
			var entry: GSTManifestEntry = _library.get_entry(id)
			if _stack.layers.is_empty() and not entry.inputs.is_empty():
				continue
			if source_only and id not in ["source/texture", "source/screen"]:
				continue
			var input_kinds: Array[String] = []
			for input: Dictionary in entry.inputs:
				input_kinds.append(_kind_name(int(input["kind"])))
			rows.append({"value": id, "title": entry.function, "category": id.get_slice("/", 0), "kind": "(%s) -> %s" % [", ".join(input_kinds), _kind_name(entry.kind_out)], "description": entry.description, "conversion": _conversion(entry.kind_out, wanted_kind)})
		return rows
	if purpose == "recipe":
		for name: String in _recipe_names():
			rows.append({"value": name, "title": name, "category": "Recipes", "kind": "stack", "description": "Open this bundled recipe as an editable stack.", "conversion": ""})
		return rows
	if purpose in ["input", "warp"]:
		rows.append(_mode_row("", "No layer", "Leave this input unconnected."))
	elif purpose == "output_color":
		wanted_kind = GSTLayer.Kind.COLOR
		rows.append(_mode_row("", _output_block.get_automatic_color_text(), "Use the highest color layer in the stack."))
	elif purpose == "output_alpha":
		rows.append(_mode_row("", _output_block.get_automatic_alpha_text(), "Use texture transparency when a texture source exists; otherwise use opaque."))
		rows.append(_mode_row("none", "Opaque", "Show the finished effect without transparency."))
		rows.append(_mode_row("texture", "Texture transparency", "Use the original texture transparency."))
		rows.append(_mode_row("color_alpha", "Output layer transparency", "Use the output layer transparency. A field output is opaque."))
	var limit: int = GSTStackOps.find_index(_stack, dest.id) if dest != null else _stack.layers.size()
	for i: int in range(limit - 1, -1, -1):
		var layer: GSTLayer = _stack.layers[i]
		if source_only and layer.entry not in ["source/texture", "source/screen"]:
			continue
		if purpose == "output_alpha" and layer.kind_out != GSTLayer.Kind.FIELD:
			continue
		var entry: GSTManifestEntry = _library.get_entry(layer.entry)
		rows.append({"value": String(layer.id), "title": "%s (l%s)" % [entry.function if entry != null else layer.entry, String(layer.id)], "category": "Layers", "kind": _kind_name(layer.kind_out), "description": entry.description if entry != null else "", "conversion": _conversion(layer.kind_out, wanted_kind)})
	return rows


func _mode_row(value: String, title: String, description: String) -> Dictionary:
	return {"value": value, "title": title, "category": "Options", "kind": "", "description": description, "conversion": ""}


func _kind_name(kind: int) -> String:
	return "field" if kind == GSTLayer.Kind.FIELD else "color"


func _conversion(kind: int, wanted: int) -> String:
	if wanted < 0 or kind == wanted:
		return ""
	return "field -> color: grayscale" if kind == GSTLayer.Kind.FIELD else "color -> field: luminance"


func _on_picker_choice(choice: Dictionary) -> void:
	if not is_picker_open():
		return
	if not choice.has("value"):
		_picker_refusal("This choice has no value.")
		return
	var error: String = _destination_error()
	if not error.is_empty():
		_picker_refusal(error)
		return
	var value: String = String(choice.get("value", ""))
	var eligible: bool = false
	for row: Dictionary in _choice_rows(_picker.get_tab_index()):
		if row["value"] == value:
			eligible = true
			break
	if not eligible:
		_picker_refusal("This choice is no longer available for this input.")
		return
	var purpose: String = _picker_context["purpose"]
	var layer_id: StringName = _picker_context["layer_id"]
	var slot: String = _picker_context["slot_name"]
	var result: Dictionary = {"ok": true, "reason": ""}
	_applying_choice = true
	match purpose:
		"add":
			result = _undo.add_layer_for_ui(value)
			if result["ok"]:
				_stack_list.select_layer(result["layer"].id)
		"input":
			result = _undo.add_layer_below_and_wire(layer_id, value, slot) if _picker.get_tab_index() == 1 else _undo.assign_slot(layer_id, slot, StringName(value))
		"warp":
			result = _undo.add_layer_below_and_wire_warp(layer_id, value, slot) if _picker.get_tab_index() == 1 else _undo.assign_warp(layer_id, slot, StringName(value))
		"output_color":
			if _stack.output_color != StringName(value):
				result = _undo.set_output_color(StringName(value))
		"output_alpha":
			if _stack.output_alpha != StringName(value):
				result = _undo.set_output_alpha(StringName(value))
		"recipe":
			var loaded: Dictionary = GSTStackIO.load("%s/%s.tres" % [RECIPES_DIR, value], _library)
			result = loaded
			if loaded["ok"]:
				# open_document awaits _finish_pending_edits(), which suspends
				# across a native color-popup commit; without this await the
				# success tail below would run against the previous
				# _active_document.
				await open_document(loaded["stack"], "", true, value)
	_applying_choice = false
	if not result["ok"]:
		_picker_refusal(result["reason"])
		return
	_picker_refusal("")
	_close_picker()


## Synchronous operation message on the active document (Recipes' picker
## refusal path, the preset dropdown's screen_uv suggestion): neither can
## outlive an await across a document switch. File-dialog handlers use
## _set_operation_message_for with their resolved document.
func _set_operation_message(control: String, reason: String) -> void:
	_set_operation_message_for(_active_document, control, reason)


## Routes an operation diagnostic onto doc.operation_messages and rebuilds
## the shared label only when doc is active. A null doc (resolved
## stale/closed request) is a no-op.
func _set_operation_message_for(doc: GSTDocument, control: String, reason: String) -> void:
	if doc == null:
		return
	if reason.is_empty():
		doc.operation_messages.erase(control)
	else:
		doc.operation_messages[control] = reason
	if doc == _active_document:
		_refresh_operation_message_label()


## Rebuilds _message_label from _active_document.operation_messages; called
## from _set_operation_message_for and _install_stack.
func _refresh_operation_message_label() -> void:
	var lines: Array[String] = []
	if _active_document != null:
		for name: Variant in _active_document.operation_messages:
			lines.append("%s: %s" % [String(name), _active_document.operation_messages[name]])
	_message_label.text = "\n".join(lines)
	_message_label.visible = not lines.is_empty()
