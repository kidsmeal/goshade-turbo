extends SceneTree

## Exports sandbox/vortex/vortex_portal_stack.tres as the self-contained
## .gdshader vortex_portal.tscn uses:
## `godot --headless --path . -s res://sandbox/vortex/export_portal.gd`
## The .tres is the source of truth: edit it in the GoShade panel (or Export
## from the panel directly, same result). Pass `-- --rebuild` to regenerate
## the .tres from the metaball_portal recipe plus the edits below, which
## discards any panel edits.
##
## Why the recipe alone reads fuzzy on a particle source: the recipe's base
## colour is the raw texture rgb (the soft circles' own grey rim), and its
## edge comes from filter/outline, an alpha-edge detector, which never fires
## on the particle viewport's soft alpha. Two stack edits fix both with roster
## ops only:
## - base: color/fill (flat, white by default; the "colour the vortex" slider)
##   replaces the raw source in mix 9's `a`
## - edge: a second smoothstep on the source luma just above the blob mask,
##   inverted and multiplied by the mask, is a crisp band along the blob
##   boundary; it replaces the outline in mix 10's `mask`, and the outline
##   layer is removed

const RECIPE: String = "res://addons/goshade_turbo/recipes/metaball_portal.tres"
const STACK_OUT: String = "res://sandbox/vortex/vortex_portal_stack.tres"
const SHADER_OUT: String = "res://sandbox/vortex/metaball_portal.gdshader"
const SOURCE_ID: StringName = &"0"
const MASK_ID: StringName = &"1"
const OUTLINE_ID: StringName = &"2"
const BASE_MIX_ID: StringName = &"9"
const EDGE_MIX_ID: StringName = &"10"
const INNER_EDGE0: float = 0.60
const INNER_EDGE1: float = 0.68


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var library: GSTLibrary = GSTLibrary.new()
	library.scan()
	var rebuild: bool = OS.get_cmdline_user_args().has("--rebuild") or not FileAccess.file_exists(STACK_OUT)
	var stack: GSTStack
	if rebuild:
		stack = _build_from_recipe(library)
		if stack == null:
			return
		var saved: Dictionary = GSTStackIO.save(stack, STACK_OUT)
		if not saved["ok"]:
			_fail("save stack: %s" % saved["reason"])
			return
	else:
		var loaded: Dictionary = GSTStackIO.load(STACK_OUT, library)
		if not loaded["ok"]:
			_fail("load stack: %s" % loaded["reason"])
			return
		stack = loaded["stack"]

	var result: Dictionary = GSTExport.write(stack, library, SHADER_OUT, true)
	if not result["ok"]:
		_fail("export: %s" % result["reason"])
		return
	print("EXPORT PASS %s -> %s (%s)" % [STACK_OUT, SHADER_OUT, "rebuilt from recipe" if rebuild else "from .tres"])
	quit(0)


func _build_from_recipe(library: GSTLibrary) -> GSTStack:
	var loaded: Dictionary = GSTStackIO.load(RECIPE, library)
	if not loaded["ok"]:
		_fail("load recipe: %s" % loaded["reason"])
		return null
	var stack: GSTStack = loaded["stack"]

	# Base: flat fill in place of the raw source rgb.
	var fill: GSTLayer = _add(stack, library, "color/fill", GSTLayer.Kind.COLOR, 2)
	fill.params = {"color": Color(1.0, 1.0, 1.0, 1.0)}
	if not _wire(stack, library, BASE_MIX_ID, "a", fill.id):
		return null

	# Edge band: mask * invert(inner mask), both from the source luma.
	var inner: GSTLayer = _add(stack, library, "fieldops/smoothstep", GSTLayer.Kind.FIELD, 3)
	inner.params = {"edge0": INNER_EDGE0, "edge1": INNER_EDGE1}
	var inv: GSTLayer = _add(stack, library, "fieldops/invert", GSTLayer.Kind.FIELD, 4)
	var edge: GSTLayer = _add(stack, library, "fieldops/multiply", GSTLayer.Kind.FIELD, 5)
	if not _wire(stack, library, inner.id, "x", SOURCE_ID):
		return null
	if not _wire(stack, library, inv.id, "x", inner.id):
		return null
	if not _wire(stack, library, edge.id, "a", MASK_ID):
		return null
	if not _wire(stack, library, edge.id, "b", inv.id):
		return null
	if not _wire(stack, library, EDGE_MIX_ID, "mask", edge.id):
		return null
	GSTStackOps.remove_layer(stack, OUTLINE_ID, library)
	return stack


func _add(stack: GSTStack, library: GSTLibrary, entry: String, kind: GSTLayer.Kind, index: int) -> GSTLayer:
	var layer: GSTLayer = GSTStackOps.add_layer(stack, entry, kind)
	layer.manifest = library.get_entry(entry)
	var moved: Dictionary = GSTStackOps.reorder_layer(stack, layer.id, index)
	if not moved["ok"]:
		_fail("reorder %s: %s" % [entry, moved["reason"]])
	return layer


func _wire(stack: GSTStack, library: GSTLibrary, layer_id: StringName, slot: String, target: StringName) -> bool:
	var wired: Dictionary = GSTStackOps.assign_slot(stack, layer_id, slot, target, library)
	if not wired["ok"]:
		_fail("wire %s.%s -> %s: %s" % [String(layer_id), slot, String(target), wired["reason"]])
	return wired["ok"]


func _fail(reason: String) -> void:
	print("EXPORT FAIL %s" % reason)
	quit(1)
