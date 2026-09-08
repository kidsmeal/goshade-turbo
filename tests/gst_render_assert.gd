@tool
class_name GSTRenderAssert
extends RefCounted

## Per-pixel readback assertions for a rendered check (docs/PLAN.md Phase 7
## Files, design Release checklist: "no NaN or inf pixels, alpha channel
## within [0, 1], output not uniformly one value"). Every pixel of `image` is
## sampled (docs/PLAN.md Phase 7 Build: "sample every pixel of a 128x128
## readback"), not a sparse grid like tests/gst_editor_smoke.gd's own
## _image_is_uniform: a rendered check runs once per recipe/stack, not every
## frame of a live editor session, so the full scan is affordable and catches
## a single bad pixel a sparse sample would miss.


## Every reason `image` fails the rendered check, or an empty array when it
## passes. `image == null` (the --headless dummy driver's own readback
## failure, verified in docs/PLAN.md) is reported as its own reason rather
## than silently passing.
static func check(image: Image) -> Array[String]:
	var reasons: Array[String] = []
	if image == null:
		reasons.append("image is null (readback failed)")
		return reasons

	var width: int = image.get_width()
	var height: int = image.get_height()
	if width == 0 or height == 0:
		reasons.append("image has zero size (%dx%d)" % [width, height])
		return reasons

	var has_nan_or_inf: bool = false
	var has_bad_alpha: bool = false
	var first_pixel: Color = image.get_pixel(0, 0)
	var all_equal: bool = true

	for y: int in range(height):
		for x: int in range(width):
			var pixel: Color = image.get_pixel(x, y)
			if not has_nan_or_inf and _has_nan_or_inf(pixel):
				has_nan_or_inf = true
			if not has_bad_alpha and (pixel.a < 0.0 or pixel.a > 1.0):
				has_bad_alpha = true
			if all_equal and not pixel.is_equal_approx(first_pixel):
				all_equal = false

	if has_nan_or_inf:
		reasons.append("image contains a NaN or inf component")
	if has_bad_alpha:
		reasons.append("image contains an alpha component outside [0, 1]")
	if all_equal:
		reasons.append("image is uniformly one pixel value (%s)" % first_pixel)
	return reasons


static func _has_nan_or_inf(c: Color) -> bool:
	return _bad_component(c.r) or _bad_component(c.g) or _bad_component(c.b) or _bad_component(c.a)


static func _bad_component(value: float) -> bool:
	return is_nan(value) or is_inf(value)
