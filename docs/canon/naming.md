# Naming

## Project
- Product: `GoShade Turbo`. (`DESIGN.md` status line, locked 2026-09-07)
- Repo: `goshade-turbo`. Addon folder: `addons/goshade_turbo`. (`DESIGN.md` status line)
- Class prefix: `GST`. (`DESIGN.md` status line)

## Code
- Script file `gst_<name>.gd`, class `GST<Name>`, e.g. `gst_stack_ops.gd` / `GSTStackOps`. (verified by glob of `addons/goshade_turbo/**/*.gd`)
- Shader-side identifiers the plugin owns start with `gst_`: `gst_rect_size`, `gst_screen_texture`. (`gst_codegen.gd:60`, `:65`)
- Filter template tokens start with `GST_`. (`PLAN.md B10`)
- Uniform, local and group names: see `codegen.md`.

## Library
- Manifest id: `<folder>/<snake_name>`. (`GSTManifestEntry.id`, `docs/LIBRARY.md`)
- A `function` that would collide with a GLSL builtin takes the `gst_` prefix: `gst_abs`, `gst_fract`, `gst_max`, `gst_min`, `gst_mix`, `gst_pow`, `gst_smoothstep`. (`docs/LIBRARY.md`)
- A `function` shared across folders takes a folder prefix: `color_add`, `color_mix`, `color_multiply`. (`docs/LIBRARY.md`)
- Blend modes: `blend_<mode>`. Shapes: `sdf_<shape>`. Sources: `gst_source_<name>`. (`docs/LIBRARY.md`)
- Variants of one entry share its stem: `cell_borders`, `cell_borders_round`, `cell_borders_round_varied`, `cell_borders_edge_warp`. (`docs/LIBRARY.md`)

## Recipes
- File stem is `snake_case`. Sprite finishes are `sprite_<finish>`. (verified by glob of `addons/goshade_turbo/recipes/`)

## UI terms (canonical spelling)
- Panels: `Layers`, `Layer settings`, `Preview`, `Final output`. (`EDITOR_UI d15`)
- Commands: `Add Layer`, `Create Empty Stack`, `Recipes`, `Randomize`, `Save`, `Export`, `File` menu with `New`, `Open`, `Save As`, `Reopen Shader`. (`EDITOR_UI d2`, `d27`)
- Picker tabs: `Existing layers`, `Add new`. (`EDITOR_UI d3`)
- Layer menu item: `Preview this layer`; back control: `Return to finished effect`. (`EDITOR_UI d14`, `d26`)
- States: `No effect yet`, `Showing last successful preview`. (`EDITOR_UI d6`, `d29`)
- Output: `Output color`, `Transparency`. (`docs/USAGE.md` Panel, `EDITOR_UI d28`)

## UI term to code term
| UI | Code | Source |
|---|---|---|
| Position | `offset` | `EDITOR_UI d30` |
| Movement speed | `scroll` | `EDITOR_UI d30` |
| Distortion inputs, Distortion strength | `warp_x`, `warp_y`, `warp_strength` | `EDITOR_UI d30`, `d33` |
| Transparency | `output_alpha` | `EDITOR_UI d28` |
| Final output | output block, `gst_output_block.gd` | `EDITOR_UI d13`, `DESIGN.md d12` |
| Preview this layer | solo, `solo_layer_id` | `EDITOR_UI d14`, `GSTCodegen.generate` |
| Input | slot, `GSTLayer.slots` | `EDITOR_UI d3`, `DESIGN.md` Data model |
| Color center | palette param `a` | `EDITOR_UI d31` |
