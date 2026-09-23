# GoShade Turbo v0.2: design

Status: decision board drafted 2026-09-16 from the v0.1 gap audit, user approved every recommendation the same day. Not yet grilled through `/claudhd:design`; not yet reviewed. Decision 34 added 2026-09-21 (stack shape locked, VisualShader trial evidence). Decision 35 added 2026-09-22 (dependency marks in the stack list). Extends `docs/DESIGN.md`. Decision numbers continue from 22. Every v0.1 decision stays in force unless a decision below names it.

Roadmap item: `ROADMAP.md` Next, "GoShade Turbo v0.2". Done when the release checklist below is all ticked.

## What v0.2 adds

Five capabilities a shader creator hits in the first session on v0.1 and cannot work around, plus one read-only view:

- Layer ops: duplicate, rename, bypass.
- Texture param type plus a `source/image` entry.
- Any float or int param driven by a field layer.
- `custom` layer type, with save-as-library-entry.
- User recipes folder.
- Dependency marks in the stack list (decision 35). No schema change.

One schema change carries the five capabilities.

## Locked decisions

23. Schema bump, once. `GSTLayer` gains `label`, `enabled`, `param_links`, `custom_code`, `custom_kinds`, `custom_params`. `gst_header.gd` `SCHEMA_VERSION` goes 1 to 2. Reopen accepts schema 1 (every new field takes its default) and schema 2. v0.1 refuses schema 2 with its existing unknown-schema message. Beat: one bump per feature, four migration paths.

24. Duplicate. New id from `next_id`, same `entry`, `params`, `coord` (deep copy), `slots` (same source ids, all below the original so the no-forward-reference rule holds), `label` suffixed ` copy`. Inserted directly above the original. One undo record. Beat: paste from a clipboard, which needs cross-stack id remapping.

25. Rename. `label: String`, default empty. Stack list shows `label` when set, else the function name. `group_uniforms` uses `L<position>_<label or function>`, label sanitized to `[A-Za-z0-9_]`. Uniform names stay id-based (decision 7). Beat: label in uniform names, which renames every uniform on every edit.

26. Bypass. `enabled: bool`, default true. A bypassed operator emits `l<id> = <first input of the same kind>`, converted via the decision 2 rules when no same-kind input exists. A bypassed filter emits its source sampled at `UV` (or `SCREEN_UV`) unchanged. Generators, sources and `custom` layers with no inputs refuse bypass with the reason beside the toggle. Uniforms of a bypassed layer are still emitted so the exported inspector does not change shape. Beat: emit the kind's zero for generators; a black layer mid-stack reads as a bug, not a bypass.

27. Texture param type. Manifest `params` accept `type: texture`. Export: `uniform sampler2D l<id>_<function>_<param> : source_color, filter_linear, repeat_enable;`. No `hint_range`. Inspector: the native `Texture2D` property editor through the existing `EditorInspector.instantiate_property_editor` path. Preview: `set_shader_parameter` with the `Texture2D`. Stack `.tres` stores the resource as an `ExtResource`. Header json stores the resource path string; a missing file on reopen leaves the uniform unset and reports the path in the document's message label, the stack still opens. Beat: embedding image bytes in the header, which makes every exported shader file carry its images.

28. `source/image`. New entry, kind `color`, `coord: true`, one texture param `image`. Body samples `texture(l<id>_image, coord<id>)`. Scale, offset, rotation, scroll and warp apply through the coord block. It joins `texture` and `screen` as an allowed filter input (decision 21): a filter on `source/image` samples `l<id>_image` at `coord<id> + offset`. `_is_source_layer` gains the entry. Beat: texture params on operators only, which gives masks but no transformable second image.

29. Param links, base plus amount. `param_links: Dictionary`, param name to `{target: layer_id, amount: float}`. A linkable param is `type: float` or `type: int`; `color`, `vec3` and `texture` do not link in v0.2. The target must be below the layer; a `color` target converts via `luma` (decision 2). The slider stays live as the base value. `amount` is -1..1, default 1.0. Codegen replaces the uniform with `clamp(<base> + (l<target> - 0.5) * <amount> * (<max> - <min>), <min>, <max>)`, wrapped in `int(round(...))` for int params; `<base>` is the param's literal value from `params`, so amount 0 is identical to unlinked and linking never jumps. The target is per pixel, so a noise target varies the param across the surface and a `generative/clock` target animates it around the base. The uniform is not emitted while linked, same rule as scroll and `TIME`. Deleting the target clears the link (decision 22 reporting). Reordering the target above the linker is refused with the reason. Beats: `mix(min, max, field)`, which discards the slider and needs a remap layer for any modulation smaller than the full range; raw field value into the param, same remap cost. Amended 2026-09-20 from the mix form.

30. Link UI. A link button beside every linkable slider in the inspector column opens the shared picker in a new mode listing field and color layers below the current layer, no library entries. A linked row keeps the slider (the base value) and adds a second line under it: the target's label or function name, an amount slider -1..1, an unlink button. Unlink removes the second line; the base slider is unchanged. Beats: replacing the slider with the target name, which loses the base value; a separate "modulation" section, which splits one param across two places. Amended 2026-09-20 with decision 29.

31. `custom` layer. Entry id `custom`, not a manifest file. `custom_code: String` is a function body; codegen wraps it as `<kind> custom_l<id>(<inputs>, <params>) { <body> }` and emits the call like any operator. `custom_kinds: Dictionary` holds `kind_out` and `inputs` (name plus kind, up to 3). `custom_params: Array[Dictionary]` uses the manifest param schema (`name`, `type`, `min`, `max`, `default`), types `float`, `int`, `color`, `vec3`, `texture`. The inspector shows a code box, a kind dropdown, an inputs editor, a params editor. Compile errors surface through the existing codegen error label above the preview. Header json carries the whole block, so export and reopen need no library. A custom layer has no coord block in v0.2; use a generator input for coords. Beat: forcing every custom function through the library folder before it can be used.

32. Save as library entry. A button on a `custom` layer writes `addons/goshade_turbo/library/custom/<function>.tres` with `source_math = "own construction"` and empty license fields, then swaps the layer's `entry` to the new id and clears the custom fields. Refused when `function` collides with an existing roster function (codegen requires uniqueness). Undo covers the swap; the file stays. Beat: writing to the user recipes folder, which the library scan does not read.

33. User recipes. Project setting `goshade_turbo/recipes_dir`, default `res://goshade_recipes/`. The Recipes menu lists the addon folder, then a separator, then the user folder. "Save as Recipe" in the File menu writes the active stack there by name and opens nothing. Randomize (decision 16) treats user recipes the same as bundled ones. Beat: editing the addon folder, lost on addon update.

34. Stack shape, locked. The stack stays a linear, typed, downward-referencing list of whole-function layers. No free-form wiring, no forward references, no inline expression node, no canvas. Every v0.2 feature is checked against this: param links (29) reference one lower layer per param; `custom` (31) is a typed function with a declared signature and enters the library (32), never an inline glsl box on a wire. Evidence, 2026-09-21: first-time VisualShader trial by the project owner in this repo (`visualtest1.tres`, deleted). Scrolling noise with pulsing alpha took 6 nodes plus 3 nested resources (`Texture2D` node > `NoiseTexture2D` > `FastNoiseLite`) and still rendered the missing-texture magenta checker, did not scroll (`VectorOp b` unwired) and would blink (`sin(TIME)` unremapped into alpha); a correct version is 10 nodes. The goshade equivalent is `generative/noise` with scroll speed plus `fieldops/remap` on `generative/clock` into output alpha, two layers, zero resources. Owner verdict after 15 minutes: lost at the resource nesting, not a fan. What the stack buys that the graph cannot: canonical reading order, one-line json header that diffs and pastes, no invalid wiring by construction, randomize that always compiles, per-layer license and tests, single-pass codegen with no cycle check. What it gives up: fan-in beyond a layer's declared inputs, shader types other than `canvas_item`, arbitrary topology. Beat: evolving toward a graph, which converges on VisualShader with a worse skin and none of the above. Recorded in `ROADMAP.md` Non-goals.

35. Dependency marks in the stack list. Selecting a layer marks, in the stack list, every layer it reads and every layer that reads it. Direct edges only. Edges are slots, coord `warp_x` and `warp_y`, and `param_links` targets (decision 29). A row the selected layer reads gets the suffix `  feeds: <names>`, the selected layer's slot, warp or param names that read it. A row that reads the selected layer gets `  reads: <names>`, that row's own slot, warp or param names. Both row types also take a background tint from the editor accent color; the suffix carries the information without color. The marks are derived in `GSTStackList.refresh()` from a named-edge form of `GSTStackOps._references_of` (edge list of `{target, name}`), which decision 29 extends with link targets for the reorder refusal anyway. Read only: no model field, no schema change, no undo record. Bypassed layers keep their marks, since the edge is still in the data. Recomputed on selection change and on every stack edit. Beats: transitive closure, which on a long stack marks most rows and shows nothing; a separate graph or dependency panel, which is a canvas under another name (decision 34) and splits one layer's wiring across two places; marks only on hover, which leaves nothing visible while editing the inspector. Evidence: the slot dropdowns show a layer's inputs only while that layer is selected, and no view shows its consumers; param links (decision 29) add edges that the linked layer's row does not show. Added 2026-09-22.

## Data model delta

```
Layer (Resource)
  label: String = ""                      # decision 25
  enabled: bool = true                    # decision 26
  param_links: Dictionary = {}            # param name -> {target: layer id, amount: float}, decision 29
  custom_code: String = ""                # decision 31, entry == "custom" only
  custom_kinds: Dictionary = {}           # {kind_out, inputs: [{name, kind}]}
  custom_params: Array[Dictionary] = []   # manifest param schema
```

`params` may hold a `Texture2D` resource for `type: texture` (decision 27). Everything else unchanged.

## Manifest delta

- `params[].type` accepts `texture` (decision 27).
- `source/image` is a manifest file like any other; `samples_source` stays false on it. Filters recognise it by entry id (decision 28).
- The `custom` entry id is reserved and never a file.

## Codegen delta

- Bypass: `_layer_body_lines` branches on `enabled` before kind dispatch (decision 26).
- Texture uniform line: `_param_uniform_line` handles `texture` with no default and no range.
- Param link: `_operator_body_lines` and `_generator_body_lines` substitute the base-plus-amount expression for the uniform name, with base, amount, min and max as literals; `_layer_uniform_lines` skips linked params.
- Custom: `_include_order` appends one synthetic entry per custom layer after the library walk; function name `custom_l<id>` cannot collide with roster functions.
- Header: schema 2, new fields serialized only when non-default so schema 1 readers of exported bodies still see familiar json.

## Build order (architectural risks first)

1. Schema bump, `GSTLayer` fields, header schema 2 read and write, schema 1 reopen test, stack io roundtrip.
2. Bypass and param links in codegen, headless tests for every emit path, combination test: every field under every linkable param compiles.
3. Texture param type, `source/image`, filter on image, render checks with a bundled second image.
4. Layer ops UI: duplicate, rename, bypass toggle, link button, picker layer mode. Undo coverage for each. Dependency marks (decision 35).
5. `custom` layer: model, codegen, inspector editors, error surfacing, save as library entry.
6. User recipes folder, project setting, File menu entries.
7. Reference stacks and screenshots for `source/image`, one custom layer, one linked param. Release checklist.

## Release checklist (v0.2)

- [ ] Schema 1 headers and `.tres` files from v0.1 reopen with every new field at its default.
- [ ] Headless codegen tests: bypass per kind, linked float and int, amount 0 emits the same body as unlinked, texture uniform, `source/image` under every filter, custom layer with 0 to 3 inputs, custom function name uniqueness.
- [ ] Combination test: every field entry linked into every linkable param of every entry compiles.
- [ ] Rendered checks on the new reference stacks pass the existing `GSTRenderAssert`.
- [ ] Headless test: dependency marks for slot, warp and param link edges in both directions, suffix names, direct edges only.
- [ ] Undo covers duplicate, rename, bypass, link, unlink, custom edit, save as library entry.
- [ ] Every v0.1 recipe still passes the rendered and motion checks.
- [ ] Runs on 4.4, 4.6, 4.7.

## Out of v0.2 (named so they are not relitigated here)

Each is its own design round: `vec2` kind, filters on any layer, `render_mode`, `light()`, vertex effects, instance uniforms, bake to constant, other shader types, structural randomize, picker thumbnails, mouse-driven coords (needs a runtime script). Preview pause and per-layer thumbnails are quick fixes, not v0.2 items.

## Open

- Grill pass through `/claudhd:design` after the comment cleanup lands, then `/claudhd:plan`.
- Bundled second image for the `source/image` reference stack: reuse `preview_default.png` or add one asset. Decide at planning.
