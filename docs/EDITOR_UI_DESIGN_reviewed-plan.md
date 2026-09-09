# GoShade Turbo editor UI redesign - Implementation Plan

Source design: `docs/EDITOR_UI_DESIGN_reviewed.md` (`Status: reviewed`).

Conventions read: user-provided `AGENTS.md` instructions, `docs/DESIGN.md`, `docs/PLAN.md`, `docs/EDITOR_SMOKE.md`, `NOW.md`, and `ROADMAP.md`. No repository convention/style/index/architecture files were found. Current code confirms typed GDScript, tabs, double-quoted strings, `snake_case` members/files, `GST`-prefixed class names, `UPPER_SNAKE_CASE` constants, and `@tool` editor scripts. Historical statements in `docs/PLAN.md` about missing code/binaries are superseded by the current tree and final version matrix.

## Summary

Five phases deliver the reviewed design. Phase 1 fixes the visible allocation and sizing failure; later phases change add semantics, property presentation, chooser interactions, and entry/recovery behavior.

The source design owns product behavior. Pixel minimums and layout breakpoints are implementation measurements, not unresolved product decisions.

## Blockers / Open Questions

- None prevent phase 1.
- Commit/push/deploy remain user gates; implementation authorization does not authorize them.
- The original release-tuning work in `docs/PLAN.md` remains separate from this redesign.

## Verification commands and shared phase files

Run engine commands sequentially, including across agents. A named unit run starts its own child process; do not launch another engine command until the wrapper exits.

```powershell
godot --headless --path . --import
godot --headless --path . -s res://tests/run_codegen_tests.gd
godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd
```

- Real editor smoke: set `GST_EDITOR_SMOKE` to the phase selector, then run the resolved binary with `--editor --path .` and a GPU rendering driver.
- Add selectors `ui_layout`, `ui_actions`, `ui_labels`, `ui_picker`, and `ui_complete` to `tests/gst_editor_smoke.gd`; retain existing selectors `4` through `8`.
- Use `Start-Process -WindowStyle Hidden` with redirected stdout/stderr for background engine runs, unless the user requests a visible editor.
- Capture exit codes and error markers; an aborted assertion cannot count as a passing smoke run.
- Select the actual `GoShade Turbo` main-screen tab, wait for container layout, and inspect visible active controls.
- Headless import/unit tests cannot establish preview rendering or native editor usability.
- Baseline reported by the orchestrator: `21` test files, `123` methods, `0` failures on `4.6.2`.
- Existing final matrix records `78` rendered checks on `4.4`, `4.6.2`, and `4.7`.
- `4.4`: `C:/Users/atk67/Downloads/Godot_v4.4-stable_win64.exe/Godot_v4.4-stable_win64.exe`.
- `4.6.2`: resolve the `godot` PATH wrapper to its executable for `Start-Process`.
- `4.7`: `C:/Users/atk67/Documents/godot/Godot_v4.7-stable_win64.exe`.

**The following shared files are part of every phase's Files scope:**

- `tests/run_codegen_tests.gd`, `tests/gst_test_runner.gd`, `tests/gst_test_base.gd` (existing unit entrypoints/helpers; preserve automatic discovery and error detection).
- `tests/gst_editor_smoke.gd` and `addons/goshade_turbo/plugin.gd` (existing editor entrypoint/dispatch).
- `tests/run_render_checks.gd`, `tests/gst_render_assert.gd`, `tests/gst_shader_compile.gd` (existing render entrypoint/helpers; preserve their checks).
- Existing discovered suite: `tests/test_codegen_color.gd`, `tests/test_codegen_fieldop.gd`, `tests/test_codegen_generator.gd`, `tests/test_combinations.gd`, `tests/test_coord_space.gd`, `tests/test_filter_input_refusal.gd`, `tests/test_header_roundtrip.gd`, `tests/test_include_walk.gd`, `tests/test_layer_identity.gd`, `tests/test_library_index.gd`, `tests/test_material_sync.gd`, `tests/test_output_block.gd`, `tests/test_overwrite_check.gd`, `tests/test_randomize_range.gd`, `tests/test_recipe_roundtrip.gd`, `tests/test_slot_conversion.gd`, `tests/test_solo_output.gd`, `tests/test_stack_io.gd`, `tests/test_stack_ops.gd`, `tests/test_time_emission.gd`, `tests/test_uniform_names.gd` (run unchanged unless a phase explicitly changes the tested contract).
- `docs/EDITOR_UI_DESIGN_reviewed-plan.md`, `docs/EDITOR_SMOKE.md`, `docs/RUNTIME_VERIFICATION_QUEUE.md` (phase status and measured evidence, owned by orchestrator).
- `NOW.md`, `.now/state.json`, `.now/active-thread.json`, `.now/review-log.jsonl`, `.now/last-session.md`, `.now/branches/main.md`, `.now/branches/main.head`, `SHIPPED.md`, `ROADMAP.md` (orchestrator state; use the existing state workflow and current branch equivalents).
- Corresponding `.gd.uid` sidecars for scripts created or changed in the phase; asset `.import` sidecars only if intentionally needed.
- `project.godot` only to restore incidental editor `config/features` churn to the minimum `4.4`; no feature or renderer change is planned.

Shared scope is permission to maintain integration and verification, not a requirement to rewrite every listed file. No phase may weaken an existing smoke assertion to avoid a failure. When an approved behavior changes, update that assertion to the new behavior and preserve its original undo/render/serialization coverage.

## Phase 1: Full-height layout and usable preview allocation

**Status:** committed (2026-09-08)

**Goal:** Make the active editor fill the main-screen rectangle with a measured default `60%` editing / `40%` preview split and fixed output controls beneath the preview.

**Files:**

- Shared phase files above.
- `addons/goshade_turbo/ui/gst_main_panel.tscn`, `addons/goshade_turbo/ui/gst_main_panel.gd`.
- `addons/goshade_turbo/ui/gst_stack_list.tscn`, `addons/goshade_turbo/ui/gst_stack_list.gd`.
- `addons/goshade_turbo/ui/gst_inspector_column.gd`.
- `addons/goshade_turbo/ui/gst_output_block.tscn`, `addons/goshade_turbo/ui/gst_output_block.gd`.
- `addons/goshade_turbo/ui/gst_preview.tscn`, `addons/goshade_turbo/ui/gst_preview.gd`.
- `tests/gst_editor_ui_layout_smoke.gd` (new, dispatched by `ui_layout`).

**Implementation:**

- Set root horizontal and vertical expand/fill flags before measuring. Current root vertical flags are `1`; built-in main-screen siblings use `3`.
- Make the outer `HSplitContainer` divide editing from preview; default child stretch ratios are `1.5:1.0`.
- Put Layers and Layer settings in an inner editing split. Use headings and visible separators for Inputs, Parameters, and Position and movement.
- Keep the native inspectors and current controls functional; readable manifest labels and replacement pickers belong to later phases.
- Move Final output below the preview into vertical color/transparency rows; update its script base if the root container type changes.
- Group New/Open/Save As/Reopen Shader under File to remove the current toolbar minimum-width constraint; preserve handlers, Save, Export, Recipes, and recipe-only Randomize.
- Constrain long option captions and wrap messages; disable longest-item minimum sizing where it forces allocation overflow. Preserve existing selected-text test helpers and semantic values.
- Derive minimum widths from actual control minimums at the active editor scale. Record panel, editing, preview, and preview image rectangles after Godot docks/toolbars consume their space.
- Switch the inner split to Layers / Layer settings tabs before editing columns violate their minimums. Reparent the same wrappers rather than duplicate inspectors or state.
- Persist divider ratios, narrow tab selection, and collapsible section state with editor-only project metadata; clamp restored values to current measured bounds.
- Keep stack rows fixed-height, retain function/kind/stable ID, and restore selection plus scroll anchor by stable ID.
- Keep layer scrolling independent from settings, preview, and Final output. Do not hardcode a large minimum width that makes the entire plugin exceed its host rectangle.

**Verification:**

- Run import and the named unit suite; run `ui_layout` plus existing editor smoke selectors `4` through `8` sequentially on `4.6.2`.
- At `1366x768`, select the live panel with surrounding Godot UI present; record editor scale, host rectangle, root rectangle, split widths, preview image width/height, and final-output rectangle.
- Assert the root consumes available vertical allocation; default editing/preview widths are within one divider width plus rounding of `60/40` when minimums permit.
- Assert visible preview image dimensions exceed the measured minimums and the recorded collapsed-height failure (`488x74`) is absent; compare against the same-size active-panel baseline where available.
- Drag both splitters; assert bounds and persistent restore. Resize below and above the computed tab breakpoint; assert no host overflow, retained selection, one live inspector, and separate preview allocation.
- Load `20` layers, select by stable ID, scroll and rebuild/reorder; assert fixed rows, restored selection/anchor, and unchanged preview/output rectangles during list scrolling.
- Exercise long function captions and refusal messages; assert their controls remain inside assigned columns.
- Confirm a GPU-rendered preview still changes through the existing native parameter edit path.

**Exit criteria:** The visible active editor passes the geometry and scrolling checks, records measured minimums/breakpoint in `docs/EDITOR_SMOKE.md`, and preserves current editing behavior.

**Blockers:** None. New picker behavior, input defaults, warp conversion, and output-alpha compatibility are explicitly outside this phase.

**Wires:** Existing plugin main-screen installation, toolbar handlers, splitters, stack list, inspectors, and preview remain live in the new container hierarchy.

## Phase 2: Atomic layer additions and retained conversion behavior

**Status:** committed (2026-09-08)

**Goal:** Establish add/input/output and conversion semantics before the new chooser exposes them.

**Files:**

- Shared phase files above.
- `addons/goshade_turbo/model/gst_stack_ops.gd`.
- `addons/goshade_turbo/ui/gst_undo.gd`, `addons/goshade_turbo/ui/gst_stack_list.gd`, `addons/goshade_turbo/ui/gst_inspector_column.gd`, `addons/goshade_turbo/ui/gst_main_panel.gd`.
- `addons/goshade_turbo/codegen/gst_codegen.gd`.
- `tests/test_stack_ops.gd`, `tests/test_slot_conversion.gd`, `tests/test_filter_input_refusal.gd`, `tests/test_output_block.gd`, `tests/test_codegen_generator.gd`.
- `tests/gst_editor_ui_actions_smoke.gd` (new, dispatched by `ui_actions`).

**Implementation:**

- Add explicit UI add operations that initialize manifest inputs from the immediate lower layer when legal and assign top-level additions to `output_color`.
- Keep low-level fixture/resource construction APIs usable without changing historical unset-input/output fallback behavior.
- First addition assigns its stable ID; later additions assign the new top layer. Optional warp inputs stay empty.
- Source-sampling inputs initialize only from immediate-below `source/texture` or `source/screen`; other manifest kind differences use existing conversion rules.
- Add-for-input inserts immediately below its captured consumer, initializes the inserted layer's own inputs, wires the destination, and preserves output.
- Record each complete operation in one existing `EditorUndoRedoManager` action with stable history context and exact undo/redo restoration.
- Permit color warp references, include them in `_stack_needs_luma`, and emit converted warp locals in `_generator_body_lines`.
- Make field output use `_alpha_expr`; `field + color_alpha` produces alpha `1.0` through the existing field-to-color contract.

**Verification:**

- Run import, named unit suite, GPU rendered checks, `ui_actions`, and all existing editor smoke selectors.
- Cover first/top-level multi-input additions, legal/illegal immediate-below source filters, add-for-input, and one-step undo/redo of layer/input/output state.
- Assert refused operations leave resources and history count unchanged.
- Cover exact-kind and both conversion directions, including color warp shader compilation and luma emission.
- Cover every transparency mode for field/color outputs, including field-layer alpha and unset automatic mode.
- Assert existing saved empty inputs/outputs retain prior fallback behavior; retain stable IDs, uniform names, recipe/header roundtrips, and fixture APIs.

**Exit criteria:** UI add paths implement decisions `3`, `17`, and `19`; all retained conversion and transparency contracts compile and undo correctly.

**Blockers:** None.

**Wires:** Existing Add Layer and add-for-input handlers call the compound operations; existing warp controls use the corrected eligibility and codegen path.

## Phase 3: Function-specific labels through native property editors

**Status:** committed (2026-09-08)

**Goal:** Present readable labels and descriptions without replacing native editors or changing resource/uniform keys.

**Files:**

- Shared phase files above.
- `addons/goshade_turbo/model/gst_manifest_entry.gd`, `addons/goshade_turbo/model/gst_layer.gd`, `addons/goshade_turbo/model/gst_coord_block.gd`.
- `addons/goshade_turbo/ui/gst_inspector_column.gd`.
- `addons/goshade_turbo/ui/gst_inspector_plugin.gd` (new, registered/unregistered by `plugin.gd`).
- Every shipped `addons/goshade_turbo/library/**/*.tres` manifest with inputs or params, hand-edited only: `color/{add,brightness_contrast,fill,gradient_map,hue_shift,mix,multiply,overlay,palette,posterize,saturation,screen,soft_light}.tres`; `fieldops/{abs,add,alpha,fract,invert,max,min,mix,multiply,pow,remap,smoothstep}.tres`; `filter/{box_blur,chromatic_split,dither,outline,pixelate}.tres`; `generative/{cellular_edges,checker,fbm,hash,linear_gradient,perlin,radial_gradient,snoise,stripes,value_noise,voronoi}.tres`; `sdf/{box,circle,intersect,line,polygon,ring,rounded_box,smooth_union,star,subtract,union}.tres`. Entries without dictionaries need no fabricated metadata.
- `tests/test_library_index.gd`, `tests/test_uniform_names.gd`, `tests/test_stack_io.gd`, `tests/test_header_roundtrip.gd`.
- `tests/gst_editor_ui_labels_smoke.gd` (new, dispatched by `ui_labels`).

**Implementation:**

- Add nonempty function-specific `label` and `description` to every shipped input and parameter dictionary; leave identifier, type, ranges, defaults, code, attribution, and function name intact.
- Implement `EditorInspectorPlugin._parse_property` with `EditorInspector.instantiate_property_editor` using original paths/hints, then `add_property_editor(..., false, label)` and manifest tooltips.
- Keep parameter writes on the existing `GSTLayer` property and coordinate writes on `GSTCoordBlock`; preserve native inspector undo and material synchronization.
- Hide model bookkeeping from normal editing; expose coordinate controls with Position, Rotation, Movement speed, and horizontal/vertical distortion labels in their section.
- Recompute measured layout minimums after native labels are installed and preserve phase 1's bounds/tab behavior.

**Verification:**

- Run import and named unit suite; verify every shipped dictionary has label/description metadata.
- Run `ui_labels` on `4.4`, `4.6.2`, and `4.7`; perform an actual native property edit and undo, verify the displayed widget value, label, tooltip, serialized keys, and uniform names.
- Compare pre/post-label resource/header keys and unchanged-value shader text byte-for-byte; normal value edits must only change their intended values.
- Run existing native inspector/randomize smoke and `ui_layout` after label changes.

**Exit criteria:** All shipped inputs/params have specific readable metadata; minimum-version native widgets, undo, and serialization compatibility are proven.

**Blockers:** None; the required inspector APIs were verified against Godot `4.4` documentation.

**Wires:** Plugin registration activates labels for the live Layer settings inspectors; manifest input labels appear on their initiating controls.

## Phase 4: Embedded contextual choosers and local refusal state

**Status:** committed (2026-09-08)

**Goal:** Replace long menus with one editing-area chooser that preserves preview visibility and immutable destinations.

**Files:**

- Shared phase files above.
- `addons/goshade_turbo/ui/gst_picker.tscn`, `addons/goshade_turbo/ui/gst_picker.gd`.
- `addons/goshade_turbo/ui/gst_main_panel.tscn`, `addons/goshade_turbo/ui/gst_main_panel.gd`.
- `addons/goshade_turbo/ui/gst_stack_list.tscn`, `addons/goshade_turbo/ui/gst_stack_list.gd`.
- `addons/goshade_turbo/ui/gst_inspector_column.gd`.
- `addons/goshade_turbo/ui/gst_output_block.tscn`, `addons/goshade_turbo/ui/gst_output_block.gd`.
- `tests/gst_editor_ui_picker_smoke.gd` (new, dispatched by `ui_picker`).
- `addons/goshade_turbo/ui/gst_undo.gd`, `tests/gst_editor_ui_actions_smoke.gd`: extend atomic add-and-wire to coordinate distortion destinations, required by the Add new warp chooser.

**Implementation:**

- Replace the popup with an editing-area full-rect `PanelContainer` overlay using mouse STOP, search, context heading, and multi-column function/kind/description results.
- Capture stack instance, purpose, stable destination layer ID, and input/warp name at open; resolve and revalidate that immutable destination at activation.
- Route Add Layer, input/warp Existing layers and Add new, Recipes, output color, and Transparency through the chooser.
- Restrict empty-stack additions to zero-input entries; preserve taxonomy, earlier-layer legality, source-only rules, optional empty choices, and automatic output choices.
- Match name and description case-insensitively; hide taxonomy folders with no matching selectable result.
- Show persistent neutral conversion labels on connected rows and both candidate tabs, including color-to-field warp candidates.
- Click or Enter applies immediately; refusal keeps the chooser open. Escape cancels and returns focus; tab changes retain query and destination.
- Block mutating toolbar commands and keyboard handlers while open; retain Save, Export, preview controls, and rendering.
- Store refusal messages by initiating control/destination independently of codegen messages; clear only on valid edit of that control, destination removal, or stack installation.
- Use the approved Transparency names and automatic effective-mode labels; preserve `field + color_alpha` as valid.

**Verification:**

- Run import, named unit suite, `ui_picker`, `ui_actions`, `ui_layout`, and existing editor smoke selectors.
- Drive every chooser from its real initiating control; assert the overlay stays in the editing rectangle and preview pixels continue rendering.
- Exercise click, arrows, Enter, Escape, focus return, query retention, taxonomy filtering, description search (`noise` finds `fbm`), and narrow-layout transitions.
- Verify exact-kind/conversion/source-only candidates in both tabs and their emitted conversion expressions.
- Force stack/destination staleness through a test seam; assert zero mutation, unchanged history count, retained destination, and local refusal.
- Attempt each blocked command through both button and handler/shortcut entrypoints; assert Save/Export and preview controls remain available.
- Verify first-library filtering from every empty-stack add path, plus output automatic choices and every Transparency choice.

**Exit criteria:** All chooser purposes are reachable from the live editor, preserve preview and destination, and maintain local refusal state without invalid mutations.

**Blockers:** None; relies on phase 2 semantics and phase 3 metadata.

**Wires:** Live stack, input, warp, recipe, and output controls all invoke the embedded chooser and phase 2 mutations.

## Phase 5: Entry flow, preview recovery, and complete editor verification

**Status:** committed (2026-09-09)

**Goal:** Complete the first-session and diagnostic-preview flows and prove the approved editor end to end.

**Files:**

- Shared phase files above.
- `addons/goshade_turbo/ui/gst_main_panel.tscn`, `addons/goshade_turbo/ui/gst_main_panel.gd`.
- `addons/goshade_turbo/ui/gst_inspector_column.gd`, `addons/goshade_turbo/ui/gst_stack_list.gd`.
- `addons/goshade_turbo/ui/gst_preview.gd`, `addons/goshade_turbo/ui/gst_preview.tscn`, `addons/goshade_turbo/ui/gst_material_sync.gd`.
- `tests/test_material_sync.gd`, `tests/test_solo_output.gd`.
- `tests/gst_editor_ui_complete_smoke.gd` (new, dispatched by `ui_complete`).
- `addons/goshade_turbo/ui/gst_picker.gd`: final scaled verification exposed conversion clipping; wrap the existing kind text to its measured column width.
- `tests/gst_editor_ui_layout_smoke.gd`, `tests/gst_editor_ui_actions_smoke.gd`, `tests/gst_editor_ui_labels_smoke.gd`, `tests/gst_editor_ui_picker_smoke.gd` (final integration coverage).

**Implementation:**

- Show recipes, Open, and Create Empty Stack for the initial unsaved empty installation; show No effect yet above its preview.
- Create Empty Stack and File > New enter ordinary editing and immediately open the first library; cancellation leaves Add Layer available.
- Keep start-screen dismissal/navigation outside undo; recipe/open replacement remains undoable, and undo returns to the ordinary empty editor.
- Move individual-layer preview to the selected layer's secondary menu; remove Solo from primary controls and show function/ID plus Return to finished effect when active.
- Retain preview target/image controls and text coordinate suggestion; diagnostic preview never changes stack output or export text.
- Separate preview errors from control refusals; empty stacks are not codegen failures.
- Reset successful-material cache on stack installation; retain only the current installation's previous successful render on later failure and label it Showing last successful preview.
- Preserve error lifetimes through successful unrelated edits/codegen, retry, undo/redo, and replacement.

**Verification:**

- Run import, named unit suite, rendered checks, existing editor smoke selectors, and all new UI selectors sequentially on `4.4`, `4.6.2`, and `4.7`.
- Cover recipe/open/empty entry, cancelled library, one-step replacement undo, and no start-screen resurrection.
- Cover empty, first success, failure after success, failure before success, local refusal, valid retry, unrelated success, and stack replacement; assert independent messages and cache identity.
- Verify native parameter and coordinate edit/undo, recipe Randomize/undo, selected-layer preview/return, export, and reopen.
- Repeat `1366x768`, scaled/narrow layout, long captions/conversions/errors, picker transitions, persisted layout, and `20`-layer independent scrolling against active visible geometry.
- Perform the beginner task with the real controls: choose a recipe, change its effect through readable labels, export a self-contained shader, and compile/reopen it.
- Record screenshots/rectangles and version results in `docs/EDITOR_SMOKE.md`; mark unavailable runtime evidence explicitly in `docs/RUNTIME_VERIFICATION_QUEUE.md`, never as passed.

**Exit criteria:** Every reviewed decision has runtime or automated evidence; no required check remains unrun, failed, or replaced by hidden-node measurements.

**Blockers:** None currently known; missing required runtime access would block final completion rather than phase 1 implementation.

**Wires:** Initial panel navigation, File > New, recipe/open handlers, secondary preview action, and material synchronization implement the completed flow.

## Cross-cutting concerns

- **Undo and shared editor state:** Keep `GSTUndo` and stack replacement on existing stable history contexts in phases 2/4/5. Native property editors retain their own undo integration. Navigation, preview state, layout, and picker state never register stack edits. Undo/redo restores compound changes exactly; no new autoload is planned.
- **Resources and manifests:** Phase 3 adds editor metadata dictionaries only. Hand-edit manifests; never re-save library resources through `ResourceSaver` or another Godot version. Stack `.tres`, embedded JSON header, parameter names, function IDs, stable IDs, and uniform names retain their formats. Existing empty inputs/outputs are not migrated. Rollback requires no resource migration.
- **Code generation:** Phase 2 intentionally changes field-output transparency and color-warp expressions to the retained design contract. Export and preview continue using one generator; run shader compilation and render checks. Existing exports are not bulk rewritten; regeneration happens only through normal export. Record this intended behavior delta separately from phase 3's byte-compatible labels.
- **Public UI helpers/signals:** Preserve existing fixture and introspection APIs where possible. New chooser requests carry destination identity, and refusal presentation needs control identity. Update all live callers and smoke helpers in the same phase; do not retain unreachable duplicate product controls merely for tests. Document changed UI assertions while preserving original coverage.
- **Inspector plugin lifecycle:** Phase 3 registers one plugin and removes it on teardown. Intercept only GST properties; create standard editors without recursion and preserve original hint/range/path metadata. Other Godot inspectors must remain unaffected.
- **Shared container sizing:** Phase 1 changes root/output container types and hierarchy. Maintain scene script base compatibility and unique-name references. Later labels/pickers must respect measured minimums and tab fallback; re-run active geometry after each related phase.
- **Editor metadata:** Phase 1 stores bounded ratios, tabs, and collapsed state in editor-only project metadata. Metadata changes neither shader/resource content nor undo. Missing/corrupt settings fall back to approved defaults; deleting metadata resets layout safely.
- **Preview cache identity:** Phase 5 scopes last-success state to each active installation, including undo/redo stack replacement. A previous stack's material cannot appear as recovery for the next stack.
- **Engine-generated files:** Include intended `.gd.uid` sidecars after import; do not commit `.godot` caches, temporary smoke logs, or incidental manifest/recipe rewrites. Restore only engine-introduced `project.godot` feature-version churn, preserving unrelated user changes.
- **Pipeline and release state:** Orchestrator updates phase status and `.now` state through existing workflow. No implementation phase commits, pushes, deploys, or marks the original release-tuning phase shipped without explicit authorization.
