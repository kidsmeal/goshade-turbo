# GoShade Turbo: editor UI redesign

Status: reviewed

Source: `C:/Users/atk67/Documents/goshade-turbo/docs/DESIGN.md`.

User-reported problems: long vertical menus and an undersized preview. User requirement: someone who has never used a shader can choose an effect, change it through clearly named controls, and export it.

The earlier six directions and their rankings were discarded when the user requested a restart. The decisions below describe the replacement design.

## Scope

- Retain the stack data model, stable IDs, earlier-layer references, automatic kind conversions, and source-only sampling filters.
- Retain the native `EditorInspector` property editors and existing shader parameter keys. Readable UI labels do not rename serialized keys or exported uniforms.
- Retain function names in the library, taxonomy grouping, kind signatures, and descriptions. No function display names or thumbnails.
- Retain blend operators as layers and one self-contained shader export.
- Supersede the output placement in original decision `12` and the picker/solo presentation in original decision `13`.
- The redesigned UI add paths explicitly initialize inputs and assign output. Existing resources with unset outputs or inputs retain their current codegen fallback behavior.
- Repair codegen paths that contradict retained decisions `2` and `12`: warp accepts color-to-field luminance conversion, and a field selected as output color still uses the selected transparency mode. These are compatibility fixes within the existing model and shader contract.

## Locked decisions

Numbered in interview order. Owner is the user unless marked as an implementation decision by Codex. Benefits remain unverified until the redesigned editor is tested.

1. Preview visibility: opening any layer, input, recipe, or output picker leaves the preview visible and rendering. Pickers replace the editing area's contents for their lifetime; they never cover or collapse the preview area. Beat: a popup covering the preview while the user chooses a function.

2. First session: when the panel opens with its initial unsaved empty stack, the editing area presents recipe choices, Open, and Create Empty Stack while the preview says No effect yet. Choosing a recipe or successfully opening a stack enters the ordinary editor. Create Empty Stack enters the ordinary editor and immediately opens the first-layer library. Dismissing this start surface is navigation state outside undo; undoing an initial recipe/open replacement returns to the ordinary empty editor rather than reopening the start surface. Beat: requiring a new user to construct and wire an effect before seeing a result.

3. Input picker: each input control opens one picker with Existing layers and Add new tabs. Existing layers lists legal earlier layers. Add new creates a layer immediately below the consuming layer, initializes that new layer's own manifest inputs from its immediate below default where legal, and connects the destination input in one undoable action. Existing saved empty slots continue to use the current typed codegen constants until the user assigns them. Beat: separate dropdown and plus-button workflows.

4. Picker activation: clicking a selectable result applies it immediately and closes the picker. Enter performs the same action. There is no Apply step. A refused activation leaves the picker open, preserves its destination, and shows the reason beside the initiating control. Beat: selecting a result and confirming it with another button.

5. Conversion visibility: show a persistent conversion label both beside a connected input and beside any existing-layer or add-new candidate that requires conversion. Use `field -> color: grayscale` and `color -> field: luminance`. Styling is neutral. Labels remain visible without hovering. The retained conversion contract applies to manifest inputs and the field-kind warp inputs; slot filtering must include opposite-kind candidates that codegen can convert. Beat: silent conversion or tooltip-only explanations.

6. Error locations: refused edits display their reason beside the initiating control and register no undo action. A control-local refusal clears only when that control completes a valid edit, its destination is removed, or the active stack is replaced. Codegen errors appear above the preview and remain until a later codegen succeeds for the active stack. A successful control edit does not clear an unrelated codegen error, and a successful codegen does not clear an unrelated control refusal. When retaining a previous successful render from the same active stack, label it Showing last successful preview. Beat: one shared message label whose meaning and lifetime depend on the last action.

7. Undo scope: stack edits remain in `EditorUndoRedoManager`, including stack replacement and recipe loading. Layer selection, individual-layer preview, preview image/preset, picker state, start-surface state, and panel resizing stay outside undo history. Compound add operations record layer creation, initialized inputs, destination wiring, and any required output assignment as one action. Beat: requiring undo presses to traverse navigation and viewing changes before reverting an edit.

8. Main allocation: default to `60%` editing and `40%` preview, with a draggable divider. These percentages apply to the available plugin panel after Godot's surrounding UI is accounted for. Both sides receive measured minimum widths; the narrow-layout rule activates before either side falls below its minimum. Beat: the proposed equal split and a preview receiving only the width left over from editing controls.

9. Editing arrangement and separation: within the editing area, put the stack beside the selected layer's controls. Separate sections with headings and visible dividers. Keep input controls distinct from parameter controls and position/movement controls. Beat: controls expanding inside stack rows or sections running together without visible boundaries.

10. Long stacks: retain one flat, ordered list. At `20` layers, scroll that list independently while the selected-layer controls and preview remain in place. Selection and scroll restoration use stable layer IDs rather than row indices. Beat: expanding inspector controls inside the list or adding collapsible layer groups.

11. Picker modality: opening a picker captures an immutable destination containing the active stack instance, picker purpose, destination layer ID where applicable, and input/warp name where applicable. While it is open, a full-rect `PanelContainer` overlay inside the editing allocation stops mouse input, and mutating toolbar commands plus focus-driven shortcuts are disabled. This blocks layer structure, input/output edits, recipe replacement, New/Open, and Randomize while leaving Save, Export, preview controls, and preview rendering available. Activation revalidates the captured stack and stable IDs before mutation; a stale destination registers no undo action and reports beside the initiating control. Closing or cancelling the picker restores ordinary editing. Beat: allowing selection or structure changes to invalidate an open picker's destination.

12. Picker size and position: the picker fills the editing area and stays fixed within it. Search sits above a multi-column results list with dedicated columns for function name, kind/signature, and description. Results scroll inside the picker. Beat: a small floating popup with long, vertically stacked menu items.

13. Output placement: put output color and transparency controls in a separate, labeled Final output section beneath the preview. This section remains visible at the bottom of the preview allocation and does not scroll with layers, parameters, or the preview image. Beat: output controls sharing the narrow stack column.

14. Individual-layer preview: the primary preview shows the finished effect. Put Preview this layer in the selected layer's secondary menu. Do not put a Solo checkbox or Output/Selected switch in the main controls. This mode remains viewing state and never changes output fields or exported shader text. Beat: presenting a troubleshooting mode as a primary beginner action.

15. UI language: use readable section names, including Layers, Layer settings, Preview, and Final output. Input and parameter labels describe their specific function. Use familiar terms such as Position, Rotation, and Transparency where they match the control's behavior. Keep library function names unchanged. Beat: exposing internal property names without an explanation or replacing library function names with aliases.

16. Empty-stack entry: Create Empty Stack and File > New both install an empty stack, enter the ordinary editor, and immediately open the first-layer library. Cancelling leaves the empty editor visible with Add Layer available and No effect yet above the preview. Beat: creating an empty workspace and requiring another Add Layer click.

17. First output: choosing the first layer assigns its stable ID to `output_color` in the same undo action as the add. Field output uses the existing grayscale conversion and the selected/default transparency mode. Undo removes the layer and restores the previous output field; redo restores both. Beat: adding a field successfully while the preview continues to show an unrelated default output.

18. First-library eligibility: when there are no layers, offer only manifest entries with no layer inputs. This includes standalone generators, sources, and any other zero-input entry. Functions with one or more manifest inputs, including source-sampling filters, become available during later additions. The same filter applies from the initial start surface, Create Empty Stack, File > New, and Add Layer on an empty stack. Beat: offering a first choice that immediately requires wiring or produces an unresolved-input error.

19. Later additions: Add Layer appends at the top, initializes every manifest input to the layer immediately below when that assignment is legal, and assigns the new layer's ID to `output_color`; creation, input initialization, and output assignment are one undo action. Ordinary field/color kind differences are legal through decision `2` conversion. A `samples_source` input receives the immediate below layer only when it is `source/texture` or `source/screen`; otherwise it remains empty for the user to complete. Optional warp inputs remain empty. Add new from an input picker follows the same input-default rule for the inserted layer but preserves the stack's current output. Beat: leaving the first explicitly selected output unchanged as the user adds subsequent top-level layers, or changing the output when merely supplying an input.

20. Search: match the visible function name and manifest description, case-insensitively. A descriptive query such as `noise` can find `fbm`. Retain taxonomy and picker-context filters, and keep folder rows visible only while they contain a matching selectable entry. Beat: requiring users to know a function's identifier before they can find it.

21. Layout persistence: remember the main divider ratio, the editing-area column divider ratio, narrow-layout tab selection, and collapsed section state in editor-only project metadata. Restore values with bounds derived from measured minimum sizes. Do not write them into the stack resource, shader header, exported shader, or undo history. Beat: resetting the user's layout whenever the editor restarts.

22. Narrow layout: when the available width cannot satisfy the measured minimum widths of both editing columns, use Layers and Layer settings tabs inside the editing area. Preserve the separate preview allocation, defaulting to `40%`. The breakpoint is computed from those control minimums at the active editor scale rather than fixed to one screen width. Beat: shrinking the preview further or allowing editing controls to overflow the panel.

## Interaction details

The following are implementation decisions by Codex within the approved design. They retain the existing product constraints.

23. Stack identity: show each row's function, kind, and stable layer ID. Keep row height fixed and preserve the existing top-to-bottom display order. Selection, references, independent scrolling, and restoration after rebuilds use stable IDs. Beat: position-based identities or expanded controls that displace adjacent rows.

24. Input context: show the frozen destination layer and input at the top of the picker. Existing-layer choices obey earlier-layer and source-only restrictions. New-entry choices obey source-only restrictions for the destination and include exact-kind plus automatically convertible output kinds. Preserve optional empty inputs. Display the current connection and its conversion label beside the initiating control after the picker closes. Beat: presenting a selectable choice that assignment subsequently refuses for a known restriction.

25. Keyboard flow: opening a picker focuses search; arrow keys navigate selectable results; Enter applies; Escape cancels without a stack edit and restores focus to the initiating control. Switching Existing layers/Add new tabs retains search text and the frozen destination. Beat: mouse-only completion or focus returning to an unrelated editor control.

26. Preview controls: place preview target and image controls above the preview. Keep sprite, text, and full-rectangle behavior and the existing coordinate-space suggestion for text. During individual-layer preview, identify the layer by function and stable ID and show Return to finished effect. Export continues to use the stack output. Beat: leaving a user in a diagnostic preview without a visible way back.

27. Toolbar grouping: keep Save and Export directly accessible. Place New, Open, Save As, and Reopen Shader in a File menu. Keep Recipes accessible without returning to the initial screen; its choices use the wide picker treatment. Keep Randomize associated with an open recipe. Mutating toolbar actions follow picker modality in decision `11`. Beat: a single row containing every file, recipe, and editing command.

28. Output editing: output selectors use the same wide chooser treatment rather than long dropdowns. Preserve the unset automatic choices and all existing alpha modes. Name alpha Transparency in the UI and describe `none` as Opaque, `texture` as Texture transparency, `color_alpha` as Output layer transparency, and a field layer as that layer's grayscale value. Show the effective layer or mode for an automatic choice. A field selected as output color must still apply the selected `_alpha_expr`; codegen may not hardcode alpha `1.0` for every mode. When `color_alpha` is selected for a field output, use `1.0`, which is the alpha of decision `2`'s `vec4(vec3(field), 1.0)` field-to-color conversion. Existing `field + color_alpha` resources remain valid and choosing a field output never creates a new refusal. Beat: ambiguous empty/default labels, output menus retaining the original menu problem, or a transparency choice the generated shader ignores.

29. Empty and recovery states: before a recipe or layer is chosen, label the preview No effect yet and do not treat the empty stack as a codegen failure. Cancelling the first library picker leaves an empty stack with Add Layer available. Track the last successful material per active stack installation; replacing the stack clears that cache before the new stack generates, so a broken opened stack cannot display an unrelated prior stack. If the active stack has a prior successful material, a later codegen failure retains it and shows Showing last successful preview beneath the error. Without one, show the error and no prior-effect claim. Refusals and codegen failures retain the separate lifecycles in decision `6`. Beat: blank unexplained space or unrelated successful actions clearing an unresolved error.

30. Property presentation: keep shader parameters in native property editors. Extend manifest input and parameter dictionaries with editor-only `label` and `description` metadata; every shipped input and parameter defines both. Labels are function-specific and never derived by applying one generic rename to `a`, `b`, or `t`. Fixed coordinate metadata presents `offset` as Position, `rotation` as Rotation, `scroll` as Movement speed, and the warp rows as horizontal/vertical distortion inputs. Register an `EditorInspectorPlugin`; in `parse_property`, create the standard editor with `EditorInspector.instantiate_property_editor` using the original property path/range metadata, then pass it to `add_property_editor(property, editor, false, readable_label)`. Use the manifest description as the tooltip. The editor continues to read and write the original property name in `GSTLayer.params`; serialization, uniform names, and native inspector undo remain unchanged. Hide `id`, `entry`, `kind_out`, raw `slots`, raw `params`, `coord`, and manifest bookkeeping from the normal editing surface. Beat: a custom slider implementation or misleading labels derived from identifier spelling alone.

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
| stable ID        | [Choose input...]       |        LIVE PREVIEW         |
|                  | conversion explanation  |                             |
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

Verified by reading the current UI, model, codegen, and smoke-test code, plus `C:/Users/atk67/Documents/goshade-turbo/docs/EDITOR_SMOKE.md`:

- The current UI has separate stack, inspector, and preview columns; the preview has no explicit minimum size in its scene.
- The current main-screen root is a vertical child with minimum size `959x181`; its two built-in sibling screens use horizontal expand/fill size flags while the plugin root does not. The layout implementation must give the root matching expansion flags before measuring split allocations.
- Godot `4.4` exposes `EditorInspector.instantiate_property_editor`, `EditorInspectorPlugin.add_property_editor(..., label)`, and `EditorPlugin.add_inspector_plugin`; the native-label design has an available API path across the minimum version.
- Current function search matches function names only. Input rows do not show conversion tags, and slot add-new filtering excludes convertible opposite-kind entries.
- Add-for-slot already creates and connects a layer in a compound undo action, but it does not initialize the inserted layer's own inputs.
- `GSTStackOps.add_layer` and `GSTUndo.add_layer` leave manifest inputs empty. `GSTCodegen._slot_arg` supplies typed constants for those empty inputs, so top-level add does not currently implement decision `3`'s below default.
- Explicit output selection remains unchanged when a new layer is appended; the approved add behavior requires a compound add/input/output action.
- `GSTCodegen._main_output_line` hardcodes alpha `1.0` for field output, so the current shader ignores every selected transparency mode on that path.
- `GSTUndo.assign_warp` rejects color layers, the inspector hides them, `_stack_needs_luma` does not scan warp references, and `_generator_body_lines` emits warp locals without conversion. All four contradict retained decision `2`.
- The current shared message label is overwritten by codegen resync and cannot maintain separate initiating-control refusal and preview-error lifecycles.
- The recorded editor smoke covers structural undo, stack replacement, preview recovery, and recipe randomization. The final version matrix records `123` test methods and `78` rendered stack checks on Godot `4.4`, `4.6.2`, and `4.7`.

Required implementation verification:

- Verify the native property-editor label and tooltip path with an actual inspector edit and undo on `4.4`, `4.6.2`, and `4.7`; confirm the displayed labels change while serialized parameter keys, generated uniform names, values, and inspector undo remain byte-for-byte compatible.
- Measure the actual plugin rectangle at `1366x768`, including Godot's visible docks, toolbars, and editor scale. Derive preview/editing minimums and the tab-layout breakpoint from control minimum sizes.
- Verify long function names, conversion labels, manifest descriptions, and local error messages remain readable without widening the panel beyond its allocation.
- Build a `20`-layer stack and verify independent list scrolling, stable-ID selection restoration, fixed preview/output placement, and usable source selection.
- Verify every picker purpose preserves its frozen destination, preview visibility, focus return, and cancellation behavior through tab changes and narrow-layout transitions. Force a stale destination through a test seam and verify zero mutation and zero undo entry.
- Verify first layer add; later top-level add; multi-input operator add; source-filter add with legal and illegal immediate-below layers; and add-new-for-input. Each action must initialize the specified inputs, preserve or assign output as specified, and undo/redo in one step.
- Verify exact-kind and both conversion directions in connected input rows, Existing layers, Add new, and warp rows. Conversion labels must match the emitted expression.
- Verify every transparency mode with both color and field outputs. Field output must use the selected alpha expression, and `field + color_alpha` must compile with alpha `1.0` from the approved field-to-color conversion.
- Verify empty stack, first successful preview, codegen failure after success, codegen failure before any success, control refusal, successful retry, and stack replacement. Each message must follow decisions `6` and `29` without clearing unrelated state.
- Verify a new user can choose a recipe, change its effect through the readable native labels, and export without needing shader terminology explained externally.

The warp discrepancy is resolved by the retained automatic-conversion contract in `DESIGN.md` decision `2`: warp remains a field-kind input, but a connected color layer is legal and codegen converts it with `luma()`. Implementation must include color candidates and the persistent `color -> field: luminance` label, remove the color rejection in `GSTUndo.assign_warp`, include color warp references in `_stack_needs_luma`, and wrap each color warp local in `_generator_body_lines`. This is a required compatibility patch with no stack-schema change; the current field-only behavior is not retained.
