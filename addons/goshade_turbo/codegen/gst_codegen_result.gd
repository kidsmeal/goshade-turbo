@tool
class_name GSTCodegenResult
extends RefCounted

## Result of one GSTCodegen.generate_result() call. One instance per call,
## never shared across concurrent or nested generation.

## The generated .gdshader text, or "" when error is non-empty.
var code: String = ""
## Empty on success. On failure, the reason generation stopped; code is then "".
var error: String = ""


func ok() -> bool:
	return error.is_empty()
