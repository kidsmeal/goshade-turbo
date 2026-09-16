@tool
class_name GSTPreviewPresets
extends RefCounted

## Builds the preview target node per preset. Switching a preset swaps the
## node only; GSTPreview assigns the same ShaderMaterial instance to
## whichever node is active.

const SPRITE: String = "sprite"
const TEXT: String = "text"
const FULL_RECT: String = "full_rect"
const PRESET_NAMES: Array[String] = [SPRITE, TEXT, FULL_RECT]

const TEXT_LABEL: String = "GoShade"
const TEXT_FONT_SIZE: int = 96


## sprite: a TextureRect showing preview_image, aspect-correct and centered.
## text: a Label reading TEXT_LABEL at TEXT_FONT_SIZE.
## full_rect: a ColorRect filling the viewport.
## An unknown name falls back to sprite so GSTPreview never lacks a target.
static func build(preset_name: String, preview_image: Texture2D) -> Control:
	match preset_name:
		TEXT:
			return _build_text()
		FULL_RECT:
			return _build_full_rect()
		_:
			return _build_sprite(preview_image)


static func _build_sprite(preview_image: Texture2D) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.texture = preview_image
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	return rect


static func _build_text() -> Label:
	var label: Label = Label.new()
	label.text = TEXT_LABEL
	label.add_theme_font_size_override("font_size", TEXT_FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	return label


static func _build_full_rect() -> ColorRect:
	var rect: ColorRect = ColorRect.new()
	rect.color = Color.WHITE
	return rect


## True when the text preset should suggest screen_uv (a suggestion, no
## automatic change). A Label draws one quad per glyph, each carrying that
## glyph's font-atlas UV rect rather than a 0..1 span across the label, so
## `uv` space is meaningless on the text preset; screen_uv is independent of
## the target's per-quad UV layout.
static func suggests_screen_uv(preset_name: String, coord_space: GSTStack.CoordSpace) -> bool:
	return preset_name == TEXT and coord_space == GSTStack.CoordSpace.UV
