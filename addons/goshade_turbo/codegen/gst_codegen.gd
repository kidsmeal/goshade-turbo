@tool
class_name GSTCodegen
extends RefCounted

## Turns a GSTStack into compiling canvas_item shader text: color slot
## conversion, source/filter emission, and the four-mode output block. Field
## outputs use grayscale with the selected alpha expression; color warp
## inputs use luminance.

## Fed into an unset field-kind operator input slot so a single operator
## compiles alone without an upstream layer.
const FALLBACK_FIELD_CONSTANT: String = "0.5"
## Fed into an unset color-kind operator input slot for the same reason.
const FALLBACK_COLOR_CONSTANT: String = "vec4(0.5, 0.5, 0.5, 1.0)"

## Builds the full .gdshader text for `stack`. When `solo_layer_id` is set,
## the output line is replaced by that single layer instead of
## `stack.output_color` (solo preview). Wrapper over generate_result();
## returns "" on a codegen error.
static func generate(stack: GSTStack, library: GSTLibrary, solo_layer_id: StringName = &"") -> String:
	return generate_result(stack, library, solo_layer_id).code


## Same as generate(), but the error (an unknown GST_ token left in a filter
## template after expansion) travels on the returned GSTCodegenResult, so a
## caller can report the reason. Invocation-local: safe for nested calls.
static func generate_result(stack: GSTStack, library: GSTLibrary, solo_layer_id: StringName = &"") -> GSTCodegenResult:
	var result: GSTCodegenResult = GSTCodegenResult.new()
	var lines: Array[String] = []

	for header_line: String in _header_lines(stack):
		lines.append(header_line)
	lines.append("shader_type canvas_item;")
	lines.append("")

	var is_local: bool = stack.coord_space == GSTStack.CoordSpace.LOCAL
	if is_local:
		lines.append("uniform vec2 gst_rect_size = vec2(1.0);")
		lines.append("varying vec2 local_pos;")
		lines.append("")

	if _stack_has_screen_source(stack):
		lines.append("uniform sampler2D gst_screen_texture : hint_screen_texture, filter_linear_mipmap;")
		lines.append("")

	var uniform_lines: Array[String] = _uniform_lines(stack, library)
	if not uniform_lines.is_empty():
		for uniform_line: String in uniform_lines:
			lines.append(uniform_line)
		lines.append("")

	if _stack_has_generator(stack):
		for transform_line: String in _gst_transform_function():
			lines.append(transform_line)
		lines.append("")

	if _stack_needs_luma(stack, library):
		for luma_line: String in _luma_function():
			lines.append(luma_line)
		lines.append("")

	for entry: GSTManifestEntry in _include_order(stack, library):
		# A filter's code is an inline body template expanded per layer inside
		# fragment() by _filter_body_lines. A source entry's code is empty;
		# _source_body_lines reads the built-in directly. Neither is emitted
		# at file scope. Their dependencies (e.g. dither's hash) are separate
		# entries in the walk and still emit normally.
		if entry.samples_source or entry.is_source():
			continue
		if entry.code.is_empty():
			continue
		lines.append(entry.code)

	if is_local:
		for vertex_line: String in _vertex_function():
			lines.append(vertex_line)
		lines.append("")

	for fragment_line: String in _fragment_function(stack, library, solo_layer_id, result):
		lines.append(fragment_line)

	if not result.error.is_empty():
		result.code = ""
		return result
	result.code = "\n".join(lines) + "\n"
	return result


## License notice plus the one-line stack header. gst_header.gd produces the
## header line, so the on-the-wire JSON schema lives in one file.
static func _header_lines(stack: GSTStack) -> Array[String]:
	return [
		"// GoShade Turbo generated shader. MIT License.",
		GSTHeader.header_line(stack),
	]


static func _stack_has_generator(stack: GSTStack) -> bool:
	for layer: GSTLayer in stack.layers:
		if layer.coord != null:
			return true
	return false


## True when any "source/screen" layer exists, whether read directly or
## through a filter's samples_source slot.
static func _stack_has_screen_source(stack: GSTStack) -> bool:
	for layer: GSTLayer in stack.layers:
		if layer.entry == "source/screen":
			return true
	return false


## True when any "source/texture" layer exists (unset-alpha default).
static func _stack_has_texture_source(stack: GSTStack) -> bool:
	for layer: GSTLayer in stack.layers:
		if layer.entry == "source/texture":
			return true
	return false


## True when any slot, warp assignment, or output alpha mode converts a color
## layer to a field through luminance, so _luma_function must be declared.
## Structural, not a text scan, so it does not depend on fragment() having
## been generated yet.
static func _stack_needs_luma(stack: GSTStack, library: GSTLibrary) -> bool:
	for layer: GSTLayer in stack.layers:
		if layer.coord != null:
			for target_id: StringName in [layer.coord.warp_x, layer.coord.warp_y]:
				var target_layer: GSTLayer = GSTStackOps.find_layer(stack, target_id)
				if target_layer != null and target_layer.kind_out == GSTLayer.Kind.COLOR:
					return true
			continue
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		if entry == null or entry.samples_source:
			continue
		for input: Dictionary in entry.inputs:
			if int(input["kind"]) != GSTLayer.Kind.FIELD:
				continue
			var target_id: StringName = layer.slots.get(input["name"], &"")
			if target_id == &"":
				continue
			var target_layer: GSTLayer = GSTStackOps.find_layer(stack, target_id)
			if target_layer != null and target_layer.kind_out == GSTLayer.Kind.COLOR:
				return true
	return _output_alpha_needs_luma(stack)


static func _output_alpha_needs_luma(stack: GSTStack) -> bool:
	var mode: StringName = stack.output_alpha
	if mode == &"" or mode == &"none" or mode == &"texture" or mode == &"color_alpha":
		return false
	var layer: GSTLayer = GSTStackOps.find_layer(stack, mode)
	return layer != null and layer.kind_out == GSTLayer.Kind.COLOR


## gst_transform is emitted once, whenever any generator exists.
static func _gst_transform_function() -> Array[String]:
	return [
		"vec2 gst_transform(vec2 p, vec2 scale, float rotation, vec2 offset) {",
		"\tvec2 scaled = p * scale;",
		"\tfloat s = sin(rotation);",
		"\tfloat c = cos(rotation);",
		"\tvec2 rotated = vec2(scaled.x * c - scaled.y * s, scaled.x * s + scaled.y * c);",
		"\treturn rotated + offset;",
		"}",
		"",
	]


## luma is emitted once, whenever any color-to-field conversion occurs. Rec.
## 601 coefficients.
static func _luma_function() -> Array[String]:
	return [
		"float luma(vec4 c) {",
		"\treturn dot(c.rgb, vec3(0.299, 0.587, 0.114));",
		"}",
		"",
	]


static func _vertex_function() -> Array[String]:
	return [
		"void vertex() {",
		"\tlocal_pos = VERTEX / gst_rect_size;",
		"}",
		"",
	]


## Every manifest entry the stack's layers reach, dependencies first (depth
## first over depends, deduped by id).
static func _include_order(stack: GSTStack, library: GSTLibrary) -> Array[GSTManifestEntry]:
	var root_ids: Array[String] = []
	for layer: GSTLayer in stack.layers:
		if not root_ids.has(layer.entry):
			root_ids.append(layer.entry)
	return GSTIncludeWalk.walk(root_ids, library)


## One group_uniforms line plus its uniform declarations per layer that
## carries any uniform, stack order (group position = stack index).
static func _uniform_lines(stack: GSTStack, library: GSTLibrary) -> Array[String]:
	var lines: Array[String] = []
	for i: int in range(stack.layers.size()):
		var layer: GSTLayer = stack.layers[i]
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		if entry == null:
			continue
		var layer_lines: Array[String] = _layer_uniform_lines(layer, entry)
		if layer_lines.is_empty():
			continue
		lines.append(GSTUniformNames.group_line(i, entry.function))
		for layer_line: String in layer_lines:
			lines.append(layer_line)
	return lines


static func _layer_uniform_lines(layer: GSTLayer, entry: GSTManifestEntry) -> Array[String]:
	var lines: Array[String] = []
	if layer.coord != null:
		for coord_line: String in _coord_uniform_lines(layer):
			lines.append(coord_line)
	for param: Dictionary in entry.params:
		lines.append(_param_uniform_line(layer, entry.function, param))
	return lines


## scale/offset/rotation are always emitted for a generator. scroll and its
## TIME term are emitted together or not at all (zero scroll emits neither).
## warp_strength is emitted only when at least one warp slot is set,
## alongside the warp term it drives.
static func _coord_uniform_lines(layer: GSTLayer) -> Array[String]:
	var coord: GSTCoordBlock = layer.coord
	var lines: Array[String] = []
	lines.append("uniform vec2 %s = vec2(%s, %s);" % [
		GSTUniformNames.coord_scale(layer.id), _glsl_float(coord.scale.x), _glsl_float(coord.scale.y),
	])
	lines.append("uniform vec2 %s = vec2(%s, %s);" % [
		GSTUniformNames.coord_offset(layer.id), _glsl_float(coord.offset.x), _glsl_float(coord.offset.y),
	])
	lines.append("uniform float %s = %s;" % [
		GSTUniformNames.coord_rotation(layer.id), _glsl_float(coord.rotation),
	])
	if coord.scroll != Vector2.ZERO:
		lines.append("uniform vec2 %s = vec2(%s, %s);" % [
			GSTUniformNames.coord_scroll(layer.id), _glsl_float(coord.scroll.x), _glsl_float(coord.scroll.y),
		])
	if coord.warp_x != &"" or coord.warp_y != &"":
		lines.append("uniform float %s = %s;" % [
			GSTUniformNames.coord_warp_strength(layer.id), _glsl_float(coord.warp_strength),
		])
	return lines


## Uniform types: int/float carry hint_range; color carries no range and the
## source_color hint; vec3 carries no range, since a scalar hint_range is not
## meaningful per channel on a color-like triple (palette's a/b/c/d).
static func _param_uniform_line(layer: GSTLayer, function_name: String, param: Dictionary) -> String:
	var param_name: String = param["name"]
	var param_type: String = param["type"]
	var value: Variant = layer.params.get(param_name, param["default"])
	var uniform_name: String = GSTUniformNames.param_uniform(layer.id, function_name, param_name)
	if param_type == "color":
		return "uniform vec4 %s : source_color = %s;" % [uniform_name, _glsl_color4(value)]
	if param_type == "vec3":
		return "uniform vec3 %s = %s;" % [uniform_name, _glsl_vec3(value)]
	var glsl_type: String = "int" if param_type == "int" else "float"
	var min_literal: String = _glsl_number(param["min"], param_type)
	var max_literal: String = _glsl_number(param["max"], param_type)
	var default_literal: String = _glsl_number(value, param_type)
	return "uniform %s %s : hint_range(%s, %s) = %s;" % [glsl_type, uniform_name, min_literal, max_literal, default_literal]


static func _glsl_number(value: Variant, param_type: String) -> String:
	if param_type == "int":
		return str(int(value))
	return _glsl_float(float(value))


static func _glsl_float(value: float) -> String:
	var text: String = str(value)
	if not text.contains(".") and not text.contains("e") and not text.contains("E"):
		text += ".0"
	return text


static func _glsl_color4(value: Variant) -> String:
	var c: Color = value
	return "vec4(%s, %s, %s, %s)" % [_glsl_float(c.r), _glsl_float(c.g), _glsl_float(c.b), _glsl_float(c.a)]


static func _glsl_vec3(value: Variant) -> String:
	var v: Vector3 = value
	return "vec3(%s, %s, %s)" % [_glsl_float(v.x), _glsl_float(v.y), _glsl_float(v.z)]


static func _fragment_function(stack: GSTStack, library: GSTLibrary, solo_layer_id: StringName, codegen_result: GSTCodegenResult) -> Array[String]:
	var lines: Array[String] = []
	lines.append("void fragment() {")
	lines.append("\tvec2 space_coord = %s;" % _space_coord_source(stack.coord_space))
	for layer: GSTLayer in stack.layers:
		for body_line: String in _layer_body_lines(layer, library, stack, codegen_result):
			lines.append(body_line)
	lines.append("\t%s" % _output_line(stack, solo_layer_id))
	lines.append("}")
	return lines


## uv reads UV, screen_uv reads SCREEN_UV, local reads the varying set in
## vertex().
static func _space_coord_source(coord_space: GSTStack.CoordSpace) -> String:
	match coord_space:
		GSTStack.CoordSpace.SCREEN_UV:
			return "SCREEN_UV"
		GSTStack.CoordSpace.LOCAL:
			return "local_pos"
		_:
			return "UV"


static func _layer_body_lines(layer: GSTLayer, library: GSTLibrary, stack: GSTStack, codegen_result: GSTCodegenResult) -> Array[String]:
	var entry: GSTManifestEntry = library.get_entry(layer.entry)
	if entry == null:
		return []
	if layer.coord != null:
		return _generator_body_lines(layer, entry, stack)
	if entry.is_source():
		return _source_body_lines(entry, layer)
	if entry.samples_source:
		return _filter_body_lines(layer, entry, stack, codegen_result)
	return _operator_body_lines(layer, entry, stack)


static func _generator_body_lines(layer: GSTLayer, entry: GSTManifestEntry, stack: GSTStack) -> Array[String]:
	var lines: Array[String] = []
	var coord: GSTCoordBlock = layer.coord
	var coord_var: String = GSTUniformNames.coord_var(layer.id)
	lines.append("\tvec2 %s = gst_transform(space_coord, %s, %s, %s);" % [
		coord_var,
		GSTUniformNames.coord_scale(layer.id),
		GSTUniformNames.coord_rotation(layer.id),
		GSTUniformNames.coord_offset(layer.id),
	])
	if coord.scroll != Vector2.ZERO:
		lines.append("\t%s += %s * TIME;" % [coord_var, GSTUniformNames.coord_scroll(layer.id)])
	if coord.warp_x != &"" or coord.warp_y != &"":
		var wx: String = _warp_arg(stack, coord.warp_x)
		var wy: String = _warp_arg(stack, coord.warp_y)
		lines.append("\t%s += vec2(%s, %s) * %s;" % [coord_var, wx, wy, GSTUniformNames.coord_warp_strength(layer.id)])
	var args: Array[String] = [coord_var]
	for param: Dictionary in entry.params:
		args.append(GSTUniformNames.param_uniform(layer.id, entry.function, param["name"]))
	var glsl_type: String = "vec4" if entry.kind_out == GSTLayer.Kind.COLOR else "float"
	lines.append("\t%s %s = %s(%s);" % [glsl_type, GSTUniformNames.local_var(layer.id), entry.function, ", ".join(args)])
	return lines


static func _warp_arg(stack: GSTStack, target_id: StringName) -> String:
	if target_id == &"":
		return "0.0"
	var local: String = GSTUniformNames.local_var(target_id)
	var target: GSTLayer = GSTStackOps.find_layer(stack, target_id)
	return "luma(%s)" % local if target != null and target.kind_out == GSTLayer.Kind.COLOR else local


## Sources have no function body: codegen reads the built-in directly.
## "texture" reads at the stack's coordinate space; "screen" always reads
## SCREEN_UV, independent of coord_space.
static func _source_body_lines(entry: GSTManifestEntry, layer: GSTLayer) -> Array[String]:
	var local: String = GSTUniformNames.local_var(layer.id)
	if entry.id == "source/screen":
		return ["\tvec4 %s = texture(gst_screen_texture, SCREEN_UV);" % local]
	return ["\tvec4 %s = texture(TEXTURE, space_coord);" % local]


## Filter calling convention: filters cannot be GLSL functions (TEXTURE
## cannot cross a function-call boundary). A filter's `code` is an inline
## body template, expanded here into a `{ }` block inside fragment(), one
## block per filter layer so two filter layers never collide on the
## template's locals (token list in gst_manifest_entry.gd's samples_source
## comment).
##
## An unwired slot, or one whose target is not a "source/texture" or
## "source/screen" layer, is not silently sampled as TEXTURE: assign_slot
## refuses most such assignments, but remove_layer's reset can still leave a
## samples_source slot empty when no source remains below. That case sets an
## invocation-local error naming the filter layer and its entry on
## `codegen_result` and emits no lines for this layer.
static func _filter_body_lines(layer: GSTLayer, entry: GSTManifestEntry, stack: GSTStack, codegen_result: GSTCodegenResult) -> Array[String]:
	var input: Dictionary = entry.inputs[0]
	var target_id: StringName = layer.slots.get(input["name"], &"")
	var target_layer: GSTLayer = GSTStackOps.find_layer(stack, target_id) if target_id != &"" else null
	if target_layer == null or (target_layer.entry != "source/texture" and target_layer.entry != "source/screen"):
		codegen_result.error = "filter layer %s (entry %s) has no resolved texture or screen source wired to its %s slot" % [String(layer.id), entry.id, input["name"]]
		return []
	var is_screen: bool = target_layer.entry == "source/screen"
	var sample_tex: String = "gst_screen_texture" if is_screen else "TEXTURE"
	var uv_source: String = "SCREEN_UV" if is_screen else "UV"
	var out_var: String = GSTUniformNames.local_var(layer.id)

	var expanded: String = _expand_filter_template(entry, layer, sample_tex, uv_source, out_var, codegen_result)
	if not codegen_result.error.is_empty():
		return []

	var lines: Array[String] = []
	lines.append("\tvec4 %s;" % out_var)
	lines.append("\t{")
	for template_line: String in expanded.strip_edges(false, true).split("\n"):
		lines.append("\t\t%s" % template_line if not template_line.is_empty() else "")
	lines.append("\t}")
	return lines


## GST_SAMPLE( and GST_PARAM( take a balanced parenthesized argument, found
## by a scanner rather than a regex so a nested paren in the argument (e.g.
## GST_SAMPLE(uv + vec2(x, y))) does not break the match.
static func _expand_filter_template(entry: GSTManifestEntry, layer: GSTLayer, sample_tex: String, uv_source: String, out_var: String, codegen_result: GSTCodegenResult) -> String:
	var body: String = entry.code
	var sample_mapper: Callable = func(arg: String) -> String:
		return "texture(%s, %s)" % [sample_tex, arg]
	body = _expand_balanced_calls(body, "GST_SAMPLE(", sample_mapper, codegen_result)
	if not codegen_result.error.is_empty():
		return ""
	var param_mapper: Callable = func(arg: String) -> String:
		return GSTUniformNames.param_uniform(layer.id, entry.function, arg.strip_edges())
	body = _expand_balanced_calls(body, "GST_PARAM(", param_mapper, codegen_result)
	if not codegen_result.error.is_empty():
		return ""
	body = body.replace("GST_UV", uv_source)
	body = body.replace("GST_OUT", out_var)

	var stray_idx: int = body.find("GST_")
	if stray_idx != -1:
		codegen_result.error = "unknown token '%s' in filter template (entry %s)" % [_identifier_at(body, stray_idx), entry.id]
		return ""
	return body


static func _expand_balanced_calls(body: String, token: String, mapper: Callable, codegen_result: GSTCodegenResult) -> String:
	var result: String = ""
	var pos: int = 0
	while true:
		var idx: int = body.find(token, pos)
		if idx == -1:
			return result + body.substr(pos)
		result += body.substr(pos, idx - pos)
		var arg_start: int = idx + token.length()
		var depth: int = 1
		var i: int = arg_start
		while i < body.length() and depth > 0:
			var ch: String = body[i]
			if ch == "(":
				depth += 1
			elif ch == ")":
				depth -= 1
			i += 1
		if depth != 0:
			codegen_result.error = "unbalanced parens for %s in filter template" % token
			return ""
		var arg: String = body.substr(arg_start, i - 1 - arg_start)
		result += mapper.call(arg)
		pos = i
	return result


## Used only to name the offending token in a codegen error message.
static func _identifier_at(body: String, idx: int) -> String:
	var end: int = idx
	while end < body.length():
		var c: String = body[end]
		var is_word_char: bool = c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")
		if not is_word_char:
			break
		end += 1
	return body.substr(idx, end - idx)


static func _operator_body_lines(layer: GSTLayer, entry: GSTManifestEntry, stack: GSTStack) -> Array[String]:
	var args: Array[String] = []
	for input: Dictionary in entry.inputs:
		args.append(_slot_arg(stack, layer, input))
	for param: Dictionary in entry.params:
		args.append(GSTUniformNames.param_uniform(layer.id, entry.function, param["name"]))
	var glsl_type: String = "vec4" if entry.kind_out == GSTLayer.Kind.COLOR else "float"
	var line: String = "\t%s %s = %s(%s);" % [glsl_type, GSTUniformNames.local_var(layer.id), entry.function, ", ".join(args)]
	return [line]


## The call argument for one input slot: the wired target's local, wrapped
## across a kind boundary, or a fallback constant of the slot's expected kind
## when unwired.
static func _slot_arg(stack: GSTStack, layer: GSTLayer, input: Dictionary) -> String:
	var input_name: String = input["name"]
	var expected_kind: int = int(input["kind"])
	var target_id: StringName = layer.slots.get(input_name, &"")
	if target_id == &"":
		return FALLBACK_COLOR_CONSTANT if expected_kind == GSTLayer.Kind.COLOR else FALLBACK_FIELD_CONSTANT
	var target_layer: GSTLayer = GSTStackOps.find_layer(stack, target_id)
	var local: String = GSTUniformNames.local_var(target_id)
	var target_kind: int = target_layer.kind_out if target_layer != null else expected_kind
	if target_kind == expected_kind:
		return local
	if expected_kind == GSTLayer.Kind.COLOR:
		return "vec4(vec3(%s), 1.0)" % local
	return "luma(%s)" % local


static func _output_line(stack: GSTStack, solo_layer_id: StringName) -> String:
	if solo_layer_id != &"":
		return _solo_output_line(stack, solo_layer_id)
	return _main_output_line(stack)


## Solo preview replaces the output entirely: a color layer shows as-is, a
## field layer shows grayscale.
static func _solo_output_line(stack: GSTStack, layer_id: StringName) -> String:
	var layer: GSTLayer = GSTStackOps.find_layer(stack, layer_id)
	var local: String = GSTUniformNames.local_var(layer_id)
	if layer != null and layer.kind_out == GSTLayer.Kind.COLOR:
		return "COLOR = vec4(%s.rgb, 1.0);" % local
	return "COLOR = vec4(vec3(%s), 1.0);" % local


## When stack.output_color is unset, defaults to the top (highest stack
## index) color-kind layer. Returns a fixed black opaque line when no color
## layer exists, rather than emitting an undefined GLSL identifier.
static func _main_output_line(stack: GSTStack) -> String:
	var output_id: StringName = stack.output_color if stack.output_color != &"" else _default_color_layer_id(stack)
	if output_id == &"":
		return "COLOR = vec4(0.0, 0.0, 0.0, 1.0);"
	var layer: GSTLayer = GSTStackOps.find_layer(stack, output_id)
	var local: String = GSTUniformNames.local_var(output_id)
	if layer != null and layer.kind_out == GSTLayer.Kind.FIELD:
		return "COLOR = vec4(vec3(%s), %s);" % [local, _alpha_expr(stack)]
	return "COLOR = vec4(%s.rgb, %s);" % [local, _alpha_expr(stack)]


static func _default_color_layer_id(stack: GSTStack) -> StringName:
	for i: int in range(stack.layers.size() - 1, -1, -1):
		var layer: GSTLayer = stack.layers[i]
		if layer.kind_out == GSTLayer.Kind.COLOR:
			return layer.id
	return &""


## Four alpha modes: none -> 1.0, texture -> texture(TEXTURE, UV).a (same
## expression regardless of how many texture layers exist), color_alpha ->
## the output color layer's alpha, a layer id -> that field layer's local, or
## luma(local) when the referenced layer is color kind. An unset mode (&"")
## resolves to texture when the stack has a "source/texture" layer, else
## none; &"none" is always the explicit 1.0.
static func _alpha_expr(stack: GSTStack) -> String:
	var mode: StringName = stack.output_alpha
	if mode == &"":
		mode = &"texture" if _stack_has_texture_source(stack) else &"none"
	if mode == &"none":
		return "1.0"
	if mode == &"texture":
		return "texture(TEXTURE, UV).a"
	if mode == &"color_alpha":
		var color_id: StringName = stack.output_color if stack.output_color != &"" else _default_color_layer_id(stack)
		var color_layer: GSTLayer = GSTStackOps.find_layer(stack, color_id)
		if color_layer != null and color_layer.kind_out == GSTLayer.Kind.FIELD:
			return "1.0"
		return "%s.a" % GSTUniformNames.local_var(color_id)
	var layer: GSTLayer = GSTStackOps.find_layer(stack, mode)
	var local: String = GSTUniformNames.local_var(mode)
	if layer != null and layer.kind_out == GSTLayer.Kind.COLOR:
		return "luma(%s)" % local
	return local
