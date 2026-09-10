# Multiple shader tabs - Design

Status: draft
Intent: Keep several shaders open and switch between them without losing edits or the place being edited.

## Problem

- Verified in `plugin.gd` and `gst_main_panel.gd`: the plugin creates one panel with one current stack, path, selection, and preview. New/Open/Recipes replace that stack.
- Verified in Godot's `EditorPlugin` documentation: the existing top row belongs to scenes. User approved an independent shader row visible only inside GoShade Turbo, then requested implementation.
- User reports Pearl and Opal work. The overall release tuning checklist remains open.

## Design

Implementation defaults below are Codex decisions within the approved tab feature. User decisions are identified explicitly.

1. Placement (user): put a horizontal shader-tab row above the GoShade toolbar, inside its root Control. Godot's scene tabs remain unchanged. Hiding the GoShade panel hides its shader row. Beat: shader tabs visible in other main screens or scene-dependent shader documents.
2. Opening (Codex): New, Open, Reopen Shader, and a recipe selection create and activate a document. Reuse the initial pristine empty document for its first content. Opening an already-open canonical stack path activates that tab. Repeated recipe selection creates an independent editable copy. Beat: replacing unsaved work or accidentally sharing mutable layers across tabs.
3. Identity (Codex): each runtime document owns a stable session ID, its GSTStack and nested resources, save path, recipe flag, selected stable layer ID, preview preset/image/solo state, and saved-content fingerprint. Preserve existing stack/header formats. Session IDs are never serialized into exports. Beat: using tab index or mutable filename as identity.
4. Presentation (Codex): titles use filename without extension, recipe name before save, or numbered Untitled labels. Show `*` when stack content differs from the last successful save/open baseline; unsaved nonempty recipe/import documents require saving. Tooltip shows the full path or unsaved origin. Tabs have close buttons and a trailing `+` for New. Overflow scrolls horizontally. Beat: fixed-width tabs shrinking titles indefinitely.
5. Editing (Codex): switching restores document-specific state, retains the current editing/preview width allocation, and performs no stack undo action. Cancel any open layer/input picker before switching, preserving no stale target. Suspend inactive preview viewports. Beat: multiple active render loops or edits reaching a prior tab's layer.
6. Undo (approved proposal, technical mechanism requires verification): Ctrl+Z/Ctrl+Shift+Z in GoShade affect only the active shader, preserving inactive shader undo/redo. Every stack mutation remains registered through EditorUndoRedoManager and parameter widgets remain Godot-native property editors. Scene switching and Save As must not reroute shader history into scene history. Never clear or rewrite Godot's shared scene/global history. Beat: undo silently modifying a hidden shader or game scene.
7. Undo implementation boundary (Codex): first prove a public-API solution on Godot 4.4. The shared manager only exposes scene/global history inference; distinct context Resources alone are insufficient. A document-owned EditorUndoRedoManager with explicitly routed native EditorProperty edits is an implementation candidate, not a verified capability. Preserve native widget presentation and continuous-edit grouping. Do not create dummy scenes, fabricate resource paths, call unbound methods, or patch Godot editor internals. If no compliant route works, stop for a user decision before changing the undo contract.
8. Saving (Codex): Save/Save As/Export act on the initiating document. Pending dialog state carries its stable ID; switching cannot redirect a response. A failed save leaves dirty state and the document open. Save As onto a path already owned by another open document is refused with a specific message. Export does not clear the stack's unsaved marker. Beat: writing one tab into another's path.
9. Closing (Codex): unmodified saved documents close immediately. Dirty documents offer Save, Discard, Cancel; Save on an untitled document runs Save As and closes only after success. Closing selects the adjacent remaining tab. Closing the last tab restores the existing recipe/Open/Create Empty Stack entry surface. Close/navigation are UI operations outside stack undo. Beat: data loss or undo reopening discarded tabs.
10. Shutdown (Codex): integrate Godot's supported unsaved-status and save-external-data callbacks so closing the project warns about unsaved shader documents. Do not silently overwrite saved files, discard untitled edits, or continue shutdown after a cancelled required save. Verify actual editor lifecycle behavior; report a blocker if public APIs cannot enforce the chosen contract. Beat: close protection working only on the tab close button.
11. Session scope (Codex): keep open documents through main-screen and scene switches for the current editor session. Restoring tabs after editor restart and crash recovery are deferred. Preserve existing shared layout persistence. Beat: expanding the initial feature into an autosave system.
12. Compatibility (Codex): ordinary edits, slot conversions, stable layer IDs, native Color center picker, recipe Randomize, codegen/export, and one self-contained shader retain their existing contracts. New/Open/Recipe become document-open navigation and supersede the old replacement-undo behavior for these entry points. Explicit internal replacement may remain for fixtures only when it does not escape document ownership.

```text
Godot scenes: [level.tscn x] [+]
GoShade:      [Pearl x] [Opal* x] [Untitled 1 x] [+]
              File  Save  Recipes  Randomize       Export
              -----------------------------------------
              Layers | Layer settings | Preview
```

## Contracts touched

- `plugin.gd`: main-screen lifecycle, native inspector registration, shutdown callbacks.
- `ui/gst_main_panel.gd`: document ownership, file entry points, history, tab activation, save/close lifecycle.
- `ui/gst_undo.gd`, `gst_inspector_column.gd`, `gst_inspector_plugin.gd`: ownership-aware native and structural undo, without custom slider widgets.
- `ui/gst_preview.gd`: pause inactive rendering while retaining state.
- `docs/EDITOR_UI_DESIGN_reviewed.md` decision `7`: new-document navigation no longer replaces the active stack as one undo action.
- No stack schema migration or shader-library change.

## Edge cases and verification

- Two recipe copies must have independent layer/coord objects; changing one must not change the other.
- Alternate structural edits, native slider/color edits, Undo, Redo, Save As, and scene switches across documents. No other shader or game-scene state may change.
- Repeated undo of a merged slider drag is one edit; switching tabs must finish the edit before rebinding native controls.
- Save/open errors, duplicate paths, and stale dialogs preserve all unsaved data.
- Closing dirty tabs: Save success/failure/cancel, Discard, Cancel; last-tab close returns to initial entry.
- Main-screen visibility, many long tab titles, keyboard focus, narrow layout, and 20-layer stacks preserve usable preview/output placement.
- A deliberately invalid stack in one tab must not leak errors or last-successful preview into another tab.
- Test a small host game scene, not only the standalone sandbox. Preserve the user's untracked `weird1.tres`, `weird2.tres`, and pre-existing Glow import changes.
- Minimum-version native undo feasibility is a required first implementation check. Then test focused lifecycle/UI behavior on Godot 4.4, 4.6.2, and 4.7 plus current unit/render regressions. Record exact evidence and limitations.

## Out of scope

- Scene-row replacement, scene-bound shaders, simultaneous side-by-side previews, cross-document layer references/copy-paste, automatic session restore, crash recovery, and release-tuning sign-off.

## Open questions

- No unresolved product preference. Undo routing and editor shutdown are explicit technical verification gates; do not silently weaken their behavior.

## Evidence

- Godot 4.4 public manager API: https://docs.godotengine.org/en/4.4/classes/class_editorundoredomanager.html
- Godot 4.4 manager implementation: https://github.com/godotengine/godot/blob/4.4/editor/editor_undo_redo_manager.cpp
- Godot 4.4 plugin lifecycle: https://docs.godotengine.org/en/4.4/classes/class_editorplugin.html
