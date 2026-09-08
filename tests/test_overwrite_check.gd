extends GSTTestBase

## GSTOverwriteCheck and GSTExport's overwrite gate (design decisions 8 and
## 9, docs/PLAN.md Phase 6 Files). Writes only under user:// (mirrors
## test_stack_io.gd: never into the repo).


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


## One generator wired into one field op, output_color the field op (field
## converts to grayscale, decision 12) -- real shipped manifests, enough for
## a real header and a real body to diff (real-input rule).
func _build_stack(lib: GSTLibrary) -> GSTStack:
	var stack: GSTStack = GSTStack.new()
	var fbm: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	var invert: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	GSTStackOps.assign_slot(stack, invert.id, "x", fbm.id, lib)
	stack.output_color = invert.id
	return stack


## Appends a trailing space to the first non-empty body line (the first line
## strictly after the header), a one-character mutation that never touches
## the header's own JSON.
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
