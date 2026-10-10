extends GSTTestBase

## GSTHeader: serialize/parse the one-line stack JSON header.


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


## Shipped manifests (generative/hash, generative/fbm, fieldops/invert,
## color/fill, color/palette), covering every param type in the roster (int,
## float, color, vec3), a coord block with a warp ref, and a slot ref.
func _build_stack(lib: GSTLibrary) -> Dictionary:
	var stack: GSTStack = GSTStack.new()

	var hash_layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)

	var fbm: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	fbm.coord.scale = Vector2(1.5, 0.5)
	fbm.coord.offset = Vector2(-0.25, 0.75)
	fbm.coord.rotation = 0.2
	fbm.coord.scroll = Vector2(0.1, 0.0)
	fbm.coord.warp_x = hash_layer.id
	fbm.coord.warp_strength = 0.4
	fbm.params["octaves"] = 6
	fbm.params["gain"] = 0.65

	var invert: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, invert.id, "x", fbm.id, lib)

	var fill: GSTLayer = GSTStackOps.add_layer(stack, "color/fill", GSTLayer.Kind.COLOR, false)
	fill.params["color"] = Color(0.9, 0.1, 0.3, 0.8)

	var palette: GSTLayer = GSTStackOps.add_layer(stack, "color/palette", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, palette.id, "t", invert.id, lib)
	palette.params["a"] = Vector3(0.2, 0.3, 0.4)

	stack.output_color = palette.id
	stack.output_alpha = invert.id
	stack.next_id = 7

	return {"stack": stack, "hash": hash_layer, "fbm": fbm, "invert": invert, "fill": fill, "palette": palette}


func test_serialize_parse_recodegen_byte_equal_to_exported_body() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = (_build_stack(lib)["stack"] as GSTStack)

	var exported: GSTCodegenResult = GSTCodegen.generate_result(stack, lib)
	assert_true(exported.ok(), "exported stack codegen succeeds: %s" % exported.error)

	var found: Dictionary = GSTOverwriteCheck.find_header_line(exported.code)
	assert_true(found["found"], "exported text carries a '// stack:' header line")

	var parsed: Dictionary = GSTHeader.parse(found["line"], lib)
	assert_true(parsed["ok"], "header parses back: %s" % parsed["reason"])

	var reparsed: GSTCodegenResult = GSTCodegen.generate_result(parsed["stack"], lib)
	assert_true(reparsed.ok(), "re-codegen of the reparsed stack succeeds: %s" % reparsed.error)

	var reparsed_found: Dictionary = GSTOverwriteCheck.find_header_line(reparsed.code)
	assert_true(reparsed_found["found"], "re-codegen text also carries a header line")
	assert_eq(reparsed_found["body"], found["body"], "re-codegen body is byte-equal to the originally exported body")


func test_header_line_is_exactly_one_line() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = (_build_stack(lib)["stack"] as GSTStack)

	var line: String = GSTHeader.header_line(stack)
	assert_false(line.contains("\n"), "header_line() never embeds a newline")

	var exported: GSTCodegenResult = GSTCodegen.generate_result(stack, lib)
	var header_line_count: int = 0
	for text_line: String in exported.code.split("\n"):
		if text_line.begins_with(GSTHeader.HEADER_PREFIX):
			header_line_count += 1
	assert_eq(header_line_count, 1, "exactly one '// stack:' line exists in the exported text")


## The exported text has "//" comments above the header (the license
## notice); a body that itself contains "//" comments below the header must
## not make find_header_line/parse match the wrong line.
func test_body_containing_slash_slash_comments_still_parses() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = (_build_stack(lib)["stack"] as GSTStack)
	var header_line: String = GSTHeader.header_line(stack)

	var text: String = "\n".join([
		"// GoShade Turbo generated shader. MIT License.",
		header_line,
		"",
		"// a hand-added comment inside the body",
		"shader_type canvas_item;",
		"// another stray comment",
		"void fragment() {}",
	])

	var found: Dictionary = GSTOverwriteCheck.find_header_line(text)
	assert_true(found["found"], "header line is found despite surrounding '//' comments")
	assert_eq(found["line"], header_line, "the found line is exactly the header line, not a stray comment")

	var parsed: Dictionary = GSTHeader.parse(found["line"], lib)
	assert_true(parsed["ok"], "parse succeeds on the header line found inside a commented body: %s" % parsed["reason"])
	assert_eq((parsed["stack"] as GSTStack).layers.size(), 5, "parsed stack has the expected layer count")


func test_parse_refuses_missing_header_prefix() -> void:
	var lib: GSTLibrary = _scanned_library()
	var parsed: Dictionary = GSTHeader.parse("shader_type canvas_item;", lib)
	assert_false(parsed["ok"], "a line with no '// stack: ' prefix is refused")
	assert_true(parsed["reason"].contains("prefix"), "refusal names the missing prefix: %s" % parsed["reason"])


func test_parse_refuses_unparsable_json() -> void:
	var lib: GSTLibrary = _scanned_library()
	var parsed: Dictionary = GSTHeader.parse("// stack: {not valid json", lib)
	assert_false(parsed["ok"], "unparsable JSON after the prefix is refused")
	assert_true(parsed["reason"].contains("unparsable"), "refusal names the unparsable JSON: %s" % parsed["reason"])


func test_parse_refuses_unknown_schema() -> void:
	var lib: GSTLibrary = _scanned_library()
	var line: String = "// stack: {\"schema\":3,\"coord_space\":\"uv\",\"output_color\":\"\",\"output_alpha\":\"\",\"next_id\":0,\"layers\":[]}"
	var parsed: Dictionary = GSTHeader.parse(line, lib)
	assert_false(parsed["ok"], "schema 3 is refused (only schemas 1 and 2 are known)")
	assert_true(parsed["reason"].contains("unknown stack header schema 3"), "refusal keeps the unknown-schema message: %s" % parsed["reason"])


## The header v0.1 wrote for _build_small_stack, captured from v0.1 code
## (schema 1, no label/enabled/param_links keys). Decision 23.
const V0_1_SMALL_HEADER: String = "// stack: {\"coord_space\":\"uv\",\"layers\":[{\"coord\":{\"offset\":[0.0,0.0],\"rotation\":0.0,\"scale\":[1.0,1.0],\"scroll\":[0.0,0.0],\"warp_strength\":0.0,\"warp_x\":\"\",\"warp_y\":\"\"},\"entry\":\"generative/fbm\",\"id\":\"0\",\"kind_out\":0,\"params\":{},\"slots\":{}},{\"coord\":null,\"entry\":\"fieldops/invert\",\"id\":\"1\",\"kind_out\":0,\"params\":{},\"slots\":{\"x\":\"0\"}}],\"next_id\":2,\"output_alpha\":\"\",\"output_color\":\"1\",\"schema\":1}"


## generative/fbm wired into fieldops/invert, output_color the invert: the
## stack V0_1_SMALL_HEADER was captured from.
func _build_small_stack(lib: GSTLibrary) -> GSTStack:
	var stack: GSTStack = GSTStack.new()
	var fbm: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	var invert: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, invert.id, "x", fbm.id, lib)
	stack.output_color = invert.id
	return stack


func test_schema_1_header_opens_with_v0_2_fields_at_default() -> void:
	var lib: GSTLibrary = _scanned_library()
	var parsed: Dictionary = GSTHeader.parse(V0_1_SMALL_HEADER, lib)
	assert_true(parsed["ok"], "a schema 1 header parses: %s" % parsed["reason"])
	if not parsed["ok"]:
		return
	var stack: GSTStack = parsed["stack"]
	assert_eq(stack.layers.size(), 2, "schema 1 header keeps its layers")
	for layer: GSTLayer in stack.layers:
		assert_eq(layer.label, "", "layer %s label defaults to empty" % String(layer.id))
		assert_true(layer.enabled, "layer %s enabled defaults to true" % String(layer.id))
		assert_true(layer.param_links.is_empty(), "layer %s param_links defaults to empty" % String(layer.id))
	print("test_schema_1_header_opens_with_v0_2_fields_at_default: ok=%s, %d layers at label \"\", enabled true, param_links empty" % [parsed["ok"], stack.layers.size()])


func test_schema_1_header_ignores_v0_2_keys() -> void:
	var lib: GSTLibrary = _scanned_library()
	var line: String = V0_1_SMALL_HEADER.replace("\"id\":\"1\",", "\"enabled\":false,\"id\":\"1\",\"label\":\"x\",")
	var parsed: Dictionary = GSTHeader.parse(line, lib)
	assert_true(parsed["ok"], "schema 1 header with stray v0.2 keys parses: %s" % parsed["reason"])
	if not parsed["ok"]:
		return
	var invert: GSTLayer = (parsed["stack"] as GSTStack).layers[1]
	assert_eq(invert.label, "", "schema 1 opens label at its default regardless of keys")
	assert_true(invert.enabled, "schema 1 opens enabled at its default regardless of keys")


func test_header_without_v0_2_fields_differs_from_v0_1_only_in_schema() -> void:
	var lib: GSTLibrary = _scanned_library()
	var line: String = GSTHeader.header_line(_build_small_stack(lib))
	assert_true(line.contains("\"schema\":2"), "header writes schema 2: %s" % line)
	assert_eq(line.replace("\"schema\":2", "\"schema\":1"), V0_1_SMALL_HEADER, "header differs from the v0.1 string only in the schema value")


func test_v0_2_fields_serialize_only_when_non_default() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = _build_small_stack(lib)
	var invert: GSTLayer = stack.layers[1]
	invert.label = "edge"
	var line: String = GSTHeader.header_line(stack)
	var json: JSON = JSON.new()
	assert_eq(json.parse(GSTHeader.serialize(stack)), OK, "serialized header is valid JSON")
	var layers: Array = (json.get_data() as Dictionary)["layers"]
	var fbm_keys: Array = (layers[0] as Dictionary).keys()
	var invert_keys: Array = (layers[1] as Dictionary).keys()
	for key: String in ["label", "enabled", "param_links"]:
		assert_false(fbm_keys.has(key), "default %s is not serialized" % key)
	assert_true(invert_keys.has("label"), "non-default label is serialized")
	assert_false(invert_keys.has("enabled"), "default enabled is not serialized beside a set label")
	assert_false(invert_keys.has("param_links"), "empty param_links is not serialized beside a set label")
	assert_false(line.contains("\n"), "header with v0.2 fields stays one line")


func test_schema_2_round_trips_label_enabled_and_param_links() -> void:
	var lib: GSTLibrary = _scanned_library()
	var ctx: Dictionary = _build_stack(lib)
	var stack: GSTStack = ctx["stack"]
	var hash_layer: GSTLayer = ctx["hash"]
	var fbm: GSTLayer = ctx["fbm"]
	var invert: GSTLayer = ctx["invert"]
	fbm.label = "clouds base"
	invert.enabled = false
	fbm.param_links = {"gain": {"target": hash_layer.id, "amount": -0.35}, "octaves": {"target": hash_layer.id, "amount": 1.0}}

	var parsed: Dictionary = GSTHeader.parse(GSTHeader.header_line(stack), lib)
	assert_true(parsed["ok"], "schema 2 header parses: %s" % parsed["reason"])
	if not parsed["ok"]:
		return
	var reparsed: GSTStack = parsed["stack"]
	var reparsed_fbm: GSTLayer = GSTStackOps.find_layer(reparsed, fbm.id)
	var reparsed_invert: GSTLayer = GSTStackOps.find_layer(reparsed, invert.id)
	var reparsed_hash: GSTLayer = GSTStackOps.find_layer(reparsed, hash_layer.id)

	assert_eq(reparsed_fbm.label, "clouds base", "label round-trips")
	assert_eq(reparsed_invert.label, "", "unset label stays empty")
	assert_false(reparsed_invert.enabled, "enabled false round-trips")
	assert_true(reparsed_fbm.enabled, "unset enabled stays true")
	assert_eq(reparsed_fbm.param_links.size(), 2, "both param links round-trip")
	var gain_link: Dictionary = reparsed_fbm.param_links.get("gain", {})
	assert_eq(gain_link.get("target"), hash_layer.id, "link target round-trips by value")
	assert_true(typeof(gain_link.get("target")) == TYPE_STRING_NAME, "link target round-trips as StringName")
	assert_eq(gain_link.get("amount"), -0.35, "link amount round-trips by value")
	assert_true(typeof(gain_link.get("amount")) == TYPE_FLOAT, "link amount round-trips as float")
	var octaves_link: Dictionary = reparsed_fbm.param_links.get("octaves", {})
	assert_true(typeof(octaves_link.get("amount")) == TYPE_FLOAT, "amount 1.0 round-trips as float, not int")
	assert_true(reparsed_hash.param_links.is_empty(), "unset param_links stays empty")
	assert_eq(GSTHeader.header_line(reparsed), GSTHeader.header_line(stack), "reparsed stack serializes to the same header")


func test_every_param_type_round_trips() -> void:
	var lib: GSTLibrary = _scanned_library()
	var ctx: Dictionary = _build_stack(lib)
	var stack: GSTStack = ctx["stack"]

	var parsed: Dictionary = GSTHeader.parse(GSTHeader.header_line(stack), lib)
	assert_true(parsed["ok"], "header parses: %s" % parsed["reason"])
	var reparsed: GSTStack = parsed["stack"]

	var fbm_id: StringName = (ctx["fbm"] as GSTLayer).id
	var fill_id: StringName = (ctx["fill"] as GSTLayer).id
	var palette_id: StringName = (ctx["palette"] as GSTLayer).id

	var reparsed_fbm: GSTLayer = GSTStackOps.find_layer(reparsed, fbm_id)
	var reparsed_fill: GSTLayer = GSTStackOps.find_layer(reparsed, fill_id)
	var reparsed_palette: GSTLayer = GSTStackOps.find_layer(reparsed, palette_id)

	assert_eq(reparsed_fbm.params.get("octaves"), 6, "int param 'octaves' round-trips by value")
	assert_true(typeof(reparsed_fbm.params.get("octaves")) == TYPE_INT, "int param 'octaves' round-trips as int, not float")
	assert_eq(reparsed_fbm.params.get("gain"), 0.65, "float param 'gain' round-trips by value")

	assert_eq(reparsed_fill.params.get("color"), Color(0.9, 0.1, 0.3, 0.8), "color param round-trips by value")
	assert_true(typeof(reparsed_fill.params.get("color")) == TYPE_COLOR, "color param round-trips as Color")

	assert_eq(reparsed_palette.params.get("a"), Vector3(0.2, 0.3, 0.4), "vec3 param round-trips by value")
	assert_true(typeof(reparsed_palette.params.get("a")) == TYPE_VECTOR3, "vec3 param round-trips as Vector3")


func test_labels_leave_every_shipped_function_export_byte_identical() -> void:
	var labeled: GSTLibrary = _scanned_library()
	var unlabeled: GSTLibrary = GSTLibrary.new()
	for id: String in labeled.entries:
		var copy: GSTManifestEntry = labeled.get_entry(id).duplicate(true) as GSTManifestEntry
		for schema: Array[Dictionary] in [copy.inputs, copy.params]:
			for item: Dictionary in schema:
				item.erase("label")
				item.erase("description")
		unlabeled.add_entry(copy)
	for id: String in labeled.entries:
		var entry: GSTManifestEntry = labeled.get_entry(id)
		var stack: GSTStack = GSTStack.new()
		var source: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR)
		var layer: GSTLayer = GSTStackOps.add_layer(stack, id, entry.kind_out, entry.coord)
		layer.manifest = entry
		for input: Dictionary in entry.inputs:
			layer.slots[String(input["name"])] = source.id
		for param: Dictionary in entry.params:
			layer.params[String(param["name"])] = param["default"]
		stack.output_color = layer.id
		var with_labels: GSTCodegenResult = GSTCodegen.generate_result(stack, labeled)
		assert_true(with_labels.ok(), "%s generates with labels: %s" % [id, with_labels.error])
		var header: String = GSTHeader.header_line(stack)
		layer.manifest = unlabeled.get_entry(id)
		var without_labels: GSTCodegenResult = GSTCodegen.generate_result(stack, unlabeled)
		assert_true(without_labels.ok(), "%s generates without labels: %s" % [id, without_labels.error])
		assert_eq(with_labels.code, without_labels.code, "%s export is byte-identical with or without presentation metadata" % id)
		assert_eq(GSTHeader.header_line(stack), header, "%s header retains original keys and values" % id)
