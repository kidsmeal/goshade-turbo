# Currentness Audit

Last updated: <DATE>

Purpose: help a future session answer "what is actually current?" before touching an old
plan. This is an audit snapshot, not a reorganization. Prefer correcting this file over
rewriting or moving the older docs. Refresh it with `/claudhd:audit`.

## Trust First

The best current anchors. A session can rely on these.

| Area | Current anchor | Current read |
|---|---|---|
| Active implementation | `<path>` | <what is live, which phases landed, what is in flight> |
| Codebase lookup | `<path>` | <the map that is most current; may lag on fine detail> |
| Conventions / rules | `<path>` | <the authoritative style/design rules - reference, not a task queue> |
| Runtime verification | `RUNTIME_VERIFICATION_QUEUE.md` | <live list of shipped-but-unverified systems> |
| Durable memory | `<path>` | <preferences / long-range intent - not a build queue> |

## Needs Reconciliation

Docs or systems with mixed signals. Name the stale claim and what the code actually shows.

### <Doc or system>
<what it claims> vs <what the code evidence shows>. Read as: <how to treat it until reconciled>.

## Likely Shipped / Historical

Should not pull attention unless a bug points back here.

| Area | Read |
|---|---|
| <area> | <shipped / archived - keep as history> |

## Open doc flags

Written by the review relay when a phase diff made a standing doc stale. Cleared by `/claudhd:audit`.
Format: `- [ ] <doc path>: <one line, what the diff invalidated> (phase N, <feature or plan name>)`.

- [x] docs/EDITOR_SMOKE.md: round 2 fixes section reports 17 passing assertions for r6a; archived tabs-proof-r6a-4.4.stdout.log contains 18 (phase 1, Multiple shader tabs, review round 3 judgment flag; corrected to 18 in the round 3 fix pass)
- [ ] docs/EDITOR_UI_DESIGN_reviewed.md:35: the shared-message-label lifetime claim ("a control-local refusal clears only when that control completes a valid edit, its destination is removed, or the active stack is replaced") no longer describes file-operation messages, which are per-document and re-shown on activation (gst_main_panel.gd `_refresh_operation_message_label`) (phase 5, Multiple shader tabs)
- [ ] docs/SHADER_TABS_reviewed.md:25: decision 10 says `_get_unsaved_status("")` lists dirty shader documents and that `_save_external_data()` cannot veto shutdown; shipped code lists documents needing shutdown attention (`GSTDocument.needs_shutdown_attention`) and Godot 4.4 `editor_node.cpp:3071` re-gates the quit with `p_confirmed = false` after `save_external_data()` (phase 7, Multiple shader tabs)

## Deferred review notes

Written by the review relay at the commit gate, one line per Deferred note the phase-reviewer
chose not to fix this phase (pending external API, plan-blessed placeholder, later-phase consumer).
A deferred note is not a dropped note - it lives here until someone clears it. Retire a line when
the work lands or the reason expires; `/claudhd:audit` prunes stale ones.
Format: `- [ ] <note, with file:line>: <why deferred> (phase N, <feature or plan name>)`.

- [x] README.md must state the `godot --headless --path . --import` prerequisite before the test command (docs/PLAN.md phase 8 README entry): resolved phase 8, `README.md` Tests section states the import prerequisite before every test command (phase 1, GoShade Turbo v0.1)
- [x] cellular_edges.tres description says bright boundaries, code returns F2 - F1 which is dark at boundaries (addons/goshade_turbo/library/generative/cellular_edges.tres:9 and :38): resolved phase 8, code now returns `1.0 - smoothstep(0.0, width, F2 - F1)` with a new `width` param, so the field reads 1.0 at boundaries and falls off inside, matching the description (phase 2, GoShade Turbo v0.1)
- [ ] tests/run_render_checks.gd:38: the codex phase-reviewer sandbox has no GPU and crashes the rendered command with signal 11; the orchestrator's GPU runs on 4.4, 4.6.2, 4.7 are the evidence (docs/EDITOR_SMOKE.md "Version matrix, final phase 8 tree"). Clears when a GPU-capable reviewer environment exists (phase 8, GoShade Turbo v0.1)
- [ ] docs/EDITOR_SMOKE.md:2413: independent reviewer runs reproduced the documented sandbox cache/settings errors despite passing phase assertions; repeat stderr verification when the reviewer environment permits those writes, during the phase 2 native-editor verification: reviewer sandbox limitation, not a proof defect (phase 1, Multiple shader tabs, review round 5)
- [ ] docs/EDITOR_SMOKE.md (phase 2 evidence): record the reviewer's `Failed to read the root certificate store` diagnostic alongside phase 2 verification evidence; isolated settings did not eliminate it and the run cannot establish error-free engine startup: phase 8 review round 1 (fix 12) un-ticks this. Phase 8's own matrix pass recorded `0` occurrences across its own `4.4`/`4.6.2`/`4.7` runs, but the round-1 reviewer's own `4.7` `tabs_native` run emitted `ERROR: Failed to read the root certificate store`, reproducing the original diagnostic on that reviewer's own machine profile. This is environment-dependent (isolated `APPDATA`/`LOCALAPPDATA` eliminates it in the orchestrator's own environment, confirmed again this pass across every `tabs_recovery`/`tabs_native` run below with `0` occurrences), not resolved outright; remains open until a run in the affected profile itself shows `0` occurrences (phase 2, Multiple shader tabs, review round 4; reproduced again in phase 3 review rounds 2 and 3; reproduced on the phase 8 round-1 reviewer's own machine)
- [x] docs/SHADER_TABS_reviewed-plan.md:145: the reviewer's 4.6.2 launcher started overlapping processes and did not capture individual exit codes; all seven assertion summaries passed. Repeat serial verification with per-process exit capture during phase 8 (phase 2, Multiple shader tabs, review round 5): resolved phase 8, every selector on every version ran as its own serial process with its own captured exit code (docs/EDITOR_SMOKE.md "Shader tabs phase 8" matrix table)
- [x] addons/goshade_turbo/ui/gst_main_panel.gd:1384: `hide_export_dialog()` hides the dialog without clearing `_pending_export`, so each caller must clear it (the leak patched at tests/gst_editor_smoke.gd:1029); move the clear into `hide_export_dialog()`: resolved phase 6, `hide_export_dialog(abandon: bool = true)` now clears `_pending_export` itself by default; the one caller shape needing the request to survive (`_run_export_second_confirmation`) opts out with `abandon=false` (phase 5, Multiple shader tabs, review round 1)
- [x] addons/goshade_turbo/ui/gst_main_panel.gd:1570 and :1621: a closed-target Save As/Export response returns `{ok:false, reason:"This document is no longer open."}` and the `*_file_selected` handlers discard it, so the user sees no feedback: resolved phase 6, both handlers now surface that reason through `_set_operation_message` onto whichever document is active (phase 5, Multiple shader tabs, review round 1)
- [ ] addons/goshade_turbo/ui/gst_main_panel.gd:1462: `_finish_pending_edits()` cannot be awaited from the void `_save_external_data()` virtual, so an open native color popup's final value can commit after the recovery record is written (gst_inspector_column.gd:189 awaits the deferred close); reachable only by quitting with a color popup open: observed at phase 8 cross-version lifecycle verification (production unchanged, no fix applied). A one-off scripted probe (docs/EDITOR_SMOKE.md "Shader tabs phase 8", verification scratch only, never committed) left a native color popup's hex field mid-edit (typed, uncommitted) and drove a real confirmed Save and Quit on `4.4`, `4.6.2`, and `4.7`: the recovery record's stored value in all three cases was the pending typed color (`Vector3(0.333333, 0.4, 0.933333)`, i.e. `#5566ee`), not the pre-edit original (`0.5, 0.5, 0.5`) -- the pending edit committed before the recovery write completed in every run observed. No synchronous close path is needed based on this evidence; only one interaction pattern (a single untitled document, one popup, no other pending edits) was probed. Un-ticked at review round 5 fix-now: this round's own production edits (`gst_inspector_column.gd`'s stray-echo scoping and comment trims) touch neither `_save_external_data()` nor this recovery-write race, so the gap is unchanged and a broader probe (multiple documents, mixed pending edits) remains open (phase 7, Multiple shader tabs, review round 1; un-ticked phase 8 review round 5)
- [ ] docs/SHADER_TABS_reviewed.md:25: amend decision 10's `_get_unsaved_status` wording and its veto claim to match the engine's `p_confirmed = false` re-check: waits on the design-doc pass at phase 8 sign-off (phase 7, Multiple shader tabs, review round 1). Evidence phase 8 leaves for that pass: docs/EDITOR_SMOKE.md "Shader tabs phase 8" `tabs_recovery` two-stage runs on `4.4`/`4.6.2`/`4.7`, all showing the same `_get_unsaved_status`/`p_confirmed = false` re-check behavior this line already names.
- [x] docs/EDITOR_SMOKE.md:3676: the round 6 reviewer launcher retained only stage 2's exit code for the two-stage tabs_recovery run; during phase 8's verification retain both stage exit codes and recheck the certificate-store diagnostic (phase 7, Multiple shader tabs, review round 6): resolved phase 8, both `tabs_recovery` stage exit codes captured and recorded on all three versions (stage 1 and stage 2 each exit `0` on `4.4`/`4.6.2`/`4.7`; reconfirmed again in phase 8 review round 1's own fix-10 reruns). Certificate-store diagnostic rechecked, `0` occurrences in the orchestrator's own environment across all six two-stage processes both times -- but see the un-ticked line above: it is environment-dependent, not universally resolved.

## Rule of thumb
- Roadmap says what to do next.
- Plans say how to do it.
- Design says why it exists and what constraints it obeys.
- Archive says what happened.
- Memory says what must not be forgotten.
