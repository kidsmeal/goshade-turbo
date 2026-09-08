@tool
class_name GSTUniformNames
extends RefCounted

## Single source of every uniform name and group_uniforms token the codegen
## emits. Design: docs/DESIGN.md, decision 7. Naming resolved at planning,
## docs/PLAN.md Blockers B3 (group token) and B4 (uniform names).
##
## Slider uniforms: l<id>_<function>_<param>. Coord block uniforms carry no
## function segment: l<id>_scale, l<id>_offset, l<id>_rotation, l<id>_scroll,
## l<id>_warp_strength. Group line per layer: group_uniforms L<pos>_<function>;
## with pos the two-digit zero-padded stack position (0 is bottom).


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


## group_uniforms L<pos>_<function>; pos is the two-digit zero-padded stack
## position (index in Stack.layers, 0 is bottom). A bare numeric position
## does not compile (docs/PLAN.md Blocker B3, verified); it must be part of
## one identifier with the function name.
static func group_line(stack_position: int, function_name: String) -> String:
	return "group_uniforms L%02d_%s;" % [stack_position, function_name]
