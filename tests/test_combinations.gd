extends GSTTestBase

## Cross-product compile checks over the roster: every field op with every
## generator as input, every color op with every color entry as input. Each
## test wires one real stack per combination through GSTStackOps and asserts
## GSTShaderCompile.compiles() on the codegen result, reporting the
## combination count in the assertion message.


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


## True when every declared input of `entry` is field-kind. fieldops/alpha's
## sole input is color-kind, so it is excluded from the field-op x generator
## loop; tests/test_codegen_color.gd covers it.
func _all_inputs_field(entry: GSTManifestEntry) -> bool:
	if entry.inputs.is_empty():
		return false
	for input: Dictionary in entry.inputs:
		if int(input["kind"]) != GSTLayer.Kind.FIELD:
			return false
	return true


func _has_color_input(entry: GSTManifestEntry) -> bool:
	for input: Dictionary in entry.inputs:
		if int(input["kind"]) == GSTLayer.Kind.COLOR:
			return true
	return false


## Every non-source entry with coord == true: every generative/* generator
## plus every sdf/* generator. source/image carries a coord block but is a
## color source (decision 28), covered by EXPECTED_COLOR_ENTRY_IDS. New
## entries must be added here on purpose.
const EXPECTED_GENERATOR_IDS: Array[String] = [
	"generative/cell_borders", "generative/cell_borders_edge_warp", "generative/cell_borders_round",
	"generative/cell_borders_round_varied", "generative/cellular_edges", "generative/checker",
	"generative/fbm", "generative/hash", "generative/linear_gradient", "generative/perlin",
	"generative/radial_gradient", "generative/snoise", "generative/stripes",
	"generative/value_noise", "generative/voronoi",
	"sdf/box", "sdf/circle", "sdf/line", "sdf/polygon", "sdf/ring", "sdf/rounded_box", "sdf/star",
]

## Every fieldops/* entry whose inputs are all field-kind (fieldops/alpha
## excluded, color-kind input). New entries must be added here on purpose.
const EXPECTED_FIELD_OP_IDS: Array[String] = [
	"fieldops/abs", "fieldops/add", "fieldops/ease", "fieldops/fract", "fieldops/invert",
	"fieldops/max", "fieldops/min", "fieldops/mix", "fieldops/multiply", "fieldops/pow",
	"fieldops/ratchet", "fieldops/remap", "fieldops/smoothstep",
]

## Every color/* entry with at least one color-kind input (fill has no
## inputs, gradient_map and palette take only a field input). New entries
## must be added here on purpose.
const EXPECTED_COLOR_OP_IDS: Array[String] = [
	"color/add", "color/brightness_contrast", "color/hue_shift", "color/mix",
	"color/multiply", "color/overlay", "color/posterize", "color/saturation",
	"color/screen", "color/soft_light",
]

## Every color-kind entry: the color/* roster, the source/* roster, and every
## filter/* entry (its kind_out is color). New entries must be
## added here on purpose.
const EXPECTED_COLOR_ENTRY_IDS: Array[String] = [
	"color/add", "color/brightness_contrast", "color/fill", "color/gradient_map",
	"color/hue_shift", "color/mix", "color/multiply", "color/overlay", "color/palette",
	"color/posterize", "color/saturation", "color/screen", "color/soft_light",
	"filter/box_blur", "filter/chromatic_split", "filter/dither", "filter/outline", "filter/pixelate",
	"source/image", "source/screen", "source/texture",
]

## sdf/* entries with coord == false. New entries must be added here on
## purpose.
const EXPECTED_SDF_OPERATOR_IDS: Array[String] = [
	"sdf/intersect", "sdf/smooth_union", "sdf/subtract", "sdf/union",
]

## sdf/* entries with coord == true. New entries must be added here on
## purpose.
const EXPECTED_SDF_GENERATOR_IDS: Array[String] = [
	"sdf/box", "sdf/circle", "sdf/line", "sdf/polygon", "sdf/ring", "sdf/rounded_box", "sdf/star",
]


## Every field op with every generator wired into every one of that field
## op's input slots, so a two-input op (e.g. fieldops/max) gets the same
## generator on both "a" and "b". A generator is any non-source entry with
## coord == true.
func test_every_field_op_compiles_with_every_generator_as_input() -> void:
	var lib: GSTLibrary = _scanned_library()
	var generator_ids: Array[String] = []
	var field_op_ids: Array[String] = []
	for id: String in lib.entries.keys():
		var entry: GSTManifestEntry = lib.get_entry(id)
		if entry.coord and not entry.is_source():
			generator_ids.append(id)
		elif id.begins_with("fieldops/") and _all_inputs_field(entry):
			field_op_ids.append(id)
	assert_true(_roster_matches(generator_ids, EXPECTED_GENERATOR_IDS), "generator roster matches expected (%s)" % _roster_diff_message(generator_ids, EXPECTED_GENERATOR_IDS))
	assert_true(_roster_matches(field_op_ids, EXPECTED_FIELD_OP_IDS), "all-field-input field op roster matches expected (%s)" % _roster_diff_message(field_op_ids, EXPECTED_FIELD_OP_IDS))

	var checked: int = 0
	for field_op_id: String in field_op_ids:
		var field_op_entry: GSTManifestEntry = lib.get_entry(field_op_id)
		for generator_id: String in generator_ids:
			var stack: GSTStack = GSTStack.new()
			var generator_layer: GSTLayer = GSTStackOps.add_layer(stack, generator_id, GSTLayer.Kind.FIELD, true)
			var op_layer: GSTLayer = GSTStackOps.add_layer(stack, field_op_id, GSTLayer.Kind.FIELD, false)
			for input: Dictionary in field_op_entry.inputs:
				var assign_result: Dictionary = GSTStackOps.assign_slot(stack, op_layer.id, input["name"], generator_layer.id, lib)
				assert_true(assign_result["ok"], "%s slot %s accepts generator %s: %s" % [field_op_id, input["name"], generator_id, assign_result["reason"]])
			stack.output_color = op_layer.id
			var code: String = GSTCodegen.generate(stack, lib)
			assert_true(GSTShaderCompile.compiles(code), "%s fed by %s compiles" % [field_op_id, generator_id])
			checked += 1
	assert_eq(checked, field_op_ids.size() * generator_ids.size(), "checked %d field-op x generator combinations (%d field ops x %d generators)" % [checked, field_op_ids.size(), generator_ids.size()])


## True when `id` is a filter/* entry (samples_source): its color-kind input
## accepts only a source (texture/screen), so it needs a source/texture layer
## wired ahead of it wherever it is used as a color-kind input.
func _is_filter(id: String) -> bool:
	return id.begins_with("filter/")


## Builds `color_entry_id` as a layer in `stack` and returns it, ready to be
## wired as a color-kind input. A color/* or source/* entry is added as is,
## with a coord block when its manifest has one (source/image). A filter/*
## entry gets a source/texture layer added first and wired into its "source"
## (samples_source) slot; the returned layer is the filter.
func _build_color_entry_layer(stack: GSTStack, color_entry_id: String, lib: GSTLibrary) -> GSTLayer:
	if not _is_filter(color_entry_id):
		return GSTStackOps.add_layer(stack, color_entry_id, GSTLayer.Kind.COLOR, lib.get_entry(color_entry_id).coord)
	var texture_layer: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var filter_layer: GSTLayer = GSTStackOps.add_layer(stack, color_entry_id, GSTLayer.Kind.COLOR, false)
	var filter_entry: GSTManifestEntry = lib.get_entry(color_entry_id)
	for input: Dictionary in filter_entry.inputs:
		var assign_result: Dictionary = GSTStackOps.assign_slot(stack, filter_layer.id, input["name"], texture_layer.id, lib)
		assert_true(assign_result["ok"], "%s slot %s accepts source/texture: %s" % [color_entry_id, input["name"], assign_result["reason"]])
	return filter_layer


## Every filter/* entry fed a source/image layer (decision 28), enabled and
## bypassed (decision 26), compiles. The filter roster is the
## EXPECTED_COLOR_ENTRY_IDS filter subset.
func test_source_image_under_every_filter_compiles() -> void:
	var lib: GSTLibrary = _scanned_library()
	var filter_ids: Array[String] = []
	for id: String in lib.entries.keys():
		if _is_filter(id):
			filter_ids.append(id)
	var expected_filter_ids: Array[String] = []
	for id: String in EXPECTED_COLOR_ENTRY_IDS:
		if _is_filter(id):
			expected_filter_ids.append(id)
	assert_true(_roster_matches(filter_ids, expected_filter_ids), "filter roster matches expected (%s)" % _roster_diff_message(filter_ids, expected_filter_ids))

	var checked: int = 0
	for filter_id: String in filter_ids:
		for enabled: bool in [true, false]:
			var stack: GSTStack = GSTStack.new()
			var image_layer: GSTLayer = GSTStackOps.add_layer(stack, "source/image", GSTLayer.Kind.COLOR, true)
			var filter_layer: GSTLayer = GSTStackOps.add_layer(stack, filter_id, GSTLayer.Kind.COLOR, false)
			var assign_result: Dictionary = GSTStackOps.assign_slot(stack, filter_layer.id, "source", image_layer.id, lib)
			assert_true(assign_result["ok"], "%s accepts source/image: %s" % [filter_id, assign_result["reason"]])
			filter_layer.enabled = enabled
			stack.output_color = filter_layer.id
			var result: GSTCodegenResult = GSTCodegen.generate_result(stack, lib)
			assert_true(result.ok(), "%s (enabled %s) over source/image generates: %s" % [filter_id, enabled, result.error])
			assert_true(GSTShaderCompile.compiles(result.code), "%s (enabled %s) over source/image compiles" % [filter_id, enabled])
			checked += 1
	assert_eq(checked, filter_ids.size() * 2, "checked %d filter x bypass combinations over source/image" % checked)
	print("test_combinations: source/image under every filter compiled: %d (%d filters x enabled, bypassed)" % [checked, filter_ids.size()])


## Every color op (a color/* entry with at least one color-kind input; fill,
## gradient_map, and palette are excluded) with every color-kind entry (the
## color/* roster, the three source/* entries, and every filter/* entry fed by
## a source/texture layer) wired into its first color input. A second color
## input (the blend family, color/mix) is fed color/fill; a field input
## (color/mix's mask) is fed generative/fbm.
func test_every_color_op_compiles_with_every_color_entry_as_input() -> void:
	var lib: GSTLibrary = _scanned_library()
	var color_op_ids: Array[String] = []
	var color_entry_ids: Array[String] = []
	for id: String in lib.entries.keys():
		var entry: GSTManifestEntry = lib.get_entry(id)
		if id.begins_with("color/") and _has_color_input(entry):
			color_op_ids.append(id)
		if id.begins_with("color/") or id.begins_with("source/") or _is_filter(id):
			color_entry_ids.append(id)
	assert_true(_roster_matches(color_op_ids, EXPECTED_COLOR_OP_IDS), "color-op roster matches expected (%s)" % _roster_diff_message(color_op_ids, EXPECTED_COLOR_OP_IDS))
	assert_true(_roster_matches(color_entry_ids, EXPECTED_COLOR_ENTRY_IDS), "color-entry roster matches expected (%s)" % _roster_diff_message(color_entry_ids, EXPECTED_COLOR_ENTRY_IDS))

	var checked: int = 0
	for color_op_id: String in color_op_ids:
		var color_op_entry: GSTManifestEntry = lib.get_entry(color_op_id)
		for color_entry_id: String in color_entry_ids:
			var stack: GSTStack = GSTStack.new()
			var entry_layer: GSTLayer = _build_color_entry_layer(stack, color_entry_id, lib)
			var color_inputs: Array[Dictionary] = []
			var field_inputs: Array[Dictionary] = []
			for input: Dictionary in color_op_entry.inputs:
				if int(input["kind"]) == GSTLayer.Kind.COLOR:
					color_inputs.append(input)
				else:
					field_inputs.append(input)
			var fill_layer: GSTLayer = null
			if color_inputs.size() >= 2:
				fill_layer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
			var fbm_layer: GSTLayer = null
			if not field_inputs.is_empty():
				fbm_layer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
			var op_layer: GSTLayer = GSTStackOps.add_layer(stack, color_op_id, GSTLayer.Kind.COLOR, false)

			var color_input_index: int = 0
			for input: Dictionary in color_op_entry.inputs:
				var target_id: StringName
				if int(input["kind"]) == GSTLayer.Kind.COLOR:
					target_id = entry_layer.id if color_input_index == 0 else fill_layer.id
					color_input_index += 1
				else:
					target_id = fbm_layer.id
				var assign_result: Dictionary = GSTStackOps.assign_slot(stack, op_layer.id, input["name"], target_id, lib)
				assert_true(assign_result["ok"], "%s slot %s accepts %s: %s" % [color_op_id, input["name"], String(target_id), assign_result["reason"]])

			stack.output_color = op_layer.id
			var code: String = GSTCodegen.generate(stack, lib)
			assert_true(GSTShaderCompile.compiles(code), "%s fed by %s compiles" % [color_op_id, color_entry_id])
			checked += 1
	assert_eq(checked, color_op_ids.size() * color_entry_ids.size(), "checked %d color-op x color-entry combinations (%d color ops x %d color entries)" % [checked, color_op_ids.size(), color_entry_ids.size()])
	print("test_combinations: color-op x color-entry combinations checked: %d (%d color ops x %d color-kind entries, filters included per fix pass 3 item 5)" % [checked, color_op_ids.size(), color_entry_ids.size()])


## The int and float params of `entry`, the linkable set (decision 29).
func _linkable_params(entry: GSTManifestEntry) -> Array[String]:
	var names: Array[String] = []
	for param: Dictionary in entry.params:
		if param["type"] == "float" or param["type"] == "int":
			names.append(param["name"])
	return names


## Decision 29: every field-kind entry as the link target of every linkable
## param of every entry. One stack per (target, linker) pair links all of
## the linker's linkable params at once to the target below it. A filter
## linker gets a source/texture layer wired to its samples_source slot;
## other unwired inputs take the fallback constants.
func test_every_field_entry_links_into_every_linkable_param_and_compiles() -> void:
	var lib: GSTLibrary = _scanned_library()
	var field_ids: Array[String] = []
	var linker_ids: Array[String] = []
	for id: String in lib.entries.keys():
		var entry: GSTManifestEntry = lib.get_entry(id)
		if entry.kind_out == GSTLayer.Kind.FIELD:
			field_ids.append(id)
		if not _linkable_params(entry).is_empty():
			linker_ids.append(id)
	field_ids.sort()
	linker_ids.sort()
	assert_true(field_ids.size() >= 40, "field-kind roster present (%d entries)" % field_ids.size())

	var checked: int = 0
	var links: int = 0
	for field_id: String in field_ids:
		var field_entry: GSTManifestEntry = lib.get_entry(field_id)
		for linker_id: String in linker_ids:
			var linker_entry: GSTManifestEntry = lib.get_entry(linker_id)
			var stack: GSTStack = GSTStack.new()
			var target: GSTLayer = GSTStackOps.add_layer(stack, field_id, field_entry.kind_out, field_entry.coord)
			var source: GSTLayer = null
			if linker_entry.samples_source:
				source = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
			var linker: GSTLayer = GSTStackOps.add_layer(stack, linker_id, linker_entry.kind_out, linker_entry.coord)
			if source != null:
				var assign_result: Dictionary = GSTStackOps.assign_slot(stack, linker.id, linker_entry.inputs[0]["name"], source.id, lib)
				assert_true(assign_result["ok"], "%s accepts source/texture: %s" % [linker_id, assign_result["reason"]])
			for param_name: String in _linkable_params(linker_entry):
				linker.param_links[param_name] = {"target": target.id, "amount": 1.0}
				links += 1
			stack.output_color = linker.id
			var result: GSTCodegenResult = GSTCodegen.generate_result(stack, lib)
			assert_true(result.ok(), "%s linked to %s generates: %s" % [linker_id, field_id, result.error])
			assert_true(GSTShaderCompile.compiles(result.code), "%s with every linkable param linked to %s compiles" % [linker_id, field_id])
			checked += 1
	assert_eq(checked, field_ids.size() * linker_ids.size(), "checked %d field-target x linker combinations" % checked)
	print("test_combinations: param link combinations checked: %d stacks, %d links (%d field targets x %d linker entries)" % [checked, links, field_ids.size(), linker_ids.size()])


## Every sdf operator (union, subtract, intersect, smooth_union) with every
## ordered pair of sdf generators (circle, box, rounded_box, polygon, star,
## line, ring) wired into its "a" and "b" slots.
func test_every_sdf_operator_compiles_with_every_pair_of_sdf_generators() -> void:
	var lib: GSTLibrary = _scanned_library()
	var sdf_operator_ids: Array[String] = []
	var sdf_generator_ids: Array[String] = []
	for id: String in lib.entries.keys():
		if not id.begins_with("sdf/"):
			continue
		var entry: GSTManifestEntry = lib.get_entry(id)
		if entry.coord:
			sdf_generator_ids.append(id)
		else:
			sdf_operator_ids.append(id)
	assert_true(_roster_matches(sdf_operator_ids, EXPECTED_SDF_OPERATOR_IDS), "sdf-operator roster matches expected (%s)" % _roster_diff_message(sdf_operator_ids, EXPECTED_SDF_OPERATOR_IDS))
	assert_true(_roster_matches(sdf_generator_ids, EXPECTED_SDF_GENERATOR_IDS), "sdf-generator roster matches expected (%s)" % _roster_diff_message(sdf_generator_ids, EXPECTED_SDF_GENERATOR_IDS))

	var checked: int = 0
	for sdf_operator_id: String in sdf_operator_ids:
		var sdf_operator_entry: GSTManifestEntry = lib.get_entry(sdf_operator_id)
		for generator_a_id: String in sdf_generator_ids:
			for generator_b_id: String in sdf_generator_ids:
				var stack: GSTStack = GSTStack.new()
				var layer_a: GSTLayer = GSTStackOps.add_layer(stack, generator_a_id, GSTLayer.Kind.FIELD, true)
				var layer_b: GSTLayer = GSTStackOps.add_layer(stack, generator_b_id, GSTLayer.Kind.FIELD, true)
				var op_layer: GSTLayer = GSTStackOps.add_layer(stack, sdf_operator_id, GSTLayer.Kind.FIELD, false)
				var targets: Array[GSTLayer] = [layer_a, layer_b]
				for i: int in range(sdf_operator_entry.inputs.size()):
					var input: Dictionary = sdf_operator_entry.inputs[i]
					var assign_result: Dictionary = GSTStackOps.assign_slot(stack, op_layer.id, input["name"], targets[i].id, lib)
					assert_true(assign_result["ok"], "%s slot %s accepts %s: %s" % [sdf_operator_id, input["name"], String(targets[i].id), assign_result["reason"]])
				stack.output_color = op_layer.id
				var code: String = GSTCodegen.generate(stack, lib)
				assert_true(GSTShaderCompile.compiles(code), "%s fed by (%s, %s) compiles" % [sdf_operator_id, generator_a_id, generator_b_id])
				checked += 1
	assert_eq(checked, sdf_operator_ids.size() * sdf_generator_ids.size() * sdf_generator_ids.size(), "checked %d sdf-operator x generator-pair combinations (%d operators x %d x %d generators)" % [checked, sdf_operator_ids.size(), sdf_generator_ids.size(), sdf_generator_ids.size()])
