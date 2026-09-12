extends SceneTree

## Writes sandbox/logo/logo.tscn from scratch:
## `godot --headless --path . -s res://sandbox/logo/build_logo_scene.gd [-- --font brunoace]`
## Default font is zendots (decision 2026-09-11).
## Text SubViewport (square, transparent): two stacked Labels in the chosen
## font with a FontVariation shear. Out SubViewport (square, transparent):
## a Sprite2D showing the Text viewport through logo.gdshader. A Preview
## sprite on the root shows Out in the editor. Overwrites the .tscn, so any
## editor edits to it are lost; re-run only to reset. Font, size, shear and
## text are the constants at the top.

const SCENE_OUT: String = "res://sandbox/logo/logo.tscn"
const SHADER: String = "res://sandbox/logo/logo.gdshader"
const FONTS: Dictionary = {
	"brunoace": "res://sandbox/logo/fonts/BrunoAceSC-Regular.ttf",
	"zendots": "res://sandbox/logo/fonts/ZenDots-Regular.ttf",
}
const SIZE: int = 2048
const LINES: Array[String] = ["GOSHADE", "TURBO"]
const FONT_SIZES: Array[int] = [256, 256]
const SLANT: float = 0.18
const LINE_GAP: int = -40


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var font_key: String = "zendots"
	var idx: int = args.find("--font")
	if idx != -1 and idx + 1 < args.size():
		font_key = args[idx + 1]
	if not FONTS.has(font_key):
		print("SCENE FAIL unknown font %s (have %s)" % [font_key, FONTS.keys()])
		quit(1)
		return

	var root: Node2D = Node2D.new()
	root.name = "Logo"

	var text_vp: SubViewport = SubViewport.new()
	text_vp.name = "Text"
	text_vp.size = Vector2i(SIZE, SIZE)
	text_vp.transparent_bg = true
	text_vp.disable_3d = true
	text_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(text_vp)
	text_vp.owner = root

	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	text_vp.add_child(center)
	center.owner = root

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Lines"
	column.add_theme_constant_override("separation", LINE_GAP)
	center.add_child(column)
	column.owner = root

	var variation: FontVariation = FontVariation.new()
	variation.base_font = load(FONTS[font_key])
	# Fake italic. Godot applies this transform transposed relative to a
	# plain Transform2D: the slant goes in the x axis (docs example
	# Transform2D(1.0, slant, 0.0, 1.0, 0.0, 0.0)). Putting it in the y axis
	# skews the horizontals instead (verified 2026-09-11).
	variation.variation_transform = Transform2D(Vector2(1.0, SLANT), Vector2(0.0, 1.0), Vector2.ZERO)

	for i: int in range(LINES.size()):
		var label: Label = Label.new()
		label.name = "Line%d" % i
		label.text = LINES[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var settings: LabelSettings = LabelSettings.new()
		settings.font = variation
		settings.font_size = FONT_SIZES[i]
		settings.font_color = Color.WHITE
		label.label_settings = settings
		column.add_child(label)
		label.owner = root

	var out_vp: SubViewport = SubViewport.new()
	out_vp.name = "Out"
	out_vp.size = Vector2i(SIZE, SIZE)
	out_vp.transparent_bg = true
	out_vp.disable_3d = true
	out_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(out_vp)
	out_vp.owner = root

	var text_tex: ViewportTexture = ViewportTexture.new()
	text_tex.viewport_path = NodePath("Text")
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(SHADER)
	var shaded: Sprite2D = Sprite2D.new()
	shaded.name = "Logo"
	shaded.position = Vector2(SIZE / 2.0, SIZE / 2.0)
	shaded.texture = text_tex
	shaded.material = material
	out_vp.add_child(shaded)
	shaded.owner = root

	var out_tex: ViewportTexture = ViewportTexture.new()
	out_tex.viewport_path = NodePath("Out")
	var preview: Sprite2D = Sprite2D.new()
	preview.name = "Preview"
	preview.position = Vector2(SIZE / 2.0, SIZE / 2.0)
	preview.texture = out_tex
	root.add_child(preview)
	preview.owner = root

	var packed: PackedScene = PackedScene.new()
	var pack_err: Error = packed.pack(root)
	if pack_err != OK:
		print("SCENE FAIL pack: %s" % error_string(pack_err))
		quit(1)
		return
	var save_err: Error = ResourceSaver.save(packed, SCENE_OUT)
	if save_err != OK:
		print("SCENE FAIL save: %s" % error_string(save_err))
		quit(1)
		return
	print("SCENE PASS %s font=%s" % [SCENE_OUT, font_key])
	quit(0)
