extends SceneTree

## Renders sandbox/logo/logo.tscn and saves the logo as a transparent PNG
## (needs a GPU session, same rule as tests/run_render_checks.gd):
## `godot --path . --rendering-driver opengl3 -s res://sandbox/logo/run_logo_check.gd`
## Reads back the Out SubViewport, crops to the alpha bounding box plus a
## margin, runs GSTRenderAssert, asserts the four corners are fully
## transparent, downsamples by SUPERSAMPLE (the outline filter is a hard
## step, so the 2048 render is the anti-aliasing) and writes
## sandbox/logo/goshade_turbo_logo.png.

const SCENE: String = "res://sandbox/logo/logo.tscn"
const PNG_OUT: String = "res://sandbox/logo/goshade_turbo_logo.png"
const SETTLE_FRAMES: int = 20
const MARGIN: int = 48
const SUPERSAMPLE: int = 2


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		_fail("scene did not load: %s" % SCENE)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	var out: SubViewport = scene.get_node("Out")

	for i: int in range(SETTLE_FRAMES):
		await process_frame

	var image: Image = out.get_texture().get_image()
	if image == null:
		_fail("Out readback is null")
		return
	var bbox: Rect2i = image.get_used_rect()
	if bbox.size == Vector2i.ZERO:
		_fail("Out is fully transparent (no text rendered)")
		return
	var crop: Rect2i = bbox.grow(MARGIN).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var logo: Image = image.get_region(crop)

	var ok: bool = true
	var reasons: Array[String] = GSTRenderAssert.check(logo)
	print("LOGO render %s %s" % ["PASS" if reasons.is_empty() else "FAIL", reasons])
	ok = reasons.is_empty() and ok

	var w: int = logo.get_width()
	var h: int = logo.get_height()
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]
	var corners_clear: bool = true
	for c: Vector2i in corners:
		if logo.get_pixelv(c).a > 0.0:
			corners_clear = false
	print("LOGO corners %s size=%dx%d bbox=%s" % ["PASS" if corners_clear else "FAIL", w, h, bbox])
	ok = corners_clear and ok

	logo.resize(w / SUPERSAMPLE, h / SUPERSAMPLE, Image.INTERPOLATE_LANCZOS)
	var err: Error = logo.save_png(PNG_OUT)
	if err != OK:
		_fail("save %s: %s" % [PNG_OUT, error_string(err)])
		return
	print("LOGO saved %s %dx%d" % [PNG_OUT, logo.get_width(), logo.get_height()])
	print("run_logo_check: %s" % ["PASS" if ok else "FAIL"])
	quit(0 if ok else 1)


func _fail(reason: String) -> void:
	print("LOGO FAIL %s" % reason)
	quit(1)
