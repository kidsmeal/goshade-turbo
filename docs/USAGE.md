# Usage

Panel, recipes, export, and coordinate spaces. Short form in `README.md`.

## Panel

The plugin adds a main screen tab next to 2D, 3D and Script. Three columns:
Layers (the stack), Layer settings (the selected layer's inputs and
sliders), Preview.

The add button opens a picker grouped by folder: generative, sdf, fieldops,
color, source, filter. Each entry shows its function name, kind signature
and description. The picker lists only entries whose output kind fits the
slot it was opened from.

Stack rules:

- A slot picks any layer below it. No forward references.
- A generator layer (noise, gradient, shape) has a Position and movement
  group: Scale, Position, Rotation, Movement speed, Distortion strength, and
  two optional distortion inputs, Horizontal and Vertical.
- Final output picks the Output color layer and the Transparency: a field
  layer's grayscale value, Texture transparency, Output layer transparency,
  Opaque, or Automatic (Texture transparency when the stack reads the
  node's texture, otherwise Opaque).
- Every stack edit goes through the editor's undo history. Slider edits go
  through the inspector, so they do too.

## Recipes

`Recipes` in the toolbar lists the `.tres` files under
`addons/goshade_turbo/recipes/` and opens one as a starting stack.

`Randomize` is enabled while a recipe is open. It sets every layer's
sliders to random values inside their ranges and leaves Position and
movement untouched. One undo reverts it.

## Export

Export writes a self-contained `.gdshader`: a license notice, one
`// stack: <json>` line carrying the whole stack, then the shader body.
Opening that file in the panel rebuilds the stack from the header. No
`.tres` needed.

Export compares an existing file's body against a fresh codegen of its own
header and asks before overwriting a hand-edited body. Opening a file with
no `// stack:` header, an unparsable header, or an unknown schema version is
refused with the reason.

## `local` coordinate space

The Coord space dropdown above Layers offers `uv`, `screen_uv` and `local`.
`local` is `VERTEX / gst_rect_size`, computed in `vertex()`, because
`VERTEX` inside `fragment()` is screen space in a `canvas_item` shader.

The plugin and the preview set the `gst_rect_size` uniform from the node's
rect size. An exported shader defaults it to `vec2(1.0)`. Set
`gst_rect_size` to the node's rect size on any node that gets a `local`
space shader, or it renders as if the node were 1x1.
