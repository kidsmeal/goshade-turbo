extends SceneTree

## Records vortex_portal.tscn as a side-by-side PNG sequence for
## docs/media/vortex_portal.gif: left the raw GPUParticles2D SubViewport,
## right the same SubViewport read through the metaball portal export.
## Needs a GPU session and a fixed frame rate so particle motion matches the
## GIF timing:
## `godot --path . --rendering-driver opengl3 --fixed-fps 20 -s res://sandbox/vortex/record_vortex_frames.gd`
## Frames land in OUT_DIR (printed as an absolute path). Encode with:
## `ffmpeg -framerate 20 -i <dir>/frame_%03d.png -vf "split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer" -loop 0 docs/media/vortex_portal.gif`

const SCENE: String = "res://sandbox/vortex/vortex_portal.tscn"
const OUT_DIR: String = "user://vortex_frames"
const SOURCE_SIZE: int = 512
const PANEL: int = 256
const GAP: int = 8
const SETTLE_FRAMES: int = 60
const FRAMES: int = 120
const BACKGROUND: Color = Color(0.11, 0.11, 0.13, 1.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	RenderingServer.set_default_clear_color(BACKGROUND)
	var packed: PackedScene = load(SCENE)
	if packed == null:
		print("VORTEX_FRAMES FAIL scene did not load: %s" % SCENE)
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	var sub: SubViewport = scene.get_node("Sub")
	var out_abs: String = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_abs)
	for file: String in DirAccess.get_files_at(out_abs):
		DirAccess.remove_absolute(out_abs.path_join(file))

	for i: int in range(SETTLE_FRAMES):
		await process_frame

	var source_rect: Rect2i = Rect2i(0, 0, SOURCE_SIZE, SOURCE_SIZE)
	for i: int in range(FRAMES):
		await process_frame
		var particles: Image = sub.get_texture().get_image()
		particles.convert(Image.FORMAT_RGBA8)
		var left: Image = Image.create_empty(SOURCE_SIZE, SOURCE_SIZE, false, Image.FORMAT_RGBA8)
		left.fill(BACKGROUND)
		left.blend_rect(particles, source_rect, Vector2i.ZERO)
		var right: Image = root.get_texture().get_image().get_region(source_rect)
		right.convert(Image.FORMAT_RGBA8)
		left.resize(PANEL, PANEL, Image.INTERPOLATE_LANCZOS)
		right.resize(PANEL, PANEL, Image.INTERPOLATE_LANCZOS)
		var frame: Image = Image.create_empty(PANEL * 2 + GAP, PANEL, false, Image.FORMAT_RGBA8)
		frame.fill(BACKGROUND)
		frame.blit_rect(left, Rect2i(0, 0, PANEL, PANEL), Vector2i.ZERO)
		frame.blit_rect(right, Rect2i(0, 0, PANEL, PANEL), Vector2i(PANEL + GAP, 0))
		var err: Error = frame.save_png(out_abs.path_join("frame_%03d.png" % i))
		if err != OK:
			print("VORTEX_FRAMES FAIL save frame %d: %s" % [i, error_string(err)])
			quit(1)
			return

	print("VORTEX_FRAMES PASS %d frames in %s" % [FRAMES, out_abs])
	quit(0)
