# Multiple shader tabs: implementation plan

Source design: `docs/SHADER_TABS_reviewed.md`.

Conventions read: user-provided `AGENTS.md` instructions, `docs/DESIGN.md`, `docs/EDITOR_UI_DESIGN_reviewed.md`, `NOW.md`, and relevant evidence in `docs/EDITOR_SMOKE.md`. No repository convention/style/index/architecture file was found. Implementation conventions are inferred from the existing typed GDScript, `GST` classes, `GSTStackIO` result dictionaries, native editor controls, and editor-smoke dispatch.

## Summary

Build session-scoped shader documents with one Godot `UndoRedo` instance per document, native property controls, tabs, document-bound file operations, close protection, and confirmed-shutdown recovery in `8` phases. Phase `1` verifies the replacement undo route and shutdown prerequisites before production changes.

Source files per phase: `1: 0`, `2: 5`, `3: 2`, `4: 5`, `5: 2`, `6: 2`, `7: 4`, `8: 0`. Tests, evidence documents, fixtures, and generated `.uid` companions are excluded. Listed existing test files may require fixture adaptation; listing them does not require unrelated edits.

Verified integration points: `plugin.gd` injects the shared editor manager; `GSTUndo` uses its method-registration overloads and a history anchor; `GSTInspectorColumn` creates two `EditorInspector` containers and watches shared histories. `GSTMainPanel` owns the current stack, file dialogs, Randomize, and preview refresh. Existing tests read those histories and inspector getters, so their adapters change with phase `2`.

## Blockers / open questions

- No user decisions block phase `1`. The user approved per-document `UndoRedo`; `docs/DESIGN.md` decision `20` supersedes the earlier shared-manager contract and embedded inspector routing.
- Historical result: private `EditorUndoRedoManager` construction failed on Godot `4.4` because the class is abstract. Preserve `.now/tabs-validation/evidence/tabs-proof-4.4.stdout.log` and `import-4.4.stderr.log`; neither proves any later check ran.
- Replacement proof `r2` ended with `TABS_PROOF SUMMARY pass=8 fail=1` in `.now/tabs-validation/evidence/tabs-proof-r2q-4.4.stdout.log`. Standalone histories, structural isolation, native vector/RGB values, shortcuts/host-scene isolation, resource/scene retention, and shutdown-status assertions passed.
- Its failed float assertion required `changing=true`; actual float and vector input emitted `changing=false`. These value/isolation passes do not prove gesture grouping or complete phase `1`.
- Phase `1` must prove decision `7`'s public numeric gesture boundaries, native color final emission, and forced-finish ordering on Godot `4.4`.
- Actual confirmed Save and Quit and callback-written recovery remain untested technical gates. Callback-status assertions do not establish shutdown persistence.
- Any failed mechanism returns to design review. Shared shader history, private editor-manager construction, dummy scenes, fabricated resource paths, unbound methods, custom sliders, and editor-internal patches are forbidden fallbacks.
- Local recovery follows reviewed decision `10`; the orchestrator must incorporate any later user steering before dependent implementation.
- Every commit, push, or deploy requires existing explicit user authorization. This plan grants none.

## Verification commands and ownership

- Minimum engine: `C:/Users/atk67/Downloads/Godot_v4.4-stable_win64.exe/Godot_v4.4-stable_win64.exe`.
- Other engines: `C:/Users/atk67/Desktop/Godot_v4.6.2-stable_win64.exe` and `C:/Users/atk67/Documents/godot/Godot_v4.7-stable_win64.exe`.
- Import new classes with `<godot> --headless --path <isolated-project> --import`.
- Unit command: `<godot> --headless --path <isolated-project> -s res://tests/run_codegen_tests.gd`.
- Editor command: set `GST_EDITOR_SMOKE=<selector>`, then run `<godot> --editor --path <isolated-project> --rendering-method gl_compatibility`.
- Render command: `<godot> --path <isolated-project> --rendering-method gl_compatibility -s res://tests/run_render_checks.gd`.
- For the final Forward+ matrix, replace `--rendering-method gl_compatibility` with `--rendering-method forward_plus` in render and motion commands.
- Motion command: `<godot> --path <isolated-project> --rendering-method gl_compatibility -s res://tests/run_recipe_motion_checks.gd`.
- Use existing smoke dispatch in `tests/gst_editor_smoke.gd`, loaded by the real plugin. New selectors below load their named test scripts.
- Record command, version, renderer, exit code, assertion count, stderr, and screenshot paths in `docs/EDITOR_SMOKE.md` for each phase.
- Run GPU/editor checks in a real editor environment; a headless parse pass cannot prove native controls or rendering.
- Expected-error fixtures must identify the exact expected diagnostic. Unexpected script/engine errors fail verification even with exit `0`.
- The documented Godot `4.4.0` first-import progress-dialog diagnostic is a separate engine limitation; do not label that import error-free.
- Preserve the user's `weird1.tres`, `weird2.tres`, existing `glow.png.import` changes, and running editor. Use isolated test project/settings/recovery paths and stop only owned processes.
- Verified prior unit baseline is `145` methods. `NOW.md` expects `79` rendered stacks after the Clouds move; that count remains unverified until run. Record actual discovered counts without dropping cases.

## Phase 1: Prove the minimum-version editor mechanisms

**Status:** committed (2026-09-10)

Round-1 review verdict `FAIL` with six required fixes (`.gantry/review-round.json`). The fixes are written in the proof and shutdown fixture and verified on `2026-09-10`: `r5b` passed `17` checks through confirmed Save and Quit (exit `0`), `r5c` passed `3` fresh-open checks (exit `0`), evidence in `docs/EDITOR_SMOKE.md` "Shader tabs phase 1 review round 1 fixes verified". One r5 defect was corrected during verification: the forced color-popup close now commits pending hex text before hiding, per `ColorPicker::_html_focus_exit`. Production tab implementation has not started.

**Goal:** Establish that the reviewed native editing and shutdown mechanisms work on Godot `4.4` before changing production behavior.

**Files:**

- `tests/gst_editor_smoke.gd` (dispatch only).
- `tests/gst_editor_document_proof.gd` (revise the partially verified replacement proof).
- `tests/fixtures/shader_tabs_host.tscn` (existing small host scene).
- `tests/fixtures/shader_tabs_shutdown_plugin.gd` (revise existing callback probe).
- `tests/fixtures/shader_tabs_shutdown_plugin.cfg` (isolated test plugin fixture).
- `tests/fixtures/shader_tabs_proof_target.gd` (serializable history-owning proof resource for the Save As reload check; added at review round 4 because a script-local inner class cannot be reloaded through `ResourceLoader`).
- `docs/EDITOR_SMOKE.md` (proof evidence).

**Implementation:**

- Revise `tabs_proof` to construct two `UndoRedo.new()` instances with stable owning document targets. Remove private-manager construction and fixed/global-history routing from shader proof actions.
- Use the standalone API: `add_do_method(callable)` and `add_undo_method(callable)` with bound arguments. Do not retain the manager's object/method/varargs overload or custom history context in `create_action`.
- Mount standalone native float, vector, and RGB color `EditorProperty` controls through `instantiate_property_editor`, `set_object_and_property`, and `property_changed`.
- Correct `_on_bound_property_changed` to receive all four emitted arguments `(property, value, field, changing)` before bound context arguments. Validate component-field changes against the bound property and preserve other vector components.
- Create rows in plugin-owned containers, outside any `EditorInspector`; preserve labels, tooltips, and native Color-to-Vector3 storage.
- Keep `property_changed` authoritative for values; never require numeric rows to emit `changing=true`.
- Discover each numeric row's public `EditorSpinSlider` descendants and connect `grabbed`, `ungrabbed`, `value_focus_entered`, and `value_focus_exited`.
- Capture the exact bound pre-gesture value on the first begin signal; another begin during that interaction retains it. Apply every value live to the immutable document/object/property target.
- Finish a drag on `ungrabbed`. Value entry after a non-drag grab continues that interaction; finish it on `value_focus_exited`.
- Finish with one mutation-first action only when final content differs from the captured value. The next begin captures a new value; repeated gestures must remain separate actions.
- Outside a native boundary, the first `changing=true` starts a gesture and the following `changing=false` finishes it; an isolated `changing=false` is one discrete action.
- Preserve native `EditorPropertyColor` live popup preview and its final `property_changed` emission on close.
- Before rebind, Save/Save As, shutdown save, or undo/redo, finish numeric gestures and close active native color popups. Continue only after the final color change reaches its original immutable target; never perform the operation with a pending native edit.
- Exercise real float and vector-component drags with at least `2` distinct emitted value changes within each drag; each must undo once from final to first value and redo to final value.
- Drive the same control through `2` later gestures; prove each separately restores its own first value. Record action/history positions and intermediate values, not only pointer motion counts.
- Exercise real numeric text focus, including non-drag grab followed by value entry, and native RGB popup close; each interaction finishes once. Synthetic signal emission alone cannot pass the proof.
- Force finish during numeric and color edits before rebind, Save/Save As, shutdown save, and focused undo/redo. Assert final delivery precedes the operation and no late event mutates another target.
- Register one structural edit and one real continuous native property edit in each document history. Prove path-bearing resources, Save As, and scene switches retain both histories.
- Retain the passing isolation/value assertions; verify exact first/final values, one action per gesture, vector fields, Color-to-Vector3 storage, and property refresh after external writes.
- Send Ctrl+Z/Ctrl+Shift+Z with focus in GoShade, including a native property popup; assert the active document alone changes and its inactive history survives.
- Give the host scene its own editor action through the real editor manager, then invoke Undo outside GoShade. Compare scene and both shader states/history positions before and after every action; never clear the host history.
- In the isolated test project, open Godot's real quit confirmation with dirty named and untitled proof documents. Capture the listed unsaved status, select Save and Quit, and record `_save_external_data` delivery through process exit.
- Probe nonempty `for_scene` and actually close a host scene; shader documents must remain session-owned. Direct callback calls test return values only.
- Write a self-contained `GSTStack` plus metadata synchronously inside the shutdown callback for untitled or failed-path documents. A payload prepared before quitting cannot establish callback persistence.
- Reopen the isolated project in a fresh editor and compare saved/recovered content with its pre-quit snapshots. Cover mixed named-save success/failure and forced recovery-write failure with exact attempted paths and expected errors.
- `EditorInterface.restart_editor(true)` alone cannot prove confirmed Save and Quit. If confirmation must be operated manually, record that step and its screenshots; do not mark the gate passed without it.

**Verification:** Run `tabs_proof` on `4.4` and the isolated shutdown fixture through actual Save and Quit and fresh project open. Record ordered public gesture signals, complete property arguments/values, per-gesture action/history positions, forced-finish ordering, confirmation screenshots, callback-written recovery content, and process logs. Float and vector drags each require more than `1` actual value change and exactly `1` undo action; repeated gestures require separate actions. Include real focus and popup paths plus all prior isolation checks. Keep fixture activation/configuration in the isolated project.

**Exit criteria:** Two `UndoRedo` histories preserve independent structural/property undo and leave host scene history intact. Actual multi-change float/vector drags each undo once; repeated gestures undo separately; text focus and RGB popup close finish once. Forced finish delivers the original target's final change before rebind/save/undo/redo. Actual confirmed shutdown writes readable recovery content; forced failure reports its path and the void callback's inability to veto shutdown. Any unexecuted check keeps phase `1` pending.

**Blockers:** Any failed proof stops subsequent phases and returns the failure to design review.

## Phase 2: Route stack edits through standalone UndoRedo

**Status:** pending

**Goal:** Route structural and native property edits through the standalone history mechanism proved in phase `1`.

**Files:**

- `addons/goshade_turbo/plugin.gd`.
- `addons/goshade_turbo/ui/gst_main_panel.gd`.
- `addons/goshade_turbo/ui/gst_undo.gd`.
- `addons/goshade_turbo/ui/gst_inspector_column.gd`.
- `addons/goshade_turbo/ui/gst_inspector_plugin.gd` (adapt/remove obsolete registration support).
- `tests/gst_editor_smoke.gd`.
- `tests/gst_editor_ui_labels_smoke.gd`.
- `tests/gst_editor_ui_layout_smoke.gd`.
- `tests/gst_editor_ui_actions_smoke.gd`.
- `tests/gst_editor_ui_picker_smoke.gd`.
- `tests/gst_editor_ui_complete_smoke.gd`.
- `tests/gst_editor_native_undo_smoke.gd` (new).
- `docs/EDITOR_SMOKE.md`.

**Implementation:**

- Create one panel-owned `UndoRedo` for the interim single-document state; phase `3` transfers history ownership into each document.
- Remove live dependency on `EditorInterface.get_editor_undo_redo()` and plugin `get_undo_redo()` for GoShade actions.
- Adapt `GSTUndo` to `UndoRedo` and its Callable-based method registration; remove `_history_context` and editor-manager history lookup. Preserve mutation-first `commit_action(false)` and exactly one initial refresh where already used.
- Route structural edits, coord-space edits, Randomize, and native property edits through `GSTUndo` into that history. Retain compound actions and same-instance restoration.
- Build parameter/coordinate rows from existing property metadata; retain original property names, ranges, labels, tooltips, RGB color adapter, and contextual explanations.
- Bind rows to immutable edited-object/property targets; refresh native widgets and control context after initial writes, undo/redo, and Randomize.
- Handle `(property, value, field, changing)` before bound context arguments using phase `1` evidence; reject stale bindings and retain complete vector/color values.
- Preserve absent parameter keys when undo restores an implicit default, because the dirty fingerprint includes serialized content.
- Implement phase `1`'s public `EditorSpinSlider` descendant connections: `grabbed`, `ungrabbed`, `value_focus_entered`, and `value_focus_exited`.
- First begin captures the exact pre-gesture value; repeated begin retains it. Apply each authoritative `property_changed` value live to the immutable document/object/property target.
- Finish drag on `ungrabbed`; retain a non-drag grab's original value through subsequent value entry and finish on `value_focus_exited`.
- Register one mutation-first action only when final content differs; reset gesture state so the next gesture captures a new original value.
- Use `changing=true`/final `changing=false` as fallback boundaries only outside an active native boundary; an isolated `changing=false` remains one discrete action.
- Preserve native color popup live preview and final property emission. Before rebind, Save/Save As, shutdown save, or undo/redo, finish numeric gestures and close color popups; continue only after final delivery to the original target.
- Preserve native presentation, read-only explanations, focus restoration, and refresh when replacing embedded inspectors with standalone rows.
- Scope keyboard undo/redo to GoShade focus, including native property popup ownership; preserve scene Undo outside the panel and picker modality.
- Replace test seams typed as `EditorInspector` with native-row container/property seams. Remove throwaway shared-history inspector fixtures used to simulate GoShade edits.
- Migrate direct `GSTUndo.new(...)` fixtures, panel history getters, Randomize registration, and helper property-edit calls together. Retain scene-manager use only for the separate host-scene assertions.

**Verification:** Add selector `tabs_native` for standalone routing, actual multi-change float/vector drags with one action each, repeated gestures with separate actions, real numeric focus/non-drag value entry, and RGB popup finalization. Assert no-op gestures add no action and forced finish precedes rebind, Save/Save As, shutdown save, and focused undo/redo. Cover Color center, implicit defaults, focus restoration, stale-target rejection, and host-scene isolation. Run it on `4.4`; run existing selectors `4`, `8`, `ui_labels`, `ui_layout`, `ui_actions`, `ui_picker`, and `ui_complete` on `4.6.2` after adapting their history/widget access.

**Exit criteria:** Every live GoShade stack mutation registers through `GSTUndo` into its standalone `UndoRedo`; native controls preserve displayed/stored/material values across edit/undo/redo. No shared-history watcher or embedded `EditorInspector` remains in the GoShade property column.

**Blockers:** Phase `1` must pass. Failed native grouping or scene isolation returns to design review.

**Wires:** `plugin.gd` initializes the panel; `GSTInspectorColumn` property signals and toolbar/structural handlers invoke `GSTUndo`.

## Phase 3: Add runtime document ownership

**Status:** pending

**Goal:** Make each open shader own its content, private history, baseline, and editing state independently.

**Files:**

- `addons/goshade_turbo/ui/gst_document.gd` (new).
- `addons/goshade_turbo/ui/gst_main_panel.gd`.
- `tests/gst_editor_documents_smoke.gd` (new).
- `tests/gst_editor_smoke.gd`.
- `tests/gst_editor_ui_actions_smoke.gd`.
- `tests/gst_editor_ui_picker_smoke.gd`.
- `tests/gst_editor_ui_complete_smoke.gd`.
- `tests/gst_editor_ui_labels_smoke.gd`.
- `docs/EDITOR_SMOKE.md`.

**Implementation:**

- Store stable session identity, independently owned stack/nested resources, one `UndoRedo` instance and its `GSTUndo` adapter, save path, origin/recipe state, and selected stable layer ID in `GSTDocument`.
- Store document-specific preview preset/image/solo state and material-sync/error state; retain shared layout metadata at panel scope.
- Compute a deterministic content fingerprint from the existing serialized stack representation. Include `next_id` and raw parameter-key presence; exclude paths, layout, selection, history position, and session metadata.
- Track successful open/save baselines separately from unsaved recipe/import origin; pristine initial empty content remains reusable.
- Change New/Open/Reopen Shader/Recipes to create and activate documents. Failed loads create no document; repeat canonical stack paths activate the existing document.
- Repeated recipes create independent layer/coord instances. Reopen Shader keeps an unsaved origin and preserves the body-difference warning.
- Rebind panel callers to the active document and capture the owning document in action callbacks. Inactive histories must survive switching without calling active-panel mutation callbacks against the wrong stack.
- Replace legacy replacement-undo expectations with navigation/history-preservation assertions. Keep internal replacement only where a fixture explicitly requires it and document ownership remains intact.

**Verification:** Add selector `tabs_documents` for independent recipe copies, baseline/dirty rules, canonical path reuse, failed open, stable IDs, and alternating undo/redo. Adapt and run selectors `6`, `7`, `8`, `ui_actions`, `ui_picker`, `ui_complete`, and `ui_labels` on `4.6.2`; run `tabs_documents` on `4.4`.

**Exit criteria:** Opening content never replaces another document's unsaved stack; navigation creates no stack action; inactive histories and raw serialized content remain independent.

**Blockers:** Phase `2` must pass. Path canonicalization must match the platform's filesystem semantics for the tested project paths.

**Wires:** Existing New/Open/Reopen Shader/Recipes handlers create documents and activate them. Visible tab controls are wired in phase `4`.

## Phase 4: Add shader tabs and activation state

**Status:** pending

**Goal:** Expose document switching through the GoShade tab row while restoring editing state and rendering only the active preview.

**Files:**

- `addons/goshade_turbo/ui/gst_document.gd`.
- `addons/goshade_turbo/ui/gst_main_panel.gd`.
- `addons/goshade_turbo/ui/gst_main_panel.tscn`.
- `addons/goshade_turbo/ui/gst_preview.gd`.
- `addons/goshade_turbo/ui/gst_stack_list.gd`.
- `tests/gst_editor_tabs_smoke.gd` (new).
- `tests/gst_editor_smoke.gd`.
- `tests/gst_editor_ui_layout_smoke.gd`.
- `tests/gst_editor_ui_picker_smoke.gd`.
- `tests/gst_editor_ui_complete_smoke.gd`.
- `docs/EDITOR_SMOKE.md`.

**Implementation:**

- Insert a horizontally scrolling shader-tab row above `FileToolbar`, with filename/recipe/numbered Untitled titles, dirty stars, full-path/origin tooltips, and trailing New control.
- Route activation through stable document IDs, independent of displayed order or mutable save names.
- Finish native continuous edits, cancel the current picker, clear stale focus restoration, then bind the selected document.
- Restore stable-ID layer selection and list position, preview preset/image/solo state, and document-local diagnostics; keep divider allocation and shared section settings.
- Retain last-successful preview only for its own document. An invalid document with no successful material shows no previous document's effect.
- Explicitly control `GSTPreview` update mode so only active, visible GoShade content renders; document material state may remain retained without an active viewport.
- Main-screen and scene switches preserve documents and undo histories. Hiding GoShade hides its tab row.
- Wire the tab-close affordance in phase `6`; do not expose an unguarded close path in this phase.

**Verification:** Add selector `tabs_ui` for title updates, overflow, stable-ID switching, selection/list restoration, stale picker cancellation, finish-before-switch behavior, and active-only viewport updates. Measure long titles, narrow layout, `20` layers, preview/output rectangles, normal scale, and `150%` scale. Run `tabs_ui` on `4.4`; run `ui_layout`, `ui_picker`, and `ui_complete` on `4.6.2`.

**Exit criteria:** Tab activation preserves document state and shared allocation; inactive/hidden previews do not update; no native edit, picker result, error, or preview reaches a different document.

**Blockers:** Phase `3` must pass.

**Wires:** Tab selection and trailing New call the document activation/open handlers; panel visibility controls preview rendering. Close buttons are wired in phase `6`.

## Phase 5: Bind file operations to their initiating document

**Status:** pending

**Goal:** Make Save, Save As, Export, and delayed file-dialog responses operate on the document that initiated them.

**Files:**

- `addons/goshade_turbo/ui/gst_document.gd`.
- `addons/goshade_turbo/ui/gst_main_panel.gd`.
- `tests/gst_editor_document_files_smoke.gd` (new).
- `tests/gst_editor_smoke.gd`.
- `tests/gst_editor_ui_complete_smoke.gd`.
- `docs/EDITOR_SMOKE.md`.

**Implementation:**

- Capture stable document ID and request identity for Save As, Export, overwrite confirmation, preview-image selection, and delayed open/reopen requests.
- Resolve every response against its pending request and owning document; reject closed/stale targets without touching another document.
- Preserve export's existing hand-edit overwrite check and bind its second confirmation to the original request.
- Refuse Save As to a canonical path owned by another open document with a specific path-conflict message.
- Update path/title and the saved fingerprint only after successful stack save; Export never clears dirty state.
- Return a concrete success/failure result to the close lifecycle without inferring success from dialog dismissal.
- Route operation messages to their owning document so a delayed failure cannot replace another document's diagnostics.

**Verification:** Add selector `tabs_files`; switch active documents between dialog open/response and export confirmation. Verify success, cancellation, failed save/open/export, canonical path collisions, delayed preview-image response, and stale request rejection. Read written `.tres`/shader headers to prove the originating content was used. Run on `4.4` and existing selectors `6`, `7`, `ui_complete` on `4.6.2`.

**Exit criteria:** Delayed callbacks cannot redirect a write or preview-image edit; only successful saves update baseline/path; failed writes retain content and dirty state.

**Blockers:** Phase `4` must pass. Closed-document callbacks receive their full runtime check after phase `6` adds closure.

**Wires:** Existing file toolbar/dialog callbacks resolve stable document requests; successful save results are consumed by phase `6` close continuations.

## Phase 6: Protect document close

**Status:** pending

**Goal:** Close shader tabs through a document-bound Save, Discard, or Cancel lifecycle.

**Files:**

- `addons/goshade_turbo/ui/gst_main_panel.gd`.
- `addons/goshade_turbo/ui/gst_document.gd`.
- `tests/gst_editor_document_close_smoke.gd` (new).
- `tests/gst_editor_document_files_smoke.gd`.
- `tests/gst_editor_smoke.gd`.
- `docs/EDITOR_SMOKE.md`.

**Implementation:**

- Wire close buttons; close clean documents immediately and prompt for dirty documents.
- Save untitled documents through Save As; close only the original requested document after success.
- Preserve dirty documents after failed saves or either dialog cancellation. Discard releases only the selected document's resources/history.
- Invalidate pending file/picker/property callbacks for a closed document; prevent stale close continuation from closing a replacement tab.
- Select an adjacent remaining tab; closing the last restores the existing recipe/Open/Create Empty Stack entry surface.
- Keep closing and entry navigation outside stack undo. Finish continuous native edits before evaluating dirty state.

**Verification:** Add selector `tabs_close` for clean close, dirty Save/Discard/Cancel, untitled Save As success/failure/cancel, inactive-document close, adjacent selection, last close, and stale responses after closure. Re-run `tabs_files` with closed-target cases on `4.4` and `4.6.2`.

**Exit criteria:** Every close path preserves unsaved data unless explicitly discarded or successfully saved; undo cannot reopen a closed document.

**Blockers:** Phase `5` must pass.

**Wires:** Tab close buttons invoke close requests; close-dialog and Save As callbacks resolve the same document ID.

## Phase 7: Save dirty documents during confirmed shutdown

**Status:** pending

**Goal:** Preserve dirty documents through Godot's confirmed quit flow using synchronous saves and project-local recovery records.

**Files:**

- `addons/goshade_turbo/plugin.gd`.
- `addons/goshade_turbo/ui/gst_main_panel.gd`.
- `addons/goshade_turbo/ui/gst_document.gd`.
- `addons/goshade_turbo/ui/gst_document_recovery.gd` (new).
- `tests/gst_editor_document_recovery_smoke.gd` (new).
- `tests/gst_editor_smoke.gd`.
- `tests/fixtures/shader_tabs_host.tscn`.
- `docs/EDITOR_SMOKE.md`.

**Implementation:**

- Add `_get_unsaved_status("")` reporting dirty shader documents; nonempty scene requests report no scene-owned shader data.
- Implement `_save_external_data()` synchronously: finish current native edits, save dirty named documents, and recover untitled or failed-path documents.
- Store self-contained recovery stacks plus metadata under `get_project_settings_dir()/goshade_turbo/recovery`; preserve original path/origin and record identity separately from stack schema.
- Check every stack and metadata operation before claiming recovery success; a partial record cannot be treated as restored content.
- Reopen valid recovery records as dirty documents before initial entry. Keep failed/unreadable records and report their paths instead of deleting them.
- Keep each record until its document is successfully saved or explicitly discarded; verify cleanup after Save As and close Discard.
- Recovery files never use a user's original stack/export as their destination. Repeated shutdown must retain recoverable content and avoid duplicate restoration of one record.
- If original save and recovery both fail, report both exact paths and the void-callback limitation through an editor error.

**Verification:** Add selector `tabs_recovery` with isolated recovery storage and controlled save/write failures. Test mixed named/untitled documents, successful and failed saves, metadata failure, fresh-editor restoration, retained dirty markers, later Save/Discard cleanup, and nonempty `for_scene`. Execute the real quit confirmation and Save and Quit on `4.4`, then reopen the project. Apply phase `1` evidence requirements to production callbacks with the probe disabled; preserve the expected dual-failure error.

**Exit criteria:** Confirmed shutdown saves or recovers each dirty document; restoration occurs before entry; records survive until save/discard; the failure case reports exact paths without claiming shutdown can be vetoed.

**Blockers:** Phase `1` shutdown proof and phase `6` must pass. A callback/storage mismatch returns to design review.

**Wires:** Plugin quit callbacks call panel document save/recovery operations; plugin startup loads recovery records; document Save/Discard removes the matching record.

## Phase 8: Verify complete lifecycle across supported versions

**Status:** pending

**Goal:** Establish integrated tab, native-editing, lifecycle, and rendering compatibility on Godot `4.4`, `4.6.2`, and `4.7`.

**Files:**

- `tests/gst_editor_smoke.gd`.
- `tests/gst_editor_document_proof.gd`.
- `tests/gst_editor_native_undo_smoke.gd`.
- `tests/gst_editor_documents_smoke.gd`.
- `tests/gst_editor_tabs_smoke.gd`.
- `tests/gst_editor_document_files_smoke.gd`.
- `tests/gst_editor_document_close_smoke.gd`.
- `tests/gst_editor_document_recovery_smoke.gd`.
- `tests/gst_editor_ui_layout_smoke.gd`.
- `tests/gst_editor_ui_actions_smoke.gd`.
- `tests/gst_editor_ui_labels_smoke.gd`.
- `tests/gst_editor_ui_picker_smoke.gd`.
- `tests/gst_editor_ui_complete_smoke.gd`.
- `tests/run_codegen_tests.gd` (run unchanged).
- `tests/run_render_checks.gd` (run unchanged).
- `tests/run_recipe_motion_checks.gd` (run unchanged).
- `tests/fixtures/shader_tabs_host.tscn`.
- `tests/fixtures/shader_tabs_shutdown_plugin.gd`.
- `tests/fixtures/shader_tabs_shutdown_plugin.cfg`.
- `docs/EDITOR_SMOKE.md`.

**Verification:**

- Run unit wrapper, all new tab selectors, and existing selectors `4`, `5`, `6`, `7`, `8`, `ui_layout`, `ui_actions`, `ui_labels`, `ui_picker`, `ui_complete` on all three versions.
- Run GPU render/composition/noise and recipe-motion commands on Compatibility and Forward+ on all three versions.
- Test a small host game scene on all versions: document-owned structural/native edits, scene switch, Save As, alternating focused Undo/Redo including native popups, and scene Undo outside GoShade.
- Execute real confirmed Save and Quit followed by fresh project open on all versions; include mixed path failures and an expected recovery-write failure. Keep confirmation evidence separate from callback-only tests and direct restart calls.
- Inspect normal/scaled screenshots for long tab overflow, focused controls, native RGB popup, narrow layout, `20` layers, and fixed preview/output placement.
- Compare serialized output before/after navigation; verify no session metadata enters `.tres`, headers, or shaders.
- Maintain a replacement-assertion migration list: previous expectation, reviewed navigation replacement, and retained nonreplacement checks. Historical evidence remains historical.
- Record observed test counts, error exceptions, renderer restrictions, and any manual-only steps. Do not claim OS-dialog or quit UI automation from direct callback tests alone.

**Exit criteria:** Supported-version matrices pass with no unresolved isolation/data-loss failures; every reviewed edge case has evidence. Production fixes discovered here return to the owning phase and receive review before affected checks repeat.

**Blockers:** Phases `1` through `7` must pass. Release tuning remains the user's separate open checklist item.

## Cross-cutting concerns

### Shared editor state and history

- Phase `2` removes GoShade action/watcher dependence on the shared editor manager; phase `3` owns one standalone `UndoRedo` per document.
- Resource paths and active scenes cannot choose a shader history. Register shader actions directly on the owning document's instance; no `GLOBAL_HISTORY` lookup or editor-manager context applies.
- Phase `4` keeps editor layout metadata shared while document state and material/error caches remain isolated.
- Never clear or rewrite Godot scene/global history. Teardown releases only GoShade-owned histories, adapters, and connections; disconnect listeners and release bound callables without retaining closed documents.
- Rollback requires preserving dirty documents through save/recovery before removing the implementation; reverting source cannot restore discarded runtime state.

### Serialization and recovery format

- Existing stack/header schema, stable layer IDs, parameter keys, and shader text contracts stay unchanged.
- Phase `3` fingerprints serialized content, including monotonic `next_id`; undoing an add may leave a different fingerprint because IDs are never reused.
- Phase `7` introduces editor-local recovery metadata only. Define and validate its record version, record identity, stack filename, original save path, and origin/recipe information in that implementation.
- Invalid/unknown recovery metadata remains available for diagnosis; no migration may silently delete it.
- Rollback retains recovery files until the user saves or discards recovered content; no cleanup of unrelated project settings files is allowed.

### Public APIs, signals, and callbacks

- Phase `2` changes inspector getter types and native-property routing; all listed smoke consumers move to standalone rows in the same phase.
- `GSTUndo` constructor/history types change from `EditorUndoRedoManager` to `UndoRedo`; method actions use bound Callables. Every caller and fixture migrates in phase `2`.
- Native `property_changed(property, value, field, changing)` remains authoritative for values and retains the immutable owning document/object/property target; numeric `changing=true` is not required.
- Phase `1` proves, then phase `2` implements, public `EditorSpinSlider` descendant signals `grabbed`, `ungrabbed`, `value_focus_entered`, and `value_focus_exited`. First begin captures the original value; another begin retains it; drag release or value-focus exit finishes the corresponding interaction.
- Non-drag grab followed by value entry is one interaction. Finish registers one mutation-first action only for a changed value; next begin captures a fresh original. Outside native boundaries, use the `changing=true`/`changing=false` fallback or one discrete action for isolated `false`.
- Native color popup preview/final emission remains intact. Finish numeric gestures and close native color popups before rebind, Save/Save As, shutdown save, or undo/redo; wait for final delivery to the original target before continuing.
- Phase `1` and `2` tests require actual multi-change float/vector drags, separate repeated gestures, real numeric focus/RGB popup close, forced-finish ordering, and document/scene isolation. Phases `4`, `5`, and `7` consume this boundary for switching, saves, and shutdown; phase `8` repeats the tests across supported versions.
- Phase `3` makes New/Open/Recipes/Reopen navigation APIs create/activate documents; internal fixture replacement cannot serve as a user-facing history escape.
- Phase `4` adds stable-ID activation and render-visibility control; phase `5` binds file requests/results to stable IDs.
- Phase `6` adds guarded close continuations; phase `7` connects plugin unsaved/save callbacks and recovery startup.
- Existing structural `GSTUndo` semantics and same-instance layer restoration remain required. Callback refresh targets must resolve the owning document before accessing active UI.
- On rollback, restore matching callers, inspector registration, and tests together. Do not combine standalone property routing with the superseded shared-manager shader history.

### Shared controls, base classes, and themes

- Phase `2` adapts only the native property-row container boundary and its metadata/context support.
- Reuse existing labels, hints, section-state persistence, measurement rules, color adapter, and picker controls.
- No new custom parameter widget, theme redesign, global Inspector behavior, shader library change, or recipe tuning is included.

### Generated files and release configuration

- New scripts receive Godot-generated `.uid` companions; new `class_name` scripts require import before tests.
- Source `.tscn` changes count toward the phase cap; generated imports and screenshots do not authorize unrelated modifications.
- Keep minimum Godot version `4.4` and production plugin activation/configuration unchanged, apart from the reviewed runtime callback/registration changes.
- Shutdown probe plugin configuration belongs only to isolated verification projects.
- Preserve pre-existing project/import changes; restore only test-generated version churn using the recorded starting state.
- No release, deployment, publishing, or dependency changes are planned.
