@tool
class_name GSTEditorV01ReopenSmoke
extends RefCounted

var _pass_count := 0
var _fail_count := 0

func run(plugin: EditorPlugin) -> void:
	var lib = GSTLibrary.new()
	var reopen_result = GSTExport.reopen("res://glow_v0_1_export.gdshader", lib)

	if reopen_result.ok:
		var body_differs = reopen_result.body_differs
		var path = "res://glow_v0_1_export.gdshader"
		if body_differs:
			var message = "%s reopened: its body differs from a fresh codegen of the header (hand edits detected)" % path
			print("SMOKE reopen_v0_1_export_message: %s" % message)
			_fail_count += 1
			print("SMOKE reopen v0.1 export FAIL body_differs=true")
		else:
			print("SMOKE reopen_v0_1_export_message: (no warning, no hand edits)")
			_pass_count += 1
			print("SMOKE reopen v0.1 export PASS body_differs=false")
	else:
		_fail_count += 1
		print("SMOKE reopen v0.1 export FAIL: %s" % reopen_result.reason)

	_finish(plugin)

func _finish(plugin: EditorPlugin) -> void:
	print("SMOKE SUMMARY pass=%d fail=%d" % [_pass_count, _fail_count])
	if _fail_count > 0:
		plugin.get_tree().quit(1)
	else:
		plugin.get_tree().quit(0)
