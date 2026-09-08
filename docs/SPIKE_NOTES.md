# Phase 1 API spike results

Run 2026-09-07 against `Godot_v4.6.2-stable_win64.exe`. Source: `docs/PLAN.md`, Phase 1 spike.

## Fix-pass update (2026-09-07): items (a)-(c) driven programmatically

Required fix 2 on the phase 1 review asked for items (a)-(c) to actually run
rather than stay carried forward as blocker B9. `addons/goshade_turbo/plugin.gd`
was temporarily rewritten to run the spike from `_enter_tree` (main screen
override, `EditorUndoRedoManager` round trip, a dock holding a `SubViewport`
running a fixed-color `ShaderMaterial`), launched with `godot --editor --path .`
from PowerShell, and self-quit via `get_tree().quit()` after recording results
to a scratch file. `plugin.gd` was restored to the `_enter_tree`/`_exit_tree`
skeleton immediately after. Full method-by-method detail is below; this
section states the final outcome.

Result: (a), (b), (c) all PASS. No `ERROR` lines appeared in the editor's
stdout for this run. B9 is closed; no blocker remains.

| Item | Result |
|---|---|
| (a) main screen tab (`_make_visible(true)` fires after `EditorInterface.set_main_screen_editor`) | PASS |
| (b) `EditorUndoRedoManager` round trip (`get_history_undo_redo(...).has_undo()`) | PASS |
| (c) `SubViewport` dock renders a `ShaderMaterial` on a `TextureRect` (readback center pixel `(1.0, 0.0, 0.0, 1.0)`) | PASS |
| (d) `group_uniforms L03_fbm;` compiles | PASS (unchanged, see below) |

## Fix-pass 3 update (2026-09-07): item (c) re-run with `TextureRect`

Required fix 1 on the phase 1 review (round 3) found that the fix-pass 2 run
of item (c) used a `ColorRect`, not the `TextureRect` `docs/PLAN.md:74`
requires. `plugin.gd` was again temporarily rewritten to run only item (c)
from `_enter_tree`, launched with `godot --editor --path .` from PowerShell,
and self-quit via `get_tree().quit()` after printing the result to stdout.
`plugin.gd` was restored to the `_enter_tree`/`_exit_tree` skeleton
immediately after, byte-identical to the prior committed-candidate version.

Result: PASS with `TextureRect`. B9 stays closed.

## (d) `group_uniforms L03_fbm;` compiles

Status: PASS. Verified headless.

Method: a throwaway `-s` script built a `Shader` with `shader_type canvas_item;`, a `group_uniforms L03_fbm;` line, two `uniform` declarations under it (`l3_fbm_octaves`, `l3_fbm_gain`), a minimal `fragment()`, then called `get_shader_uniform_list()`.

Result: `uniform_count=2`, exit 0. Confirms the B3-resolution token (`group_uniforms L<position>_<function>;`, e.g. `L03_fbm`) compiles on 4.6.2, consistent with the planner's earlier verification (`docs/PLAN.md`, Verified engine facts).

Script used (not committed, throwaway):

```gdscript
extends SceneTree

func _initialize() -> void:
	var code := "shader_type canvas_item;\n\ngroup_uniforms L03_fbm;\nuniform int l3_fbm_octaves : hint_range(1, 8) = 4;\nuniform float l3_fbm_gain : hint_range(0.2, 0.8) = 0.5;\n\nvoid fragment() {\n\tCOLOR = vec4(vec3(float(l3_fbm_octaves) * l3_fbm_gain), 1.0);\n}\n"
	var shader := Shader.new()
	shader.code = code
	var uniforms := shader.get_shader_uniform_list()
	print("uniform_count=", uniforms.size())
	if uniforms.size() > 0:
		quit(0)
	else:
		quit(1)
```

## (a) `_has_main_screen()` puts a tab next to 2D/3D/Script

Status: PASS. Verified in a real editor session (see "Fix-pass update" above).

Method: `plugin.gd` overrode `_has_main_screen() -> bool: return true`,
`_get_plugin_name() -> String: return "GoShade Turbo"`, and
`_make_visible(visible: bool)` to record when it was called with `true`.
After the plugin entered the tree and the editor had run several frames,
the spike called `EditorInterface.set_main_screen_editor("GoShade Turbo")`
and then checked the recorded flag.

Result: `_make_visible(true) fired after set_main_screen_editor=true`. The
editor registered the main screen tab and switching to it invoked
`_make_visible(true)` as expected. No error in the Output dock.

## (b) `EditorUndoRedoManager` round trip via `get_undo_redo()`

Status: PASS. Verified in a real editor session (see "Fix-pass update" above).

Method: created a throwaway `Resource`, set `resource_name = "before"`, then
`get_undo_redo().create_action("GST spike b")`,
`add_do_property(dummy, "resource_name", "after")`,
`add_undo_property(dummy, "resource_name", "before")`, `commit_action()`.
Checked `get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(dummy)).has_undo()`.

Result: `dummy.resource_name after commit=after,
get_history_undo_redo(...).has_undo()=true`. The commit applied the do
property immediately and the object's undo history recorded an undo step.

## (c) `SubViewport` in an editor dock renders a `ShaderMaterial` on a `TextureRect`

Status: PASS. Verified in a real editor session (see "Fix-pass 3 update" above).
Re-run for fix-pass 3; the fix-pass 2 run used a `ColorRect`, which did not
match `docs/PLAN.md:74`'s requirement of a `TextureRect`.

Method: `Control` dock added via `add_control_to_dock(DOCK_SLOT_RIGHT_UL, ...)`
holding a `SubViewport` (`render_target_update_mode = UPDATE_ALWAYS`, size
`64x64`) containing a `TextureRect` (`position = (0, 0)`, `size = (64, 64)`,
`stretch_mode = STRETCH_SCALE`) whose `texture` is a 64x64 `ImageTexture`
built from a solid-black `Image` and whose `material` is a `ShaderMaterial`
running a trivial `canvas_item` fragment shader that outputs solid red
regardless of the texture's own pixels (`COLOR = vec4(1.0, 0.0, 0.0, 1.0);`).
Waited 3 `process_frame`s, then read `sub_viewport.get_texture().get_image()`
and its center pixel (`get_pixel(32, 32)`).

Result: `image_null=false center_pixel=(1.0, 0.0, 0.0, 1.0)
expected=(1.0, 0.0, 0.0, 1.0) matched=true`. The `TextureRect`'s
`ShaderMaterial` overrode the source texture's black pixels and the readback
matched exactly; this is a non-headless run (`godot --editor --path .`),
consistent with the plan's verified `--headless` readback limitation.

## Summary

| Item | Result |
|---|---|
| (a) main screen tab | PASS, verified in a real editor session |
| (b) `EditorUndoRedoManager` round trip | PASS, verified in a real editor session |
| (c) `SubViewport` dock preview on a `TextureRect` | PASS, verified in a real editor session |
| (d) `group_uniforms L03_fbm;` compiles | PASS, verified headless |

Per the plan: "A failure here changes the design, not the code." All four
spike items pass on 4.6.2. B9 is closed; no blocker remains from the phase 1
spike.
