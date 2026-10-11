@tool
class_name GSTEditorV01ReopenSmoke
extends RefCounted

var _pass_count := 0
var _fail_count := 0

func run(plugin: EditorPlugin) -> void:
	var lib = GSTLibrary.new()
	var reopen_result = GSTExport.reopen("res://logo_v0_1.gdshader", lib)
	_check("reopen v0.1 export", reopen_result.ok)
	_check("body_differs false", reopen_result.body_differs == false)

	if reopen_result.ok:
		print("SMOKE reopen v0.1 export message: (body_differs=%s)" % reopen_result.body_differs)

	_finish(plugin)

func _check(label: String, ok: bool) -> void:
	if ok:
		_pass_count += 1
		print("SMOKE %s PASS" % label)
	else:
		_fail_count += 1
		print("SMOKE %s FAIL" % label)

func _finish(plugin: EditorPlugin) -> void:
	print("SMOKE SUMMARY pass=%d fail=%d" % [_pass_count, _fail_count])
	if _fail_count > 0:
		plugin.get_tree().quit(1)
	else:
		plugin.get_tree().quit(0)
