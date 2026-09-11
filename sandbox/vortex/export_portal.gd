extends SceneTree

## Exports sandbox/vortex/vortex_portal_stack.tres as the self-contained
## .gdshader vortex_portal.tscn uses:
## `godot --headless --path . -s res://sandbox/vortex/export_portal.gd`
## The .tres is the source of truth: edit it in the GoShade panel (or Export
## from the panel directly, same result). Pass `-- --rebuild` to reset the
## .tres to a fresh copy of the metaball_portal recipe, which discards any
## panel edits. The recipe is this same stack (flat fill base, source-luma
## edge band), so a rebuild and a panel-saved .tres export the same body.

const RECIPE: String = "res://addons/goshade_turbo/recipes/metaball_portal.tres"
const STACK_OUT: String = "res://sandbox/vortex/vortex_portal_stack.tres"
const SHADER_OUT: String = "res://sandbox/vortex/metaball_portal.gdshader"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var library: GSTLibrary = GSTLibrary.new()
	library.scan()
	var rebuild: bool = OS.get_cmdline_user_args().has("--rebuild") or not FileAccess.file_exists(STACK_OUT)
	var source: String = RECIPE if rebuild else STACK_OUT
	var loaded: Dictionary = GSTStackIO.load(source, library)
	if not loaded["ok"]:
		_fail("load %s: %s" % [source, loaded["reason"]])
		return
	var stack: GSTStack = loaded["stack"]
	if rebuild:
		var saved: Dictionary = GSTStackIO.save(stack, STACK_OUT)
		if not saved["ok"]:
			_fail("save stack: %s" % saved["reason"])
			return

	var result: Dictionary = GSTExport.write(stack, library, SHADER_OUT, true)
	if not result["ok"]:
		_fail("export: %s" % result["reason"])
		return
	print("EXPORT PASS %s -> %s (%s)" % [STACK_OUT, SHADER_OUT, "rebuilt from recipe" if rebuild else "from .tres"])
	quit(0)


func _fail(reason: String) -> void:
	print("EXPORT FAIL %s" % reason)
	quit(1)
