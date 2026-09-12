extends SceneTree

## Builds sandbox/logo/logo_stack.tres (first run, or `-- --rebuild`) and
## exports it as the self-contained sandbox/logo/logo.gdshader that the
## Out/Logo sprite in logo.tscn uses:
## `godot --headless --path . -s res://sandbox/logo/export_logo.gd`
## The .tres is the source of truth: tune it in the GoShade panel (or Export
## from the panel directly, same result). `--rebuild` discards panel edits
## and rewrites the .tres from the stack defined in _build_stack below.

const STACK_OUT: String = "res://sandbox/logo/logo_stack.tres"
const SHADER_OUT: String = "res://sandbox/logo/logo.gdshader"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var library: GSTLibrary = GSTLibrary.new()
	library.scan()
	var rebuild: bool = OS.get_cmdline_user_args().has("--rebuild") or not FileAccess.file_exists(STACK_OUT)
	var stack: GSTStack
	if rebuild:
		stack = _build_stack()
		for layer: GSTLayer in stack.layers:
			layer.manifest = library.get_entry(layer.entry)
			if layer.manifest == null:
				_fail("unknown entry %s" % layer.entry)
				return
		var saved: Dictionary = GSTStackIO.save(stack, STACK_OUT)
		if not saved["ok"]:
			_fail("save stack: %s" % saved["reason"])
			return
	else:
		var loaded: Dictionary = GSTStackIO.load(STACK_OUT, library)
		if not loaded["ok"]:
			_fail("load %s: %s" % [STACK_OUT, loaded["reason"]])
			return
		stack = loaded["stack"]

	var result: Dictionary = GSTExport.write(stack, library, SHADER_OUT, true)
	if not result["ok"]:
		_fail("export: %s" % result["reason"])
		return
	print("EXPORT PASS %s -> %s (%s)" % [STACK_OUT, SHADER_OUT, "rebuilt" if rebuild else "from .tres"])
	quit(0)


## Chrome band through the letters (vertical ramp warped by scrolling
## simplex noise, mapped through a cosine palette), CRT scanlines multiplied
## on top, a dark outline around the alpha edge. Output alpha is
## max(text alpha, outline) so the outline survives outside the glyphs.
func _build_stack() -> GSTStack:
	var s: GSTStack = GSTStack.new()
	var src: GSTLayer = GSTStackOps.add_layer(s, "source/texture", GSTLayer.Kind.COLOR)

	var noise: GSTLayer = GSTStackOps.add_layer(s, "generative/snoise", GSTLayer.Kind.FIELD, true)
	noise.coord.scale = Vector2(3.0, 3.0)
	noise.coord.scroll = Vector2(0.15, 0.05)

	# linear_gradient ramps along coord x; rotation -PI/2 maps UV y onto it,
	# scale 2 with offset -1 puts 0 at UV y 0.25 and 1 at UV y 0.75.
	var ramp: GSTLayer = GSTStackOps.add_layer(s, "generative/linear_gradient", GSTLayer.Kind.FIELD, true)
	ramp.coord.scale = Vector2(2.0, 2.0)
	ramp.coord.rotation = -PI / 2.0
	ramp.coord.offset = Vector2(-1.0, 0.0)
	ramp.coord.warp_x = noise.id
	ramp.coord.warp_strength = 0.12

	var palette: GSTLayer = GSTStackOps.add_layer(s, "color/palette", GSTLayer.Kind.COLOR)
	palette.slots["t"] = ramp.id
	palette.params = {
		# Green at the top, cyan mid, blue at the bottom (fitted 2026-09-11).
		"a": Vector3(0.15, 0.71, 0.65),
		"b": Vector3(0.52, 0.49, 0.16),
		"c": Vector3(0.92, 0.37, 0.83),
		"d": Vector3(0.82, 0.09, 0.48),
	}

	var stripes: GSTLayer = GSTStackOps.add_layer(s, "generative/stripes", GSTLayer.Kind.FIELD, true)
	stripes.coord.scale = Vector2(48.0, 48.0)
	stripes.coord.rotation = -PI / 2.0

	var scan: GSTLayer = GSTStackOps.add_layer(s, "color/gradient_map", GSTLayer.Kind.COLOR)
	scan.slots["t"] = stripes.id
	scan.params = {"color_a": Color(0.6, 0.6, 0.65, 1.0), "color_b": Color(1, 1, 1, 1)}

	var shaded: GSTLayer = GSTStackOps.add_layer(s, "color/multiply", GSTLayer.Kind.COLOR)
	shaded.slots["a"] = palette.id
	shaded.slots["b"] = scan.id
	shaded.params = {"t": 0.5}

	var outline: GSTLayer = GSTStackOps.add_layer(s, "filter/outline", GSTLayer.Kind.COLOR)
	outline.slots["source"] = src.id
	outline.params = {"thickness": 0.006, "threshold": 0.1}

	var rim: GSTLayer = GSTStackOps.add_layer(s, "color/fill", GSTLayer.Kind.COLOR)
	rim.params = {"color": Color(0.02, 0.05, 0.12, 1.0)}

	var composed: GSTLayer = GSTStackOps.add_layer(s, "color/mix", GSTLayer.Kind.COLOR)
	composed.slots["a"] = shaded.id
	composed.slots["b"] = rim.id
	composed.slots["mask"] = outline.id

	var text_alpha: GSTLayer = GSTStackOps.add_layer(s, "fieldops/alpha", GSTLayer.Kind.FIELD)
	text_alpha.slots["color"] = src.id

	var out_alpha: GSTLayer = GSTStackOps.add_layer(s, "fieldops/max", GSTLayer.Kind.FIELD)
	out_alpha.slots["a"] = text_alpha.id
	out_alpha.slots["b"] = outline.id

	s.output_color = composed.id
	s.output_alpha = out_alpha.id
	return s


func _fail(reason: String) -> void:
	print("EXPORT FAIL %s" % reason)
	quit(1)
