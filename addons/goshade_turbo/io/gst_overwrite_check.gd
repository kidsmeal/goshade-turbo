@tool
class_name GSTOverwriteCheck
extends RefCounted

## Compares an exported .gdshader's on-disk body to a fresh codegen of its
## own embedded header (design decisions 8 and 9: "Export checks the target
## file against a fresh codegen of its header and asks before overwriting a
## differing body"). Used by gst_export.gd's write() (the overwrite gate) and
## reopen() (the decision-8 stale-body warning), and directly by
## gst_main_panel.gd's export confirmation flow.


## `{exists, has_header, differs, reason}`. A target that does not exist is
## never a conflict (exists=false, differs=false). A target with no
## recognizable "// stack: " header line is a hand-written file and always
## `differs = true` (a header-less body can never be regenerated to compare
## against). A target whose header exists but fails to parse (B8), or whose
## parsed stack fails to re-codegen, is also `differs = true`, naming the
## failure: neither case can produce a body to compare, so both count as "do
## not silently overwrite this."
static func check(path: String, library: GSTLibrary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"exists": false, "has_header": false, "differs": false, "reason": ""}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"exists": true, "has_header": false, "differs": true,
			"reason": "cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())],
		}
	var text: String = file.get_as_text()
	file.close()

	var found: Dictionary = find_header_line(text)
	if not found["found"]:
		return {
			"exists": true, "has_header": false, "differs": true,
			"reason": "%s has no '// stack:' header (hand-written file)" % path,
		}

	var parsed: Dictionary = GSTHeader.parse(found["line"], library)
	if not parsed["ok"]:
		return {
			"exists": true, "has_header": true, "differs": true,
			"reason": "%s header refused: %s" % [path, parsed["reason"]],
		}

	var fresh_result: GSTCodegenResult = GSTCodegen.generate_result(parsed["stack"], library)
	if not fresh_result.ok():
		return {
			"exists": true, "has_header": true, "differs": true,
			"reason": "%s regeneration from its own header failed: %s" % [path, fresh_result.error],
		}

	var fresh_found: Dictionary = find_header_line(fresh_result.code)
	var fresh_body: String = fresh_found["body"] if fresh_found["found"] else fresh_result.code
	var differs: bool = found["body"] != fresh_body
	return {
		"exists": true, "has_header": true, "differs": differs,
		"reason": "%s body differs from a fresh codegen of its own header" % path if differs else "",
	}


## Finds the first line beginning with GSTHeader.HEADER_PREFIX in `text`.
## `{found, line, body}`: `body` is every line strictly after the header
## line, rejoined with "\n" (Codegen rules: "Header: license notice, then
## `// stack: <json>` on one line"; the body being compared is everything
## after that one line, not the constant license comment above it). Shared
## by gst_export.gd's reopen() so both files agree on exactly what counts as
## "the header line" and "the body".
static func find_header_line(text: String) -> Dictionary:
	var lines: PackedStringArray = text.split("\n")
	for i: int in range(lines.size()):
		if lines[i].begins_with(GSTHeader.HEADER_PREFIX):
			var after: PackedStringArray = lines.slice(i + 1)
			return {"found": true, "line": lines[i], "body": "\n".join(after)}
	return {"found": false, "line": "", "body": ""}
