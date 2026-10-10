@tool
class_name GSTUniformNames
extends RefCounted

## Single source of every uniform name and group_uniforms token the codegen
## emits.
##
## Slider uniforms: l<id>_<function>_<param>. Coord block uniforms carry no
## function segment: l<id>_scale, l<id>_offset, l<id>_rotation, l<id>_scroll,
## l<id>_warp_strength. Group line per layer: group_uniforms L<pos>_<name>;
## pos is the two-digit zero-padded stack position (0 is bottom), name the
## sanitized label or the function name. Uniform names stay id-based.


## The fragment() local a layer's value is stored in: l<id>.
static func local_var(layer_id: StringName) -> String:
	return "l%s" % String(layer_id)


## The generator coord local for a layer: coord<id>.
static func coord_var(layer_id: StringName) -> String:
	return "coord%s" % String(layer_id)


## A slider uniform: l<id>_<function>_<param>.
static func param_uniform(layer_id: StringName, function_name: String, param_name: String) -> String:
	return "l%s_%s_%s" % [String(layer_id), function_name, param_name]


static func coord_scale(layer_id: StringName) -> String:
	return "l%s_scale" % String(layer_id)


static func coord_offset(layer_id: StringName) -> String:
	return "l%s_offset" % String(layer_id)


static func coord_rotation(layer_id: StringName) -> String:
	return "l%s_rotation" % String(layer_id)


static func coord_scroll(layer_id: StringName) -> String:
	return "l%s_scroll" % String(layer_id)


static func coord_warp_strength(layer_id: StringName) -> String:
	return "l%s_warp_strength" % String(layer_id)


## The amount uniform of a linked param: l<id>_<function>_<param>_amount
## (decision 29, base plus amount emit form).
static func param_amount_uniform(layer_id: StringName, function_name: String, param_name: String) -> String:
	return "%s_amount" % param_uniform(layer_id, function_name, param_name)


## group_uniforms L<pos>_<name>; pos is the two-digit zero-padded index in
## Stack.layers (0 is bottom). A bare numeric group name does not compile,
## so the position is joined with the name into one identifier. The name is
## the sanitized layer label, or the function name when the label sanitizes
## to empty (decision 25, amends decision 7's group rule).
static func group_line(stack_position: int, function_name: String, label: String = "") -> String:
	var name: String = sanitize_label(label)
	if name.is_empty():
		name = function_name
	return "group_uniforms L%02d_%s;" % [stack_position, name]


## Reduces a user label to [A-Za-z0-9_] for a group_uniforms identifier
## (decision 25): each run of other characters, underscores included,
## becomes one "_", and leading and trailing "_" are dropped. Collapsing
## keeps "__" out of the identifier, which GLSL reserves.
static func sanitize_label(label: String) -> String:
	var result: String = ""
	var pending_separator: bool = false
	for i: int in range(label.length()):
		var c: String = label[i]
		var is_alnum: bool = (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")
		if not is_alnum:
			pending_separator = true
			continue
		if pending_separator and not result.is_empty():
			result += "_"
		pending_separator = false
		result += c
	return result
