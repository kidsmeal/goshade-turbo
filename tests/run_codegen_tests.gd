extends SceneTree

## Named verification command: `godot --headless --path . -s res://tests/run_codegen_tests.gd`
##
## Wrapper around tests/gst_test_runner.gd. GDScript has no hook that
## catches an engine-level SCRIPT ERROR in the process that raises it, so
## the inner runner runs as a child process via OS.execute. Its combined
## stdout+stderr is printed verbatim; the run exits 1 if the child exited
## nonzero or the output contains "SCRIPT ERROR", "ERROR:", or "Parse error".
##
## Prerequisite, once after clone and after adding any class_name script:
## `godot --headless --path . --import`. Without it class_name globals fail
## with a Parse error in the child run.
##
## On Godot 4.4/4.6 that --import run leaves .recovery_mode_lock in the
## user data dir (the editor removes it 1s after its first filesystem scan;
## --import quits before that; 4.7 removes it in Main::cleanup()). This
## wrapper never passes --editor or --import, so it only removes the stale
## lock, once before and once after the child run.

const INNER_SCRIPT: String = "res://tests/gst_test_runner.gd"


func _remove_stale_recovery_lock() -> void:
	var lock_path: String = OS.get_user_data_dir().path_join(".recovery_mode_lock")
	if FileAccess.file_exists(lock_path):
		DirAccess.remove_absolute(lock_path)
		print("removed stale %s (Godot's --import prerequisite leaves this on 4.4/4.6; see docs/TESTING.md)" % lock_path)


func _initialize() -> void:
	_remove_stale_recovery_lock()

	var godot_path: String = OS.get_executable_path()
	var project_path: String = ProjectSettings.globalize_path("res://")
	var arguments: PackedStringArray = PackedStringArray([
		"--headless",
		"--path", project_path,
		"-s", INNER_SCRIPT,
	])
	var output: Array = []
	var exit_code: int = OS.execute(godot_path, arguments, output, true)

	_remove_stale_recovery_lock()

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
