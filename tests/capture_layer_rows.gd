extends SceneTree

## Saves a screenshot of a GSTStackList holding a renamed, a duplicated and a
## bypassed row (T-0100 visual check). Builds the list alone: GSTMainPanel
## needs EditorInterface. Every edit goes through GSTUndo, the path the
## Layer menu uses. Run windowed:
## godot --path . -s res://tests/capture_layer_rows.gd

const OUTPUT_PATH: String = "res://.godot/layer-ops.png"
const LIST_POSITION: Vector2 = Vector2(16.0, 16.0)
const LIST_SIZE: Vector2 = Vector2(480.0, 220.0)
const SETTLE_FRAMES: int = 5


func _initialize() -> void:
	_run()


func _run() -> void:
	var library: GSTLibrary = GSTLibrary.new()
	library.scan()
	var stack: GSTStack = GSTStack.new()
	var undo_redo: UndoRedo = UndoRedo.new()
	var undo: GSTUndo = GSTUndo.new(undo_redo, stack, library, Callable(), Callable())

	var stack_list: GSTStackList = (load("res://addons/goshade_turbo/ui/gst_stack_list.tscn") as PackedScene).instantiate() as GSTStackList
	root.add_child(stack_list)
	# Root enters the tree after _initialize returns; _ready fills the
	# list's @onready nodes one frame later.
	await process_frame
	stack_list.position = LIST_POSITION
	stack_list.size = LIST_SIZE
	stack_list.setup(stack, library, undo)

	var fbm: GSTLayer = stack_list.add_layer_by_entry_id("generative/fbm")
	var invert: GSTLayer = stack_list.add_layer_by_entry_id("fieldops/invert")
	var copy: GSTLayer = stack_list.duplicate_layer(invert.id)
	undo.rename_layer(fbm.id, "base")
	stack_list.set_layer_enabled(invert.id, false)
	stack_list.refresh()

	for i: int in range(SETTLE_FRAMES):
		await process_frame
	var rows: Array[String] = []
	for id: StringName in [copy.id, invert.id, fbm.id]:
		rows.append(stack_list.get_row_text(id))
	var image: Image = root.get_viewport().get_texture().get_image()
	var error: Error = ERR_UNAVAILABLE if image == null else image.save_png(OUTPUT_PATH)
	print("CAPTURE path=%s error=%d rows=%s" % [ProjectSettings.globalize_path(OUTPUT_PATH), error, rows])
	undo_redo.free()
	quit(0 if error == OK else 1)
