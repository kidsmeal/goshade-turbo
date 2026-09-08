extends GSTTestBase

## Round-trip proof for the three phase 7 recipes (docs/PLAN.md Phase 7
## Files/Verification, design build order step 4): each recipe under
## addons/goshade_turbo/recipes/ saves and reloads with every field intact
## (GSTStackIO, reusing gst_test_base.gd's _compare_stacks), exports and
## reopens from its own header with a byte-equal re-codegen body (GSTExport,
## same as tests/test_header_roundtrip.gd's in-memory check but through the
## real file write/reopen path), and its generated shader compiles alone,
## with TIME emitted only by sprite_holographic (the one recipe with a
## nonzero coord scroll).
##
## This is the plan's own gate: "Do not start phase 8 before this passes; it
## is the design's gate on writing the rest of the library."

const RECIPE_NAMES: Array[String] = ["dissolve", "sprite_holographic", "outline"]
const RECIPE_DIR: String = "res://addons/goshade_turbo/recipes"


func _scanned_library() -> GSTLibrary:
	var lib: GSTLibrary = GSTLibrary.new()
	lib.scan()
	return lib


func _recipe_path(name: String) -> String:
	return "%s/%s.tres" % [RECIPE_DIR, name]


func _load_recipe(name: String, lib: GSTLibrary) -> GSTStack:
	var load_result: Dictionary = GSTStackIO.load(_recipe_path(name), lib)
	assert_true(load_result["ok"], "%s: recipe loads: %s" % [name, load_result["reason"]])
	return load_result["stack"] as GSTStack


func test_recipes_save_and_load_round_trip_every_field() -> void:
	var lib: GSTLibrary = _scanned_library()
	for name: String in RECIPE_NAMES:
		var stack: GSTStack = _load_recipe(name, lib)
		if stack == null:
			continue

		var temp_path: String = "user://gst_test_recipe_roundtrip_%s.tres" % name
		var save_result: Dictionary = GSTStackIO.save(stack, temp_path)
		assert_true(save_result["ok"], "%s: save succeeds: %s" % [name, save_result["reason"]])

		var reload_result: Dictionary = GSTStackIO.load(temp_path, lib)
		assert_true(reload_result["ok"], "%s: reload succeeds: %s" % [name, reload_result["reason"]])
		if reload_result["ok"]:
			var mismatches: Array[String] = _compare_stacks(stack, reload_result["stack"])
			assert_true(mismatches.is_empty(), "%s: round trip field mismatches (%d): %s" % [name, mismatches.size(), mismatches])

		DirAccess.remove_absolute(temp_path)


## Export, parse the header back into a stack, re-codegen: the body compares
## byte-equal to the exported body (design decision 8, Codegen rules). Uses
## the real GSTExport.write/reopen file path, not the in-memory
## GSTHeader.parse test_header_roundtrip.gd already covers, so a bug specific
## to the write/reopen file IO would surface here even if the in-memory path
## stayed correct.
func test_recipes_export_reopen_and_recodegen_are_byte_equal() -> void:
	var lib: GSTLibrary = _scanned_library()
	for name: String in RECIPE_NAMES:
		var stack: GSTStack = _load_recipe(name, lib)
		if stack == null:
			continue

		var export_path: String = "user://gst_test_recipe_roundtrip_%s.gdshader" % name
		var write_result: Dictionary = GSTExport.write(stack, lib, export_path, true)
		assert_true(write_result["ok"], "%s: export write succeeds: %s" % [name, write_result["reason"]])

		var reopen_result: Dictionary = GSTExport.reopen(export_path, lib)
		assert_true(reopen_result["ok"], "%s: reopen succeeds: %s" % [name, reopen_result["reason"]])
		assert_false(reopen_result["body_differs"], "%s: reopened body matches a fresh codegen of its own header" % name)

		if reopen_result["ok"]:
			var recodegen_result: GSTCodegenResult = GSTCodegen.generate_result(reopen_result["stack"], lib)
			assert_true(recodegen_result.ok(), "%s: re-codegen of the reopened stack succeeds: %s" % [name, recodegen_result.error])
			var exported_text: String = _read_text(export_path)
			assert_eq(recodegen_result.code, exported_text, "%s: re-codegen body is byte-equal to the exported file" % name)

		_remove_with_uid(export_path)


## Every recipe's generated shader compiles alone (release checklist: "Every
## roster entry above exists as a manifest file and compiles alone in the
## preview" applies equally to a recipe stack of roster entries); TIME is
## emitted only by sprite_holographic, whose stripes layer carries a nonzero
## coord.scroll (Codegen rules: "TIME and the scroll uniform are both emitted
## or both absent").
func test_every_recipe_compiles_and_time_emission_matches_scroll() -> void:
	var lib: GSTLibrary = _scanned_library()
	var expect_time: Dictionary = {
		"dissolve": false,
		"sprite_holographic": true,
		"outline": false,
	}
	for name: String in RECIPE_NAMES:
		var stack: GSTStack = _load_recipe(name, lib)
		if stack == null:
			continue

		var result: GSTCodegenResult = GSTCodegen.generate_result(stack, lib)
		assert_true(result.ok(), "%s: codegen succeeds: %s" % [name, result.error])
		if not result.ok():
			continue

		assert_true(GSTShaderCompile.compiles(result.code), "%s: generated shader compiles" % name)

		var has_time: bool = result.code.contains("TIME")
		assert_eq(has_time, expect_time[name], "%s: TIME emission (expect %s)" % [name, expect_time[name]])


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _remove_with_uid(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var uid_path: String = path + ".uid"
	if FileAccess.file_exists(uid_path):
		DirAccess.remove_absolute(uid_path)
