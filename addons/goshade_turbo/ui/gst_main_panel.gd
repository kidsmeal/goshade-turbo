@tool
class_name GSTMainPanel
extends VBoxContainer

## Main screen panel: a responsive editing allocation beside a persistent
## preview allocation. The editing allocation holds Layers and Layer
## settings in a split or tabs; Final output stays below the preview.
##
## Holds the current GSTStack (a new empty stack on open) and the GSTLibrary
## (scanned once). stack_changed fires after every structural edit so this
## panel's own preview material stays in sync (self-connected below) and so
## a caller that mutates the stack directly, bypassing GSTUndo (e.g. an
## invocation-local codegen-error excursion), can re-emit it to force a
## resync (docs/PLAN.md Phase 5 Files, tests/gst_editor_smoke.gd item 8).
##
## Material sync (decision 7, GSTMaterialSync) resyncs on three triggers now
## that phase 2 (docs/SHADER_TABS_reviewed-plan.md) routes every stack
## mutation -- structural edits, coord-space edits, Randomize, and native
## property edits alike -- through GSTUndo into one standalone UndoRedo:
## (1) stack_changed, self-connected here, fired by GSTUndo's own bound
## _notify/_notify_replace do/undo pair on every initial edit, undo, and
## redo, covering every mutation this panel makes without needing a separate
## history-version watcher (decision superseding 20: an embedded
## EditorInspector's own automatic undo integration no longer exists, so
## there is no gap to cover); (2) diagnostic preview changes; (3) a preset or
## preview-image change. A fourth path, GSTPreview.target_rect_changed (an
## editor-window or splitter resize), does not run this full resync: it
## writes only gst_rect_size via GSTMaterialSync.write_rect_size, since it
## can fire once per frame during a drag (B5).

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

const COORD_SPACE_NAMES: Array[String] = ["uv", "screen_uv", "local"]
## docs/PLAN.md Phase 7 Files: the Recipes MenuButton lists every .tres here.
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
## This interim phase (docs/SHADER_TABS_reviewed-plan.md phase 2) gives the
## whole panel one standalone UndoRedo, shared across New/Open/Reopen/Recipe
## the same way the prior EditorUndoRedoManager history was; phase 3 moves
## ownership of a UndoRedo instance onto each GSTDocument instead. A
## standalone UndoRedo has exactly one history bucket, so unlike the prior
## EditorUndoRedoManager there is no custom_context/get_object_history_id
## routing concern: every GSTUndo action and every "Replace stack"/Randomize
## action below always lands in this same instance.
var _undo_redo: UndoRedo = UndoRedo.new()
var _undo: GSTUndo = null
var _preview_sync: GSTMaterialSync = GSTMaterialSync.new()
var _material: ShaderMaterial = _preview_sync.get_material()
var _preview_layer_id: StringName = &""
var _start_recipe_buttons: Dictionary = {}
## Guards _coord_space_option.select() calls made to reflect stack state from
## re-triggering _on_coord_space_selected (mirrors gst_output_block.gd's own
## _syncing guard for the same reason).
var _syncing_coord_space: bool = false
var _file_dialog: EditorFileDialog = null

## The .tres this stack was last opened from or saved to; "" for a new,
## never-saved stack, or after a reopen-from-.gdshader (decision 8: a
## reopened stack has no .tres of its own to "Save" back onto, so it starts
## unsaved like a new stack).
var _current_path: String = ""
var _open_dialog: EditorFileDialog = null
var _save_as_dialog: EditorFileDialog = null
var _export_dialog: EditorFileDialog = null
var _reopen_shader_dialog: EditorFileDialog = null
var _overwrite_dialog: ConfirmationDialog = null
## The export target awaiting the overwrite confirmation dialog's answer.
var _pending_export_path: String = ""

## True only right after open_recipe() installs a shipped recipe (docs/PLAN.md
## Phase 8 Build item 3, design decision 16): gates the Randomize button.
## New, Open, and Reopen Shader each clear it, since a from-scratch or
## reopened-from-.gdshader stack is not "an open recipe" even if its layers
## happen to match one.
var _recipe_open: bool = false

## Overrides the RandomNumberGenerator _on_randomize_pressed draws from
## (docs/PLAN.md Phase 8 fix pass 4, item 2). null (the default) keeps the
## shipped behavior: a fresh RandomNumberGenerator seeded from the OS on
## every press. tests/gst_editor_smoke.gd seeds a duplicate stack's RNG with
## the same seed before pressing the real button and computes the expected
## change set from that duplicate, so GST_EDITOR_SMOKE=8's post-randomize
## checks compare against an exact expectation instead of merely "changed".
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

	# _resync_material runs before the material is ever handed to the preview
	# node: GSTMaterialSync.sync() creates _material.shader itself and sets
	# its code to a real, non-empty value in the same call. Assigning a
	# ShaderMaterial to a CanvasItem's `material` while its Shader still has
	# empty code, then mutating `.code` afterward on that same Shader object,
	# leaves the render stuck showing the node's unshaded appearance forever
	# after -- confirmed by an isolated repro (a second TextureRect whose
	# shader code was set 3 frames after first being assigned rendered black,
	# never green, across 8 further frames; a material created with real code
	# before ever being assigned rendered correctly immediately). Every
	# _resync_material() call after this first one is safe either way, since
	# by then the shader already carries real code. _install_stack() (called
	# below, once this node's own wiring above is complete) resyncs again once
	# the stack is actually editable, so no further call is needed here.
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

	_recipes_button.pressed.connect(_on_recipes_pressed)
	_randomize_button.pressed.connect(_on_randomize_pressed)
	_set_recipe_open(false)

	_open_dialog = EditorFileDialog.new()
	_open_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_open_dialog.add_filter("*.tres", "GoShade Turbo Stack")
	_open_dialog.file_selected.connect(_on_open_file_selected)
	add_child(_open_dialog)

	_save_as_dialog = EditorFileDialog.new()
	_save_as_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_save_as_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_save_as_dialog.add_filter("*.tres", "GoShade Turbo Stack")
	_save_as_dialog.file_selected.connect(_on_save_as_file_selected)
	add_child(_save_as_dialog)

	_export_dialog = EditorFileDialog.new()
	_export_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_export_dialog.add_filter("*.gdshader", "GoShade Turbo Shader")
	_export_dialog.file_selected.connect(_on_export_file_selected)
	add_child(_export_dialog)

	_reopen_shader_dialog = EditorFileDialog.new()
	_reopen_shader_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_reopen_shader_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_reopen_shader_dialog.add_filter("*.gdshader", "GoShade Turbo Shader")
	_reopen_shader_dialog.file_selected.connect(_on_reopen_shader_file_selected)
	add_child(_reopen_shader_dialog)

	_overwrite_dialog = ConfirmationDialog.new()
	_overwrite_dialog.confirmed.connect(_on_overwrite_confirmed)
	add_child(_overwrite_dialog)
	_build_start_screen()
	_apply_default_layout.call_deferred()

	# Installs the initial, never-saved stack with no undo action registered
	# around it: there is nothing before the first stack to undo back to.
	# Previously called externally by plugin.gd once it had a real
	# EditorUndoRedoManager to hand over (decision 20); phase 2 gives this
	# panel its own standalone UndoRedo directly, so installation happens
	# here instead of waiting on the plugin.
	_install_stack(_stack, GSTUndo.new(_undo_redo, _stack, _library, _on_stack_changed, _on_property_changed))


## Releases this panel's own UndoRedo (an Object, not a RefCounted or a Node:
## it has no owner to free it automatically) and its GSTUndo adapter, which
## retains bound Callables closing over this panel, when the panel itself
## leaves the tree (phase 2 review round 2 fix pass). GSTUndo's own bound
## Callables inside _undo_redo's recorded actions are released along with it.
func _exit_tree() -> void:
	if _undo_redo != null and is_instance_valid(_undo_redo):
		_undo_redo.free()
	_undo_redo = null
	_undo = null


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


## Called once by plugin.gd right after instantiation (decision 20's
## Wires the stack-list/output-block/inspector columns and the coord-space
## dropdown to `stack`/`undo`, and resyncs the material. This is the do/undo
## primitive for a stack replacement (phase 6 fix pass 2, item 1): replace_stack
## below registers this method as both the do and the undo method of a
## "Replace stack" UndoRedo action (alongside a second do/undo pair for
## _current_path), so undo reinstalls the exact previous GSTStack instance and
## its previous GSTUndo instance -- not a freshly constructed one -- and every
## action already recorded through that GSTUndo's own bound-Callable methods
## keeps landing on the GSTStack/GSTLayer instances it actually closed over.
## Also called directly, with no action registered, by _ready() for the very
## first stack.
func _install_stack(stack: GSTStack, undo: GSTUndo) -> void:
	_preview_sync.reset_installation()
	_material = _preview_sync.get_material()
	_preview_layer_id = &""
	_picker.set_refusal("")
	_control_refusals.clear()
	_message_label.text = ""
	_message_label.hide()
	_stack_list.clear_refusals()
	_inspector_column.clear_refusals()
	_output_block.clear_refusals()
	_stack = stack
	_undo = undo
	_stack_list.setup(_stack, _library, _undo)
	_output_block.setup(_stack, _library, _undo)
	_inspector_column.setup(_stack, _library, _undo)
	_inspector_column.edit(_stack_list.get_selected_layer_id())
	_syncing_coord_space = true
	_coord_space_option.select(int(_stack.coord_space))
	_syncing_coord_space = false
	_resync_material()


func _raw_set_current_path(path: String) -> void:
	_current_path = path


func _notify_replace() -> void:
	stack_changed.emit()


## Finishes any active native gesture and closes any open native color popup
## before a rebind, Save/Save As, Export, or keyboard undo/redo (decision
## superseding 20; phase 1 tabs_proof "forced_finish_ordering"). The common
## case (nothing pending) resolves synchronously with no suspension, since
## GSTInspectorColumn only awaits a frame while an open color popup's typed
## text is actually being committed.
func _finish_pending_edits() -> void:
	await _inspector_column.finish_pending_edits()


## Wired-by: none (editor smoke seam)
func get_stack() -> GSTStack:
	return _stack


## Installs new_stack (and new_path as the new _current_path, and
## new_recipe_open as the new _recipe_open) as an undoable "Replace stack"
## action in this panel's one standalone UndoRedo, rather than mutating
## _stack/_current_path/_recipe_open directly: a structural edit made before
## New, Open, or Reopen Shader now stays undoable afterward instead of being
## discarded along with the replaced GSTStack (phase 6 fix pass 2 item 1). The
## recipe-open flag (decision 16's Randomize gate) is recorded and replayed
## the same way: undoing a New/Open/Reopen that closed an open recipe
## re-enables Randomize, and redoing it disables it again (fix pass 3, item
## 3). Phase 2 removes the prior EditorUndoRedoManager custom_context/history
## bucket concern entirely: this standalone UndoRedo has exactly one bucket,
## so every action -- this one, every GSTUndo action, and Randomize -- always
## lands in the same place regardless of what was opened in between.
## _on_new_pressed, open_path, open_recipe, and reopen_shader_path call this
## instead of mutating _stack/_current_path/_recipe_open directly.
func replace_stack(new_stack: GSTStack, new_path: String, new_recipe_open: bool) -> void:
	if is_picker_open() and not _applying_choice:
		return
	await _finish_pending_edits()
	_dismiss_start_screen()
	var old_stack: GSTStack = _stack
	var old_undo: GSTUndo = _undo
	var old_path: String = _current_path
	var old_recipe_open: bool = _recipe_open
	var new_undo: GSTUndo = GSTUndo.new(_undo_redo, new_stack, _library, _on_stack_changed, _on_property_changed)
	_install_stack(new_stack, new_undo)
	_raw_set_current_path(new_path)
	_set_recipe_open(new_recipe_open)
	_undo_redo.create_action("GST: Replace stack", UndoRedo.MERGE_DISABLE)
	_undo_redo.add_do_method(_install_stack.bind(new_stack, new_undo))
	_undo_redo.add_undo_method(_install_stack.bind(old_stack, old_undo))
	_undo_redo.add_do_method(_raw_set_current_path.bind(new_path))
	_undo_redo.add_undo_method(_raw_set_current_path.bind(old_path))
	_undo_redo.add_do_method(_set_recipe_open.bind(new_recipe_open))
	_undo_redo.add_undo_method(_set_recipe_open.bind(old_recipe_open))
	_undo_redo.add_do_method(_notify_replace)
	_undo_redo.add_undo_method(_notify_replace)
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


## Not named get_material: Control (CanvasItem) already declares
## get_material() -> Material for its own `material` property; a narrowed
## ShaderMaterial return type is legal (covariant), but the rename keeps this
## unambiguous alongside gst_preview.gd's own set_shader_material rename.
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


## This panel's one standalone UndoRedo (phase 2). Lets editor smoke drive
## undo()/redo() directly against the exact history every GSTUndo action,
## Randomize, and "Replace stack" action commits to.
## Wired-by: none (editor smoke seam)
func get_watched_history() -> UndoRedo:
	return _undo_redo


## The .tres this stack was last opened from or saved to, or "" for a new or
## reopened-from-.gdshader stack (see _current_path).
## Wired-by: none (editor smoke seam)
func get_current_path() -> String:
	return _current_path


## Wired-by: none (editor smoke seam)
func is_overwrite_dialog_visible() -> bool:
	return _overwrite_dialog != null and _overwrite_dialog.visible


## Wired-by: none (editor smoke seam)
func is_export_dialog_visible() -> bool:
	return _export_dialog != null and _export_dialog.visible


## Wired-by: none (editor smoke seam)
func hide_export_dialog() -> void:
	if _export_dialog != null:
		_export_dialog.hide()


func _on_new_pressed() -> void:
	if is_picker_open() and not _applying_choice:
		return
	replace_stack(GSTStack.new(), "", false)
	_message_label.text = ""
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
	_open_dialog.popup_centered_ratio()


func _on_open_file_selected(path: String) -> void:
	open_path(path)


## Loads `path` through GSTStackIO and installs it via replace_stack (decision
## 20: an undoable "Replace stack" action, same as New). A refusal (a missing
## file or an unresolved entry) leaves the current stack untouched and shows
## the reason in the message label. This is the Open button's own
## file-selected handler (_on_open_file_selected calls it directly); public
## so tests/gst_editor_smoke.gd can drive the same path without popping the
## file dialog (docs/PLAN.md Phase 4 Files precedent, gst_stack_list.gd's
## add_layer_by_entry_id).
func open_path(path: String) -> void:
	if is_picker_open() and not _applying_choice:
		return
	var result: Dictionary = GSTStackIO.load(path, _library)
	if not result["ok"]:
		_set_operation_message("Open", result["reason"])
		return
	replace_stack(result["stack"], path, false)
	_set_operation_message("Open", "")


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


## Loads RECIPES_DIR/<name>.tres and installs it via replace_stack (decision
## 20: an undoable "Replace stack" action, same as New/Open/Reopen Shader),
## with the new current_path left empty rather than set to the recipe's own
## path: a recipe is a template, so Save falls back to Save As instead of
## silently overwriting the shipped recipe file (docs/PLAN.md Phase 7 Files).
## This is the Recipes menu's own handler; public so
## tests/gst_editor_smoke.gd can drive the same path directly.
func open_recipe(name: String) -> void:
	if is_picker_open() and not _applying_choice:
		return
	var path: String = "%s/%s.tres" % [RECIPES_DIR, name]
	var result: Dictionary = GSTStackIO.load(path, _library)
	if not result["ok"]:
		_set_operation_message("Recipes", result["reason"])
		return
	replace_stack(result["stack"], "", true)
	_set_operation_message("Recipes", "")


func _on_save_pressed() -> void:
	if _current_path.is_empty():
		_on_save_as_pressed()
		return
	save_to_path(_current_path)


func _on_save_as_pressed() -> void:
	_save_as_dialog.popup_centered_ratio()


func _on_save_as_file_selected(path: String) -> void:
	save_to_path(path)


## Saves the open stack to `path` through GSTStackIO. This is both the Save
## button's own handler (when a current path already exists) and Save As's
## file-selected handler; public so the smoke can drive it directly too.
## Finishes pending native gestures/popups first (decision superseding 20):
## a save must never write before the pending edit reaches the stack.
func save_to_path(path: String) -> void:
	await _finish_pending_edits()
	var result: Dictionary = GSTStackIO.save(_stack, path)
	if not result["ok"]:
		_set_operation_message("Save", result["reason"])
		return
	_current_path = path
	_set_operation_message("Save", "")


func _on_export_pressed() -> void:
	_export_dialog.popup_centered_ratio()


func _on_export_file_selected(path: String) -> void:
	export_to_path(path, false)


## Exports the open stack to `path` through GSTExport.write (decision 9: the
## overwrite gate). When the target exists with a differing body and
## `confirm` is false, shows the overwrite confirmation dialog and performs
## no write; confirming it re-calls this with `confirm = true`. This is the
## Export button's file-selected handler and the confirmation dialog's own
## confirmed handler; public so the smoke can drive it directly too. Finishes
## pending native gestures/popups first (decision superseding 20).
func export_to_path(path: String, confirm: bool) -> void:
	await _finish_pending_edits()
	var result: Dictionary = GSTExport.write(_stack, _library, path, confirm)
	if result["needs_confirmation"]:
		_pending_export_path = path
		_overwrite_dialog.dialog_text = "%s already holds a body that differs from this stack's codegen. Overwrite it?" % path
		_overwrite_dialog.popup_centered()
		return
	# Any other outcome resolves the question the dialog was asking (a
	# confirmed write, or a write that turned out not to need confirmation
	# at all): closes it explicitly rather than relying on AcceptDialog's
	# own auto-hide-on-confirmed, which only fires for an actual button
	# press, not a direct confirm=true call (the smoke's own path here).
	if _overwrite_dialog.visible:
		_overwrite_dialog.hide()
	if not result["ok"]:
		_set_operation_message("Export", result["reason"])
		return
	_set_operation_message("Export", "")


func _on_overwrite_confirmed() -> void:
	export_to_path(_pending_export_path, true)
	_pending_export_path = ""


func _on_reopen_shader_pressed() -> void:
	if is_picker_open() and not _applying_choice:
		return
	_reopen_shader_dialog.popup_centered_ratio()


func _on_reopen_shader_file_selected(path: String) -> void:
	reopen_shader_path(path)


## Reopens a stack from an exported .gdshader's embedded header through
## GSTExport.reopen (decision 8). A refusal (no header, unparsable header, or
## an unknown schema -- B8) shows the reason in the message label and leaves
## the current stack untouched; no new empty stack is offered. On success,
## installs the rebuilt stack via replace_stack (an undoable "Replace stack"
## action, same as New/Open) with an empty _current_path (a reopened stack has
## no .tres of its own). When the file's body differs from a fresh codegen of
## its own header
## (decision 8's stale-body warning), that is shown instead of the plain
## success clear. This is the Reopen Shader button's own file-selected
## handler; public so the smoke can drive it directly too.
func reopen_shader_path(path: String) -> void:
	if is_picker_open() and not _applying_choice:
		return
	var result: Dictionary = GSTExport.reopen(path, _library)
	if not result["ok"]:
		_set_operation_message("Reopen Shader", result["reason"])
		return
	replace_stack(result["stack"], "", false)
	if result["body_differs"]:
		_set_operation_message("Reopen Shader", "%s reopened: its body differs from a fresh codegen of the header (hand edits detected, decision 8)" % path)
	else:
		_set_operation_message("Reopen Shader", "")


func _on_layer_selected(layer_id: StringName) -> void:
	_inspector_column.edit(layer_id)
	_update_layer_menu()


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


## GSTUndo's on_property_changed callback: fires after every do and undo of
## a native property edit specifically. Deliberately does not touch
## _stack_list, _output_block, or _inspector_column: a property edit never
## changes layer identity, slots, or references, and rebuilding the
## inspector column here would free the very row a live gesture, an open
## native color popup, or a test still holds a reference to (decision
## superseding 20). gst_inspector_column.gd refreshes that one row's own
## displayed value itself, bound by key, alongside this call.
func _on_property_changed() -> void:
	_resync_material()


## _resync_material runs first and always sets _message_label to the current
## codegen error (or "" on success): the screen_uv suggestion below is only
## applied on top of a clean sync, so a real codegen error is never masked
## by it.
func _on_preset_selected(index: int) -> void:
	_set_operation_message("Preview", "")
	var preset_name: String = GSTPreviewPresets.PRESET_NAMES[index]
	_preview.set_preset(preset_name)
	_resync_material()
	if _codegen_message.text.is_empty() and GSTPreviewPresets.suggests_screen_uv(preset_name, _stack.coord_space):
		_set_operation_message("Preview", "Text preview: use screen_uv for coordinates across the screen.")


func _on_image_button_pressed() -> void:
	_file_dialog.popup_centered_ratio()


func _on_preview_image_selected(path: String) -> void:
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
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
	_resync_material()


func _on_return_to_effect_pressed() -> void:
	_preview_layer_id = &""
	_resync_material()


## GSTPreview.target_rect_changed (an editor-window or splitter resize, or a
## preset swap to a differently-sized target). Writes only gst_rect_size
## (B5), never a full GSTMaterialSync.sync() codegen pass, since this can
## fire once per frame during a drag.
func _on_target_rect_changed(size: Vector2) -> void:
	GSTMaterialSync.write_rect_size(_material, size)


func _on_coord_space_selected(index: int) -> void:
	if _syncing_coord_space or is_picker_open():
		return
	_undo.set_coord_space(index as GSTStack.CoordSpace)


func _set_recipe_open(value: bool) -> void:
	_recipe_open = value
	_randomize_button.disabled = not value or is_picker_open()


## Injects the RNG _on_randomize_pressed draws from (docs/PLAN.md Phase 8 fix
## pass 4, item 2): tests/gst_editor_smoke.gd's GST_EDITOR_SMOKE=8 seeds a
## seeded RandomNumberGenerator here so the handler's change set is
## deterministic and comparable against an independently-computed
## expectation, instead of merely differing from the pre-randomize values by
## chance.
## Wired-by: none (editor smoke seam)
func set_randomize_rng(rng: RandomNumberGenerator) -> void:
	_randomize_rng = rng


## Randomizes every slider on the open recipe (decision 16, docs/PLAN.md
## Phase 8 Build item 3): computes the change set with GSTRandomize.randomize,
## then hands it to GSTUndo.apply_randomize (phase 2: previously registered
## directly on the shared EditorUndoRedoManager here, paired with an explicit
## _refresh_inspector do/undo call; GSTUndo's own bound _notify pair now
## covers that refresh the same way it covers every other GSTUndo action).
## `old_changes` mirrors `changes`' shape with each layer's pre-randomize
## values, captured before GSTRandomize.apply(_stack, changes) runs, so
## GSTUndo's undo method can restore them. `unset_params` records which of
## those values were implicit defaults, so undo erases them again instead of
## leaving an explicit default that would change the serialized header. A
## stack with nothing to randomize (GSTRandomize.randomize returns an empty
## Dictionary) registers no action, matching every other no-op guard in this
## file. _randomize_rng, when set via set_randomize_rng, replaces the fresh
## OS-seeded RandomNumberGenerator this handler otherwise draws from.
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
## popup (decision superseding 20): this panel's standalone UndoRedo is no
## longer reachable through the editor's own Edit > Undo/Redo, which only
## drives EditorUndoRedoManager histories. Outside GoShade focus, this leaves
## the event alone so Godot's own scene Undo keeps working unaffected
## (docs/SHADER_TABS_reviewed-plan.md Cross-cutting "Never clear or rewrite
## Godot scene/global history"). Only reachable through the root viewport:
## a focused native color popup's own embedded-Window input never reaches
## here at all (Godot's embedded-subwindow forwarding, scene/main/
## viewport.cpp, claims it first), so gst_inspector_column.gd's own
## color_popup_undo_redo_requested signal (connected in _ready() straight to
## _apply_keyboard_undo_redo) is that case's own separate entry point.
func _handle_undo_redo_shortcut(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or not (key.ctrl_pressed or key.meta_pressed) or key.keycode != KEY_Z:
		return
	if not _owns_undo_focus():
		return
	# Consumed here, before the await below, so a later frame's input pass
	# cannot also see this event as unhandled and let something else act on
	# it too (phase 2 review round 1 fix pass: awaiting first left the event
	# unhandled for as long as finish_pending_edits() itself yielded).
	get_viewport().set_input_as_handled()
	await _apply_keyboard_undo_redo(key.shift_pressed)


## Finishes any pending native edit, then undoes (or redoes, if `redo`) this
## panel's own standalone UndoRedo -- the shared body behind both keyboard
## Undo/Redo entry points: _handle_undo_redo_shortcut above (a real Ctrl+Z/
## Ctrl+Shift+Z reaching the root viewport's own _input()) and
## gst_inspector_column.gd's color_popup_undo_redo_requested signal (the
## same keys reaching a focused native color popup's own embedded Window
## instead, forwarded here since the root viewport never sees them).
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


func _close_picker() -> void:
	if not is_picker_open():
		return
	var context: Dictionary = _picker_context
	_picker_context = {}
	_picker.hide()
	_set_picker_modality(false)
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
				replace_stack(loaded["stack"], "", true)
	_applying_choice = false
	if not result["ok"]:
		_picker_refusal(result["reason"])
		return
	_picker_refusal("")
	_close_picker()


func _set_operation_message(control: String, reason: String) -> void:
	var key: String = "file:" + control
	if reason.is_empty():
		_control_refusals.erase(key)
	else:
		_control_refusals[key] = reason
	var lines: Array[String] = []
	for name: String in _control_refusals:
		if name.begins_with("file:"):
			lines.append("%s: %s" % [name.trim_prefix("file:"), _control_refusals[name]])
	_message_label.text = "\n".join(lines)
	_message_label.visible = not lines.is_empty()
