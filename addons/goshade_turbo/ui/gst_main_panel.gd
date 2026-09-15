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
@onready var _shader_tab_row: HBoxContainer = %ShaderTabRow
@onready var _shader_tabs: TabBar = %ShaderTabs
@onready var _new_tab_button: Button = %NewTabButton

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
## Every open GSTDocument (phase 3, docs/SHADER_TABS_reviewed-plan.md), in
## creation order. _close_document_now is the only pruner (_documents.remove_at).
var _documents: Array[GSTDocument] = []
## The document currently bound to the shared UI (stack list, inspector
## column, output block, coord-space dropdown, preview). Changed by
## New/Open/Reopen Shader/Recipes, %ShaderTabs's own tab_changed handler
## (_on_tab_bar_tab_changed, 2026-09-15 TabBar pass), and the internal
## fixture seams below.
var _active_document: GSTDocument = null
## Mirrors _active_document.undo_redo/.undo so every existing call site in
## this file (get_watched_history(), get_undo(), keyboard undo/redo, every
## _undo.* call) keeps reading the active document's own history without
## rebinding each one individually (Cross-cutting "Rebind panel callers to
## the active document"). Kept in sync exclusively by _install_stack/
## _activate_document.
var _undo_redo: UndoRedo = null
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
## Phase 6 (docs/SHADER_TABS_reviewed-plan.md): Save/Discard/Cancel prompt for
## closing a dirty document (decision 9). ok_button_text is overridden to
## "Save"; the constructor's own Cancel button is kept as-is; a third
## "Discard" button is added via add_button (native AcceptDialog API), which
## never auto-hides the dialog on press (dialogs.cpp AcceptDialog::
## _custom_action never calls hide()) -- _on_close_custom_action hides it
## explicitly.
var _close_dialog: ConfirmationDialog = null
var _close_discard_button: Button = null

## Phase 5 (docs/SHADER_TABS_reviewed-plan.md): "capture stable document ID
## and request identity for Save As, Export, overwrite confirmation,
## preview-image selection, and delayed open/reopen requests." Each of the
## six *_pending_* Dictionaries below is either `{}` (no request captured --
## the dialog-opening "_pressed" handler that captures one was never called,
## exactly the case when a test drives save_to_path/export_to_path/open_path/
## reopen_shader_path or the *_file_selected/_on_overwrite_confirmed seams
## directly without popping the real dialog first, e.g.
## tests/gst_editor_smoke.gd items 2 and 4-9, tests/gst_editor_documents_smoke.gd,
## tests/gst_editor_native_undo_smoke.gd, tests/gst_editor_tabs_smoke.gd) or
## `{"request_id": int, "doc_id": int}` (captured when the dialog opened, or,
## for `_pending_overwrite`, when _export_stack_to_path first found it needs
## confirmation). `request_id` is a monotonic stamp from
## _next_file_request_id, unique per capture, for diagnosability; resolution
## itself only depends on `doc_id` still resolving through
## _find_document_by_session_id (Cross-cutting "resolve every response
## against its pending request and owning document; reject closed/stale
## targets without touching another document") -- _resolve_pending_document
## below is the one place that reads any of these back.
var _next_file_request_id: int = 0
var _pending_save_as: Dictionary = {}
var _pending_export: Dictionary = {}
## Also carries "path": the export target this confirmation answers, taking
## over _pending_export_path's old job.
var _pending_overwrite: Dictionary = {}
var _pending_open: Dictionary = {}
var _pending_reopen: Dictionary = {}
var _pending_image: Dictionary = {}
## Phase 6: captures the document a close request's own Save/Discard/Cancel
## prompt is asking about, the same shape as every *_pending_* Dictionary
## above -- so a stale response (the document closed some other way while the
## prompt was up) resolves to null through _resolve_pending_document instead
## of acting on whatever document happens to be active when the dialog
## answers.
var _pending_close: Dictionary = {}

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
## Tab index -> GSTDocument.session_id, rebuilt wholesale by _refresh_tabs()
## every time it runs (matching gst_stack_list.gd's own full-rebuild-per-
## change convention), 1:1 with %ShaderTabs's own tabs (index i here is
## always tab i). tab_changed/tab_close_pressed resolve back to a document
## through this array plus _find_document_by_session_id, the same stable-id
## pattern every other pending/deferred response in this file already uses,
## rather than trusting a raw tab index alone to still mean the same document
## by the time a signal actually reaches its handler.
var _tab_session_ids: Array[int] = []
## Guards %ShaderTabs.current_tab writes made to reflect _active_document
## (2026-09-15 TabBar pass): TabBar.set_current_tab() emits tab_changed
## whenever the index actually moves, so a programmatic write in
## _refresh_tabs() must not re-enter _on_tab_bar_tab_changed's own
## activate_document call (mirrors _syncing_coord_space's own guard for the
## same reason).
var _syncing_tabs: bool = false
## Guards _preset_option.select() calls made to reflect a newly activated
## document's own stored preview_preset (mirrors _syncing_coord_space's own
## guard for the same reason: OptionButton.select() does not itself emit
## item_selected, but the guard is kept for the same defensive parity).
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
	# Phase 5: an explicit Cancel/Escape must not leave a captured request
	# sitting around for some later, unrelated resolution of the same dialog
	# to pick up (a real dialog only ever fires file_selected once per open,
	# but a canceled one still shows "canceled" here to keep every one of
	# these six dialogs' own pending capture symmetrical and easy to reason
	# about). set_visible(false)/hide() alone does not emit this (only the
	# Cancel button/Esc path does, dialogs.cpp AcceptDialog::_cancel_pressed);
	# a caller that force-hides a dialog directly (e.g. hide_export_dialog())
	# clears its own pending capture itself if it needs to.
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

	_new_tab_button.pressed.connect(_on_new_pressed)
	# 2026-09-15 TabBar pass: tab_changed only fires when %ShaderTabs's own
	# current_tab index actually moves (TabBar.set_current_tab, tab_bar.cpp),
	# so a reclick on the already-active tab is already a no-op at the engine
	# level -- no ButtonGroup/toggle bookkeeping needed the way the old
	# per-tab Button row required. tab_close_pressed fires on the close icon
	# specifically (tab_bar.cpp's own cb_rect hit-test), independent of
	# tab_changed/tab_clicked.
	_shader_tabs.tab_changed.connect(_on_tab_bar_tab_changed)
	_shader_tabs.tab_close_pressed.connect(_on_tab_bar_close_pressed)
	# Phase 4 Cross-cutting "Explicitly control GSTPreview update mode...":
	# pauses the shared preview SubViewport while the GoShade main-screen tab
	# is hidden (plugin.gd's _make_visible(false)) and resumes it when shown
	# again. Fires once immediately below too, since plugin.gd calls
	# _panel.hide() right after this node's own _ready() already ran.
	visibility_changed.connect(_on_panel_visibility_changed)
	# Round 1 fix 3 (Button-row era) / 2026-09-15 TabBar pass: %ShaderTabs's
	# own ensure_tab_visible() call in _refresh_tabs() only re-fires when the
	# tab row itself is rebuilt (a document/stack change). A resize alone
	# (main window, editor-scale, or the narrow-layout breakpoint toggling)
	# can shrink %ShaderTabs without rebuilding anything, which could
	# otherwise leave the still-correct active tab scrolled out of view. The
	# tab row spans the whole panel width regardless of the main split, so
	# %ShaderTabs's own resized signal covers every one of those cases
	# directly.
	_shader_tabs.resized.connect(_on_tab_scroll_resized)
	# 2026-09-15 tab-row-width pass: %ShaderTabs no longer stretches across
	# ShaderTabRow (size_flags_horizontal is now SIZE_SHRINK_BEGIN,
	# gst_main_panel.tscn), so its own width is driven entirely by
	# custom_minimum_size.x, recomputed by _apply_tab_bar_width() whenever
	# either side of that calculation can change: the row's own available
	# width (this resize) or the tab content itself (_refresh_tabs()).
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

	# Phase 6: Save/Discard/Cancel prompt for closing a dirty document
	# (decision 9). confirmed (the native OK button, relabeled "Save") and
	# canceled (the native Cancel button, unchanged) are AcceptDialog's own
	# signals; "Discard" is a third button added via add_button, whose own
	# press never auto-hides the dialog (dialogs.cpp AcceptDialog::
	# _custom_action), so _on_close_custom_action hides it explicitly.
	_close_dialog = ConfirmationDialog.new()
	_close_dialog.ok_button_text = "Save"
	_close_discard_button = _close_dialog.add_button("Discard", true, "discard")
	_close_dialog.confirmed.connect(_on_close_save_requested)
	_close_dialog.canceled.connect(func() -> void: _pending_close = {})
	_close_dialog.custom_action.connect(_on_close_custom_action)
	add_child(_close_dialog)
	_build_start_screen()
	_apply_default_layout.call_deferred()

	# Installs the initial, never-saved document with no undo action
	# registered around it: there is nothing before the first document to
	# undo back to. Previously called externally by plugin.gd once it had a
	# real EditorUndoRedoManager to hand over (decision 20); phase 2 gave this
	# panel its own standalone UndoRedo directly; phase 3 moves that
	# ownership onto the first GSTDocument instead, created the same way
	# open_document creates every later one.
	_activate_document(_create_document(_stack, "", false))
	# Phase 7 (docs/SHADER_TABS_reviewed-plan.md): reopen any dirty document a
	# prior confirmed-quit save_external_data() call recovered, before the
	# user ever sees this bootstrap document's own start screen (Cross-
	# cutting "restoration occurs before entry"). A project with no recovery
	# records is the overwhelmingly common case and this call is a no-op for
	# it: GSTDocumentRecovery.load_all() on a missing index.json returns no
	# records and no failures.
	load_recovery_records()


## Releases every open document's own UndoRedo (an Object, not a RefCounted
## or a Node: it has no owner to free it automatically) and its GSTUndo
## adapter, which retains bound Callables closing over this panel and that
## document, when the panel itself leaves the tree (phase 2 review round 2
## fix pass; phase 3 extends it from the one panel-owned UndoRedo to every
## open document's own instance, active or not -- an inactive document was
## never reachable through _undo_redo alone).
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


## Sizes %ShaderTabs to its own tab content instead of stretching across
## ShaderTabRow (2026-09-15 tab-row-width pass). %ShaderTabs's own
## size_flags_horizontal is SIZE_SHRINK_BEGIN (gst_main_panel.tscn), so
## HBoxContainer gives it exactly its combined minimum size; clip_tabs stays
## true (gst_main_panel.tscn), which forces TabBar::get_minimum_size() to
## report 0 regardless of tab content (tab_bar.cpp:103-105), so that combined
## minimum size is entirely custom_minimum_size.x, written here. Bounded to
## the row's own available width minus %NewTabButton and the row's own
## separation: %NewTabButton sits immediately after the last tab when every
## tab fits, and stays pinned at the row's own right edge, with %ShaderTabs
## scrolling its own content internally, once they do not -- matching
## Godot's own scene tab strip. Called from _refresh_tabs() (tab count/
## content changed) and _on_tab_row_resized (row width changed, e.g. a window
## resize) -- the only two things either side of this calculation depends on.
func _apply_tab_bar_width() -> void:
	if _shader_tab_row == null or _shader_tabs == null or _new_tab_button == null:
		return
	var content_width: float = _measure_tab_bar_content_width()
	var separation: float = float(_shader_tab_row.get_theme_constant("separation"))
	var available: float = maxf(0.0, _shader_tab_row.size.x - _new_tab_button.size.x - separation)
	_shader_tabs.custom_minimum_size.x = minf(content_width, available)


## %ShaderTabs's own true, unclipped tab content width. TabBar::
## get_minimum_size (tab_bar.cpp) sums every tab's real styled width and only
## zeroes the result at the very end when clip_tabs is true (:103-105), so
## toggling clip_tabs off for one synchronous read recovers that sum without
## needing a separate per-tab-rect loop; clip_tabs is restored to true
## immediately after, since that is also what keeps %ShaderTabs's own native
## overflow scroll arrows available for the many-tabs case
## _apply_tab_bar_width's own available-width clamp produces.
func _measure_tab_bar_content_width() -> float:
	_shader_tabs.clip_tabs = false
	var width: float = _shader_tabs.get_minimum_size().x
	_shader_tabs.clip_tabs = true
	return width


## FileMenu draws as a flat MenuButton by construction regardless of its own
## flat property (MenuButton::MenuButton calls set_flat(true) unconditionally,
## confirmed .now/tabs-validation/godot-4.4-source/scene/gui/menu_button.cpp:
## 217): gst_main_panel.tscn's flat = false ("Tab row and toolbar layout
## 2026-09-15" pass) has no visible effect on its own, since the editor theme
## still supplies MenuButton's own distinct styleboxes under the "MenuButton"
## theme type independent of the flat property. Copying Button's own
## styleboxes/font colors onto %FileMenu as per-instance overrides makes it
## draw identically to %SaveButton/%RecipesButton/%RandomizeButton/
## %ExportButton (all plain Buttons, "Button" theme type) without touching
## flatness, get_popup(), or any popup-id wiring. has_theme_stylebox/
## has_theme_color gate each copy so a theme that omits one name (e.g. no
## hover_pressed) leaves %FileMenu's own default for it untouched rather than
## overriding with a missing resource.
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


## Rebinds the stack-list/output-block/inspector columns and the
## coord-space dropdown to `stack`/`undo`, and resyncs the material. This is
## the do/undo primitive for an in-place stack replacement (phase 6 fix pass
## 2, item 1; phase 3 keeps it as replace_stack's own internal fixture-only
## primitive): replace_stack below registers this method as both the do and
## the undo method of a "Replace stack" UndoRedo action on the active
## document's own history (alongside a second do/undo pair for
## _current_path), so undo reinstalls the exact previous GSTStack instance
## and its previous GSTUndo instance -- not a freshly constructed one -- and
## every action already recorded through that GSTUndo's own bound-Callable
## methods keeps landing on the GSTStack/GSTLayer instances it actually
## closed over. Writes stack/undo onto _active_document too, so this stays
## the one place document ownership and the shared UI mirrors ever diverge
## (phase 3: New/Open/Reopen/Recipes create and activate a whole new
## GSTDocument instead of calling this directly; see open_document/
## _activate_document below). Does not touch preview_sync/material/
## preview_layer_id: those are document-scoped state _activate_document
## installs once per document, not once per raw stack swap.
func _install_stack(stack: GSTStack, undo: GSTUndo) -> void:
	_picker.set_refusal("")
	_control_refusals.clear()
	# Phase 5: file-operation messages are now per-document
	# (GSTDocument.operation_messages), so this rebuilds the shared label
	# from whichever document is _active_document right now -- already the
	# incoming one by the time this runs, since _activate_document sets
	# _active_document before calling _install_document_state/_install_stack
	# -- instead of unconditionally blanking it.
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


## Wraps _install_stack with this panel's own preview material/diagnostic
## state (phase 3): _install_stack's own internal _resync_material() call
## must already see the right preview_sync/material/preview_layer_id before
## it runs, so this sets those mirrors (and _active_document's matching
## fields) first, then calls _install_stack, as a single atomic do/undo
## primitive -- registering them as two separate UndoRedo methods would
## replay in the wrong relative order on undo (UndoRedo replays undo
## methods in reverse registration order). Kept separate from _install_stack
## itself so tests/gst_editor_ui_picker_smoke.gd's own "Bypass guarded UI
## only to simulate a stale installation" fixture can keep calling
## _install_stack(stack, undo) directly to swap only stack/undo in place,
## without touching preview material state at all (that fixture proves
## picker-context staleness, not rendering).
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
## replace_stack's own "Replace stack" action (phase 3 fix pass 1, round 1):
## always writes doc's own fields regardless of which document is active,
## and only touches the shared UI/panel mirrors when doc is still the
## active one. Without this, replaying replace_stack's do/undo methods for
## an inactive doc (a stale callback, or a test driving that document's own
## history directly) would overwrite whichever *other* document happens to
## be active right now, since the un-scoped _install_document_state always
## writes _active_document unconditionally.
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


## Document-bound path setter, shared by replace_stack's own action (same
## isolation reason as _install_document_state_for above) and
## _save_stack_to_path's successful-write branch (:1620), which reuses this
## instead of re-writing its two lines inline.
func _raw_set_current_path_for(doc: GSTDocument, path: String) -> void:
	doc.current_path = path
	if doc == _active_document:
		_current_path = path


## Document-bound counterpart of _set_recipe_open, used only by
## replace_stack's own action (same isolation reason as
## _install_document_state_for above).
func _set_recipe_open_for(doc: GSTDocument, value: bool) -> void:
	doc.recipe_open = value
	if doc != _active_document:
		return
	_recipe_open = value
	_randomize_button.disabled = not value or is_picker_open()


## Document-bound counterpart of _notify_replace, used only by
## replace_stack's own action: an inactive document's own replay must never
## announce stack_changed for content the shared UI is not currently
## showing.
func _notify_replace_for(doc: GSTDocument) -> void:
	if doc == _active_document:
		_notify_replace()


## Builds a new GSTDocument for new_stack, appends it to _documents, and
## returns it without activating it (bootstrap primitive shared by _ready()'s
## very first document and open_document's later ones). GSTUndo's on_changed/
## on_property_changed callbacks are bound to this document (Callable.bind),
## so a later replay -- while this document is active or not -- always
## resolves the document it actually belongs to (Cross-cutting "Public APIs,
## signals, and callbacks": "capture the owning document in action
## callbacks"). new_recipe_name/new_reopened_import retain the recipe/import
## origin (phase 3 fix pass 1, round 1) so phase 4 can display it; passing
## either marks the document dirty on setup instead of clean (GSTDocument.
## setup's starts_dirty), since unsaved recipe/import content has no saved
## baseline of its own to mark.
func _create_document(new_stack: GSTStack, new_path: String, new_recipe_open: bool, new_recipe_name: String = "", new_reopened_import: bool = false) -> GSTDocument:
	var doc: GSTDocument = GSTDocument.new()
	doc.current_path = new_path
	doc.recipe_open = new_recipe_open
	doc.recipe_name = new_recipe_name
	doc.reopened_import = new_reopened_import
	doc.setup(new_stack, _library, _on_document_stack_changed.bind(doc), _on_document_property_changed.bind(doc), new_recipe_open or new_reopened_import)
	_documents.append(doc)
	return doc


## GSTUndo's on_changed callback for a document-owned action (phase 3):
## every structural/coord-space/Randomize action on any document, active or
## not, calls this bound to its own owning document. Only the active
## document's replay may touch the shared UI: an inactive document's own
## undo/redo (e.g. a stale callback, or a test driving it directly) must
## never rebuild _stack_list/_inspector_column/_output_block against a stack
## they are not currently bound to (Cross-cutting: "Inactive histories must
## survive switching without calling active-panel mutation callbacks against
## the wrong stack").
func _on_document_stack_changed(doc: GSTDocument) -> void:
	if doc != _active_document:
		return
	_on_stack_changed()


## Same isolation as _on_document_stack_changed, for a native property
## edit's lighter on_property_changed callback.
func _on_document_property_changed(doc: GSTDocument) -> void:
	if doc != _active_document:
		return
	_on_property_changed()


## Points the shared UI at doc: mirrors its stack/undo/current_path/
## recipe_open/preview material/diagnostic state into this panel's own
## fields, then calls _install_stack to rebind the stack list, inspector
## column, output block, and coord-space dropdown. Registers no undo action
## anywhere (decision superseding 20, phase 3): switching which open
## document the UI shows is navigation, not a stack edit, and must never
## appear in any document's own history -- an inactive document's history
## survives switching untouched because its UndoRedo instance is simply not
## the one _undo_redo/get_watched_history() point callers at right now. Does
## not touch the start screen: _ready()'s own bootstrap activation of the
## very first document must never dismiss a start screen that has not been
## shown yet; activate_document/open_document below dismiss it themselves.
func _activate_document(doc: GSTDocument) -> void:
	# Captured from the still-installed previous document's own rows/scroll
	# state before anything below rebinds the stack list to doc's stack
	# (phase 4: "restore stable-ID layer selection and list position"). Only
	# the previous document's own selected_layer_id is already kept live via
	# _on_layer_selected; scroll position has no per-scroll signal to hook,
	# so it is captured here, at the one point every switch passes through.
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


## Restores doc's own stable-ID layer selection and list scroll position
## (phase 4) after _install_stack above has already rebuilt _stack_list's
## rows for doc.stack. Clears any selection _install_stack's own refresh()
## carried over by coincidence (a stale pre-clear selected_id in the old
## list happening to match an id that also exists in doc's own stack) before
## applying doc's real remembered selection, so a switch never leaves the
## wrong row highlighted or the inspector column pointed at the wrong layer.
func _restore_document_selection(doc: GSTDocument) -> void:
	_stack_list.clear_selection()
	if doc.selected_layer_id != &"" and GSTStackOps.find_layer(_stack, doc.selected_layer_id) != null:
		_stack_list.select_layer(doc.selected_layer_id)
	else:
		doc.selected_layer_id = &""
		_inspector_column.edit(&"")
	_update_layer_menu()
	_stack_list.restore_scroll_state(doc.list_scroll_anchor_id, doc.list_scroll_offset)


## Restores doc's own stored preview preset/image (phase 4: solo/diagnostic
## state -- preview_layer_id -- is already restored by _install_document_state
## above, which is called before this). "" preview_preset/preview_image_path
## means doc never changed them away from the shipped defaults (a pristine
## New document, or one never touched from this panel's own current-session
## preset/image controls), so both fall back to their _ready()-time defaults
## instead of leaking whatever another document last selected.
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


## Rebuilds %ShaderTabs (a native TabBar, 2026-09-15 pass) from _documents
## (phase 4), matching gst_stack_list.gd's own full-rebuild-per-change
## convention rather than patching individual tabs in place. Called after
## every activation/creation (_activate_document) and every active-document
## stack or property edit (_on_stack_changed/_on_property_changed) and
## successful save (_save_stack_to_path, :1622), so titles and dirty stars
## stay current without a separate per-document watcher. clear_tabs()/
## add_tab() below replace the old per-document Button row entirely: a
## TabBar draws each tab's title and its CLOSE_BUTTON_SHOW_ALWAYS close icon
## as one native tab shape (matching Godot's own scene tabs), so there is no
## wrapper Control and no separate close Button to track. _tab_session_ids is
## rebuilt 1:1 with %ShaderTabs's own tab indices in the same pass, so
## _on_tab_bar_tab_changed/_on_tab_bar_close_pressed can resolve a tab index
## back to the document it belongs to by stable session id rather than
## trusting the raw index alone. _new_tab_button is %ShaderTabs's own fixed
## sibling in ShaderTabRow (gst_main_panel.tscn), never touched here.
##
## %ShaderTabs itself is never freed or recreated (unlike the old per-tab
## Button row), so keyboard-undo focus (_owns_undo_focus()) surviving a
## rebuild is no longer this function's concern: if the TabBar held focus
## before this call, it still holds the same Control instance, and therefore
## still holds focus, after it. _syncing_tabs suppresses
## _on_tab_bar_tab_changed while the current_tab write below runs, so
## restoring the active tab's own index here can never re-enter
## activate_document against the document _refresh_tabs() is already
## reflecting.
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
	# Fix 3 (round 1, Button-row era) / 2026-09-15 TabBar pass: keep the
	# active tab scrolled into view under overflow, including right after a
	# narrow-layout resize. _await_ensure_active_tab_visible re-reads
	# active_index's own current validity since another _refresh_tabs() call
	# (e.g. two edits in the same frame) can rebuild the tab list again
	# before it runs.
	_await_ensure_active_tab_visible(active_index)
	_apply_tab_bar_width()


## %ShaderTabs's own laid-out size is not guaranteed final until the next
## real frame boundary -- measured at a 150% editor scale (round 1 fix 3,
## Button-row era, reproduced identically for TabBar.ensure_tab_visible's own
## get_size().width read, tab_bar.cpp): a same-frame call here read a stale
## size and landed short of the true end by a fixed amount every time.
## Awaiting process_frame first lets layout settle.
func _await_ensure_active_tab_visible(index: int) -> void:
	await get_tree().process_frame
	if is_instance_valid(_shader_tabs) and index >= 0 and index < _shader_tabs.get_tab_count():
		_shader_tabs.ensure_tab_visible(index)


## %ShaderTabs.tab_changed: fires only when TabBar's own current_tab index
## actually moves (TabBar::set_current_tab, tab_bar.cpp), so a reclick on the
## already-active tab never reaches here at all -- no toggle/button_group
## bookkeeping needed the way the old per-tab Button row required.
## _syncing_tabs rejects the case this same signal fires for _refresh_tabs()'s
## own programmatic current_tab write, which must not re-enter
## activate_document against the document already being reflected.
## Wired-by: %ShaderTabs.tab_changed (_ready()).
func _on_tab_bar_tab_changed(tab: int) -> void:
	if _syncing_tabs or tab < 0 or tab >= _tab_session_ids.size():
		return
	var doc: GSTDocument = _find_document_by_session_id(_tab_session_ids[tab])
	if doc == null:
		return
	activate_document(doc)


## %ShaderTabs.tab_close_pressed: the close icon's own cb_rect hit-test
## (tab_bar.cpp), independent of tab_changed/tab_clicked. Resolves through
## _tab_session_ids/_find_document_by_session_id, same as
## _on_tab_bar_tab_changed above, rather than indexing _documents directly,
## so a stale signal delivered after some other rebuild already ran resolves
## to null instead of closing whatever document now happens to occupy that
## index.
## Wired-by: %ShaderTabs.tab_close_pressed (_ready()).
func _on_tab_bar_close_pressed(tab: int) -> void:
	if tab < 0 or tab >= _tab_session_ids.size():
		return
	var doc: GSTDocument = _find_document_by_session_id(_tab_session_ids[tab])
	if doc == null:
		return
	close_document(doc)


## Presentation (decision 4, docs/SHADER_TABS_reviewed.md): filename without
## extension once saved, recipe name before that first save, or a numbered
## Untitled label for a document with neither (a brand new document, or one
## reopened from an exported .gdshader header, decision 8 -- it has no
## recipe name and no .tres of its own either). untitled_index is this
## document's own 1-based position among currently open untitled-bucket
## documents, computed by the caller as it iterates _documents in creation
## order. A trailing `*` marks content that differs from the last successful
## open/save baseline (GSTDocument.is_dirty()).
func _tab_title(doc: GSTDocument, untitled_index: int) -> String:
	var base: String = ""
	if not doc.current_path.is_empty():
		base = doc.current_path.get_file().get_basename()
	elif not doc.recipe_name.is_empty():
		base = doc.recipe_name.replace("_", " ").capitalize()
	else:
		base = "Untitled %d" % untitled_index
	return base + ("*" if doc.is_dirty() else "")


## Tooltip shows the full path or unsaved origin (decision 4).
func _tab_tooltip(doc: GSTDocument) -> String:
	if not doc.current_path.is_empty():
		return doc.current_path
	if not doc.recipe_name.is_empty():
		return "Opened from recipe '%s' (not yet saved)." % doc.recipe_name
	if doc.reopened_import:
		return "Reopened from an exported .gdshader header (not yet saved)."
	return "New shader (not yet saved)."


## Public navigation entry point onto an already-open document (phase 3).
## Finishes any pending native gesture/color popup on the currently active
## document before switching (phase 3 fix pass 1, round 1): ownership must
## not move to doc while a commit is still in flight, since that commit
## would otherwise land after _install_document_state/_inspector_column.setup
## have already rebound _undo/the inspector column to doc's own adapter.
## Wired-by: %ShaderTabs.tab_changed, through _on_tab_bar_tab_changed (2026-
## 09-15 TabBar pass, predecessor: _refresh_tabs()'s own per-tab
## Button.pressed connection, phase 4); also the New/Open/Reopen/Recipes
## handlers' own canonical-path-reuse path (open_path below) and an editor
## smoke seam for
## tests/gst_editor_documents_smoke.gd, tests/gst_editor_tabs_smoke.gd, and
## the navigation/history-preservation assertions in tests/gst_editor_smoke.gd.
func activate_document(doc: GSTDocument) -> void:
	if doc == null or doc == _active_document:
		return
	await _finish_pending_edits()
	# Decision 5 (docs/SHADER_TABS_reviewed.md): switching cancels any open
	# picker rather than refusing to switch or leaving it open against a
	# stack it no longer destinations into -- restore_focus=false so no
	# stale target on the document being left is queued for a deferred
	# grab_focus() against rows _install_stack is about to free.
	_close_picker(false)
	_dismiss_start_screen()
	_activate_document(doc)


## Wired-by: none (editor smoke seam)
func get_active_document() -> GSTDocument:
	return _active_document


## Wired-by: none (editor smoke seam)
func get_documents() -> Array[GSTDocument]:
	return _documents.duplicate()


## %ShaderTabs itself (2026-09-15 TabBar pass, predecessor: get_tab_button/
## get_tab_close_button, which returned per-document Buttons a TabBar has no
## equivalent of).
## Wired-by: none (editor smoke seam)
func get_tab_bar() -> TabBar:
	return _shader_tabs


## doc's own tab index within %ShaderTabs, or -1 if doc is not open.
## Wired-by: none (editor smoke seam)
func get_tab_index(doc: GSTDocument) -> int:
	if doc == null:
		return -1
	return _tab_session_ids.find(doc.session_id)


## doc's own tab body rect, in global/screen coordinates. Rect2() if doc is
## not open.
## Wired-by: none (editor smoke seam)
func get_tab_rect(doc: GSTDocument) -> Rect2:
	var index: int = get_tab_index(doc)
	if index == -1:
		return Rect2()
	var local: Rect2 = _shader_tabs.get_tab_rect(index)
	return Rect2(_shader_tabs.get_global_rect().position + local.position, local.size)


## doc's own tab close-icon hit rect, in global/screen coordinates. Rect2() if
## doc is not open. See _tab_close_rect_local below for the derivation.
## Wired-by: none (editor smoke seam)
func get_tab_close_rect(doc: GSTDocument) -> Rect2:
	var index: int = get_tab_index(doc)
	if index == -1:
		return Rect2()
	var local: Rect2 = _tab_close_rect_local(index)
	return Rect2(_shader_tabs.get_global_rect().position + local.position, local.size)


## Replicates TabBar's own internal close-button hit rect (TabBar::_draw_tab's
## cb_rect, tab_bar.cpp), algebraically, from the same public StyleBox/
## Texture2D theme items that function itself reads -- cb_rect is private,
## with no getter. No shader tab is ever given an icon or a right_button, so
## cb_rect's right edge is exactly the tab's own right edge offset by the tab
## style's own right margin minus the close button's own highlight-style
## right margin, and its size is that highlight style's own minimum size plus
## the close icon's own size. Verified against
## .now/tabs-validation/godot-4.4-source/scene/gui/tab_bar.cpp:604-626 (the
## draw-time cb_rect assignment) algebraically cancelled against
## get_minimum_size's own matching width accounting at :40-108, so this reads
## only get_tab_rect's own already-final size_cache plus theme items, never a
## re-derivation of text width.
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


## The full tab row (%ShaderTabs plus the trailing New-tab Button). Unchanged
## by the 2026-09-15 TabBar pass; get_tab_scroll() (the ScrollContainer
## %ShaderTabs used to sit inside) is gone -- %ShaderTabs now scrolls its own
## tab content internally (scrolling_enabled, gst_main_panel.tscn).
## Wired-by: none (editor smoke seam)
func get_tab_row() -> HBoxContainer:
	return _shader_tab_row


## Canonical path comparison logic, exposed statically and gated by an
## explicit case_insensitive argument so tests can exercise both filesystem
## case-sensitivity modes without depending on the actual platform (phase 3
## review round 2 fix-now note 1). simplify_path() first (dedupes "//" and
## resolves "." / ".."), then ProjectSettings.globalize_path() so a res:// or
## user:// path and its already-absolute filesystem equivalent compare
## equal, then case-folds only when case_insensitive is true, so two
## spellings that differ only in letter case compare equal on
## case-insensitive filesystems and stay distinct on case-sensitive ones.
static func _canonical_path_for(path: String, case_insensitive: bool) -> String:
	var globalized: String = ProjectSettings.globalize_path(path.simplify_path())
	return globalized.to_lower() if case_insensitive else globalized


## Canonical identity for _find_document_by_path (phase 3 fix pass 1, round
## 1; platform-gated by round 2's fix-now pass instead of unconditionally
## case-folding): delegates to _canonical_path_for with case_insensitive
## true only on the two platforms whose default filesystem is itself
## case-insensitive (OS.get_name() "Windows"/"macOS"); every other platform
## name (Linux, FreeBSD, etc.) keeps case-sensitive identity, so e.g.
## Fire.tres and fire.tres never collapse into the same document there. Only
## used for comparison here; doc.current_path itself always keeps the
## caller's original spelling for display/save.
func _canonical_path(path: String) -> String:
	return _canonical_path_for(path, OS.get_name() in ["Windows", "macOS"])


## An already-open document whose own current_path canonically matches path,
## or null. Empty/unset paths never match (every never-saved document shares
## the same empty current_path, which is not a canonical identity).
func _find_document_by_path(path: String) -> GSTDocument:
	if path.is_empty():
		return null
	var canonical: String = _canonical_path(path)
	for doc: GSTDocument in _documents:
		if not doc.current_path.is_empty() and _canonical_path(doc.current_path) == canonical:
			return doc
	return null


## A still-open, never-saved, never-edited document with no recipe/import
## origin, or null (phase 3 fix pass 1, round 1: "pristine initial empty
## content remains reusable"). Recipe/import documents can never match:
## GSTDocument.setup's starts_dirty leaves them dirty from creation, so
## is_dirty() alone already excludes them here, without needing to also
## check recipe_open/reopened_import. New reuses this document instead of
## piling up another blank tab every time it is pressed with nothing yet
## typed into the current one.
func _find_reusable_pristine_document() -> GSTDocument:
	for doc: GSTDocument in _documents:
		if doc.current_path.is_empty() and not doc.is_dirty():
			return doc
	return null


## Looks up an already-open document by its stable session id (phase 5).
## Returns null when no open document carries that id -- it belonged to a
## document that has since closed through _close_document_now (phase 6);
## tests/gst_editor_document_files_smoke.gd still isolates the resolution
## guard by removing a document from _documents directly instead of driving
## a real close.
func _find_document_by_session_id(session_id: int) -> GSTDocument:
	for doc: GSTDocument in _documents:
		if doc.session_id == session_id:
			return doc
	return null


## Resolves a delayed file-dialog response against the document captured
## when its request was issued (phase 5, see the *_pending_* Dictionaries'
## own doc comment above). `pending` empty means no request was ever
## captured for this dialog, so this falls back to whatever is active right
## now -- the production meaning every plain path-taking seam
## (save_to_path/export_to_path/open_path/reopen_shader_path) and every
## *_file_selected/_on_overwrite_confirmed direct test call already relies
## on. A captured request whose doc_id no longer resolves through
## _find_document_by_session_id belonged to a document that is no longer
## open: this returns null, and the caller must reject the response without
## writing to, or messaging, any other document.
func _resolve_pending_document(pending: Dictionary) -> GSTDocument:
	if pending.is_empty():
		return _active_document
	return _find_document_by_session_id(int(pending.get("doc_id", -1)))


## Captures _active_document's stable id under a fresh, unique request_id
## (phase 5), for a dialog-opening "_pressed" handler to store into its own
## *_pending_* field just before popping its dialog. `{}` when there is no
## active document to capture (never observed in practice: _ready() always
## installs a first document before any dialog can open).
func _capture_active_document_request() -> Dictionary:
	return _capture_document_request(_active_document)


## Same capture shape as _capture_active_document_request, parameterized by
## doc instead of always _active_document (phase 6): a close request, and the
## Save As it may trigger for an untitled document, binds to the document the
## close button actually belongs to -- not necessarily the active one, since
## an inactive tab's own close button closes that tab whether or not it is
## on screen right now.
func _capture_document_request(doc: GSTDocument) -> Dictionary:
	if doc == null:
		return {}
	_next_file_request_id += 1
	return {"request_id": _next_file_request_id, "doc_id": doc.session_id}


## Creates a new GSTDocument for new_stack and activates it (decision
## superseding 20, phase 3): New, Open, Reopen Shader, and Recipes each open
## their own document now instead of replacing the single active document's
## stack through an undoable "Replace stack" action -- switching between
## documents is navigation, not a stack edit, and registers no action in any
## document's own UndoRedo. new_path "" for a never-saved or unsaved-origin
## (recipe, reopened-from-.gdshader) document. new_recipe_name/
## new_reopened_import mark and retain an unsaved recipe/import origin (Fix
## pass 1, round 1); a plain New call (both left at their defaults) instead
## reuses an existing pristine document via _find_reusable_pristine_document
## rather than allocating another one. This is the New/Open/Reopen/Recipes
## handlers' own shared entry point; public so
## tests/gst_editor_documents_smoke.gd can drive it directly.
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


## Public close entry point (decision 9, docs/SHADER_TABS_reviewed-plan.md
## phase 6): wired by %ShaderTabs's own tab_close_pressed signal, through
## _on_tab_bar_close_pressed (2026-09-15 TabBar pass, predecessor: each tab's
## own close Button, _refresh_tabs). A clean
## (non-dirty) document closes immediately; a dirty one is offered
## Save/Discard/Cancel through _close_dialog. Finishes any active native
## gesture on doc first, but only when doc is the active document -- an
## inactive document can hold no live gesture of its own (every past edit on
## it was already committed before ownership moved away,
## activate_document/open_document's own await _finish_pending_edits()
## before switching, the same rule _save_stack_to_path/_export_stack_to_path
## already follow) -- before evaluating GSTDocument.is_dirty(), since a
## pending edit's fingerprint has not landed on the stack yet (Cross-cutting
## "Finish continuous native edits before evaluating dirty state"). Registers
## no undo action anywhere (Cross-cutting "Keep closing and entry navigation
## outside stack undo").
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


## Short display name for the close-confirmation dialog's own text and
## get_unsaved_status_text's own per-document lines; not the tab title
## (_tab_title), which also carries the dirty star this message does not
## need. Fix-now round 2, note 2: an untitled document (no current_path, no
## recipe_name) used to fall through to the same literal "This shader" for
## every such document, so two dirty untitled documents rendered as two
## identical, indistinguishable lines in Godot's own quit confirmation
## (observed: "This shader\nquit_named_failed"). Reuses _tab_title's own
## 1-based "Untitled %d" numbering (_untitled_index) instead, so this
## message and the tab row always agree on which untitled document is which.
func _describe_document(doc: GSTDocument) -> String:
	if not doc.current_path.is_empty():
		return doc.current_path.get_file().get_basename()
	if not doc.recipe_name.is_empty():
		return doc.recipe_name.replace("_", " ").capitalize()
	return "Untitled %d" % _untitled_index(doc)


## doc's own 1-based position among _documents' untitled bucket (no
## current_path, no recipe_name), in the same creation-order iteration
## _refresh_tabs uses to compute _tab_title's own untitled_index -- shared
## here so _describe_document (close-confirmation dialog, unsaved-status
## lines) and the tab row itself never disagree about which untitled
## document is which.
func _untitled_index(doc: GSTDocument) -> int:
	var index: int = 0
	for candidate: GSTDocument in _documents:
		if candidate.current_path.is_empty() and candidate.recipe_name.is_empty():
			index += 1
		if candidate == doc:
			return index
	return index


## _close_dialog.confirmed ("Save"). Resolves against the document captured
## when the prompt opened, not whichever document is active now, the same
## resolve-by-session-id pattern as every other pending file/dialog response
## (Cross-cutting "resolve every response against its pending request and
## owning document; reject closed/stale targets without touching another
## document") -- a stale/closed target (doc == null) does nothing. An
## untitled document (decision 9: "Save on an untitled document runs Save As
## and closes only after success") routes through the real Save As dialog
## with close_after=true in its own pending capture, so _on_save_as_file_
## selected finishes the close once that write actually succeeds. A named
## document saves directly to its own current_path and closes only if that
## write succeeds; a failed save leaves it dirty and open with its own
## failure message already set by _save_stack_to_path.
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


## _close_dialog.custom_action ("Discard"; every other action string is
## ignored). Discard releases only the selected document's own
## resources/history (Cross-cutting), never any other open document's.
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


## Removes doc from _documents and tears down its own UndoRedo/GSTUndo (the
## only place that actually detaches a document from this panel). Every
## *_pending_* Dictionary above already resolves through
## _find_document_by_session_id, so once doc is removed here every in-flight
## file/picker/property callback captured against its session id resolves to
## null on its own -- no separate invalidation pass is needed. Closing the
## active document selects the adjacent remaining tab (decision 9, clamped to
## the same index the closed tab occupied); closing the last document
## recreates the exact bootstrap condition _ready() itself installs (one
## fresh pristine document, hidden behind the entry surface) instead of
## leaving the panel with no document at all, so every existing invariant
## that assumes an active document always exists stays intact. Registers no
## undo action anywhere (Cross-cutting "Keep closing and entry navigation
## outside stack undo").
func _close_document_now(doc: GSTDocument) -> void:
	if not _documents.has(doc):
		return
	var index: int = _documents.find(doc)
	var was_active: bool = doc == _active_document
	if was_active:
		# Decision 5's own switch-time rule applies to close too: a picker
		# open against the document being closed must not survive pointed at
		# a stack this panel is about to stop showing.
		_close_picker(false)
	_documents.remove_at(index)
	# Phase 7: closing a document -- whether through Discard or an already-
	# clean immediate close -- is one of the two places a recovery record is
	# allowed to disappear (the other is a successful save, _save_stack_to_
	# path below). A no-op when doc never held one.
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
## before a rebind, Save/Save As, Export, or keyboard undo/redo (decision
## superseding 20; phase 1 tabs_proof "forced_finish_ordering"). The common
## case (nothing pending) resolves synchronously with no suspension, since
## GSTInspectorColumn only awaits a frame while an open color popup's typed
## text is actually being committed.
func _finish_pending_edits() -> void:
	await _inspector_column.finish_pending_edits()


## Phase 7 (docs/SHADER_TABS_reviewed-plan.md): shutdown recovery storage,
## always under *this running project's own* settings directory -- never a
## user's own stack/export path (decision 10). Running the editor against an
## isolated test project (tests/gst_editor_document_recovery_smoke.gd's own
## convention, matching every other Shader tabs phase) is what keeps this off
## a real project's own recovery records; production takes whatever project
## is actually open.
## Wired-by: none (editor smoke seam).
func get_recovery_dir() -> String:
	return GSTDocumentRecovery.recovery_dir(EditorInterface.get_editor_paths().get_project_settings_dir())


## plugin.gd's own _get_unsaved_status(""); decision 10 lists every dirty
## shader document by the same short name the close-confirmation dialog uses
## (_describe_document). A nonempty for_scene reports "" unconditionally:
## every open GSTDocument is session-scoped, never scene-owned (Cross-
## cutting "Scene close must not treat session-scoped shader documents as
## scene-owned"), so Godot's own scene-close confirmation must never see
## shader content as if it belonged to whatever scene is closing. No pending-
## edit finish runs here: property_changed already applies a live gesture's
## value straight onto the document/object/property target as it happens
## (phase 1/2), so is_dirty()'s fingerprint already reflects it without
## needing this synchronous, non-awaitable virtual to wait on anything.
## Wired-by: plugin.gd's _get_unsaved_status.
func get_unsaved_status_text(for_scene: String) -> String:
	if not for_scene.is_empty():
		return ""
	var names: Array[String] = []
	for doc: GSTDocument in _documents:
		if doc.needs_shutdown_attention():
			names.append(_describe_document(doc))
	return "\n".join(names)


## plugin.gd's own _save_external_data(): the confirmed "Save and Quit"
## callback (decision 10). Godot documents this virtual as void and
## unawaited -- it cannot suspend the shutdown it was called from, so this
## finishes what pending native edit it can synchronously (matching phase 1's
## own finding, tests/gst_editor_document_proof.gd's shutdown case: "That
## closure's pending_edit argument is never supplied, so its await branch is
## never taken and the call resolves synchronously") before saving every
## dirty named document straight to its own current_path, and recovering
## every untitled or failed-path document into a self-contained record
## instead (Cross-cutting "Phase 7 introduces editor-local recovery metadata
## only"). A document whose named save just succeeded drops any recovery
## record it used to carry (Cross-cutting "Keep each record until its
## document is successfully saved..."); one whose save failed keeps its
## dirty state and gets recovered under its *original* path/origin instead,
## reusing its own record id on a later shutdown rather than piling up a
## duplicate (decision 10).
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


## Writes/updates doc's own recovery record. `save_failure_reason` is ""
## for an untitled document (nothing was ever attempted for it to fail) or
## the exact GSTStackIO.save failure reason for a named document whose own
## save just failed. On a recovery-write failure too, reports both exact
## attempted paths and this callback's own inability to veto shutdown
## through a single editor error (decision 10: "If the user chooses Save and
## Quit... report the exact paths and engine limitation through an editor
## error; _save_external_data() is void and cannot veto shutdown"). Fix-now
## round 2, note 1: a non-empty quarantined_path in write_record's own result
## means this same call just renamed an unreadable index.json out of the way
## before writing doc's own fresh one -- any stack files that quarantined
## index used to reference are now unindexed, so this reports it through the
## same push_error channel at write time instead of leaving it silent
## (load_all's own directory scan, GSTDocumentRecovery._find_quarantined_
## indexes, also keeps reporting the same file on every later startup until
## a human removes it).
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


## Removes doc's own recovery record on disk, if it has one, and clears its
## tracked id -- called after a successful save/Save As and after Discard
## (Cross-cutting "verify cleanup after Save As and close Discard"). A no-op
## for a document that never held a recovery record. Fix-now round 6, note 2
## (S2): remove_record's own result is now checked before this call clears
## doc's own recovery identity -- previously a failed stack deletion or a
## failed metadata rewrite (the same production call site, dir replaced by a
## non-empty directory or its own .tmp path blocked) still cleared doc's own
## recovery_record_id/recovery_fingerprint unconditionally, so a genuinely
## unresolved on-disk record (an orphaned stack, or a dangling index entry
## still naming a now-deleted stack) lost the only in-memory pointer this
## document ever had back to it, with nothing reported. A failed cleanup now
## leaves doc's own recovery identity exactly as it was and reports the
## reason through the same push_error channel _recover_document already uses
## for its own write-time failures, so a document whose Save/Discard cleanup
## did not actually finish is never silently treated as fully resolved.
func _forget_recovery_record(doc: GSTDocument) -> void:
	if doc.recovery_record_id.is_empty():
		return
	var remove_result: Dictionary = GSTDocumentRecovery.remove_record(get_recovery_dir(), doc.recovery_record_id)
	if not bool(remove_result.get("ok", false)):
		push_error("GoShade Turbo: could not remove recovery record %s: %s" % [doc.recovery_record_id, remove_result.get("reason", "")])
		return
	doc.recovery_record_id = ""
	doc.recovery_fingerprint = ""


## Reopens every valid recovery record left by a previous confirmed-quit
## save_external_data() call as its own dirty document (decision 10:
## "recovery documents reopen as dirty tabs before the normal entry
## surface"), before _ready() lets the user see the start screen behind the
## bootstrap document it just created. A failed/unreadable record is kept on
## disk exactly where it was and reported, never deleted (Cross-cutting
## "Invalid/unknown recovery metadata remains available for diagnosis; no
## migration may silently delete it") -- only an explicit Discard or a
## successful save removes a record (_forget_recovery_record above). Each
## recovered document starts dirty unconditionally: it holds content that
## never reached its own original_path (or never had one), so there is
## nothing on disk yet for mark_baseline() to consider "saved".
## Wired-by: _ready(); an editor smoke seam for
## tests/gst_editor_document_recovery_smoke.gd's own fresh-restoration check.
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


## Installs new_stack (and new_path as the new _current_path, and
## new_recipe_open as the new _recipe_open) as an undoable "Replace stack"
## action on the *active document's own* UndoRedo, in place -- the active
## GSTDocument instance is retained; only its own .stack/.undo swap. Phase 3
## (docs/SHADER_TABS_reviewed-plan.md) retired this as the production
## New/Open/Reopen Shader/Recipes path: those now call open_document, which
## creates and activates a whole new GSTDocument instead, so switching
## between documents registers no action anywhere and an inactive
## document's own history is never touched by navigating away from it.
## Kept only as an internal fixture-only primitive (Cross-cutting: "Keep
## internal replacement only where a fixture explicitly requires it and
## document ownership remains intact") for tests that need a real, in-place,
## undoable stack swap on the one active document without constructing a
## second GSTDocument -- e.g. simulating a stale picker-context installation
## or a broken-codegen stack directly on the document already under test.
##
## Binds the action's own do/undo methods and new_undo's on_changed/
## on_property_changed callbacks to owner_doc, the document active when
## this action was created, rather than to mutable panel state (phase 3 fix
## pass 1, round 1): replaying this action from owner_doc's own history
## while a *different* document is active (a stale callback, or a test
## driving owner_doc's history directly) must rewrite only owner_doc's own
## fields, and must only touch the shared UI when owner_doc is still the
## active one -- never overwrite whichever other document is actually on
## screen.
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
	# A fresh GSTMaterialSync/material, same as a brand new GSTDocument would
	# carry (its own _init() calls reset_installation()): a later codegen
	# failure on new_stack must never expose old_stack's last successful
	# preview, matching every other install (GSTMaterialSync.
	# reset_installation's own doc comment).
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


## Deferred note (phase 5 review round 1, resolved phase 6): a force-hide
## with no resolution coming (the default, abandon=true) now also clears
## _pending_export itself, matching every real abandonment path (the real
## dialog's own Cancel/Esc already clears it through its own canceled
## signal), instead of leaving that job to each caller. abandon=false
## preserves _pending_export for the one existing caller shape that
## immediately follows this call with its own resolution of the very request
## that opened the dialog (tests/gst_editor_document_files_smoke.gd's
## _run_export_second_confirmation, simulating a real EditorFileDialog's own
## auto-hide-on-file_selected, which never emits canceled either).
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
	# Fix-now (phase 5 review round 2, note 1): open_document itself awaits
	# _finish_pending_edits(), which suspends whenever a native color popup's
	# typed hex is being committed (decision 7's forced-finish rule). Without
	# this await, the two lines below ran immediately against the
	# still-previous _active_document instead of the document New actually
	# installed once that suspension resolved.
	await open_document(GSTStack.new(), "", false)
	# Fix-now (phase 5 review round 1, note 1): a direct _message_label.text
	# write here diverged from GSTDocument.operation_messages -- a pristine
	# document reused by _find_reusable_pristine_document (open_document's own
	# new_path.is_empty() branch) can already carry a stale diagnostic (e.g. a
	# prior failed Open landed on it while it was still pristine); blanking
	# only the label left that entry in operation_messages, so the next
	# _refresh_operation_message_label() call (a tab switch back, or any later
	# message on this document) re-showed it. Clear the entry on the document
	# itself so the two can never disagree.
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


## Phase 5: routes a delayed *failure* response's message to the document
## active when the Open dialog was opened (_pending_open), not whichever
## document is active now -- a refusal never activates anything, so there is
## no new on-screen document to carry the reason instead. A success still
## targets whichever document activate_document/open_document actually
## installs (_open_path_for's own doc comment): Open always
## creates/reactivates its own document regardless of which one this
## capture names. A stale/closed captured document
## (_resolve_pending_document returns null) gets no failure message
## anywhere, matching "reject ... without touching another document"; the
## Open itself still proceeds normally. Awaits _open_path_for (fix-now,
## phase 5 review round 3, note 1): activate_document/open_document await
## _finish_pending_edits(), which suspends across a native color-popup
## commit in flight -- without this await, a later statement here would run
## before that installation finished.
func _on_open_file_selected(path: String) -> void:
	var message_doc: GSTDocument = _resolve_pending_document(_pending_open)
	_pending_open = {}
	await _open_path_for(message_doc, path)


## Activates path's already-open document if one exists (phase 3: "repeat
## canonical stack paths activate the existing document"), checked before
## ever touching disk so a document that is still open in memory reactivates
## even if its file was since deleted or edited externally. Otherwise loads
## `path` through GSTStackIO and installs it via open_document (phase 3: a
## new, independent GSTDocument, not an undoable "Replace stack" action). A
## refusal (a missing file or an unresolved entry) leaves the active
## document untouched and shows the reason on message_doc (phase 5: the
## document active when the real Open dialog was opened, or _active_document
## for this public seam and every direct test call). This is the Open
## button's own file-selected handler (_on_open_file_selected resolves
## message_doc and calls this); public so tests/gst_editor_smoke.gd can
## drive the same path without popping the file dialog (docs/PLAN.md Phase 4
## Files precedent, gst_stack_list.gd's add_layer_by_entry_id). Awaits
## _open_path_for for the same forced-finish-suspension reason as
## _on_open_file_selected above.
func open_path(path: String) -> void:
	await _open_path_for(_active_document, path)


## Only the failure branch uses message_doc (the document captured when the
## real Open dialog was opened): a refusal never activates anything, so
## there is no new on-screen document for the reason to describe instead. A
## success (either branch) clears the message on the document
## activate_document/open_document actually installed -- captured directly
## from their own await, not re-read from _active_document afterward (fix-
## now, phase 5 review round 3, note 1): activate_document/open_document
## await _finish_pending_edits(), which suspends across a native color-popup
## commit in flight, so a non-awaited call's very next statement used to run
## against whichever document was still active before that suspension
## resolved -- erasing that document's own "Open" entry instead of the
## newly installed document's. open_document can return null
## (open_document's own is_picker_open() guard); a null opened document gets
## no success message anywhere, matching the same "no target, no message"
## rule the failure branch already follows.
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


## Loads RECIPES_DIR/<name>.tres and installs it via open_document (phase 3:
## a new, independent GSTDocument, not an undoable "Replace stack" action),
## with the new current_path left empty rather than set to the recipe's own
## path: a recipe is a template, so Save falls back to Save As instead of
## silently overwriting the shipped recipe file (docs/PLAN.md Phase 7 Files).
## Never reuses another open document (recipes always create an
## independent copy, even of the same recipe opened twice: phase 3
## "Repeated recipes create independent layer/coord instances"). This is the
## Recipes menu's own handler; public so tests/gst_editor_smoke.gd can drive
## the same path directly. Success targets the document open_document's own
## await actually installs, not _active_document re-read afterward (fix-now,
## phase 5 review round 3, note 1: open_document awaits
## _finish_pending_edits(), which suspends across a native color-popup
## commit in flight, so a non-awaited call's very next statement used to run
## against whichever document was still active before that suspension
## resolved). The failure branch has no navigation to await, so
## _active_document at that point is still the document open_recipe was
## actually called on.
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


## Phase 5: resolves against _pending_save_as (the document active when the
## Save As dialog was opened), not whichever document is active now.
## doc == null (no request captured, this dialog never popped -- every
## direct test call below still resolves to _active_document, matching prior
## behavior) is handled by _save_stack_to_path itself returning a "no longer
## open" failure only when a request *was* captured and its document is
## gone; _resolve_pending_document already folds the "never captured" case
## into _active_document, so this only ever sees null for a genuinely
## closed/stale target -- surfaced on whichever document is active now
## (deferred note, phase 5 review round 1, resolved phase 6: a closed target
## used to leave this silently discarded). close_after (phase 6: set only by
## the close lifecycle's own Save-on-untitled-document path) closes doc once
## its own save actually succeeds; a still-open failed save leaves it dirty
## and open, matching the same rule a plain Save As failure already follows.
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


## Saves the open stack to `path` through GSTStackIO. This is both the Save
## button's own handler (when a current path already exists) and the
## production/test entry point every direct caller (documents_smoke,
## native_undo_smoke, tabs_smoke) already used before phase 5: always the
## *currently active* document, exactly like before. Save As's own delayed
## dialog response instead resolves its own captured document through
## _on_save_as_file_selected above and calls the document-bound
## _save_stack_to_path directly, so a document switch between opening that
## dialog and it resolving can never redirect the write.
func save_to_path(path: String) -> Dictionary:
	return await _save_stack_to_path(_active_document, path)


## Document-bound save (phase 5). Refuses a stale/closed target (doc no
## longer in _documents) without writing or messaging anywhere else, and
## refuses a canonical path already owned by a *different* open document
## with a path-conflict message on doc itself (Cross-cutting "Refuse Save As
## to a canonical path owned by another open document"; doc's own current
## path always resolves back to doc, never itself, so a plain re-save to the
## same path is unaffected). Finishes pending native gestures/popups only
## when doc is still the active one -- an inactive document can hold no live
## gesture of its own: every past edit on it was already committed before
## ownership moved away (activate_document/open_document's own await
## _finish_pending_edits() before switching). Marks doc's own baseline
## fingerprint and path only on a successful write (phase 3's baseline
## contract; Cross-cutting "Update path/title and the saved fingerprint only
## after successful stack save").
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
	# Fix-now (phase 5 review round 2, note 2): reuse the byte-identical
	# document-bound path setter instead of re-writing its two lines inline.
	_raw_set_current_path_for(doc, path)
	doc.mark_baseline()
	# Phase 7: a successful save/Save As is the other place a recovery record
	# is allowed to disappear (Cross-cutting "Keep each record until its
	# document is successfully saved or explicitly discarded").
	_forget_recovery_record(doc)
	_refresh_tabs()
	_set_operation_message_for(doc, "Save", "")
	return result


func _on_export_pressed() -> void:
	_pending_export = _capture_active_document_request()
	_export_dialog.popup_centered_ratio()


## Phase 5: resolves against _pending_export (the document active when the
## Export dialog was opened), not whichever document is active now. A
## closed target surfaces its reason on whichever document is active now
## (deferred note, phase 5 review round 1, resolved phase 6), instead of
## being silently discarded.
func _on_export_file_selected(path: String) -> void:
	var doc: GSTDocument = _resolve_pending_document(_pending_export)
	_pending_export = {}
	var result: Dictionary = await _export_stack_to_path(doc, path, false)
	if doc == null:
		_set_operation_message("Export", String(result.get("reason", "")))


## Exports the currently active document's stack to `path`. Production/test
## entry point every direct caller already used before phase 5 (always the
## active document, unchanged); the real Export dialog's own delayed
## response instead resolves its own captured document through
## _on_export_file_selected above.
func export_to_path(path: String, confirm: bool) -> Dictionary:
	return await _export_stack_to_path(_active_document, path, confirm)


## Document-bound export (phase 5). Refuses a stale/closed target the same
## way _save_stack_to_path does. When GSTExport.write reports
## needs_confirmation, captures doc's own id (not just the path) into
## _pending_overwrite, so _on_overwrite_confirmed below re-targets the same
## document that asked for this export -- Cross-cutting "Preserve export's
## existing hand-edit overwrite check and bind its second confirmation to
## the original request" -- even if a different document becomes active
## while the confirmation dialog is up. Export never marks a baseline
## (Cross-cutting "Export never clears dirty state").
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
	# Any other outcome resolves the question the dialog was asking (a
	# confirmed write, or a write that turned out not to need confirmation
	# at all): closes it explicitly rather than relying on AcceptDialog's
	# own auto-hide-on-confirmed, which only fires for an actual button
	# press, not a direct confirm=true call (the smoke's own path here).
	if _overwrite_dialog.visible:
		_overwrite_dialog.hide()
	if not result["ok"]:
		_set_operation_message_for(doc, "Export", result["reason"])
		return result
	_refresh_exported_shader(path, result["code"])
	_set_operation_message_for(doc, "Export", "")
	return result


## GSTExport.write only replaces the bytes on disk. A Shader the editor has
## already loaded from `path` (a scene using it is open, or a material in a
## running preview holds it) keeps its old code until something reloads
## it, so a re-export looked like it never overwrote the file. Push the
## written text into the cached Shader (every ShaderMaterial on it
## recompiles) and tell EditorFileSystem the file changed.
func _refresh_exported_shader(path: String, code: String) -> void:
	if ResourceLoader.has_cached(path):
		var cached: Resource = ResourceLoader.load(path)
		if cached is Shader:
			(cached as Shader).code = code
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)


## Phase 5: re-targets the same document _export_stack_to_path captured when
## it first found this export needs confirmation (_pending_overwrite), not
## whichever document is active now. A stale/closed target (doc no longer
## open) just hides the dialog and does nothing else -- there is no longer
## any document to overwrite or message.
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


## Phase 5: routes a delayed *failure* response's message to the document
## active when the Reopen Shader dialog was opened, the same reasoning as
## _on_open_file_selected above (a success still targets whatever
## open_document actually installs -- the freshly reopened document itself
## -- independent of which document is active now). Awaits
## _reopen_shader_path_for for the same forced-finish-suspension reason as
## _on_open_file_selected (fix-now, phase 5 review round 3, note 1).
func _on_reopen_shader_file_selected(path: String) -> void:
	var message_doc: GSTDocument = _resolve_pending_document(_pending_reopen)
	_pending_reopen = {}
	await _reopen_shader_path_for(message_doc, path)


## Reopens a stack from an exported .gdshader's embedded header through
## GSTExport.reopen (decision 8). A refusal (no header, unparsable header, or
## an unknown schema -- B8) shows the reason on message_doc (phase 5: the
## document active when the real Reopen Shader dialog was opened, or
## _active_document for this public seam and every direct test call) and
## leaves the active document untouched; no new empty stack is offered. On
## success, installs the rebuilt stack via open_document (phase 3: a new,
## independent GSTDocument, not an undoable "Replace stack" action) with an
## empty _current_path (a reopened stack has no .tres of its own, and this
## new document's unsaved origin is never confused with another open
## document that happens to share the same empty path). When the file's body
## differs from a fresh codegen of its own header (decision 8's stale-body
## warning), that is shown instead of the plain success clear. This is the
## Reopen Shader button's own file-selected handler; public so the smoke can
## drive it directly too. Awaits _reopen_shader_path_for for the same
## forced-finish-suspension reason as open_path above (fix-now, phase 5
## review round 3, note 1).
func reopen_shader_path(path: String) -> void:
	await _reopen_shader_path_for(_active_document, path)


## Only the failure branch uses message_doc, the same reasoning as
## _open_path_for above: a refusal never activates anything, so there is no
## new on-screen document for the reason to describe instead; a success
## (with or without the body-differs warning) targets the document
## open_document's own await actually installs -- the freshly reopened
## document itself -- captured directly rather than re-read from
## _active_document afterward (fix-now, phase 5 review round 3, note 1):
## open_document awaits _finish_pending_edits(), which suspends across a
## native color-popup commit in flight, so a non-awaited call's very next
## statement used to run against whichever document was still active before
## that suspension resolved. open_document can return null (its own
## is_picker_open() guard); a null opened document gets no success message
## anywhere, matching the failure branch's "no target, no message" rule.
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
		_set_operation_message_for(opened, "Reopen Shader", "%s reopened: its body differs from a fresh codegen of the header (hand edits detected, decision 8)" % path)
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


## GSTUndo's on_property_changed callback: fires after every do and undo of
## a native property edit specifically. Deliberately does not touch
## _stack_list, _output_block, or _inspector_column: a property edit never
## changes layer identity, slots, or references, and rebuilding the
## inspector column here would free the very row a live gesture, an open
## native color popup, or a test still holds a reference to (decision
## superseding 20). gst_inspector_column.gd refreshes that one row's own
## displayed value itself, bound by key, alongside this call. _refresh_tabs()
## keeps the active document's own dirty star current (phase 4): a native
## property edit changes GSTDocument.is_dirty()'s fingerprint just as a
## structural edit does, but never goes through _on_stack_changed above.
func _on_property_changed() -> void:
	_resync_material()
	_refresh_tabs()


## _resync_material runs first and always sets _message_label to the current
## codegen error (or "" on success): the screen_uv suggestion below is only
## applied on top of a clean sync, so a real codegen error is never masked
## by it.
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


## Phase 5: resolves against _pending_image (the document active when the
## image dialog was opened), not whichever document is active now. Writes
## doc.preview_image_path unconditionally (a document's own stored preview
## image is its content whether or not it is on screen right now -- phase 4
## restores it from there on a later activation), but only touches the live
## _preview/_material the active UI is actually showing when doc is still
## the active document. A stale/closed target (doc == null) touches nothing
## (Cross-cutting "reject closed/stale targets without touching another
## document").
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
	if _active_document != null:
		_active_document.recipe_open = value
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
## on Godot 4.6.2/4.7, a key event never reaches here while a native,
## non-embedded color popup subwindow holds real focus.
## gst_inspector_column.gd's own color_popup_undo_redo_requested signal
## (connected in _ready() straight to _apply_keyboard_undo_redo) is that
## case's own entry point on every version, driven by that popup's own
## focused LineEdit field intercepting the key directly.
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
## same keys reaching a focused native color popup's own currently-focused
## field instead, forwarded here since the root viewport does not reliably
## see them while that popup holds focus).
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


## restore_focus=false (phase 4, activate_document's own cancel-on-switch
## call): skips the focus-restoration below entirely instead of queuing a
## deferred grab_focus() against a target that belongs to the document being
## switched away from -- exactly the "stale focus restoration" decision 5
## calls out, since _install_stack (about to run via _activate_document)
## frees and rebuilds every native row this dialog might have pointed at.
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
				# Fix-now (phase 5 review round 3, note 1): open_document
				# awaits _finish_pending_edits(), which suspends across a
				# native color-popup commit in flight. Without this await,
				# the shared success tail below (_picker_refusal("") ->
				# _set_operation_message("Recipes", "") -> _active_document)
				# used to run against whichever document was still active
				# before that suspension resolved, not the document this
				# recipe just installed.
				await open_document(loaded["stack"], "", true, value)
	_applying_choice = false
	if not result["ok"]:
		_picker_refusal(result["reason"])
		return
	_picker_refusal("")
	_close_picker()


## Convenience for a synchronous, non-delayed operation message (Recipes'
## own embedded-picker refusal path, and the preset dropdown's screen_uv
## suggestion): always the currently active document, since neither can
## outlive an await across a document switch the way a file dialog response
## can. File-dialog handlers use _set_operation_message_for directly with
## their own resolved message_doc/doc (phase 5).
func _set_operation_message(control: String, reason: String) -> void:
	_set_operation_message_for(_active_document, control, reason)


## Routes a file-operation diagnostic onto doc's own GSTDocument.
## operation_messages (phase 5: "route operation messages to their owning
## document so a delayed failure cannot replace another document's
## diagnostics") and only rebuilds the shared label when doc is still the
## active one. A null doc (a resolved-stale/closed request) is a no-op:
## there is no document left to carry the message.
func _set_operation_message_for(doc: GSTDocument, control: String, reason: String) -> void:
	if doc == null:
		return
	if reason.is_empty():
		doc.operation_messages.erase(control)
	else:
		doc.operation_messages[control] = reason
	if doc == _active_document:
		_refresh_operation_message_label()


## Rebuilds _message_label from _active_document's own operation_messages
## (phase 5), called whenever they change on the active document
## (_set_operation_message_for) and whenever the active document itself
## changes (_install_stack, reached through every activation).
func _refresh_operation_message_label() -> void:
	var lines: Array[String] = []
	if _active_document != null:
		for name: Variant in _active_document.operation_messages:
			lines.append("%s: %s" % [String(name), _active_document.operation_messages[name]])
	_message_label.text = "\n".join(lines)
	_message_label.visible = not lines.is_empty()
