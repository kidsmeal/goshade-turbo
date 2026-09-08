class_name GSTShaderCompile
extends RefCounted

## Compiles a canvas_item shader body headless and reports success. The
## --headless dummy rendering driver parses shaders and reports compile
## errors, but Shader.get_shader_uniform_list() returns an empty list both
## on a failed compile and on a genuinely successful zero-uniform compile
## (docs/PLAN.md, Verified engine facts), so a zero-uniform-by-design test
## stack (e.g. a single parameterless field op fed constants) must pass
## `allow_zero_uniforms = true`, which injects one known sentinel uniform
## right after `shader_type canvas_item;` so a successful compile always
## reports at least one uniform.

const SENTINEL_LINE: String = "uniform float gst_compile_check_sentinel = 1.0;"
const SHADER_TYPE_LINE: String = "shader_type canvas_item;"


static func compiles(code: String, allow_zero_uniforms: bool = false) -> bool:
	var final_code: String = _with_sentinel(code) if allow_zero_uniforms else code
	var shader: Shader = Shader.new()
	shader.code = final_code
	return shader.get_shader_uniform_list().size() > 0


static func _with_sentinel(code: String) -> String:
	var idx: int = code.find(SHADER_TYPE_LINE)
	if idx == -1:
		return code
	var insert_at: int = idx + SHADER_TYPE_LINE.length()
	return code.substr(0, insert_at) + "\n" + SENTINEL_LINE + code.substr(insert_at)
