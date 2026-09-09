# GoShade Turbo: editor UI redesign

Status: design resolved through the user interview. Implementation pending.

Source: `C:/Users/atk67/Documents/goshade-turbo/docs/DESIGN.md`.

User-reported problems: long vertical menus and an undersized preview. User requirement: someone who has never used a shader can choose an effect, change it through clearly named controls, and export it.

The earlier six directions and their rankings were discarded when the user requested a restart. The decisions below describe the replacement design.

## Scope

- Retain the stack data model, stable IDs, earlier-layer references, automatic kind conversions, and source-only sampling filters.
- Retain the native `EditorInspector` property editors and existing shader parameter keys. Readable UI labels do not rename serialized keys or exported uniforms.
- Retain function names in the library, taxonomy grouping, kind signatures, and descriptions. No function display names or thumbnails.
- Retain blend operators as layers and one self-contained shader export.
- Supersede the output placement in original decision `12` and the picker/solo presentation in original decision `13`.
- The new add actions explicitly assign output. They do not change how codegen resolves an unset output in existing resources.

## Locked decisions

Numbered in interview order. Owner is the user unless marked as an implementation decision by Codex. Benefits remain unverified until the redesigned editor is tested.

1. Preview visibility: opening any layer or input picker leaves the preview visible and rendering. Pickers occupy the editing area. Beat: a popup covering the preview while the user chooses a function.

2. First session: prioritize choosing a recipe, adjusting its parameters, and exporting the result. First open presents recipe choices, Open, and Create Empty Stack. It does not automatically load a default recipe. Beat: requiring a new user to construct and wire an effect before seeing a result.

3. Input picker: each input control opens one picker with Existing layers and Add new tabs. Existing layers lists legal earlier layers. Add new creates a layer below the consuming layer and connects the selected input in one undoable action. Beat: separate dropdown and plus-button workflows.

4. Picker activation: clicking a selectable result applies it immediately and closes the picker. Enter performs the same action. There is no Apply step. Beat: selecting a result and confirming it with another button.

5. Conversion visibility: show a persistent conversion label both beside a connected input and beside an existing-layer candidate that requires conversion. Use `field -> color: grayscale` and `color -> field: luminance`. Styling is neutral. Labels remain visible without hovering. Beat: silent conversion or tooltip-only explanations.

6. Error locations: refused edits display their reason beside the initiating control and register no undo action. Codegen errors appear above the preview and remain until resolved. When retaining a previous successful render, label it Showing last successful preview. Beat: one shared message label whose meaning and lifetime depend on the last action.

7. Undo scope: stack edits remain in `EditorUndoRedoManager`, including stack replacement and recipe loading. Layer selection, individual-layer preview, preview image/preset, picker state, and panel resizing stay outside undo history. Beat: requiring undo presses to traverse navigation and viewing changes before reverting an edit.

8. Main allocation: default to `60%` editing and `40%` preview, with a draggable divider. These percentages apply to the available plugin panel after Godot's surrounding UI is accounted for. Beat: the proposed equal split and a preview receiving only the width left over from editing controls.

9. Editing arrangement and separation: within the editing area, put the stack beside the selected layer's controls. Separate sections with headings and visible dividers. Keep input controls distinct from parameter controls and position/movement controls. Beat: controls expanding inside stack rows or sections running together without visible boundaries.

10. Long stacks: retain one flat, ordered list. At `20` layers, scroll that list independently while the selected-layer controls and preview remain in place. Beat: expanding inspector controls inside the list or adding collapsible layer groups.

11. Picker modality: while a picker is open, block other stack edits so its destination cannot change. The preview continues rendering. Closing or cancelling the picker restores ordinary editing. Beat: allowing selection or structure changes to invalidate an open picker's destination.

12. Picker size and position: the picker fills the editing area and stays fixed within it. Search sits above a multi-column results list with room for function names, kinds/signatures, and descriptions. Beat: a small floating popup with long, vertically stacked menu items.

13. Output placement: put output color and alpha controls in a separate, labeled Final output section beneath the preview. This section does not scroll with layers or parameters. Beat: output controls sharing the narrow stack column.

14. Individual-layer preview: the primary preview shows the finished effect. Put Preview this layer in the layer's secondary menu. Do not put a Solo checkbox or Output/Selected switch in the main controls. Beat: presenting a troubleshooting mode as a primary beginner action.

15. UI language: use readable section names, including Layers, Layer settings, Preview, and Final output. Input and parameter labels describe their specific function. Use familiar terms such as Position, Rotation, and Transparency where they match the control's behavior. Keep library function names unchanged. Beat: exposing internal property names without an explanation or replacing library function names with aliases.

16. Empty-stack entry: Create Empty Stack immediately opens the library. Beat: creating an empty workspace and requiring another Add Layer click.

17. First output: choosing the first layer also assigns it to the output in the same undo action. Field output uses the existing grayscale conversion. Beat: adding a field successfully while the preview continues to show an unrelated default output.

18. First-library eligibility: when there are no layers, initially offer only entries that work without an existing input layer, including standalone generators and sources. Functions requiring earlier inputs become available during later additions. Beat: offering a first choice that immediately requires wiring or produces an unresolved-input error.

19. Later additions: Add Layer appends at the top and makes that new layer the output in the same undo action. Add new from an input picker preserves the current output. Beat: leaving the first explicitly selected output unchanged as the user adds subsequent top-level layers, or changing the output when merely supplying an input.

20. Search: match descriptions as well as function names. A descriptive query such as `noise` can find `fbm`. Retain taxonomy and context filters. Beat: requiring users to know a function's identifier before they can find it.

21. Layout persistence: remember panel widths and collapsed sections between sessions, outside stack undo and stack serialization. Beat: resetting the user's layout whenever the editor restarts.

22. Narrow layout: when the available width cannot fit both editing columns, use Layers and Layer settings tabs inside the editing area. Preserve the separate preview allocation, defaulting to `40%`. Beat: shrinking the preview further or allowing editing controls to overflow the panel.

## Interaction details

The following are implementation decisions by Codex within the approved design. They retain the existing product constraints.

23. Stack identity: show each row's function, kind, and stable layer ID. Keep row height fixed and preserve the existing top-to-bottom display order. Selection, references, and scrolling use stable IDs. Beat: position-based identities or expanded controls that displace adjacent rows.

24. Input context: show the destination layer and input at the top of the picker. Existing-layer choices obey earlier-layer and source-only restrictions. New-entry choices retain the slot-kind prefilter and must also obey source-only restrictions. Preserve optional empty inputs. Beat: presenting a selectable choice that assignment subsequently refuses for a known restriction.

25. Keyboard flow: opening a picker focuses search; arrow keys navigate selectable results; Enter applies; Escape cancels without a stack edit and restores focus to the initiating control. Switching tabs retains the destination. Beat: mouse-only completion or focus returning to an unrelated editor control.

26. Preview controls: place preview target and image controls above the preview. Keep sprite, text, and full-rectangle behavior and the existing coordinate-space suggestion for text. During individual-layer preview, identify the layer and show Return to finished effect. Export continues to use the stack output. Beat: leaving a user in a diagnostic preview without a visible way back.

27. Toolbar grouping: keep Save and Export directly accessible. Place New, Open, Save As, and Reopen Shader in a File menu. Keep Recipes accessible without returning to the initial screen; its choices use the wide picker treatment. Keep Randomize associated with an open recipe. Beat: a single row containing every file, recipe, and editing command.

28. Output editing: output selectors use the same wide chooser treatment rather than long dropdowns. Preserve automatic/default choices and all existing alpha modes. Name alpha Transparency in the UI, with readable descriptions for the modes. Show the effective layer or mode for an automatic choice. Beat: ambiguous empty/default labels and output menus retaining the original menu problem.

29. Empty and recovery states: before a recipe or layer is chosen, label the preview No effect yet. Cancelling the first library picker leaves an empty stack with Add Layer available. If no successful preview exists, a codegen error cannot claim to show a previous successful render. Refusals and codegen failures retain separate state. Beat: blank unexplained space or unrelated successful actions clearing an unresolved error.

30. Property presentation: keep shader parameters in native property editors. Give parameter and input labels function-specific definitions; do not apply one generic rename to every `a`, `b`, or `t`. Hide implementation bookkeeping from the normal editing surface. Beat: a custom slider implementation or misleading labels derived from identifier spelling alone.

## Layout

Proportional sketch. Pixel dimensions and the narrow-layout breakpoint require measurement in Godot.

```text
+--------------------------------------------------------------------------+
| File v   Save   Recipes                                     Export...    |
+--------------------------------------------+-----------------------------+
| Editing area: 60%                          | Preview area: 40%           |
+------------------+-------------------------+-----------------------------+
| Layers   [+ Add] | Layer settings          | Target [Sprite v]  [Image]  |
|                  |                         |                             |
| function / kind  | Input layers            |                             |
| stable ID        | [Choose input...]       |                             |
|                  | conversion explanation  |        LIVE PREVIEW         |
| selected layer   +-------------------------+                             |
|                  | Parameters              |                             |
|                  | native property editors |                             |
|                  +-------------------------+-----------------------------+
|                  | Position and movement   | Final output                |
|                  | native property editors | Color [Choose...]           |
|                  |                         | Transparency [Choose...]    |
+------------------+-------------------------+-----------------------------+

Picker open:
+--------------------------------------------+-----------------------------+
| Choose input for <layer> / <input>          | Preview remains visible     |
| [Existing layers] [Add new]                 | and continues rendering     |
| [Search names and descriptions...]         |                             |
| Function       Kind/signature  Description |                             |
| ...                                        |                             |
| Escape to cancel                           |                             |
+--------------------------------------------+-----------------------------+
```

## Verification and implementation checks

Verified by reading the current UI code and `C:/Users/atk67/Documents/goshade-turbo/docs/EDITOR_SMOKE.md`:

- The current UI has separate stack, inspector, and preview columns; the preview has no explicit minimum size in its scene.
- Current function search matches function names only. Input rows do not show conversion tags.
- Add-for-slot already creates and connects a layer in a compound undo action.
- Explicit output selection remains unchanged when a new layer is appended; the approved add behavior requires a change.
- The recorded editor smoke covers structural undo, stack replacement, preview recovery, and recipe randomization. The final version matrix records `123` test methods and `78` rendered stack checks on Godot `4.4`, `4.6.2`, and `4.7`.

Unverified until implementation:

- Native property-editor labels and section presentation work across the supported Godot versions without changing serialized parameter keys or losing undo behavior.
- The layout fits the actual plugin rectangle at `1366x768`, including Godot's visible docks, toolbars, and editor scale. Determine the tab-layout breakpoint from measured control minimum sizes.
- Long names, conversion labels, and error messages remain readable without widening the panel beyond its allocation.
- A `20`-layer stack retains independent scrolling, stable selection, and usable source selection.
- Pickers preserve destination, focus, and preview visibility through selection, cancellation, and narrow-layout tab changes.
- Add plus output assignment, and add plus input assignment, each undo and redo as one operation.
- A new user can choose a recipe, change its effect, and export without needing shader terminology explained externally.

Existing consistency check required during implementation: `GSTUndo.assign_warp` currently rejects color layers, while original design decision `2` describes automatic conversion at field/color boundaries. Do not display a conversion tag for an operation the current backend cannot perform. Check the complete warp path against the retained conversion contract before changing that picker.
