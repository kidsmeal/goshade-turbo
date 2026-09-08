extends SceneTree

## Named verification command: `godot --headless --path . -s res://tests/run_codegen_tests.gd`
##
## Outer wrapper around tests/gst_test_runner.gd. GDScript exposes no hook
## that catches an engine-level SCRIPT ERROR (an assert() failure or a
## runtime error the engine itself prints) in the process that raises it, so
## this wrapper runs the inner runner as a child process via OS.execute,
## captures its combined stdout+stderr, prints it verbatim, and fails the
## whole run (exit 1) if the child process exited nonzero OR the captured
## output contains "SCRIPT ERROR", "ERROR:", or "Parse error", even when the
## inner runner itself reported exit 0 because the aborted test method never
## returned control to record a failure. Exit 0 only when the child exited 0
## and none of those substrings appear.
##
## Prerequisite, once after clone and after adding any new class_name
## script: `godot --headless --path . --import`. Without it, class_name
## globals fail with a Parse error in the child run.

const INNER_SCRIPT: String = "res://tests/gst_test_runner.gd"


func _initialize() -> void:
	var godot_path: String = OS.get_executable_path()
	var project_path: String = ProjectSettings.globalize_path("res://")
	var arguments: PackedStringArray = PackedStringArray([
		"--headless",
		"--path", project_path,
		"-s", INNER_SCRIPT,
	])
	var output: Array = []
	var exit_code: int = OS.execute(godot_path, arguments, output, true)

	var combined_output: String = ""
	for chunk: Variant in output:
		combined_output += str(chunk)
	print(combined_output)

	var reasons: Array[String] = []
	if exit_code != 0:
		reasons.append("child process exit code %d" % exit_code)
	if combined_output.contains("SCRIPT ERROR"):
		reasons.append("output contains \"SCRIPT ERROR\"")
	if combined_output.contains("ERROR:"):
		reasons.append("output contains \"ERROR:\"")
	if combined_output.contains("Parse error"):
		reasons.append("output contains \"Parse error\"")

	if reasons.is_empty():
		print("run_codegen_tests: PASS, child exit 0 and no error markers in output")
		quit(0)
	else:
		print("run_codegen_tests: FAIL, %s" % ", ".join(reasons))
		quit(1)
