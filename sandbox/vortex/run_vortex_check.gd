extends SceneTree

## Rendered check for vortex_portal.tscn (needs a GPU session, same rule as
## tests/run_render_checks.gd):
## `godot --path . --rendering-driver opengl3 -s res://sandbox/vortex/run_vortex_check.gd`
## Instantiates the scene, settles, reads back the particle SubViewport and
## the main window, runs GSTRenderAssert on both, confirms the window image
## changes over time (the vortex moves), and saves both readbacks as PNG.

const SCENE: String = "res://sandbox/vortex/vortex_portal.tscn"
const PARTICLES_PNG: String = "res://sandbox/vortex/vortex_particles.png"
const PORTAL_PNG: String = "res://sandbox/vortex/vortex_portal.png"
const SETTLE_FRAMES: int = 30
const MOTION_FRAMES: int = 30


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		print("VORTEX FAIL scene did not load: %s" % SCENE)
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	var sub: SubViewport = scene.get_node("Sub")

	for i: int in range(SETTLE_FRAMES):
		await process_frame

	var particles_img: Image = sub.get_texture().get_image()
	var portal_img: Image = root.get_texture().get_image()
	var portal_region: Image = _crop(portal_img, Rect2i(0, 0, 512, 512))

	for i: int in range(MOTION_FRAMES):
		await process_frame
	var portal_later: Image = _crop(root.get_texture().get_image(), Rect2i(0, 0, 512, 512))

	var ok: bool = true
	ok = _report("particles", GSTRenderAssert.check(particles_img)) and ok
	ok = _report("portal", GSTRenderAssert.check(portal_region)) and ok

	var changed: int = _count_changed(portal_region, portal_later)
	var motion_ok: bool = changed > 0
	print("VORTEX motion %s changed_pixels=%d over %d frames" % ["PASS" if motion_ok else "FAIL", changed, MOTION_FRAMES])
	ok = motion_ok and ok

	ok = _save(particles_img, PARTICLES_PNG) and ok
	ok = _save(portal_region, PORTAL_PNG) and ok

	print("run_vortex_check: %s" % ["PASS" if ok else "FAIL"])
	quit(0 if ok else 1)


func _report(label: String, reasons: Array[String]) -> bool:
	print("VORTEX %s %s %s" % [label, "PASS" if reasons.is_empty() else "FAIL", reasons])
	return reasons.is_empty()


func _crop(image: Image, rect: Rect2i) -> Image:
	if image == null:
		return null
	var clipped: Rect2i = rect.intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	return image.get_region(clipped)


func _count_changed(a: Image, b: Image) -> int:
	if a == null or b == null:
		return 0
	var changed: int = 0
	for y: int in range(0, a.get_height(), 4):
		for x: int in range(0, a.get_width(), 4):
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				changed += 1
	return changed


func _save(image: Image, path: String) -> bool:
	if image == null:
		print("VORTEX FAIL nothing to save for %s" % path)
		return false
	var err: Error = image.save_png(path)
	if err != OK:
		print("VORTEX FAIL save %s: %s" % [path, error_string(err)])
		return false
	print("VORTEX saved %s" % path)
	return true
