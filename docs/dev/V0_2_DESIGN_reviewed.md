# GoShade Turbo v0.2: design

Status: draft
Intent: A shader creator builds the effects they reach for in a first session without hitting a wall v0.1 cannot get past, and still reads the stack top to bottom at a glance.
History: decision board drafted 2026-09-16 from the v0.1 gap audit, user approved every recommendation the same day. Not yet grilled through `/claudhd:design`. Decision 34 added 2026-09-21 (stack shape locked, VisualShader trial evidence). Decision 35 added 2026-09-22 (dependency marks in the stack list). Design review 2026-09-29: resolvable fixes applied, open items marked `[NEEDS USER DECISION]`. Extends `docs/dev/DESIGN.md`. Decision numbers continue from 22. Every v0.1 decision stays in force unless a decision below names it.

Roadmap item: `docs/dev/ROADMAP.md` Next, "GoShade Turbo v0.2". Done when the release checklist below is all ticked.

## What v0.2 adds

Four capabilities a shader creator hits in the first session on v0.1 and cannot work around, plus one read-only view:

- Layer ops: duplicate, rename, bypass.
- Texture param type plus a `source/image` entry.
- Any float or int param driven by a field layer.
- User recipes folder.
- Dependency marks in the stack list (decision 35). No schema change.

One schema change (decision 23) carries rename, bypass, texture params and param links. Duplicate, user recipes and dependency marks need no schema change.

## Locked decisions

23. Schema bump, once. `GSTLayer` gains `label`, `enabled`, `param_links`. `gst_header.gd` `SCHEMA_VERSION` goes 1 to 2. Reopen accepts schema 1 (every new field takes its default) and schema 2. v0.1 refuses schema 2 with its existing unknown-schema message. A stack `.tres` carries no schema field (`gst_stack.gd`). v0.1 loading a v0.2 `.tres` drops `label`, `enabled` and `param_links` without a message (Godot loader behavior for unknown script properties, unverified). v0.2 codegen of a schema 1 stack equals v0.1 codegen byte for byte, so `GSTOverwriteCheck` does not report an unedited v0.1 export as hand-edited. Beat: one bump per schema-touching feature, four migration paths (`label`, `enabled`, `param_links`, texture param values).

24. Duplicate. New id from `next_id`, same `entry`, `params`, `coord` (deep copy), `slots` (same source ids, all below the original so the no-forward-reference rule holds), `enabled`, `param_links` (same targets, all below the original). `label` is the original's label, or its function name when the label is empty, suffixed ` copy`. Texture params share the original's `Texture2D` resource. Inserted directly above the original. One undo record. Beat: paste from a clipboard, which needs cross-stack id remapping.

25. Rename. `label: String`, default empty. The stack list row shows `label` when set, followed by the function name. The function name stays visible in every row (`docs/dev/EDITOR_UI_DESIGN_reviewed.md` decision 15, `docs/dev/DESIGN.md` decision 19). `group_uniforms` uses `L<position>_<label or function>`, label sanitized to `[A-Za-z0-9_]`. A label that sanitizes to empty falls back to the function name. This amends the group name rule of decision 7. Uniform names stay id-based (decision 7). Beat: label in uniform names, which renames every uniform on every edit.

26. Bypass. `enabled: bool`, default true. A bypassed operator emits `l<id> = <first input of the same kind>`, converted via the decision 2 rules when no same-kind input exists. An unwired input passes its fallback constant (`GSTCodegen.FALLBACK_FIELD_CONSTANT` or `FALLBACK_COLOR_CONSTANT`). A bypassed filter emits its source sampled unchanged at the filter's `GST_UV` mapping: `UV`, `SCREEN_UV`, or `coord<src>` for a `source/image` source (decision 28). Generators, sources and every layer with no inputs refuse bypass with the reason beside the toggle. Layers with no inputs include the operators `color/fill` and `generative/clock`. The stack list row of a bypassed layer carries the suffix `  bypassed`, so the stack reads correctly without selecting the layer (owner rule, `.claude/CLAUDE.md`). Uniforms of a bypassed layer are still emitted so the exported inspector does not change shape. Beat: emit the kind's zero for generators; a black layer mid-stack reads as a bug, not a bypass.
[NEEDS USER DECISION: decisions 24, 25 and 26 name no control for duplicate, rename or bypass, so phase planning cannot place them. Options: items in the selected layer's Layer menu (`%LayerMenu`, where Preview this layer lives); buttons on the stack list row; controls in the Layer settings header. Recommendation: Layer menu items for all three, bypass as a checkable item, because `docs/dev/EDITOR_UI_DESIGN_reviewed.md` decision 14 already puts per-layer secondary actions there.]

27. Texture param type. Manifest `params` accept `type: texture`. Export: `uniform sampler2D l<id>_<function>_<param> : source_color, filter_linear, repeat_enable;`. No `hint_range`. Inspector: the native `Texture2D` property editor through the existing `EditorInspector.instantiate_property_editor` path. `GSTLayer._get_property_list` exposes the param as `TYPE_OBJECT` with `PROPERTY_HINT_RESOURCE_TYPE` `Texture2D`; `GSTLayer._property_type_for` currently falls back to `TYPE_FLOAT` for unknown types. A standalone `EditorPropertyResource` accepting load, drag-drop and clear outside an `EditorInspector` is unverified on `4.4`; build step 3 verifies it first. Preview: `set_shader_parameter` with the `Texture2D`. Stack `.tres` stores the resource as an `ExtResource`. Header json stores the resource path string. A missing file on reopen, from the header or from the `.tres`, leaves the uniform unset and reports the path in the document's message label; the stack still opens. `GSTStackIO.load` behavior on a missing `ExtResource` is unverified. Randomize (decision 16) skips `texture` params; `GSTRandomize._random_value` currently returns a float for unknown types. Beat: embedding image bytes in the header, which makes every exported shader file carry its images.
[NEEDS USER DECISION: the native `Texture2D` editor offers built-in textures (`NoiseTexture2D`, `GradientTexture2D`, `ViewportTexture`) that have no file path. The header json then stores an empty path and the texture is lost on reopen from an export; the `.tres` stores it as a `SubResource`. Options: refuse a texture without a `resource_path` on assign, with the reason beside the control; allow it in the `.tres` and report the unexportable texture at export; serialize the built-in resource into the header. Recommendation: refuse on assign, because a noise or gradient texture duplicates a generator layer and reintroduces the nested resources decision 34 cites against VisualShader.]
[NEEDS USER DECISION: an unset texture uniform (missing file on reopen, or an exported shader before the user assigns the texture on the `ShaderMaterial`) renders whatever the engine binds for an unset `sampler2D` with no `hint_default_*` hint (value unverified). Options: add `hint_default_transparent`, so an unset `source/image` layer is invisible; add `hint_default_white` or `hint_default_black`; leave the engine default. Recommendation: `hint_default_transparent`, because a missing image then shows nothing instead of a solid fill.]

28. `source/image`. New entry, kind `color`, `coord: true`, one texture param `image`. `GSTCodegen._layer_body_lines` routes it to `_source_body_lines` ahead of the `coord != null` generator branch, because `GSTManifestEntry.is_source()` is true for every `source/` id and a source entry's code is never emitted at file scope. `_source_body_lines` emits the coord block lines (transform, scroll, warp) then `vec4 l<id> = texture(l<id>_<function>_image, coord<id>);`, the uniform named per decision 7. Scale, offset, rotation, scroll and warp apply through the coord block. It joins `texture` and `screen` as an allowed filter input (decision 21): a filter on `source/image` maps `GST_SAMPLE` to `l<src>_<function>_image` and `GST_UV` to `coord<src>`, so it samples at `coord<src> + offset`. One source predicate covering `source/texture`, `source/screen` and `source/image` replaces the hardcoded two-id checks in `GSTStackOps._is_source_layer`, `GSTStackOps.validate_slot_assignment`, `GSTCodegen._filter_body_lines` and the two `source_only` filters in `gst_main_panel.gd` `_choice_rows`. Beat: texture params on operators only, which gives masks but no transformable second image.

29. Param links, base plus amount. `param_links: Dictionary`, param name to `{target: layer_id, amount: float}`. A linkable param is `type: float` or `type: int`; `color`, `vec3` and `texture` do not link in v0.2. Linkable params include filter params (`GST_PARAM`). The target must be below the layer; a `color` target converts via `luma` (decision 2). The slider stays live as the base value. `amount` is -1..1, default 1.0. Codegen replaces the uniform with `clamp(<base> + (l<target> - 0.5) * <amount> * (<max> - <min>), <min>, <max>)`, wrapped in `int(round(...))` for int params; `<base>` is the param's literal value from `params`, so amount 0 is identical to unlinked and linking never jumps. Every literal in the expression is emitted as a float (`_glsl_float`), since the Godot shading language rejects mixed `int` and `float` operands (unverified in-repo). The target is per pixel, so a noise target varies the param across the surface and a `generative/clock` target animates it around the base. A target outside `0..1` (for example `sdf/circle`, negative inside) moves the result past the range and `clamp` saturates it; a `fieldops/remap` layer below the linker rescales it.
[NEEDS USER DECISION: the draft drops the param's uniform while linked and bakes base and amount as literals ("same rule as scroll and `TIME`"). The scroll rule emits its uniform whenever scroll is in use, so the analogy does not hold. Consequences: the exported inspector loses the param while linked, which contradicts decision 26's reason for keeping bypassed uniforms; every base or amount drag step changes the shader text, and `GSTMaterialSync.sync` recompiles the shader on every step. Options: keep literals; keep the param uniform with its `hint_range` as `<base>` and emit `amount` as a second uniform, so the exported inspector keeps its shape and drags write uniforms. Recommendation: keep the uniform and add an amount uniform, because it preserves live tuning in the exported material and matches decision 26.]
Deleting the target clears the link (decision 22 reporting). Reordering the target above the linker is refused with the reason. Beats: `mix(min, max, field)`, which discards the slider and needs a remap layer for any modulation smaller than the full range; raw field value into the param, same remap cost. Amended 2026-09-20 from the mix form.

30. Link UI. A link button beside every linkable slider in the inspector column opens the shared picker in a new mode listing field and color layers below the current layer, no library entries. A linked row keeps the slider (the base value) and adds a second line under it: the target's label and function name, an amount slider -1..1, an unlink button. The amount slider is a native `EditorProperty` from `EditorInspector.instantiate_property_editor`, so decision 20 gesture undo covers it (`docs/dev/SHADER_TABS_reviewed.md` decision 7). Unlink removes the second line; the base slider is unchanged. Beats: replacing the slider with the target name, which loses the base value; a separate "modulation" section, which splits one param across two places. Amended 2026-09-20 with decision 29.

31. `custom` layer. Moved to its own design round, 2026-09-29 (owner decision). The target user in `docs/dev/DESIGN.md` has no shader knowledge; a GLSL code box serves a different user, and its only support was the v0.1 deferral in `DESIGN.md` decision 9. Two required mechanisms are unverified: reading Godot shader compile errors in the addon, and `sampler2D` function arguments. The draft text stays in `docs/dev/V0_2_DESIGN.md` as input to that round.

32. Save as library entry. Moved out with decision 31, 2026-09-29.

33. User recipes. Project setting `goshade_turbo/recipes_dir`, default `res://goshade_recipes/`. The Recipes picker (`gst_main_panel.gd` `_choice_rows`, purpose `recipe`) and the start-screen recipe grid list the bundled recipes (`RECIPES_DIR`, `res://addons/goshade_turbo/recipes`) first, then the user folder as a second category. A recipe row carries its full path, because `_on_picker_choice` currently loads `RECIPES_DIR/<name>.tres` and a user recipe can share a bundled recipe's name. A missing user folder lists no user recipes. "Save as Recipe" in the File menu writes the active stack there by name, creates the folder when missing, asks before overwriting an existing file of that name (same rule as the export overwrite check, decision 9), and opens nothing. Randomize (decision 16) treats user recipes the same as bundled ones. Beat: editing the addon folder, lost on addon update.

34. Stack shape, locked. The stack stays a linear, typed, downward-referencing list of whole-function layers. No free-form wiring, no forward references, no inline expression node, no canvas. Every v0.2 feature is checked against this: param links (29) reference one lower layer per param. Evidence, 2026-09-21: first-time VisualShader trial by the project owner in this repo (`visualtest1.tres`, deleted). Scrolling noise with pulsing alpha took 6 nodes plus 3 nested resources (`Texture2D` node > `NoiseTexture2D` > `FastNoiseLite`) and still rendered the missing-texture magenta checker, did not scroll (`VectorOp b` unwired) and would blink (`sin(TIME)` unremapped into alpha); a correct version is 10 nodes. The goshade equivalent is `generative/noise` with scroll speed plus `fieldops/remap` on `generative/clock` into output alpha, two layers, zero resources. Owner verdict after 15 minutes: lost at the resource nesting, not a fan. What the stack buys that the graph cannot: canonical reading order, one-line json header that diffs and pastes, no invalid wiring by construction, randomize that always compiles, per-layer license and tests, single-pass codegen with no cycle check. What it gives up: fan-in beyond a layer's declared inputs, shader types other than `canvas_item`, arbitrary topology. Beat: evolving toward a graph, which converges on VisualShader with a worse skin and none of the above. Recorded in `docs/dev/ROADMAP.md` Non-goals. General test for every feature, owner rule 2026-09-24: "Does this make the stack more expressive without making the stack harder to understand?"

35. Dependency marks in the stack list. Selecting a layer marks, in the stack list, every layer it reads and every layer that reads it. Direct edges only. Edges are slots, coord `warp_x` and `warp_y`, and `param_links` targets (decision 29). A row the selected layer reads gets the suffix `  feeds: <names>`, the selected layer's slot, warp or param names that read it. A row that reads the selected layer gets `  reads: <names>`, that row's own slot, warp or param names. Both row types also take a background tint from the editor accent color; the suffix carries the information without color. The marks are derived in `GSTStackList.refresh()` from a named-edge form of `GSTStackOps._references_of` (edge list of `{target, name}`), which decision 29 extends with link targets for the reorder refusal anyway. Read only: no model field, no schema change, no undo record. Bypassed layers keep their marks, since the edge is still in the data. Recomputed on selection change and on every stack edit. Beats: transitive closure, which on a long stack marks most rows and shows nothing; a separate graph or dependency panel, which is a canvas under another name (decision 34) and splits one layer's wiring across two places; marks only on hover, which leaves nothing visible while editing the inspector. Evidence: the slot dropdowns show a layer's inputs only while that layer is selected, and no view shows its consumers; param links (decision 29) add edges that the linked layer's row does not show. Added 2026-09-22.

## Data model delta

```
Layer (Resource)
  label: String = ""                      # decision 25
  enabled: bool = true                    # decision 26
  param_links: Dictionary = {}            # param name -> {target: layer id, amount: float}, decision 29
```

`params` may hold a `Texture2D` resource for `type: texture` (decision 27). Everything else unchanged.

## Manifest delta

- `params[].type` accepts `texture` (decision 27).
- `source/image` is a manifest file like any other; `samples_source` stays false on it. Filters recognise it by entry id (decision 28).

## Codegen delta

- Bypass: `_layer_body_lines` branches on `enabled` before kind dispatch (decision 26).
- Texture uniform line: `_param_uniform_line` handles `texture` with no default and no range. `GSTHeader._param_value_to_json` and `GSTMaterialSync._write_param_uniform` gain a `texture` branch; both currently fall back to `float(value)`.
- `source/image`: `_layer_body_lines` routes it to `_source_body_lines` before the generator branch (decision 28).
- Param link: `_operator_body_lines`, `_generator_body_lines`, and the `GST_PARAM` mapper in `_expand_filter_template` substitute the base-plus-amount expression for the uniform name, with base, amount, min and max as literals (pending the decision 29 marker); `_layer_uniform_lines` skips linked params. `_stack_needs_luma` counts `color` link targets.
- Header: schema 2, new fields serialized only when non-default, so a stack that uses no v0.2 field differs from its v0.1 header only in `schema`.

## Build order (architectural risks first)

1. Schema bump, `GSTLayer` fields, header schema 2 read and write, schema 1 reopen test, stack io roundtrip.
2. Bypass and param links in codegen, headless tests for every emit path, combination test: every field under every linkable param compiles.
3. Standalone `EditorPropertyResource` verification on `4.4` (decision 27), then texture param type, `source/image`, filter on image, render checks with a bundled second image.
4. Layer ops UI: duplicate, rename, bypass toggle, link button, picker layer mode. Undo coverage for each. Dependency marks (decision 35).
5. User recipes folder, project setting, File menu entries.
6. Reference stacks and screenshots for `source/image` and one linked param. Release checklist.

## Release checklist (v0.2)

- [ ] Schema 1 headers and `.tres` files from v0.1 reopen with every new field at its default.
- [ ] Unedited v0.1 exports reopen in v0.2 without the hand-edit warning; a schema 1 stack regenerates a byte-identical body.
- [ ] Headless codegen tests: bypass per kind, bypass refused on every layer with no inputs, linked float and int, amount 0 renders the same pixels as unlinked, texture uniform, `source/image` under every filter.
- [ ] Combination test: every field entry linked into every linkable param of every entry compiles.
- [ ] Headless tests: link target delete clears the link and reports it; reorder of a link target above its linker is refused; a `color` link target emits `luma`.
- [ ] Headless tests: duplicate copies every field listed in decision 24; `group_uniforms` uses the sanitized label, and the function name when the label sanitizes to empty.
- [ ] A missing texture file on header reopen and on `.tres` reopen opens the stack and reports the path.
- [ ] User recipes list after bundled recipes; Save as Recipe writes the file, asks before overwriting, opens nothing; a user recipe named like a bundled recipe opens the user file.
- [ ] Rendered checks on the new reference stacks pass the existing `GSTRenderAssert`.
- [ ] Headless test: dependency marks for slot, warp and param link edges in both directions, suffix names, direct edges only.
- [ ] Undo covers duplicate, rename, bypass, link, amount change, unlink.
- [ ] Every v0.1 recipe still passes the rendered and motion checks.
- [ ] Runs on 4.4, 4.6, 4.7.

## Out of v0.2 (named so they are not relitigated here)

Each is its own design round: `custom` layer type and save as library entry (decisions 31, 32, moved out 2026-09-29), `vec2` kind, filters on any layer, `render_mode`, `light()`, vertex effects, instance uniforms, bake to constant, other shader types, structural randomize, picker thumbnails, mouse-driven coords (needs a runtime script). Preview pause and per-layer thumbnails are quick fixes, not v0.2 items.

## Open

- Grill pass through `/claudhd:design` after the comment cleanup lands, then `/claudhd:plan`.
- Bundled second image for the `source/image` reference stack: reuse `preview_default.png` or add one asset. Decide at planning.
