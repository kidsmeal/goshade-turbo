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
## MIT permission notice, emitted once in the export header when any included
## entry's source_code_license is MIT. The license requires it in every copy
## alongside the copyright lines.
const MIT_PERMISSION_NOTICE: Array[String] = [
	"Permission is hereby granted, free of charge, to any person obtaining a copy",
	"of this software and associated documentation files (the \"Software\"), to deal",
	"in the Software without restriction, including without limitation the rights",
	"to use, copy, modify, merge, publish, distribute, sublicense, and/or sell",
	"copies of the Software, and to permit persons to whom the Software is",
	"furnished to do so, subject to the following conditions:",
	"",
	"The above copyright notice and this permission notice shall be included in all",
	"copies or substantial portions of the Software.",
	"",
	"THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR",
	"IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,",
	"FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE",
	"AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER",
	"LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,",
	"OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE",
	"SOFTWARE.",
]

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

	for header_line: String in _header_lines(stack, library):
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


## Generator line, third-party notices, then the one-line stack header.
## gst_header.gd produces the header line, so the on-the-wire JSON schema
## lives in one file. The export carries no license of its own: the stack is
## the user's work. Each included entry with a non-empty source_code_license
## contributes one "// <id> (<function>): <license>" line, and the MIT
## permission notice follows once when any of those licenses is MIT. All of
## it sits above the "// stack:" line, outside the body GSTOverwriteCheck
## compares, so exports from older versions do not read as hand-edited.
static func _header_lines(stack: GSTStack, library: GSTLibrary) -> Array[String]:
	var lines: Array[String] = ["// Generated by GoShade Turbo."]
	var has_mit: bool = false
	for entry: GSTManifestEntry in _include_order(stack, library):
		if entry.source_code_license.is_empty():
			continue
		lines.append("// %s (%s): %s" % [entry.id, entry.function, entry.source_code_license])
		has_mit = has_mit or entry.source_code_license.begins_with("MIT")
	if has_mit:
		for notice_line: String in MIT_PERMISSION_NOTICE:
			lines.append("//" if notice_line.is_empty() else "// " + notice_line)
	lines.append(GSTHeader.header_line(stack))
	return lines


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


## True when any slot, warp assignment, param link target (decision 29),
## bypassed operator passthrough (decision 26), or output alpha mode converts
## a color layer to a field through luminance, so _luma_function must be
## declared. Structural, not a text scan, so it does not depend on
## fragment() having been generated yet. A bypassed layer's slots and links
## still count; an unused luma declaration compiles.
static func _stack_needs_luma(stack: GSTStack, library: GSTLibrary) -> bool:
	for layer: GSTLayer in stack.layers:
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		if entry != null:
			for param: Dictionary in entry.params:
				var link: Dictionary = _param_link(layer, param)
				if link.is_empty():
					continue
				var link_target: GSTLayer = GSTStackOps.find_layer(stack, StringName(String(link["target"])))
				if link_target != null and link_target.kind_out == GSTLayer.Kind.COLOR:
					return true
		if layer.coord != null:
			for target_id: StringName in [layer.coord.warp_x, layer.coord.warp_y]:
				var target_layer: GSTLayer = GSTStackOps.find_layer(stack, target_id)
				if target_layer != null and target_layer.kind_out == GSTLayer.Kind.COLOR:
					return true
			continue
		if entry == null or entry.samples_source:
			continue
		if _is_bypassed(layer, entry) and entry.kind_out == GSTLayer.Kind.FIELD:
			var passthrough_target: GSTLayer = GSTStackOps.find_layer(stack, layer.slots.get(_bypass_input(entry)["name"], &""))
			if passthrough_target != null and passthrough_target.kind_out == GSTLayer.Kind.COLOR:
				return true
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
## carries any uniform, stack order (group position = stack index). The
## group name carries the layer label (decision 25). A bypassed layer still
## emits its uniforms (decision 26).
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
		lines.append(GSTUniformNames.group_line(i, entry.function, layer.label))
		for layer_line: String in layer_lines:
			lines.append(layer_line)
	return lines


## A linked param keeps its own uniform as the slider base and gains an
## amount uniform right after it in the same group (decision 29, base plus
## amount emit form, the open marker's recommendation).
static func _layer_uniform_lines(layer: GSTLayer, entry: GSTManifestEntry) -> Array[String]:
	var lines: Array[String] = []
	if layer.coord != null:
		for coord_line: String in _coord_uniform_lines(layer):
			lines.append(coord_line)
	for param: Dictionary in entry.params:
		lines.append(_param_uniform_line(layer, entry.function, param))
		var link: Dictionary = _param_link(layer, param)
		if not link.is_empty():
			lines.append("uniform float %s : hint_range(-1.0, 1.0) = %s;" % [
				GSTUniformNames.param_amount_uniform(layer.id, entry.function, param["name"]),
				_glsl_float(float(link.get("amount", 1.0))),
			])
	return lines


## The param_links entry for `param` when the param is linkable (int or
## float, decision 29) and linked, else {}. A link on a color, vec3 or
## texture param is ignored.
static func _param_link(layer: GSTLayer, param: Dictionary) -> Dictionary:
	var param_type: String = param["type"]
	if param_type != "float" and param_type != "int":
		return {}
	var link: Variant = layer.param_links.get(String(param["name"]), null)
	if not (link is Dictionary) or String((link as Dictionary).get("target", "")) == "":
		return {}
	return link


## The value a layer's call or filter template reads for `param`: its
## uniform, or for a linked param the base plus amount expression
## clamp(base + (l<target> - 0.5) * amount * (max - min), min, max), wrapped
## in int(round(...)) for an int param (decision 29). A color target reads
## through luma (decision 2). Amount 0 reduces to the base.
static func _param_arg(stack: GSTStack, layer: GSTLayer, function_name: String, param: Dictionary) -> String:
	var param_name: String = param["name"]
	var base: String = GSTUniformNames.param_uniform(layer.id, function_name, param_name)
	var link: Dictionary = _param_link(layer, param)
	if link.is_empty():
		return base
	var target_id: StringName = StringName(String(link["target"]))
	var target_value: String = GSTUniformNames.local_var(target_id)
	var target_layer: GSTLayer = GSTStackOps.find_layer(stack, target_id)
	if target_layer != null and target_layer.kind_out == GSTLayer.Kind.COLOR:
		target_value = "luma(%s)" % target_value
	var is_int: bool = param["type"] == "int"
	var min_literal: String = _glsl_float(float(param["min"]))
	var max_literal: String = _glsl_float(float(param["max"]))
	var expression: String = "clamp(%s + (%s - %s) * %s * (%s - %s), %s, %s)" % [
		"float(%s)" % base if is_int else base,
		target_value,
		_glsl_float(0.5),
		GSTUniformNames.param_amount_uniform(layer.id, function_name, param_name),
		max_literal, min_literal, min_literal, max_literal,
	]
	return "int(round(%s))" % expression if is_int else expression


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
## meaningful per channel on a color-like triple (palette's a/b/c/d). A
## texture is a sampler2D with no default and no hint_range (decision 27);
## the preview binds its Texture2D with set_shader_parameter. An unset
## sampler reads transparent through hint_default_transparent (owner
## recommendation on the open unset-hint marker, applied in T-0099).
static func _param_uniform_line(layer: GSTLayer, function_name: String, param: Dictionary) -> String:
	var param_name: String = param["name"]
	var param_type: String = param["type"]
	var uniform_name: String = GSTUniformNames.param_uniform(layer.id, function_name, param_name)
	if GSTManifestEntry.is_texture_param(param):
		return "uniform sampler2D %s : source_color, filter_linear, repeat_enable, hint_default_transparent;" % uniform_name
	var value: Variant = layer.params.get(param_name, param["default"])
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


## Branches on bypass before kind dispatch (decision 26).
static func _layer_body_lines(layer: GSTLayer, library: GSTLibrary, stack: GSTStack, codegen_result: GSTCodegenResult) -> Array[String]:
	var entry: GSTManifestEntry = library.get_entry(layer.entry)
	if entry == null:
		return []
	if _is_bypassed(layer, entry):
		if entry.samples_source:
			return _bypassed_filter_body_lines(layer, entry, library, stack, codegen_result)
		return _bypassed_operator_body_lines(layer, entry, stack)
	# Sources route before generators: source/image carries a coord block but
	# has no function to call (decision 28).
	if entry.is_source():
		return _source_body_lines(entry, layer, stack)
	if layer.coord != null:
		return _generator_body_lines(layer, entry, stack)
	if entry.samples_source:
		return _filter_body_lines(layer, entry, library, stack, codegen_result)
	return _operator_body_lines(layer, entry, stack)


## True for a disabled layer that can be bypassed. Generators, sources and
## every layer with no inputs refuse bypass (decision 26), so a disabled
## flag on one of them, e.g. from a hand-edited header, emits the layer
## unchanged.
static func _is_bypassed(layer: GSTLayer, entry: GSTManifestEntry) -> bool:
	return not layer.enabled and layer.coord == null and not entry.is_source() and not entry.inputs.is_empty()


## The input a bypassed operator passes through: the first input of the
## entry's own kind, else the first input (decision 26).
static func _bypass_input(entry: GSTManifestEntry) -> Dictionary:
	for input: Dictionary in entry.inputs:
		if int(input["kind"]) == entry.kind_out:
			return input
	return entry.inputs[0]


## A bypassed operator assigns its pass-through input to its local:
## l<id> = <input>, converted to the entry's kind via decision 2 when the
## wired layer differs in kind. An unwired input passes the fallback
## constant of the entry's kind.
static func _bypassed_operator_body_lines(layer: GSTLayer, entry: GSTManifestEntry, stack: GSTStack) -> Array[String]:
	var is_color: bool = entry.kind_out == GSTLayer.Kind.COLOR
	var target_id: StringName = layer.slots.get(_bypass_input(entry)["name"], &"")
	var value: String = FALLBACK_COLOR_CONSTANT if is_color else FALLBACK_FIELD_CONSTANT
	if target_id != &"":
		value = _converted_local(stack, target_id, entry.kind_out)
	return ["\t%s %s = %s;" % ["vec4" if is_color else "float", GSTUniformNames.local_var(layer.id), value]]


## A bypassed filter emits its source sampled unchanged at the filter's
## GST_UV mapping (decision 26): UV, SCREEN_UV, or coord<src> for a
## source/image source (decision 28). An unresolved source sets the same
## error as _filter_body_lines.
static func _bypassed_filter_body_lines(layer: GSTLayer, entry: GSTManifestEntry, library: GSTLibrary, stack: GSTStack, codegen_result: GSTCodegenResult) -> Array[String]:
	var target_layer: GSTLayer = _filter_source_layer(layer, entry, stack, codegen_result)
	if target_layer == null:
		return []
	var mapping: Dictionary = _filter_sample_mapping(target_layer, library)
	return ["\tvec4 %s = texture(%s, %s);" % [
		GSTUniformNames.local_var(layer.id), mapping["sampler"], mapping["uv"],
	]]


static func _generator_body_lines(layer: GSTLayer, entry: GSTManifestEntry, stack: GSTStack) -> Array[String]:
	var lines: Array[String] = _coord_block_lines(layer, stack)
	var coord_var: String = GSTUniformNames.coord_var(layer.id)
	var args: Array[String] = [coord_var]
	for param: Dictionary in entry.params:
		args.append(_param_arg(stack, layer, entry.function, param))
	var glsl_type: String = "vec4" if entry.kind_out == GSTLayer.Kind.COLOR else "float"
	lines.append("\t%s %s = %s(%s);" % [glsl_type, GSTUniformNames.local_var(layer.id), entry.function, ", ".join(args)])
	return lines


## The `coord<id>` transform, scroll and warp lines of a layer with a coord
## block. Shared by generators and source/image (decision 28).
static func _coord_block_lines(layer: GSTLayer, stack: GSTStack) -> Array[String]:
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
	return lines


static func _warp_arg(stack: GSTStack, target_id: StringName) -> String:
	if target_id == &"":
		return "0.0"
	var local: String = GSTUniformNames.local_var(target_id)
	var target: GSTLayer = GSTStackOps.find_layer(stack, target_id)
	return "luma(%s)" % local if target != null and target.kind_out == GSTLayer.Kind.COLOR else local


## Sources have no function body: codegen reads the sampler directly.
## "texture" reads at the stack's coordinate space; "screen" always reads
## SCREEN_UV, independent of coord_space. "image" emits its coord block, then
## samples its own `image` uniform at `coord<id>` (decision 28).
static func _source_body_lines(entry: GSTManifestEntry, layer: GSTLayer, stack: GSTStack) -> Array[String]:
	var local: String = GSTUniformNames.local_var(layer.id)
	if entry.id == "source/screen":
		return ["\tvec4 %s = texture(gst_screen_texture, SCREEN_UV);" % local]
	if entry.id == "source/image":
		var lines: Array[String] = _coord_block_lines(layer, stack)
		lines.append("\tvec4 %s = texture(%s, %s);" % [
			local,
			GSTUniformNames.param_uniform(layer.id, entry.function, "image"),
			GSTUniformNames.coord_var(layer.id),
		])
		return lines
	return ["\tvec4 %s = texture(TEXTURE, space_coord);" % local]


## Filter calling convention: filters cannot be GLSL functions (TEXTURE
## cannot cross a function-call boundary). A filter's `code` is an inline
## body template, expanded here into a `{ }` block inside fragment(), one
## block per filter layer so two filter layers never collide on the
## template's locals (token list in gst_manifest_entry.gd's samples_source
## comment).
##
## An unwired slot, or one whose target is not a source layer
## (GSTStackOps.is_source_layer), is not silently sampled as TEXTURE:
## assign_slot refuses most such assignments, but remove_layer's reset can
## still leave a samples_source slot empty when no source remains below. That
## case sets an invocation-local error naming the filter layer and its entry
## on `codegen_result` and emits no lines for this layer.
static func _filter_body_lines(layer: GSTLayer, entry: GSTManifestEntry, library: GSTLibrary, stack: GSTStack, codegen_result: GSTCodegenResult) -> Array[String]:
	var target_layer: GSTLayer = _filter_source_layer(layer, entry, stack, codegen_result)
	if target_layer == null:
		return []
	var mapping: Dictionary = _filter_sample_mapping(target_layer, library)
	var out_var: String = GSTUniformNames.local_var(layer.id)

	var expanded: String = _expand_filter_template(entry, layer, stack, mapping["sampler"], mapping["uv"], out_var, codegen_result)
	if not codegen_result.error.is_empty():
		return []

	var lines: Array[String] = []
	lines.append("\tvec4 %s;" % out_var)
	lines.append("\t{")
	for template_line: String in expanded.strip_edges(false, true).split("\n"):
		lines.append("\t\t%s" % template_line if not template_line.is_empty() else "")
	lines.append("\t}")
	return lines


## The source layer (GSTStackOps.is_source_layer: source/texture,
## source/screen or source/image, decision 28) wired to a filter's
## samples_source slot, or null after setting the unresolved-source error on
## `codegen_result`. Shared by the normal and the bypassed filter body.
static func _filter_source_layer(layer: GSTLayer, entry: GSTManifestEntry, stack: GSTStack, codegen_result: GSTCodegenResult) -> GSTLayer:
	var input: Dictionary = entry.inputs[0]
	var target_id: StringName = layer.slots.get(input["name"], &"")
	if not GSTStackOps.is_source_layer(stack, target_id):
		codegen_result.error = "filter layer %s (entry %s) has no resolved texture, screen or image source wired to its %s slot" % [String(layer.id), entry.id, input["name"]]
		return null
	return GSTStackOps.find_layer(stack, target_id)


## The `{sampler, uv}` a filter's GST_SAMPLE and GST_UV map to for its
## source layer (decisions 21, 28): gst_screen_texture at SCREEN_UV for
## source/screen, the layer's own `image` uniform at coord<src> for
## source/image, TEXTURE at UV for source/texture.
static func _filter_sample_mapping(source_layer: GSTLayer, library: GSTLibrary) -> Dictionary:
	if source_layer.entry == "source/screen":
		return {"sampler": "gst_screen_texture", "uv": "SCREEN_UV"}
	if source_layer.entry == "source/image":
		return {
			"sampler": GSTUniformNames.param_uniform(source_layer.id, library.get_entry(source_layer.entry).function, "image"),
			"uv": GSTUniformNames.coord_var(source_layer.id),
		}
	return {"sampler": "TEXTURE", "uv": "UV"}


## GST_SAMPLE( and GST_PARAM( take a balanced parenthesized argument, found
## by a scanner rather than a regex so a nested paren in the argument (e.g.
## GST_SAMPLE(uv + vec2(x, y))) does not break the match. GST_PARAM maps
## through _param_arg, so a linked filter param reads the link expression
## (decision 29). An unknown param name keeps the plain uniform form.
static func _expand_filter_template(entry: GSTManifestEntry, layer: GSTLayer, stack: GSTStack, sample_tex: String, uv_source: String, out_var: String, codegen_result: GSTCodegenResult) -> String:
	var body: String = entry.code
	var sample_mapper: Callable = func(arg: String) -> String:
		return "texture(%s, %s)" % [sample_tex, arg]
	body = _expand_balanced_calls(body, "GST_SAMPLE(", sample_mapper, codegen_result)
	if not codegen_result.error.is_empty():
		return ""
	var param_mapper: Callable = func(arg: String) -> String:
		var param_name: String = arg.strip_edges()
		for param: Dictionary in entry.params:
			if String(param["name"]) == param_name:
				return _param_arg(stack, layer, entry.function, param)
		return GSTUniformNames.param_uniform(layer.id, entry.function, param_name)
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
		args.append(_param_arg(stack, layer, entry.function, param))
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
	return _converted_local(stack, target_id, expected_kind)


## A layer's local read as `expected_kind` (decision 2): as is for the same
## kind, vec4(vec3(l), 1.0) for field to color, luma(l) for color to field.
## A missing target reads as the expected kind.
static func _converted_local(stack: GSTStack, target_id: StringName, expected_kind: int) -> String:
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
