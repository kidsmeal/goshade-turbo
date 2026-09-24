# GoShade Turbo

Godot editor plugin for 2D shaders on sprites, UI and any other `CanvasItem`, built without a node graph or shader code. Stack layers in a list, tune sliders against a live preview, export a plain `.gdshader`.

## What it does
- Opens any of 13 bundled recipes from `recipes/` as a starting point, with every layer editable.
- Builds an effect as an ordered list of layers. Each layer is one function: a noise, a shape, a gradient, a blend, a filter.
- Connects layers through dropdowns. An input lists only the layers below it that produce the right type, so every stack compiles.
- Updates a live preview on a sprite, a text label or a full rect while you drag sliders.
- Randomize rerolls every layer's sliders within their ranges.
- Exports one `.gdshader`. A one-line header comment carries the whole stack, so opening the file restores the layers.
- Routes every edit through the editor's undo history.

## Requirements
- Godot `>= 4.4`. Tested on `4.4`, `4.6`, `4.7`.

## Install
Project Settings > Plugins > GoShade Turbo > Enable.

## Usage
Every layer outputs one of two types:
- `field`: one number per pixel, usually `0` to `1`. Noise, gradients and shapes are fields.
- `color`: an RGBA color per pixel. Fills, color ramps, blends and the sprite's own texture are colors.

1. Open the GoShade Turbo tab next to 2D, 3D and Script.
2. Recipes > pick one, or Create Empty Stack and Add layers.
3. Select a layer in Layers and drag its sliders in Layer settings.
4. In Final output, pick the Output color layer and the Transparency.
5. Export. Assign the `.gdshader` to a `ShaderMaterial` on any `CanvasItem`.

Panel, picker, coordinate spaces, export header: https://github.com/kidsmeal/goshade-turbo/blob/main/docs/USAGE.md

## Library
61 functions: noise and patterns, shapes, math on fields, color and blends, texture and screen sources, filters. Kind signatures and math sources: https://github.com/kidsmeal/goshade-turbo/blob/main/docs/LIBRARY.md

## Attribution
- `generative/hash`: David Hoskins hash12, MIT. Every other function cites its source in `docs/LIBRARY.md` in the repository.
- AI use: the code, tests and docs were written by AI coding agents, Anthropic Claude and OpenAI Codex. Exceptions, written by hand: `fieldops/ease`, `fieldops/ratchet`, `generative/cell_borders_round_varied`, `generative/cell_borders_edge_warp`.

## License
MIT. See `LICENSE` in this folder.
