# Multiple shader tabs - Design

Status: reviewed
Intent: Keep several shaders open and switch between them without losing edits or the place being edited.

## Problem

- Verified in `plugin.gd` and `gst_main_panel.gd`: the plugin creates one panel with one current stack, path, selection, and preview. New/Open/Recipes replace that stack.
- Verified in Godot's `EditorPlugin` documentation: the existing top row belongs to scenes. User approved an independent shader row visible only inside GoShade Turbo, then requested implementation.
- User reports Pearl and Opal work. The overall release tuning checklist remains open.

## Design

Implementation defaults below are Codex decisions within the approved tab feature. User decisions are identified explicitly.

1. Placement (user): put a horizontal shader-tab row above the GoShade toolbar, inside its root Control. Godot's scene tabs remain unchanged. Hiding the GoShade panel hides its shader row. Beat: shader tabs visible in other main screens or scene-dependent shader documents.
2. Opening (Codex): New, Open, Reopen Shader, and a recipe selection create and activate a document. Reuse the initial pristine empty document for its first content. Opening an already-open canonical stack path activates that tab. Repeated recipe selection creates an independent editable copy. Beat: replacing unsaved work or accidentally sharing mutable layers across tabs.
3. Identity (Codex): each runtime document owns a stable session ID, its GSTStack and nested resources, save path, recipe flag, selected stable layer ID, preview preset/image/solo state, and saved-content fingerprint. The fingerprint covers serialized stack content only. Preserve existing stack/header formats. Session IDs are never serialized into exports. Beat: using tab index or mutable filename as identity.
4. Presentation (Codex): titles use filename without extension, recipe name before save, or numbered Untitled labels. Show `*` when serialized stack content differs from the last successful save/open baseline; unsaved nonempty recipe/import documents require saving. Tooltip shows the full path or unsaved origin. Tabs have close buttons and a trailing `+` for New. Overflow scrolls horizontally. Beat: fixed-width tabs shrinking titles indefinitely.
5. Editing (Codex): switching restores document-specific state, retains the current editing/preview width allocation, and performs no stack undo action. Finish any active continuous native property edit, then cancel any open layer/input picker before rebinding the inspectors. Preserve no stale picker target. Suspend inactive preview viewports. Beat: multiple active render loops or edits reaching a prior tab's layer.
6. Undo (user, approved `2026-09-09`): each shader document owns one Godot `UndoRedo` instance. `GSTUndo` registers every stack edit, including native property edits, with the owning document's history. Ctrl+Z/Ctrl+Shift+Z while GoShade has focus acts on the active document, including focus inside a native property popup. Switching documents retains inactive histories. Scene switching and Save As do not reroute shader history into scene history. Never clear or rewrite Godot's shared scene/global history. Beat: undo silently modifying a hidden shader or game scene.
7. Undo capability gate and implementation boundary (original manager route failed; replacement route partially verified): Godot `4.4.stable.official.4c311cbee` reports `ClassDB.can_instantiate(EditorUndoRedoManager)=false`; direct `EditorUndoRedoManager.new()` also fails parsing because the native class is abstract. The prior private-manager candidate is invalid. Native property-editor factory and binding APIs remain available in Godot `4.4`, so retain native sliders and color pickers. The approved replacement route registers structural and property actions with the owning document's `UndoRedo` instance. The `4.4` replacement proof passes standalone-history, structural, shortcut/host-scene, native vector/RGB, resource/scene-retention, and shutdown-status assertions. Its remaining failure proves that `EditorProperty.property_changed(..., changing)` cannot be the only gesture boundary: `EditorPropertyFloat::_value_changed` calls `emit_changed(property, value)` without `changing=true`, and an actual vector drag also emitted multiple `changing=false` events. Keep `property_changed` as the authoritative value channel and use `changing` when an editor supplies it. For numeric rows, discover their public `EditorSpinSlider` descendants and connect the public `grabbed`, `ungrabbed`, `value_focus_entered`, and `value_focus_exited` signals. The first begin signal captures the bound property's exact pre-gesture value; another begin signal during the same interaction retains that value. Apply every emitted value live to the immutable document/object/property target. `ungrabbed` finishes a drag. A value form entered after a non-drag grab continues the same interaction, and `value_focus_exited` finishes it. Finishing registers one mutation-first action only when the final value differs from the captured value. The next begin signal captures a new value, so repeated gestures remain separate undo actions. When no native boundary is active, the first `changing=true` event begins a gesture and the following `changing=false` event finishes it; a `changing=false` event outside a gesture is one discrete action. Native color rows retain `EditorPropertyColor`'s live popup preview and final `property_changed` emission. Before document rebind, Save/Save As, shutdown save, or undo/redo, finish an active numeric gesture; close an active native color popup and continue only after its final property change has reached the original immutable target. Never save, rebind, or execute undo/redo while a native edit is pending. Replace the two embedded `EditorInspector` containers with plugin-owned rows made from `EditorInspector.instantiate_property_editor(...)`; bind each returned native `EditorProperty` through public `set_object_and_property(...)`. Preserve native widget presentation, labels, tooltips, read-only explanations, focus restoration, and property refresh. Ctrl+Z/Ctrl+Shift+Z while GoShade has focus call undo/redo on the active document history. Do not connect these standalone property rows to an `EditorInspector`, create custom parameter widgets, create dummy scenes, fabricate resource paths, call unbound methods, or patch Godot editor internals. Before other tab work resumes, prove on Godot `4.4` that an actual multi-change float drag and vector-component drag each undo once, two repeated gestures undo separately, text-focus entry finishes once, native RGB popup close finishes once, and forced finish precedes rebind/save/undo. Retain the passing isolation assertions. Stop and return to design review if the public boundaries fail any real input path.
8. Saving (Codex): Save/Save As/Export act on the initiating document. Pending dialog state carries its stable ID; switching cannot redirect a response. A failed save leaves dirty state and the document open. Save As onto a canonical path already owned by another open document is refused with a specific message. Export does not clear the stack's unsaved marker. Beat: writing one tab into another's path.
9. Closing (Codex): unmodified saved documents close immediately. Dirty documents offer Save, Discard, Cancel; Save on an untitled document runs Save As and closes only after success. Closing selects the adjacent remaining tab. Closing the last tab restores the existing recipe/Open/Create Empty Stack entry surface. Close/navigation are UI operations outside stack undo. Beat: data loss or undo reopening discarded tabs.
10. Shutdown (Codex): `_get_unsaved_status("")` lists dirty shader documents in Godot's quit confirmation. If the user chooses Save and Quit, `_save_external_data()` synchronously saves dirty documents that have paths and writes every untitled or failed-path document as a self-contained recovery stack plus metadata under `EditorInterface.get_editor_paths().get_project_settings_dir()/goshade_turbo/recovery`. On the next project open, recovery documents reopen as dirty tabs before the normal entry surface; each recovery record remains until that document is saved or discarded. A recovery record never overwrites a user stack or exported shader. If both the requested save and recovery write fail, report the exact paths and engine limitation through an editor error; `_save_external_data()` is void and cannot veto shutdown. Beat: close protection working only on the tab close button.
11. Session scope (Codex): keep open documents through main-screen and scene switches for the current editor session. General saved-tab restoration and crash recovery are deferred. Shutdown recovery in decision `10` covers only dirty documents presented to Godot's confirmed quit flow. Preserve existing shared layout persistence. Beat: expanding the initial feature into a full session-restore system.
12. Compatibility (Codex): ordinary edits, slot conversions, stable layer IDs, native Color center picker, recipe Randomize, codegen/export, and one self-contained shader retain their existing contracts. New/Open/Recipe become document-open navigation and supersede the old replacement-undo behavior for these entry points. Explicit internal replacement may remain for fixtures only when it does not escape document ownership.

```text
Godot scenes: [level.tscn x] [+]
GoShade:      [Pearl x] [Opal* x] [Untitled 1 x] [+]
              File  Save  Recipes  Randomize       Export
              -----------------------------------------
              Layers | Layer settings | Preview
```

## Contracts touched

- `plugin.gd`: main-screen lifecycle, `_get_unsaved_status`, `_save_external_data`, and recovery loading.
- `ui/gst_main_panel.gd`: document ownership, file entry points, history, tab activation, save/close lifecycle.
- `ui/gst_undo.gd`, `gst_inspector_column.gd`, `gst_inspector_plugin.gd`: document-owned `UndoRedo` history for structural and native property edits; standalone native `EditorProperty` creation/routing; obsolete embedded-inspector registration removed or adapted.
- `ui/gst_preview.gd`: pause inactive rendering while retaining state.
- `docs/EDITOR_UI_DESIGN_reviewed.md` decisions `7` and `30`: `docs/DESIGN.md` decision `20` supersedes the shared-manager mechanism, embedded inspector routing, and replacement undo for new-document navigation. Navigation and viewing state remain outside history. Compound edits remain one action. Native controls and original data keys, ranges, labels, and tooltips remain unchanged.
- No stack schema migration or shader-library change.

## Edge cases and verification

- Two recipe copies must have independent layer/coord objects; changing one must not change the other.
- The replacement phase `1` proof passes `8` assertions and fails `1`. Per-document histories, structural edits, vector/RGB values, shortcuts, host-scene isolation, resource/scene retention, and shutdown status pass. The native-float assertion expected `changing=true`, but Godot `4.4` emits `false`; vector changes also emit `false`.
- Rerun the minimum-version proof with the corrected gesture adapter. Drive at least two actual value changes inside one float drag and one vector-component drag; each gesture must create one undo action from its first value to its final value. Drive the same control through two later gestures; each must create a separate action with its own first value.
- Verify numeric text focus and native RGB popup close, including forced finish before tab switch, save, and focused undo. Alternate active-document Undo/Redo, switch Godot scenes, invoke Undo outside GoShade, and inspect every affected history. Stop implementation if one gesture splits, repeated gestures merge, or any edit reaches the wrong document or game scene.
- Save/open errors, duplicate paths, and stale dialogs preserve all unsaved data.
- Closing dirty tabs: Save success/failure/cancel, Discard, Cancel; last-tab close returns to initial entry.
- Main-screen visibility, many long tab titles, keyboard focus, narrow layout, and 20-layer stacks preserve usable preview/output placement.
- A deliberately invalid stack in one tab must not leak errors or last-successful preview into another tab.
- Shutdown verification covers dirty named and untitled documents, mixed save success/failure, recovery write/read, restart restoration, later Save/Discard cleanup, scene close with a nonempty `for_scene`, and a forced recovery-write failure. Scene close must not treat session-scoped shader documents as scene-owned. The callback status assertion passes; real confirmed Save and Quit remains untested.
- Test a small host game scene, not only the standalone sandbox. Preserve the user's untracked `weird1.tres`, `weird2.tres`, and pre-existing Glow import changes.
- After the replacement undo route passes its capability gate, test focused lifecycle/UI behavior on Godot `4.4`, `4.6.2`, and `4.7` plus current unit/render regressions. Record exact evidence and limitations.

## Out of scope

- Scene-row replacement, scene-bound shaders, simultaneous side-by-side previews, cross-document layer references/copy-paste, automatic restoration of clean/saved tabs, crash recovery outside Godot's confirmed quit flow, and release-tuning sign-off.

## Open questions

- No user decisions remain. Decision `6` approves one Godot `UndoRedo` instance per shader document.
- Shutdown recovery retains decision `10` as the default and remains a first-phase technical verification gate alongside the replacement undo route.

## Evidence

- Godot `4.4` public manager API and history model: https://docs.godotengine.org/en/4.4/classes/class_editorundoredomanager.html
- Godot `4.4` manager implementation: https://github.com/godotengine/godot/blob/4.4/editor/editor_undo_redo_manager.cpp
- Godot `4.4` native inspector wiring: https://github.com/godotengine/godot/blob/4.4/editor/editor_inspector.cpp
- Godot `4.4` native property-editor API: https://docs.godotengine.org/en/4.4/classes/class_editorproperty.html
- Godot `4.4` public numeric-editor gesture signals: https://docs.godotengine.org/en/4.4/classes/class_editorspinslider.html
- Godot `4.4` float editor implementation (`EditorPropertyFloat::_value_changed`, lines `1341-1345`): https://raw.githubusercontent.com/godotengine/godot/4.4/editor/editor_properties.cpp
- Godot `4.4` standalone UndoRedo API: https://docs.godotengine.org/en/4.4/classes/class_undoredo.html
- Godot `4.4` plugin lifecycle: https://docs.godotengine.org/en/4.4/classes/class_editorplugin.html
- Godot `4.4` project-specific editor storage: https://docs.godotengine.org/en/4.4/classes/class_editorpaths.html
- Local phase 1 runtime proof: `.now/tabs-validation/evidence/tabs-proof-4.4.stdout.log` records `ClassDB.can_instantiate(EditorUndoRedoManager)=false` and `TABS_PROOF SUMMARY pass=0 fail=1`.
- Local direct-construction proof: `.now/tabs-validation/evidence/import-4.4.stderr.log` records `Native class "EditorUndoRedoManager" cannot be constructed as it is abstract.`
- Local replacement proof: `.now/tabs-validation/evidence/tabs-proof-r2q-4.4.stdout.log` records `TABS_PROOF SUMMARY pass=8 fail=1`; the float drag emitted `changing=false`, the vector edit emitted multiple `changing=false` events, and the remaining isolation/value/status assertions passed.
