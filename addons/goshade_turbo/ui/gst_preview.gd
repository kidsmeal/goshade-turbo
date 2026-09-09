@tool
class_name GSTPreview
extends Control

## Live preview column (decision 13, decision 10). Built entirely in script
## rather than via .tscn nodes (matching gst_inspector_column.gd's own
## programmatic-EditorInspector pattern), so every enum-valued property
## (SubViewport.render_target_update_mode, TextureRect.stretch_mode /
## expand_mode, BackBufferCopy.copy_mode) is set through its named GDScript
## constant instead of a hand-typed .tscn ordinal.
##
## Tree: opaque checkerboard (outside the SubViewport, UI only), then a
## transparent SubViewportContainer using premultiplied-alpha blending. Inside
## the SubViewport: preview image, BackBufferCopy, a blend-disabled transparent
## clear, then the active preset target. Screen-source shaders sample the saved
## preview image while target transparency reveals the checkerboard without
## putting it in pixel readback.

## Fires whenever the active target node's own rect size changes: an editor
## window resize, an HSplitContainer drag, or set_preset swapping the target
## node to a preset with a different natural size. GSTMainPanel connects this
## to a cheap gst_rect_size-only uniform write (B5), never a full codegen
## pass, since this can fire every frame during a drag.
signal target_rect_changed(size: Vector2)

const DEFAULT_SIZE: Vector2i = Vector2i(256, 256)
const DEFAULT_IMAGE_PATH: String = "res://addons/goshade_turbo/assets/preview_default.png"
const CHECKER_SHADER_CODE: String = """shader_type canvas_item;
void fragment() {
	vec2 cell = floor(FRAGCOORD.xy / 16.0);
	float alternate = mod(cell.x + cell.y, 2.0);
	COLOR = vec4(vec3(mix(0.30, 0.42, alternate)), 1.0);
}
"""
const BACKGROUND_CAPTURE_SHADER_CODE: String = """shader_type canvas_item;
render_mode blend_disabled;
void fragment() {
	COLOR = texture(TEXTURE, UV);
}
"""
const TRANSPARENT_CLEAR_SHADER_CODE: String = """shader_type canvas_item;
render_mode blend_disabled;
void fragment() {
	COLOR = vec4(0.0);
}
"""

var _checkerboard: ColorRect = null
var _viewport_container: SubViewportContainer = null
var _viewport: SubViewport = null
var _background: TextureRect = null
var _back_buffer_copy: BackBufferCopy = null
var _transparent_clear: ColorRect = null
var _target_node: Control = null
var _material: ShaderMaterial = null
var _preset_name: String = GSTPreviewPresets.SPRITE
var _preview_image: Texture2D = null


func _ready() -> void:
	_checkerboard = ColorRect.new()
	_checkerboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_checkerboard.set_anchors_preset(Control.PRESET_FULL_RECT)
	var checker_material: ShaderMaterial = ShaderMaterial.new()
	checker_material.shader = Shader.new()
	checker_material.shader.code = CHECKER_SHADER_CODE
	_checkerboard.material = checker_material
	add_child(_checkerboard)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport_material: CanvasItemMaterial = CanvasItemMaterial.new()
	viewport_material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_viewport_container.material = viewport_material
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.size = DEFAULT_SIZE
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_container.add_child(_viewport)

	_background = TextureRect.new()
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	var background_material: ShaderMaterial = ShaderMaterial.new()
	background_material.shader = Shader.new()
	background_material.shader.code = BACKGROUND_CAPTURE_SHADER_CODE
	_background.material = background_material
	_viewport.add_child(_background)

	_back_buffer_copy = BackBufferCopy.new()
	_back_buffer_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_viewport.add_child(_back_buffer_copy)

	_transparent_clear = ColorRect.new()
	_transparent_clear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transparent_clear.set_anchors_preset(Control.PRESET_FULL_RECT)
	var clear_material: ShaderMaterial = ShaderMaterial.new()
	clear_material.shader = Shader.new()
	clear_material.shader.code = TRANSPARENT_CLEAR_SHADER_CODE
	_transparent_clear.material = clear_material
	_viewport.add_child(_transparent_clear)

	_preview_image = load(DEFAULT_IMAGE_PATH) as Texture2D
	_background.texture = _preview_image

	set_preset(_preset_name)


## Not named set_material: Control (CanvasItem) already declares a
## set_material(Material) setter for its own `material` property, and a
## ShaderMaterial-typed parameter here would not match that signature
## (verified: `godot --headless --path . --import` raised "Parse Error:
## Could not resolve external class member 'set_material'" before this
## rename). This assigns the shared instance to whichever node is the
## current preset's target, not to GSTPreview's own inherited `material`.
##
## The ShaderMaterial instance stays fixed across preset switches:
## set_preset reassigns it to whichever node is the new target, never
## replaces it.
func set_shader_material(material: ShaderMaterial) -> void:
	_material = material
	if _target_node != null:
		_target_node.material = _material


func set_preset(preset_name: String) -> void:
	_preset_name = preset_name
	var new_node: Control = GSTPreviewPresets.build(preset_name, _preview_image)
	new_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	new_node.material = _material
	if _target_node != null:
		_viewport.remove_child(_target_node)
		_target_node.queue_free()
	_viewport.add_child(new_node)
	_target_node = new_node
	_target_node.resized.connect(_on_target_resized)
	target_rect_changed.emit(get_target_rect_size())


## The old target node's `resized` connection is severed automatically when
## it is freed in set_preset, so only the current target node is ever
## connected here.
func _on_target_resized() -> void:
	target_rect_changed.emit(get_target_rect_size())


## Sets the bundled/picked preview image on the background and, when the
## active preset is a TextureRect (sprite), on the target node too.
func set_image(texture: Texture2D) -> void:
	_preview_image = texture
	_background.texture = texture
	if _target_node is TextureRect:
		(_target_node as TextureRect).texture = texture


## Pixel readback for tests (docs/PLAN.md Phase 1 spike: SubViewport.
## get_texture().get_image() works in the editor; null under --headless).
## Wired-by: none (editor smoke seam)
func get_viewport_image() -> Image:
	return _viewport.get_texture().get_image()


## The preview node's own rect size, fed to material sync as gst_rect_size
## (B5) so `local` space matches `uv` at scale 1.0.
func get_target_rect_size() -> Vector2:
	return Vector2(_viewport.size)


## The active target node's own material property, for a test to confirm the
## same ShaderMaterial instance survives a preset switch rather than a copy.
## Wired-by: none (editor smoke seam)
func get_current_target_material() -> ShaderMaterial:
	return _target_node.material as ShaderMaterial if _target_node != null else null
