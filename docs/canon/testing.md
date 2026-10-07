# Testing

Commands: `docs/TESTING.md`.

## Setup
- Run `godot --headless --path . --import` once per clone and after adding any `class_name` script. Without it `-s` runs fail with `Parse error`. (`docs/TESTING.md`, `PLAN.md` verified engine facts)
- Import on `4.4` and `4.6` leaves `.recovery_mode_lock`; run with an isolated `APPDATA` and `LOCALAPPDATA`. (`docs/TESTING.md`)

## Headless codegen and unit tests
- Runner: `tests/run_codegen_tests.gd`. (`docs/TESTING.md`)
- The wrapper fails on a nonzero child exit or output containing `SCRIPT ERROR`, `ERROR:` or `Parse error`. (`tests/run_codegen_tests.gd:9`)
- Test files are `tests/test_*.gd`; test methods are `test_*`. (`tests/gst_test_runner.gd:3`)
- Assertions come from `tests/gst_test_base.gd`. (`PLAN.md` phase 1)
- Every generated shader in a test is compiled, not only text-compared. (`PLAN.md` phase 2 verification)
- The headless dummy driver compiles shaders: `Shader.get_shader_uniform_list().size()` is `0` on a failed compile. (`PLAN.md` verified engine facts)
- Golden-text assertions depend on `GSTUniformNames`; a naming change breaks them. (`PLAN.md cross-cutting`)

## Rendered checks
- Runner: `tests/run_render_checks.gd`, needs a GPU and display session. `--headless` cannot read back pixels. (`docs/TESTING.md`, `PLAN.md` verified engine facts)
- Pass criteria per stack: no NaN or inf pixel, alpha within `[0, 1]`, output not uniformly one value. (`DESIGN.md` release checklist, `tests/gst_render_assert.gd`)
- Covers every reference stack and every recipe. (`DESIGN.md` release checklist)
- `-- --write-screenshots` writes `sandbox/screenshots/<stack>.png`, gitignored. (`docs/TESTING.md`)
- Recipe motion checks run at `1`, `30` and `120` seconds: `tests/run_recipe_motion_checks.gd`. (`docs/TESTING.md`)

## Coverage rules
- Combination tests: every field op with every generator input compiles; every color op with every color entry input compiles. (`DESIGN.md` release checklist, `tests/test_combinations.gd`)
- Every roster entry compiles alone. (`DESIGN.md` release checklist)
- Randomized values stay inside manifest ranges. (`PLAN.md` phase 8, `tests/test_randomize_range.gd`)
- Save, reopen, export and re-codegen of a stack is byte-exact. (`PLAN.md` phase 6 and 7 exit criteria)
- Undo coverage includes add, remove, reorder, slot change, output change. (`DESIGN.md` release checklist)

## Editor smoke
- `tests/gst_editor_smoke.gd` runs in a real editor when `GST_EDITOR_SMOKE` is set and prints `SMOKE <item> PASS|FAIL <detail>` lines. (`PLAN.md` phase 4 files)
- Results are appended to `docs/dev/EDITOR_SMOKE.md`. (`PLAN.md` phase 4 files)

## Version matrix
- Tests run on Godot `4.4`, `4.6` and `4.7`. (`DESIGN.md d17`, `DESIGN.md` release checklist)
- After a `4.7` run, `git status` shows no manifest churn. (`PLAN.md B2`)

## Device check
- Android device check renders exported recipes and reference shaders on a phone and logs `MOBILE <name> PASS|FAIL`. (`docs/TESTING.md` Device check)
