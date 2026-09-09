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
## Phase 5 material sync (decision 7, GSTMaterialSync) resyncs on five
## triggers: (1) stack_changed, self-connected here, covering every GSTUndo
## structural edit plus any caller-forced re-emission; (2)
## gst_inspector_column.gd's param_edited signal, the direct relay of a real
## EditorInspector-driven property edit (a slider via EditorInspector's own
## property_edited, or a GSTCoordBlock field via GSTCoordBlock.changed) --
## decision 20's "slider edits come free from the inspector" never goes
## through GSTUndo at all, so this relay is the only path such an edit
## reaches the preview (fix pass 2, item 1: the shared
## EditorUndoRedoManager history's version_changed signal alone is not
## sufficient here, since a real inspector-driven create_action() call binds
## to whatever object the editor's undo manager currently treats as context,
## not necessarily this stack's own history bucket -- only a
## GSTUndo-authored action or a caller that explicitly passes
## custom_context = the stack is guaranteed to land there); (3) that same
## version_changed signal, kept for undo/redo replay of a property edit,
## which sets the value straight through Object.set() and fires neither
## property_edited nor Resource.changed; (4) layer selection while the solo
## toggle is on; (5) a preset or preview-image change. A sixth path,
## GSTPreview.target_rect_changed (an editor-window or splitter resize), does
## not run this full resync: it writes only gst_rect_size via
## GSTMaterialSync.write_rect_size, since it can fire once per frame during a
## drag (B5).

signal stack_changed

@onready var _stack_list: GSTStackList = %StackList
@onready var _output_block: GSTOutputBlock = %OutputBlock
@onready var _inspector_column: GSTInspectorColumn = %InspectorColumn
@onready var _message_label: Label = %MessageLabel
@onready var _preview: GSTPreview = %Preview
@onready var _preset_option: OptionButton = %PresetOption
@onready var _image_button: Button = %ImageButton
@onready var _solo_check: CheckButton = %SoloCheck
@onready var _coord_space_option: OptionButton = %CoordSpaceOption
@onready var _save_button: Button = %SaveButton
@onready var _export_button: Button = %ExportButton
@onready var _recipes_button: MenuButton = %RecipesButton
@onready var _randomize_button: Button = %RandomizeButton
@onready var _file_menu: MenuButton = %FileMenu
@onready var _main_split: HSplitContainer = %MainSplit
@onready var _editing_area: VBoxContainer = %EditingArea
@onready var _editing_split: HSplitContainer = %EditingSplit
@onready var _editing_tabs: TabContainer = %EditingTabs
@onready var _layer_pane: VBoxContainer = %LayerPane
@onready var _settings_pane: VBoxContainer = %SettingsPane
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
var _undo_redo: EditorUndoRedoManager = null
var _undo: GSTUndo = null
## A dedicated, never-persisted, never-installed Resource used only as
## EditorUndoRedoManager's custom_context for "Replace stack" actions and for
## resolving the watched history (docs/PLAN.md Phase 7 finding): a GSTStack
## loaded from a real res:// path -- as GSTStackIO.load produces for Open,
## Reopen Shader, and open_recipe -- routes to a different
## EditorUndoRedoManager history bucket than a bare, path-less
## GSTStack.new() does on 4.6.2 (empirically verified: chaining
## open_recipe -> New -> build -> undo-to-end -> redo-to-end left the panel's
## material on the prior recipe's codegen, because the New action's
## custom_context was old_stack, the just-loaded path-bearing recipe stack,
## which landed outside the bucket _get_history() resolved and drove). This
## anchor is always a bare, path-less Resource, so replace_stack's own action
## and _get_history()'s lookup both stay in the one shared bucket regardless
## of what was opened in between.
var _history_context: Resource = Resource.new()
var _material: ShaderMaterial = ShaderMaterial.new()
var _watched_history: UndoRedo = null
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


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = PREVIEW_IMAGE_MINIMUM
	_tab_breakpoint = _measure_tab_breakpoint()
	_main_split.dragged.connect(_on_main_split_dragged)
	_main_split.resized.connect(_on_editing_area_resized)
	_editing_split.dragged.connect(_on_inner_split_dragged)
	_editing_area.resized.connect(_on_editing_area_resized)
	resized.connect(_on_editing_area_resized)
	_editing_tabs.tab_changed.connect(_on_editing_tab_changed)
	_inspector_column.section_state_changed.connect(_on_section_state_changed)
	_library = GSTLibrary.new()
	_library.scan()
	_stack = GSTStack.new()
	_stack_list.layer_selected.connect(_on_layer_selected)
	_stack_list.structural_edit_refused.connect(_on_refused)
	_inspector_column.edit_refused.connect(_on_refused)
	_inspector_column.param_edited.connect(_on_param_edited)
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
	# by then the shader already carries real code. _install_stack() (called by
	# set_undo_redo_manager right after this node enters the tree) resyncs
	# again once the stack is actually editable, so no further call is needed
	# here.
	_resync_material()
	_preview.set_shader_material(_material)
	_preview.target_rect_changed.connect(_on_target_rect_changed)

	for preset_name: String in GSTPreviewPresets.PRESET_NAMES:
		_preset_option.add_item(preset_name)
	_preset_option.item_selected.connect(_on_preset_selected)
	_image_button.pressed.connect(_on_image_button_pressed)
	_solo_check.toggled.connect(_on_solo_toggled)

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

	_refresh_recipes_menu()
	_recipes_button.get_popup().index_pressed.connect(_on_recipe_index_pressed)
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
	_apply_default_layout.call_deferred()


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
	if not _narrow_layout:
		_tab_breakpoint = _measure_tab_breakpoint()
	var main_available: float = maxf(0.0, _main_split.size.x - float(_main_split.get_theme_constant("separation")))
	var width: float = minf(_editing_area.size.x, main_available * _current_main_ratio())
	var should_narrow: bool = width <= _tab_breakpoint + 0.5
	if should_narrow == _narrow_layout:
		return
	_narrow_layout = should_narrow
	if _narrow_layout:
		_layer_pane.reparent(_editing_tabs)
		_settings_pane.reparent(_editing_tabs)
		_editing_split.hide()
		_editing_tabs.show()
		_editing_tabs.set_tab_title(0, "Layers")
		_editing_tabs.set_tab_title(1, "Layer settings")
		_editing_tabs.current_tab = _preferred_narrow_tab
	else:
		_layer_pane.reparent(_editing_split)
		_settings_pane.reparent(_editing_split)
		_layer_pane.show()
		_settings_pane.show()
		_editing_tabs.hide()
		_editing_split.show()
		_apply_inner_ratio.call_deferred(_metadata_float("inner_ratio", DEFAULT_INNER_RATIO))
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
## EditorUndoRedoManager is only reachable through the EditorPlugin, not a
## plain Control). Installs the initial, never-saved stack with no undo action
## registered around it: there is nothing before the first stack to undo back
## to.
func set_undo_redo_manager(undo_redo: EditorUndoRedoManager) -> void:
	_undo_redo = undo_redo
	_install_stack(_stack, GSTUndo.new(_undo_redo, _stack, _library, _on_stack_changed, _history_context))


## Wires the stack-list/output-block/inspector columns, the watched undo
## history, and the coord-space dropdown to `stack`/`undo`, and resyncs the
## material. This is the do/undo primitive for a stack replacement (phase 6
## fix pass 2, item 1; docs/PLAN.md Cross-cutting "EditorUndoRedoManager
## integration"): replace_stack below registers this method as both the do
## and the undo method of a "Replace stack" EditorUndoRedoManager action
## (alongside a second do/undo pair for _current_path), so undo reinstalls the
## exact previous GSTStack instance and its previous GSTUndo instance -- not a
## freshly constructed one -- and every action already recorded through that
## GSTUndo's own add_do_method(self, ...) bindings keeps landing on the
## GSTStack/GSTLayer instances it actually closed over. Also called directly,
## with no action registered, by set_undo_redo_manager for the very first
## stack.
func _install_stack(stack: GSTStack, undo: GSTUndo) -> void:
	_stack = stack
	_undo = undo
	_stack_list.setup(_stack, _library, _undo)
	_output_block.setup(_stack, _library, _undo)
	_inspector_column.setup(_stack, _library, _undo)
	_rewatch_history()
	_syncing_coord_space = true
	_coord_space_option.select(int(_stack.coord_space))
	_syncing_coord_space = false
	_resync_material()


func _raw_set_current_path(path: String) -> void:
	_current_path = path


func _notify_replace() -> void:
	stack_changed.emit()


## Wired-by: none (editor smoke seam)
func get_stack() -> GSTStack:
	return _stack


## Installs new_stack (and new_path as the new _current_path, and
## new_recipe_open as the new _recipe_open) as an undoable "Replace stack"
## action in the shared editor history, rather than mutating
## _stack/_current_path/_recipe_open directly: a structural edit made before
## New, Open, or Reopen Shader now stays undoable afterward instead of being
## discarded along with the replaced GSTStack (docs/PLAN.md Cross-cutting
## "EditorUndoRedoManager integration", phase 6 fix pass 2 item 1). The
## recipe-open flag (decision 16's Randomize gate) is recorded and replayed
## the same way: undoing a New/Open/Reopen that closed an open recipe
## re-enables Randomize, and redoing it disables it again (fix pass 3, item
## 3). custom_context is _history_context, the panel's path-less anchor
## Resource: on 4.6.2, get_object_history_id routes a Resource with a res://
## path to a different history than a path-less one (verified:
## tests/gst_editor_smoke.gd phase 7 run 2), so the stack instance is never
## used as context. _on_new_pressed, open_path, open_recipe, and
## reopen_shader_path call this instead of mutating
## _stack/_current_path/_recipe_open directly.
func replace_stack(new_stack: GSTStack, new_path: String, new_recipe_open: bool) -> void:
	var old_stack: GSTStack = _stack
	var old_undo: GSTUndo = _undo
	var old_path: String = _current_path
	var old_recipe_open: bool = _recipe_open
	var new_undo: GSTUndo = GSTUndo.new(_undo_redo, new_stack, _library, _on_stack_changed, _history_context)
	_install_stack(new_stack, new_undo)
	_raw_set_current_path(new_path)
	_set_recipe_open(new_recipe_open)
	_undo_redo.create_action("GST: Replace stack", UndoRedo.MERGE_DISABLE, _history_context)
	_undo_redo.add_do_method(self, "_install_stack", new_stack, new_undo)
	_undo_redo.add_undo_method(self, "_install_stack", old_stack, old_undo)
	_undo_redo.add_do_method(self, "_raw_set_current_path", new_path)
	_undo_redo.add_undo_method(self, "_raw_set_current_path", old_path)
	_undo_redo.add_do_method(self, "_set_recipe_open", new_recipe_open)
	_undo_redo.add_undo_method(self, "_set_recipe_open", old_recipe_open)
	_undo_redo.add_do_method(self, "_notify_replace")
	_undo_redo.add_undo_method(self, "_notify_replace")
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
func get_solo_check() -> CheckButton:
	return _solo_check


## Wired-by: none (editor smoke seam)
func get_message_label() -> Label:
	return _message_label


## Wired-by: none (editor smoke seam)
func get_randomize_button() -> Button:
	return _randomize_button


## The UndoRedo bucket _watched_history currently points at (the same one
## _get_history()/_history_context resolve to). Lets the phase 7 smoke drive
## undo()/redo() directly against the exact history this panel watches,
## instead of recomputing a bucket the smoke's own stack argument might not
## share with GSTUndo's actions (docs/PLAN.md Cross-cutting
## "EditorUndoRedoManager integration", "History anchor (phase 7)").
## Wired-by: none (editor smoke seam)
func get_watched_history() -> UndoRedo:
	return _watched_history


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
	replace_stack(GSTStack.new(), "", false)
	_message_label.text = ""


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
	var result: Dictionary = GSTStackIO.load(path, _library)
	if not result["ok"]:
		_message_label.text = result["reason"]
		return
	replace_stack(result["stack"], path, false)
	_message_label.text = ""


## Rebuilds the Recipes MenuButton's popup from every .tres under
## RECIPES_DIR, by file name (docs/PLAN.md Phase 7 Files). Called once from
## _ready(); the recipe roster is fixed at edit time in this phase (no
## structural add/remove path adds one during a session), so no further
## refresh trigger exists yet.
func _refresh_recipes_menu() -> void:
	var popup: PopupMenu = _recipes_button.get_popup()
	popup.clear()
	for recipe_name: String in _recipe_names():
		popup.add_item(recipe_name)


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


## PopupMenu.add_item() auto-assigns each item's id equal to its own index
## (no explicit id was ever passed above), so index_pressed's index maps
## directly onto _recipe_names()'s own sorted order without a second lookup.
func _on_recipe_index_pressed(index: int) -> void:
	var names: Array[String] = _recipe_names()
	if index < 0 or index >= names.size():
		return
	open_recipe(names[index])


## Loads RECIPES_DIR/<name>.tres and installs it via replace_stack (decision
## 20: an undoable "Replace stack" action, same as New/Open/Reopen Shader),
## with the new current_path left empty rather than set to the recipe's own
## path: a recipe is a template, so Save falls back to Save As instead of
## silently overwriting the shipped recipe file (docs/PLAN.md Phase 7 Files).
## This is the Recipes menu's own handler; public so
## tests/gst_editor_smoke.gd can drive the same path directly.
func open_recipe(name: String) -> void:
	var path: String = "%s/%s.tres" % [RECIPES_DIR, name]
	var result: Dictionary = GSTStackIO.load(path, _library)
	if not result["ok"]:
		_message_label.text = result["reason"]
		return
	replace_stack(result["stack"], "", true)
	_message_label.text = ""


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
func save_to_path(path: String) -> void:
	var result: Dictionary = GSTStackIO.save(_stack, path)
	if not result["ok"]:
		_message_label.text = result["reason"]
		return
	_current_path = path
	_message_label.text = ""


func _on_export_pressed() -> void:
	_export_dialog.popup_centered_ratio()


func _on_export_file_selected(path: String) -> void:
	export_to_path(path, false)


## Exports the open stack to `path` through GSTExport.write (decision 9: the
## overwrite gate). When the target exists with a differing body and
## `confirm` is false, shows the overwrite confirmation dialog and performs
## no write; confirming it re-calls this with `confirm = true`. This is the
## Export button's file-selected handler and the confirmation dialog's own
## confirmed handler; public so the smoke can drive it directly too.
func export_to_path(path: String, confirm: bool) -> void:
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
		_message_label.text = result["reason"]
		return
	_message_label.text = ""


func _on_overwrite_confirmed() -> void:
	export_to_path(_pending_export_path, true)
	_pending_export_path = ""


func _on_reopen_shader_pressed() -> void:
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
	var result: Dictionary = GSTExport.reopen(path, _library)
	if not result["ok"]:
		_message_label.text = result["reason"]
		return
	replace_stack(result["stack"], "", false)
	if result["body_differs"]:
		_message_label.text = "%s reopened: its body differs from a fresh codegen of the header (hand edits detected, decision 8)" % path
	else:
		_message_label.text = ""


func _on_layer_selected(layer_id: StringName) -> void:
	_inspector_column.edit(layer_id)
	if _solo_check.button_pressed:
		_resync_material()


func _on_refused(reason: String) -> void:
	_message_label.text = reason


## GSTUndo's on_changed callback: fires after every do and undo.
func _on_stack_changed() -> void:
	_stack_list.refresh()
	_output_block.refresh()
	_inspector_column.edit(_stack_list.get_selected_layer_id())
	_syncing_coord_space = true
	_coord_space_option.select(int(_stack.coord_space))
	_syncing_coord_space = false
	stack_changed.emit()


## _resync_material runs first and always sets _message_label to the current
## codegen error (or "" on success): the screen_uv suggestion below is only
## applied on top of a clean sync, so a real codegen error is never masked
## by it.
func _on_preset_selected(index: int) -> void:
	var preset_name: String = GSTPreviewPresets.PRESET_NAMES[index]
	_preview.set_preset(preset_name)
	_resync_material()
	if _message_label.text.is_empty() and GSTPreviewPresets.suggests_screen_uv(preset_name, _stack.coord_space):
		_message_label.text = "text preset: coord space is uv; screen_uv reads more consistently on text (decision 11)"


func _on_image_button_pressed() -> void:
	_file_dialog.popup_centered_ratio()


func _on_preview_image_selected(path: String) -> void:
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		return
	_preview.set_image(texture)
	_resync_material()


func _on_solo_toggled(_pressed: bool) -> void:
	_resync_material()


## GSTPreview.target_rect_changed (an editor-window or splitter resize, or a
## preset swap to a differently-sized target). Writes only gst_rect_size
## (B5), never a full GSTMaterialSync.sync() codegen pass, since this can
## fire once per frame during a drag.
func _on_target_rect_changed(size: Vector2) -> void:
	GSTMaterialSync.write_rect_size(_material, size)


func _on_coord_space_selected(index: int) -> void:
	if _syncing_coord_space:
		return
	_undo.set_coord_space(index as GSTStack.CoordSpace)


func _set_recipe_open(value: bool) -> void:
	_recipe_open = value
	_randomize_button.disabled = not value


## Registered as both the do and undo method of the randomize action,
## alongside GSTRandomize.apply itself (docs/PLAN.md Phase 8 fix pass 2,
## item 1): relays to GSTInspectorColumn.refresh() so the selected layer's
## EditorProperty widgets re-read after apply, undo, and redo alike. Every
## other structural edit already gets this for free from
## _on_stack_changed's own _inspector_column.edit() call; the randomize
## action bypasses GSTUndo/_on_stack_changed entirely, so it needs this
## explicit pair.
func _refresh_inspector() -> void:
	_inspector_column.refresh()


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
## then registers it as one undoable "Randomize sliders" EditorUndoRedoManager
## action whose do/undo methods both call GSTRandomize.apply (fix pass 3,
## item 2: apply is the live change-set writer, not add_do_property/
## add_undo_property directly), each paired with a call to
## _refresh_inspector (fix pass 2, item 1: GSTRandomize.apply's writes are
## external to whatever EditorProperty widgets the inspector column already
## built, so undo and redo of this action must force it to re-read, not only
## the initial apply), with custom_context = _history_context, the
## same anchor every other GST action uses so it lands in the one shared
## watched history. `old_changes` mirrors `changes`' shape with each layer's
## pre-randomize values, captured before GSTRandomize.apply(_stack, changes)
## runs, so the undo method's GSTRandomize.apply(_stack, old_changes) call
## restores them. A stack with nothing to randomize (GSTRandomize.randomize
## returns an empty Dictionary) registers no action, matching every other
## no-op guard in this file. commit_action() (execute = true, the default)
## applies the do method immediately, which runs GSTRandomize.apply and
## _refresh_inspector once, and fires the watched history's version_changed,
## which resyncs the material (_on_history_version_changed) -- no further
## call is needed here (fix pass 4, item 3: the prior explicit
## _resync_material() and _refresh_inspector() calls after commit_action were
## a duplicate of that do-method/signal path, not an additional step).
## _randomize_rng, when set via set_randomize_rng, replaces the fresh
## OS-seeded RandomNumberGenerator this handler otherwise draws from.
func _on_randomize_pressed() -> void:
	var rng: RandomNumberGenerator = _randomize_rng
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var changes: Dictionary = GSTRandomize.randomize(_stack, _library, rng)
	if changes.is_empty():
		return
	var old_changes: Dictionary = {}
	for layer_id: Variant in changes.keys():
		var layer: GSTLayer = GSTStackOps.find_layer(_stack, StringName(layer_id))
		if layer == null:
			continue
		var layer_changes: Dictionary = changes[layer_id]
		var old_layer_changes: Dictionary = {}
		for param_name: Variant in layer_changes.keys():
			old_layer_changes[param_name] = layer.get(StringName(param_name))
		old_changes[layer_id] = old_layer_changes
	_undo_redo.create_action("GST: randomize sliders", UndoRedo.MERGE_DISABLE, _history_context)
	_undo_redo.add_do_method(GSTRandomize, "apply", _stack, changes)
	_undo_redo.add_do_method(self, "_refresh_inspector")
	_undo_redo.add_undo_method(GSTRandomize, "apply", _stack, old_changes)
	_undo_redo.add_undo_method(self, "_refresh_inspector")
	_undo_redo.commit_action()


## The shared EditorUndoRedoManager history for _stack (same one GSTUndo's
## _create_action commits to). version_changed on this history catches undo
## and redo of a GSTUndo-authored structural action (stack_changed already
## covers its initial do) and, when one lands here, undo/redo of an
## inspector-driven property edit too: Object.set() during undo/redo fires
## neither EditorInspector.property_edited nor Resource.changed, so
## gst_inspector_column.gd's param_edited relay (the live-edit path) cannot
## see it, and this is the only remaining hook for that case (fix pass 2,
## item 1).
func _get_history() -> UndoRedo:
	if _undo_redo == null:
		return null
	var history_id: int = _undo_redo.get_object_history_id(_history_context)
	return _undo_redo.get_history_undo_redo(history_id)


func _rewatch_history() -> void:
	if _watched_history != null and _watched_history.version_changed.is_connected(_on_history_version_changed):
		_watched_history.version_changed.disconnect(_on_history_version_changed)
	_watched_history = _get_history()
	if _watched_history != null:
		_watched_history.version_changed.connect(_on_history_version_changed)


func _on_history_version_changed() -> void:
	_resync_material()


## gst_inspector_column.gd's param_edited relay (fix pass 2, item 1): the
## direct path for a real, live EditorInspector-driven edit, independent of
## which EditorUndoRedoManager history bucket its create_action() call landed
## in.
func _on_param_edited(_property: String) -> void:
	_resync_material()


## Solo (decision 13) previews the selected layer instead of the stack's own
## output, without mutating the stack; the codegen error, if any, keeps the
## last good material and shows in the message label (GSTMaterialSync never
## touches the material on a failed sync).
func _resync_material() -> void:
	if _stack == null or _library == null or _preview == null or _material == null:
		return
	var solo_id: StringName = _stack_list.get_selected_layer_id() if _solo_check.button_pressed else &""
	var rect_size: Vector2 = _preview.get_target_rect_size()
	var result: GSTCodegenResult = GSTMaterialSync.sync(_stack, _library, _material, solo_id, rect_size)
	_message_label.text = result.error
