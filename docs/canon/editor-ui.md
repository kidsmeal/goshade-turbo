# Editor UI

## Layout
- The panel is a main screen tab next to 2D, 3D and Script. (`DESIGN.md d13`)
- Editing area beside preview, default `60%` / `40%`, draggable divider. (`EDITOR_UI d8`)
- Editing area: Layers beside Layer settings. Inputs, parameters and Position and movement are separate sections. (`EDITOR_UI d9`)
- Final output sits beneath the preview and does not scroll with layers. (`EDITOR_UI d13`)
- Below measured minimum widths, Layers and Layer settings become tabs; the preview keeps its allocation. (`EDITOR_UI d22`)
- Layout state lives in editor-only project metadata, never in the stack, header, export or undo. (`EDITOR_UI d21`)
- One flat ordered layer list; long lists scroll on their own. Selection and scroll restore by stable id. (`EDITOR_UI d10`, `d23`)

## Labels
- Section names: Layers, Layer settings, Preview, Final output. (`EDITOR_UI d15`)
- Coord labels: `offset` is Position, `rotation` is Rotation, `scroll` is Movement speed, warp rows are horizontal and vertical distortion inputs. (`EDITOR_UI d30`)
- Alpha is Transparency: `none` is Opaque, `texture` is Texture transparency, `color_alpha` is Output layer transparency, a field is that layer's grayscale value. (`EDITOR_UI d28`)
- UI labels never rename serialized keys or exported uniforms. (`EDITOR_UI` Scope, `d30`)
- Library function names stay unchanged and visible. (`EDITOR_UI d15`, `DESIGN.md d19`)
- User-facing messages carry no design-doc ids. (`90d59dd`)
- Conversion labels stay visible without hover: `field -> color: grayscale`, `color -> field: luminance`. (`EDITOR_UI d5`)

## Property editors
- Parameters use native editors from `EditorInspector.instantiate_property_editor`. No custom slider widgets. (`EDITOR_UI d30`, `SHADER_TABS d7`)
- Native rows bind through `set_object_and_property`; no Godot editor internals are patched. (`SHADER_TABS d7`)
- Ineffective controls are read-only with the reason shown below them. (`EDITOR_UI d33`)
- Raw `id`, `entry`, `kind_out`, `slots`, `params`, `coord` stay off the editing surface. (`EDITOR_UI d30`)

## Pickers
- An open picker fills the editing area; the preview stays visible and rendering. (`EDITOR_UI d1`, `d12`)
- Search covers function name and description, case-insensitive. (`EDITOR_UI d20`)
- Click or Enter applies and closes. No Apply step. Escape cancels and restores focus. (`EDITOR_UI d4`, `d25`)
- A picker captures an immutable destination and revalidates it before mutating. A stale destination mutates nothing and registers no undo. (`EDITOR_UI d11`)
- While a picker is open, mutating toolbar commands are disabled. (`EDITOR_UI d11`)
- Input pickers offer only legal choices: earlier layers, source-only rules, exact or convertible kinds. (`EDITOR_UI d24`)

## Adding layers
- First layer: only entries with no inputs. Adding it assigns `output_color` in the same undo action. (`EDITOR_UI d17`, `d18`)
- Add Layer appends at the top, wires each input to the layer below where legal, assigns `output_color`, one undo action. (`EDITOR_UI d19`)
- Add new from an input picker inserts directly below the consumer, wires its inputs the same way, keeps the current output. (`EDITOR_UI d3`, `d19`)
- Warp inputs stay empty on add. (`EDITOR_UI d19`)

## Messages
- A refused edit shows its reason beside the initiating control and registers no undo action. (`EDITOR_UI d6`)
- Codegen errors show above the preview until a later codegen succeeds. (`EDITOR_UI d6`)
- After a failure, the last successful preview of the same stack stays, labelled Showing last successful preview. (`EDITOR_UI d29`)
- An empty stack shows No effect yet and is not a codegen failure. (`EDITOR_UI d29`)
- File-operation messages are kept per document and re-shown on tab activation. (`SHADER_TABS d8`, `EDITOR_UI d6` supersede note)

## Undo
- Each shader document owns one Godot `UndoRedo`. Every stack edit, native property edits included, registers there. (`DESIGN.md d20`, `SHADER_TABS d6`)
- Godot scene history stays separate and is never cleared or rewritten. (`SHADER_TABS d6`)
- Structural mutations go through `GSTUndo`, never direct `GSTStack` writes. (`PLAN.md cross-cutting`)
- Compound adds are one action. (`EDITOR_UI d7`)
- One native slider gesture is one undo action; repeated gestures stay separate. (`SHADER_TABS d7`)
- A pending native edit finishes before rebind, save or undo. (`SHADER_TABS d7`)
- Outside undo: selection, layer preview, preview image and preset, picker state, start surface, layout, tab open and close. (`EDITOR_UI d7`, `SHADER_TABS d9`)

## Documents and tabs
- A document is identified by a stable session id, never tab index or filename. Session ids are never exported. (`SHADER_TABS d3`)
- Save, Save As and Export act on the initiating document. (`SHADER_TABS d8`)
- Save As onto a path owned by another open document is refused. (`SHADER_TABS d8`)
- Closing a dirty document offers Save, Discard, Cancel. (`SHADER_TABS d9`)
- Switching tabs performs no undo action and cancels an open picker. (`SHADER_TABS d5`)

## Preview
- Preview targets: sprite, text, full rect. Switching swaps the preview node only. (`DESIGN.md d11`)
- The text preset suggests `screen_uv` while space is `uv`. (`DESIGN.md d11`)
- Preview this layer lives in the layer menu, is viewing state, and never changes output or export. (`EDITOR_UI d14`, `d26`)
- The preview draws a checkerboard behind transparent output. (`EDITOR_UI d32`)

## Randomize
- Enabled while a recipe is open. Sets slider params inside their ranges, leaves Position and movement unchanged, one undo reverts it. (`DESIGN.md d16`, `docs/USAGE.md` Recipes, `EDITOR_UI d27`)
