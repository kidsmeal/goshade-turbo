# GoShade Turbo: design

Status: grilled and locked 2026-09-07, revised the same day after external review (12 findings, all applied, see Review revisions). Name: GoShade Turbo (locked 2026-09-07). Repo `goshade-turbo`, addon folder `addons/goshade_turbo`, class prefix `GST`.

## What it is

A Godot editor plugin. A user builds a `canvas_item` shader by stacking typed layers, each one a function from a bundled MIT library, with sliders, live preview, and a self-contained `.gdshader` export. Target user: someone with no shader knowledge who wants to click things and see what happens, then ship the result.

Own project, own repo, MIT. Not a Capsule Castle feature.

## Prior art (why this exists)

Verified 2026-09-07. Nothing does the combination.

- godotshaders.com and the Godot Shaders Library addon: whole shaders, browse and install, no composing.
- LYGIA: the function library, no UI, Prosperity 3.0 license (see decision 15).
- Godot VisualShader plus ShaderV: node graph with preview and sliders. Graph shaped, not stack shaped.
- PS1 Shader Mixer: click, slide, export. Seven fixed post effects, no custom blocks.
- SHADERed Godot plugin, Shader Previewer, Godot Shaders Sketchbook: preview or debug one shader, no library.

## Locked decisions

Numbered in the order they were grilled. Each carries the alternative it beat. Revised items are marked.

1. Shader type: `canvas_item` only.
2. Two layer kinds: `field` (float) and `color` (vec4). Every layer declares its kind from its function signature. Mask and warp slots take fields. Blend slots take same kind. Boundaries auto-convert: field to color is grayscale, color to field is luminance. Conversion is inserted by codegen and shown as a tag on the slot, never an error. Beat: single vec4 type (destroys sdf and warp values), full types (graph again).
3. Inputs: any slot picks any earlier layer in the stack. Below is the default selection. No forward references, so no cycles. References are by stable layer id, never by index (revised). Beat: strict stack (cant fan out one noise to three consumers), full graph.
4. Generators carry a built-in coord block: scale, offset, rotation, scroll speed, plus two warp slots `warp_x` and `warp_y` (fields, applied after the transform, each optional) with one strength slider (revised: one scalar warp shifted both axes identically). Operators have no coord block. `TIME` enters the shader only through scroll. Beat: transforms as their own layers (three boilerplate layers before a pixel changes).
5. Library entries are a hand-written manifest, one file per function, with tuned slider ranges and a one-line description. Adding a function is adding a file. Beat: parsing a third party library (dead with decision 15).
6. Export inlines every reached function into one self-contained `.gdshader`. The plugin's live preview compiles the same text. Beat: `#include` lines (runtime dependency on the addon), two code paths.
7. Every slider exports as a `uniform` with the same `hint_range`. Names `l<id>_<function>_<param>`; coord block uniforms are `l<id>_scale`, `l<id>_offset`, `l<id>_rotation`, `l<id>_scroll`, `l<id>_warp_strength` with no function segment (revised at planning, B4). `group_uniforms L<position>_<function>;` per layer, position two-digit zero-padded, so the inspector reads like the stack (revised at planning, B3: a bare numeric position does not compile). Layer resources are authoritative; the plugin syncs the preview material from them on every change (revised: the earlier text had the material's inspector as the slider ui, which conflicted with decision 13). Beat: baked constants.
8. Source of truth is a `.tres` Resource per stack. Export writes the `.gdshader` and embeds the stack as json in a header comment so an exported shader reopens without its `.tres`. Reopen from header warns when the body differs from a fresh codegen.
9. Hand edits allowed. Export checks the target file against a fresh codegen of its header and asks before overwriting a differing body. The `custom` layer type (raw snippet with declared kinds) moves to v0.2 (revised).
10. Two source layers: `texture` (color, reads `TEXTURE`) and `screen` (color, reads the screen texture). Preview is a SubViewport with a TextureRect running the material, a preview image picker with a bundled default sprite. `screen` previews with the same image.
11. No target declaration at start. A stack-level coordinate space dropdown: `uv` (default), `screen_uv`, `local`. `local` is passed from `vertex()` through a varying, because `VERTEX` inside `fragment()` is screen space in canvas_item (revised, verified in the 4.4 shader reference). The varying is `VERTEX` divided by a `uniform vec2 gst_rect_size` set from the target node, so scale `1.0` matches `uv` (revised at planning, B5). Every generator coord block reads from it. Preview target presets: sprite, text, full rect. Switching a preset swaps the preview node only. Text preset suggests `screen_uv` if space is still `uv`.
12. Fixed output block at the bottom of the panel. `color` picker (any color layer, default the top color layer). `alpha` picker: any field, `texture` alpha, the selected color layer's own alpha, or `none` (revised: added the color layer's own alpha). Alpha defaults to `texture` alpha when a texture source exists, else `none`. Alpha is per pixel; combining alphas is a field operator layer. An `alpha(color) -> field` entry exists in the roster so operators can read alpha, since the automatic color to field conversion is luminance (revised).
13. Panel is a main screen tab next to 2D/3D/Script. Three columns: stack list, selected layer sliders (the inspector's own property editor pointed at the layer resource), preview. Picker opens as a popup from an add button. The preview has a solo toggle that shows the selected layer instead of the output, fields rendered grayscale, without changing the stack (revised: added).
14. Blend is not a per-layer property. A layer is a generator (coord block plus sliders) or an operator (typed slots plus sliders). `blendScreen(a, b)` is a layer, opacity is its `t` slider, a mask is `mix(a, b, mask)`. A "blend" quick-add inserts a `mix` referencing the two selected layers. Beat: photoshop per-layer blend/opacity/mask (two ways to do one thing).
15. Library source: our own MIT function library. LYGIA is Prosperity Public License 3.0 (noncommercial free, 30 day commercial trial, then a paid Patron license). Inlining it into exports would put that restriction inside every user's game. `lygia-godot` is a one star, year stale include-path rewrite, not a port. We keep LYGIA's folder taxonomy as organization. Formulas are not copyrightable; code is. Rule per entry: cite the source of the math, write the code, record a license only when code was copied from a permissive source. Not legal advice.
16. Recipes: the eight listed under Recipes. Randomize in v0.1 is slider randomization inside an open recipe's ranges, which always renders. Structural randomization (random layers and wiring) waits for the rendered checks that reject blank and non-finite output (revised).
17. Godot minimum 4.4, tested on 4.6 and 4.7. No api in the plan is newer than 4.4.
18. Repo: a plain Godot project with the plugin in `addons/<name>/`, project root as the sandbox holding reference stacks and screenshots, a headless test runner for codegen.
19. Picker: grouped by taxonomy folder, each entry shows function name, kind signature, and description. Search box. Opened from a slot, pre-filtered to entries whose output kind fits. Function names only, no display names, no thumbnails (user constraint).
20. Undo: every stack edit (add, remove, reorder, slot change, output change) registered with `EditorUndoRedoManager`. Slider edits come free from the inspector.
21. Filters that sample neighbors (blur, pixelate, chromatic split, outline, dither) operate on sources only in v0.1: they take a `texture` or `screen` layer and sample it at offset coordinates. A filter cannot take an arbitrary layer, because a layer is one value at this pixel. The general fix, compiling every layer as a function of coord so any layer can be re-evaluated at neighbors, is an expansion (new, from review).
22. Layer identity. Each layer has a stable id assigned at creation. References, uniform names, and undo records use the id. Reordering a layer above any layer it references is refused with the reason shown. Deleting a referenced layer resets every slot that pointed at it to the below default and reports which layers changed (new, from review).

## Data model

```
Stack (Resource)
  coord_space: uv | screen_uv | local
  layers: Array[Layer]            # order is stack order, index 0 is bottom
  output_color: StringName        # layer id, color kind
  output_alpha: StringName | "texture" | "color_alpha" | "none"
  next_id: int                    # monotonic, ids are never reused

Layer (Resource)
  id: StringName                  # stable, assigned at creation
  entry: String                   # manifest id, e.g. "generative/fbm"
  kind_out: field | color         # copied from manifest, fixed
  slots: Dictionary               # slot name -> layer id, kinds checked on assign
  params: Dictionary              # param name -> value, ranges from manifest
  coord: CoordBlock | null        # generators only

CoordBlock
  scale: Vector2, offset: Vector2, rotation: float, scroll: Vector2
  warp_x: StringName | ""         # layer id, field kind
  warp_y: StringName | ""         # layer id, field kind
  warp_strength: float
```

Reserved for expansion: `kind` may gain `vec2`; `Layer` may gain `custom_code` and `custom_kinds` (v0.2).

## Manifest entry (one file per function)

```
id: generative/fbm
function: fbm
description: layered noise, cloud like, octaves control detail
source_math: <url or citation>
source_code: null | {url, license}
kind_out: field
inputs: []                        # operators list [{name, kind}]
params:
  - {name: octaves, type: int, min: 1, max: 8, default: 4}
  - {name: gain, type: float, min: 0.2, max: 0.8, default: 0.5}
coord: true                       # generator
samples_source: false             # true for filters (decision 21), input must be a source layer
depends: [generative/snoise, math/hash]
code: |
  float fbm(vec2 p, int octaves, float gain) { ... }
```

Format: `.tres` or `.json`, decided at planning. Codegen requires `function` to be unique across the roster.

## Codegen rules

- Each layer becomes one local in `fragment()`, in stack order: `float l3 = fbm(coord3, l3_fbm_octaves, l3_fbm_gain);` where `3` is the layer id.
- Generator coord: `vec2 coord3 = transform(space_coord, l3_scale, l3_rotation, l3_offset);` then `coord3 += l3_scroll * TIME;` when scroll is nonzero at export, then `coord3 += vec2(l<wx>, l<wy>) * l3_warp_strength;` with a missing warp axis contributing `0.0`. When scroll is zero at export, neither the scroll uniform nor the `TIME` term is emitted, so a static stack has no `TIME`. When scroll is nonzero, both are emitted, so the exported uniform can animate.
- Slot conversion: field into color slot wraps as `vec4(vec3(lN), 1.0)`; color into field slot wraps as `luma(lN)`. Alpha is reached only through the `alpha` entry or the output block.
- Filters (`samples_source: true`): the input must be a source layer; codegen emits `texture(TEXTURE, uv + offset)` or the screen equivalent inside an inline block in `fragment()`, expanded from the manifest's body template (revised at phase 3, B10: Godot functions cannot read `TEXTURE`, and passing it as an argument prints an engine error on every compile). Any other input is refused at slot assignment.
- Uniforms: one per param, `hint_range(min, max)`, default from the layer, grouped per layer by stack position and function name.
- Include walk: depth first over `depends`, dedupe by id, emit function bodies before `fragment()`.
- Header: license notice, then `// stack: <json>` on one line.
- Output: `COLOR = vec4(l<c>.rgb, <alpha expr>);` where alpha is `1.0`, `texture(TEXTURE, UV).a`, `l<c>.a`, or `l<a>`.
- Solo preview: same codegen with the output replaced by the selected layer, fields as `vec4(vec3(lN), 1.0)`.
- Space: `uv` reads `UV`, `screen_uv` reads `SCREEN_UV`, `local` reads a `varying vec2 local_pos` set from `VERTEX` in `vertex()`.

## v0.1 roster (all written by us)

Counts are not a target. The release checklist below is.

- generative (field): value noise, perlin, simplex, fbm, voronoi, cellular edges, hash, checker, stripes, radial gradient, linear gradient.
- sdf (field): circle, box, rounded box, polygon, star, line, ring, union, subtract, intersect, smooth union.
- field ops: smoothstep, invert, remap, multiply, add, max, min, mix, pow, abs, fract, alpha (color to field).
- color: fill, gradient map, palette (cosine), hue shift, saturation, brightness contrast, posterize, multiply, screen, overlay, add, soft light, mix.
- source (color): texture, screen.
- filter (source to color, decision 21): pixelate, box blur, outline, chromatic split, dither.

Capsule Castle's `shaders/` folder already holds our own `random`, `noise`, `palette`, `hsv2rgb` in Godot shader language. They seed the roster with no license question.

## Recipes (each a `.tres` in the addon)

- water: warped noise, gradient map, scroll.
- fire: fbm through a palette, masked by a linear gradient, scroll.
- glow: sdf circle, smoothstep, additive over texture.
- dissolve: `alpha(texture)` times thresholded noise, edge color.
- outline: outline filter on texture, fill.
- hologram: texture, stripes, hue shift, scanline scroll.
- sprite finishes: holographic, pearl, foil, oil slick, opal, rebuilt from Capsule Castle's sprite shaders.
- metaball portal (the origin of the project, r/godot post by fespindola 2026-09-06): texture source showing a ViewportTexture of GPUParticles2D soft circles, luminance to field, smoothstep threshold (merged blob mask), outline filter on the source (edge field), cosine palette with scroll (edge color), voronoi thresholded and gradient mapped (stars), mix stars over base by mask, mix edge color by edge field, output alpha = blob mask. The particle half is Godot's own inspector, nothing to build.

Randomize (v0.1): a button on an open recipe that sets every slider to a random value inside its manifest range.

## Build order (architectural risks first)

1. Data model, ids, codegen for generators and field ops, headless codegen tests.
2. Main screen tab, stack list, picker, inspector column, preview, solo toggle, undo.
3. Save, reopen from `.tres`, export with header, reopen from header, overwrite check.
4. Prove three recipes end to end through save, reopen, export, and undo before writing the rest of the library: dissolve (alpha path), one sprite finish (color chain with scroll), outline (source filter path).
5. Remaining roster entries and recipes, reference screenshots, tuning pass.
6. Randomize, polish, release checklist.

## Release checklist (v0.1)

- [ ] Every roster entry above exists as a manifest file and compiles alone in the preview.
- [ ] Every entry has a reference stack with default sliders and a committed screenshot.
- [ ] Headless codegen tests pass: entry to shader text, include walk dedupe, slot conversion insertion, filter input refusal, id stability across reorder, delete of a referenced layer, header roundtrip, overwrite check, `TIME` emitted only with nonzero scroll.
- [ ] Combination tests: every field op with every generator as input compiles; every color op with every color entry as input compiles.
- [ ] Rendered checks on every reference stack and every recipe: no NaN or inf pixels, alpha channel within `[0, 1]`, output not uniformly one value.
- [ ] All eight recipes build from the roster only and pass the rendered checks.
- [ ] Tuning pass by the user: every slider produces a visible change across its whole range.
- [ ] Undo covers add, remove, reorder, slot change, output change.
- [ ] Runs on 4.4, 4.6, 4.7.

## Expansions (out of v0.1, named so they are not relitigated)

- Layers compiled as functions of coord so filters can take any layer, not only sources (decision 21).
- `custom` layer type, raw snippet with declared kinds (decision 9, v0.2).
- Structural randomize, random layers and wiring, gated on the rendered checks (decision 16).
- `vec2` kind and coord layers, so transforms can be driven by layers (decision 4).
- Shape toolkit ui and sdf beyond the four shipped ops.
- Preview pointed at a live node in the open scene (decision 10).
- Per-slider bake to constant on export (decision 7).
- `spatial`, `sky`, `fog` shader types.
- `particles` process shaders as a second stack type (per-particle state over time, not per-pixel over uv) with its own roster of operators (velocity fields, attractors, color over life). Reuses the field roster (noise, sdf) as inputs. Never planned as new layers in the canvas stack. Exported canvas shaders already work as a GPUParticles2D draw material today.
- `viewport` preview preset: a bundled GPUParticles2D rendered into a SubViewport feeding the preview texture, so the metaball portal recipe previews without setup.
- Picker display names and thumbnails.
- Godot 4.7 inline preview integration. Header parsers for third party libraries.
- Asset library publish, after the release checklist is green.

## Review revisions (2026-09-07)

External review returned 12 findings. Disposition:

- Filters cannot sample neighbors from one value: applied as decision 21, source-only filters, general fix listed as expansion.
- Alpha unreachable through luminance conversion: applied, `alpha` entry plus color-alpha output option (decision 12).
- Scalar warp shifts both axes identically: applied, `warp_x` and `warp_y` slots (decision 4).
- Layer identity across reorder and delete: applied as decision 22 and the data model.
- Slider model contradiction between decisions 7 and 13: applied, layer resources authoritative, material synced.
- `TIME` omission made exported scroll uniforms dead: applied, uniform and term emitted together or not at all.
- `VERTEX` in `fragment()` is screen space: applied, varying from `vertex()` (decision 11).
- Defer custom snippets: applied, v0.2.
- Defer arbitrary random stacks: applied partially, slider randomization inside a recipe stays in v0.1, structural randomize is an expansion.
- Selected-layer preview: applied, solo toggle (decision 13).
- Prove dissolve, a finish, and outline through save, reopen, export, undo before the library: applied as build order step 4.
- Counts wrong and verification thin: applied, counts removed, release checklist with combination and rendered checks added.

## Open

- Manifest file format: resolved at planning, `.tres` (see `docs/PLAN.md`, Decisions made at planning).
- Remaining planning blockers B2, B6, B7, B8 are listed in `docs/PLAN.md`.
