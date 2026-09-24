extends SceneTree

## Renders every recipe under addons/goshade_turbo/recipes/ to
## docs/media/recipes/<recipe>.png for the README gallery (needs a GPU
## session, same rule as tests/run_render_checks.gd):
## `godot --path . --rendering-driver opengl3 -s res://sandbox/gallery/render_gallery.gd`
## Each recipe renders through the sprite preview preset at TIME = FRAME_TIME
## (TIME replaced by a constant, as in tests/run_recipe_motion_checks.gd), is
## composited over BACKGROUND so tiles read the same on light and dark pages,
## and is downsampled by SUPERSAMPLE.

const RECIPE_DIR: String = "res://addons/goshade_turbo/recipes"
const OUT_DIR: String = "res://docs/media/recipes"
const PREVIEW_IMAGE_PATH: String = "res://addons/goshade_turbo/assets/preview_default.png"
const TILE_SIZE: int = 256
const SUPERSAMPLE: int = 2
const FRAME_TIME: float = 2.0
const SETTLE_FRAMES: int = 4
const BACKGROUND: Color = Color(0.11, 0.11, 0.13, 1.0)

var _failed: bool = false


func _remove_stale_recovery_lock() -> void:
	var lock_path: String = OS.get_user_data_dir().path_join(".recovery_mode_lock")
	if FileAccess.file_exists(lock_path):
		DirAccess.remove_absolute(lock_path)


func _initialize() -> void:
	_remove_stale_recovery_lock()
	_run.call_deferred()


func _run() -> void:
	var library: GSTLibrary = GSTLibrary.new()
	library.scan()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var render_size: Vector2i = Vector2i(TILE_SIZE, TILE_SIZE) * SUPERSAMPLE
	var viewport: SubViewport = SubViewport.new()
	viewport.size = render_size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = "shader_type canvas_item; void fragment() { COLOR = texture(TEXTURE, UV); }"
	var target: Control = GSTPreviewPresets.build(GSTPreviewPresets.SPRITE, load(PREVIEW_IMAGE_PATH))
	target.set_anchors_preset(Control.PRESET_FULL_RECT)
	target.material = material
	viewport.add_child(target)

	var files: PackedStringArray = DirAccess.get_files_at(RECIPE_DIR)
	for file: String in files:
		if file.get_extension() != "tres":
			continue
		var recipe: String = file.get_basename()
		var loaded: Dictionary = GSTStackIO.load(RECIPE_DIR.path_join(file), library)
		if not loaded["ok"]:
			_fail(recipe, "load: %s" % loaded["reason"])
			continue
		var result: GSTCodegenResult = GSTMaterialSync.sync(loaded["stack"], library, material, &"", Vector2(render_size))
		if not result.ok():
			_fail(recipe, "codegen: %s" % result.error)
			continue
		material.shader.code = result.code.replace("TIME", "%.3f" % FRAME_TIME)
		for frame: int in range(SETTLE_FRAMES):
			await process_frame
		var rendered: Image = viewport.get_texture().get_image()
		rendered.convert(Image.FORMAT_RGBA8)
		var tile: Image = Image.create_empty(render_size.x, render_size.y, false, Image.FORMAT_RGBA8)
		tile.fill(BACKGROUND)
		tile.blend_rect(rendered, Rect2i(Vector2i.ZERO, render_size), Vector2i.ZERO)
		tile.resize(TILE_SIZE, TILE_SIZE, Image.INTERPOLATE_LANCZOS)
		var out_path: String = OUT_DIR.path_join(recipe + ".png")
		var err: Error = tile.save_png(out_path)
		if err != OK:
			_fail(recipe, "save %s: %s" % [out_path, error_string(err)])
			continue
		print("GALLERY %s PASS %s" % [recipe, out_path])

	print("GALLERY SUMMARY %s" % ("FAIL" if _failed else "PASS"))
	_remove_stale_recovery_lock()
	quit(1 if _failed else 0)


func _fail(recipe: String, reason: String) -> void:
	_failed = true
	print("GALLERY %s FAIL %s" % [recipe, reason])
