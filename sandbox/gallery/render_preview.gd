extends SceneTree

## Composes docs/media/preview_recipes.png, the store listing preview: every
## recipe tile from docs/media/recipes/ in a COLUMNS-wide grid with its name
## under it, and the wordmark in the free cells of the last row (needs a GPU
## session, same rule as tests/run_render_checks.gd):
## `godot --path . --rendering-driver opengl3 -s res://sandbox/gallery/render_preview.gd`
## Run sandbox/gallery/render_gallery.gd first; this script only reads its
## PNGs. Labels use the engine's default font.

const TILE_DIR: String = "res://docs/media/recipes"
const LOGO_PATH: String = "res://sandbox/logo/goshade_turbo_logo.png"
const OUT_PATH: String = "res://docs/media/preview_recipes.png"
const COLUMNS: int = 5
const TILE: int = 208
const LABEL_HEIGHT: int = 28
const GAP: int = 20
const MARGIN: int = 32
const FONT_SIZE: int = 17
const BACKGROUND: Color = Color(0.07, 0.07, 0.09, 1.0)
const LABEL_COLOR: Color = Color(0.82, 0.82, 0.86, 1.0)
const SETTLE_FRAMES: int = 6


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var names: PackedStringArray = PackedStringArray()
	for file: String in DirAccess.get_files_at(TILE_DIR):
		if file.get_extension() == "png":
			names.append(file.get_basename())
	names.sort()
	if names.is_empty():
		print("PREVIEW FAIL no tiles in %s; run render_gallery.gd first" % TILE_DIR)
		quit(1)
		return

	var rows: int = ceili(float(names.size()) / COLUMNS)
	var cell: Vector2i = Vector2i(TILE, TILE + LABEL_HEIGHT)
	var size: Vector2i = Vector2i(
		MARGIN * 2 + COLUMNS * TILE + (COLUMNS - 1) * GAP,
		MARGIN * 2 + rows * cell.y + (rows - 1) * GAP
	)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background: ColorRect = ColorRect.new()
	background.color = BACKGROUND
	background.size = Vector2(size)
	viewport.add_child(background)

	for i: int in range(names.size()):
		var origin: Vector2 = _cell_origin(i, cell)
		var tile: TextureRect = TextureRect.new()
		tile.texture = _texture(TILE_DIR.path_join(names[i] + ".png"))
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.stretch_mode = TextureRect.STRETCH_SCALE
		tile.position = origin
		tile.size = Vector2(TILE, TILE)
		viewport.add_child(tile)
		var label: Label = Label.new()
		label.text = names[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", FONT_SIZE)
		label.add_theme_color_override("font_color", LABEL_COLOR)
		label.position = origin + Vector2(0, TILE)
		label.size = Vector2(TILE, LABEL_HEIGHT)
		viewport.add_child(label)

	var free_cells: int = rows * COLUMNS - names.size()
	if free_cells > 0:
		var first: Vector2 = _cell_origin(names.size(), cell)
		var area: Vector2 = Vector2(free_cells * TILE + (free_cells - 1) * GAP, cell.y)
		var logo: TextureRect = TextureRect.new()
		logo.texture = _texture(LOGO_PATH)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.position = first + area * 0.1
		logo.size = area * 0.8
		viewport.add_child(logo)

	for frame: int in range(SETTLE_FRAMES):
		await process_frame
	var image: Image = viewport.get_texture().get_image()
	var err: Error = image.save_png(OUT_PATH)
	if err != OK:
		print("PREVIEW FAIL save %s: %s" % [OUT_PATH, error_string(err)])
		quit(1)
		return
	print("PREVIEW PASS %s %dx%d, %d tiles" % [OUT_PATH, size.x, size.y, names.size()])
	quit(0)


func _cell_origin(index: int, cell: Vector2i) -> Vector2:
	var column: int = index % COLUMNS
	var row: int = index / COLUMNS
	return Vector2(MARGIN + column * (TILE + GAP), MARGIN + row * (cell.y + GAP))


## docs/ carries a .gdignore, so its PNGs are read from disk, not imported.
func _texture(path: String) -> ImageTexture:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(image)
