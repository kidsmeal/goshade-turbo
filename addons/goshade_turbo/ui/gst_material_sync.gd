@tool
class_name GSTMaterialSync
extends RefCounted

## Rebuilds a ShaderMaterial's shader code and uniforms from a GSTStack's
## layer resources (decision 7: layer resources are authoritative; the
## plugin syncs the preview material from them on every change, never the
## other direction). Design: docs/DESIGN.md decision 7, docs/PLAN.md
## Cross-cutting concern "Codegen error reporting".
##
## On a codegen error, the material's shader and every uniform are left
## exactly as they were before the call (the caller keeps showing the last
## good preview), and the GSTCodegenResult carries the error for the panel's
## message label. On success, shader.code is written only when the text
## actually changed, then every uniform is written from the layer resources,
## restricted to uniforms the compiled shader actually declares: a coord
## block's scroll/warp_strength are omitted at zero (codegen mirrors this in
## GSTCodegen._coord_uniform_lines), so writing them unconditionally would
## either no-op against a nonexistent uniform or, worse, silently succeed
## against a stale one left over from a previous compile.

const SAFE_TRANSPARENT_SHADER_CODE: String = """shader_type canvas_item;

void fragment() {
	COLOR = vec4(0.0);
}
"""

var _material: ShaderMaterial = null
var _has_success: bool = false


func _init() -> void:
	reset_installation()


## Starts one stack installation with a distinct transparent material. Main
## calls this for every direct replacement and undo/redo replacement so a
## later failure cannot expose another installation's successful preview.
func reset_installation() -> void:
	_material = ShaderMaterial.new()
	_set_safe_transparent_shader()
	_has_success = false


func get_material() -> ShaderMaterial:
	return _material


func has_successful_preview() -> bool:
	return _has_success


## Synchronizes the active installation while retaining its last successful
## material on failure. Empty stacks clear any prior effect and return a
## non-error result with no generated code.
func sync_preview(stack: GSTStack, library: GSTLibrary, solo_layer_id: StringName, rect_size: Vector2) -> GSTCodegenResult:
	if stack == null:
		var null_result: GSTCodegenResult = GSTCodegenResult.new()
		null_result.error = "Cannot generate a preview without a stack."
		return null_result
	if stack.layers.is_empty():
		_set_safe_transparent_shader()
		_has_success = false
		return GSTCodegenResult.new()

	var result: GSTCodegenResult = sync(stack, library, _material, solo_layer_id, rect_size)
	if result.ok() and not result.code.is_empty():
		_has_success = true
	return result


func _set_safe_transparent_shader() -> void:
	var shader: Shader = Shader.new()
	shader.code = SAFE_TRANSPARENT_SHADER_CODE
	_material.shader = shader


## Regenerates `material`'s shader from `stack` (solo variant when
## `solo_layer_id` is non-empty) and writes every uniform GSTUniformNames
## would have declared, using `rect_size` for gst_rect_size (B5: the preview
## node's own rect, so `local` space matches `uv` at scale 1.0). Returns the
## GSTCodegenResult so the caller can show its error, if any.
static func sync(stack: GSTStack, library: GSTLibrary, material: ShaderMaterial, solo_layer_id: StringName, rect_size: Vector2) -> GSTCodegenResult:
	var result: GSTCodegenResult = GSTCodegen.generate_result(stack, library, solo_layer_id)
	if not result.ok():
		return result

	if material.shader == null:
		material.shader = Shader.new()
	if material.shader.code != result.code:
		material.shader.code = result.code

	var declared: Dictionary = _declared_uniform_names(material.shader)
	_write_uniforms(stack, library, material, rect_size, declared)
	return result


## Cheap resize path (B5): rewrites only gst_rect_size on `material`'s
## already-compiled shader, without touching shader.code or any other
## uniform. Called on every GSTPreview.target_rect_changed signal, which can
## fire once per frame during a splitter or window drag, so this never runs
## a codegen pass. No-op when the shader has no material/shader yet or does
## not declare gst_rect_size (coord space is not local).
static func write_rect_size(material: ShaderMaterial, rect_size: Vector2) -> void:
	if material == null or material.shader == null:
		return
	var declared: Dictionary = _declared_uniform_names(material.shader)
	_set_if_declared(material, declared, "gst_rect_size", rect_size)


static func _declared_uniform_names(shader: Shader) -> Dictionary:
	var names: Dictionary = {}
	for info: Dictionary in shader.get_shader_uniform_list():
		names[String(info["name"])] = true
	return names


static func _write_uniforms(stack: GSTStack, library: GSTLibrary, material: ShaderMaterial, rect_size: Vector2, declared: Dictionary) -> void:
	for layer: GSTLayer in stack.layers:
		var entry: GSTManifestEntry = library.get_entry(layer.entry)
		if entry == null:
			continue
		if layer.coord != null:
			_write_coord_uniforms(layer, material, declared)
		for param: Dictionary in entry.params:
			_write_param_uniform(layer, entry.function, param, material, declared)
	_set_if_declared(material, declared, "gst_rect_size", rect_size)


## Mirrors GSTCodegen._coord_uniform_lines exactly: scale/offset/rotation are
## always declared for a generator, scroll only when nonzero at the codegen
## call that produced the current shader.code, warp_strength only when a
## warp slot is set. _set_if_declared checks the compiled shader's own
## uniform list rather than re-deriving those conditions here, so this stays
## correct even if that emission logic changes without this file changing.
static func _write_coord_uniforms(layer: GSTLayer, material: ShaderMaterial, declared: Dictionary) -> void:
	var coord: GSTCoordBlock = layer.coord
	_set_if_declared(material, declared, GSTUniformNames.coord_scale(layer.id), coord.scale)
	_set_if_declared(material, declared, GSTUniformNames.coord_offset(layer.id), coord.offset)
	_set_if_declared(material, declared, GSTUniformNames.coord_rotation(layer.id), coord.rotation)
	_set_if_declared(material, declared, GSTUniformNames.coord_scroll(layer.id), coord.scroll)
	_set_if_declared(material, declared, GSTUniformNames.coord_warp_strength(layer.id), coord.warp_strength)


## Value type per uniform GLSL type (docs/PLAN.md Phase 5 Build: "Color
## params write Color, vec3 write Vector3, int write int"). Mirrors
## GSTCodegen._param_uniform_line's own type switch exactly, including its
## fallback: any type string other than "color"/"vec3"/"int" (currently only
## "float", since no manifest declares "vec2" yet) is declared as a plain
## GLSL float uniform there, so it is written as a float here too.
static func _write_param_uniform(layer: GSTLayer, function_name: String, param: Dictionary, material: ShaderMaterial, declared: Dictionary) -> void:
	var param_name: String = param["name"]
	var param_type: String = param["type"]
	var uniform_name: String = GSTUniformNames.param_uniform(layer.id, function_name, param_name)
	var value: Variant = layer.params.get(param_name, param["default"])
	match param_type:
		"color":
			_set_if_declared(material, declared, uniform_name, value as Color)
		"vec3":
			_set_if_declared(material, declared, uniform_name, value as Vector3)
		"int":
			_set_if_declared(material, declared, uniform_name, int(value))
		_:
			_set_if_declared(material, declared, uniform_name, float(value))


static func _set_if_declared(material: ShaderMaterial, declared: Dictionary, uniform_name: String, value: Variant) -> void:
	if not declared.has(uniform_name):
		return
	material.set_shader_parameter(uniform_name, value)
