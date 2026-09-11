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
- [ ] docs/EDITOR_SMOKE.md (phase 2 evidence): record the reviewer's `Failed to read the root certificate store` diagnostic alongside phase 2 verification evidence; isolated settings did not eliminate it and the run cannot establish error-free engine startup: recheck during phase 8's supported-environment matrix (phase 2, Multiple shader tabs, review round 4)
- [ ] docs/SHADER_TABS_reviewed-plan.md:145: the reviewer's 4.6.2 launcher started overlapping processes and did not capture individual exit codes; all seven assertion summaries passed. Repeat serial verification with per-process exit capture during phase 8 (phase 2, Multiple shader tabs, review round 5)

## Rule of thumb
- Roadmap says what to do next.
- Plans say how to do it.
- Design says why it exists and what constraints it obeys.
- Archive says what happened.
- Memory says what must not be forgotten.
