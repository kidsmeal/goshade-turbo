@tool
class_name GSTPreview
extends Control

## Live preview column. Built in script rather than .tscn so every
## enum-valued property (SubViewport.render_target_update_mode,
## TextureRect.stretch_mode / expand_mode, BackBufferCopy.copy_mode) is set
## through its named constant instead of a .tscn ordinal.
##
## Tree: opaque checkerboard (outside the SubViewport, UI only), then a
## transparent SubViewportContainer using premultiplied-alpha blending. Inside
## the SubViewport: preview image, BackBufferCopy, a blend-disabled transparent
## clear, then the active preset target. Screen-source shaders sample the
## preview image; target transparency reveals the checkerboard without putting
## it in pixel readback.

## Fires when the active target node's rect size changes (window resize,
## splitter drag, set_preset). Can fire every frame during a drag, so
## GSTMainPanel connects it to GSTMaterialSync.write_rect_size, never a
## codegen pass.
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


## Not named set_material: CanvasItem declares set_material(Material) for its
## own `material` property, and a ShaderMaterial-typed override fails to
## parse. Assigns the shared instance to the current preset's target node,
## not to GSTPreview's own `material`. The instance stays fixed across preset
## switches; set_preset reassigns it, never replaces it.
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


## Only the current target node is connected: freeing the old one in
## set_preset severs its `resized` connection.
func _on_target_resized() -> void:
	target_rect_changed.emit(get_target_rect_size())


## Sets the preview image on the background and, when the active preset is a
## TextureRect (sprite), on the target node.
func set_image(texture: Texture2D) -> void:
	_preview_image = texture
	_background.texture = texture
	if _target_node is TextureRect:
		(_target_node as TextureRect).texture = texture


## Pixel readback for tests. Returns null under --headless.
## Wired-by: none (editor smoke seam)
func get_viewport_image() -> Image:
	return _viewport.get_texture().get_image()


## The preview node's rect size, fed to material sync as gst_rect_size so
## `local` space matches `uv` at scale 1.0.
func get_target_rect_size() -> Vector2:
	return Vector2(_viewport.size)


## The active target node's material, for a test to confirm the same
## ShaderMaterial instance survives a preset switch.
## Wired-by: none (editor smoke seam)
func get_current_target_material() -> ShaderMaterial:
	return _target_node.material as ShaderMaterial if _target_node != null else null


## Reinstalls the default preview image. Document activation calls this for a
## document whose preview_image_path is "", so a previous document's picked
## image does not persist. Routes through set_image.
## Wired-by: gst_main_panel.gd (document activation).
func reset_image() -> void:
	set_image(load(DEFAULT_IMAGE_PATH) as Texture2D)


## Stops the shared SubViewport rendering while the GoShade tab is hidden and
## resumes it when shown. Document material/state is untouched.
## Wired-by: gst_main_panel.gd (_on_panel_visibility_changed).
func set_active(active: bool) -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED


## The shared SubViewport's current update mode, for a test to confirm
## set_active's effect.
## Wired-by: none (editor smoke seam)
func get_update_mode() -> SubViewport.UpdateMode:
	return _viewport.render_target_update_mode
