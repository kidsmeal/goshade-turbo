extends SceneTree

## Named verification command (docs/PLAN.md Phase 7 Files):
## `godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd`
##
## Not headless by design (docs/PLAN.md "Verified engine facts": the
## --headless dummy driver returns a null SubViewport image; only a real GPU
## session under --rendering-driver opengl3 without --headless reads back
## real pixels). Loads every .tres under addons/goshade_turbo/recipes/ and
## sandbox/stacks/, renders each through a SubViewport built the same way
## gst_preview.gd builds its own (Background TextureRect + BackBufferCopy +
## target TextureRect sharing one ShaderMaterial, so a screen-sourced layer
## still reads a real screen texture), reads back the image, and runs
## GSTRenderAssert.check on it. Prints one "RENDER <path> PASS|FAIL <reasons>"
## line per stack, plus whether its generated shader contains TIME. Exits 1
## if any stack fails to load, fails codegen, or fails the render assert.

const RECIPE_DIR: String = "res://addons/goshade_turbo/recipes"
const SANDBOX_DIR: String = "res://sandbox/stacks"
const PREVIEW_IMAGE_PATH: String = "res://addons/goshade_turbo/assets/preview_default.png"
const VIEWPORT_SIZE: Vector2i = Vector2i(128, 128)
const SETTLE_FRAMES: int = 3


func _initialize() -> void:
	var library: GSTLibrary = GSTLibrary.new()
	library.scan()

	var paths: Array[String] = _collect_stack_paths()
	var all_passed: bool = true
	for path: String in paths:
		var passed: bool = await _check_one(path, library)
		if not passed:
			all_passed = false

	print("run_render_checks: %s, %d stack(s) checked" % ["PASS" if all_passed else "FAIL", paths.size()])
	quit(0 if all_passed else 1)


func _collect_stack_paths() -> Array[String]:
	var paths: Array[String] = []
	paths.append_array(_tres_paths_in(RECIPE_DIR))
	paths.append_array(_tres_paths_in(SANDBOX_DIR))
	paths.sort()
	return paths


func _tres_paths_in(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and entry_name.ends_with(".tres"):
			out.append(dir_path.path_join(entry_name))
		entry_name = dir.get_next()
	dir.list_dir_end()
	return out


## Loads `path`, codegens it (GSTExport.build, so the has_TIME check reads the
## same text the export flow would write), builds a fresh SubViewport render
## tree matching gst_preview.gd's own (Background + BackBufferCopy + target
## TextureRect), syncs the material's uniforms through GSTMaterialSync, waits
## SETTLE_FRAMES frames, reads back, and runs GSTRenderAssert.check. Returns
## whether `path` passed. Every failure path still prints one RENDER line so a
## load or codegen failure is as visible as a render failure.
func _check_one(path: String, library: GSTLibrary) -> bool:
	var load_result: Dictionary = GSTStackIO.load(path, library)
	if not load_result["ok"]:
		print("RENDER %s FAIL [\"load: %s\"] has_TIME=false" % [path, load_result["reason"]])
		return false
	var stack: GSTStack = load_result["stack"]

	var codegen_result: GSTCodegenResult = GSTExport.build(stack, library)
	if not codegen_result.ok():
		print("RENDER %s FAIL [\"codegen: %s\"] has_TIME=false" % [path, codegen_result.error])
		return false
	var has_time: bool = codegen_result.code.contains("TIME")

	var preview_image: Texture2D = load(PREVIEW_IMAGE_PATH) as Texture2D
	var material: ShaderMaterial = ShaderMaterial.new()

	var viewport: SubViewport = SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var background: TextureRect = TextureRect.new()
	background.texture = preview_image
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(background)

	var back_buffer_copy: BackBufferCopy = BackBufferCopy.new()
	back_buffer_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	viewport.add_child(back_buffer_copy)

	# Sync before the material reaches a live CanvasItem: a ShaderMaterial
	# assigned with empty shader code never picks up later code edits
	# (docs/EDITOR_SMOKE.md phase 5 run 1).
	var sync_result: GSTCodegenResult = GSTMaterialSync.sync(stack, library, material, &"", Vector2(VIEWPORT_SIZE))
	if not sync_result.ok():
		print("RENDER %s FAIL [\"material sync: %s\"] has_TIME=%s" % [path, sync_result.error, has_time])
		viewport.queue_free()
		return false

	var target: TextureRect = GSTPreviewPresets.build(GSTPreviewPresets.SPRITE, preview_image) as TextureRect
	target.set_anchors_preset(Control.PRESET_FULL_RECT)
	target.material = material
	viewport.add_child(target)

	for i: int in range(SETTLE_FRAMES):
		await process_frame

	var image: Image = viewport.get_texture().get_image()
	var reasons: Array[String] = GSTRenderAssert.check(image)
	var status: String = "PASS" if reasons.is_empty() else "FAIL"
	print("RENDER %s %s %s has_TIME=%s" % [path, status, reasons, has_time])

	viewport.queue_free()
	return reasons.is_empty()
