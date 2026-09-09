extends SceneTree

## GPU regression for recipes whose clamped gradients formerly became flat.
## Run with a real renderer: godot --path . -s res://tests/run_recipe_motion_checks.gd

const SIZE: Vector2i = Vector2i(128, 128)
var _library: GSTLibrary
var _viewport: SubViewport
var _material: ShaderMaterial
var _failed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_library = GSTLibrary.new()
	_library.scan()
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_material = ShaderMaterial.new()
	_material.shader = Shader.new()
	_material.shader.code = "shader_type canvas_item; void fragment() { COLOR = texture(TEXTURE, UV); }"
	var target: Control = GSTPreviewPresets.build(GSTPreviewPresets.SPRITE, load("res://addons/goshade_turbo/assets/preview_default.png"))
	target.set_anchors_preset(Control.PRESET_FULL_RECT)
	target.material = _material
	_viewport.add_child(target)
	for recipe: String in ["sprite_foil", "sprite_opal"]:
		var loaded: Dictionary = GSTStackIO.load("res://addons/goshade_turbo/recipes/%s.tres" % recipe, _library)
		if not loaded["ok"]:
			_check(false, recipe + " load", str(loaded))
			continue
		var stack: GSTStack = loaded["stack"]
		var gradient: GSTLayer = GSTStackOps.find_layer(stack, &"1")
		for time: float in [1.0, 30.0, 120.0]:
			var baseline: Image = await _render(stack, time)
			var render_errors: Array[String] = GSTRenderAssert.check(baseline)
			_check(render_errors.is_empty(), recipe + " rendered", "time=%s errors=%s" % [time, render_errors])
			var repeat: Image = await _render(stack, time)
			_check(_difference(baseline, repeat) <= 0.00001, recipe + " deterministic", "time=%s" % time)
			var later: Image = await _render(stack, time + 0.5)
			var motion: float = _difference(baseline, later)
			_check(motion > 0.0005, recipe + " motion", "time=%s mean_rgb_delta=%f" % [time, motion])
			var position: Vector2 = gradient.coord.offset
			gradient.coord.offset.x += 0.2
			var moved: Image = await _render(stack, time)
			gradient.coord.offset = position
			var response: float = _difference(baseline, moved)
			_check(response > 0.001, recipe + " gradient_position", "time=%s mean_rgb_delta=%f" % [time, response])
			if recipe == "sprite_opal":
				gradient.params["radius"] = 0.65
				var resized: Image = await _render(stack, time)
				gradient.params.erase("radius")
				var radius_response: float = _difference(baseline, resized)
				_check(radius_response > 0.001, recipe + " gradient_radius", "time=%s mean_rgb_delta=%f" % [time, radius_response])
			var capture_dir: String = OS.get_environment("GST_RECIPE_MOTION_CAPTURE")
			if not capture_dir.is_empty():
				_check(baseline.save_png(capture_dir.path_join("%s-%ds.png" % [recipe, int(time)])) == OK, recipe + " capture", str(time))
	print("RECIPE_MOTION SUMMARY %s" % ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)


func _render(stack: GSTStack, time: float) -> Image:
	var result: GSTCodegenResult = GSTMaterialSync.sync(stack, _library, _material, &"", Vector2(SIZE))
	if not result.ok():
		_check(false, "compile", result.error)
		return null
	_material.shader.code = result.code.replace("TIME", "%.3f" % time)
	for frame: int in range(4):
		await process_frame
	return _viewport.get_texture().get_image()


func _difference(first: Image, second: Image) -> float:
	if first == null or second == null:
		return 0.0
	var total: float = 0.0
	for y: int in range(SIZE.y):
		for x: int in range(SIZE.x):
			var a: Color = first.get_pixel(x, y)
			var b: Color = second.get_pixel(x, y)
			total += (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
	return total / float(SIZE.x * SIZE.y)


func _check(ok: bool, check_name: String, detail: String) -> void:
	print("RECIPE_MOTION %s %s %s" % [check_name, "PASS" if ok else "FAIL", detail])
	_failed = _failed or not ok
