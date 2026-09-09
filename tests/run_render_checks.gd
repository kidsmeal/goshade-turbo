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
## Also checks the shipped simplex field for discontinuities on the active
## renderer; run Forward+, Mobile, and Compatibility to cover shader backends.
##
## --write-screenshots (docs/PLAN.md Phase 8 Files): when passed as a user
## arg (`-- --write-screenshots`, read via OS.get_cmdline_user_args() so it
## survives Godot's own `--` argument split), every stack's rendered image is
## additionally saved to sandbox/screenshots/<stack file stem>.png, so the
## committed screenshots are this harness's own output rather than a
## hand-exported copy. A failed sandbox/screenshots directory create prints
## one RENDER FAIL line naming the directory and fails the run (fix pass 3,
## item 4); a per-stack Image.save_png failure is appended to that stack's
## own reasons list, so the stack's RENDER line reports FAIL and the run
## exits 1 the same as a failed render assert.

const RECIPE_DIR: String = "res://addons/goshade_turbo/recipes"
const SANDBOX_DIR: String = "res://sandbox/stacks"
const SCREENSHOT_DIR: String = "res://sandbox/screenshots"
const PREVIEW_IMAGE_PATH: String = "res://addons/goshade_turbo/assets/preview_default.png"
const VIEWPORT_SIZE: Vector2i = Vector2i(128, 128)
const SETTLE_FRAMES: int = 3
const WRITE_SCREENSHOTS_ARG: String = "--write-screenshots"


func _initialize() -> void:
	var library: GSTLibrary = GSTLibrary.new()
	library.scan()

	var write_screenshots: bool = OS.get_cmdline_user_args().has(WRITE_SCREENSHOTS_ARG)
	var all_passed: bool = true
	# A failed screenshot-directory create disables screenshot writing for
	# every stack below (the directory will not exist for any of them
	# either), but does not skip the render/codegen checks themselves.
	var screenshot_dir_ok: bool = true
	if write_screenshots:
		var screenshot_dir_absolute: String = ProjectSettings.globalize_path(SCREENSHOT_DIR)
		var make_dir_err: Error = DirAccess.make_dir_recursive_absolute(screenshot_dir_absolute)
		if make_dir_err != OK:
			print("RENDER %s FAIL [\"screenshot dir: %s\"] has_TIME=false" % [SCREENSHOT_DIR, error_string(make_dir_err)])
			all_passed = false
			screenshot_dir_ok = false

	var paths: Array[String] = _collect_stack_paths()
	for path: String in paths:
		var passed: bool = await _check_one(path, library, write_screenshots and screenshot_dir_ok)
		if not passed:
			all_passed = false
	if not await _check_noise_continuity(library):
		all_passed = false

	print("run_render_checks: %s, %d stack(s) checked" % ["PASS" if all_passed else "FAIL", paths.size()])
	quit(0 if all_passed else 1)


## Nonuniform recipe images can still contain discontinuities at lattice
## boundaries. Exercise the shipped noise on the active GPU renderer.
func _check_noise_continuity(library: GSTLibrary) -> bool:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = "shader_type canvas_item;\n" + library.get_entry("generative/hash").code + library.get_entry("generative/snoise").code + "\nvoid fragment() { float n = snoise((UV - vec2(0.5)) * 8.0); COLOR = vec4(vec3(n * 0.5 + 0.5), 1.0); }"
	var target: ColorRect = ColorRect.new()
	target.set_anchors_preset(Control.PRESET_FULL_RECT)
	target.material = material
	viewport.add_child(target)
	for frame: int in range(5):
		await process_frame
	var image: Image = viewport.get_texture().get_image()
	if image == null or image.is_empty():
		print("NOISE_CONTINUITY FAIL: missing GPU readback")
		viewport.queue_free()
		return false
	var maximum_delta: float = 0.0
	var minimum_value: float = 1.0
	var maximum_value: float = 0.0
	for y: int in range(image.get_height() - 1):
		for x: int in range(image.get_width() - 1):
			var value: float = image.get_pixel(x, y).r
			minimum_value = minf(minimum_value, value)
			maximum_value = maxf(maximum_value, value)
			maximum_delta = maxf(maximum_delta, absf(value - image.get_pixel(x + 1, y).r))
			maximum_delta = maxf(maximum_delta, absf(value - image.get_pixel(x, y + 1).r))
	# At 1/64 coordinate units per pixel the smooth field stays below 0.04
	# on the reference GPU. The broken Forward+ path jumps above 0.61.
	# The range check prevents blank output from passing as continuous.
	var passed: bool = maximum_delta < 0.1 and maximum_value - minimum_value > 0.5
	print("NOISE_CONTINUITY %s renderer=%s max_adjacent=%f range=%f" % ["PASS" if passed else "FAIL", RenderingServer.get_current_rendering_method(), maximum_delta, maximum_value - minimum_value])
	viewport.queue_free()
	return passed


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
## load or codegen failure is as visible as a render failure. When
## `write_screenshots` is true and a real image was read back, it is saved to
## SCREENSHOT_DIR before the assert result is decided, so a failing stack's
## image is still on disk to inspect.
func _check_one(path: String, library: GSTLibrary, write_screenshots: bool) -> bool:
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
	if write_screenshots and image != null:
		var screenshot_path: String = "%s/%s.png" % [SCREENSHOT_DIR, path.get_file().get_basename()]
		var save_err: Error = image.save_png(screenshot_path)
		if save_err != OK:
			reasons.append("screenshot save %s: %s" % [screenshot_path, error_string(save_err)])

	var status: String = "PASS" if reasons.is_empty() else "FAIL"
	print("RENDER %s %s %s has_TIME=%s" % [path, status, reasons, has_time])

	viewport.queue_free()
	return reasons.is_empty()
