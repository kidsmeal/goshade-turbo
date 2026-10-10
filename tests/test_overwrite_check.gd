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
