extends GSTTestBase

## GSTOverwriteCheck and GSTExport's overwrite gate. Writes only under
## user://, never into the repo.


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


## One generator wired into one field op, output_color the field op (field
## converts to grayscale), from the shipped manifests: enough for a real
## header and body to diff.
func _build_stack(lib: GSTLibrary) -> GSTStack:
	var stack: GSTStack = GSTStack.new()
	var fbm: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	var invert: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, invert.id, "x", fbm.id, lib)
	stack.output_color = invert.id
	return stack


## Appends a trailing space to the first non-empty body line (the first line
## after the header), a one-character mutation that never touches the header
## JSON.
func _mutate_body_char(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	for i: int in range(lines.size()):
		if lines[i].begins_with(GSTHeader.HEADER_PREFIX):
			for j: int in range(i + 1, lines.size()):
				if not lines[j].is_empty():
					lines[j] = lines[j] + " "
					return "\n".join(lines)
	return text


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_check_reports_no_difference_after_a_clean_export() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = _build_stack(lib)
	var path: String = "user://gst_test_overwrite_clean.gdshader"

	var write_result: Dictionary = GSTExport.write(stack, lib, path, false)
	assert_true(write_result["ok"], "clean export to a nonexistent path succeeds: %s" % write_result["reason"])

	var check_result: Dictionary = GSTOverwriteCheck.check(path, lib)
	assert_true(check_result["exists"], "check sees the just-written file")
	assert_true(check_result["has_header"], "check finds the header line")
	assert_false(check_result["differs"], "an untouched export reports no difference: %s" % check_result["reason"])

	DirAccess.remove_absolute(path)


## The header v0.1 wrote for _build_stack, captured from v0.1 code: schema 1,
## no label/enabled/param_links keys. Decision 23.
const V0_1_HEADER: String = "// stack: {\"coord_space\":\"uv\",\"layers\":[{\"coord\":{\"offset\":[0.0,0.0],\"rotation\":0.0,\"scale\":[1.0,1.0],\"scroll\":[0.0,0.0],\"warp_strength\":0.0,\"warp_x\":\"\",\"warp_y\":\"\"},\"entry\":\"generative/fbm\",\"id\":\"0\",\"kind_out\":0,\"params\":{},\"slots\":{}},{\"coord\":null,\"entry\":\"fieldops/invert\",\"id\":\"1\",\"kind_out\":0,\"params\":{},\"slots\":{\"x\":\"0\"}}],\"next_id\":2,\"output_alpha\":\"\",\"output_color\":\"1\",\"schema\":1}"


## An unedited v0.1 export: the schema 1 header above the codegen body of the
## same stack. Reopen and regenerate must report no hand edit (decision 23).
func test_unedited_v0_1_export_reports_no_hand_edit() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = _build_stack(lib)
	var path: String = "user://gst_test_overwrite_v0_1.gdshader"

	var exported: GSTCodegenResult = GSTExport.build(stack, lib)
	assert_true(exported.ok(), "fixture stack exports: %s" % exported.error)
	var found: Dictionary = GSTOverwriteCheck.find_header_line(exported.code)
	var v0_1_text: String = exported.code.replace(found["line"], V0_1_HEADER)
	_write_text(path, v0_1_text)

	var check_result: Dictionary = GSTOverwriteCheck.check(path, lib)
	assert_true(check_result["has_header"], "check finds the schema 1 header")
	assert_false(check_result["differs"], "an unedited v0.1 export reports no difference: %s" % check_result["reason"])

	var reopen_result: Dictionary = GSTExport.reopen(path, lib)
	assert_true(reopen_result["ok"], "a v0.1 export reopens: %s" % reopen_result["reason"])
	if reopen_result["ok"]:
		assert_false(reopen_result["body_differs"], "reopen does not flag the v0.1 body as hand-edited")
		var regenerated: GSTCodegenResult = GSTCodegen.generate_result(reopen_result["stack"], lib)
		assert_true(regenerated.ok(), "the reopened stack regenerates: %s" % regenerated.error)
		var regenerated_found: Dictionary = GSTOverwriteCheck.find_header_line(regenerated.code)
		var v0_1_found: Dictionary = GSTOverwriteCheck.find_header_line(v0_1_text)
		assert_eq(regenerated_found["body"], v0_1_found["body"], "regenerated body is byte-identical to the v0.1 body")

	DirAccess.remove_absolute(path)


## The first line where `a` and `b` differ, as "line N: <a> | <b>", or "" when
## equal. Names the drifted codegen line in a failure message.
func _first_line_difference(a: String, b: String) -> String:
	var a_lines: PackedStringArray = a.split("\n")
	var b_lines: PackedStringArray = b.split("\n")
	for i: int in range(maxi(a_lines.size(), b_lines.size())):
		var a_line: String = a_lines[i] if i < a_lines.size() else "<end>"
		var b_line: String = b_lines[i] if i < b_lines.size() else "<end>"
		if a_line != b_line:
			return "line %d: %s | %s" % [i + 1, a_line, b_line]
	return ""


## The real v0.1.4 export sandbox/logo/logo.gdshader, unedited since that
## tag, never reopens with the hand-edit warning. With a scanned library it
## reopens with `body_differs == false`. With an unscanned library (the call
## that reported the bug) no manifest resolves and reopen refuses naming the
## entry, where it used to report the regeneration failure as
## `body_differs == true` (decision 23).
func test_v0_1_4_logo_export_reopen_does_not_flag_hand_edit() -> void:
	var lib: GSTLibrary = _scanned_library()
	var path: String = "res://sandbox/logo/logo.gdshader"

	var reopen_result: Dictionary = GSTExport.reopen(path, lib)
	assert_true(reopen_result["ok"], "the v0.1.4 logo export reopens: %s" % reopen_result["reason"])
	if reopen_result["ok"]:
		var regenerated: GSTCodegenResult = GSTCodegen.generate_result(reopen_result["stack"], lib)
		assert_true(regenerated.ok(), "the reopened logo stack regenerates: %s" % regenerated.error)
		var on_disk_body: String = GSTOverwriteCheck.find_header_line(_read_text(path))["body"]
		var fresh_body: String = GSTOverwriteCheck.find_header_line(regenerated.code)["body"]
		assert_false(reopen_result["body_differs"], "reopen does not flag the v0.1.4 logo body as hand-edited, first difference (on disk | fresh): %s" % _first_line_difference(on_disk_body, fresh_body))

	var unscanned_result: Dictionary = GSTExport.reopen(path, GSTLibrary.new())
	assert_false(unscanned_result["body_differs"], "an unscanned library does not report the logo body as hand-edited")
	assert_false(unscanned_result["ok"], "an unscanned library refuses the reopen")
	assert_true(String(unscanned_result["reason"]).contains("unresolved entry source/texture"), "the refusal names the first unresolved entry: %s" % unscanned_result["reason"])


## A schema 1 stack touching every body path codegen emits: a generator with
## scroll, warp and tuned params, a field op, a color-to-field luma slot, a
## field-to-color op, a texture source, a filter and a three-input color op.
## No layer carries a label, a bypass or a param link.
func _build_parity_stack(lib: GSTLibrary) -> GSTStack:
	var stack: GSTStack = GSTStack.new()
	var fbm: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	fbm.params["octaves"] = 6
	fbm.params["gain"] = 0.65
	fbm.coord.scroll = Vector2(0.1, 0.0)
	var hash_layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	hash_layer.coord.warp_x = fbm.id
	hash_layer.coord.warp_strength = 0.25
	var smooth: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/smoothstep", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, smooth.id, "x", fbm.id, lib)
	var ramp: GSTLayer = GSTStackOps.add_layer(stack, "color/gradient_map", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, ramp.id, "t", smooth.id, lib)
	var tex: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	var pixel: GSTLayer = GSTStackOps.add_layer(stack, "filter/pixelate", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, pixel.id, "source", tex.id, lib)
	var inv: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, inv.id, "x", pixel.id, lib)
	var mix_layer: GSTLayer = GSTStackOps.add_layer(stack, "color/mix", GSTLayer.Kind.COLOR, false)
	GSTStackOps.assign_slot(stack, mix_layer.id, "a", ramp.id, lib)
	GSTStackOps.assign_slot(stack, mix_layer.id, "b", pixel.id, lib)
	GSTStackOps.assign_slot(stack, mix_layer.id, "mask", inv.id, lib)
	stack.output_color = mix_layer.id
	return stack


## The body (everything below the "// stack:" line) main generated for
## _build_parity_stack before v0.2 codegen landed (decision 23).
const PARITY_BODY_FROM_MAIN: String = """shader_type canvas_item;

group_uniforms L00_fbm;
uniform vec2 l0_scale = vec2(1.0, 1.0);
uniform vec2 l0_offset = vec2(0.0, 0.0);
uniform float l0_rotation = 0.0;
uniform vec2 l0_scroll = vec2(0.10000000149012, 0.0);
uniform int l0_fbm_octaves : hint_range(1, 8) = 6;
uniform float l0_fbm_gain : hint_range(0.2, 0.8) = 0.65;
group_uniforms L01_hash;
uniform vec2 l1_scale = vec2(1.0, 1.0);
uniform vec2 l1_offset = vec2(0.0, 0.0);
uniform float l1_rotation = 0.0;
uniform float l1_warp_strength = 0.25;
group_uniforms L02_gst_smoothstep;
uniform float l2_gst_smoothstep_edge0 : hint_range(-1.0, 2.0) = 0.0;
uniform float l2_gst_smoothstep_edge1 : hint_range(-1.0, 2.0) = 1.0;
group_uniforms L03_gradient_map;
uniform vec4 l3_gradient_map_color_a : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 l3_gradient_map_color_b : source_color = vec4(1.0, 1.0, 1.0, 1.0);
group_uniforms L05_pixelate;
uniform float l5_pixelate_cell_size : hint_range(0.001, 0.2) = 0.02;

vec2 gst_transform(vec2 p, vec2 scale, float rotation, vec2 offset) {
	vec2 scaled = p * scale;
	float s = sin(rotation);
	float c = cos(rotation);
	vec2 rotated = vec2(scaled.x * c - scaled.y * s, scaled.x * s + scaled.y * c);
	return rotated + offset;
}


float luma(vec4 c) {
	return dot(c.rgb, vec3(0.299, 0.587, 0.114));
}


float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 gst_grad2(ivec2 i) {
	float a = hash(vec2(i)) * 6.28318530718;
	return vec2(cos(a), sin(a));
}

float snoise(vec2 p) {
	const float k1 = 0.36602540378; // (sqrt(3.0) - 1.0) / 2.0
	const float k2 = 0.21132486541; // (3.0 - sqrt(3.0)) / 6.0
	vec2 i = floor(p + (p.x + p.y) * k1);
	vec2 a = p - i + (i.x + i.y) * k2;
	vec2 o = a.x > a.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
	vec2 b = a - o + k2;
	vec2 c = a - 1.0 + 2.0 * k2;
	vec3 h = max(0.5 - vec3(dot(a, a), dot(b, b), dot(c, c)), 0.0);
	// Integer corner addresses keep shared gradients consistent across renderers.
	vec3 n = h * h * h * h * vec3(dot(a, gst_grad2(ivec2(i))), dot(b, gst_grad2(ivec2(i) + ivec2(o))), dot(c, gst_grad2(ivec2(i) + ivec2(1))));
	return dot(n, vec3(70.0)) * 0.5 + 0.5;
}

float fbm(vec2 p, int octaves, float gain) {
	float sum = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < octaves; i++) {
		sum += amp * (snoise(p * freq) * 2.0 - 1.0);
		freq *= 2.0;
		amp *= gain;
	}
	return sum + 0.5;
}

float gst_smoothstep(float x, float edge0, float edge1) {
	// Equal or reversed edges: clamp edge1 above edge0 so GLSL smoothstep
	// (undefined for edge0 >= edge1) instead resolves to a step at edge0.
	float e1 = max(edge1, edge0 + 0.00001);
	return smoothstep(edge0, e1, x);
}

vec4 gradient_map(float t, vec4 color_a, vec4 color_b) {
	return mix(color_a, color_b, clamp(t, 0.0, 1.0));
}

float invert(float x) {
	return 1.0 - x;
}

vec4 color_mix(vec4 a, vec4 b, float mask) {
	return mix(a, b, mask);
}

void fragment() {
	vec2 space_coord = UV;
	vec2 coord0 = gst_transform(space_coord, l0_scale, l0_rotation, l0_offset);
	coord0 += l0_scroll * TIME;
	float l0 = fbm(coord0, l0_fbm_octaves, l0_fbm_gain);
	vec2 coord1 = gst_transform(space_coord, l1_scale, l1_rotation, l1_offset);
	coord1 += vec2(l0, 0.0) * l1_warp_strength;
	float l1 = hash(coord1);
	float l2 = gst_smoothstep(l0, l2_gst_smoothstep_edge0, l2_gst_smoothstep_edge1);
	vec4 l3 = gradient_map(l2, l3_gradient_map_color_a, l3_gradient_map_color_b);
	vec4 l4 = texture(TEXTURE, space_coord);
	vec4 l5;
	{
		vec2 cell = max(vec2(l5_pixelate_cell_size), vec2(0.0001));
		vec2 snapped = floor(UV / cell) * cell + cell * 0.5;
		l5 = texture(TEXTURE, snapped);
	}
	float l6 = invert(luma(l5));
	vec4 l7 = color_mix(l3, l5, l6);
	COLOR = vec4(l7.rgb, texture(TEXTURE, UV).a);
}
"""


## A stack with no v0.2 field regenerates the body main produced, byte for
## byte, so GSTOverwriteCheck does not flag an unedited v0.1 export
## (decision 23).
func test_schema_1_stack_body_is_byte_identical_to_main() -> void:
	var lib: GSTLibrary = _scanned_library()
	var generated: GSTCodegenResult = GSTCodegen.generate_result(_build_parity_stack(lib), lib)
	assert_true(generated.ok(), "parity stack generates: %s" % generated.error)
	var body: String = GSTOverwriteCheck.find_header_line(generated.code)["body"]
	assert_eq(body, PARITY_BODY_FROM_MAIN, "schema 1 body matches the fixture captured from main")
	assert_true(GSTShaderCompile.compiles(generated.code), "parity stack compiles")


func test_check_reports_a_difference_after_mutating_one_character() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = _build_stack(lib)
	var path: String = "user://gst_test_overwrite_mutated.gdshader"

	GSTExport.write(stack, lib, path, false)
	_write_text(path, _mutate_body_char(_read_text(path)))

	var check_result: Dictionary = GSTOverwriteCheck.check(path, lib)
	assert_true(check_result["differs"], "a one-character body mutation is detected")
	assert_false(check_result["reason"].is_empty(), "the difference carries a reason")

	DirAccess.remove_absolute(path)


func test_headerless_file_reports_differs_with_reason() -> void:
	var lib: GSTLibrary = _scanned_library()
	var path: String = "user://gst_test_overwrite_headerless.gdshader"
	_write_text(path, "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0); }\n")

	var check_result: Dictionary = GSTOverwriteCheck.check(path, lib)
	assert_true(check_result["exists"], "check sees the hand-written file")
	assert_false(check_result["has_header"], "a headerless file has no header")
	assert_true(check_result["differs"], "a headerless file always counts as differing")
	assert_false(check_result["reason"].is_empty(), "the headerless case carries a reason")

	DirAccess.remove_absolute(path)


func test_write_without_confirm_blocks_and_leaves_file_byte_identical() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = _build_stack(lib)
	var path: String = "user://gst_test_overwrite_write_noconfirm.gdshader"

	GSTExport.write(stack, lib, path, false)
	var mutated_text: String = _mutate_body_char(_read_text(path))
	_write_text(path, mutated_text)

	var write_result: Dictionary = GSTExport.write(stack, lib, path, false)
	assert_false(write_result["ok"], "write without confirm is refused when the body differs")
	assert_true(write_result["needs_confirmation"], "the refusal is reported as needing confirmation")

	assert_eq(_read_text(path), mutated_text, "the file is byte-identical to the mutated version: no write happened")

	DirAccess.remove_absolute(path)


func test_write_with_confirm_overwrites() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = _build_stack(lib)
	var path: String = "user://gst_test_overwrite_write_confirm.gdshader"

	GSTExport.write(stack, lib, path, false)
	_write_text(path, _mutate_body_char(_read_text(path)))

	var write_result: Dictionary = GSTExport.write(stack, lib, path, true)
	assert_true(write_result["ok"], "write with confirm=true overwrites: %s" % write_result["reason"])
	assert_false(write_result["needs_confirmation"], "a confirmed write never asks again")

	var fresh: GSTCodegenResult = GSTExport.build(stack, lib)
	assert_eq(_read_text(path), fresh.code, "the overwritten file matches a fresh codegen exactly")

	DirAccess.remove_absolute(path)


func test_reopen_reports_body_differs_and_rebuilds_the_original_body() -> void:
	var lib: GSTLibrary = _scanned_library()
	var stack: GSTStack = _build_stack(lib)
	var path: String = "user://gst_test_overwrite_reopen.gdshader"

	var original: GSTCodegenResult = GSTExport.build(stack, lib)
	GSTExport.write(stack, lib, path, false)
	_write_text(path, _mutate_body_char(_read_text(path)))

	var reopen_result: Dictionary = GSTExport.reopen(path, lib)
	assert_true(reopen_result["ok"], "reopen succeeds despite the body mutation: %s" % reopen_result["reason"])
	assert_true(reopen_result["body_differs"], "reopen reports the mutated body as differing")

	var rebuilt: GSTCodegenResult = GSTCodegen.generate_result(reopen_result["stack"], lib)
	assert_true(rebuilt.ok(), "the rebuilt stack re-codegens: %s" % rebuilt.error)
	assert_eq(rebuilt.code, original.code, "the rebuilt stack generates the original, unmutated body")

	DirAccess.remove_absolute(path)
