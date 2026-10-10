@tool
class_name GSTRenderAssert
extends RefCounted

## Per-pixel readback assertions for a rendered check: no NaN or inf
## pixels, alpha within [0, 1], output not uniformly one value. Every pixel
## of `image` is sampled; a rendered check runs once per stack, so the full
## scan is affordable.


## Every reason `image` fails the rendered check, or an empty array when it
## passes. `image == null` (the --headless dummy driver's readback failure)
## is reported as its own reason.
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


## Every reason `image` fails to match `source_image` at each UV point in
## `points` (0..1 in both axes), or an empty array when every point matches
## within `tolerance`. `source/image` samples its texture at the same UV the
## layer's own coord block reports, so a correct render reads the asset
## itself at any point, not just "looks non-uniform".
static func check_matches_source_at(image: Image, source_image: Image, points: Array[Vector2], tolerance: float) -> Array[String]:
	var reasons: Array[String] = []
	if image == null or image.is_empty():
		reasons.append("image is null (readback failed)")
		return reasons
	if source_image == null or source_image.is_empty():
		reasons.append("source image is null (asset load failed)")
		return reasons
	for point: Vector2 in points:
		var rendered: Color = _sample_normalized(image, point)
		var source: Color = _sample_normalized(source_image, point)
		# GSTPreview reads back a transparent SubViewport, which stores
		# premultiplied alpha (run_render_checks.gd's
		# _check_preview_composition documents the same convention).
		var expected: Color = Color(source.r * source.a, source.g * source.a, source.b * source.a, source.a)
		if not _colors_close(rendered, expected, tolerance):
			reasons.append("sample at uv=%s rendered=%s expected=%s" % [point, rendered, expected])
	return reasons


## The pixel of `image` at normalized `uv` (0..1 in both axes), clamped to
## the image bounds.
static func _sample_normalized(image: Image, uv: Vector2) -> Color:
	var x: int = clampi(int(uv.x * image.get_width()), 0, image.get_width() - 1)
	var y: int = clampi(int(uv.y * image.get_height()), 0, image.get_height() - 1)
	return image.get_pixel(x, y)


static func _colors_close(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) <= tolerance and absf(a.g - b.g) <= tolerance and absf(a.b - b.b) <= tolerance and absf(a.a - b.a) <= tolerance


## Mean RGB value of the left half of `image` minus the mean RGB value of
## the right half. Used to measure a param link's spatial effect: the link
## target in `ref_param_link.tres` is a left-to-right field, so a working
## link reads as a large-magnitude delta.
static func left_right_mean_delta(image: Image) -> float:
	if image == null or image.is_empty():
		return 0.0
	var width: int = image.get_width()
	var height: int = image.get_height()
	var half: int = width / 2
	var left_sum: float = 0.0
	var right_sum: float = 0.0
	for y: int in range(height):
		for x: int in range(half):
			left_sum += _mean_channel(image.get_pixel(x, y))
		for x: int in range(half, width):
			right_sum += _mean_channel(image.get_pixel(x, y))
	var left_mean: float = left_sum / float(half * height)
	var right_mean: float = right_sum / float((width - half) * height)
	return right_mean - left_mean


static func _mean_channel(c: Color) -> float:
	return (c.r + c.g + c.b) / 3.0


## Every reason `image_a` differs from `image_b` by more than `tolerance`
## per channel at any pixel, or an empty array when every pixel matches.
## Used to prove a param link at amount 0 renders identically to the same
## stack unlinked (decision 29: "amount 0 is identical to unlinked").
static func check_images_equal(image_a: Image, image_b: Image, tolerance: float) -> Array[String]:
	var reasons: Array[String] = []
	if image_a == null or image_a.is_empty() or image_b == null or image_b.is_empty():
		reasons.append("one image is null or empty (readback failed)")
		return reasons
	if image_a.get_size() != image_b.get_size():
		reasons.append("image sizes differ: %s vs %s" % [image_a.get_size(), image_b.get_size()])
		return reasons
	var mismatch_count: int = 0
	var max_delta: float = 0.0
	for y: int in range(image_a.get_height()):
		for x: int in range(image_a.get_width()):
			var a: Color = image_a.get_pixel(x, y)
			var b: Color = image_b.get_pixel(x, y)
			if not _colors_close(a, b, tolerance):
				mismatch_count += 1
				max_delta = maxf(max_delta, maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a))))
	if mismatch_count > 0:
		reasons.append("%d pixel(s) differ, max_delta=%f" % [mismatch_count, max_delta])
	return reasons
