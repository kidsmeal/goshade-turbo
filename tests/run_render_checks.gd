extends SceneTree

## Named verification command:
## `godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd`
##
## Not headless: the --headless dummy driver returns a null SubViewport
## image. Loads every .tres under addons/goshade_turbo/recipes/ and
## sandbox/stacks/, renders each through GSTPreview, reads back the
## transparent target image, and runs GSTRenderAssert.check on it. Prints one
## "RENDER <path> PASS|FAIL <reasons>" line per stack, plus whether its
## generated shader contains TIME. Exits 1 if any stack fails to load, fails
## codegen, or fails the render assert. Also checks the shipped simplex field
## for discontinuities on the active renderer; run Forward+, Mobile, and
## Compatibility to cover shader backends.
##
## --write-screenshots, passed as a user arg (`-- --write-screenshots`, read
## via OS.get_cmdline_user_args()), also saves every stack's rendered image
## to sandbox/screenshots/<stack file stem>.png. A failed directory create
## prints one RENDER FAIL line and fails the run; a per-stack Image.save_png
## failure is appended to that stack's reasons and fails it.

const RECIPE_DIR: String = "res://addons/goshade_turbo/recipes"
const SANDBOX_DIR: String = "res://sandbox/stacks"
const SCREENSHOT_DIR: String = "res://sandbox/screenshots"
const PREVIEW_IMAGE_PATH: String = "res://addons/goshade_turbo/assets/preview_default.png"
const VIEWPORT_SIZE: Vector2i = Vector2i(128, 128)
const SETTLE_FRAMES: int = 3
const WRITE_SCREENSHOTS_ARG: String = "--write-screenshots"

const SOURCE_IMAGE_STACK_PATH: String = "res://sandbox/stacks/ref_source_image.tres"
const PARAM_LINK_STACK_PATH: String = "res://sandbox/stacks/ref_param_link.tres"

## Two fully-opaque, distinctly-colored interior points of
## preview_default.png (0..1 UV): the yellow circle and the pink/magenta
## circle, each measured ~70 pixels from its own shape edge so GPU texture
## filtering cannot shift the sample across a color boundary.
const SOURCE_IMAGE_SAMPLE_POINTS: Array[Vector2] = [Vector2(0.25, 0.25), Vector2(0.75, 0.75)]
const SOURCE_IMAGE_SAMPLE_TOLERANCE: float = 0.08

## The param_links entry name ref_param_link.tres's linker layer carries.
const PARAM_LINK_PARAM_NAME: String = "radius"
const PARAM_LINK_MIN_LEFT_RIGHT_DELTA: float = 0.2
const PARAM_LINK_EQUAL_TOLERANCE: float = 0.004


## On Godot 4.4/4.6 the docs/TESTING.md --import prerequisite leaves
## .recovery_mode_lock in the user data dir (the editor removes it 1s after
## its first filesystem scan; --import quits before that; 4.7 removes it in
## Main::cleanup()). This script never passes --editor or --import, so it
## only removes the stale lock, at start and before quit.
func _remove_stale_recovery_lock() -> void:
	var lock_path: String = OS.get_user_data_dir().path_join(".recovery_mode_lock")
	if FileAccess.file_exists(lock_path):
		DirAccess.remove_absolute(lock_path)
		print("removed stale %s (Godot's --import prerequisite leaves this on 4.4/4.6; see docs/TESTING.md)" % lock_path)


func _initialize() -> void:
	_remove_stale_recovery_lock()
	call_deferred("_run")


func _run() -> void:
	var library: GSTLibrary = GSTLibrary.new()
	library.scan()

	var write_screenshots: bool = OS.get_cmdline_user_args().has(WRITE_SCREENSHOTS_ARG)
	var all_passed: bool = true
	# A failed screenshot-directory create disables screenshot writing for
	# every stack below but does not skip the render/codegen checks.
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
	if not await _check_source_image(library):
		all_passed = false
	if not await _check_param_link(library):
		all_passed = false

	print("run_render_checks: %s, %d stack(s) checked" % ["PASS" if all_passed else "FAIL", paths.size()])
	_remove_stale_recovery_lock()
	quit(0 if all_passed else 1)


## GSTPreview keeps its checkerboard outside the transparent render target,
## so the target retains real alpha while texture and screen sources still
## sample the selected preview image exactly.
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
	# Compare that parent-viewport result to the nested target's premultiplied
	# readback over the checker-only parent frame.
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
		# BackBufferCopy result, then require GSTPreview to blend that sampled
		# RGBA once over its transparent target.
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
	# Sample cell interiors from both checker colors; borders are excluded so
	# the assertion measures container blending, not control clipping.
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


## Checks the shipped noise for discontinuities at lattice boundaries on
## the active GPU renderer.
func _check_noise_continuity(library: GSTLibrary) -> bool:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = "shader_type canvas_item;\n" + library.get_entry("generative/hash").code + library.get_entry("generative/snoise").code + "\nvoid fragment() { float n = snoise((UV - vec2(0.5)) * 8.0); COLOR = vec4(vec3(n), 1.0); }"
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
	# snoise returns 0..1, shown directly.
	# At 1/64 coordinate units per pixel the smooth field stays below 0.04;
	# the discontinuous Forward+ path measured above 0.61. The range check
	# stops blank output from passing as continuous.
	var passed: bool = maximum_delta < 0.1 and maximum_value - minimum_value > 0.5
	print("NOISE_CONTINUITY %s renderer=%s max_adjacent=%f range=%f" % ["PASS" if passed else "FAIL", RenderingServer.get_current_rendering_method(), maximum_delta, maximum_value - minimum_value])
	viewport.queue_free()
	return passed


## Loads the checked-in `ref_source_image.tres` (not a rebuilt equivalent, so
## a broken `image` ExtResource in the file itself would fail this) and
## confirms its own GLSL sampler (`_source_body_lines` in gst_codegen.gd)
## actually reads the asset, by comparing the render against an independent
## CPU read of the same file.
func _check_source_image(library: GSTLibrary) -> bool:
	var load_result: Dictionary = GSTStackIO.load(SOURCE_IMAGE_STACK_PATH, library)
	if not load_result["ok"]:
		print("SOURCE_IMAGE FAIL [\"load: %s\"]" % load_result["reason"])
		return false

	var result: Dictionary = await _render_stack_image(load_result["stack"], library)
	if not result["ok"]:
		print("SOURCE_IMAGE FAIL [\"%s\"]" % result["reason"])
		return false

	var source_texture: Texture2D = load(PREVIEW_IMAGE_PATH) as Texture2D
	var source_image: Image = source_texture.get_image() if source_texture != null else null
	var reasons: Array[String] = GSTRenderAssert.check_matches_source_at(result["image"], source_image, SOURCE_IMAGE_SAMPLE_POINTS, SOURCE_IMAGE_SAMPLE_TOLERANCE)
	print("SOURCE_IMAGE %s %s" % ["PASS" if reasons.is_empty() else "FAIL", reasons])
	return reasons.is_empty()


## The layer carrying a non-empty `param_links` dict, or null. Used to find
## `ref_param_link.tres`'s linker layer (`generative/radial_gradient`)
## without hardcoding its id.
func _find_linked_layer(stack: GSTStack) -> GSTLayer:
	for layer: GSTLayer in stack.layers:
		if not layer.param_links.is_empty():
			return layer
	return null


## Loads the checked-in `ref_param_link.tres` three independent times
## (GSTStackIO.load uses CACHE_MODE_IGNORE, so each call returns its own
## layer instances, not shared state) and renders it three ways: as checked
## in (linked, amount 1.0, must show a left-right difference the unlinked
## render does not), with the linked layer's amount forced to 0, and with
## its link erased entirely. Then checks amount 0 against unlinked pixel for
## pixel (decision 29: "amount 0 is identical to unlinked"). Loading the
## file itself, rather than rebuilding its shape in code, means a
## `param_links` entry that fails to round-trip through the .tres would fail
## this check.
func _check_param_link(library: GSTLibrary) -> bool:
	var linked_load: Dictionary = GSTStackIO.load(PARAM_LINK_STACK_PATH, library)
	var amount_zero_load: Dictionary = GSTStackIO.load(PARAM_LINK_STACK_PATH, library)
	var unlinked_load: Dictionary = GSTStackIO.load(PARAM_LINK_STACK_PATH, library)

	var load_failures: Array[String] = []
	for load_result: Dictionary in [linked_load, amount_zero_load, unlinked_load]:
		if not load_result["ok"]:
			load_failures.append("load: %s" % load_result["reason"])
	if not load_failures.is_empty():
		print("PARAM_LINK_EFFECT FAIL %s" % [load_failures])
		print("PARAM_LINK_AMOUNT_ZERO FAIL %s" % [load_failures])
		return false

	var amount_zero_linker: GSTLayer = _find_linked_layer(amount_zero_load["stack"])
	var unlinked_linker: GSTLayer = _find_linked_layer(unlinked_load["stack"])
	if amount_zero_linker == null or unlinked_linker == null:
		var reason: String = "%s has no layer with a param_links entry" % PARAM_LINK_STACK_PATH
		print("PARAM_LINK_EFFECT FAIL [\"%s\"]" % reason)
		print("PARAM_LINK_AMOUNT_ZERO FAIL [\"%s\"]" % reason)
		return false
	(amount_zero_linker.param_links[PARAM_LINK_PARAM_NAME] as Dictionary)["amount"] = 0.0
	unlinked_linker.param_links.erase(PARAM_LINK_PARAM_NAME)

	var linked_result: Dictionary = await _render_stack_image(linked_load["stack"], library)
	var amount_zero_result: Dictionary = await _render_stack_image(amount_zero_load["stack"], library)
	var unlinked_result: Dictionary = await _render_stack_image(unlinked_load["stack"], library)

	var render_failures: Array[String] = []
	for result: Dictionary in [linked_result, amount_zero_result, unlinked_result]:
		if not result["ok"]:
			render_failures.append(result["reason"])
	if not render_failures.is_empty():
		print("PARAM_LINK_EFFECT FAIL %s" % [render_failures])
		print("PARAM_LINK_AMOUNT_ZERO FAIL %s" % [render_failures])
		return false

	var delta: float = GSTRenderAssert.left_right_mean_delta(linked_result["image"])
	var effect_passed: bool = absf(delta) >= PARAM_LINK_MIN_LEFT_RIGHT_DELTA
	print("PARAM_LINK_EFFECT %s left_right_delta=%f minimum=%f" % ["PASS" if effect_passed else "FAIL", delta, PARAM_LINK_MIN_LEFT_RIGHT_DELTA])

	var equal_reasons: Array[String] = GSTRenderAssert.check_images_equal(amount_zero_result["image"], unlinked_result["image"], PARAM_LINK_EQUAL_TOLERANCE)
	print("PARAM_LINK_AMOUNT_ZERO %s %s" % ["PASS" if equal_reasons.is_empty() else "FAIL", equal_reasons])

	return effect_passed and equal_reasons.is_empty()


## Shared by `_check_one`, `_check_source_image` and `_check_param_link`:
## codegens `stack`, syncs it to a fresh material, renders it through a
## throwaway GSTPreview at VIEWPORT_SIZE, and reads back the result.
func _render_stack_image(stack: GSTStack, library: GSTLibrary) -> Dictionary:
	var codegen_result: GSTCodegenResult = GSTExport.build(stack, library)
	if not codegen_result.ok():
		return {"ok": false, "reason": "codegen: %s" % codegen_result.error, "image": null, "code": ""}

	var material: ShaderMaterial = ShaderMaterial.new()
	var sync_result: GSTCodegenResult = GSTMaterialSync.sync(stack, library, material, &"", Vector2(VIEWPORT_SIZE))
	if not sync_result.ok():
		return {"ok": false, "reason": "material sync: %s" % sync_result.error, "image": null, "code": codegen_result.code}

	var preview_image: Texture2D = load(PREVIEW_IMAGE_PATH) as Texture2D
	var preview: GSTPreview = GSTPreview.new()
	preview.size = Vector2(VIEWPORT_SIZE)
	root.add_child(preview)
	preview.set_image(preview_image)
	preview.set_preset(GSTPreviewPresets.SPRITE)
	preview.set_shader_material(material)

	for i: int in range(SETTLE_FRAMES):
		await process_frame

	var image: Image = preview.get_viewport_image()
	preview.queue_free()
	await process_frame
	return {"ok": true, "reason": "", "image": image, "code": codegen_result.code}


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


## Loads `path`, then renders it through `_render_stack_image` (codegen,
## material sync, a throwaway GSTPreview, readback) and runs
## GSTRenderAssert.check on the result. Returns whether `path` passed. Every
## failure path prints one RENDER line, naming has_TIME=false when codegen
## never ran. When `write_screenshots` is true the image is saved to
## SCREENSHOT_DIR before the assert result is decided, so a failing stack's
## image is on disk.
func _check_one(path: String, library: GSTLibrary, write_screenshots: bool) -> bool:
	var load_result: Dictionary = GSTStackIO.load(path, library)
	if not load_result["ok"]:
		print("RENDER %s FAIL [\"load: %s\"] has_TIME=false" % [path, load_result["reason"]])
		return false

	var render_result: Dictionary = await _render_stack_image(load_result["stack"], library)
	var has_time: bool = String(render_result.get("code", "")).contains("TIME")
	if not render_result["ok"]:
		print("RENDER %s FAIL [\"%s\"] has_TIME=%s" % [path, render_result["reason"], has_time])
		return false

	var image: Image = render_result["image"]
	var reasons: Array[String] = GSTRenderAssert.check(image)
	if write_screenshots and image != null:
		var screenshot_path: String = "%s/%s.png" % [SCREENSHOT_DIR, path.get_file().get_basename()]
		var save_err: Error = image.save_png(screenshot_path)
		if save_err != OK:
			reasons.append("screenshot save %s: %s" % [screenshot_path, error_string(save_err)])

	var status: String = "PASS" if reasons.is_empty() else "FAIL"
	print("RENDER %s %s %s has_TIME=%s" % [path, status, reasons, has_time])
	return reasons.is_empty()
