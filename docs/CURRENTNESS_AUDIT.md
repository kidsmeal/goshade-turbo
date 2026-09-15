# Currentness Audit

Last updated: 2026-09-15

Purpose: help a future session answer "what is actually current?" before touching an old
plan. This is an audit snapshot, not a reorganization. Prefer correcting this file over
rewriting or moving the older docs. Refresh it with `/claudhd:audit`.

## Trust First

The best current anchors. A session can rely on these.

| Area | Current anchor | Current read |
|---|---|---|
| Active implementation | `docs/SHADER_TABS_reviewed-plan.md` | All 8 phases committed (phase 8 `ee12dcd`, 2026-09-14). Nothing in flight; the next thread is picked from ROADMAP.md. |
| Codebase lookup | `addons/goshade_turbo/` tree plus `docs/EDITOR_SMOKE.md` evidence sections | No standing map file. `gst_main_panel.gd` owns documents, tabs, file ops, close, shutdown; `gst_document.gd`, `gst_document_recovery.gd`, `gst_inspector_column.gd`, `gst_undo.gd` are the phase 2 to 7 modules. |
| Conventions / rules | `docs/DESIGN.md` (locked decisions, prior art re-verified 2026-09-15, release checklist) | Reference, not a task queue. One checklist item open: the user tuning pass (line 159). |
| Runtime verification | `docs/RUNTIME_VERIFICATION_QUEUE.md` | Live list, refreshed 2026-09-15. |
| Durable memory | `~/.claude/projects/.../memory/` (`codex-reviewer-only.md`, `claude-vs-codex-token-scale.md`) | Reviewer routing history and token scale; not a build queue. |

## Needs Reconciliation

Docs or systems with mixed signals. Name the stale claim and what the code actually shows.

### docs/SHADER_TABS_reviewed.md decision 10 (line 25), resolved 2026-09-15
Claims `_get_unsaved_status("")` lists dirty shader documents and `_save_external_data()` cannot veto shutdown. Code: `gst_main_panel.gd` lists documents where `GSTDocument.needs_shutdown_attention()` is true (dirty with no current recovery record), because Godot 4.4 `editor_node.cpp:3071` re-gates the quit with `p_confirmed = false` after `save_external_data()`, and a permanently dirty recovered document would loop the confirmation. Read as: the shipped behavior is the reviewed intent; amend the decision text, do not change code.

### docs/EDITOR_UI_DESIGN_reviewed.md decisions 6 and 7 (lines 35 and 37)
Decision 7 says stack edits remain in `EditorUndoRedoManager`; shader tabs phase 2 moved every stack action onto a per-document `UndoRedo` (`gst_undo.gd`, `gst_document.gd`). Decision 6 says a control-local refusal clears only on a valid edit, destination removal, or stack replacement; phase 5 made file-operation messages per-document and re-shown on activation (`_refresh_operation_message_label`). Read as: superseded by `docs/SHADER_TABS_reviewed.md` decisions 7 to 12; treat that doc as authoritative for undo and messages.

### tests/run_codegen_tests.gd baseline
Reports `145 methods, 21 failures` (20 pre-existing: `generative/clock` shader compile error plus stale library-index counts; 1 added by `generative/cell_borders`, a hardcoded roster size in `tests/test_combinations.gd`). Read as: a known plan-external baseline, on ROADMAP.md Next; not a signal about shader tabs.

## Likely Shipped / Historical

Should not pull attention unless a bug points back here.

| Area | Read |
|---|---|
| `docs/PLAN.md` | GoShade Turbo v0.1 build plan, all phases shipped by 2026-09-07; history. |
| `docs/EDITOR_UI_DESIGN_reviewed-plan.md` | Editor UI phases 1 to 5 committed 2026-09-08 and 09; history. |
| `docs/EDITOR_UI_DESIGN.md`, `docs/SHADER_TABS.md` | Pre-review drafts; the `_reviewed.md` files supersede them. |
| `docs/SPIKE_NOTES.md` | Early spike notes; history. |
| `docs/EDITOR_SMOKE.md` | 4469-line evidence log, append-only by convention; newest sections at the end are current, older ones are superseded by later correction sections. |

## Open doc flags

Written by the review relay when a phase diff made a standing doc stale. Cleared by `/claudhd:audit`.
Format: `- [ ] <doc path>: <one line, what the diff invalidated> (phase N, <feature or plan name>)`.

- [x] docs/EDITOR_UI_DESIGN_reviewed.md:35 (superseded note appended 2026-09-15): decision 6 message-label lifetime no longer describes file-operation messages, which are per-document and re-shown on activation (phase 5, Multiple shader tabs)
- [x] docs/EDITOR_UI_DESIGN_reviewed.md:37 (superseded note appended 2026-09-15): decision 7 says stack edits stay in `EditorUndoRedoManager`; phase 2 moved them to a per-document `UndoRedo` (phase 2, Multiple shader tabs; found at audit 2026-09-15)
- [x] docs/SHADER_TABS_reviewed.md:25 (decision 10 rewritten 2026-09-15): decision 10 lists "dirty shader documents" and says shutdown cannot be vetoed; code lists `needs_shutdown_attention()` documents and the engine re-gates the quit (phase 7, Multiple shader tabs)

## Deferred review notes

Written by the review relay at the commit gate, one line per Deferred note the phase-reviewer
chose not to fix this phase (pending external API, plan-blessed placeholder, later-phase consumer).
A deferred note is not a dropped note - it lives here until someone clears it. Retire a line when
the work lands or the reason expires; `/claudhd:audit` prunes stale ones.
Format: `- [ ] <note, with file:line>: <why deferred> (phase N, <feature or plan name>)`.

- [ ] tests/run_render_checks.gd:38: the Codex reviewer sandbox has no GPU; the orchestrator's GPU runs on 4.4, 4.6.2, 4.7 are the evidence. Clears when a GPU-capable reviewer environment exists (phase 8, GoShade Turbo v0.1)
- [ ] docs/EDITOR_SMOKE.md: `Failed to read the root certificate store` appears on some reviewer machine profiles and not in the orchestrator's isolated `APPDATA` runs (0 occurrences across phase 8). Clears when a run in an affected profile reports 0 (phase 2, Multiple shader tabs; last reproduced phase 8 review round 1)
- [ ] addons/goshade_turbo/ui/gst_main_panel.gd `_save_external_data` path: `_finish_pending_edits()` cannot be awaited from the void virtual, so a color popup mid-edit could commit after the recovery write. The phase 8 probe on 4.4, 4.6.2, 4.7 (one untitled document, one popup) saw the pending value land in the record every time. Clears after a multi-document, mixed-pending-edit probe (phase 7, Multiple shader tabs)
- [ ] tests/gst_editor_document_close_smoke.gd `dirty_named_close_discard` on 4.4: one `pass=10 fail=3` first run in phase 8 (`dialog_shown=true closed=false`, `disk_unchanged=true`), never reproduced in about 10 later fresh runs on any version. Clears when it recurs with the failing check names captured before any retry (phase 8, Multiple shader tabs)
- [ ] docs/EDITOR_SMOKE.md phase 8 matrix: selectors 4 to 8 last ran at review round 2 while `gst_inspector_column.gd` changed in rounds 3 to 5; the reviewer verified by reading that the changed color-row code is unreachable from them. Clears at the next full-matrix pass, the v0.1 release checklist (phase 8, Multiple shader tabs)

Retired 2026-09-15 (work landed, see SHIPPED.md and git): README import prerequisite (v0.1 phase 8); cellular_edges description (v0.1 phase 2, then superseded by quick fix `6980a5a`, which dropped `width` and returns raw F2 - F1); 4.6.2 launcher exit codes (shader tabs phase 8); `hide_export_dialog` pending-export clear and closed-target Save As and Export feedback (shader tabs phase 6); both `tabs_recovery` stage exit codes (shader tabs phase 8); the two paragraph-length ledger lines, compacted above.

## Rule of thumb
- Roadmap says what to do next.
- Plans say how to do it.
- Design says why it exists and what constraints it obeys.
- Archive says what happened.
- Memory says what must not be forgotten.
