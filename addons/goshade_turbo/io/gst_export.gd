@tool
class_name GSTExport
extends RefCounted

## Writes a self-contained .gdshader (license notice + one-line JSON header +
## codegen body) and reopens one back into a GSTStack without its .tres.
## GSTOverwriteCheck supplies the overwrite verdict; write() is the only
## place that decides whether a write happens.


## The full generated text for `stack`, header included.
static func build(stack: GSTStack, library: GSTLibrary) -> GSTCodegenResult:
	return GSTCodegen.generate_result(stack, library)


## `{ok, reason, needs_confirmation}` plus `code` (the written text) on
## success. A codegen failure refuses with nothing written. When `path`
## exists and `confirm_overwrite` is false, a body that differs from a fresh
## codegen of its own header refuses with `needs_confirmation = true`.
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
	return {"ok": true, "reason": "", "needs_confirmation": false, "code": result.code}


## Reopens a stack from an exported .gdshader's embedded header.
## `{ok, stack, reason, body_differs}`. A missing file, a missing "// stack:"
## header, or an unparsable/unknown-schema header refuses with `ok = false`;
## no empty stack is offered. On success `body_differs` is GSTOverwriteCheck's
## verdict: true means the body was edited after export.
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
		return {"ok": false, "stack": null, "reason": "%s has no '// stack:' header" % path, "body_differs": false}

	var parsed: Dictionary = GSTHeader.parse(found["line"], library)
	if not parsed["ok"]:
		return {
			"ok": false, "stack": null,
			"reason": "%s header refused: %s" % [path, parsed["reason"]],
			"body_differs": false,
		}

	var check_result: Dictionary = GSTOverwriteCheck.check(path, library)
	return {"ok": true, "stack": parsed["stack"], "reason": "", "body_differs": check_result["differs"]}
