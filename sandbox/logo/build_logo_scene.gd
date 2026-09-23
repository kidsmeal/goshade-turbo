extends SceneTree

## Writes sandbox/logo/logo.tscn from scratch:
## `godot --headless --path . -s res://sandbox/logo/build_logo_scene.gd [-- --font brunoace] [--icon]`
## Default font is zendots.
## Text SubViewport (square, transparent): two stacked Labels in the chosen
## font with a FontVariation shear. Out SubViewport (square, transparent):
## a Sprite2D showing the Text viewport through logo.gdshader. A Preview
## sprite on the root shows Out in the editor. Overwrites the .tscn, so any
## editor edits to it are lost. Font, size, shear and text are the constants
## at the top.
## `--icon` writes sandbox/logo/logo_icon.tscn instead: one Text SubViewport
## per ICON_LETTERS entry, each letter shifted by its ICON_OFFSETS entry, and
## one shaded Sprite2D per letter in Out, drawn in order so later letters sit
## in front with their own outline. Every Text viewport and sprite covers the
## full SIZE square at the same position, so the shader's UV-space gradient
## runs across the whole icon instead of restarting per letter.

const SCENE_OUT: String = "res://sandbox/logo/logo.tscn"
const ICON_SCENE_OUT: String = "res://sandbox/logo/logo_icon.tscn"
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
const ICON_LETTERS: Array[String] = ["G", "T"]
# T's bar top sits on the top edge of G's middle crossbar (measured at font
# size 820: crossbar top 259 px below G's top), its left cap overlapping G's
# right side.
const ICON_OFFSETS: Array[Vector2] = [Vector2(-333, -102), Vector2(176, 153)]
const ICON_FONT_SIZE: int = 820


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
	var icon: bool = args.has("--icon")
	var scene_out: String = ICON_SCENE_OUT if icon else SCENE_OUT

	var root: Node2D = Node2D.new()
	root.name = "Logo"

	var variation: FontVariation = FontVariation.new()
	variation.base_font = load(FONTS[font_key])
	# Fake italic. Godot applies variation_transform transposed relative to a
	# plain Transform2D: the slant goes in the x axis. Putting it in the y
	# axis skews the horizontals instead.
	variation.variation_transform = Transform2D(Vector2(1.0, SLANT), Vector2(0.0, 1.0), Vector2.ZERO)

	# [viewport name, sprite name, lines, font sizes, offset]
	var layers: Array = []
	if icon:
		for i: int in range(ICON_LETTERS.size()):
			var sizes: Array[int] = [ICON_FONT_SIZE]
			var lines: Array[String] = [ICON_LETTERS[i]]
			layers.append(["Text" + ICON_LETTERS[i], "Logo" + ICON_LETTERS[i], lines, sizes, ICON_OFFSETS[i]])
	else:
		layers.append(["Text", "Logo", LINES, FONT_SIZES, Vector2.ZERO])

	for layer: Array in layers:
		_add_text_viewport(root, layer[0], layer[2], layer[3], layer[4], variation)

	var out_vp: SubViewport = SubViewport.new()
	out_vp.name = "Out"
	out_vp.size = Vector2i(SIZE, SIZE)
	out_vp.transparent_bg = true
	out_vp.disable_3d = true
	out_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(out_vp)
	out_vp.owner = root

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(SHADER)
	for layer: Array in layers:
		var text_tex: ViewportTexture = ViewportTexture.new()
		text_tex.viewport_path = NodePath(layer[0])
		var shaded: Sprite2D = Sprite2D.new()
		shaded.name = layer[1]
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
	var save_err: Error = ResourceSaver.save(packed, scene_out)
	if save_err != OK:
		print("SCENE FAIL save: %s" % error_string(save_err))
		quit(1)
		return
	print("SCENE PASS %s font=%s" % [scene_out, font_key])
	quit(0)


func _add_text_viewport(root: Node, vp_name: String, lines: Array[String], font_sizes: Array[int], offset: Vector2, variation: FontVariation) -> void:
	var text_vp: SubViewport = SubViewport.new()
	text_vp.name = vp_name
	text_vp.size = Vector2i(SIZE, SIZE)
	text_vp.transparent_bg = true
	text_vp.disable_3d = true
	text_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(text_vp)
	text_vp.owner = root

	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_left = offset.x
	center.offset_right = offset.x
	center.offset_top = offset.y
	center.offset_bottom = offset.y
	text_vp.add_child(center)
	center.owner = root

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Lines"
	column.add_theme_constant_override("separation", LINE_GAP)
	center.add_child(column)
	column.owner = root

	for i: int in range(lines.size()):
		var label: Label = Label.new()
		label.name = "Line%d" % i
		label.text = lines[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var settings: LabelSettings = LabelSettings.new()
		settings.font = variation
		settings.font_size = font_sizes[i]
		settings.font_color = Color.WHITE
		label.label_settings = settings
		column.add_child(label)
		label.owner = root
