# Editor smoke results

Current UI redesign evidence is recorded in the final `Editor UI redesign` sections. Earlier sections describe the original phase 4 through 8 implementation.

Per-phase record of `tests/gst_editor_smoke.gd` runs (docs/PLAN.md Phase 4
Files). Method: `$env:GST_EDITOR_SMOKE="4"; godot --editor --path .`,
captured stdout, `config/features` in `project.godot` reset to `"4.4"`
afterward (the 4.6.2 editor rewrites it to `"4.6"` on every run, per
docs/PLAN.md Cross-cutting concern "`project.godot` `config/features`
churn").

## Phase 4 (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

### Run 1: fail, root cause identified

`gst_undo.gd` called `EditorUndoRedoManager.create_action(name)` with no
`custom_context`. Verified on this build: `create_action()` with no context
does not land every action in one stable global bucket. Only the most
recently created action (`set_output_color`) ended up in the history that
`get_object_history_id(stack)` resolved to; the three earlier actions (add
fbm, add invert, wire the slot) landed elsewhere and were unreachable from
that history. Evidence: `history.has_undo()` was already `false` after 2 of
the planned 4 undo calls, and the two mid-sequence assertions failed because
nothing had actually been reverted.

```
SMOKE 1 PASS panel present
SMOKE 1 PASS panel.visible after set_main_screen_editor=true
SMOKE 2a PASS fbm=():<Resource#-9223370420822932114> invert=():<Resource#-9223370413558396664>
SMOKE 2b PASS wire invert.x -> fbm:
SMOKE 2c PASS reorder fbm above invert refused=true reason=layer 1 references layer 0, which would be at or above it after this move
SMOKE 3 PASS set output color to invert:
SMOKE 4a PASS output_color after undo 1: '' (expect empty)
SMOKE 4b FAIL invert.slots['x'] after undo 2: '0' (expect empty)
SMOKE 4c FAIL invert gone=false row_count=2 (expect gone, 1 row)
SMOKE 4d FAIL fbm gone=false row_count=2 (expect gone, 0 rows)
SMOKE 4e PASS history.has_undo() after 4 undos: false (expect false, reorder in 2c was refused and registered no action)
SMOKE 5a PASS open_for_slot(FIELD) listed 23 entries, all field kind=true
SMOKE 5b PASS search 'fbm' visible=["generative/fbm"] (expect ['generative/fbm'])
SMOKE 6 PASS codegen of two-layer stack: error='' code_len=1803
SMOKE SUMMARY pass=11 fail=3
```

Fix: every `create_action()` call in `gst_undo.gd` now passes
`custom_context = _stack` explicitly, via a shared `_create_action(name)`
helper. This forces every GST action onto one deterministic history keyed
by the open `GSTStack` resource, matching what
`EditorUndoRedoManager.get_object_history_id(stack)` resolves to regardless
of call order or what the editor's own inspector last showed.

### Run 2: pass, after the `custom_context` fix (pre-amendment verification)

Ran against the phase 4 Verification wording as it stood before the
orchestrator's second amendment (3 layers, one reorder attempted directly
through `GSTUndo`, 4 actions/4 undos). Superseded by Run 3 below, which
re-runs the amended script (adds a third layer, a real reorder through
`GSTUndo` plus a refusal through the stack list's own button handler, the
output-block default-text check, and 6 actions/6 undos). Kept for the
history of the `custom_context` fix's verification.

```
SMOKE 1 PASS panel present
SMOKE 1 PASS panel.visible after set_main_screen_editor=true
SMOKE 2a PASS fbm=():<Resource#-9223370420806154395> invert=():<Resource#-9223370413541619448>
SMOKE 2b PASS wire invert.x -> fbm:
SMOKE 2c PASS reorder fbm above invert refused=true reason=layer 1 references layer 0, which would be at or above it after this move
SMOKE 3 PASS set output color to invert:
SMOKE 4a PASS output_color after undo 1: '' (expect empty)
SMOKE 4b PASS invert.slots['x'] after undo 2: '' (expect empty)
SMOKE 4c PASS invert gone=true row_count=1 (expect gone, 1 row)
SMOKE 4d PASS fbm gone=true row_count=0 (expect gone, 0 rows)
SMOKE 4e PASS history.has_undo() after 4 undos: false (expect false, reorder in 2c was refused and registered no action)
SMOKE 5a PASS open_for_slot(FIELD) listed 23 entries, all field kind=true
SMOKE 5b PASS search 'fbm' visible=["generative/fbm"] (expect ['generative/fbm'])
SMOKE 6 PASS codegen of two-layer stack: error='' code_len=1803
SMOKE SUMMARY pass=14 fail=0
```

### Run 3: pass, second amendment (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Amended `tests/gst_editor_smoke.gd` to cover: a third layer (`generative/hash`);
a hash reorder one position down through the same `GSTUndo` call the stack
list's Down button uses (allowed, hash references nothing); an attempt to
move `fbm` above `invert` through the stack list's actual Up button handler
(`_on_up_pressed`, not `GSTUndo` directly), asserting the panel's message
label contains the refusal reason and the layer order is unchanged; the
output-block default-text check (item 7) run right after the three adds,
before any color layer or explicit output_alpha exists; and 6 undos (add
fbm, add invert, add hash, wire the slot, reorder hash, set output color)
instead of 4, since the up-press attempt is refused and registers no undo
action, same as the prior reorder attempt.

The up-press refusal check runs before the hash-down reorder: `fbm` and
`invert` are adjacent immediately after the three adds (`fbm`@0, `invert`@1,
`hash`@2), so a single Up step swaps them directly and decision 22's
forward-reference check refuses it. Moving hash down first would insert it
between `fbm` and `invert`, and a single Up step on `fbm` would then only
reach `hash`'s old slot without crossing `invert`, never triggering the
refusal. Running the (non-mutating) refusal attempt first, then the hash
move, keeps both assertions true without fabricating either one.

Command run via a `Start-Process -RedirectStandardOutput/-RedirectStandardError`
PowerShell wrapper rather than a plain `&` invocation and pipe: the editor
process's console handles were not reliably inherited by a plain pipe
redirect in this environment (the wrapped invocation returned before the
real editor window's output ever printed). `Start-Process` with explicit
redirected file handles captured the process end to end.

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE 1 PASS panel present
SMOKE 1 PASS panel.visible after set_main_screen_editor=true
SMOKE 2a PASS fbm=():<Resource#-9223370420655159954> invert=():<Resource#-9223370413390624500> hash=():<Resource#-9223370406998505188>
SMOKE 7 PASS after the adds, before any output-block or color-layer state exists: color option='(none)' alpha option='(default) none' (expect '(none)' and '(default) none')
SMOKE 2b PASS wire invert.x -> fbm: 
SMOKE 2c PASS up-press fbm above invert message='layer 1 references layer 0, which would be at or above it after this move' order_unchanged=true
SMOKE 2d PASS hash move down: ok=true index 2 -> 1
SMOKE 3 PASS set output color to invert: 
SMOKE 4a PASS output_color after undo 1: '' (expect empty), row_count=3 (expect 3)
SMOKE 4b PASS hash index after undo 2: 2 (expect original 2), row_count=3 (expect 3)
SMOKE 4c PASS invert.slots['x'] after undo 3: '' (expect empty), row_count=3 (expect 3)
SMOKE 4d PASS hash gone=true row_count=2 (expect gone, 2 rows)
SMOKE 4e PASS invert gone=true row_count=1 (expect gone, 1 row)
SMOKE 4f PASS fbm gone=true row_count=0 (expect gone, 0 rows)
SMOKE 4g PASS history.has_undo() after 6 undos: false (expect false, up-press in 2c was refused and registered no action)
SMOKE 5a PASS open_for_slot(FIELD) listed 23 entries, all field kind=true
SMOKE 5b PASS search 'fbm' visible=["generative/fbm"] (expect ['generative/fbm'])
SMOKE 6 PASS codegen of two-layer stack: error='' code_len=1803
SMOKE SUMMARY pass=18 fail=0
```

stderr: empty.

### Deviation from docs/PLAN.md Phase 4 Verification wording

The plan's original Verification section describes five undo steps ("the
output change, the slot change, the reorder, the second add, and the first
add"). Run 3 above follows the second amendment: a refused up-press through
the button handler plus a real hash reorder through `GSTUndo` replace the
single ambiguous "reorder" step, giving 6 real actions (3 adds, 1 wire, 1
reorder, 1 output-color set) and 6 undos, not 5. All 6 revert correctly and
`history.has_undo()` is `false` afterward, confirmed rather than a 7th call
being fabricated against empty history. Items 4a-4g above cover the 6 real
reverts plus the exhausted-history check, matching what the amended plan
actually asks the smoke script to exercise.

### Run 4: pass, phase-reviewer fix pass (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Run 3 passed but the phase reviewer failed the phase on process grounds:
`set_output_color`/`set_output_alpha` registered an `EditorUndoRedoManager`
action via `commit_action(false)` without ever applying the mutation first
(the do methods only fire on redo, never on the initial `commit_action(false)`
commit), so the initial output edits silently no-opped; nothing asserted the
applied value before undo, so Run 3 never caught it. `GSTMainPanel.stack_changed`
had the same gap for every structural edit's initial commit, not only output.
A same-index reorder registered an undo action for a no-op move. The picker
kind-filter check called `GSTPicker.open_for_slot()` directly instead of
through a real UI control, and no button routed to it. `gst_editor_smoke.gd`
was missing `@tool`.

Fixes: every `GSTUndo` front-door method now applies its mutation directly
(already true for add/remove/reorder/assign_slot/assign_warp; extended to
`set_output_color`/`set_output_alpha`) and then calls `_notify()` once
directly after `commit_action(false)`, since `commit_action(false)` never
invokes the registered do methods on the initial commit. `reorder_layer`
now returns early without creating an action when the target index resolves
to the layer's current index. The inspector column gained a per-slot "Add
for slot" button that calls `GSTPicker.open_for_slot()` and, on
`entry_picked`, adds the new layer directly below the anchor layer and wires
the slot in one compound `GSTUndo` action (`GSTUndo.add_layer_below_and_wire`).
`gst_editor_smoke.gd` gained `@tool`.

`gst_editor_smoke.gd` rewritten to: assert `stack.output_color` /
`stack.output_alpha` applied immediately after each set call, before any
undo; drive the new "Add for slot" button instead of calling the picker
directly, asserting the picker lists field-kind entries only, the search box
filters within that set, the picked layer lands directly below the anchor
with the slot wired, and undoing the compound action clears both; assert a
top-of-stack boundary reorder registers no undo action
(`history.get_history_count()` unchanged); add positive checks that adding
`color/fill` and `source/texture` through the panel flips the output block's
default text to `(default) l<id> fill` / `(default) texture`, and that
undoing both reverts it to `(none)` / `(default) none`. The two excursions
(color/alpha defaults, add-for-slot) are undone in place before the real
wiring/reorder/output steps run; each is truncated from
`EditorUndoRedoManager`'s redo tail by the next real action committed after
it (verified directly against a bare `UndoRedo` instance: committing a new
action while a prior undo has pending redo drops the pending redo from
`get_history_count()`), so the persistent action count is 7, not 9: 3 adds,
1 wire, 1 reorder, output color, output alpha (was 6 in Run 3, +1 for the
newly-asserted output alpha action).

Command run the same way as Run 3 (`Start-Process` with redirected stdout
and stderr, 180s timeout).

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE 1 PASS panel present
SMOKE 1 PASS panel.visible after set_main_screen_editor=true
SMOKE 2 PASS fbm=():<Resource#-9223370419044546659> invert=():<Resource#-9223370411511576252> hash=():<Resource#-9223370403575952999>
SMOKE 3 PASS after the adds, before any output-block or color-layer state exists: color option='(none)' alpha option='(default) none' (expect '(none)' and '(default) none')
SMOKE 4a PASS color default after adding fill: '(default) l3 fill' (expect '(default) l3 fill')
SMOKE 4b PASS alpha default after adding texture: '(default) texture' (expect '(default) texture')
SMOKE 4c PASS alpha default after undoing texture add: '(default) none' (expect '(default) none')
SMOKE 4d PASS color default after undoing fill add: '(none)' (expect '(none)')
SMOKE 5a PASS add-for-slot picker listed 23 entries, all field kind=true
SMOKE 5b PASS search 'checker' visible=["generative/checker"] (expect ['generative/checker'])
SMOKE 5c PASS picked generative/checker: placed_below=true slot_wired=true count 3 -> 4
SMOKE 5d PASS undo add-for-slot: invert.slots['x']='' (expect empty), count=3 (expect 3)
SMOKE 6 PASS wire invert.x -> fbm: 
SMOKE 7 PASS up-press fbm above invert message='layer 1 references layer 0, which would be at or above it after this move' order_unchanged=true
SMOKE 8 PASS hash move down: ok=true index 2 -> 1
SMOKE 9 PASS boundary move at top: ok=true history_count 5 -> 5 (expect unchanged)
SMOKE 10 PASS set output color to invert: ok=true applied='1' (expect '1')
SMOKE 11 PASS set output alpha to none: ok=true applied='none' selected_text='none' (expect 'none')
SMOKE 12a PASS output_alpha after undo 1: '' (expect empty), row_count=3 (expect 3)
SMOKE 12b PASS output_color after undo 2: '' (expect empty), row_count=3 (expect 3)
SMOKE 12c PASS hash index after undo 3: 2 (expect original 2), row_count=3 (expect 3)
SMOKE 12d PASS invert.slots['x'] after undo 4: '' (expect empty), row_count=3 (expect 3)
SMOKE 12e PASS hash gone=true row_count=2 (expect gone, 2 rows)
SMOKE 12f PASS invert gone=true row_count=1 (expect gone, 1 row)
SMOKE 12g PASS fbm gone=true row_count=0 (expect gone, 0 rows)
SMOKE 12h PASS history.has_undo() after 7 undos: false (expect false)
SMOKE 13 PASS codegen of two-layer stack: error='' code_len=1803
SMOKE SUMMARY pass=27 fail=0
```

stderr: empty.

### Run 5: pass, phase-reviewer fix pass 2 (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Second review round failed on: `_property_type_for` had no `"vec3"` case,
so `color/palette`'s real `a`/`b`/`c`/`d` params (declared `"vec3"` in
`palette.tres`) fell through to `TYPE_FLOAT` in the inspector; `remove_layer`
never cleared a deleted layer's id out of `stack.output_color` /
`stack.output_alpha`, leaving a dangling reference codegen could not
resolve; `gst_inspector_column.gd`'s `GSTPickerScene` constant did not match
the project's `UPPER_SNAKE_CASE` constant convention (`DEFAULT_ROOT` in
`gst_library.gd`); the output block's default row silently no-oped instead
of writing `&""` through `GSTUndo` (not undoable); a stale comment at
`tests/gst_editor_smoke.gd:189` claimed no `custom_context` was passed to
`create_action` when `gst_undo.gd`'s `_create_action` does pass one
(`_stack`).

Fixes: `gst_layer.gd::_property_type_for` now maps `"vec2"` -> `TYPE_VECTOR2`,
`"vec3"` -> `TYPE_VECTOR3`, and an unknown type string falls back to
`TYPE_FLOAT` with a `push_warning` naming the entry and param.
`gst_undo.gd::remove_layer` now also snapshots `output_color`/`output_alpha`,
clears a matching field to `&""` on removal (`_clear_output_refs`, called
from both the initial removal and `_redo_remove`), and restores both fields
on undo. `gst_undo.gd::set_output_alpha` now accepts `&""` as an explicit
reset value (previously only `"none"`/`"texture"`/`"color_alpha"`/a field
layer id were legal), needed so the output block's default row can write
`&""` through undo like any other pick; `gst_output_block.gd`'s
`_on_color_selected`/`_on_alpha_selected` now call
`_undo.set_output_color(&"")`/`_undo.set_output_alpha(&"")` when the default
row is picked, guarded to no-op (no undo action) when the field is already
`&""`. `GSTPickerScene` renamed to `PICKER_SCENE`. The stale comment at
`gst_editor_smoke.gd:189` corrected to describe `custom_context = _stack`
and why it keeps `get_object_history_id(stack)` stable.

`gst_editor_smoke.gd` gained: item 15 (`_run_palette_inspector_check`),
adding a real `color/palette` layer, asserting `get_property_list()` shows
four `TYPE_VECTOR3` properties named `a`/`b`/`c`/`d` and `layer.get("a")`
returns a `Vector3`, then undoing the add; items 11b/11c, driving the output
block's `_on_alpha_selected(0)` handler directly (same private-method
pattern as `stack_list._on_up_pressed()`) after an explicit `"none"` pick,
asserting `output_alpha` clears to `&""` and the history count grows by
one, then undoing it so the existing 7-action undo sequence below is
unaffected; item 14 (`_run_output_referenced_removal_excursion`), wiring a
fresh color layer to `output_color` and a fresh field layer to
`output_alpha`, removing each in turn, asserting the matching output field
clears to `&""` and `GSTCodegen.generate_result` still returns `ok()`, then
undo (field restored) and redo (cleared again) for both, fully unwound
afterward. `tests/test_library_index.gd` gained
`test_every_manifest_param_type_is_known`, asserting every real manifest
param's `"type"` string is one of `int`/`float`/`color`/`vec2`/`vec3`
(headless, `godot --headless --path . -s res://tests/run_codegen_tests.gd`,
included in the 91-test-method run below).

Command run the same way as Runs 3-4 (`Start-Process` with redirected
stdout/stderr via a `.ps1` wrapper, 180s timeout).

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE 1 PASS panel present
SMOKE 1 PASS panel.visible after set_main_screen_editor=true
SMOKE 2 PASS fbm=():<Resource#-9223370418776111203> invert=():<Resource#-9223370411243140796> hash=():<Resource#-9223370403307517543>
SMOKE 3 PASS after the adds, before any output-block or color-layer state exists: color option='(none)' alpha option='(default) none' (expect '(none)' and '(default) none')
SMOKE 15a PASS color/palette TYPE_VECTOR3 property names: ["a", "b", "c", "d"] (expect ["a", "b", "c", "d"])
SMOKE 15b PASS layer.get('a') type: 9 (expect Vector3)
SMOKE 15c PASS undo the palette add: layer gone=true
SMOKE 4a PASS color default after adding fill: '(default) l4 fill' (expect '(default) l4 fill')
SMOKE 4b PASS alpha default after adding texture: '(default) texture' (expect '(default) texture')
SMOKE 4c PASS alpha default after undoing texture add: '(default) none' (expect '(default) none')
SMOKE 4d PASS color default after undoing fill add: '(none)' (expect '(none)')
SMOKE 5a PASS add-for-slot picker listed 23 entries, all field kind=true
SMOKE 5b PASS search 'checker' visible=["generative/checker"] (expect ['generative/checker'])
SMOKE 5c PASS picked generative/checker: placed_below=true slot_wired=true count 3 -> 4
SMOKE 5d PASS undo add-for-slot: invert.slots['x']='' (expect empty), count=3 (expect 3)
SMOKE 6 PASS wire invert.x -> fbm: 
SMOKE 7 PASS up-press fbm above invert message='layer 1 references layer 0, which would be at or above it after this move' order_unchanged=true
SMOKE 8 PASS hash move down: ok=true index 2 -> 1
SMOKE 9 PASS boundary move at top: ok=true history_count 5 -> 5 (expect unchanged)
SMOKE 10 PASS set output color to invert: ok=true applied='1' (expect '1')
SMOKE 11 PASS set output alpha to none: ok=true applied='none' selected_text='none' (expect 'none')
SMOKE 11b PASS select default alpha row after explicit none: output_alpha='' (expect empty), history_count 7 -> 8 (expect +1)
SMOKE 11c PASS undo default-row pick restores explicit none: output_alpha='none' (expect 'none')
SMOKE 12a PASS output_alpha after undo 1: '' (expect empty), row_count=3 (expect 3)
SMOKE 12b PASS output_color after undo 2: '' (expect empty), row_count=3 (expect 3)
SMOKE 12c PASS hash index after undo 3: 2 (expect original 2), row_count=3 (expect 3)
SMOKE 12d PASS invert.slots['x'] after undo 4: '' (expect empty), row_count=3 (expect 3)
SMOKE 12e PASS hash gone=true row_count=2 (expect gone, 2 rows)
SMOKE 12f PASS invert gone=true row_count=1 (expect gone, 1 row)
SMOKE 12g PASS fbm gone=true row_count=0 (expect gone, 0 rows)
SMOKE 12h PASS history.has_undo() after 7 undos: false (expect false)
SMOKE 14a PASS wire output color=7 alpha=8
SMOKE 14b PASS remove output_alpha's layer: output_alpha='' (expect empty) codegen.ok=true error=''
SMOKE 14c PASS undo remove alpha layer: output_alpha='8' (expect '8'), layer present=true
SMOKE 14d PASS redo remove alpha layer: output_alpha='' (expect empty), layer present=false (expect false)
SMOKE 14e PASS remove output_color's layer: output_color='' (expect empty) codegen.ok=true error=''
SMOKE 14f PASS undo remove color layer: output_color='7' (expect '7'), layer present=true
SMOKE 14g PASS redo remove color layer: output_color='' (expect empty), layer present=false (expect false)
SMOKE 14h PASS excursion fully unwound: has_undo=false layers=0 output_color='' output_alpha=''
SMOKE 13 PASS codegen of two-layer stack: error='' code_len=1803
SMOKE SUMMARY pass=40 fail=0
```

stderr: empty.

Headless run immediately before this (`godot --headless --path . -s res://tests/run_codegen_tests.gd`):

```
GST tests: 14 file(s), 91 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

`project.godot`'s `config/features` was rewritten to `PackedStringArray("4.6")` by this run (same churn documented in the Cross-cutting concern) and reset to `PackedStringArray("4.4")` afterward; confirmed clean via `git status` (no other engine-written files appeared).

### Run 6: pass, phase-reviewer fix pass 3 (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Review round 3 found `GSTUndo._snapshot_layers()` deep-duplicated every
layer on `remove_layer` and `_undo_remove` replaced the whole array with the
duplicates, detaching every surviving `GSTLayer`/`GSTCoordBlock` instance
from whatever `EditorUndoRedoManager` property-undo actions (inspector
slider edits) already pointed at, once a remove was undone.

Fix: `gst_undo.gd::remove_layer` no longer duplicates. It records, before
calling `GSTStackOps.remove_layer`: the removed layer's own instance and
index, the list of `(layer, slot_name)` pairs and `(coord, axis)` pairs
whose value pointed at the removed id (`_snapshot_referencing_slots`,
`_snapshot_referencing_warps`), and the two output fields.
`_undo_remove` reinserts the same removed instance at the same index and
writes the recorded value back onto the same referencing `GSTLayer.slots`
dictionaries and `GSTCoordBlock` fields, never allocating a new layer.
`_redo_remove` calls `GSTStackOps.remove_layer` again on the same instance.
Reorder and `add_layer_below_and_wire` already moved/wired instances in
place with no duplication; confirmed unchanged. `gst_inspector_column.gd`
gained `get_edited_object()` so a test can confirm the live
`EditorInspector` still points at the restored instance.

`gst_editor_smoke.gd` gained `_run_slider_remove_undo_identity_excursion`
(items 16a-16f): adds a `generative/fbm` layer, commits a `gain` change
through `EditorUndoRedoManager.add_do_property`/`add_undo_property` the same
way `EditorInspector` does (not through `GSTUndo`), removes the layer
through `GSTUndo`, undoes the remove and asserts the layer back in the
stack `is_same()` as the original instance, undoes once more and asserts
`gain` reverted to the pre-slider value on that same instance, re-selects it
in the inspector column and asserts `get_edited_object().get_instance_id()`
still matches, then undoes the add to fully unwind. Self-canceling like the
excursions before it.

Command run the same way as Runs 3-5 (`Start-Process` with redirected
stdout/stderr, 180s timeout).

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE 1 PASS panel present
SMOKE 1 PASS panel.visible after set_main_screen_editor=true
SMOKE 2 PASS fbm=():<Resource#-9223370418507675747> invert=():<Resource#-9223370410974705340> hash=():<Resource#-9223370403039082087>
SMOKE 3 PASS after the adds, before any output-block or color-layer state exists: color option='(none)' alpha option='(default) none' (expect '(none)' and '(default) none')
SMOKE 15a PASS color/palette TYPE_VECTOR3 property names: ["a", "b", "c", "d"] (expect ["a", "b", "c", "d"])
SMOKE 15b PASS layer.get('a') type: 9 (expect Vector3)
SMOKE 15c PASS undo the palette add: layer gone=true
SMOKE 4a PASS color default after adding fill: '(default) l4 fill' (expect '(default) l4 fill')
SMOKE 4b PASS alpha default after adding texture: '(default) texture' (expect '(default) texture')
SMOKE 4c PASS alpha default after undoing texture add: '(default) none' (expect '(default) none')
SMOKE 4d PASS color default after undoing fill add: '(none)' (expect '(none)')
SMOKE 5a PASS add-for-slot picker listed 23 entries, all field kind=true
SMOKE 5b PASS search 'checker' visible=["generative/checker"] (expect ['generative/checker'])
SMOKE 5c PASS picked generative/checker: placed_below=true slot_wired=true count 3 -> 4
SMOKE 5d PASS undo add-for-slot: invert.slots['x']='' (expect empty), count=3 (expect 3)
SMOKE 6 PASS wire invert.x -> fbm: 
SMOKE 7 PASS up-press fbm above invert message='layer 1 references layer 0, which would be at or above it after this move' order_unchanged=true
SMOKE 8 PASS hash move down: ok=true index 2 -> 1
SMOKE 9 PASS boundary move at top: ok=true history_count 5 -> 5 (expect unchanged)
SMOKE 10 PASS set output color to invert: ok=true applied='1' (expect '1')
SMOKE 11 PASS set output alpha to none: ok=true applied='none' selected_text='none' (expect 'none')
SMOKE 11b PASS select default alpha row after explicit none: output_alpha='' (expect empty), history_count 7 -> 8 (expect +1)
SMOKE 11c PASS undo default-row pick restores explicit none: output_alpha='none' (expect 'none')
SMOKE 12a PASS output_alpha after undo 1: '' (expect empty), row_count=3 (expect 3)
SMOKE 12b PASS output_color after undo 2: '' (expect empty), row_count=3 (expect 3)
SMOKE 12c PASS hash index after undo 3: 2 (expect original 2), row_count=3 (expect 3)
SMOKE 12d PASS invert.slots['x'] after undo 4: '' (expect empty), row_count=3 (expect 3)
SMOKE 12e PASS hash gone=true row_count=2 (expect gone, 2 rows)
SMOKE 12f PASS invert gone=true row_count=1 (expect gone, 1 row)
SMOKE 12g PASS fbm gone=true row_count=0 (expect gone, 0 rows)
SMOKE 12h PASS history.has_undo() after 7 undos: false (expect false)
SMOKE 14a PASS wire output color=7 alpha=8
SMOKE 14b PASS remove output_alpha's layer: output_alpha='' (expect empty) codegen.ok=true error=''
SMOKE 14c PASS undo remove alpha layer: output_alpha='8' (expect '8'), layer present=true
SMOKE 14d PASS redo remove alpha layer: output_alpha='' (expect empty), layer present=false (expect false)
SMOKE 14e PASS remove output_color's layer: output_color='' (expect empty) codegen.ok=true error=''
SMOKE 14f PASS undo remove color layer: output_color='7' (expect '7'), layer present=true
SMOKE 14g PASS redo remove color layer: output_color='' (expect empty), layer present=false (expect false)
SMOKE 14h PASS excursion fully unwound: has_undo=false layers=0 output_color='' output_alpha=''
SMOKE 16a PASS slider commit gain=0.75 (expect 0.75)
SMOKE 16b PASS layer removed: present=false (expect false)
SMOKE 16c PASS undo remove restores same instance: is_same=true restored_id=-9223370307778049430 original_id=-9223370307778049430
SMOKE 16d PASS undo slider after undo remove: gain=0.5 (expect 0.5)
SMOKE 16e PASS EditorInspector edits the restored instance: edited_id=-9223370307778049430 (expect -9223370307778049430)
SMOKE 16f PASS excursion fully unwound: layer_gone=true has_undo=false
SMOKE 13 PASS codegen of two-layer stack: error='' code_len=1803
SMOKE SUMMARY pass=46 fail=0
```

stderr: empty.

Headless run immediately before this (`godot --headless --path . -s res://tests/run_codegen_tests.gd`):

```
GST tests: 14 file(s), 91 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

`project.godot`'s `config/features` was rewritten to `PackedStringArray("4.6")` by this run and reset to `PackedStringArray("4.4")` afterward; confirmed clean via `git diff project.godot` (empty) and `git status` (only the reviewer's fix files touched, plus the pre-existing untracked phase 4 set).

## Phase 5 (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Method: `$env:GST_EDITOR_SMOKE = "5"` then `godot --editor --path .`, via a
PowerShell wrapper calling `Godot_v4.6.2-stable_win64.exe` directly through
`Start-Process -RedirectStandardOutput/-RedirectStandardError -PassThru`
(same rationale as phase 4 Run 3: a plain `&`/pipe invocation did not
reliably capture the real editor window's output), 180s timeout via
`$proc.WaitForExit(180000)`. `tests/gst_editor_smoke.gd`'s `run(plugin)`
reads `GST_EDITOR_SMOKE` itself and dispatches to `_run_phase4`/`_run_phase5`
(`plugin.gd` only checks non-empty, unchanged, so it was not touched).

### Run 1: fail, root cause found (rendering, not codegen)

Items 2 and 3b failed: `SMOKE 2 FAIL checker scale uniform=(6.0, 6.0)
(expect (6.0, 6.0)) image_changed=false` and `SMOKE 3b FAIL
full_rect_nonuniform=false sprite_nonuniform=true material_still_same=true`.
Diagnostic instrumentation (temporary, removed before the final run) traced
this through several false leads -- pixel sampling density on a non-square
viewport rect, `BackBufferCopy` interference, `SubViewportContainer`
stretch resizing -- each ruled out in turn by direct experiment (an
isolated SubViewport + TextureRect + hardcoded red shader, parented
directly under the panel matching the phase 1 spike's structure, rendered
correctly on the first try). The decisive experiment: a second isolated
node whose `ShaderMaterial.shader` was created with **empty** `code`,
assigned to an already-in-tree, already-rendering `TextureRect`, and only
given real (green) `code` three frames later, rendered **black** forever
after, across 8 further frames -- reproducing the bug exactly. The first
isolated node (shader `code` set to its final value *before* the material
was ever assigned to a node) rendered correctly immediately.

Root cause: `GSTMainPanel._ready()` did `_material.shader = Shader.new()`
(an empty-code `Shader`) and immediately handed that `_material` to
`GSTPreview.set_shader_material()`, which assigned it to the already-live
target `TextureRect`, *before* the first `_resync_material()` call ever set
real `.code` on that same `Shader` object. Once a `ShaderMaterial` with an
empty-code `Shader` is assigned to a rendering `CanvasItem`, later mutating
`.code` in place on that same `Shader` object never takes visual effect,
even many frames later; the checker layer's field is `0.0` almost
everywhere at the default `scale = (1, 1)` (`floor(uv) = (0, 0)` across
virtually the whole `0..1` range), so the resulting solid-black render
happened to read as "non-uniform" only because it was being diffed against
whatever had rendered before the material got stuck (item 1 passed as a
false positive for this same reason, never actually observing the checker
shader's own output).

Fix: `GSTMainPanel._ready()` now calls `_resync_material()` (which creates
`_material.shader` itself, inside `GSTMaterialSync.sync()`, and sets its
`code` to a real value in the same call) *before* ever calling
`_preview.set_shader_material(_material)`. The `Shader` object is never
assigned to a rendering node while its `code` is empty. Every later
`_resync_material()` call mutates `.code` on an already-populated `Shader`,
which is the ordinary, unaffected hot-reload path.

### Run 2: pass, after the fix

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE 1 PASS checker layer renders non-uniform pixels after 3 frames (img_null=false)
SMOKE 2 PASS checker scale uniform=(6.0, 6.0) (expect (6.0, 6.0)) image_changed=true
SMOKE 3a PASS preset=text material_same=true message='text preset: coord space is uv; screen_uv reads more consistently on text (decision 11)'
SMOKE 3b PASS full_rect_nonuniform=true sprite_nonuniform=true material_still_same=true
SMOKE 4a PASS solo on: has_solo_line=true stack_unchanged=true
SMOKE 4b PASS solo off: code equals pre-solo code byte for byte=true
SMOKE 5 PASS texture source center pixel got=(0.9137, 0.5451, 0.1843, 1.0) want=(0.9176, 0.549, 0.1765, 1.0)
SMOKE 6 PASS screen source center pixel got=(0.898, 0.5373, 0.1804, 1.0) want=(0.9176, 0.549, 0.1765, 1.0)
SMOKE 7a PASS gst_rect_size=(488.0, 74.0) target=(488.0, 74.0) has_varying=true
SMOKE 7b PASS undo restores coord_space to uv: true (actual 0)
SMOKE 8a PASS forced codegen error: message='filter layer 3 (entry filter/pixelate) has no resolved texture or screen source wired to its source slot' code_unchanged=true
SMOKE 8b PASS recovery after removing the filter: message=''
SMOKE SUMMARY pass=14 fail=0
```

stderr: two benign `WARNING: Loaded resource as image file, this will not
work on export` lines, from items 5 and 6 deliberately calling
`Image.load()` directly on `preview_default.png`'s source path (bypassing
the `.import` pipeline) so the smoke script compares against the raw PNG's
own ground-truth pixels rather than whatever the editor's texture importer
produced. No other stderr output.

Confirmed re-run (`Run 3`, identical script, no further changes) reproduced
the same `pass=14 fail=0` result and the same stderr, verifying the fix is
not flaky.

`BackBufferCopy` (`copy_mode = COPY_MODE_VIEWPORT`, inserted between
`Background` and the active target node): included from the first
implementation, per the plan's explicit anticipation of the need, rather
than added reactively. Item 6 (`source/screen`) passed with it in place,
sampling the background image through `hint_screen_texture` within
tolerance (`got=(0.898, 0.5373, 0.1804, 1.0)` vs `want=(0.9176, 0.549,
0.1765, 1.0)`, tolerance `0.12`/channel). Not proven strictly necessary by
an A/B removal test (removing it was not tried once the real bug turned out
to be the empty-shader ordering issue above, to keep the number of
editor-relaunch cycles bounded); kept as the plan directs.

`godot --headless --path . -s res://tests/run_codegen_tests.gd` immediately
before this run:

```
GST tests: 15 file(s), 95 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

`project.godot`'s `config/features` was rewritten to `PackedStringArray("4.6")`
by every run in this section and reset to `PackedStringArray("4.4")`
afterward each time; confirmed clean via `git status` (only this phase's
new/modified files, `project.godot` unmodified) after the final run.

### Run 3: pass, phase-reviewer fix pass (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Review failed the phase: `gst_rect_size` never followed a resize with no
structural stack edit in between (an editor-window or splitter resize).
`GSTPreview.get_target_rect_size()` correctly tracked the live `SubViewport`
size, but nothing re-read it after the preview column's own rect changed;
`GSTMaterialSync.sync()` only ran from `stack_changed`, the shared
`EditorUndoRedoManager` history's `version_changed`, layer selection under
solo, and a preset/image change, none of which a bare resize fires. An S1
violation of B5 at `docs/PLAN.md:44`.

Fix: `GSTPreview` gained `signal target_rect_changed(size: Vector2)`,
connected to the active target node's own `resized` signal (reconnected on
every `set_preset` swap, since the old node's connection dies with it) and
emitted once directly from `set_preset` too. `GSTMaterialSync` gained
`write_rect_size(material, rect_size)`, a cheap path that rewrites only
`gst_rect_size` on an already-compiled shader's declared uniform list,
never touching `shader.code` or any other uniform. `GSTMainPanel` connects
`target_rect_changed` to a new `_on_target_rect_changed(size)` that calls
`GSTMaterialSync.write_rect_size` directly, not `_resync_material()`
(no codegen pass), since this can fire once per frame during a drag.

`gst_editor_smoke.gd` gained items 7c/7d inside a new
`_run_phase5_local_resize`, called from `_run_phase5_coord_space` after 7a/7b:
a scale-1 (`GSTCoordBlock.scale` default `Vector2.ONE`) `generative/checker`
layer is added under local space first, so the resize that follows is the
only thing that changes before the readback (no `GSTUndo` structural edit
runs in between, which would otherwise mask a stale-uniform bug by forcing a
full resync that re-reads the live size anyway). `preview.custom_minimum_size`
(`GSTPreview extends Control`, no new accessor needed) is grown past the
current target rect; item 7c asserts the rect actually grew and
`gst_rect_size` now equals the new size. Item 7d then reads the center pixel
and a quarter-rect pixel under local, switches to `uv` (same resized rect, no
further size change), reads the same two pixels again, and asserts they
match within tolerance: `local_pos = VERTEX / gst_rect_size` only equals `UV`
at this resized rect if `gst_rect_size` actually followed the resize, so a
stale value here would have shown up as visible checkerboard variation
against `uv`'s always-uniform-at-scale-1 render (confirmed against the fix:
before it, the stale pre-resize `gst_rect_size` combined with the new,
larger `VERTEX` range pushes `local_pos` past `1.0` over part of the rect).

Command run the same way as prior phase 5 runs (`Start-Process` with
redirected stdout/stderr, 180s timeout, `GST_EDITOR_SMOKE=5`).

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE 1 PASS checker layer renders non-uniform pixels after 3 frames (img_null=false)
SMOKE 2 PASS checker scale uniform=(6.0, 6.0) (expect (6.0, 6.0)) image_changed=true
SMOKE 3a PASS preset=text material_same=true message='text preset: coord space is uv; screen_uv reads more consistently on text (decision 11)'
SMOKE 3b PASS full_rect_nonuniform=true sprite_nonuniform=true material_still_same=true
SMOKE 4a PASS solo on: has_solo_line=true stack_unchanged=true
SMOKE 4b PASS solo off: code equals pre-solo code byte for byte=true
SMOKE 5 PASS texture source center pixel got=(0.9137, 0.5451, 0.1843, 1.0) want=(0.9176, 0.549, 0.1765, 1.0)
SMOKE 6 PASS screen source center pixel got=(0.898, 0.5373, 0.1804, 1.0) want=(0.9176, 0.549, 0.1765, 1.0)
SMOKE 7a PASS gst_rect_size=(488.0, 74.0) target=(488.0, 74.0) has_varying=true
SMOKE 7b PASS undo restores coord_space to uv: true (actual 0)
SMOKE 7c PASS resized=true before=(488.0, 74.0) after=(584.0, 138.0) gst_rect_size=(584.0, 138.0)
SMOKE 7d PASS local center=(0.0, 0.0, 0.0, 1.0) quarter=(0.0, 0.0, 0.0, 0.0); uv center=(0.0, 0.0, 0.0, 1.0) quarter=(0.0, 0.0, 0.0, 0.0)
SMOKE 8a PASS forced codegen error: message='filter layer 4 (entry filter/pixelate) has no resolved texture or screen source wired to its source slot' code_unchanged=true
SMOKE 8b PASS recovery after removing the filter: message=''
SMOKE SUMMARY pass=16 fail=0
```

stderr: the same two benign `WARNING: Loaded resource as image file, this
will not work on export` lines as Run 2 (items 5 and 6), nothing else.

`godot --headless --path . -s res://tests/run_codegen_tests.gd` immediately
before this run:

```
GST tests: 15 file(s), 95 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

`project.godot`'s `config/features` was rewritten to
`PackedStringArray("4.6")` by this run and reset to `PackedStringArray("4.4")`
afterward; confirmed via `git status` (no diff on `project.godot`).

### Run 4: pass, item 7d rewrite for real evidence (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Item 7d passed in Run 3 but was not evidence: `generative/checker.tres`
carries no manifest params (`params = Array[Dictionary]([])`, verified by
reading the file), so a checker layer's only density control is the
coord-block `scale` that item 7d was also supposed to hold at `1.0` per
B5's literal claim. At `scale = 1.0` with no offset,
`mod(floor(p.x)+floor(p.y), 2.0)` is exactly one cell across the whole
`[0,1)` rect (`floor(p) == (0,0)` everywhere), so both the `local` and `uv`
renders were uniformly black and the "matches" assertion passed
vacuously. The quarter-rect sample additionally read alpha `0`: the
sprite-preset target node did not cover the resized rect at that point, so
the sample landed outside the node entirely.

Fix: `_run_phase5_local_resize` now calls a new
`_run_phase5_checker_grid_evidence`, which switches the preset to
`full_rect` first (target node covers the viewport, every sampled fraction
lands inside it), adds a second `generative/checker` layer, and sets its
`coord.offset` to `(0.5, 0.5)` -- not `scale` -- through the same
`EditorUndoRedoManager` property-action pattern item 2 uses. Offsetting the
single scale-1 cell boundary into view produces a real four-quadrant
pattern (`mod(floor(x)+floor(y), 2)` parities `[0, 1, 1, 0]` at the four
rect corners) without moving `scale` off `1.0`, honoring the literal B5
precondition.

Samples are the four rect corners (`0.125`/`0.875` on each axis), not the
`x == y` diagonal the original fix request suggested: `floor(x) ==
floor(y)` everywhere on that line, so `mod(floor(x)+floor(y), 2)` is
provably `0` along the whole diagonal regardless of scale or offset --
confirmed by direct computation before writing the test, not discovered by
a failing run. A diagonal sample set would have been vacuous evidence
again, the same failure mode as the original item 7d.

Item 7d is now three checks: `7d1` captures the `uv` baseline and asserts
the four corner samples are not all equal (the checker actually renders
somewhere non-uniform); `7d2` switches to `local` and asserts each corner
sample matches its `uv` counterpart within `0.05` tolerance -- the actual
B5 claim, at the resized rect 7c produced, with genuinely varying evidence
behind it this time; `7d3` is a negative control, bumping `scale` to
`(2.0, 2.0)` under `local` only (the `uv` reference stays captured at
`scale = 1.0`) and asserting at least one corner sample now differs from
the `uv` reference, proving the four-point comparison in `7d2` is capable
of failing rather than passing regardless of input.

Command run the same way as prior phase 5 runs (`Start-Process` with
redirected stdout/stderr, 180s timeout, `GST_EDITOR_SMOKE=5`).

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE 1 PASS checker layer renders non-uniform pixels after 3 frames (img_null=false)
SMOKE 2 PASS checker scale uniform=(6.0, 6.0) (expect (6.0, 6.0)) image_changed=true
SMOKE 3a PASS preset=text material_same=true message='text preset: coord space is uv; screen_uv reads more consistently on text (decision 11)'
SMOKE 3b PASS full_rect_nonuniform=true sprite_nonuniform=true material_still_same=true
SMOKE 4a PASS solo on: has_solo_line=true stack_unchanged=true
SMOKE 4b PASS solo off: code equals pre-solo code byte for byte=true
SMOKE 5 PASS texture source center pixel got=(0.9137, 0.5451, 0.1843, 1.0) want=(0.9176, 0.549, 0.1765, 1.0)
SMOKE 6 PASS screen source center pixel got=(0.898, 0.5373, 0.1804, 1.0) want=(0.9176, 0.549, 0.1765, 1.0)
SMOKE 7a PASS gst_rect_size=(488.0, 74.0) target=(488.0, 74.0) has_varying=true
SMOKE 7b PASS undo restores coord_space to uv: true (actual 0)
SMOKE 7c PASS resized=true before=(488.0, 74.0) after=(584.0, 138.0) gst_rect_size=(584.0, 138.0)
SMOKE 7d1 PASS uv checker corner samples=[(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0)] (expect not all equal)
SMOKE 7d2 PASS local corner samples=[(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0)] match uv corner samples=[(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0)] (tolerance 0.05)
SMOKE 7d3 PASS local scale=2.0 corner samples=[(0.0, 0.0, 0.0, 1.0), (0.0, 0.0, 0.0, 1.0), (0.0, 0.0, 0.0, 1.0), (0.0, 0.0, 0.0, 1.0)] vs uv reference=[(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0)] (expect at least one differs)
SMOKE 8a PASS forced codegen error: message='filter layer 5 (entry filter/pixelate) has no resolved texture or screen source wired to its source slot' code_unchanged=true
SMOKE 8b PASS recovery after removing the filter: message=''
SMOKE SUMMARY pass=18 fail=0
```

stderr: the same two benign `WARNING: Loaded resource as image file, this
will not work on export` lines as prior runs (items 5 and 6), plus one
benign `WARNING: GENERAL - ... windows_read_data_files_in_registry:
Registry lookup failed to get layer manifest files` from the Vulkan loader
on this machine (unrelated to the plugin, seen on this environment before).
Nothing else.

`7d3`'s corner samples are `[0,0,0,1]` at all four points against a `uv`
reference of `[0,1,1,0]`: at `scale=(2,2)` with `offset=(0.5,0.5)`, `q =
2p + 0.5` puts all four sample fractions back on even cell-index pairs for
this particular offset/scale combination, an artifact of the specific
numbers chosen rather than something tuned to pass -- the assertion only
requires at least one of the four to differ, and two of the four
(`(0.125,0.875)` and `(0.875,0.125)`) do (`1` in the `uv` reference, `0`
here), which is what `7d3 PASS` reports.

`project.godot`'s `config/features` was rewritten to
`PackedStringArray("4.6")` by this run and reset to `PackedStringArray("4.4")`
afterward; confirmed via `git status` (no diff on `project.godot`).

### Run 5: pass, phase-reviewer fix pass 2 (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Second review round found: item 2 forced
`EditorUndoRedoManager.create_action(..., custom_context = stack)` directly
on `coord.scale`, which artificially bound the action to the stack's own
undo history bucket and never proved a real inspector-driven edit -- whose
`create_action()` call does not pass that context -- reaches the material at
all; item 3a checked only the message label text for the text preset, never
a rendered pixel; `GSTMainPanel.get_preview_slot()` was documented in
`docs/PLAN.md` phase 4 as "removed in phase 5 as obsolete" but was never
actually removed; several other `GSTMainPanel`/`GSTPreview` public accessors
had no live caller in `addons/` and no `Wired-by` declaration.

Fix 1 (the property relay): `gst_inspector_column.gd` now connects its
`EditorInspector.property_edited` signal and re-emits it as a new
`param_edited(property: String)` signal; `GSTMainPanel._ready()` connects
that to `_resync_material()`. A `GSTLayer`'s own dynamic params (e.g. a
manifest slider) are top-level properties of that column's `EditorInspector`
and relay this way directly. `GSTCoordBlock` has no dynamic property list, so
its fields show as a nested resource sub-editor; `gst_inspector_column.gd`
connects `GSTCoordBlock.changed` (the signal the engine's own inspector code
emits on the resource it just wrote a property onto) whenever a layer with a
coord block is selected, relaying that the same way. The shared
`EditorUndoRedoManager` history's `version_changed` signal (`_watched_history`)
is kept, narrowed by comment to its one remaining real job: undo/redo replay
of a property edit, which sets the value through `Object.set()` directly and
fires neither `property_edited` nor `Resource.changed`, so the live-edit
relay above cannot see it.

Item 2 was rewritten to drive a real `EditorProperty` widget's own
`emit_changed()` instead of a raw undo action. Walking
`gst_inspector_column.gd`'s live `EditorInspector` tree (temporary debug dump,
removed after diagnosis) confirmed `coord` shows as a collapsed
`EditorPropertyResource` row holding only an `EditorResourcePicker`'s own
buttons -- no nested `EditorProperty` children exist until a user expands it
by hand, which this test does not do. `GSTInspectorColumn` gained a static
`find_editor_property_in(root, property_name, edited_object)` (and an
instance-scoped `find_editor_property()` wrapper over its own inspector);
`gst_editor_smoke.gd` gained `_drive_real_property_edit()`, which points a
throwaway `EditorInspector` directly at `coord` (making `scale` a top-level
property with no expand step needed, the same `EditorProperty`/
`property_edited` machinery the column's own inspector already uses for
`GSTLayer`'s top-level properties) and calls the found widget's
`emit_changed()`.

Item 3a (fix 2) now also reads the viewport image after switching to the
text preset and asserts it is both non-uniform and differs from the sprite
preset's own image (captured just before the switch), not merely that the
message label mentions `screen_uv`.

Fix 3 (dead accessors / smoke seams, per the plan's new Cross-cutting entry
"Editor smoke seams"): `GSTMainPanel.get_preview_slot()` deleted along with
its now-unused `_preview_slot` `@onready` var (the `PreviewSlot` scene node
itself stays -- a real layout container, not dead). `GSTMainPanel.
get_preset_option()`, `get_coord_space_option()`, and `GSTPreview.
get_preset_name()` deleted: zero callers anywhere, in `addons/` or `tests/`.
Every remaining `GSTMainPanel`/`GSTPreview` public accessor with no live
caller in `addons/` (`get_stack`, `get_library`, `get_undo`, `get_stack_list`,
`get_output_block`, `get_inspector_column`, `get_preview`,
`get_shader_material`, `get_solo_check`, `get_message_label`,
`GSTPreview.get_viewport_image`, `GSTPreview.get_current_target_material`)
gained the doc comment line `## Wired-by: none (editor smoke seam)`, grepped
individually against `addons/` and `tests/` to confirm each is smoke-only.
`GSTPreview.set_shader_material`, `set_preset`, `set_image`, and
`get_target_rect_size` keep no such line: each has a live caller in
`gst_main_panel.gd`. `GSTMainPanel.set_stack()` also keeps no such line: it
has no live caller yet, but is explicitly forward-wired in `docs/PLAN.md`
phase 4's own `Wired-by: phase 6` note ("the open and reopen entry point"),
not an editor-smoke-only seam.

Command run the same way as prior phase 5 runs (`Start-Process` with
redirected stdout/stderr, 180s timeout, `GST_EDITOR_SMOKE=5`).

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE 1 PASS checker layer renders non-uniform pixels after 3 frames (img_null=false)
SMOKE 2 PASS checker scale via real EditorProperty widget found=true coord.scale=(6.0, 6.0) uniform=(6.0, 6.0) (expect (6.0, 6.0)) image_changed=true
SMOKE 3a PASS preset=text material_same=true message='text preset: coord space is uv; screen_uv reads more consistently on text (decision 11)' text_nonuniform=true differs_from_sprite=true
SMOKE 3b PASS full_rect_nonuniform=true sprite_nonuniform=true material_still_same=true
SMOKE 4a PASS solo on: has_solo_line=true stack_unchanged=true
SMOKE 4b PASS solo off: code equals pre-solo code byte for byte=true
SMOKE 5 PASS texture source center pixel got=(0.9137, 0.5451, 0.1843, 1.0) want=(0.9176, 0.549, 0.1765, 1.0)
SMOKE 6 PASS screen source center pixel got=(0.898, 0.5373, 0.1804, 1.0) want=(0.9176, 0.549, 0.1765, 1.0)
SMOKE 7a PASS gst_rect_size=(488.0, 74.0) target=(488.0, 74.0) has_varying=true
SMOKE 7b PASS undo restores coord_space to uv: true (actual 0)
SMOKE 7c PASS resized=true before=(488.0, 74.0) after=(584.0, 138.0) gst_rect_size=(584.0, 138.0)
SMOKE 7d1 PASS uv checker corner samples=[(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0)] (expect not all equal)
SMOKE 7d2 PASS local corner samples=[(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0)] match uv corner samples=[(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0)] (tolerance 0.05)
SMOKE 7d3 PASS local scale=2.0 corner samples=[(0.0, 0.0, 0.0, 1.0), (0.0, 0.0, 0.0, 1.0), (0.0, 0.0, 0.0, 1.0), (0.0, 0.0, 0.0, 1.0)] vs uv reference=[(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0)] (expect at least one differs)
SMOKE 8a PASS forced codegen error: message='filter layer 5 (entry filter/pixelate) has no resolved texture or screen source wired to its source slot' code_unchanged=true
SMOKE 8b PASS recovery after removing the filter: message=''
SMOKE SUMMARY pass=18 fail=0
```

stderr: the same two benign `WARNING: Loaded resource as image file, this
will not work on export` lines as prior runs (items 5 and 6), nothing else.

`godot --headless --path . -s res://tests/run_codegen_tests.gd` immediately
before this run:

```
GST tests: 15 file(s), 95 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

Rerun of the phase 4 section (`GST_EDITOR_SMOKE=4`), to confirm the accessor
cleanup in fix 3 above did not disturb it, same wrapper and timeout:

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE 1 PASS panel present
SMOKE 1 PASS panel.visible after set_main_screen_editor=true
SMOKE 2 PASS fbm=():<Resource#-9223370405840877180> invert=():<Resource#-9223370398291129557> hash=():<Resource#-9223370390087070848>
SMOKE 3 PASS after the adds, before any output-block or color-layer state exists: color option='(none)' alpha option='(default) none' (expect '(none)' and '(default) none')
SMOKE 15a PASS color/palette TYPE_VECTOR3 property names: ["a", "b", "c", "d"] (expect ["a", "b", "c", "d"])
SMOKE 15b PASS layer.get('a') type: 9 (expect Vector3)
SMOKE 15c PASS undo the palette add: layer gone=true
SMOKE 4a PASS color default after adding fill: '(default) l4 fill' (expect '(default) l4 fill')
SMOKE 4b PASS alpha default after adding texture: '(default) texture' (expect '(default) texture')
SMOKE 4c PASS alpha default after undoing texture add: '(default) none' (expect '(default) none')
SMOKE 4d PASS color default after undoing fill add: '(none)' (expect '(none)')
SMOKE 5a PASS add-for-slot picker listed 23 entries, all field kind=true
SMOKE 5b PASS search 'checker' visible=["generative/checker"] (expect ['generative/checker'])
SMOKE 5c PASS picked generative/checker: placed_below=true slot_wired=true count 3 -> 4
SMOKE 5d PASS undo add-for-slot: invert.slots['x']='' (expect empty), count=3 (expect 3)
SMOKE 6 PASS wire invert.x -> fbm: 
SMOKE 7 PASS up-press fbm above invert message='layer 1 references layer 0, which would be at or above it after this move' order_unchanged=true
SMOKE 8 PASS hash move down: ok=true index 2 -> 1
SMOKE 9 PASS boundary move at top: ok=true history_count 5 -> 5 (expect unchanged)
SMOKE 10 PASS set output color to invert: ok=true applied='1' (expect '1')
SMOKE 11 PASS set output alpha to none: ok=true applied='none' selected_text='none' (expect 'none')
SMOKE 11b PASS select default alpha row after explicit none: output_alpha='' (expect empty), history_count 7 -> 8 (expect +1)
SMOKE 11c PASS undo default-row pick restores explicit none: output_alpha='none' (expect 'none')
SMOKE 12a PASS output_alpha after undo 1: '' (expect empty), row_count=3 (expect 3)
SMOKE 12b PASS output_color after undo 2: '' (expect empty), row_count=3 (expect 3)
SMOKE 12c PASS hash index after undo 3: 2 (expect original 2), row_count=3 (expect 3)
SMOKE 12d PASS invert.slots['x'] after undo 4: '' (expect empty), row_count=3 (expect 3)
SMOKE 12e PASS hash gone=true row_count=2 (expect gone, 2 rows)
SMOKE 12f PASS invert gone=true row_count=1 (expect gone, 1 row)
SMOKE 12g PASS fbm gone=true row_count=0 (expect gone, 0 rows)
SMOKE 12h PASS history.has_undo() after 7 undos: false (expect false)
SMOKE 14a PASS wire output color=7 alpha=8
SMOKE 14b PASS remove output_alpha's layer: output_alpha='' (expect empty) codegen.ok=true error=''
SMOKE 14c PASS undo remove alpha layer: output_alpha='8' (expect '8'), layer present=true
SMOKE 14d PASS redo remove alpha layer: output_alpha='' (expect empty), layer present=false (expect false)
SMOKE 14e PASS remove output_color's layer: output_color='' (expect empty) codegen.ok=true error=''
SMOKE 14f PASS undo remove color layer: output_color='7' (expect '7'), layer present=true
SMOKE 14g PASS redo remove color layer: output_color='' (expect empty), layer present=false (expect false)
SMOKE 14h PASS excursion fully unwound: has_undo=false layers=0 output_color='' output_alpha=''
SMOKE 16a PASS slider commit gain=0.75 (expect 0.75)
SMOKE 16b PASS layer removed: present=false (expect false)
SMOKE 16c PASS undo remove restores same instance: is_same=true restored_id=-9223370282545116079 original_id=-9223370282545116079
SMOKE 16d PASS undo slider after undo remove: gain=0.5 (expect 0.5)
SMOKE 16e PASS EditorInspector edits the restored instance: edited_id=-9223370282545116079 (expect -9223370282545116079)
SMOKE 16f PASS excursion fully unwound: layer_gone=true has_undo=false
SMOKE 13 PASS codegen of two-layer stack: error='' code_len=1803
SMOKE SUMMARY pass=46 fail=0
```

stderr: empty.

`project.godot`'s `config/features` was rewritten to
`PackedStringArray("4.6")` by both runs above and reset to
`PackedStringArray("4.4")` afterward; confirmed via `git status --short
project.godot` (no output, clean) after the reset.

### `preview_default.png` generation method

Generated once by a throwaway `godot --headless --path . -s <script>.gd`
script (not committed, per the plan): builds a 256x256 `Image`
(`Image.create_empty`), fills it with a radial gradient from
`Color(0.92, 0.55, 0.18, 1.0)` at the center to `Color(0.12, 0.32, 0.82,
1.0)` at the edge, alpha falling off as `pow(1.0 - d, 1.4)` (`d` = distance
from center over the corner-to-corner max distance), then overlays three
solid opaque shapes (a yellow circle, a green square, a red circle) clear
of the exact center so the center pixel stays the pure gradient color
(`(0.9176, 0.549, 0.1765, 1.0)`, verified) for phase 5's texture/screen
source pixel-match checks. Saved with `Image.save_png()`, then
`godot --headless --path . --import` generated the `.import` sidecar
normally.

## Phase 6 (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Method: `$env:GST_EDITOR_SMOKE = "6"` then `godot --editor --path .`, same
`Start-Process -RedirectStandardOutput/-RedirectStandardError -PassThru`
wrapper as phases 4-5, `$proc.WaitForExit(180000)`. `tests/gst_editor_smoke.gd`'s
`run(plugin)` gained an `elif flag == "6"` branch dispatching to
`_run_phase6`, alongside the existing `"5"`/default dispatch (`plugin.gd`
unchanged, same as phase 5's own note).

Builds a three-layer stack (`generative/checker` output_color,
`generative/fbm` with `octaves = 6`, `fieldops/invert` wired to fbm) through
the panel's own `GSTStackList`/`GSTUndo`, then drives every persistence step
through the panel's public seams (`save_to_path`, `_on_new_pressed`,
`open_path`, `export_to_path`, `reopen_shader_path`,
`is_overwrite_dialog_visible`), the same functions the toolbar's button
handlers call. Files land under `sandbox/stacks/` and `sandbox/exports/`
and are deleted (`DirAccess.remove_absolute`, plus any `.uid` sidecar) at
the end of the run regardless of pass/fail.

### Run 1: fail, two real bugs found

```
SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE 1 PASS three layers added: checker=():<Resource#-9223370376581410911> fbm=():<Resource#-9223370369367207628> invert=():<Resource#-9223370360223624752>
SMOKE 2 PASS save_to_path: current_path='res://sandbox/stacks/gst_editor_smoke_phase6.tres' (expect 'res://sandbox/stacks/gst_editor_smoke_phase6.tres') message='' file_exists=true
SMOKE 3 FAIL New: layers=0 (expect 0) has_undo=true (expect false) current_path='' (expect '')
SMOKE 4 PASS open_path: ids_match=true params_match=true (octaves=6) preview_nonuniform=true current_path='res://sandbox/stacks/gst_editor_smoke_phase6.tres' (expect 'res://sandbox/stacks/gst_editor_smoke_phase6.tres')
SMOKE 5 PASS export_to_path: exists=true header_present=true
SMOKE 6 PASS export confirm=false on a differing target: dialog_visible=true (expect true) file_unchanged=true (expect true)
SMOKE 7 FAIL export confirm=true overwrites: overwritten=true (expect true) dialog_hidden=false (expect true)
SMOKE 8 PASS reopen_shader_path rebuilds the same ids: true (current_path='', expect empty)
SMOKE 9 PASS reopen of a headerless file is refused (B8): message='res://sandbox/exports/gst_editor_smoke_phase6_headerless.gdshader has no '// stack:' header (B8)' stack_unchanged=true
SMOKE SUMMARY pass=9 fail=2
```

**Item 3 root cause (engine constraint, not a code defect):**
`EditorUndoRedoManager.get_object_history_id(object)` does not give a fresh
`GSTStack` its own private bucket the instant it exists. Verified on
4.6.2: a `GSTStack` is a bare `Resource`, never added to the edited scene,
so every `create_action(..., custom_context = <a GSTStack not in the
scene>)` routes into the same shared "Remote History" bucket regardless of
*which* `GSTStack` instance is passed. `has_undo()` on it stayed `true`
immediately after New because the pre-New stack's own actions were still
sitting in that same shared bucket, not because anything leaked into the
new stack. Phases 4 and 5 never exercised this: both ran one continuous
stack instance for their entire session, so that stack was incidentally the
sole tenant of the shared bucket throughout, making `gst_undo.gd`'s own
"stable bucket" comment true in the narrower sense those phases actually
tested.

Fix: rather than assert `has_undo() == false` (not achievable for a bare
Resource custom_context on this engine version), item 3 now asserts the
weaker, correct claim: the new stack has zero layers both before and after
undoing the shared timeline's pending action once. That undo can only
replay against the *previous* `GSTUndo` instance's own closures (bound to
the *old* stack object the do/undo methods captured), so it is expected to
leave the new stack's own `layers` array untouched either way; the test
confirms this rather than asserting an object-level history isolation the
engine does not provide for floating Resources.

**Item 7 root cause:** `GSTMainPanel.export_to_path()` never hid
`_overwrite_dialog` on a successful confirmed write. In real button usage
`AcceptDialog` auto-hides itself when its own OK button triggers
`confirmed`, but the smoke (and any caller that re-invokes `export_to_path`
with `confirm = true` directly, bypassing the dialog's own button) never
fires that internal path, so the dialog popped in item 6 stayed visible.

Fix: `export_to_path()` now explicitly closes `_overwrite_dialog` whenever
the outcome is anything other than `needs_confirmation` (a resolved
confirm-then-write, or a write that turned out not to need confirmation at
all), independent of how `confirm = true` was reached.

### Run 2: pass, after both fixes

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE 1 PASS three layers added: checker=():<Resource#-9223370381312586084> fbm=():<Resource#-9223370374098382801> invert=():<Resource#-9223370365089017653>
SMOKE 2 PASS save_to_path: current_path='res://sandbox/stacks/gst_editor_smoke_phase6.tres' (expect 'res://sandbox/stacks/gst_editor_smoke_phase6.tres') message='' file_exists=true
SMOKE 3 PASS New: layers_before_undo=0 layers_after_undo=0 (expect 0/0, isolated from the shared Remote History bucket) current_path='' (expect '')
SMOKE 4 PASS open_path: ids_match=true params_match=true (octaves=6) preview_nonuniform=true current_path='res://sandbox/stacks/gst_editor_smoke_phase6.tres' (expect 'res://sandbox/stacks/gst_editor_smoke_phase6.tres')
SMOKE 5 PASS export_to_path: exists=true header_present=true
SMOKE 6 PASS export confirm=false on a differing target: dialog_visible=true (expect true) file_unchanged=true (expect true)
SMOKE 7 PASS export confirm=true overwrites: overwritten=true (expect true) dialog_hidden=true (expect true)
SMOKE 8 PASS reopen_shader_path rebuilds the same ids: true (current_path='', expect empty)
SMOKE 9 PASS reopen of a headerless file is refused (B8): message='res://sandbox/exports/gst_editor_smoke_phase6_headerless.gdshader has no '// stack:' header (B8)' stack_unchanged=true
SMOKE SUMMARY pass=11 fail=0
```

stderr: empty.

`godot --headless --path . -s res://tests/run_codegen_tests.gd` immediately
before this run:

```
GST tests: 18 file(s), 110 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

`project.godot`'s `config/features` was rewritten to
`PackedStringArray("4.6")` by both runs above and reset to
`PackedStringArray("4.4")` afterward each time; confirmed via `git status
--porcelain` (`project.godot` absent from the list, only the phase's own
new/modified files and the two committed `.gitkeep`s under `sandbox/`
shown) and `find sandbox -type f` (only the two `.gitkeep`s, confirming the
smoke's own files were deleted).

### Run 3: pass, phase-reviewer fix pass 2 (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Fix pass covering three phase-reviewer findings: (1) `New`/`Open`/`Reopen
Shader` are now undoable "Replace stack" `EditorUndoRedoManager` actions
(`gst_main_panel.gd`'s `replace_stack`/`_install_stack`), so a
pre-replacement structural edit stays undoable instead of being discarded
with the old `GSTStack`; item 3 rewritten to prove the full do/undo/redo
round trip (instance identity via `is_same`, layer count, `current_path`,
and the old stack's own last action replaying correctly) instead of the
weaker "isolated from the shared Remote History bucket" claim Run 1/2
settled for. (2) `tests/test_stack_io.gd` now compares every persisted
`GSTStack`/`GSTLayer`/`GSTCoordBlock` field via
`_compare_stacks`/`_compare_layers`/`_compare_dict`/`_compare_coord`
helpers that return every mismatch as a list, including params type
equality (an `int` param, `fbm`'s `octaves`, must stay `int` after the
`.tres` round trip). (3) the phase 6 smoke now drives Save As, Open,
Export, the overwrite confirmation, and Reopen through the panel's own
`EditorFileDialog`/`ConfirmationDialog` handlers
(`_on_save_as_file_selected`, `_on_open_file_selected`,
`_on_export_file_selected`, `_on_overwrite_confirmed`,
`_on_reopen_shader_file_selected`) instead of the plain path-taking seams
those handlers call, and a new item 3f presses the Export button with no
`current_path` and asserts the export dialog opens.

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE 1 PASS three layers added: checker=():<Resource#-9223370376413638752> fbm=():<Resource#-9223370369199435469> invert=():<Resource#-9223370360190070321>
SMOKE 2 PASS _on_save_as_file_selected: current_path='res://sandbox/stacks/gst_editor_smoke_phase6.tres' (expect 'res://sandbox/stacks/gst_editor_smoke_phase6.tres') message='' file_exists=true
SMOKE 3a PASS New: layers=0 current_path='' new_instance=true has_undo=true
SMOKE 3b PASS undo 1 after New restores the previous stack instance: is_same=true layers=3 (expect 3) layer_ids_match=true current_path='res://sandbox/stacks/gst_editor_smoke_phase6.tres' (expect 'res://sandbox/stacks/gst_editor_smoke_phase6.tres')
SMOKE 3c PASS redo 1 re-applies New: is_same=true layers=0 current_path=''
SMOKE 3d PASS undo twice more reaches the pre-New old stack with its own last action (set_output_color) undone: is_same=true layers=3 (expect 3) output_color='' (expect '')
SMOKE 3e PASS redo twice more returns to the New state: is_same=true layers=0 current_path=''
SMOKE 3f PASS Export press with no current_path opens the export dialog: current_path='' (expect '') dialog_visible=true
SMOKE 4 PASS _on_open_file_selected: ids_match=true params_match=true (octaves=6) preview_nonuniform=true current_path='res://sandbox/stacks/gst_editor_smoke_phase6.tres' (expect 'res://sandbox/stacks/gst_editor_smoke_phase6.tres')
SMOKE 5 PASS _on_export_file_selected: exists=true header_present=true
SMOKE 6 PASS re-selecting a differing export target: dialog_visible=true (expect true) file_unchanged=true (expect true)
SMOKE 7 PASS _on_overwrite_confirmed overwrites: overwritten=true (expect true) dialog_hidden=true (expect true)
SMOKE 8 PASS _on_reopen_shader_file_selected rebuilds the same ids: true (current_path='', expect empty)
SMOKE 9 PASS reopen of a headerless file is refused (B8): message='res://sandbox/exports/gst_editor_smoke_phase6_headerless.gdshader has no '// stack:' header (B8)' stack_unchanged=true
SMOKE SUMMARY pass=16 fail=0
```

stderr: empty.

`godot --headless --path . -s res://tests/run_codegen_tests.gd` immediately before this run:

```
GST tests: 18 file(s), 110 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

Phase 4 regression re-run (`GST_EDITOR_SMOKE=4`, same fix pass, unmodified
phase 4 checks -- required by the fix pass since `replace_stack` changes
`gst_main_panel.gd`'s `set_undo_redo_manager` and adds `_install_stack`
which the phase 4 undo sequence's own initial wiring depends on):

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE 1 PASS panel present
SMOKE 1 PASS panel.visible after set_main_screen_editor=true
SMOKE 2 PASS fbm=():<Resource#-9223370376413638752> invert=():<Resource#-9223370368863891129> hash=():<Resource#-9223370360794050148>
SMOKE 3 PASS after the adds, before any output-block or color-layer state exists: color option='(none)' alpha option='(default) none' (expect '(none)' and '(default) none')
SMOKE 15a PASS color/palette TYPE_VECTOR3 property names: ["a", "b", "c", "d"] (expect ["a", "b", "c", "d"])
SMOKE 15b PASS layer.get('a') type: 9 (expect Vector3)
SMOKE 15c PASS undo the palette add: layer gone=true
SMOKE 4a PASS color default after adding fill: '(default) l4 fill' (expect '(default) l4 fill')
SMOKE 4b PASS alpha default after adding texture: '(default) texture' (expect '(default) texture')
SMOKE 4c PASS alpha default after undoing texture add: '(default) none' (expect '(default) none')
SMOKE 4d PASS color default after undoing fill add: '(none)' (expect '(none)')
SMOKE 5a PASS add-for-slot picker listed 23 entries, all field kind=true
SMOKE 5b PASS search 'checker' visible=["generative/checker"] (expect ['generative/checker'])
SMOKE 5c PASS picked generative/checker: placed_below=true slot_wired=true count 3 -> 4
SMOKE 5d PASS undo add-for-slot: invert.slots['x']='' (expect empty), count=3 (expect 3)
SMOKE 6 PASS wire invert.x -> fbm: 
SMOKE 7 PASS up-press fbm above invert message='layer 1 references layer 0, which would be at or above it after this move' order_unchanged=true
SMOKE 8 PASS hash move down: ok=true index 2 -> 1
SMOKE 9 PASS boundary move at top: ok=true history_count 5 -> 5 (expect unchanged)
SMOKE 10 PASS set output color to invert: ok=true applied='1' (expect '1')
SMOKE 11 PASS set output alpha to none: ok=true applied='none' selected_text='none' (expect 'none')
SMOKE 11b PASS select default alpha row after explicit none: output_alpha='' (expect empty), history_count 7 -> 8 (expect +1)
SMOKE 11c PASS undo default-row pick restores explicit none: output_alpha='none' (expect 'none')
SMOKE 12a PASS output_alpha after undo 1: '' (expect empty), row_count=3 (expect 3)
SMOKE 12b PASS output_color after undo 2: '' (expect empty), row_count=3 (expect 3)
SMOKE 12c PASS hash index after undo 3: 2 (expect original 2), row_count=3 (expect 3)
SMOKE 12d PASS invert.slots['x'] after undo 4: '' (expect empty), row_count=3 (expect 3)
SMOKE 12e PASS hash gone=true row_count=2 (expect gone, 2 rows)
SMOKE 12f PASS invert gone=true row_count=1 (expect gone, 1 row)
SMOKE 12g PASS fbm gone=true row_count=0 (expect gone, 0 rows)
SMOKE 12h PASS history.has_undo() after 7 undos: false (expect false)
SMOKE 14a PASS wire output color=7 alpha=8
SMOKE 14b PASS remove output_alpha's layer: output_alpha='' (expect empty) codegen.ok=true error=''
SMOKE 14c PASS undo remove alpha layer: output_alpha='8' (expect '8'), layer present=true
SMOKE 14d PASS redo remove alpha layer: output_alpha='' (expect empty), layer present=false (expect false)
SMOKE 14e PASS remove output_color's layer: output_color='' (expect empty) codegen.ok=true error=''
SMOKE 14f PASS undo remove color layer: output_color='7' (expect '7'), layer present=true
SMOKE 14g PASS redo remove color layer: output_color='' (expect empty), layer present=false (expect false)
SMOKE 14h PASS excursion fully unwound: has_undo=false layers=0 output_color='' output_alpha=''
SMOKE 16a PASS slider commit gain=0.75 (expect 0.75)
SMOKE 16b PASS layer removed: present=false (expect false)
SMOKE 16c PASS undo remove restores same instance: is_same=true restored_id=-9223370253772189065 original_id=-9223370253772189065
SMOKE 16d PASS undo slider after undo remove: gain=0.5 (expect 0.5)
SMOKE 16e PASS EditorInspector edits the restored instance: edited_id=-9223370253772189065 (expect -9223370253772189065)
SMOKE 16f PASS excursion fully unwound: layer_gone=true has_undo=false
SMOKE 13 PASS codegen of two-layer stack: error='' code_len=2182
SMOKE SUMMARY pass=46 fail=0
```

stderr: empty.

`project.godot`'s `config/features` was rewritten to `PackedStringArray("4.6")`
by both runs above and reset to `PackedStringArray("4.4")` afterward;
verified via `grep config/features project.godot`. `find sandbox -type f`
after Run 3 showed only the two committed `.gitkeep`s, confirming the
smoke's own files (`gst_editor_smoke_phase6.tres`,
`gst_editor_smoke_phase6.gdshader`,
`gst_editor_smoke_phase6_headerless.gdshader`, and their `.uid` sidecars)
were deleted.

## Phase 7 (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Method: `$env:GST_EDITOR_SMOKE="7"; godot --editor --path .`, captured
stdout/stderr via `Start-Process -RedirectStandardOutput/-RedirectStandardError`
with a 180s timeout, `config/features` reset to `"4.4"` afterward.

### Run 1: fail, root cause identified

For each of the three recipes, the smoke builds the same stack through
`GSTUndo`'s public actions (add, wire, output) plus real
`EditorUndoRedoManager` property actions for params (the same shape a slider
commit uses), captures the shader text, undoes to `has_undo() == false`
(asserts the stack is empty), redoes to `has_redo() == false` (asserts the
shader text is byte-equal to the capture and the preview renders
non-uniform), then calls `panel.open_recipe(name)` and checks the panel lands
on the same codegen text a fresh, independent `GSTStackIO.load` of that
recipe file produces.

`dissolve`'s own round trip passed. `sprite_holographic`'s and `outline`'s
`_redo_match` checks failed: the shader text after the full redo-to-end pass
was byte-identical to **`dissolve`'s own** codegen output (verified by a
temporary debug dump of both texts), not the recipe actually built in that
iteration.

Root cause: `gst_main_panel.gd::replace_stack` registered its "Replace
stack" `EditorUndoRedoManager` action with `custom_context = old_stack` (the
stack being replaced). `dissolve`'s own `open_recipe("dissolve")` call
installs a `GSTStack` loaded from a real `res://` path via `GSTStackIO.load`.
The next recipe's own `New` press then runs `replace_stack` with
`old_stack` = that path-bearing, just-loaded stack. On 4.6.2,
`EditorUndoRedoManager.get_object_history_id()` routes a path-bearing
`Resource` to a **different** history bucket than a bare, path-less
`GSTStack.new()` (verified empirically here; the existing phase 6 cross-cutting
note "every custom_context = stack action ... routes into the one shared
bucket" was verified there only for path-less `New` calls, never for a
`New` following an `Open`-like load). The smoke's own `history` reference
(and `gst_main_panel.gd::_get_history()`, used by the live
`_on_history_version_changed` resync) was fetched once from the original
path-less stack and therefore never observed the second recipe's own `New`
action at all: that action alone landed in the other bucket. Full redo of
the observed bucket replayed `New -> dissolve build -> open_recipe(dissolve)`
correctly, then replayed the *next* recipe's own build actions (their own
`GSTUndo` instance, bound to their own path-less stack, still lived in the
shared bucket) directly on top of `dissolve`'s reinstalled stack state --
mutating an object `panel._stack` no longer pointed at, so every
`_resync_material()` triggered along the way kept re-codegenning
`dissolve`'s own stack.

```
SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE dissolve_build PASS dissolve: built stack produces non-empty shader text (len=4314)
SMOKE dissolve_undo_empty PASS dissolve: stack empty and has_undo()=false after undoing to the end: layers=0 has_undo=false
SMOKE dissolve_redo_match PASS dissolve: redo-to-end shader text byte-equal to the build capture=true has_redo=false
SMOKE dissolve_redo_render PASS dissolve: preview renders non-uniform pixels after redo (img_null=false)
SMOKE dissolve_open_match PASS dissolve: open_recipe panel shader text equals a fresh codegen of the recipe file=true (fresh_ok=true)
SMOKE dissolve_open_render PASS dissolve: preview renders non-uniform pixels after open_recipe (img_null=false)
SMOKE sprite_holographic_build PASS sprite_holographic: built stack produces non-empty shader text (len=2294)
SMOKE sprite_holographic_undo_empty PASS sprite_holographic: stack empty and has_undo()=false after undoing to the end: layers=0 has_undo=false
SMOKE sprite_holographic_redo_match FAIL sprite_holographic: redo-to-end shader text byte-equal to the build capture=false has_redo=false
SMOKE sprite_holographic_redo_render PASS sprite_holographic: preview renders non-uniform pixels after redo (img_null=false)
SMOKE sprite_holographic_open_match PASS sprite_holographic: open_recipe panel shader text equals a fresh codegen of the recipe file=true (fresh_ok=true)
SMOKE sprite_holographic_open_render PASS sprite_holographic: preview renders non-uniform pixels after open_recipe (img_null=false)
SMOKE outline_build PASS outline: built stack produces non-empty shader text (len=1649)
SMOKE outline_undo_empty PASS outline: stack empty and has_undo()=false after undoing to the end: layers=0 has_undo=false
SMOKE outline_redo_match FAIL outline: redo-to-end shader text byte-equal to the build capture=false has_redo=false
SMOKE outline_redo_render PASS outline: preview renders non-uniform pixels after redo (img_null=false)
SMOKE outline_open_match PASS outline: open_recipe panel shader text equals a fresh codegen of the recipe file=true (fresh_ok=true)
SMOKE outline_open_render PASS outline: preview renders non-uniform pixels after open_recipe (img_null=false)
SMOKE SUMMARY pass=18 fail=2
```

Fix: `gst_main_panel.gd` gained a dedicated field `_history_context: Resource
= Resource.new()`, created once and never given a `resource_path`, used as
`custom_context` in place of `old_stack`/`_stack` in both `replace_stack`'s
own action and `_get_history()`'s lookup. A bare, always path-less anchor
stays in the one shared bucket regardless of what was opened in between,
since bucket routing keys off path-less-ness, not literal object identity
(confirmed by Run 2 below). This is a general fix to existing phase 4/6
code (`gst_main_panel.gd`, already in this phase's Files list for the
Recipes menu), not new phase 7 machinery; `gst_undo.gd`'s own
`_create_action` (unrelated file, outside this phase's Files list) still
keys its context off the live `_stack` instance directly, which remains
correct for every path this smoke exercises (every recipe build starts from
a fresh `New`, i.e. a path-less stack) but is not proven safe for a
structural edit made directly on a stack immediately after `Open`/`Reopen
Shader`/`open_recipe`, with no intervening `New` -- flagged as an open
finding in the phase report, not fixed here.

### Run 2: pass, after the `_history_context` fix

```
SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE dissolve_build PASS dissolve: built stack produces non-empty shader text (len=4314)
SMOKE dissolve_undo_empty PASS dissolve: stack empty and has_undo()=false after undoing to the end: layers=0 has_undo=false
SMOKE dissolve_redo_match PASS dissolve: redo-to-end shader text byte-equal to the build capture=true has_redo=false
SMOKE dissolve_redo_render PASS dissolve: preview renders non-uniform pixels after redo (img_null=false)
SMOKE dissolve_open_match PASS dissolve: open_recipe panel shader text equals a fresh codegen of the recipe file=true (fresh_ok=true)
SMOKE dissolve_open_render PASS dissolve: preview renders non-uniform pixels after open_recipe (img_null=false)
SMOKE sprite_holographic_build PASS sprite_holographic: built stack produces non-empty shader text (len=2294)
SMOKE sprite_holographic_undo_empty PASS sprite_holographic: stack empty and has_undo()=false after undoing to the end: layers=0 has_undo=false
SMOKE sprite_holographic_redo_match PASS sprite_holographic: redo-to-end shader text byte-equal to the build capture=true has_redo=false
SMOKE sprite_holographic_redo_render PASS sprite_holographic: preview renders non-uniform pixels after redo (img_null=false)
SMOKE sprite_holographic_open_match PASS sprite_holographic: open_recipe panel shader text equals a fresh codegen of the recipe file=true (fresh_ok=true)
SMOKE sprite_holographic_open_render PASS sprite_holographic: preview renders non-uniform pixels after open_recipe (img_null=false)
SMOKE outline_build PASS outline: built stack produces non-empty shader text (len=1649)
SMOKE outline_undo_empty PASS outline: stack empty and has_undo()=false after undoing to the end: layers=0 has_undo=false
SMOKE outline_redo_match PASS outline: redo-to-end shader text byte-equal to the build capture=true has_redo=false
SMOKE outline_redo_render PASS outline: preview renders non-uniform pixels after redo (img_null=false)
SMOKE outline_open_match PASS outline: open_recipe panel shader text equals a fresh codegen of the recipe file=true (fresh_ok=true)
SMOKE outline_open_render PASS outline: preview renders non-uniform pixels after open_recipe (img_null=false)
SMOKE SUMMARY pass=20 fail=0
```

stderr: empty.

The `_history_context` fix was re-verified against phases 4, 5, and 6
(re-running each phase's own smoke unchanged) to confirm no regression:
phase 4 `pass=46 fail=0`, phase 5 `pass=18 fail=0`, phase 6 `pass=16 fail=0`,
all identical to their previously recorded runs above.

`project.godot`'s `config/features` was rewritten to `PackedStringArray("4.6")`
by every run above and reset to `PackedStringArray("4.4")` afterward;
verified via `grep config/features project.godot`. `find sandbox -type f`
after the final run showed only the two committed `.gitkeep`s and the three
committed reference stacks (`sandbox/stacks/dissolve.tres`,
`sandbox/stacks/outline.tres`, `sandbox/stacks/sprite_holographic.tres`,
themselves generated once by a throwaway headless script and committed as
data, never written by the smoke).

### Rendered check: `godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd`

Run via `Start-Process` (not `--headless`, per the plan's verified engine
facts) with redirected stdout/stderr and a 180s timeout. Checks every
`.tres` under `addons/goshade_turbo/recipes/` and `sandbox/stacks/` (six
files: the three recipes plus their three sandbox copies).

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
OpenGL API 3.3.0 NVIDIA 610.88 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

RENDER res://addons/goshade_turbo/recipes/dissolve.tres PASS [] has_TIME=false
RENDER res://addons/goshade_turbo/recipes/outline.tres PASS [] has_TIME=false
RENDER res://addons/goshade_turbo/recipes/sprite_holographic.tres PASS [] has_TIME=true
RENDER res://sandbox/stacks/dissolve.tres PASS [] has_TIME=false
RENDER res://sandbox/stacks/outline.tres PASS [] has_TIME=false
RENDER res://sandbox/stacks/sprite_holographic.tres PASS [] has_TIME=true
run_render_checks: PASS, 6 stack(s) checked
```

stderr: empty. `config/features` unaffected by this run (`-s`, no editor
session).

### Run 3: pass, `gst_undo.gd` history anchor fix (scoped fix, 2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Run 1's own fix note flagged an open finding: `gst_undo.gd::_create_action`
still keyed `custom_context` off the live `_stack` instance, "not proven safe
for a structural edit made directly on a stack immediately after
`Open`/`Reopen Shader`/`open_recipe`, with no intervening `New`." This run
closes that finding.

`GSTUndo._init` now takes `history_context: Resource` (the panel's
`_history_context`, the same bare, always path-less `Resource.new()`
`replace_stack`/`_get_history()` already use) and `_create_action` passes it
as `custom_context` in place of `_stack`. `gst_main_panel.gd` passes
`_history_context` at both `GSTUndo.new()` call sites
(`set_undo_redo_manager`, `replace_stack`). `GSTMainPanel` gained
`get_watched_history() -> UndoRedo` (editor smoke seam), returning
`_watched_history` directly so the smoke can drive `undo()`/`redo()` against
the exact bucket the panel watches instead of recomputing one.

`tests/gst_editor_smoke.gd` gained `_run_phase7_history_anchor`, two
excursions: `open_recipe("dissolve")` with no `New` in between, then
`GSTUndo.add_layer("generative/hash", ...)` with nothing wired -- asserts
`panel.get_watched_history().has_undo()` is true and the shader text resynced
after the add, then `history.undo()` -- asserts the layer is gone from
`stack.layers` and the shader text's codegen body (below the `// stack:`
header line, since the header's `next_id` never reverts on undo of an add
per decision 22 and would otherwise legitimately differ) equals the
post-open capture, then `history.redo()` -- asserts the layer is back. The
`Reopen Shader` path repeats the add/undo pair (no redo) after exporting the
open dissolve stack to `sandbox/exports/gst_editor_smoke_phase7_history.gdshader`
and calling `reopen_shader_path` on it, then deletes the export and its
`.uid` sidecar.

Command run the same way as Runs 1-2 (`Start-Process` with redirected
stdout/stderr, 180s timeout, `GST_EDITOR_SMOKE=7`).

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE dissolve_build PASS dissolve: built stack produces non-empty shader text (len=4314)
SMOKE dissolve_undo_empty PASS dissolve: stack empty and has_undo()=false after undoing to the end: layers=0 has_undo=false
SMOKE dissolve_redo_match PASS dissolve: redo-to-end shader text byte-equal to the build capture=true has_redo=false
SMOKE dissolve_redo_render PASS dissolve: preview renders non-uniform pixels after redo (img_null=false)
SMOKE dissolve_open_match PASS dissolve: open_recipe panel shader text equals a fresh codegen of the recipe file=true (fresh_ok=true)
SMOKE dissolve_open_render PASS dissolve: preview renders non-uniform pixels after open_recipe (img_null=false)
SMOKE sprite_holographic_build PASS sprite_holographic: built stack produces non-empty shader text (len=2294)
SMOKE sprite_holographic_undo_empty PASS sprite_holographic: stack empty and has_undo()=false after undoing to the end: layers=0 has_undo=false
SMOKE sprite_holographic_redo_match PASS sprite_holographic: redo-to-end shader text byte-equal to the build capture=true has_redo=false
SMOKE sprite_holographic_redo_render PASS sprite_holographic: preview renders non-uniform pixels after redo (img_null=false)
SMOKE sprite_holographic_open_match PASS sprite_holographic: open_recipe panel shader text equals a fresh codegen of the recipe file=true (fresh_ok=true)
SMOKE sprite_holographic_open_render PASS sprite_holographic: preview renders non-uniform pixels after open_recipe (img_null=false)
SMOKE outline_build PASS outline: built stack produces non-empty shader text (len=1649)
SMOKE outline_undo_empty PASS outline: stack empty and has_undo()=false after undoing to the end: layers=0 has_undo=false
SMOKE outline_redo_match PASS outline: redo-to-end shader text byte-equal to the build capture=true has_redo=false
SMOKE outline_redo_render PASS outline: preview renders non-uniform pixels after redo (img_null=false)
SMOKE outline_open_match PASS outline: open_recipe panel shader text equals a fresh codegen of the recipe file=true (fresh_ok=true)
SMOKE outline_open_render PASS outline: preview renders non-uniform pixels after open_recipe (img_null=false)
SMOKE history_open_add PASS open_recipe(dissolve) + add generative/hash: has_undo=true resynced=true
SMOKE history_open_undo PASS undo the add: layer_gone=true code_matches_post_open=true
SMOKE history_open_redo PASS redo the add: layer_back=true
SMOKE history_reopen_add PASS reopen_shader_path(dissolve export) + add generative/hash: has_undo=true resynced=true
SMOKE history_reopen_undo PASS undo the add: layer_gone=true code_matches_post_reopen=true
SMOKE SUMMARY pass=25 fail=0
```

stderr: empty. A first attempt at `history_open_undo`/`history_reopen_undo`
compared the undo-time shader text byte-for-byte against the pre-add
capture and failed both (`layer_gone=true code_matches_post_open=false`):
not an anchor bug, but the header's `next_id` field legitimately bumping and
never reverting on undo of an add (decision 22), diagnosed by inspection of
`gst_header.gd`/`gst_codegen.gd` before the fix; both comparisons rescoped
to `GSTOverwriteCheck.find_header_line(code)["body"]` (the same header-scoped
comparison `tests/test_codegen_generator.gd` already uses per its own phase
6 amendment), after which both passed as shown above. `find sandbox -type f`
after this run showed only the two committed `.gitkeep`s and the three
committed reference stacks, confirming
`gst_editor_smoke_phase7_history.gdshader` and its `.uid` sidecar were
deleted.

### Regression re-runs: phases 6 and 4 (same session, same binary)

Both re-run unchanged (no script edits in this scoped fix touched phase 4 or
6 items) to confirm the `GSTUndo` constructor signature change
(`history_context` added as a required parameter) did not regress either.

Phase 6 (`GST_EDITOR_SMOKE=6`): `SMOKE SUMMARY pass=16 fail=0`, identical to
the count recorded in the Phase 6 section above.

Phase 4 (`GST_EDITOR_SMOKE=4`): `SMOKE SUMMARY pass=46 fail=0`, identical to
Run 6's recorded count in the Phase 4 section above.

`project.godot`'s `config/features` was rewritten to
`PackedStringArray("4.6")` by every run in this section (phase 7 Run 3, then
the phase 6 and phase 4 regressions) and reset to `PackedStringArray("4.4")`
once after the last of the three; `git diff project.godot` empty afterward.

### Phase 7 render check, orchestrator run after the review round 1 ordering fix (2026-09-08)

Command: `godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd` on 4.6.2, GPU session. Exit 0.

```
RENDER res://addons/goshade_turbo/recipes/dissolve.tres PASS [] has_TIME=false
RENDER res://addons/goshade_turbo/recipes/outline.tres PASS [] has_TIME=false
RENDER res://addons/goshade_turbo/recipes/sprite_holographic.tres PASS [] has_TIME=true
RENDER res://sandbox/stacks/dissolve.tres PASS [] has_TIME=false
RENDER res://sandbox/stacks/outline.tres PASS [] has_TIME=false
RENDER res://sandbox/stacks/sprite_holographic.tres PASS [] has_TIME=true
run_render_checks: PASS, 6 stack(s) checked
```

The phase-reviewer's sandbox has no GPU; its run of the same command crashed with signal 11 before any `RENDER` line. That crash is environmental, not a code defect.

## Phase 8 (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Method: `$env:GST_EDITOR_SMOKE = "8"` then `godot --editor --path .`, via the
same `Start-Process -RedirectStandardOutput/-RedirectStandardError` wrapper
as phases 4-7, 180s timeout, `config/features` reset to `"4.4"` afterward.

### Regression found while building the recipes: `generative/checker.tres` gained a `cells` param

docs/PLAN.md Phase 8 Build item 1 added a `cells` int param (default 8) to
`generative/checker.tres`, multiplying the coord inside the function so a
checker at pure default coord (scale 1) renders 8 cells across instead of one
uniform cell. Re-running the phase 5 smoke as a regression check (any file
under `tests/gst_editor_smoke.gd` is touched by every later phase's own
`_run_phase8` addition, so a full re-run of 4-7 was done before trusting the
phase 8 result) found `SMOKE 7d3 FAIL`: the negative control that bumps
`coord.scale` to `(2, 2)` under `local` to prove the four-corner comparison
in items 7d1/7d2 can actually fail now lands on a parity that coincidentally
still matches the `uv` reference at exactly those four corner points, once
`cells = 8` changes the sampled grid density. Root cause: the negative
control's specific numbers (`scale = (2, 2)`, corners at `0.125`/`0.875`)
were tuned against the pre-`cells` checker math; a scale bump alone can now
land back on a matching parity by coincidence at that finer density.

Fix: item 7d3 bumps `coord.rotation` (`0.4` radians) instead of `coord.scale`
under `local` only. A rotation shears the cell grid rather than merely
resampling it at a different density, so it reliably moves the corner
samples off the reference's parity regardless of the `cells` value. Comments
in items 1, 2, and the 7d block that claimed "`generative/checker.tres`
carries no manifest params" were corrected to describe the new `cells`
param.

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE 1 PASS checker layer renders non-uniform pixels after 3 frames (img_null=false)
SMOKE 2 PASS checker scale via real EditorProperty widget found=true coord.scale=(6.0, 6.0) uniform=(6.0, 6.0) (expect (6.0, 6.0)) image_changed=true
SMOKE 3a PASS preset=text material_same=true message='text preset: coord space is uv; screen_uv reads more consistently on text (decision 11)' text_nonuniform=true differs_from_sprite=true
SMOKE 3b PASS full_rect_nonuniform=true sprite_nonuniform=true material_still_same=true
SMOKE 4a PASS solo on: has_solo_line=true stack_unchanged=true
SMOKE 4b PASS solo off: code equals pre-solo code byte for byte=true
SMOKE 5 PASS texture source center pixel got=(0.9137, 0.5451, 0.1843, 1.0) want=(0.9176, 0.549, 0.1765, 1.0)
SMOKE 6 PASS screen source center pixel got=(0.898, 0.5373, 0.1804, 1.0) want=(0.9176, 0.549, 0.1765, 1.0)
SMOKE 7a PASS gst_rect_size=(488.0, 74.0) target=(488.0, 74.0) has_varying=true
SMOKE 7b PASS undo restores coord_space to uv: true (actual 0)
SMOKE 7c PASS resized=true before=(488.0, 74.0) after=(584.0, 138.0) gst_rect_size=(584.0, 138.0)
SMOKE 7d1 PASS uv checker corner samples=[(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0)] (expect not all equal)
SMOKE 7d2 PASS local corner samples=[(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0)] match uv corner samples=[(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0)] (tolerance 0.05)
SMOKE 7d3 PASS local rotation=0.4 corner samples=[(1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0)] vs uv reference=[(0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0), (0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0, 1.0)] (expect at least one differs)
SMOKE 8a PASS forced codegen error: message='filter layer 5 (entry filter/pixelate) has no resolved texture or screen source wired to its source slot' code_unchanged=true
SMOKE 8b PASS recovery after removing the filter: message=''
SMOKE SUMMARY pass=18 fail=0
```

Regression re-runs, same session, unaffected by the checker/randomize changes:
phase 4 `SMOKE SUMMARY pass=46 fail=0`, phase 6 `SMOKE SUMMARY pass=16
fail=0`, phase 7 `SMOKE SUMMARY pass=25 fail=0` -- all identical to their
previously recorded counts.

### Randomize (`GST_EDITOR_SMOKE=8`)

`open_recipe("fire")`, the Randomize button's own `_on_randomize_pressed()`
handler, one undo, one redo, `New`. `stderr` empty on every run below.

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE 1 PASS open_recipe(fire) + Randomize: button_enabled=true at_least_one_param_changed=true
SMOKE 2 PASS every param on the randomized stack stays inside its manifest range: true
SMOKE 3 PASS preview renders non-uniform pixels after randomize (img_null=false)
SMOKE 4 PASS undo restores every param to the recipe values: body matches post-open body byte for byte=true
SMOKE 5 PASS redo re-applies the randomized values: body matches post-randomize body byte for byte=true
SMOKE 6 PASS Randomize disabled after New: disabled=true
SMOKE SUMMARY pass=8 fail=0
```

`project.godot`'s `config/features` was rewritten to `PackedStringArray("4.6")`
by every editor run in this section and reset to `PackedStringArray("4.4")`
after each; confirmed clean via `git diff project.godot` (empty) after the
last reset.

### Fix pass: reviewer findings 2, 3, 4, 5 (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Reviewer required: (2) `GSTRandomize.apply` had no live caller --
`_on_randomize_pressed` now registers `GSTRandomize.apply` itself as the
"Randomize sliders" action's do and undo method (`add_do_method`/
`add_undo_method` on `GSTRandomize`, a static-method Callable target,
confirmed valid via a throwaway headless probe before wiring it in), instead
of a per-property `add_do_property`/`add_undo_property` loop. (3)
`replace_stack` did not carry `_recipe_open` through its own undo/redo --
`replace_stack` gained a `new_recipe_open` parameter and now records/replays
`_recipe_open` (and the Randomize button's `disabled` state) the same way it
already does `_stack`/`_current_path`, via `add_do_method`/`add_undo_method`
on `_set_recipe_open`. (4) `run_render_checks.gd` did not propagate a failed
screenshot directory create or a failed `Image.save_png` to `all_passed`/exit
1 -- both now do, the directory failure via one `RENDER ... FAIL` line naming
`sandbox/screenshots` and the per-stack save failure appended to that stack's
own `reasons` list. (5) `test_combinations.gd`'s color-op loop omitted
`filter/*` entries as color-kind inputs -- `color_entry_ids` now includes
every `filter/*` entry, each built as a `source/texture` layer feeding the
filter's own `source` slot before being wired into the color op under test
(20 color-kind entries total: 13 color + 2 source + 5 filter).

`godot --headless --path . -s res://tests/run_codegen_tests.gd`:

```
test_combinations: color-op x color-entry combinations checked: 200 (10 color ops x 20 color-kind entries, filters included per fix pass 3 item 5)
GST tests: 21 file(s), 122 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

`godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd -- --write-screenshots` (`Start-Process`, 300s timeout): all 78 stacks
`PASS`, `run_render_checks: PASS, 78 stack(s) checked`, exit 0. No `screenshot
dir` or `screenshot save` FAIL lines (the directory already existed and every
`save_png` succeeded), so the new failure paths were not exercised by a real
failure on this run; the propagation logic itself was read against
`GSTRenderAssert.check`'s existing `reasons` plumbing rather than forced
end-to-end, since forcing an actual directory-create or PNG-save failure
would mean sabotaging the sandbox in a way this fix pass had no reason to do.

Smoke (`GST_EDITOR_SMOKE=8`), extending the existing Randomize run with items
7-9 for finding 3 (recipe-open state through New's own undo/redo, then two
more undos past it):

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org

SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE 1 PASS open_recipe(fire) + Randomize: button_enabled=true at_least_one_param_changed=true
SMOKE 2 PASS every param on the randomized stack stays inside its manifest range: true
SMOKE 3 PASS preview renders non-uniform pixels after randomize (img_null=false)
SMOKE 4 PASS undo restores every param to the recipe values: body matches post-open body byte for byte=true
SMOKE 5 PASS redo re-applies the randomized values: body matches post-randomize body byte for byte=true
SMOKE 6 PASS Randomize disabled after New: disabled=true
SMOKE 7 PASS undo New: Randomize re-enabled=true
SMOKE 8 PASS redo New: Randomize disabled again=true
SMOKE 9 PASS undo twice more (past New, past randomize): Randomize still enabled=true body matches post-open body=true
SMOKE SUMMARY pass=11 fail=0
```

stderr: empty. `project.godot`'s `config/features` was rewritten to
`PackedStringArray("4.6")` by this run and reset to `PackedStringArray("4.4")`
afterward; confirmed via `git diff project.godot` (empty) after the reset.

### Headless suite and render checks, 4.6.2 baseline

`godot --headless --path . -s res://tests/run_codegen_tests.gd`:

```
GST tests: 21 file(s), 122 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

`godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd -- --write-screenshots`:
every reference stack (54), every recipe (12, twice -- once under
`addons/goshade_turbo/recipes/`, once under `sandbox/stacks/`) checked, all
`PASS`, `run_render_checks: PASS, 78 stack(s) checked`. Full per-stack output
recorded above under "Rendered check" is representative; the final run after
the 9 new recipes landed printed the same shape with 12 additional recipe
lines (`fire`, `glow`, `hologram`, `metaball_portal`, `sprite_foil`,
`sprite_oil_slick`, `sprite_opal`, `sprite_pearl`, `water`, each twice) and
`run_render_checks: PASS, 78 stack(s) checked` (previously 60). Screenshots
written to `sandbox/screenshots/*.png` (66 files: 78 stacks collapse to 66
distinct file stems, since a recipe's `addons/.../recipes/<name>.tres` copy
and its `sandbox/stacks/<name>.tres` copy share one screenshot filename --
pre-existing behavior from phase 7, not new here).

## Version matrix

Run for docs/PLAN.md Phase 8 Build item 5 and Blocker B2: the same two named
verification commands against 4.4 and 4.7 by absolute path, plus the 4.6.2
baseline above recorded again here for one-place comparison. Every summary
line below is the runner's own verbatim output.

### `Godot_v4.6.2-stable_win64.exe` (`C:\Users\atk67\Desktop\Godot_v4.6.2-stable_win64.exe`, resolved via the `godot` PATH shim)

`--version`: `4.6.2.stable.official.71f334935`

`godot --headless --path . --import`: exit 0, no errors.

`godot --headless --path . -s res://tests/run_codegen_tests.gd`:
```
GST tests: 21 file(s), 122 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

`godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd`:
```
run_render_checks: PASS, 78 stack(s) checked
```

### `C:\Users\atk67\Downloads\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64.exe`

`--version`: `4.4.stable.official.4c311cbee`

`godot --headless --path . --import`: exit 0. Stderr printed seven
`ERROR: Do not use progress dialog (task) while flushing the message queue
or using call_deferred()!` / `ERROR: Condition "!tasks.has(p_task)" is true.`
lines from the editor's own progress-dialog internals during the import
scan; `.godot/global_script_class_cache.cfg` was still created and every
later command ran clean. Environmental (a 4.4-editor-internal progress
dialog race during first-scan import), not a project defect: the plan's
prerequisite step is not the named verification command itself, and the
named commands below printed no such lines.

`godot --headless --path . -s res://tests/run_codegen_tests.gd`:
```
GST tests: 21 file(s), 122 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

`godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd`:
```
run_render_checks: PASS, 78 stack(s) checked
```

No manifest/recipe churn: `git status --porcelain -- addons/goshade_turbo/library addons/goshade_turbo/recipes`
showed only this implementer's own intentional edits/adds (`checker.tres`,
`cellular_edges.tres` modified in earlier phase 8 work, `sdf/` and the nine
new recipes newly added) both before and after this run; `git diff
project.godot` was empty (headless `-s`/`--import` runs never touch
`config/features`, only `--editor`/windowed sessions do).

### `C:\Users\atk67\Documents\godot\Godot_v4.7-stable_win64.exe`

`--version`: `4.7.stable.official.5b4e0cb0f`

`godot --headless --path . --import`: exit 0, no errors.

`godot --headless --path . -s res://tests/run_codegen_tests.gd`:
```
GST tests: 21 file(s), 122 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

`godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd`:
```
run_render_checks: PASS, 78 stack(s) checked
```

No manifest/recipe churn (B2, plan decision "Manifests are never re-saved"):
`git status --porcelain -- addons/goshade_turbo/library addons/goshade_turbo/recipes`
identical before and after this run; `git diff project.godot` empty. Every
command here was `-s`/`--import`, never `--editor`, so no `.tres` was ever
opened by the 4.7 editor's own save path.

### Summary

All three engine versions: `--import` exit 0, headless suite
`122 test method(s), 0 failure(s)`, rendered checks `PASS, 78 stack(s)
checked`. No failure on 4.4 or 4.7 versus the 4.6.2 baseline; no code change
was needed against decision 17's Godot-4.4-minimum API surface.

### Fix pass 2: reviewer finding 1 (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Reviewer required: keep `GSTRandomize.apply` as the live undo/redo writer,
refresh the selected layer's `EditorInspector` after apply/undo/redo, and
extend `tests/gst_editor_smoke.gd`'s Randomize section to verify an actual
parameter `EditorProperty` after randomize, undo, and redo -- not only the
`GSTLayer` model and the shader body.

`GSTRandomize.apply` now writes each param through `layer.set(param, value)`
(so `GSTLayer._set` runs, matching a real inspector edit's own write path)
and calls `layer.emit_changed()` once per touched layer. `gst_main_panel.gd`
registers a new `_refresh_inspector` method (relaying to a new
`GSTInspectorColumn.refresh()`) as both the do and undo method of the
"Randomize sliders" action, alongside `GSTRandomize.apply` itself, so apply,
undo, and redo all force the inspector to re-read. `EditorInspector` exposes
no `refresh()` method on 4.6.2 (checked against a `--doctool` class-doc
dump: only `edit()`, `get_edited_object()`, `get_selected_path()`, and
`instantiate_property_editor()` are bound), so `GSTInspectorColumn.refresh()`
clears the edited object first (`edit(null)`) and re-points it (`edit(_layer)`),
rather than re-calling `edit()` on the object it already has open.

`tests/gst_editor_smoke.gd`'s Randomize section (`_run_phase8`) now selects
`fire.tres`'s `generative/fbm` layer (id `"0"`, param `gain`, float, manifest
range `[0.2, 0.8]`) before randomizing, finds its real `EditorProperty` via
`GSTInspectorColumn.find_editor_property`, and reads the displayed value off
the widget's own `Range` descendant control (a `SpinBox`/`EditorSpinSlider`),
not the `GSTLayer` model, at four points: before randomize (must equal the
model), after randomize (must equal the new model value and differ from the
pre-randomize display), after one undo (must equal the original), after one
redo (must equal the randomized value again). `gain` was chosen over
`fieldops/smoothstep`'s `edge0`/`edge1` (fire.tres's other float params on a
selectable layer): at the time of this run, `fire.tres`'s `edge0 = -0.3` sat
outside `edge0`'s manifest range, then `[0.0, 1.0]` (widened later in phase 8
to `[-1.0, 2.0]`, which now contains `-0.3`), and a `PROPERTY_HINT_RANGE`
widget clamps its displayed value to the hint's min/max, so the display
could never equal that out-of-range model value regardless of whether the
refresh fix worked -- confirmed by a first run against `edge0` that failed
items "1b" and "4b" on exactly that clamp, with "3b" (post-randomize, back
inside range) passing. `gain`'s shipped value (`0.5`, the manifest default)
stays inside its own range, avoiding the clamp confound entirely.

`godot --headless --path . -s res://tests/run_codegen_tests.gd` (after
switching `GSTRandomize.apply` to `layer.set()`, `tests/test_randomize_range.gd`'s
`test_apply_writes_every_changed_value_onto_the_layer` needed its own layer's
`manifest` resolved before calling `apply()`, matching what every real caller
already guarantees; `GSTRandomize.randomize` itself is unaffected, since it
never calls `Object.set()`):

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org

Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org

test_combinations: color-op x color-entry combinations checked: 200 (10 color ops x 20 color-kind entries, filters included per fix pass 3 item 5)
GST tests: 21 file(s), 122 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

Smoke (`GST_EDITOR_SMOKE=8`), the Randomize section with the new
`EditorProperty` checks "1b", "3b", "4b", "5b" interleaved:

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE 1b PASS pre-randomize gain EditorProperty found=true displayed=0.5 layer=0.5
SMOKE 1 PASS open_recipe(fire) + Randomize: button_enabled=true at_least_one_param_changed=true
SMOKE 2 PASS every param on the randomized stack stays inside its manifest range: true
SMOKE 3 PASS preview renders non-uniform pixels after randomize (img_null=false)
SMOKE 3b PASS post-randomize gain EditorProperty found=true displayed=0.231 layer=0.23148301243782 changed_from_pre=true
SMOKE 4 PASS undo restores every param to the recipe values: body matches post-open body byte for byte=true
SMOKE 4b PASS undo gain EditorProperty found=true displayed=0.5 expected=0.5
SMOKE 5 PASS redo re-applies the randomized values: body matches post-randomize body byte for byte=true
SMOKE 5b PASS redo gain EditorProperty found=true displayed=0.231 expected=0.23148301243782
SMOKE 6 PASS Randomize disabled after New: disabled=true
SMOKE 7 PASS undo New: Randomize re-enabled=true
SMOKE 8 PASS redo New: Randomize disabled again=true
SMOKE 9 PASS undo twice more (past New, past randomize): Randomize still enabled=true body matches post-open body=true
SMOKE SUMMARY pass=15 fail=0
```

stderr: empty. `project.godot`'s `config/features` was rewritten to
`PackedStringArray("4.6")` by this run and reset to `PackedStringArray("4.4")`
afterward; confirmed via `git diff project.godot` (empty) after the reset.

### Fix-now pass: reviewer findings 2, 3, 4 (2026-09-08, `Godot_v4.6.2-stable_win64.exe`)

Reviewer required: (2) make the selected `gain` randomization deterministic
so `_run_phase8`'s "3b" check cannot fail by chance -- `GSTMainPanel` gained
`set_randomize_rng(rng: RandomNumberGenerator)` (`Wired-by: none (editor
smoke seam)`), read by `_on_randomize_pressed` in place of a fresh
OS-seeded RNG when set. `_run_phase8` now seeds two
`RandomNumberGenerator`s with the same value (`424242`): one runs
`GSTRandomize.randomize` against an independently-loaded copy of
`fire.tres` to compute `expected_gain`, the other is handed to the panel via
`set_randomize_rng` before pressing the real button, so "3b" asserts the
displayed value equals `expected_gain` instead of merely differing from the
pre-randomize value. New check "1c" confirms the expectation stack itself
loaded. (3) `_on_randomize_pressed`'s `_resync_material()`/
`_refresh_inspector()` calls after `commit_action()` were a duplicate of
work `commit_action` already does (its do methods run `GSTRandomize.apply`
and `_refresh_inspector` once, and `_history_context`'s `version_changed`
signal, watched by `_on_history_version_changed`, already calls
`_resync_material()`) -- both duplicate calls removed. (4) the stale `[0.0,
1.0]`/`[0, 1]` smoothstep range explanation, obsolete after `smoothstep.tres`
was widened to `[-1.0, 2.0]` earlier in phase 8, corrected in
`tests/test_recipe_roundtrip.gd`'s `test_every_stored_param_stays_inside_its_manifest_range`
doc comment and in this file's phase 8 "Fix pass 2" narrative.

`godot --headless --path . --import`: exit 0, no errors.

`godot --headless --path . -s res://tests/run_codegen_tests.gd`:

```
test_combinations: color-op x color-entry combinations checked: 200 (10 color ops x 20 color-kind entries, filters included per fix pass 3 item 5)
GST tests: 21 file(s), 123 test method(s), 0 failure(s)

run_codegen_tests: PASS, child exit 0 and no error markers in output
```

`godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd`:
`run_render_checks: PASS, 78 stack(s) checked`.

Smoke (`GST_EDITOR_SMOKE=8`), the Randomize section with the new seeded
"1c"/"3b":

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 5070 Ti Laptop GPU

SMOKE setup1 PASS panel present
SMOKE setup2 PASS panel.visible after set_main_screen_editor=true
SMOKE 1b PASS pre-randomize gain EditorProperty found=true displayed=0.5 layer=0.5
SMOKE 1c PASS expectation stack for the randomize seed loads: ok=true
SMOKE 1 PASS open_recipe(fire) + Randomize: button_enabled=true at_least_one_param_changed=true
SMOKE 2 PASS every param on the randomized stack stays inside its manifest range: true
SMOKE 3 PASS preview renders non-uniform pixels after randomize (img_null=false)
SMOKE 3b PASS post-randomize gain EditorProperty found=true displayed=0.344 layer=0.34438347816467 expected(seed=424242)=0.34438347816467 matches_expected=true
SMOKE 4 PASS undo restores every param to the recipe values: body matches post-open body byte for byte=true
SMOKE 4b PASS undo gain EditorProperty found=true displayed=0.5 expected=0.5
SMOKE 5 PASS redo re-applies the randomized values: body matches post-randomize body byte for byte=true
SMOKE 5b PASS redo gain EditorProperty found=true displayed=0.344 expected=0.34438347816467
SMOKE 6 PASS Randomize disabled after New: disabled=true
SMOKE 7 PASS undo New: Randomize re-enabled=true
SMOKE 8 PASS redo New: Randomize disabled again=true
SMOKE 9 PASS undo twice more (past New, past randomize): Randomize still enabled=true body matches post-open body=true
SMOKE SUMMARY pass=16 fail=0
```

stderr: empty, exit 0. `project.godot`'s `config/features` was rewritten to
`PackedStringArray("4.6")` by this run and reset to `PackedStringArray("4.4")`
afterward; confirmed via `git diff project.godot` (empty) after the reset.

## Version matrix, final phase 8 tree (2026-09-09, orchestrator run)

Commands per binary: `--headless --path . --import`, then `--headless --path . -s res://tests/run_codegen_tests.gd`, then `--path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd`. `project.godot` `config/features` reset to `"4.4"` after each binary. `git status` under `addons/goshade_turbo/library` and `addons/goshade_turbo/recipes` after the 4.7 run showed only the phase 8 edits already in the tree; no manifest or recipe was re-saved by 4.4 or 4.7.

```
=== 4.4 : C:/Users/atk67/Downloads/Godot_v4.4-stable_win64.exe/Godot_v4.4-stable_win64.exe
4.4.stable.official.4c311cbee
GST tests: 21 file(s), 123 test method(s), 0 failure(s)
run_codegen_tests: PASS, child exit 0 and no error markers in output
run_render_checks: PASS, 78 stack(s) checked
=== 4.6.2 : godot (PATH wrapper)
GST tests: 21 file(s), 123 test method(s), 0 failure(s)
run_codegen_tests: PASS, child exit 0 and no error markers in output
run_render_checks: PASS, 78 stack(s) checked
=== 4.7 : C:/Users/atk67/Documents/godot/Godot_v4.7-stable_win64.exe
4.7.stable.official.5b4e0cb0f
GST tests: 21 file(s), 123 test method(s), 0 failure(s)
run_codegen_tests: PASS, child exit 0 and no error markers in output
run_render_checks: PASS, 78 stack(s) checked
```

## Editor UI redesign, phase 1 (2026-09-08)

Source: `docs/EDITOR_UI_DESIGN_reviewed-plan.md`, phase 1. Verification uses `tests/gst_editor_ui_layout_smoke.gd` through selector `GST_EDITOR_SMOKE=ui_layout` on Godot `4.6.2`, OpenGL compatibility rendering, NVIDIA GeForce RTX 5070 Ti Laptop GPU.

### Geometry and interaction evidence

- Pre-change editor run: host `1346x1002`, panel `1346x181`, root size flags `1/1`, preview `644x74`.
- Pre-change result: `pass=1 fail=2`; the full-height assertion failed and the new layout measurement API was absent.
- Final run explicitly set the editor window to `1366x768`; surrounding Godot docks remained visible.
- Final editor scale: `1.00`; host and panel both occupy `(287,80), 792x641`; root size flags are `3/3`.
- Editing area: `(287,129), 473x592`; preview area: `(763,129), 316x592`; divider width: `3`.
- Default editing width: `473`, compared with `473.4` for `60%` of the available child width.
- Preview control and rendered viewport: `316x358`; Final output: `(763,618), 316x70`.
- Measured editing breakpoint: `388`; configured preview minimum: `220x180`.
- The before/after runs use different host sizes. They verify the collapsed-height defect and its removal; they do not establish a same-window size multiplier.
- Captured `1366x768` editor image was inspected by the implementer and orchestrator: titled sections and separators are visible; Final output remains beneath the preview.

```text
SMOKE ui_layout_file_menu PASS items=["New", "Open...", "Save As...", "Reopen Shader..."] new_installed=true save_export_visible=true
SMOKE ui_layout_section_persistence PASS collapsed=true content_visible=false metadata={ "inputs": true, "parameters": false, "position": false }
SMOKE ui_layout_split_persistence PASS inner=0.455->0.506->0.506 main=0.599->0.525->0.525
SMOKE ui_layout_responsive_tabs PASS breakpoint=388.0 widths=388.0/473.0 narrow=true wide=false enclosed=true/true one_inspector=true tab_persisted=true
SMOKE ui_layout_stable_scroll PASS items=20 selected=true reorder=true anchor=13/13/13 fixed_rows=true
SMOKE ui_layout_native_preview_edit PASS editor_property=true image_before=(316, 358) image_after=(316, 358)
SMOKE SUMMARY pass=14 fail=0
```

- Both splitter checks inject mouse events into the editor viewport and verify movement before restoring metadata.
- Responsive checks resize the actual editor window and move its divider; both layouts remain inside the host with one native inspector.
- The stack check exercises `20` layers, real scrolling, reordering, rebuilding, retained selection, and a stable first-visible layer ID.
- The long-content check verifies a long input caption inside Layer settings and a wrapped refusal inside the preview area.
- The native parameter check requires non-null before/after GPU images and verifies their pixels change through an `EditorProperty` edit.
- Exit: `0`; stderr: empty.

### Regression evidence

- Implementer runs of existing editor selectors passed on `4.6.2`: `4` = `46/0`, `5` = `18/0`, `6` = `16/0`, `7` = `25/0`, `8` = `16/0` (pass/fail).
- Orchestrator reran `godot --headless --path . --import` after the final smoke-only cleanup: exit `0`, no script errors.
- Orchestrator reran `godot --headless --path . -s res://tests/run_codegen_tests.gd` on the final implementation: `21` files, `123` methods, `0` failures; wrapper exit `0`, no error markers.
- `project.godot` minimum version restored to `4.4` after editor-generated `4.6` churn.
- Phase 1 has not rerun the redesign on `4.4` or `4.7`; the earlier version matrix describes the pre-redesign tree.
- Independent review round `1`: unit suite `123/0`; GPU `ui_layout` `14/0`, exit `0`.
- Reviewer code inspection found that metadata restore updates the saved narrow-tab value without always selecting that visible tab. The existing assertion inspected the backing value, so the review verdict is `FAIL` pending a production fix and visible-pane regression check.
- The review sandbox denied Godot AppData/cache writes. Its GPU assertions completed, but that run does not establish persistence across editor restarts.

### Review round 1 fix

- Strengthened the narrow-tab test to select visible tab `0`, restore saved tab `1`, and inspect `EditingTabs.current_tab` plus both pane visibilities.
- Before the production fix: `different_start=true tab_persisted=false`, `13/1`, exit `1`.
- Fixed `_apply_restored_layout` to apply the preferred tab when narrow mode is active.
- After the fix: `different_start=true tab_persisted=true`, `14/0`, exit `0`; stderr empty.
- Final import passed; named unit suite passed `21` files, `123` methods, `0` failures.
- `project.godot` restored to `4.4`; `git diff --check` passed.

### Independent re-review

- Verdict: `PASS`; no required fixes, deferred notes, or additional docs impact.
- Named unit command: `21` files, `123` methods, `0` failures.
- GPU `ui_layout`: `14/0`, exit `0`, stderr empty.
- Visible-tab restore: `different_start=true tab_persisted=true`; both pane visibility assertions passed.
- Splitter persistence, responsive tabs, overflow, preview allocation, and native parameter edits passed.
- Orchestrator restored `project.godot` to `4.4` after the review run. Phase 1 is ready for commit approval; phases 2 through 5 remain pending.

## Editor UI redesign, phase 2 (2026-09-08)

Source: `docs/EDITOR_UI_DESIGN_reviewed-plan.md`, phase 2. Phase 1 was committed as `1c7ae37` before phase 2 began.

### Test-first evidence and limits

- Added unit cases for immediate-below input defaults, source restrictions, unknown slots, color warp conversion, and field-output transparency before production changes.
- Added editor selector `ui_actions` for compound add/undo/redo, refusal state, stable IDs, and existing-resource input restoration.
- Pre-change sandboxed engine runs crashed before test summaries; a redirected run exited `-1073741819` with signal `11`.
- An elevated redirected run produced an engine banner but no assertions within `30` seconds; the implementer terminated only its own wrapper/child processes.
- No pre-change assertion failure was observed. These attempts do not establish a passing or failing behavior result.
- Final verification and independent review remain pending.

### Initial verification

- Sandbox import logs identify denied access to Godot's AppData directories. Elevated `4.6.2` import then passed with exit `0`.
- Named unit suite: `21` files, `132` methods, `0` failures; wrapper reports child exit `0` and no error markers.
- GPU render suite: `78` stacks checked, `PASS`, exit `0`.
- New editor `ui_actions` initially passed `18/0` assertions but exited `-1073741819` after its summary on two runs. Assertion success alone does not satisfy its exit criterion.
- Existing `ui_layout`: `14/0`, exit `0`.
- Existing selector `4` initially reported `49/1`: one legacy undo assertion expected an empty input, although the new UI add explicitly assigned the immediately preceding layer. The assertion was updated to verify that assigned layer is restored.

### Final implementation verification

- Import: exit `0`. Final named unit suite: `21` files, `134` methods, `0` failures; wrapper exit `0` and no error markers.
- GPU render suite: `78` stacks, `PASS`, exit `0`.
- `ui_actions`: `20/0`, exit `0`, stderr empty. The final test waits for five process frames and reads the final preview before quitting.
- The exact cause of the earlier shutdown access violations was not isolated. The final run exited normally; independent review must repeat the current action smoke.
- An attempted `RenderingServer.frame_post_draw` wait did not complete in the hidden editor; it was removed. No passing result is claimed for that experiment.
- A new warp-candidate check initially compared integer metadata to a `StringName`; the test now checks the metadata type before comparing it.
- Existing editor selectors: `ui_layout` = `14/0`, `4` = `50/0`, `5` = `18/0`, `6` = `16/0`, `7` = `25/0`, `8` = `16/0`; each exited `0`.
- `project.godot` restored to `4.4`; `git diff --check` passed. Independent review is pending.

### Independent phase 2 review

- Verdict: `PASS`; no required fixes, fix-now notes, deferred notes, or additional docs impact.
- Named unit command: `21` files, `134` methods, `0` failures; exit `0`.
- GPU rendered checks: `78` shipped recipe/sandbox stacks passed; exit `0`.
- `ui_actions`: `20/0`, exit `0`, stderr empty. The earlier shutdown access violation did not recur in this independent run.
- `ui_layout`: `14/0`; selectors `4` through `8`: `50/0`, `18/0`, `16/0`, `25/0`, `16/0`; every process exited `0`.
- Reviewer confirmed compound undo, refusal atomicity, source restrictions, stable instances/IDs, retained fallback behavior, warp conversion, and field transparency.
- Orchestrator restored the minimum feature version to `4.4` after review. Phase 2 is ready for commit approval; phases 3 through 5 remain pending.

## Editor UI redesign, phase 3 (2026-09-08)

Source: `docs/EDITOR_UI_DESIGN_reviewed-plan.md`, phase 3. Phase 2 was committed as `161a27b` before phase 3 began.

### Test-first evidence

- Added metadata completeness coverage before changing shipped manifest dictionaries.
- Added compatibility checks for every shipped function's export/header bytes, stack resource bytes, native property keys, and uniform names.
- Pre-metadata named unit command on `4.6.2`: `GST tests: 21 file(s), 138 test method(s), 200 failure(s)`.
- The failures reported missing input/parameter labels and descriptions. Wrapper: `run_codegen_tests: FAIL, child process exit code 1`.
- Runtime native-editor verification and independent review are pending.

### Metadata audit

- Added labels and descriptions to `100` dictionaries across `45` manifests. The other `9` shipped manifests contain no input or parameter dictionaries.
- Orchestrator stripped only the appended metadata lines and compared all `45` changed manifests with `161a27b`; every original line matched after line-ending normalization.
- The audit checked descriptions against shader formulas and corrected chromatic-split direction, blur grid spacing, and line endpoint wording.
- Palette Vector3 tooltips identify `X/Y/Z` as red/green/blue; parameter identifiers remain `a/b/c/d`.

### Initial runtime findings

- Pre-implementation `ui_labels` reported `1/1` because separate parameter/coordinate inspectors were absent.
- Import and the named unit suite passed after implementation: `21` files, `138` methods, `0` failures.
- The first implemented `ui_labels` run exposed recursive inspector-plugin dispatch inside `instantiate_property_editor`; stderr reported a stack overflow in `_parse_property`.
- That run is a failure. Native-editor construction requires a re-entry guard before the version matrix can pass.
- The re-entry guard removed the stack overflow. Native parameter/coordinate edits and undo passed on the next run; tooltip assertions failed because the engine reset tooltip text during setup.
- Deferred tooltip assignment passed the tooltip assertions. Screenshot review then found clipped labels and empty model-category headings despite passing assertions.
- Added visible-control and label-width checks. These initially failed after the calculated minimum width activated the narrow tab layout; visible-pane verification remains required.

### Resolved presentation checks

- The orchestrator inspected `ui_labels-4.6.2-final2.png`: complete native parameter/coordinate labels, separate titled sections, and no empty `Resource` heading.
- The same run reported `17/0` and exit `0`; the native parameter and coordinate edit/undo checks passed.
- Input labels occupy their own full-width line above the selector. A long comparison label fits without splitting words into a narrow side column.
- Settings use one outer scroll container. Both native inspectors size to their contents inside it.
- Native label minimum width is calculated from the active font, label text, and native name split ratio; the existing narrow-tab behavior supplies the editing width.
- Hidden model properties retain storage usage. Inherited `resource_path` was the remaining cause of the empty resource section.
- The cross-version matrix and independent review are pending.

### Final implementation verification

- Import on `4.6.2`: exit `0`. Named unit suite: `GST tests: 21 file(s), 138 test method(s), 0 failure(s)`; wrapper exit `0`.
- `ui_labels`: `4.4` = `14/0`, `4.6.2` = `17/0`, `4.7` = `14/0`; every process exited `0`.
- Final editor logs identify OpenGL `3.3.0` Compatibility rendering on the NVIDIA GeForce RTX `5070 Ti` Laptop GPU.
- The `4.6.2` run includes three additional screenshot-save assertions; the other versions run the same fourteen behavioral assertions.
- After the `4.4` and screenshot `4.6.2` runs, a test-only adjustment records native widget presence before an edit can rebuild that widget. The final `4.7` run uses this test; production code is unchanged between these version runs. Independent review must run the final smoke on the earlier versions.
- `ui_layout` on `4.6.2`: `14/0`, exit `0`. The responsive test now selects a generator before checking inspector targets and restores the original window after testing a wider layout.
- Responsive evidence: editing widths `364/806`, inspector counts `2/2`, targets correct in both layouts, visible-tab persistence passed.
- Default allocation at `1366x768`: host/root `792x641`, editing width `473`, preview area width `316`, rendered preview `316x358`, Final output `316x70`.
- Existing native-editor selector `4`: `50/0`; recipe-randomize selector `8`: `16/0`; both exited `0`.
- `project.godot` restored to minimum `4.4`; `git diff --check` passed. All owned Godot processes exited.
- Independent review is pending.

### Independent phase 3 review

- Verdict: `PASS`; no required code fixes, deferred defects, blockers, or additional documentation impact.
- Reviewer read all `59` modified files and `4` untracked files.
- Named unit suite: `21` files, `138` methods, `0` failures; exit `0`.
- Final `ui_labels` on `4.4` and `4.6.2`: `14/0` each, exit `0`, stderr empty. These reruns include the final widget-lifetime assertion.
- `ui_layout` on `4.6.2`: `14/0`, exit `0`, stderr empty.
- Reviewer verified visible native widgets, metadata labels/tooltips/hints, resource and uniform updates, undo, bounded input labels, and retained inspector instances through responsive reparenting.
- The `4.7` final assertion run remains the implementer's `14/0` evidence; independent review did not repeat it.
- Orchestrator restored only `project.godot` feature metadata to `4.4` after review. No production code changed after the passing review.
- Phase 3 is ready for commit approval. Phases 4 and 5 remain pending.

## Editor UI redesign phase 4: embedded choosers

### Implementation and evidence

- Phase 3 committed as `68d0c6e`; this section records phase 4 verification.
- `GST_EDITOR_SMOKE=ui_picker` dispatches `tests/gst_editor_ui_picker_smoke.gd` inside the real editor.
- Evidence directory: `C:/Users/atk67/.codex/visualizations/2026/09/09/01a083c7-014d-7361-ae67-8eddff9c46f1/phase4-evidence`.
- Baseline `red.stdout.log`: embedded `PanelContainer` assertion failed before implementation.
- Add Layer, inputs, distortion, Recipes, output color, and Transparency now share the editing-area chooser.
- Input and distortion choices use Existing layers and Add new tabs; both include eligible automatic conversions.
- `GSTUndo.add_layer_below_and_wire_warp` adds, initializes, inserts, and connects a distortion source in one undo action without changing output.
- `GSTUndo.add_layer_for_ui` rejects input-dependent entries on an empty stack before allocating an ID.
- Native parameter and coordinate inspectors remain the property-editing surface.
- Control refusal labels and the code generation label have independent state. Code generation errors appear above the preview.

### Failures found during implementation

- Early keyboard tests ran before the editor finished startup. Events reached the panel but native controls did not receive them; waiting for startup allowed actual viewport keyboard dispatch.
- Enter uses native `LineEdit.text_submitted` and `Tree.item_activated` signals. Single-click activation uses the tree's selected item.
- An applied input edit rebuilt its button before focus restoration. Closing now resolves the current destination button.
- Screenshot inspection found the chooser inheriting an empty panel style, leaving underlying controls visible. The chooser now supplies an opaque editor-colored panel.
- Resizing exposed stale tree-column minimum widths and horizontal scrolling. Columns now use expansion ratios updated on the tree's own resize signal.
- The native label smoke inherited a collapsed Inputs section and measured hidden rows. It now expands sections, requires visible positive geometry, and restores the previous section state.
- A temporary test indentation error caused one bounded timeout and unrelated script-load errors in the following label run. That run is not clean verification; the typo was corrected before `ui_picker-final2`.
- Recipe replacement left the inspector editing an old resource. Stack installation now points it at the selected layer in the installed stack.
- A preview coordinate suggestion survived switching back to Sprite. Preset changes now update only their own message state.

### Implementation verification on 4.6.2

- Import exited `0` with empty stderr before integration runs.
- Named unit suite: `21` files, `138` test methods, `0` failures; wrapper exit `0`. Independent review must repeat after the final empty-stack guard.
- `ui_picker-final2.stdout.log`: `45/0`, normal exit, empty stderr.
- Chooser coverage includes actual mouse activation, arrow navigation, Enter, Escape, focus return, retained search/context, description search, earlier/source eligibility, conversions, and every Transparency mode.
- Atomic distortion add/undo/redo preserves output and resource identity; invalid destinations allocate no ID or history action.
- Stale stack and removed destination checks retain the captured context and register no edit.
- Mutating handlers and undo shortcut are blocked while open. Save and Export file dialogs remain reachable; animated fire preview pixels continue changing.
- `1366x768` default allocation: host/root `792x641`, editing `473x559`, preview area `316x559`, rendered preview `316x358` before adding a conversion row to Final output.
- Wide-to-narrow transition retained context. Narrow editing width measured `443`; preview remained `296x180`.
- At the restored `1366x768` size, tree columns total `439` pixels inside a `453`-pixel tree; conversion text line widths fit the visible kind column.
- Orchestrator inspected `picker-conversion.png`: opaque chooser, all three columns visible, complete two-line luminance conversion, persistent output grayscale tag, and visible preview.
- `ui_layout-2`: `15/0`, empty stderr, including independent stack/settings refusal bounds and removal cleanup.
- `ui_actions-1`: `20/0`, empty stderr.
- Legacy selectors: `4` = `50/0`, `5` = `18/0`, `6` = `16/0`, `7` = `25/0`, `8` = `16/0`.
- Selector `5` reports the existing direct-PNG-load warnings in its texture/screen test fixtures; assertions pass.
- Final native label rerun and independent review are pending. The complete cross-version matrix remains phase 5 work.

### Independent phase 4 review, round 1

- Verdict: `FAIL`; one required test correction, no production defect, documentation impact, or deferred note reported.
- Import on `4.6.2`: exit `0`, empty stderr.
- Named unit suite: `138/0`, exit `0`, empty stderr.
- `ui_picker` on `4.6.2`: `45/0`; `ui_labels`: `14/0`; `ui_layout`: `15/0`; `ui_actions`: `20/0`. All exited `0` with empty stderr.
- `ui_picker` on `4.4`: `44/1`, exit `1`, empty stderr.
- The failed assertion assumed a requested `720x600` editor size forced narrow mode. Godot `4.4` clamped the host width to `781`, giving editing `466` pixels against a `458`-pixel breakpoint; wide mode remained valid.
- Required correction: drag the splitter below the measured breakpoint when resizing does not cross it; retain actual-crossing, narrow-mode, frozen-context, and enclosure assertions.
- Re-review and passing chooser runs on both versions are required before the commit gate.

### Round 1 fix verification

- The chooser smoke captures the actual wide breakpoint and drives the real main splitter when resizing leaves editing above it.
- On `4.4`, the first drag stopped at the wide minimum while activating tabs. A second conditional drag then crossed below that threshold using the reduced tab minimum.
- The test retains strict below-breakpoint, active-tab-layout, frozen-context, and picker-enclosure assertions.
- `fix2-ui_picker-4.4` and `fix2-ui_picker-4.6.2`: `45/0` each, normal exits, empty stderr.
- Production code is unchanged after the first independent review. Re-review is pending.

### Independent phase 4 re-review

- Verdict: `PASS`; no required fixes, fix-now notes, deferred notes, or documentation impact.
- Final `ui_picker` on `4.4` and `4.6.2`: `45/0` each, exit `0`, empty stderr.
- Actual narrow crossings: `4.4` editing width `434` against breakpoint `458`; `4.6.2` editing width `443` against breakpoint `471`.
- Reviewer confirmed real splitter input, strict threshold crossing, preserved destination, and enclosed chooser.
- `git diff --check` passed. All owned Godot processes exited.
- Orchestrator restored only `project.godot` feature metadata to `4.4` after review.
- Phase 4 is ready for commit approval. Phase 5 remains pending.

## Editor UI redesign, phase 5: entry flow and preview recovery (2026-09-09)

Status: independent phase review passed; user authorized the phase 5 commit on 2026-09-09.

### Implementation and test baseline

- Initial editing area offers every bundled recipe, Open stack, and Create Empty Stack.
- Create Empty Stack and File > New install an empty stack and open the first-layer library immediately.
- Start-screen dismissal remains navigation state; replacement undo returns to ordinary editing.
- Preview this layer is a secondary Layer menu action with a captured stable ID and Return to finished effect.
- Each stack installation receives a fresh initialized preview material, including replacement undo/redo.
- A later codegen failure retains only that installation's previous success; an empty stack clears success.
- Codegen messages use a bounded scroll area above the preview. Control refusals retain their separate lifecycle.
- Native pane minimum-size changes now schedule responsive layout updates, including while tabs are active.
- Evidence directory: `C:/Users/atk67/.codex/visualizations/2026/09/09/01a083c7-014d-7361-ae67-8eddff9c46f1/phase5-evidence`.
- Red editor baseline: `UI_COMPLETE SUMMARY pass=1 fail=1`; required entry/preview APIs were absent and the obsolete Solo API remained.
- Red named unit baseline: all four new cache tests reported missing `reset_installation`; the wrapper correctly failed on script errors.
- First green named unit run on `4.6.2`: `GST tests: 21 file(s), 142 test method(s), 0 failure(s)` and wrapper PASS.

### Integration findings

- The old layout fixture left the new automatic chooser open after File > New. It now cancels before measuring active editing controls.
- Legacy undo-to-empty checks needed to undo the initial Create Empty replacement after dismissing the start screen. Their original empty-history assertions remain intact.
- On `4.4`, native labels changed the measured editing minimum without resizing the outer allocation. The responsive breakpoint now observes pane minimum-size changes.
- One `4.7` legacy run imported an incomplete smoke edit and reported a parse error. That run was rejected; the corrected script passed the final rerun without error markers.

### Godot 4.4.0 import diagnostic

- Exact `4.4.0 --headless --import` exits `0` and emits one `add_task`, six `task_step`, and one `end_task` progress-dialog error.
- This matches the prior repository record and upstream [Godot issue 103398](https://github.com/godotengine/godot/issues/103398).
- The engine's first headless scan enters progress-dialog code while the message queue is flushing. Upstream [fix 103403](https://github.com/godotengine/godot/pull/103403) routes headless progress to console; it was included in `4.4.1`.
- The diagnostic is recorded as an engine import limitation, not a clean import pass. Named unit, GPU render, and editor checks must still complete without script or engine error markers.
- Initial `4.4` unit and render runs passed `142` test methods and `78` rendered stacks with empty stderr.
- Isolated reproduction: an empty project with no scripts or plugins emitted the identical eight diagnostics and exited `0` (`import-repro.stderr.log`). This separates the engine defect from the plugin changes.

### Runtime fixes and verification scope

- Actual numeric input reproduced a coordinate preview failure: the model changed to `offset.x = 0.17`, while the material uniform remained `0.0`. The coordinate inspector now relays `property_edited`; edit and undo both passed afterward.
- Responsive reparenting emitted `tab_changed` before both panes existed and overwrote the preferred tab. The transition now preserves the requested tab while moving controls.
- Screenshot review found clipped native labels. Inspector minimums now reserve glyph width, native label padding/reload controls, and the outer scrollbar width.
- At `1366x768`, the selected native controls use the Layer settings tab when the measured two-column minimum exceeds the editing allocation. The inspected screenshot shows complete Fine detail strength, Movement speed, and Distortion strength labels.
- Randomize undo restored effective values but added an originally absent `octaves` key to the serialized header. Undo now restores originally unset keys after applying prior values; the test requires raw params, complete shader text, effective values, and parameter uniforms to match.
- The synthetic long-error fixture now uses a known unwired filter with a long stable ID. An unknown manifest entry bypassed loader validation and produced invalid shader text, so that fixture was rejected.
- File-dialog smoke selection hides the visible dialog before emitting `file_selected`, matching its selection lifecycle and preventing exclusive-window errors.
- The complete test clicks native numeric editors and types through viewport key input. File operations exercise visible buttons/menu entries and dialog selection signals; it does not automate OS file-browser navigation.
- The error label uses smart word wrapping inside a bounded vertical scroll area; screenshot review identified the earlier long-token clipping.
- The automated beginner flow verifies controls and rendering. First-time human usability remains unverified; no user study is claimed.

### Final cross-version runtime matrix

Verified from redirected logs in the phase 5 evidence directory. Counts are passes/failures; every runtime command exited `0`.

| Check | Godot `4.4` | Godot `4.6.2` | Godot `4.7` |
|---|---|---|---|
| Named unit methods | `142/0` | `142/0` | `142/0` |
| GPU rendered stacks | `78/0` | `78/0` | `78/0` |
| Editor selector `4` | `50/0` | `50/0` | `50/0` |
| Editor selector `5` | `18/0` | `18/0` | `18/0` |
| Editor selector `6` | `16/0` | `16/0` | `16/0` |
| Editor selector `7` | `25/0` | `25/0` | `25/0` |
| Editor selector `8` | `16/0` | `16/0` | `16/0` |
| `ui_layout` | `16/0` | `16/0` | `16/0` |
| `ui_actions` | `20/0` | `20/0` | `20/0` |
| `ui_labels` | `14/0` | `14/0` | `14/0` |
| `ui_picker` | `45/0` | `45/0` | `45/0` |
| `ui_complete` | `34/0` | `34/0` | `34/0` |

- Unit, render, and selectors `4` through `7` use `final-<version>-<check>` logs.
- Selector `8`, `ui_layout`, `ui_picker`, and `ui_complete` use `final4-<version>-<check>` logs after final fixture and conversion wrapping changes.
- `ui_actions` and `ui_labels` use `final` logs on `4.4`/`4.6.2` and `final3` logs on `4.7`.
- Runtime stderr is empty except the existing selector `5` direct-PNG fixture warnings. No runtime log contains script or engine error markers.
- Imports on `4.6.2` and `4.7` exited `0` with empty stderr. Exact `4.4.0` import retains the separately reproduced engine diagnostic above.
- Additional `ui_complete` initial-entry variants on `4.6.2`: `empty` and `open` each passed `34/0` with empty stderr (`entry-empty` and `entry-open` logs).
- `ui_complete` captures five screenshots per run; those capture checks are included in its `34` assertions.
- Final layout fixtures activate the measured pane, scroll native widgets into view, and use a scaled wide-window fixture before testing both editing columns. Active-control and actual-breakpoint assertions remain enabled.
- A `150%` picker run on `4.7` exposed clipped conversion text. Kind-column wrapping now uses the live font, drawable column width, and measured multiline height. The final normal-scale chooser runs above include this fix.

### Final scaled checks and screenshot inspection

- `scaled150-<version>` logs verify active editor scale `1.50` on `4.4`, `4.6.2`, and `4.7`.
- Every version passed `ui_layout` at `16/0`, `ui_picker` at `45/0`, and `ui_complete` at `34/0`; all exited `0` with empty stderr.
- Tests requested `1366x768`; at `150%`, Godot clamped the actual editor window to `1536x900`. The recorded active scale and actual rectangles govern these assertions.
- On scaled `4.7`, host/root measured `769x706`, editing `459x632`, preview allocation `306x632`, preview image `306x278`, and Final output `306x106`.
- On normal `4.6.2`, host/root measured `792x641`, editing `473x592`, preview allocation `316x592`, preview image `316x358`, and Final output `316x70`.
- Tests retain active geometry checks for the two-column/tab transition, persisted dividers/sections, long content, and independent `20`-layer scrolling.
- Orchestrator inspected `final4-4.6.2-ui_complete-initial.png`: all twelve recipe controls, Open stack, Create Empty Stack, No effect yet, and Final output are visible.
- Orchestrator inspected the scaled `4.7` long-error screenshot: the error remains inside its scroll area above the visible preview and Final output.
- Orchestrator inspected `scaled-final-4.4-picker-conversion.png`: the complete luminance conversion wraps into three lines, and the preview continues rendering beside the chooser.
- Scaled settings use isolated evidence-directory `APPDATA`/`LOCALAPPDATA` paths. Test fixtures restore project layout metadata; normal editor settings are unchanged.

### Independent phase 5 review

- Verdict: `PASS`; no required fixes, fix-now notes, deferred notes, or documentation impact.
- Reviewer independently ran the full normal matrix on `4.4`, `4.6.2`, and `4.7`; counts matched the final runtime table with zero failures.
- Reviewer independently ran `ui_layout`, `ui_picker`, and `ui_complete` at `150%` on all three versions: `16/0`, `45/0`, and `34/0` respectively.
- Reviewer independently ran the `4.6.2` initial `empty` and `open` variants: each passed `34/0`.
- Reviewer inspected initial entry, native edits, error enclosure, and scaled conversion screenshots.
- The reproduced `4.4.0` import diagnostic remains an external engine limitation; the review does not classify it as a clean import pass.
- Independent normal logs use the `review5` prefix; entry variants use `review5-entry-empty` and `review5-entry-open`. Independent scaled runs refreshed the `scaled150` logs.
- All reviewer-owned Godot processes exited. Orchestrator restored only the generated `project.godot` feature version to `4.4`.
- User authorized the phase 5 commit on `2026-09-09`. The original release-tuning work remains separate.

## Fire noise seams, renderer regression (2026-09-09)

User evidence: Fire preview contains sharp diagonal, parallelogram-shaped discontinuities.

- Reproduced on Godot `4.6.2`, Forward+/Vulkan, NVIDIA RTX 5070 Ti Laptop GPU; the same isolated noise is continuous in Compatibility/OpenGL.
- Evidence directory: `C:/Users/atk67/.codex/visualizations/2026/09/09/01a083c7-014d-7361-ae67-8eddff9c46f1/noise-audit`.
- Fixed-time Fire and isolated simplex renders separate this defect from animation movement and background composition.
- At `512x512` over an eight-unit coordinate span, the original Forward+ field's maximum adjacent grayscale difference is `0.615686`; `780` sampled pixels exceed `0.1`.
- Changing only the simplex gradient helper and corner arguments to integer lattice addresses removes these seams. The public hash formula and simplex weighting remain unchanged.
- An alternative private integer hash also removed the seams, but changed the noise pattern. That experiment was not applied.
- The precise compiler transformation causing the floating-address discrepancy is unverified; the renderer-dependent failure and the effect of integer addresses are reproduced on the GPU.
- New regression coverage in `tests/run_render_checks.gd` requires adjacent grayscale differences below `0.1` and total grayscale range above `0.5`.
- Red run: the original code passes all `78` stack checks, then fails `NOISE_CONTINUITY`, exiting `1` with empty stderr (`red.stdout.log`).
- Prior version-matrix runs used Compatibility and checked nonuniform images without continuity checks. They did not establish Forward+ noise continuity.
- This repair does not resolve the separately diagnosed inactive controls, transparency preview composition, or Foil/Opal animation saturation.
- Green matrix: Godot `4.4`, `4.6.2`, and `4.7`, each with Forward+, Mobile, and Compatibility, passed all `78` rendered stacks plus `NOISE_CONTINUITY`. Every command exited `0` with empty stderr.
- All nine fixed runs measured maximum adjacent grayscale difference `0.039216` and range `0.701961` (`green-<version>-<renderer>` logs).
- Named unit suite on `4.6.2`: `142/0`, wrapper PASS, exit `0`, empty stderr (`phase5-evidence/noise-fix-4.6.2-unit` logs).
- Independent quick-fix review: `PASS`, no required fixes, fix-now notes, deferred notes, or documentation impact.
- Reviewer independently passed `142` unit methods and both Forward+/Compatibility render runs on `4.6.2`: `78` stacks plus continuity at `0.039216`, range `0.701961`; exits `0`, empty stderr.
- Reviewer-owned engine processes exited. The user's existing editor was left running. User authorized commit and push on `2026-09-09`.

## Palette Color center picker (2026-09-09)

- User decision: retain the cosine formula and replace only Color center (`a`) with a native RGB color picker. Alpha is hidden; `b`, `c`, and `d` remain vector editors.
- `GSTLayer` copies RGB components between the editor's `Color` and raw `Vector3` storage. Manifest types, uniform names, and the palette formula remain unchanged.
- `tests/test_stack_io.gd` verifies negative/HDR RGB, ignored alpha, direct Vector3 writes, unchanged header/shader text after reads, and Vector3 `.tres`/header round trips.
- Red baseline: `145` unit methods with `9` failures plus type errors before the adapter; green `4.6.2` run: `145/0`, exit `0`, empty stderr.
- `ui_labels` focuses the native swatch, presses Space, types `3366cc` into the actual hex input, and checks raw storage, displayed color, and material uniform through edit/undo/redo. It also checks Randomize undo and save/reopen.
- Independent review found the legacy Randomize range test reading editor values. It now checks raw stored values against the manifest schema.
- `4.6.2` regression checks: selector `4` passes `50/0`, selector `8` passes `16/0`, and `ui_complete` passes `34/0`; exits `0`, empty stderr.
- Compatibility rendering on `4.6.2`: all `78` stacks and noise continuity pass; maximum adjacent difference `0.039216`, range `0.701961`, exit `0`, empty stderr.
- Evidence directory: `C:/Users/atk67/.codex/visualizations/2026/09/09/01a083c7-014d-7361-ae67-8eddff9c46f1/phase5-evidence`; logs use `palette-` prefixes.
- Inspected `palette-4.6.2-palette-popup.png`: color wheel, RGB controls, and hex input visible; alpha absent. Swatch screenshot shows Color center beside the unchanged vector controls.
- Native-popup texture readback fails on `4.4`; the smoke test retains root-window screenshots and verifies the popup through visible controls and input events.
- Final `4.4` and `4.7` runs each pass `145/0` unit methods, `23/0` native-label checks including four screenshots, and `16/0` Randomize checks; all exit `0` with empty stderr (`palette-final3-<version>` logs).
- Independent quick review: `PASS`, no remaining findings. Reviewer independently passed `145/0` unit methods and `19/0` native-label assertions on final `4.6.2` code, exit `0`, empty stderr. Reviewer-owned engines exited; the user's editor was left running.

## Intermittent picker text slicing (2026-09-09, unresolved)

- User reported horizontally sliced letters in a library row. Moving the pointer away did not clear it; closing and reopening the picker cleared it in the user's session.
- The exact trigger and cause remain unverified. No production layout or font changes were applied.
- Fresh-editor checks on `4.4` with Forward+ and Compatibility, plus `4.6.2` Compatibility, did not reproduce the slicing. Existing picker smoke checks passed `45/0`.
- A temporary pixel probe on `4.4` Forward+ compared normal and hovered text for `21` rows at `1920x1080`; no measured foreground pixels disappeared.
- The probe also checked `30` half-pixel scroll offsets at normal, `125%`, and `150%` editor scale without reproducing disappearing glyph pixels. Scaled runs used isolated settings.
- Probe scripts and captures remain outside the repository in the evidence directory above, under `picker-*-probe.gd` and `row-*`. Temporary test instrumentation was removed.
- Next reproduction: capture the affected row before closing the picker and record the preceding search, resize, or scroll action. Reopening clears the state needed for diagnosis.

## Preview transparency, recipe motion, and control explanations (2026-09-09)

- User authorized implementation and commits with "go on all". Release tuning remains the user's decision.
- The original preview drew the selected image behind the effect, hiding transparent output. `GSTPreview` now captures that image for screen sampling, clears the target, and displays the result over an external checkerboard.
- Review identified a second alpha multiplication by `SubViewportContainer`. The new parent-viewport test reproduced `64/64` incorrect samples with maximum channel error `0.2006` (`composite-red-4.6.2-render`). Premultiplied-alpha container blending fixes the error without changing generated shader text.
- Composition checks cover output alpha `0`, `0.5`, and `1` on sprite, text, and full-rectangle presets; texture-source alpha `0`, `0.75`, and `1`; and the final checker composite.
- Screen sampling is compared against a separate native `SubViewport`/`BackBufferCopy` scene. Compatibility retains source alpha; Forward+ returns alpha `1` even for transparent source images. Both preserve the fixture's RGB. The preview follows that measured engine behavior.
- Foil and Opal previously became motionless at `30` and `120` seconds; gradient position and Opal radius also produced zero measured change (`motion-red2`). The replacement recipes animate bounded noise distortion, retaining existing layer IDs and palette/blend settings.
- `tests/run_recipe_motion_checks.gd` checks fixed times `1`, `30`, and `120`, deterministic repeats, motion after `0.5` seconds, gradient position changes, and Opal radius changes. All images must also pass the nonblank/finite render checks.
- At `120` seconds on Compatibility, mean RGB motion delta is `0.004430` for Foil and `0.002826` for Opal. Both exceed the `0.0005` regression threshold. This establishes motion, not user approval of appearance.
- Native inspectors explain disconnected distortion, FBM gain with one octave, unused Y components, radial rotational symmetry, reversed threshold edges, and thresholds driving transparency. Whole inactive gain/strength controls become read-only without changing stored values.
- Native checks verify explanations after construction, edits, and undo. Palette checks wait for the native popup commit and focus return before testing exact displayed/stored/material undo and redo values.

| Check | Godot `4.4` | Godot `4.6.2` | Godot `4.7` |
|---|---:|---:|---:|
| Named unit methods | `145/0` | `145/0` | `145/0` |
| Native labels and contextual controls | `42/0` | `42/0` | `42/0` |
| Editor selector `5` | `18/0` | `18/0` | `18/0` |
| `ui_complete` | `34/0` | `34/0` | `34/0` |
| `ui_layout` | `16/0` | `16/0` | `16/0` |
| Compatibility render checks | `78/0` | `78/0` | `78/0` |
| Forward+ render checks | `78/0` | `78/0` | `78/0` |
| Composition and noise checks, both renderers | `PASS` | `PASS` | `PASS` |
| Fixed-time recipe checks, both renderers | `PASS` | `PASS` | `PASS` |

- All recorded final commands exited `0` with empty stderr. Selector `5` now reads imported textures and tests rotation across the complete image instead of four checker corners.
- Evidence remains in the `phase5-evidence` directory recorded above. Final logs use `polish-final`, `polish-labels-final`, `polish-render-final`, and `polish-forward-final` prefixes.
- At verified `150%` scale on `4.7`, layout passed `16/0` and native labels passed `47/0`, including five screenshots (`polish-scaled150`). Inspected `polish-scaled-labels-inactive-gain.png`: the complete two-line explanation fits below Fine detail strength.
- Regenerated reference images through production `GSTPreview` with `--write-screenshots`; `78` stack checks passed (`polish-captures-4.6.2-render`). Inspected the refreshed Opal and Dissolve images. Transparent pixels are retained in the PNGs; the checker belongs to the editor UI.
- Existing user-saved stacks are unchanged. Load fresh Foil and Opal recipes to use the revised defaults.
- Independent `4.6.2` runs passed `145` unit methods, `42` native-label checks, and Compatibility/Mobile rendering and recipe motion. Each renderer passed `78` stacks, composition, and noise continuity; stderr is empty (`review-polish-compat` and `review-polish-mobile` logs). Mobile's native screen copy also returns alpha `1` for transparent source images.
- Independent review verdict: `PASS`, no remaining required fixes. Reviewer inspected the scaled explanation and refreshed images; owned engine processes exited. Restored generated project-version and Glow import-setting churn before committing.
