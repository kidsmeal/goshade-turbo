# v0.2 stack features

Source: `docs/dev/V0_2_DESIGN_reviewed.md`. Extends `docs/dev/DESIGN.md`; every v0.1 decision stays in force unless a decision below names it.

## Goal

- A shader creator builds the effects they reach for in a first session without hitting a v0.1 wall.
- The stack still reads top to bottom at a glance.
- Adds: layer ops (duplicate, rename, bypass), texture param type plus entry source/image, param links, user recipes folder, dependency marks in the stack list.
- One schema change carries rename, bypass, texture params and param links. Duplicate, user recipes and dependency marks change no schema.

## Decisions

Locked decisions, numbered as in `docs/dev/V0_2_DESIGN_reviewed.md`.

- 23 Schema bump, once: `GSTLayer` gains `label`, `enabled`, `param_links`; `SCHEMA_VERSION` in `addons/goshade_turbo/io/gst_header.gd` increments by one.
- 23 Reopen accepts the current and the new schema value; the current value opens with every new field at its default. v0.1 refuses the new value with its existing unknown-schema message.
- 23 v0.2 codegen of a schema 1 stack equals v0.1 codegen byte for byte, so `GSTOverwriteCheck` does not flag an unedited v0.1 export.
- 23 A stack resource file carries no schema field (`addons/goshade_turbo/model/gst_stack.gd`). v0.1 dropping unknown properties on load: unverified.
- 24 Duplicate: new id from `next_id`; deep copy of `entry`, `params`, `coord`, `slots`, `enabled`, `param_links`; inserted directly above the original; one undo record.
- 24 Duplicate label: original label, or its function name when empty, suffixed ` copy`. Texture params share the original `Texture2D`.
- 25 Rename: `label: String`, default empty. Row shows label then function name; function name stays visible in every row.
- 25 `group_uniforms` name is `L<position>_<label or function>`, label sanitized to `[A-Za-z0-9_]`, function name when the label sanitizes to empty. Amends decision 7's group name rule.
- 25 Uniform names stay id-based (decision 7).
- 26 Bypass: `enabled: bool`, default true.
- 26 A bypassed operator emits `l<id> = <first input of the same kind>`, converted via decision 2 when no same-kind input exists; an unwired input passes `GSTCodegen.FALLBACK_FIELD_CONSTANT` or `GSTCodegen.FALLBACK_COLOR_CONSTANT`.
- 26 A bypassed filter emits its source sampled unchanged at the filter's `GST_UV` mapping: `UV`, `SCREEN_UV`, or `coord<src>` for a source/image source (decision 28).
- 26 Generators, sources and every layer with no inputs refuse bypass, reason shown beside the toggle. Includes operators color/fill and generative/clock.
- 26 A bypassed row carries the suffix `  bypassed`. Uniforms of a bypassed layer are still emitted.
- 27 Manifest `params` accept `type: texture`; export line `uniform sampler2D l<id>_<function>_<param> : source_color, filter_linear, repeat_enable;`, no `hint_range`.
- 27 Inspector uses the native `Texture2D` editor via `EditorInspector.instantiate_property_editor`; `GSTLayer._get_property_list` exposes it as `TYPE_OBJECT` with `PROPERTY_HINT_RESOURCE_TYPE` `Texture2D`.
- 27 Preview sets the `Texture2D` with `set_shader_parameter`. The stack resource file stores an `ExtResource`; header json stores the resource path string.
- 27 A missing texture file on reopen (header or stack resource file) leaves the uniform unset, reports the path in the document message label, and still opens the stack. `GSTStackIO.load` on a missing `ExtResource`: unverified.
- 27 Randomize (decision 16) skips `texture` params.
- 28 Entry source/image: kind `color`, `coord: true`, one texture param `image`. (new)
- 28 `GSTCodegen._layer_body_lines` routes it to `_source_body_lines` before the generator branch; body is the coord block lines then `vec4 l<id> = texture(l<id>_<function>_image, coord<id>);`.
- 28 It is an allowed filter input (decision 21): `GST_SAMPLE` maps to `l<src>_<function>_image`, `GST_UV` maps to `coord<src>`.
- 28 A new shared source predicate covering source/texture, source/screen and source/image replaces the two-id checks in `GSTStackOps._is_source_layer`, `GSTStackOps.validate_slot_assignment`, `GSTCodegen._filter_body_lines` and `_choice_rows` in `addons/goshade_turbo/ui/gst_main_panel.gd`.
- 29 Param links: `param_links: Dictionary`, param name to `{target: layer_id, amount: float}`.
- 29 Linkable params: `type: float` and `type: int`, filter `GST_PARAM` params included. `color`, `vec3`, `texture` do not link.
- 29 Target must sit below the layer; a `color` target converts via `luma` (decision 2).
- 29 Slider stays live as the base. `amount` range `-1..1`, default `1.0`.
- 29 Expression: `clamp(<base> + (l<target> - 0.5) * <amount> * (<max> - <min>), <min>, <max>)`, wrapped in `int(round(...))` for int params; every literal emitted through `_glsl_float`.
- 29 Amount 0 equals unlinked; linking never jumps the value.
- 29 Deleting the target clears the link with decision 22 reporting. Reordering the target above the linker is refused with the reason.
- 30 Link UI: link button beside every linkable slider opens the shared picker in a layer mode listing field and color layers below the current layer, no library entries.
- 30 A linked row keeps the base slider and adds a second line: target label and function name, amount slider `-1..1` (native `EditorProperty`), unlink button.
- 30 Unlink removes the second line and leaves the base slider unchanged.
- 31, 32 `custom` layer and save as library entry: moved to their own design round 2026-09-29 (owner decision). Out of this spec.
- 33 Project setting `goshade_turbo/recipes_dir`, default `res://goshade_recipes/`. (new)
- 33 Recipes picker and start-screen grid list bundled recipes (`RECIPES_DIR`) first, then the user folder as a second category.
- 33 A recipe row carries its full path; a user recipe can share a bundled recipe name. A missing user folder lists no user recipes.
- 33 File menu "Save as Recipe" writes the active stack by name, creates the folder when missing, asks before overwriting (decision 9 rule), opens nothing.
- 33 Randomize treats user recipes the same as bundled ones.
- 34 Stack shape locked: linear, typed, downward-referencing list of whole-function layers; no free-form wiring, forward references, inline expression node or canvas. Recorded in `docs/dev/ROADMAP.md` Non-goals.
- 34 Every feature passes the owner rule in `.claude/CLAUDE.md`: more expressive without making the stack harder to understand.
- 35 Dependency marks: selecting a layer marks every layer it reads and every layer that reads it. Direct edges only.
- 35 Edges: slots, coord `warp_x` and `warp_y`, `param_links` targets.
- 35 A row the selected layer reads gets `  feeds: <names>`; a row that reads the selected layer gets `  reads: <names>`. Both rows get an editor accent tint.
- 35 Marks derive in `GSTStackList.refresh()` from a named-edge form of `GSTStackOps._references_of`. No model field, schema change or undo record.
- 35 Bypassed layers keep their marks. Recomputed on selection change and every stack edit.

Open, owner decision (`[NEEDS USER DECISION]` markers in the source doc, not locked):

- Control placement for duplicate, rename, bypass. Recommendation: items in `%LayerMenu`, bypass as a checkable item, per `docs/dev/EDITOR_UI_DESIGN_reviewed.md` decision 14.
- Built-in textures without a `resource_path`. Recommendation: refuse on assign with the reason beside the control.
- Unset `sampler2D` hint. Recommendation: `hint_default_transparent`.
- Linked param emit form. Recommendation: keep the param uniform as the base and add an amount uniform, matching decision 26's reason for keeping uniforms.
  - `_layer_uniform_lines` skips linked params only if the literal form is chosen.

## Behavior

- Schema 1 headers and stack resource files open with `label` empty, `enabled` true, `param_links` empty.
- Header serializes new fields only when non-default; a stack using no v0.2 field differs from its v0.1 header only in `schema`.
- `_layer_body_lines` branches on `enabled` before kind dispatch.
- `_param_uniform_line` emits the texture line with no default and no range.
- `GSTHeader._param_value_to_json` and `GSTMaterialSync._write_param_uniform` handle `texture`; both fall back to `float(value)` today.
- `GSTLayer._property_type_for` and `GSTRandomize._random_value` handle `texture`; both fall back to float today.
- `_operator_body_lines`, `_generator_body_lines` and the `GST_PARAM` mapper in `_expand_filter_template` substitute the link expression for the param uniform.
- `_stack_needs_luma` counts `color` link targets.
- A noise link target varies the param per pixel; a generative/clock target animates it around the base.
- A target outside `0..1` saturates through `clamp`; a fieldops/remap layer below the linker rescales it.
- Dependency marks show without color through the suffix text.

## Acceptance

- Schema 1 headers and stack resource files from v0.1 reopen with every new field at its default.
- Unedited v0.1 exports reopen without the hand-edit warning; a schema 1 stack regenerates a byte-identical body.
- Headless codegen tests: bypass per kind, bypass refused on every layer with no inputs, linked float and int, amount 0 renders the same pixels as unlinked, texture uniform, source/image under every filter.
- Combination test: every field entry linked into every linkable param of every entry compiles.
- Headless tests: deleting a link target clears the link and reports it; reordering a link target above its linker is refused; a `color` target emits `luma`.
- Headless tests: duplicate copies every decision 24 field; `group_uniforms` uses the sanitized label, and the function name when the label sanitizes to empty.
- A missing texture file on header reopen and on stack resource file reopen opens the stack and reports the path.
- User recipes list after bundled ones; Save as Recipe writes the file, asks before overwriting, opens nothing; a user recipe named like a bundled one opens the user file.
- Standalone `EditorPropertyResource` load, drag-drop and clear outside an `EditorInspector` verified on Godot `4.4` before texture param work.
- Rendered checks on the new reference stacks pass `tests/gst_render_assert.gd`.
- Headless test: dependency marks for slot, warp and param link edges in both directions, suffix names, direct edges only.
- Undo covers duplicate, rename, bypass, link, amount change, unlink.
- Every v0.1 recipe passes `tests/run_render_checks.gd` and `tests/run_recipe_motion_checks.gd`.
- Runs on Godot `4.4`, `4.6`, `4.7`.

## Files

- `addons/goshade_turbo/model/gst_layer.gd`
- `addons/goshade_turbo/model/gst_stack_ops.gd`
- `addons/goshade_turbo/model/gst_manifest_entry.gd`
- `addons/goshade_turbo/io/gst_header.gd`
- `addons/goshade_turbo/io/gst_stack_io.gd`
- `addons/goshade_turbo/io/gst_overwrite_check.gd`
- `addons/goshade_turbo/codegen/gst_codegen.gd`
- `addons/goshade_turbo/codegen/gst_uniform_names.gd` (`group_uniforms` name rule, decision 25)
- `addons/goshade_turbo/ui/gst_main_panel.gd`
- `addons/goshade_turbo/ui/gst_main_panel.tscn`
- `addons/goshade_turbo/ui/gst_stack_list.gd`
- `addons/goshade_turbo/ui/gst_inspector_column.gd`
- `addons/goshade_turbo/ui/gst_picker.gd`
- `addons/goshade_turbo/ui/gst_undo.gd`
- `addons/goshade_turbo/ui/gst_material_sync.gd`
- `addons/goshade_turbo/ui/gst_randomize.gd`
- `addons/goshade_turbo/plugin.gd`
- `addons/goshade_turbo/library/source/image.tres` (new)
- `addons/goshade_turbo/assets/preview_default.png` (second image candidate for the source/image reference stack; reuse or add one asset, decided at planning)
- `sandbox/stacks/ref_source_image.tres` (new)
- `sandbox/stacks/ref_param_link.tres` (new)
- `tests/test_header_roundtrip.gd`
- `tests/test_stack_io.gd`
- `tests/test_stack_ops.gd`
- `tests/test_combinations.gd`
- `tests/test_uniform_names.gd`
- `tests/test_randomize_range.gd`
- `tests/test_material_sync.gd`
- `tests/test_overwrite_check.gd`
- `tests/run_codegen_tests.gd`
- `tests/run_render_checks.gd`

## Changes
