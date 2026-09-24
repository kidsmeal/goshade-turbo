extends Control

## Device check for exported shaders. Renders every shader built by
## build_mobile_shaders.gd on the default preview sprite in its own
## SubViewport, runs GSTRenderAssert on the readback, prints one
## "MOBILE <stem> PASS|FAIL" line each (adb logcat -s godot), then a summary,
## and leaves the grid on screen for a screenshot. Screen-reading shaders get
## the plain sprite drawn underneath first.

const SHADER_DIR: String = "res://sandbox/mobile/shaders"
const SPRITE: Texture2D = preload("res://addons/goshade_turbo/assets/preview_default.png")
const ShaderList = preload("res://sandbox/mobile/shader_list.gd")
const TILE: int = 128
const SETTLE_FRAMES: int = 6


func _ready() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color(0.11, 0.11, 0.13)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 8
	add_child(grid)
	print("MOBILE renderer=%s driver=%s adapter=%s" % [
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name(),
	])
	var passed: int = 0
	var failed: PackedStringArray = PackedStringArray()
	for stem: String in ShaderList.STEMS:
		var viewport: SubViewport = SubViewport.new()
		viewport.size = Vector2i(TILE, TILE)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var shader: Shader = load(SHADER_DIR.path_join(stem + ".gdshader"))
		# A screen-reading shader samples what is already drawn: give it the
		# plain sprite underneath, as a scene would.
		if shader.code.contains("hint_screen_texture"):
			var backdrop: TextureRect = TextureRect.new()
			backdrop.texture = SPRITE
			backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			backdrop.stretch_mode = TextureRect.STRETCH_SCALE
			backdrop.size = Vector2(TILE, TILE)
			viewport.add_child(backdrop)
			var copy: BackBufferCopy = BackBufferCopy.new()
			copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
			viewport.add_child(copy)
		var sprite: TextureRect = TextureRect.new()
		sprite.texture = SPRITE
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_SCALE
		sprite.size = Vector2(TILE, TILE)
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("gst_rect_size", Vector2(TILE, TILE))
		sprite.material = material
		viewport.add_child(sprite)
		var container: SubViewportContainer = SubViewportContainer.new()
		container.add_child(viewport)
		grid.add_child(container)
		for i: int in range(SETTLE_FRAMES):
			await get_tree().process_frame
		var reasons: Array[String] = GSTRenderAssert.check(viewport.get_texture().get_image())
		if reasons.is_empty():
			passed += 1
			print("MOBILE %s PASS" % stem)
		else:
			failed.append(stem)
			print("MOBILE %s FAIL %s" % [stem, reasons])
	print("MOBILE SUMMARY %s %d/%d failed=%s" % ["PASS" if failed.is_empty() else "FAIL", passed, ShaderList.STEMS.size(), failed])
