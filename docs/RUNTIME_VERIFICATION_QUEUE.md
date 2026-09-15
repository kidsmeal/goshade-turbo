# Runtime Verification Queue

Last updated: 2026-09-15

The live list of systems that are code-complete or mostly shipped but still need real-run
confidence. Keep code/test facts separate from the manual check still owed, so stale TODOs
are easy to retire. Curate with `/claudhd:audit`.

---

## Active checks

### 1. Shader tabs in a real editing session (multi-document, human input)

**Why:** every phase 2 to 8 proof is a scripted editor run with synthetic input in an isolated project. Real OS input, a real user project with existing scenes, and the user's own editor settings have not been exercised by a person.

**Code checks already done:**
- `tabs_native`, `tabs_documents`, `tabs_ui`, `tabs_files`, `tabs_close`, `tabs_host`, and two-stage `tabs_recovery` pass on 4.4, 4.6.2, 4.7 (`docs/EDITOR_SMOKE.md` "Shader tabs phase 8" through "review round 5 fix-now").
- Real confirmed Save and Quit plus fresh reopen restoration proven per version by the two-stage protocol.

**Manual check:**
- In your own project on 4.6.2 or 4.7: open two recipes and one saved stack as tabs, edit a color via the native popup on tab A, switch to tab B, press Ctrl+Z on B. Pass: only B's history moves; A's color is unchanged when you return.
- With tab A dirty and untitled, quit the editor and choose Save and Quit. Pass: the quit completes; reopening shows A as a dirty Untitled tab with the edit intact, and `.godot/editor/goshade_turbo/recovery/` holds one record until you Save or Discard it.
- Close a dirty tab with its x, choose Cancel, then Discard. Pass: Cancel keeps the tab and its dirty star; Discard removes only that tab and Ctrl+Z cannot bring it back.

**Close when:** all three pass once on a human-driven session on 4.6.2 or 4.7 and the result is recorded in `docs/EDITOR_SMOKE.md`. If the quit was done with a color popup open, the `_save_external_data` deferred note in `docs/CURRENTNESS_AUDIT.md` closes too.

---

### 2. Slider tuning pass (v0.1 release checklist, `docs/DESIGN.md:159`)

**Why:** the only open release checklist item; a perception check no test can make.

**Code checks already done:**
- Every library block's params have ranges and defaults exercised by `tests/run_codegen_tests.gd` (21 baseline failures on ROADMAP.md excepted) and rendered by `tests/run_render_checks.gd` (81 stacks) on both renderers.
- `generative/cell_borders` (quick fix `6980a5a`) has no sandbox reference stack yet; `cellular_edges` now returns raw F2 - F1 and expects a downstream `smoothstep` or `band`.

**Manual check:**
- For each block in the picker, drag every slider end to end on the default preview image. Pass: a visible change across the whole range, no dead zone longer than a quarter of the range.
- Re-check `cellular_edges` followed by `band`, and `cell_borders` alone. Pass: edges visible at default params without hand-typing values.

**Close when:** the user ticks `docs/DESIGN.md:159` and files any dead-range blocks as quick fixes or ideas.

---

### 3. `generative/cell_borders` reference stack

**Why:** the block compiles and renders in the 81-stack run only through generic per-entry coverage; no `sandbox/stacks` reference exists, so a visual regression would go unnoticed.

**Code checks already done:**
- `addons/goshade_turbo/library/generative/cell_borders.tres` compiles alone (per-entry test in `tests/run_codegen_tests.gd`), MIT `source_code_license` set, iq bisector attribution in the description.

**Manual check:**
- Add a `sandbox/stacks/cell_borders.tres` stack (cell_borders into band or smoothstep), run `tests/run_render_checks.gd --write-screenshots` once, inspect the PNG. Pass: thin uniform-width borders around Voronoi cells, no seams at grid boundaries.

**Close when:** the reference PNG is committed and the render run reports 82 stacks.

---

### 4. Recovery Mode prompt after test runs

**Why:** `godot --headless --path . --import` (README.md Tests prerequisite) leaves `.recovery_mode_lock` in the user data dir on Godot 4.4/4.6 (`main/main.cpp` `create_lock_file`, removed only 1s after the editor's first filesystem scan via `EditorNode::_sources_changed`; an `--import` run quits before that timer fires, and 4.4/4.6 also skip the `Main::cleanup()` removal 4.7 added). The next Project Manager launch then offers Recovery Mode on a project that never crashed.

**Code checks already done:**
- `tests/run_codegen_tests.gd`, `tests/run_render_checks.gd`, `tests/run_recipe_motion_checks.gd` each remove a stale `.recovery_mode_lock` at wrapper start and again before quit, printing one line when removed (2026-09-15 fix).
- README.md Tests section documents the lock and the manual delete path per OS.

**Manual check:**
- Run the README import step, then the unit wrapper, on 4.4. Then open the project from the Project Manager. Pass: no Recovery Mode prompt.

**Close when:** the user confirms no prompt on their next session.

---

## Closed / stale items

- Sandbox `clouds.tres` picked up by render checks (NOW.md loose end): closed, phase 8 render runs report 79, then 81 stacks on all versions.
- Both `tabs_recovery` stage exit codes captured: closed, recorded per version in `docs/EDITOR_SMOKE.md` phase 8 sections.
