# GoShade Turbo

Godot editor plugin that composes `canvas_item` shaders from a typed layer library. Stack layers, tune them with sliders, preview live, export a `.gdshader`.

## What it does
- Adds a main screen tab: stack list, selected layer properties, live preview.
- Picks layers from 61 functions across generative, sdf, fieldops, color, source, filter.
- Exports a `.gdshader` with a `// stack: <json>` header; opening it rebuilds the stack.
- Loads `.tres` recipes from `addons/goshade_turbo/recipes/` as a starting stack.
- Routes every stack and slider edit through editor undo.

## Requirements
- Godot `>= 4.4`. Tested on `4.4`, `4.6`, `4.7`.

## Install
Project Settings > Plugins > GoShade Turbo > Enable.

## Usage
1. Open the GoShade Turbo tab next to 2D, 3D and Script. Pick Create Empty Stack, or open a recipe.
2. Add layers from the picker and tune their sliders.
3. Export. Assign the `.gdshader` to any `CanvasItem` material.

Panel, picker, coordinate spaces, export header: https://github.com/kidsmeal/goshade-turbo/blob/main/docs/USAGE.md

## Library
61 functions with kind signatures and math sources: https://github.com/kidsmeal/goshade-turbo/blob/main/docs/LIBRARY.md

## Attribution
- `generative/hash`: David Hoskins hash12, MIT. Every other function cites its source in `docs/LIBRARY.md` in the repository.

## License
MIT. See `LICENSE` in this folder.
