@tool
class_name GSTCodegen
extends RefCounted

## Turns a GSTStack into compiling canvas_item shader text.
## Design: docs/DESIGN.md, Codegen rules.
##
## Phase 2 scope: generators and field ops only, so every layer is field
## kind and the output block always wraps a field local as
## vec4(vec3(lN), 1.0) (docs/PLAN.md, Phase 2). Phase 3 modifies this file
## to add color slot conversion, filter emission, and the full four-mode
## output block (decision 12).

## Fed into an unset operator input slot so a single operator compiles
## alone without an upstream layer wiring it (docs/PLAN.md Phase 2 Files:
## "an operator fed constants").
const FALLBACK_FIELD_CONSTANT: String = "0.5"


## Builds the full .gdshader text for `stack`. When `solo_layer_id` is set,
## the output line is replaced by that single field layer instead of
## `stack.output_color` (decision 13, solo preview).
static func generate(stack: GSTStack, library: GSTLibrary, solo_layer_id: StringName = &"") -> String:
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

	var uniform_lines: Array[String] = _uniform_lines(stack, library)
	if not uniform_lines.is_empty():
		for uniform_line: String in uniform_lines:
			lines.append(uniform_line)
		lines.append("")

	if _stack_has_generator(stack):
		for transform_line: String in _gst_transform_function():
			lines.append(transform_line)
		lines.append("")

	for entry: GSTManifestEntry in _include_order(stack, library):
		lines.append(entry.code)

	if is_local:
		for vertex_line: String in _vertex_function():
			lines.append(vertex_line)
		lines.append("")

	for fragment_line: String in _fragment_function(stack, library, solo_layer_id):
		lines.append(fragment_line)

	return "\n".join(lines) + "\n"


## License notice plus the one-line stack header (design decision 8).
static func _header_lines(stack: GSTStack) -> Array[String]:
	return [
		"// GoShade Turbo generated shader. MIT License.",
		"// stack: %s" % _stack_header_json(stack),
	]


## Placeholder for the on-the-wire stack JSON (docs/DESIGN.md decision 8,
## header schema owned by phase 6 / gst_header.gd). One function, one call
## site above, so phase 6 replaces this body without touching the header
## line's format.
static func _stack_header_json(_stack: GSTStack) -> String:
	return "{}"


static func _stack_has_generator(stack: GSTStack) -> bool:
	for layer: GSTLayer in stack.layers:
		if layer.coord != null:
			return true
	return false


## gst_transform is emitted once, whenever any generator exists (design:
## docs/DESIGN.md, Codegen rules; naming resolved docs/PLAN.md Blocker B4).
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


static func _vertex_function() -> Array[String]:
	return [
		"void vertex() {",
		"\tlocal_pos = VERTEX / gst_rect_size;",
		"}",
		"",
	]


## Every manifest entry the stack's layers reach, dependencies first
## (Codegen rules: "Include walk: depth first over depends, dedupe by id").
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
## TIME term are emitted together or not at all (design: Codegen rules,
## "when scroll is zero at export, neither the scroll uniform nor the TIME
## term is emitted"). warp_strength is emitted only when at least one warp
## slot is set, alongside the warp term it drives.
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


static func _param_uniform_line(layer: GSTLayer, function_name: String, param: Dictionary) -> String:
	var param_name: String = param["name"]
	var param_type: String = param["type"]
	var value: Variant = layer.params.get(param_name, param["default"])
	var uniform_name: String = GSTUniformNames.param_uniform(layer.id, function_name, param_name)
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


static func _fragment_function(stack: GSTStack, library: GSTLibrary, solo_layer_id: StringName) -> Array[String]:
	var lines: Array[String] = []
	lines.append("void fragment() {")
	lines.append("\tvec2 space_coord = %s;" % _space_coord_source(stack.coord_space))
	for layer: GSTLayer in stack.layers:
		for body_line: String in _layer_body_lines(layer, library):
			lines.append(body_line)
	lines.append("\t%s" % _output_line(stack, solo_layer_id))
	lines.append("}")
	return lines


## uv reads UV, screen_uv reads SCREEN_UV, local reads the varying set in
## vertex() (design: docs/DESIGN.md decision 11, Codegen rules).
static func _space_coord_source(coord_space: GSTStack.CoordSpace) -> String:
	match coord_space:
		GSTStack.CoordSpace.SCREEN_UV:
			return "SCREEN_UV"
		GSTStack.CoordSpace.LOCAL:
			return "local_pos"
		_:
			return "UV"


static func _layer_body_lines(layer: GSTLayer, library: GSTLibrary) -> Array[String]:
	var entry: GSTManifestEntry = library.get_entry(layer.entry)
	if entry == null:
		return []
	if layer.coord != null:
		return _generator_body_lines(layer, entry)
	return _operator_body_lines(layer, entry)


static func _generator_body_lines(layer: GSTLayer, entry: GSTManifestEntry) -> Array[String]:
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
		var wx: String = GSTUniformNames.local_var(coord.warp_x) if coord.warp_x != &"" else "0.0"
		var wy: String = GSTUniformNames.local_var(coord.warp_y) if coord.warp_y != &"" else "0.0"
		lines.append("\t%s += vec2(%s, %s) * %s;" % [coord_var, wx, wy, GSTUniformNames.coord_warp_strength(layer.id)])
	var args: Array[String] = [coord_var]
	for param: Dictionary in entry.params:
		args.append(GSTUniformNames.param_uniform(layer.id, entry.function, param["name"]))
	lines.append("\tfloat %s = %s(%s);" % [GSTUniformNames.local_var(layer.id), entry.function, ", ".join(args)])
	return lines


static func _operator_body_lines(layer: GSTLayer, entry: GSTManifestEntry) -> Array[String]:
	var args: Array[String] = []
	for input: Dictionary in entry.inputs:
		var input_name: String = input["name"]
		var target_id: StringName = layer.slots.get(input_name, &"")
		if target_id == &"":
			args.append(FALLBACK_FIELD_CONSTANT)
		else:
			args.append(GSTUniformNames.local_var(target_id))
	for param: Dictionary in entry.params:
		args.append(GSTUniformNames.param_uniform(layer.id, entry.function, param["name"]))
	var line: String = "\tfloat %s = %s(%s);" % [GSTUniformNames.local_var(layer.id), entry.function, ", ".join(args)]
	return [line]


## Phase 2 field-only wrap (docs/PLAN.md Phase 2): the output color layer is
## a field, so it wraps as vec4(vec3(lN), 1.0). Full four-mode alpha is
## phase 3. Solo output replaces the target entirely (decision 13).
static func _output_line(stack: GSTStack, solo_layer_id: StringName) -> String:
	var target_id: StringName = solo_layer_id if solo_layer_id != &"" else stack.output_color
	return "COLOR = vec4(vec3(%s), 1.0);" % GSTUniformNames.local_var(target_id)
