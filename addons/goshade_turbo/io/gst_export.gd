@tool
class_name GSTExport
extends RefCounted

## Writes a self-contained .gdshader (license notice + one-line JSON header +
## codegen body, decision 8) and reopens one back into a GSTStack (decision
## 8's "an exported shader reopens without its .tres"). The overwrite gate
## (decision 9) is GSTOverwriteCheck; this file is the single place that
## decides whether a write actually happens.


## The full generated text for `stack` (header included). Thin wrapper over
## GSTCodegen.generate_result so callers that only need the text (not the
## write/confirm flow below) have one obvious entry point.
static func build(stack: GSTStack, library: GSTLibrary) -> GSTCodegenResult:
	return GSTCodegen.generate_result(stack, library)


## `{ok, reason, needs_confirmation}`. A codegen failure refuses immediately
## (nothing to write). Otherwise: when `path` already exists and
## `confirm_overwrite` is false, GSTOverwriteCheck decides whether the
## on-disk body differs from a fresh codegen of its own header; a real
## difference refuses with `needs_confirmation = true` and writes nothing
## (decision 9). A nonexistent target, an identical existing body, or
## `confirm_overwrite = true` all fall through to the write.
static func write(stack: GSTStack, library: GSTLibrary, path: String, confirm_overwrite: bool) -> Dictionary:
	var result: GSTCodegenResult = build(stack, library)
	if not result.ok():
		return {"ok": false, "reason": result.error, "needs_confirmation": false}

	if FileAccess.file_exists(path) and not confirm_overwrite:
		var check_result: Dictionary = GSTOverwriteCheck.check(path, library)
		if check_result["differs"]:
			return {"ok": false, "reason": check_result["reason"], "needs_confirmation": true}

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"reason": "cannot open %s for writing: %s" % [path, error_string(FileAccess.get_open_error())],
			"needs_confirmation": false,
		}
	file.store_string(result.code)
	file.close()
	return {"ok": true, "reason": "", "needs_confirmation": false}


## Reopens a stack from an exported .gdshader's embedded header.
## `{ok, stack, reason, body_differs}`. `reason` names the failure for a
## missing file, a missing "// stack:" header, or an unparsable/unknown-
## schema header (B8: "no new empty stack is offered" on any of these -- the
## caller gets `ok = false` and shows `reason`, nothing else). On success,
## `body_differs` is GSTOverwriteCheck's own verdict for this same file: true
## means the file's body no longer matches a fresh codegen of the header it
## carries (decision 8's reopen warning -- the file was hand-edited after
## export).
static func reopen(path: String, library: GSTLibrary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "stack": null, "reason": "%s does not exist" % path, "body_differs": false}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false, "stack": null,
			"reason": "cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())],
			"body_differs": false,
		}
	var text: String = file.get_as_text()
	file.close()

	var found: Dictionary = GSTOverwriteCheck.find_header_line(text)
	if not found["found"]:
		return {"ok": false, "stack": null, "reason": "%s has no '// stack:' header (B8)" % path, "body_differs": false}

	var parsed: Dictionary = GSTHeader.parse(found["line"], library)
	if not parsed["ok"]:
		return {
			"ok": false, "stack": null,
			"reason": "%s header refused: %s (B8)" % [path, parsed["reason"]],
			"body_differs": false,
		}

	var check_result: Dictionary = GSTOverwriteCheck.check(path, library)
	return {"ok": true, "stack": parsed["stack"], "reason": "", "body_differs": check_result["differs"]}
