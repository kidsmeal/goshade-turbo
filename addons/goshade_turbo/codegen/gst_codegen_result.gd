@tool
class_name GSTCodegenResult
extends RefCounted

## Invocation-local result of GSTCodegen.generate_result(). One instance per
## call, never shared across concurrent or nested generation (docs/PLAN.md
## Cross-cutting concern "Codegen error reporting").

## The generated .gdshader text, or "" when error is non-empty.
var code: String = ""
## Empty on success. On failure, the reason generation stopped; code is then "".
var error: String = ""


func ok() -> bool:
	return error.is_empty()
