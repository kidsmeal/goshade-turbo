# Stack model

## Kinds
- Two kinds: `field` (float) and `color` (vec4). (`DESIGN.md d2`)
- A layer's kind comes from its manifest function signature and never changes (`kind_out`). (`DESIGN.md d2`, Data model)
- Mask and warp inputs take fields. Blend inputs take the same kind. (`DESIGN.md d2`)
- Field into a color input converts to grayscale: `vec4(vec3(f), 1.0)`. (`DESIGN.md d2`, Codegen rules)
- Color into a field input converts to luminance: `luma(c)`. (`DESIGN.md d2`, Codegen rules)
- Conversion is inserted by codegen, shown as a label, never an error. (`DESIGN.md d2`, `EDITOR_UI d5`)
- Warp inputs accept color layers through luminance conversion. (`EDITOR_UI` closing paragraph)
- Alpha is reached only through `fieldops/alpha` or the output block; automatic conversion is luminance. (`DESIGN.md d12`, Codegen rules)

## Layer roles
- Generator: has a coord block, no input slots. (`DESIGN.md d4`, `d14`)
- Operator: typed input slots plus sliders, no coord block. (`DESIGN.md d4`, `d14`)
- Source: `source/texture` reads `TEXTURE`; `source/screen` reads the screen texture. Kind `color`. (`DESIGN.md d10`)
- Filter (`samples_source: true`): samples a source layer at neighbor offsets. (`DESIGN.md d21`)
- A filter input accepts only a `source/texture` or `source/screen` layer. Filter-of-filter is refused. (`DESIGN.md d21`, `PLAN.md B6`)
- A filter refusal names the slot and the offending layer. (`PLAN.md B6`)
- A filter input left unwired produces a codegen error naming the filter layer. (`PLAN.md cross-cutting`, unwired filter rule)

## Coord block
- Fields: `scale`, `offset`, `rotation`, `scroll`, `warp_x`, `warp_y`, `warp_strength`. (`DESIGN.md d4`, Data model)
- `warp_x` and `warp_y` are optional field inputs applied after the transform, with one strength. (`DESIGN.md d4`)
- `TIME` enters a shader only through scroll. (`DESIGN.md d4`)

## References and identity
- An input picks any layer below it. The default is the layer directly below. No forward references, no cycles. (`DESIGN.md d3`)
- References use the stable layer id, never the index. (`DESIGN.md d3`, `d22`)
- Ids come from `GSTStack.next_id`, are monotonic and are never reused. (`DESIGN.md d22`, Data model)
- Ids key references, uniform names and undo records. (`DESIGN.md d22`)
- Moving a layer above a layer it references is refused with the reason. (`DESIGN.md d22`)
- Deleting a referenced layer resets each pointing input to the below default and reports which layers changed. (`DESIGN.md d22`)
- An unset operator input compiles with a typed constant: `GSTCodegen.FALLBACK_FIELD_CONSTANT` `0.5`, `FALLBACK_COLOR_CONSTANT` `vec4(0.5, 0.5, 0.5, 1.0)`. (`addons/goshade_turbo/codegen/gst_codegen.gd:12-14`, `EDITOR_UI d3`)

## Output
- `output_color` is any color layer; a field layer is accepted and shown as grayscale. (`DESIGN.md d12`)
- Unset `output_color` resolves to the top color layer. (`DESIGN.md d12`, `PLAN.md B7`)
- `output_alpha` is a field layer, `texture`, `color_alpha` or `none`. (`DESIGN.md d12`)
- Unset `output_alpha` resolves to `texture` when a texture source exists, else `none`. (`DESIGN.md d12`, `PLAN.md B7`)
- A field output applies the selected alpha mode; `field + color_alpha` uses `1.0`. (`EDITOR_UI d28`)
- Alpha is per pixel; combining alphas is a field operator layer. (`DESIGN.md d12`)

## Coord space
- Stack-level `coord_space`: `uv` (default), `screen_uv`, `local`. (`DESIGN.md d11`)
- `local` is `VERTEX / gst_rect_size`, computed in `vertex()` and passed through a varying, because `VERTEX` in `fragment()` is screen space. (`DESIGN.md d11`, `PLAN.md B5`)
- `gst_rect_size` defaults to `vec2(1.0)` in an export; the user sets it to the node's rect size. (`PLAN.md B5`, `docs/USAGE.md` `local` section)

## Persistence
- A stack `.tres` is the source of truth. (`DESIGN.md d8`)
- An exported shader carries the stack as json in its header and reopens without the `.tres`. (`DESIGN.md d8`)
- Layer resources are authoritative; the preview material is synced from them on every change. (`DESIGN.md d7`)
