# ROADMAP

The committed, ordered lane between IDEAS.md (someday, unsorted) and NOW.md (the one active thread). It holds what you have decided to do and roughly in what order, before any of it becomes the live cursor.

One cursor still rules: this file orders many intents, NOW.md points at exactly one. The roadmap is the order, not a second active thread. Add to it with `/claudhd:roadmap <intent>`; activation stays one-at-a-time through triage and NOW.md.

Every item in Next/Later/Shipped/Non-goals carries a stable, generated `r-MMDD-N` id, rendered beside its text (design section 4) - never typed from memory, never reused, checkbox or plain-bullet wording alike. Ids are backfilled onto any id-less line in those sections during init/reconcile without touching its wording (the placeholder lines below are deliberately id-less until that backfill runs, so they never carry a stale example date). `## Now` is not an item list - it is the live cursor's pointer, so its bullet is left untouched no matter what it says. The active thread declares its parent with NOW.md's `from: <id>` link, so unplanned work and stale commitments are both mechanically checkable.

## Now

The intent the active thread is currently serving (usually one, sometimes none). NOW.md holds the actual step-by-step; this is just the roadmap's pointer at what is live - it echoes whichever item below is active (same id, no id of its own), or says nothing is in flight.

- GoShade Turbo v0.2 (design mode, grilling `docs/V0_2_DESIGN.md`) `r-0916-1`

## Next

Committed and ordered, on-deck after Now. Each is a real intent you mean to build, not a someday-maybe. Carry a one-line "done" so it is ready to activate when its turn comes, not re-litigated.

- [x] Fix the 20 pre-existing `tests/run_codegen_tests.gd` unit failures (`generative/clock` shader compile error plus library-index counts); overruled out of shader tabs phase 8 review round 1 as plan-external baseline - done: `GST tests: 21 file(s), 145 test method(s), 0 failure(s)` on 4.4, 4.6.2, 4.7 (2026-09-15); `run_render_checks: PASS, 81 stack(s) checked` on 4.4 Compatibility; see `docs/EDITOR_SMOKE.md` "Unit failures fixed 2026-09-15" `r-0914-1`
- [ ] GoShade Turbo v0.2 - one schema bump carrying layer ops (duplicate, rename, bypass), texture param plus `source/image`, param links (base plus amount, decisions 29 and 30), `custom` layer with save-as-library-entry, user recipes folder - done: `docs/V0_2_DESIGN.md` release checklist all ticked `r-0916-1`

## Later

Committed but not soon. Things you know you will do, just not next. Promote to Next when they get close.

- [ ] (a known-but-not-soon intent) `r-0907-2`

## Shipped

Delivered, newest first. Move an intent here when its work lands, with a one-line note of what shipped.

- GoShade Turbo v0.1 - release checklist in `docs/DESIGN.md` all ticked 2026-09-20; tag v0.1.0 at 85c2762, GitHub release with goshade_turbo-0.1.0.zip `r-0907-1`
- (most recent shipped intent) `r-0907-3`

## Non-goals (decided, not "later")

Directions you have deliberately chosen not to take, each with the one-line why, so they stop coming back as ideas.

- (a deliberately-killed direction) - why: (one line) `r-0907-4`
