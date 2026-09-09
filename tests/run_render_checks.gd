extends SceneTree

## Named verification command (docs/PLAN.md Phase 7 Files):
## `godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd`
##
## Not headless by design (docs/PLAN.md "Verified engine facts": the
## --headless dummy driver returns a null SubViewport image; only a real GPU
## session under --rendering-driver opengl3 without --headless reads back
## real pixels). Loads every .tres under addons/goshade_turbo/recipes/ and
## sandbox/stacks/, renders each through the production GSTPreview, reads
## back the transparent target image, and runs
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
	call_deferred("_run")


func _run() -> void:
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
	if not await _check_preview_composition():
		all_passed = false
	if not await _check_noise_continuity(library):
		all_passed = false

	print("run_render_checks: %s, %d stack(s) checked" % ["PASS" if all_passed else "FAIL", paths.size()])
	quit(0 if all_passed else 1)


## GSTPreview keeps its checkerboard outside the transparent render target.
## The target therefore retains real alpha while texture and screen sources
## still sample the selected preview image exactly.
func _check_preview_composition() -> bool:
	var failures: Array[String] = []
	var sample_texture: ImageTexture = _solid_texture(Color(0.2, 0.4, 0.7, 0.75))

	for preset: String in GSTPreviewPresets.PRESET_NAMES:
		for alpha: float in [0.0, 0.5, 1.0]:
			var constant_code: String = "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(0.8, 0.3, 0.1, %.6f); }" % alpha
			var rendered: Dictionary = await _render_preview(constant_code, sample_texture, preset)
			var image: Image = rendered["image"]
			if image == null or image.is_empty():
				failures.append("%s alpha %.1f missing readback" % [preset, alpha])
				continue
			var maximum_alpha: float = _maximum_alpha(image)
			if absf(maximum_alpha - alpha) > 0.04:
				failures.append("%s alpha %.1f read %.4f" % [preset, alpha, maximum_alpha])
			if not rendered["checker_outside"]:
				failures.append("%s checkerboard is not outside the SubViewport" % preset)

	# The editor displays the transparent SubViewport through its container.
	# Compare that real parent-viewport result to the nested target's
	# premultiplied readback over the checker-only parent frame.
	var parent_composite: Dictionary = await _render_parent_composite(sample_texture)
	var composite_mismatch: Dictionary = _parent_composite_mismatch(
		parent_composite["checker"],
		parent_composite["target"],
		parent_composite["actual"],
		0.04
	)
	if int(composite_mismatch["count"]) > 0:
		failures.append("parent composite mismatches=%d/%d max_delta=%.4f" % [composite_mismatch["count"], composite_mismatch["total"], composite_mismatch["max_delta"]])

	var texture_code: String = "shader_type canvas_item;\nvoid fragment() { COLOR = texture(TEXTURE, UV); }"
	var screen_code: String = "shader_type canvas_item;\nuniform sampler2D gst_screen_texture : hint_screen_texture, repeat_disable, filter_nearest;\nvoid fragment() { COLOR = textureLod(gst_screen_texture, SCREEN_UV, 0.0); }"
	for source_alpha: float in [0.0, 0.75, 1.0]:
		var source_color: Color = Color(0.2, 0.4, 0.7, source_alpha)
		var source_texture: ImageTexture = _solid_texture(source_color)
		var expected_texture_readback: Color = Color(source_color.r * source_alpha, source_color.g * source_alpha, source_color.b * source_alpha, source_alpha)
		var texture_render: Dictionary = await _render_preview(texture_code, source_texture, GSTPreviewPresets.SPRITE)
		var texture_image: Image = texture_render["image"]
		if texture_image == null or texture_image.is_empty() or not _colors_close(_center_pixel(texture_image), expected_texture_readback, 0.03):
			failures.append("texture source alpha %.2f center=%s expected=%s" % [source_alpha, _center_pixel(texture_image), expected_texture_readback])

		# Screen-texture alpha differs by renderer. Measure the engine's native
		# BackBufferCopy result, then require GSTPreview to blend that exact
		# sampled RGBA once over its transparent target.
		var native_screen_image: Image = await _render_native_screen_copy(source_texture)
		var native_screen: Color = _center_pixel(native_screen_image)
		var native_has_source_rgb: bool = native_screen_image != null and not native_screen_image.is_empty() and _rgb_close(native_screen, source_color, 0.03)
		if not native_has_source_rgb:
			failures.append("native screen source alpha %.2f center=%s source_rgb=%s" % [source_alpha, native_screen, source_color])
		var expected_screen_readback: Color = Color(native_screen.r * native_screen.a, native_screen.g * native_screen.a, native_screen.b * native_screen.a, native_screen.a)
		var screen_render: Dictionary = await _render_preview(screen_code, source_texture, GSTPreviewPresets.FULL_RECT)
		var screen_image: Image = screen_render["image"]
		if screen_image == null or screen_image.is_empty() or not _colors_close(_center_pixel(screen_image), expected_screen_readback, 0.03):
			failures.append("screen source alpha %.2f center=%s native=%s expected=%s" % [source_alpha, _center_pixel(screen_image), native_screen, expected_screen_readback])
		print("PREVIEW_SCREEN_BASELINE source_alpha=%.2f native=%s preview=%s" % [source_alpha, native_screen, _center_pixel(screen_image)])

	print("PREVIEW_COMPOSITION %s %s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	return failures.is_empty()


func _render_preview(shader_code: String, texture: Texture2D, preset: String) -> Dictionary:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = shader_code
	var preview: GSTPreview = GSTPreview.new()
	preview.size = Vector2(VIEWPORT_SIZE)
	root.add_child(preview)
	preview.set_image(texture)
	preview.set_preset(preset)
	preview.set_shader_material(material)
	var checker_outside: bool = preview.get_child_count() >= 2 and preview.get_child(0) is ColorRect and preview.get_child(1) is SubViewportContainer
	for frame: int in range(5):
		await process_frame
	var image: Image = preview.get_viewport_image()
	preview.queue_free()
	await process_frame
	return {"image": image, "checker_outside": checker_outside}


func _render_parent_composite(texture: Texture2D) -> Dictionary:
	var parent_viewport: SubViewport = SubViewport.new()
	parent_viewport.size = VIEWPORT_SIZE
	parent_viewport.transparent_bg = true
	parent_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(parent_viewport)

	var preview: GSTPreview = GSTPreview.new()
	preview.size = Vector2(VIEWPORT_SIZE)
	parent_viewport.add_child(preview)
	preview.set_image(texture)
	preview.set_preset(GSTPreviewPresets.FULL_RECT)

	var transparent_material: ShaderMaterial = ShaderMaterial.new()
	transparent_material.shader = Shader.new()
	transparent_material.shader.code = "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(0.8, 0.3, 0.1, 0.0); }"
	preview.set_shader_material(transparent_material)
	for frame: int in range(5):
		await process_frame
	var checker_image: Image = parent_viewport.get_texture().get_image()

	var half_material: ShaderMaterial = ShaderMaterial.new()
	half_material.shader = Shader.new()
	half_material.shader.code = "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(0.8, 0.3, 0.1, 0.5); }"
	preview.set_shader_material(half_material)
	for frame: int in range(5):
		await process_frame
	var target_image: Image = preview.get_viewport_image()
	var actual_image: Image = parent_viewport.get_texture().get_image()

	parent_viewport.queue_free()
	await process_frame
	return {"checker": checker_image, "target": target_image, "actual": actual_image}


## Minimal engine reference for hint_screen_texture. The source is written
## with blend disabled, copied, then sampled by another blend-disabled draw.
## No GSTPreview node or transparent-clear pass participates in this result.
func _render_native_screen_copy(texture: Texture2D) -> Image:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var background: TextureRect = TextureRect.new()
	background.texture = texture
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	var background_material: ShaderMaterial = ShaderMaterial.new()
	background_material.shader = Shader.new()
	background_material.shader.code = "shader_type canvas_item;\nrender_mode blend_disabled;\nvoid fragment() { COLOR = texture(TEXTURE, UV); }"
	background.material = background_material
	viewport.add_child(background)

	var copy: BackBufferCopy = BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	viewport.add_child(copy)

	var target: ColorRect = ColorRect.new()
	target.set_anchors_preset(Control.PRESET_FULL_RECT)
	var target_material: ShaderMaterial = ShaderMaterial.new()
	target_material.shader = Shader.new()
	target_material.shader.code = "shader_type canvas_item;\nrender_mode blend_disabled;\nuniform sampler2D native_screen : hint_screen_texture, repeat_disable, filter_nearest;\nvoid fragment() { COLOR = textureLod(native_screen, SCREEN_UV, 0.0); }"
	target.material = target_material
	viewport.add_child(target)

	for frame: int in range(5):
		await process_frame
	var image: Image = viewport.get_texture().get_image()
	viewport.queue_free()
	await process_frame
	return image


func _solid_texture(color: Color) -> ImageTexture:
	var image: Image = Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _maximum_alpha(image: Image) -> float:
	var maximum: float = 0.0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			maximum = maxf(maximum, image.get_pixel(x, y).a)
	return maximum


func _center_pixel(image: Image) -> Color:
	if image == null or image.is_empty():
		return Color.TRANSPARENT
	return image.get_pixel(image.get_width() / 2, image.get_height() / 2)


func _colors_close(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) <= tolerance and absf(a.g - b.g) <= tolerance and absf(a.b - b.b) <= tolerance and absf(a.a - b.a) <= tolerance


func _rgb_close(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) <= tolerance and absf(a.g - b.g) <= tolerance and absf(a.b - b.b) <= tolerance


func _parent_composite_mismatch(checker: Image, target: Image, actual: Image, tolerance: float) -> Dictionary:
	if checker == null or target == null or actual == null or checker.is_empty() or target.is_empty() or actual.is_empty() or checker.get_size() != target.get_size() or checker.get_size() != actual.get_size():
		return {"count": 1, "total": 1, "max_delta": INF}
	var mismatch_count: int = 0
	var sample_count: int = 0
	var maximum_delta: float = 0.0
	# Sample cell interiors from both checker colors. Borders are excluded so
	# the assertion measures container blending rather than control clipping.
	for y: int in range(8, actual.get_height(), 16):
		for x: int in range(8, actual.get_width(), 16):
			var checker_pixel: Color = checker.get_pixel(x, y)
			var target_pixel: Color = target.get_pixel(x, y)
			var actual_pixel: Color = actual.get_pixel(x, y)
			var expected: Color = Color(
				target_pixel.r + checker_pixel.r * (1.0 - target_pixel.a),
				target_pixel.g + checker_pixel.g * (1.0 - target_pixel.a),
				target_pixel.b + checker_pixel.b * (1.0 - target_pixel.a),
				target_pixel.a + checker_pixel.a * (1.0 - target_pixel.a)
			)
			var delta: float = maxf(maxf(absf(actual_pixel.r - expected.r), absf(actual_pixel.g - expected.g)), maxf(absf(actual_pixel.b - expected.b), absf(actual_pixel.a - expected.a)))
			maximum_delta = maxf(maximum_delta, delta)
			sample_count += 1
			if delta > tolerance:
				mismatch_count += 1
	return {"count": mismatch_count, "total": sample_count, "max_delta": maximum_delta}


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
## tree through GSTPreview itself, syncs the material's uniforms through
## GSTMaterialSync, waits
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

	# Sync before the material reaches a live CanvasItem: a ShaderMaterial
	# assigned with empty shader code never picks up later code edits
	# (docs/EDITOR_SMOKE.md phase 5 run 1).
	var sync_result: GSTCodegenResult = GSTMaterialSync.sync(stack, library, material, &"", Vector2(VIEWPORT_SIZE))
	if not sync_result.ok():
		print("RENDER %s FAIL [\"material sync: %s\"] has_TIME=%s" % [path, sync_result.error, has_time])
		return false

	var preview: GSTPreview = GSTPreview.new()
	preview.size = Vector2(VIEWPORT_SIZE)
	root.add_child(preview)
	preview.set_image(preview_image)
	preview.set_preset(GSTPreviewPresets.SPRITE)
	preview.set_shader_material(material)

	for i: int in range(SETTLE_FRAMES):
		await process_frame

	var image: Image = preview.get_viewport_image()
	var reasons: Array[String] = GSTRenderAssert.check(image)
	if write_screenshots and image != null:
		var screenshot_path: String = "%s/%s.png" % [SCREENSHOT_DIR, path.get_file().get_basename()]
		var save_err: Error = image.save_png(screenshot_path)
		if save_err != OK:
			reasons.append("screenshot save %s: %s" % [screenshot_path, error_string(save_err)])

	var status: String = "PASS" if reasons.is_empty() else "FAIL"
	print("RENDER %s %s %s has_TIME=%s" % [path, status, reasons, has_time])

	preview.queue_free()
	return reasons.is_empty()
