# NOW (read me first)

<!-- claudhd: opt-in marker (do not remove) - ClauDHD's hooks only act on a NOW.md that has this line -->

One active thread at a time. This file is the cursor: what is live, the next physical action, and what is queued behind it. Read it first, update it as you go.

_Committed, so it follows your branch: `git checkout` swaps this cursor to that branch's thread._

This file is generated (design section 4): the facts below (Mode, Position, from, Counts, Last touched) render from `.now/state.json`, never hand-typed. The Active thread's two lines are the one piece of human prose, prompted at boundaries and persisted as state fields too - so it survives a regeneration without ever being parsed back out of this file.

Mode: build
Position: phase 1 of docs/SHADER_TABS_reviewed-plan.md
from: (unplanned work)
Counts: queue 0 · quick fixes 0 · ideas untriaged 9

Last touched: 2026-09-10

## Active thread (only one)

**Paused: multiple shader tabs**

Next physical action:

- [ ] Wait for user to resume; then verify the partial phase 1 review fixes and request independent re-review

Rule: when you finish a step, check it off and write the next single tiny step. Do not start another thread until this one ships or you consciously commit the next one to the roadmap (`/claudhd:roadmap <intent>`) and activate it in its turn (`/claudhd:start <id>`).

Keep this section lean (about 40 lines): a summary, the live state, and the next action, not a running shipped log. Move settled material out as you go: shipped work to SHIPPED.md, parked or future material to ROADMAP.md or IDEAS.md.

## Queue (in order, not now)

What is eligible to become active next, in order. The readiness gate lives at activation, not before: `/claudhd:start <id>` is what turns a committed ROADMAP.md intent into something concrete (restated, done + first action) and enters it into design. Nothing here queues as a bare one-liner.

(nothing queued yet)

## Quick fixes (clear in one pass)

Small, self-contained chores that need no plan and aren't worth their own thread. Capped at 3 - overflow means clear some or promote one out, so this stays a batch and never a second backlog. Add with `/claudhd:quick <text>`, clear them in one focused pass with `/claudhd:quick`. The active thread has right of way: clear these between threads, not mid-thread. A fix that turns out to need real thinking gets kicked back to IDEAS.md.

(nothing queued yet)

## Idea flow (do not open a new chat)

New idea mid-task: `/claudhd:idea <text>` records it in IDEAS.md so you can keep working. `/claudhd:harvest` backfills ideas from past sessions you never recorded. `/claudhd:triage` clears the inbox. Finished work lands in SHIPPED.md automatically at the commit boundary.

## Loose ends

- Astra reviewer measurement (user decision 2026-09-09): `.gantry/models.json` routes design-reviewer and phase-reviewer to codex `gpt-6-astra`; implementer and planner stay native. Protocol: record the Codex weekly allowance percentage before the next plan's first review and after its last, and sum reviewer tokens from `~/.codex/sessions` for the same window. Decide the ChatGPT tier on that delta.
- Release checklist: one item open, `docs/DESIGN.md` line 155 (user tuning pass). All other items ticked with evidence.
- Picker text slicing (`docs/EDITOR_SMOKE.md` "Intermittent picker text slicing"): unresolved, not reproduced in three fresh-editor runs. Next repro step recorded there.
- `sandbox/stacks/clouds.tres` (moved from repo root in `017b936`) is now picked up by `tests/run_render_checks.gd`; next GPU render run reports 79 stacks, not 78, and needs `--write-screenshots` for its reference PNG.
- ClauDHD enforcement opted in 2026-09-09 (`.now/enabled`): the commit-boundary reconcile and, from plugin 1.0.11 after a restart, the post-commit verify now run here. Any plan may be granted `thread.js commit-policy auto <plan>` to commit phases without asking; push stays manual.
- `docs/CURRENTNESS_AUDIT.md` and `docs/RUNTIME_VERIFICATION_QUEUE.md` still carry `<DATE>` template placeholders; the audit's deferred-notes list is real, the rest is scaffold.
- `docs/CURRENTNESS_AUDIT.md` deferred note: `tests/run_render_checks.gd` cannot run in the GPU-less reviewer sandbox. Clears when a GPU reviewer exists.
- Running `godot --import` on a newer Godot than 4.4 rewrites `sandbox/screenshots/glow.png.import`. Restore it before committing.

## Leaving this file when you stop

Before you walk away, or whenever you switch context, make the "Next physical action" line true and tiny. That one line is what lets you stop mid-thought and lose nothing. The rest of this file regenerates itself at every commit; only the Active thread's two lines are yours to keep current.
