# GoShade Turbo v0.1 - Implementation Plan

Source design: `docs/DESIGN.md`
Conventions read: none exist. Checked and absent: `CLAUDE.md`, `AGENTS.md`, `CONVENTIONS.md`, `STYLE.md`, `CONTRIBUTING.md`, `docs/CONVENTIONS.md`, `docs/INDEX.md`, `docs/ARCHITECTURE.md`, `docs/GLOSSARY.md`. Repo holds one commit (`.gitignore`) and no code. The implementer follows Godot 4.4 GDScript style: tabs, static typing on every declaration and return, `snake_case` file and member names, `PascalCase` `class_name` with the `GST` prefix (design decision 18), `@export` for inspector-facing fields, double-quoted strings.

Verification commands (all verified against `Godot_v4.6.2-stable_win64.exe` on 2026-09-07):

- Prerequisite, run once after clone and after adding any new `class_name` script: `godot --headless --path . --import`
- Codegen and unit tests: `godot --headless --path . -s res://tests/run_codegen_tests.gd`
- Rendered checks: `godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd`

The runner is created in phase 1. `godot` resolves to a local wrapper script for 4.6.2, verified on PATH.

### Verified engine facts this plan depends on

- `godot --headless --path <dir> -s res://<script>.gd` runs a `SceneTree`-extending script and exits cleanly. Verified.
- A `class_name` global fails with `Parse error` in a `-s` run when `.godot/global_script_class_cache.cfg` is absent. `godot --headless --path . --import` creates it and the same script then runs. Verified by reproducing both states.
- `.tres` stores a multi-line `String` with literal newlines, so an embedded GLSL `code` field stays line-diffable in git. Verified by saving a custom `Resource` and reading the file bytes.
- The `--headless` dummy rendering driver **does** parse shaders and report compile errors. `Shader.get_shader_uniform_list().size()` returns `0` on a failed compile and the real count on success, so "entry compiles alone" checks run headless. Verified.
- The `--headless` dummy rendering driver **cannot** read back pixels. `SubViewport.get_texture().get_image()` returns `null` with `ERROR: Parameter "t" is null. at: texture_2d_get (dummy/storage/texture_storage.h:106)`. Verified.
- The same scene under `--rendering-driver opengl3` without `--headless` returns a `64x64` image with correct per-pixel values. Verified on an NVIDIA RTX 5070 Ti Laptop GPU. Rendered checks therefore require a GPU and a display session; they are not CI-headless.
- `group_uniforms 3 fbm;` fails to compile: `SHADER ERROR: Expected an uniform group identifier.` A single identifier (`group_uniforms l3_fbm;`) and a dotted subgroup (`group_uniforms L03.fbm;`) both compile. Verified. See Blocker B3.
- Capsule Castle `shaders/` exists and contains `hsv2rgb`, `noise`, `palette`, `random` inline in `sprite/*.gdshader`, plus `SpriteHolographic`, `SpritePearl`, `SpriteGoldFoil`, `SpriteIridescent`. Verified by grep. Design line 121 and the sprite-finish recipe (line 131) have real source material.
- `EditorPlugin._has_main_screen()` / `_make_visible()` / `_get_plugin_name()` / `_get_plugin_icon()`, `EditorUndoRedoManager` via `EditorPlugin.get_undo_redo()`, `SubViewport`, and `group_uniforms` all predate 4.4. Unverified against a 4.4 binary because none is installed (see Blocker B2). Phase 1 spikes each on 4.6.2.

## Summary

Eight phases build a `canvas_item` shader-stack editor plugin: data model and headless test runner, codegen for generators and field ops, codegen for sources/filters/color/alpha, the editor main screen UI, the preview column, persistence and export, a three-recipe end-to-end proof with the rendered-check harness, then roster completion and the release checklist. Phases 1-3 are architectural risk, 4-6 are the editor surface, 7-8 are bulk fill plus verification. The count exceeds the usual 4-7 because design build-order steps 2 and 5 each hold more than one implementer session of work and are split here.

## Decisions made at planning

- **Manifest file format: `.tres`.** Owner: planner. Verified above that `.tres` keeps the multi-line GLSL `code` field line-diffable while JSON would escape it to a single line, and the design already uses `.tres` for the Stack (decision 8) and recipes (line 123). Manifests are typed `GSTManifestEntry` resources loaded read-only. Closes the design's `Open` section.
- **Manifests are never re-saved by the plugin.** Owner: planner. `.tres` written by one engine version and re-saved by another churns tracked files (observed in a sibling project: 4.7 serializes bools differently from 4.6). Manifests are hand-written and load-only; no code path calls `ResourceSaver.save` on a file under `addons/goshade_turbo/library/`.
- **Two test runners, not one.** Owner: planner. Codegen text and shader-compile checks run under `--headless`; pixel readback runs under `--rendering-driver opengl3` without `--headless`. Forced by the verified dummy-driver readback failure.

## Blockers / Open Questions

B1, B3, B4, B5 resolved by the user 2026-09-07. B2, B6, B7, B8 resolved by the user 2026-09-08. No blocker remains open.

- **B1 (resolved):** `docs/` un-ignored in `.gitignore`. `docs/DESIGN.md`, this plan, `docs/SPIKE_NOTES.md`, and screenshots are tracked. Owner: user.
- **B2 (resolved 2026-09-08):** Binaries for the version matrix: 4.4 at `C:/Users/atk67/Downloads/Godot_v4.4-stable_win64.exe/Godot_v4.4-stable_win64.exe`, 4.6.2 via `godot` on PATH, 4.7 at `C:/Users/atk67/Documents/godot/Godot_v4.7-stable_win64.exe`. Phase 8 runs both test commands against each by absolute path. 4.7 re-saves `.tres` bools differently (plan decision "Manifests are never re-saved"): after any 4.7 run, `git status` must show no manifest churn. Owner: user.
- **B3 (resolved):** `group_uniforms L<position>_<function>;` with a two-digit zero-padded stack position, e.g. `group_uniforms L03_fbm;`. One identifier, sorts by stack position in the inspector, no subgroup nesting. Verified to compile on 4.6.2. Owner: user.
- **B4 (resolved):** Coord-block uniforms keep the short form `l<id>_scale`, `l<id>_offset`, `l<id>_rotation`, `l<id>_scroll`, `l<id>_warp_strength`. The coord block is not a function param, so it carries no function segment. Slider uniforms keep `l<id>_<function>_<param>`. Owner: user.
- **B5 (resolved):** `local_pos` is normalized. `vertex()` divides `VERTEX` by the node's rect size, passed as a `uniform vec2 gst_rect_size` that the plugin and the preview set from the target node. A coord-block `scale` of `1.0` then matches `uv`. The exported shader defaults `gst_rect_size` to `vec2(1.0)` and the README documents that a user must set it on nodes they attach the shader to. Owner: user.
- **B6 (resolved):** Filter-of-filter is refused in v0.1. A `samples_source` slot accepts only a `texture` or `screen` layer, matching decision 21 literally. The refusal reason names the slot and the offending layer. Owner: user.
- **B7 (resolved):** With two or more `texture` layers, output alpha defaults to `texture` alpha, which reads `texture(TEXTURE, UV).a` and is the same value for every texture layer, so no tiebreak is needed for the alpha expression. The output block's default color layer stays the top color layer. Owner: user.
- **B10 (resolved at phase 3):** Filters cannot be functions. Verified on 4.6.2: `TEXTURE` inside a user function fails with `Unknown identifier`, and `TEXTURE` passed as a `sampler2D` argument compiles but prints `ERROR: Condition "!actions.custom_samplers.has(...)"` on every compile. A plain `uniform sampler2D` would need the user to bind the node texture by hand on every exported shader, which breaks decision 6. Resolution: a filter manifest's `code` is an inline body template, expanded by codegen into a `{ }` block inside `fragment()` per filter layer. Tokens: `GST_SAMPLE(p)` expands to `texture(TEXTURE, p)` for a texture source or `texture(gst_screen_texture, p)` for a screen source; `GST_UV` to `UV` or `SCREEN_UV`; `GST_OUT` to the layer local; `GST_PARAM(name)` to the param's uniform name. No `gst_self_texture` uniform exists. Owner: orchestrator, on the engine evidence above.
- **B8 (resolved):** Reopen of a `.gdshader` with no `// stack:` header, an unparsable header, or an unknown schema version is refused with a message naming the file and the reason. No new empty stack is offered. Owner: user.

## Phase 1: Scaffold, data model, layer identity, test runner

**Status:** committed (a1fe516)
**Goal:** A loadable Godot project with an enabled `GST` plugin skeleton, the four resource classes, and a green headless test runner.
**Files:**
- `project.godot` (create)
- `addons/goshade_turbo/plugin.cfg` (create)
- `addons/goshade_turbo/plugin.gd` (create, `@tool`, `EditorPlugin`, `_enter_tree`/`_exit_tree` only)
- `addons/goshade_turbo/model/gst_stack.gd` (create, `class_name GSTStack`)
- `addons/goshade_turbo/model/gst_layer.gd` (create, `class_name GSTLayer`)
- `addons/goshade_turbo/model/gst_coord_block.gd` (create, `class_name GSTCoordBlock`)
- `addons/goshade_turbo/model/gst_manifest_entry.gd` (create, `class_name GSTManifestEntry`)
- `addons/goshade_turbo/model/gst_stack_ops.gd` (create, add/remove/reorder/slot-assign with the decision-22 rules)
- `addons/goshade_turbo/library/gst_library.gd` (create, scans `library/**/*.tres`, indexes by `id`, refuses a duplicate `function`: `add_entry` returns `false` and records the collision in `duplicate_functions`, never raises)
- `tests/gst_test_base.gd` (create, `assert_eq` / `assert_true` / `assert_false` / `assert_null` / `assert_not_null`, failure accumulation)
- `tests/gst_test_runner.gd` (create, `extends SceneTree`, discovers `tests/test_*.gd`, runs every `test_*` method, `quit(1)` on any recorded assertion failure)
- `tests/run_codegen_tests.gd` (create, `extends SceneTree`, outer wrapper: runs `gst_test_runner.gd` as a child process via `OS.execute`, captures combined stdout/stderr, exits 1 if the child exit code is nonzero or the captured output contains `SCRIPT ERROR`, `ERROR:`, or `Parse error`, else exits 0. This is the named verification command; the command line itself is unchanged.)
- `tests/test_layer_identity.gd` (create)
- `tests/test_stack_ops.gd` (create)
- `tests/test_library_index.gd` (create)
- `addons/goshade_turbo/library/generative/fbm.tres`, `library/generative/hash.tres`, `library/generative/snoise.tres` (create, three seed manifests only)
- `docs/SPIKE_NOTES.md` (create, results of the API spike)
- `**/*.gd.uid` (generated by Godot 4.4+ next to every script on import, committed per Godot guidance, never hand-edited)
- `NOW.md`, `docs/PLAN.md` (orchestrator state, edited by the pipeline scripts and the orchestrator, not by the implementer)

**Spike (do this first, inside this phase):** in a throwaway `@tool` script or the plugin's `_enter_tree`, confirm on 4.6.2 that (a) `_has_main_screen()` returning `true` puts a tab next to 2D/3D/Script, (b) `EditorPlugin.get_undo_redo()` returns an `EditorUndoRedoManager` and a `create_action`/`add_do_method`/`commit_action` round trip appears in the editor's undo history, (c) a `SubViewport` with `render_target_update_mode = UPDATE_ALWAYS` inside an editor dock renders a `ShaderMaterial` on a `TextureRect`, (d) the `group_uniforms` token chosen for B3 compiles. Record pass/fail per item in `docs/SPIKE_NOTES.md`. A failure here changes the design, not the code.

**Verification:**
- `godot --headless --path . --import` exits 0 and creates `.godot/global_script_class_cache.cfg`.
- `godot --headless --path . -s res://tests/run_codegen_tests.gd` exits 0.
- Tests assert: ids are monotonic and never reused across add/delete/add; reorder above a referenced layer is refused and returns the reason string; deleting a referenced layer resets each pointing slot to the below default and returns the list of changed layer ids; `GSTLibrary` indexes 3 entries and `add_entry` returns `false` and records the collision on a duplicate `function`.
- Manual: the plugin enables in Project Settings > Plugins with no error in the Output dock.

**Exit criteria:** Test runner is green, plugin enables cleanly, all four spike items recorded pass or the design gap is filed as a blocker.
**Blockers:** none. B9 (editor spike items a-c) closed, all four spike items PASS on 4.6.2, see `docs/SPIKE_NOTES.md`.
**Wired-by:** phase 2 (the model classes and library index get their first live consumer in codegen).

## Phase 2: Codegen core - generators and field ops

**Status:** committed (e271ab5)
**Goal:** A `GSTCodegen` that turns a stack of generators and field ops into compiling `.gdshader` text.
**Files:**
- `addons/goshade_turbo/codegen/gst_codegen.gd` (create)
- `addons/goshade_turbo/codegen/gst_uniform_names.gd` (create, the single source of uniform and group naming per B3/B4)
- `addons/goshade_turbo/codegen/gst_include_walk.gd` (create, depth-first over `depends`, dedupe by id)
- `addons/goshade_turbo/library/generative/*.tres` (create: value noise, perlin, simplex, fbm, voronoi, cellular edges, hash, checker, stripes, radial gradient, linear gradient)
- `addons/goshade_turbo/library/fieldops/*.tres` (create: smoothstep, invert, remap, multiply, add, max, min, mix, pow, abs, fract)
- `tests/test_codegen_generator.gd` (create)
- `tests/test_codegen_fieldop.gd` (create)
- `tests/test_include_walk.gd` (create)
- `tests/test_uniform_names.gd` (create)
- `tests/test_time_emission.gd` (create)
- `tests/test_coord_space.gd` (create)
- `tests/test_solo_output.gd` (create)
- `tests/gst_shader_compile.gd` (create, helper: build a `Shader`, set code, return `get_shader_uniform_list().size() > 0`)
- `tests/test_library_index.gd` (modify: roster count from 3 to 22, duplicate-function assertion over the full real scan)

**Verification:** `godot --headless --path . -s res://tests/run_codegen_tests.gd` exits 0, with tests covering:
- One generator plus one field op emits exactly two `fragment()` locals in stack order.
- Coord block emits `transform`, then the scroll term only when scroll is nonzero, then the warp term with a missing axis contributing `0.0`.
- `TIME` and the scroll uniform are both emitted or both absent (checklist item "TIME emitted only with nonzero scroll").
- Include walk deduplicates a shared `depends` entry to one function body and emits all bodies before `fragment()`.
- Uniform names and `group_uniforms` tokens match the B3/B4 resolution exactly.
- `uv` / `screen_uv` / `local` each emit the right coord source, `local` adds the `varying` and the `vertex()` function.
- Solo output replaces the output line with `vec4(vec3(lN), 1.0)` for a field layer.
- Every generated shader in every test above compiles (`gst_shader_compile.gd` returns true).

**Exit criteria:** All generative and field-op manifests exist, each compiles alone, and the codegen tests are green.
**Blockers:** none (B3, B4, B5 resolved).
**Wired-by:** phase 5 (the preview column is codegen's first live caller; phases 2-3 are exercised only by tests until then).

## Phase 3: Codegen - sources, filters, color ops, alpha

**Status:** committed (ccbbb72)
**Goal:** Codegen covers the remaining layer categories, including the filter source-only rule and every alpha path.
**Files:**
- `addons/goshade_turbo/codegen/gst_codegen.gd` (modify: color slot conversion, filter emission, output block)
- `addons/goshade_turbo/model/gst_stack_ops.gd` (modify: refuse a non-source input on a `samples_source` slot, with the reason string)
- `addons/goshade_turbo/library/source/texture.tres`, `library/source/screen.tres` (create)
- `addons/goshade_turbo/library/filter/*.tres` (create: pixelate, box blur, outline, chromatic split, dither; `code` is an inline body template per B10, not a function)
- `addons/goshade_turbo/library/color/*.tres` (create: fill, gradient map, palette, hue shift, saturation, brightness contrast, posterize, multiply, screen, overlay, add, soft light, mix)
- `addons/goshade_turbo/library/fieldops/alpha.tres` (create, `alpha(color) -> field`, decision 12)
- `tests/test_slot_conversion.gd` (create)
- `tests/test_filter_input_refusal.gd` (create)
- `tests/test_output_block.gd` (create)
- `tests/test_codegen_color.gd` (create)
- `addons/goshade_turbo/model/gst_manifest_entry.gd` (modify: `samples_source` and `code` contract comments per B10)
- `addons/goshade_turbo/codegen/gst_codegen_result.gd` (create, `GSTCodegenResult`: `code`, `error`, `ok()`, the invocation-local result of `GSTCodegen.generate_result`)
- `tests/test_library_index.gd` (modify: roster count and per-category presence checks)
- `docs/DESIGN.md` (modify: Codegen rules filter line per B10)
- `tests/test_codegen_fieldop.gd`, `tests/test_codegen_generator.gd`, `tests/test_solo_output.gd`, `tests/test_stack_ops.gd` (modify: `assign_slot` callers pass a `GSTLibrary`)

**Verification:** `godot --headless --path . -s res://tests/run_codegen_tests.gd` exits 0, with tests covering:
- Field into a color slot emits `vec4(vec3(lN), 1.0)`; color into a field slot emits `luma(lN)`; `luma` appears once in the include walk.
- Assigning a non-source layer to a `samples_source: true` slot is refused and returns a reason; assigning a `texture` or `screen` layer succeeds.
- A filter emits its neighbor sampling as `texture(TEXTURE, uv + offset)` (or the screen equivalent) inside an inline block in `fragment()` (B10); no `gst_self_texture` uniform is emitted.
- All four output alpha modes emit the right expression: `1.0`, `texture(TEXTURE, UV).a`, `l<c>.a`, `l<a>`.
- Every color entry and every filter entry compiles alone.

**Exit criteria:** Full v0.1 roster categories exist as manifests, every entry compiles alone, filter refusal is enforced at slot assignment rather than at codegen.
**Blockers:** none (B6, B7 resolved).
**Wired-by:** phase 5.

## Phase 4: Editor main screen UI and undo

**Status:** committed (c40118d)
**Goal:** A main screen tab with the three-column layout, a working stack list, the picker popup, the inspector column, and undo on every structural edit.
**Files:**
- `addons/goshade_turbo/plugin.gd` (modify: `_has_main_screen`, `_get_plugin_name`, `_get_plugin_icon`, `_make_visible`)
- `addons/goshade_turbo/ui/gst_main_panel.tscn` / `.gd` (create, three-column `HSplitContainer` layout)
- `addons/goshade_turbo/ui/gst_stack_list.tscn` / `.gd` (create, ordered list, add/remove/reorder, selection)
- `addons/goshade_turbo/ui/gst_picker.tscn` / `.gd` (create, grouped by taxonomy folder, search box, kind pre-filter, shows function name + kind signature + description)
- `addons/goshade_turbo/ui/gst_inspector_column.gd` (create, `EditorInspector` pointed at the selected `GSTLayer`)
- `addons/goshade_turbo/ui/gst_output_block.tscn` / `.gd` (create, color picker + alpha picker at the panel bottom)
- `addons/goshade_turbo/ui/gst_undo.gd` (create, wraps `EditorUndoRedoManager` for add/remove/reorder/slot change/output change)
- `addons/goshade_turbo/assets/gst_icon.svg` (create)
- `addons/goshade_turbo/model/gst_layer.gd` (modify: dynamic inspector properties for `params` via `_get_property_list` / `_get` / `_set` with `PROPERTY_HINT_RANGE` from the manifest, so decision 13's inspector column shows sliders; the layer holds a non-exported `manifest: GSTManifestEntry` reference set by the panel on add and on load)
- `tests/gst_editor_smoke.gd` (create, `@tool` script the plugin runs when the `GST_EDITOR_SMOKE` environment variable is set: performs the phase 4 verification steps programmatically inside a real editor session, prints one `SMOKE <item> PASS|FAIL <detail>` line per item, then quits the editor)
- `docs/EDITOR_SMOKE.md` (create, per-phase record of editor smoke results, method, and engine version; phases 5-8 append)
- `addons/goshade_turbo/codegen/gst_codegen.gd` (modify: `_main_output_line` defaults `output_color` to the top color layer; `_alpha_expr` resolves an unset alpha to `texture` when a texture source exists else `none`, and `color_alpha` reads the resolved color id)
- `addons/goshade_turbo/model/gst_stack.gd` (modify: `output_alpha` defaults to `&""` so unset and explicit `none` are distinct)
- `tests/test_output_block.gd` (modify: default resolution tests)
- `docs/DESIGN.md` (modify: decision 12 accepts a field output color layer)
- `**/*.gd.uid`, `**/*.tscn` sidecars and scenes generated or created alongside the scripts above
- `NOW.md`, `docs/PLAN.md` (orchestrator state, edited by the pipeline scripts and the orchestrator)
- `tests/test_library_index.gd` (modify: every manifest param type is a known type string)
- `addons/goshade_turbo/assets/gst_icon.svg.import` and any other `.import` sidecar Godot generates for assets under `addons/goshade_turbo/assets/`

**Verification:** editor smoke script (`godot --editor --path .` with `GST_EDITOR_SMOKE=4`, results recorded in `docs/EDITOR_SMOKE.md`) covering each item below, plus a manual pass by the user before release:
- Enable the plugin, open the tab, add a generator, a field op, and a second generator from the picker, wire the field op's slot to the first generator, move the second generator down one position (allowed, it references nothing), attempt to move the first generator above the field op (refused with the reason shown in the message label, no undo action registered), set the output color layer.
- Undo six times: the output change, the allowed reorder, the slot change, the third add, the second add, and the first add each revert in order, and the stack list redraws to match after every step. Pass condition is all six reverting and the undo history then empty; anything sticking is a fail.
- The output block shows the effective defaults (decision 12) when `output_color` or `output_alpha` is unset: the top color layer, and `texture` alpha when a texture source exists else `none`.
- Opening the picker from a field slot lists only field-kind entries; the search box filters within that set.
- A reorder that would move a layer above one it references shows the refusal reason in the UI rather than performing it.

**Exit criteria:** All six undo operations round-trip and the history is then empty, the picker filters by slot kind, refusals surface their reason string in the UI, the output block shows decision 12 defaults and codegen resolves the same defaults.
**Blockers:** none beyond phase 1 spike results.
**Wires:** `plugin.gd` registers the main screen tab, making the panel reachable from the editor.
**Wired-by:** phase 5 (the preview column is instanced inside `gst_main_panel.tscn`; the phase 4 `get_preview_slot()` accessor was removed in phase 5 as obsolete), phase 6 (`GSTMainPanel.set_stack()` is the open and reopen entry point).

## Phase 5: Preview column

**Status:** committed (da09d46)
**Goal:** Live preview of the current stack, with target presets, an image picker, and the solo toggle.
**Files:**
- `addons/goshade_turbo/ui/gst_preview.tscn` / `.gd` (create, `SubViewport` + `TextureRect` running the generated `ShaderMaterial`)
- `addons/goshade_turbo/ui/gst_preview_presets.gd` (create, sprite / text / full rect; swaps the preview node only)
- `addons/goshade_turbo/ui/gst_material_sync.gd` (create, rebuilds shader code and writes every uniform from the layer resources on change; layer resources are authoritative per decision 7)
- `addons/goshade_turbo/assets/preview_default.png` (create, bundled default sprite)
- `addons/goshade_turbo/ui/gst_main_panel.gd` (modify: mount the preview column, wire the solo toggle)
- `tests/test_material_sync.gd` (create, headless: given a stack, the synced `ShaderMaterial` exposes one uniform per param with the layer's value)
- `addons/goshade_turbo/ui/gst_main_panel.tscn` (modify: preview column mount, coord space `OptionButton` per decision 11, solo toggle, preset selector, preview image picker)
- `addons/goshade_turbo/ui/gst_undo.gd` (modify: `set_coord_space` action)
- `addons/goshade_turbo/ui/gst_inspector_column.gd` (modify: relays `EditorInspector.property_edited` as a `param_edited` signal so the panel resyncs on real slider edits)
- `tests/gst_editor_smoke.gd` (modify: `GST_EDITOR_SMOKE=5` section covering the manual items below, pixel readback from the preview `SubViewport`)
- `docs/EDITOR_SMOKE.md` (append: phase 5 run)
- `NOW.md`, `docs/PLAN.md` (orchestrator state), `**/*.gd.uid`, `**/*.import` sidecars

**Verification:**
- `godot --headless --path . -s res://tests/run_codegen_tests.gd` exits 0 including `test_material_sync.gd`.
- Editor smoke (`GST_EDITOR_SMOKE=5`, results in `docs/EDITOR_SMOKE.md`) covering each manual item below with a pixel readback where the item is visual, plus a manual pass by the user before release: move a slider in the inspector column and the preview changes within one frame; switch the preset from sprite to text and the preview node swaps while the material stays; the text preset suggests `screen_uv` when space is still `uv`; the solo toggle shows the selected layer (a field as grayscale) and returns to the output when untoggled, with the stack unchanged (verified by the stack list and the exported text being identical before and after toggling).

**Exit criteria:** Preview updates on every slider and structural change, all three presets render, solo toggle round-trips without mutating the stack, `screen` layers preview against the same image (decision 10), `gst_rect_size` is set from the preview node so `local` space matches `uv` at scale 1 (B5), a codegen error keeps the last good material and shows the message.
**Blockers:** none.
**Wires:** the preview column is the first live caller of `GSTCodegen` and `GSTLibrary` outside tests.

## Phase 6: Persistence and export

**Status:** committed (dc78be5)
**Goal:** Save and reopen a stack `.tres`, export a self-contained `.gdshader` with a JSON header, reopen from that header, and refuse a silent overwrite of a hand-edited body.
**Files:**
- `addons/goshade_turbo/io/gst_stack_io.gd` (create, save/load `GSTStack` `.tres`)
- `addons/goshade_turbo/io/gst_export.gd` (create, license notice + `// stack: <json>` one-line header + codegen body)
- `addons/goshade_turbo/io/gst_header.gd` (create, serialize/parse the stack JSON, version tag)
- `addons/goshade_turbo/io/gst_overwrite_check.gd` (create, compares the target file body to a fresh codegen of its own header)
- `addons/goshade_turbo/ui/gst_main_panel.gd` (modify: save / open / export buttons and the overwrite confirmation dialog)
- `tests/test_header_roundtrip.gd` (create)
- `tests/test_overwrite_check.gd` (create)
- `tests/test_stack_io.gd` (create)
- `addons/goshade_turbo/ui/gst_main_panel.tscn` (modify: save / open / export buttons, file dialogs, overwrite confirmation dialog)
- `addons/goshade_turbo/codegen/gst_codegen.gd` (modify: the header line is produced by `gst_header.gd`, one call site)
- `tests/gst_editor_smoke.gd` (modify: `GST_EDITOR_SMOKE=6` section covering the manual item below through the panel's button handlers)
- `docs/EDITOR_SMOKE.md` (append: phase 6 run)
- `sandbox/stacks/`, `sandbox/exports/` (create, gitkept, where the smoke writes its files; smoke output under `sandbox/` is deleted at the end of the run)
- `tests/test_codegen_generator.gd` (modify: the no-warp assertion scopes to the body below the header, since the real header serializes every coord field)
- `NOW.md`, `docs/PLAN.md` (orchestrator state), `**/*.gd.uid` sidecars

**Verification:** `godot --headless --path . -s res://tests/run_codegen_tests.gd` exits 0, with tests covering:
- Save a stack to `.tres`, reload it, and every field including `next_id`, slot references, and coord blocks compares equal.
- Export, parse the header back into a stack, re-codegen, and the body compares byte-equal to the exported body.
- Mutate one line of an exported body, run the overwrite check, and it reports a difference; leave it untouched and it reports none.
- The header is exactly one line and survives a body that contains `//` comments.
- Editor smoke (`GST_EDITOR_SMOKE=6`): export to a path that already holds a differing body and the confirmation dialog appears before any write; save, new, open round-trips the panel state; reopen from an exported `.gdshader` rebuilds the stack; reopen of a headerless file is refused with the message (B8).

**Exit criteria:** Round trip is byte-exact, the overwrite check catches a one-character body edit, no export path writes without confirmation when a difference exists.
**Blockers:** none (B8 resolved).
**Wires:** save / open / export buttons in the main panel.

## Phase 7: Three-recipe proof and the rendered-check harness

**Status:** pending
**Goal:** Dissolve, one sprite finish, and outline each build, save, reopen, export, and undo end to end, verified by an automated rendered check.
**Files:**
- `tests/run_render_checks.gd` (create, `extends SceneTree`, loads each stack, renders through a `SubViewport`, reads back the image)
- `tests/gst_render_assert.gd` (create: no NaN or inf pixel, alpha within `[0, 1]`, output not uniformly one value)
- `addons/goshade_turbo/recipes/dissolve.tres` (create, alpha path)
- `addons/goshade_turbo/recipes/sprite_holographic.tres` (create, color chain with scroll, ported from Capsule Castle `shaders/sprite/SpriteHolographic.gdshader`)
- `addons/goshade_turbo/recipes/outline.tres` (create, source filter path)
- `sandbox/stacks/` (create, the three recipes saved as user-side stacks)
- `tests/test_recipe_roundtrip.gd` (create, headless: each recipe saves, reopens, exports, and re-codegens byte-equal)

**Verification:**
- `godot --headless --path . -s res://tests/run_codegen_tests.gd` exits 0 including `test_recipe_roundtrip.gd`.
- `godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd` exits 0 for all three recipes. This command is not headless by design; the dummy driver returns a null image (verified).
- Manual: build each of the three recipes in the panel from the picker only, then undo every step back to an empty stack and redo forward to the same shader text.

**Exit criteria:** Three recipes pass the rendered checks, the round-trip test is byte-exact, and the undo/redo walk returns identical shader text. Do not start phase 8 before this passes; it is the design's gate on writing the rest of the library (build order step 4).
**Blockers:** rendered checks require a GPU session, so they cannot run in a headless CI container. Verified.
**Wires:** the render-check harness is the first consumer of exported stacks outside the editor.

## Phase 8: Roster completion, remaining recipes, release checklist

**Status:** pending
**Goal:** Every roster entry and all eight recipes exist, pass the combination and rendered checks, and the release checklist is green.
**Files:**
- `addons/goshade_turbo/library/sdf/*.tres` (create: circle, box, rounded box, polygon, star, line, ring, union, subtract, intersect, smooth union)
- `addons/goshade_turbo/library/**` (modify: any entry retuned by the tuning pass)
- `addons/goshade_turbo/recipes/water.tres`, `fire.tres`, `glow.tres`, `hologram.tres`, `metaball_portal.tres` (create; the remaining sprite finishes as additional `.tres`)
- `addons/goshade_turbo/ui/gst_randomize.gd` (create, sets every slider on the open recipe to a random value inside its manifest range)
- `addons/goshade_turbo/ui/gst_main_panel.gd` (modify: randomize button)
- `sandbox/stacks/*.tres` (create, one reference stack per roster entry at default sliders)
- `sandbox/screenshots/*.png` (create, one committed screenshot per reference stack)
- `tests/test_combinations.gd` (create: every field op with every generator as input compiles; every color op with every color entry as input compiles)
- `tests/test_randomize_range.gd` (create: randomized values stay inside the manifest min/max)
- `README.md` (create, MIT license notice, install, the `godot --headless --path . --import` prerequisite before the test command, the per-entry `source_math` / `source_code` citations required by decision 15)
- `LICENSE` (create, MIT)

**Verification:**
- `godot --headless --path . -s res://tests/run_codegen_tests.gd` exits 0 including `test_combinations.gd` and `test_randomize_range.gd`.
- `godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd` exits 0 over every reference stack and all eight recipes.
- The same two commands run against a 4.4 binary and a 4.7 binary (B2).
- Manual tuning pass by the user: every slider produces a visible change across its whole range. This is the user's sign-off, not the implementer's.

**Exit criteria:** Every box in the design's Release checklist is ticked, including the user's tuning sign-off and the three-version run.
**Blockers:** B2 (4.4 and 4.7 binaries not installed).
**Wires:** randomize button on the open recipe.

## Cross-cutting concerns

**Uniform and group naming (`gst_uniform_names.gd`)**
- Changes: the single function that builds `l<id>_<function>_<param>` and the `group_uniforms` token.
- Affects: exported shader text, the header round trip, the material sync in the preview, every golden-text assertion in the test suite, and every already-exported user shader.
- Ordering: locked in phase 2, before any manifest or recipe is written. Changing it after phase 7 invalidates every committed reference stack and screenshot.
- Migration/rollback: no migration path for shaders exported before a change. Treat the naming as frozen once phase 7 passes.

**Layer id allocation and `next_id` (`GSTStack`, decision 22)**
- Changes: shared monotonic counter that all references, uniform names, and undo records key off.
- Affects: slot references, coord-block warp references, uniform names, header JSON, undo/redo records.
- Ordering: phase 1. Every later phase assumes ids are stable and never reused.
- Migration/rollback: if id semantics change, every saved `.tres` stack and every exported header becomes unreadable. Version the header JSON in phase 6 so a future change is detectable.

**Header JSON schema (`gst_header.gd`, decision 8)**
- Changes: the on-the-wire format embedded in every exported `.gdshader`.
- Affects: reopen-from-header, the overwrite check, and any shader a user already shipped.
- Ordering: defined in phase 6, exercised in phase 7. Include a schema version field from the first write.
- Migration/rollback: reopen must reject an unknown schema version with a message rather than parsing it partially. Behavior for a missing header is B8.

**`EditorUndoRedoManager` integration (`gst_undo.gd`, decision 20)**
- Changes: routes structural edits through the editor's global undo history, shared with every other editor action.
- Affects: add, remove, reorder, slot change, output change. Slider edits come from the inspector and are not routed here.
- Ordering: phase 4. Any structural mutation added in phases 5-8 must go through `gst_undo.gd`, never mutate a `GSTStack` directly.
- Stack replacement (phase 6 review round 1): `New`, `Open`, and `Reopen Shader` are themselves undoable actions ("Replace stack") in the same history. Undo reinstalls the previous `GSTStack` instance and its `GSTUndo`, so every earlier action stays valid against the instance it was recorded on. Nothing clears the editor's global history, because non-scene resources share it with unrelated editor actions on 4.6.2 (verified in phase 6 smoke run 1).
- Migration/rollback: an unregistered mutation leaves the editor's undo history desynced from the stack. The phase 4 five-step undo check is the guard; re-run it after any later phase adds a structural edit.

**Global script class cache (`.godot/global_script_class_cache.cfg`)**
- Changes: build state, not source. Absent on a fresh clone because `.gitignore` excludes `.godot/`.
- Affects: every `-s` test run. Verified that `class_name` globals fail with `Parse error` when it is missing.
- Ordering: phase 1 documents `godot --headless --path . --import` as the prerequisite step in `tests/run_codegen_tests.gd`'s header comment. Phase 8 adds it to `README.md`.
- Migration/rollback: re-run the import command. No data loss.

**`.tres` manifests are load-only**
- Changes: a rule, enforced by review rather than by code.
- Affects: all files under `addons/goshade_turbo/library/`.
- Ordering: stated in phase 1, holds through phase 8.
- Migration/rollback: if a plugin path ever re-saves a manifest, the file churns whenever the engine version changes (observed for 4.7 bools in a sibling project). Revert the file and remove the write path.

**`project.godot` `config/features` churn**
- Changes: build state written by the editor, not by code.
- Affects: `project.godot` line `config/features`. Opening the project in the 4.6.2 editor rewrites it to `"4.6"`. Design decision 17 requires `"4.4"`.
- Ordering: every phase that opens the editor (spikes, phases 4-8 manual checks) must reset the line to `"4.4"` before commit. Verified by review round 4 of phase 1.
- Migration/rollback: one-line edit, no data loss.

**Manifest `code` contracts (B10)**
- Changes: three `code` shapes. A normal entry's `code` is one top-level shader function named `function`, emitted once at file scope by the include walk. A source entry (`source/texture`, `source/screen`) has `code` empty: codegen emits its read expression itself and never emits source `code` at file scope. A filter entry (`samples_source = true`) has `code` as an inline body template, never emitted at file scope, expanded per layer into a `{ }` block in `fragment()` with tokens `GST_SAMPLE(p)`, `GST_UV`, `GST_OUT`, `GST_PARAM(name)`.
- Affects: `gst_codegen.gd`, `gst_manifest_entry.gd` doc comments, every filter manifest, the compile-alone tests.
- Ordering: fixed in phase 3. Phase 8 filters follow the template shape.
- Migration/rollback: a filter written as a function fails compile with `Global non-constant variables are not supported` or `Unknown identifier: TEXTURE`; the compile-alone test catches it.
- Unwired filter rule (phase 3 review round 5): a `samples_source` slot cannot be cleared through `assign_slot`. When decision 22's delete reset would point a filter at a non-source layer, the slot is left empty and codegen returns an invocation-local error naming the filter layer; phase 4 shows that error in the panel and phase 5 keeps the last good material until it clears.

**Codegen error reporting**
- Changes: `GSTCodegen.generate_result` returns a `GSTCodegenResult` (`code`, `error`, `ok()`), invocation-local, never class-global mutable state. `GSTCodegen.generate` is the string convenience wrapper that returns `""` on error.
- Affects: every caller: tests in phases 2-3, material sync in phase 5, export in phase 6.
- Ordering: set in phase 3 review. Phases 5 and 6 read the error from the returned result and surface it in the UI.
- Migration/rollback: none.

**Editor smoke seams**
- Changes: public accessors on `GSTMainPanel` and `GSTPreview` that exist only so `tests/gst_editor_smoke.gd` can observe state carry the doc comment line `Wired-by: none (editor smoke seam)`. Any accessor without that line and without a live caller is dead code.
- Affects: phases 4-8 UI files.
- Ordering: from phase 5 on.
- Migration/rollback: delete the accessor and its smoke item together.

**Rendered checks require a GPU session**
- Changes: the verification environment, not the code.
- Affects: phases 7 and 8. `godot --headless` cannot read back viewport pixels (verified).
- Ordering: the split runner lands in phase 7.
- Migration/rollback: none. If the checks must run in CI later, the runner needs a container with a GPU and a display, or a software OpenGL implementation. Untested.

**`docs/` is tracked (B1 resolved)**
- Changes: repository tracking, not code.
- Affects: `docs/DESIGN.md`, `docs/PLAN.md`, `docs/SPIKE_NOTES.md`, and the committed screenshots the release checklist requires.
- Ordering: resolved before phase 1. `.godot/` stays ignored.
