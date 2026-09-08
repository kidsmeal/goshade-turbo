class_name GSTTestBase
extends RefCounted

## Minimal assertion base for the headless test suite. Every assertion
## records rather than halts, so one test file reports every failure in a
## run instead of stopping at the first. gst_test_runner.gd reads
## `failures` after calling each `test_*` method.

var failures: Array[String] = []


func assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append("assert_true failed: %s" % message)


func assert_false(value: bool, message: String) -> void:
	if value:
		failures.append("assert_false failed: %s" % message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("assert_eq failed: %s (expected %s, got %s)" % [message, str(expected), str(actual)])


func assert_null(value: Variant, message: String) -> void:
	if value != null:
		failures.append("assert_null failed: %s (got %s)" % [message, str(value)])


func assert_not_null(value: Variant, message: String) -> void:
	if value == null:
		failures.append("assert_not_null failed: %s" % message)


func has_failures() -> bool:
	return not failures.is_empty()
