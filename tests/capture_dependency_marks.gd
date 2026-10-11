extends SceneTree

## Saves a screenshot of a GSTStackList with the middle layer selected and its
## dependency marks shown (T-0103 visual check, decision 35). Builds the list
## alone: GSTMainPanel needs EditorInterface. Outside the editor no theme
## carries Editor/accent_color, so the list gets EDITOR_ACCENT, the value the
## ui_dependency_marks smoke reads from the Godot 4.6 editor theme. Run windowed:
## godot --path . -s res://tests/capture_dependency_marks.gd

const OUTPUT_PATH: String = "res://.godot/dependency-marks.png"
const LIST_POSITION: Vector2 = Vector2(16.0, 16.0)
const LIST_SIZE: Vector2 = Vector2(480.0, 220.0)
const SETTLE_FRAMES: int = 5
const EDITOR_ACCENT: Color = Color(0.337, 0.62, 1.0)


func _initialize() -> void:
	_run()


func _run() -> void:
	var library: GSTLibrary = GSTLibrary.new()
	library.scan()
	var stack: GSTStack = GSTStack.new()
	var undo_redo: UndoRedo = UndoRedo.new()
	var undo: GSTUndo = GSTUndo.new(undo_redo, stack, library, Callable(), Callable())

	var stack_list: GSTStackList = (load("res://addons/goshade_turbo/ui/gst_stack_list.tscn") as PackedScene).instantiate() as GSTStackList
	var theme: Theme = Theme.new()
	theme.set_color(&"accent_color", &"Editor", EDITOR_ACCENT)
	stack_list.theme = theme
	root.add_child(stack_list)
	# Root enters the tree after _initialize returns; _ready fills the
	# list's @onready nodes one frame later.
	await process_frame
	stack_list.position = LIST_POSITION
	stack_list.size = LIST_SIZE
	stack_list.setup(stack, library, undo)

	var bottom: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	var invert: GSTLayer = stack_list.add_layer_by_entry_id("fieldops/invert")
	var mid: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	var top: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	undo.assign_warp(mid.id, "x", invert.id)
	undo.set_param_link(top.id, "gain", mid.id)
	undo.rename_layer(mid.id, "mid")
	stack_list.refresh()
	stack_list.select_layer(mid.id)

	for i: int in range(SETTLE_FRAMES):
		await process_frame
	var rows: Array[String] = []
	for id: StringName in [top.id, mid.id, invert.id, bottom.id]:
		rows.append(stack_list.get_row_text(id))
	var image: Image = root.get_viewport().get_texture().get_image()
	var error: Error = ERR_UNAVAILABLE if image == null else image.save_png(OUTPUT_PATH)
	print("CAPTURE path=%s error=%d rows=%s" % [ProjectSettings.globalize_path(OUTPUT_PATH), error, rows])
	undo_redo.free()
	quit(0 if error == OK else 1)
