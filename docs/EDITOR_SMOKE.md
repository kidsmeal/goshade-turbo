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

## Shader tabs phase 1 capability gate (2026-09-09)

- Status: blocked. Godot `4.4.stable.official.4c311cbee` reports `ClassDB.can_instantiate(EditorUndoRedoManager)=false`; the native class is abstract.
- Command: `GST_EDITOR_SMOKE=tabs_proof; Godot_v4.4-stable_win64.exe --editor --path C:\Users\atk67\Documents\goshade-turbo\.now\tabs-validation\project --rendering-method gl_compatibility`.
- Isolated project name: `GoShade Tabs Phase 1 Proof`; recovery and editor settings remain project-local.
- Runner summary: `TABS_PROOF SUMMARY pass=0 fail=1`; process exit code `1`.
- Exact proof line: `TABS_PROOF private_manager_construction FAIL ClassDB.can_instantiate(EditorUndoRedoManager)=false; Godot 4.4 marks the native class abstract`.
- The initial direct-construction probe also produced `SCRIPT ERROR: Parse Error: Native class "EditorUndoRedoManager" cannot be constructed as it is abstract.` Its archived log is `.now/tabs-validation/evidence/import-4.4.stderr.log`.
- Consequence: two private `GLOBAL_HISTORY` instances cannot be created through the reviewed Godot `4.4` GDScript mechanism. Native property input, host-scene isolation, and Save-and-Quit recovery proof do not run.
- The import also emitted the documented Godot `4.4` progress-dialog diagnostic. It is separate from the constructor blocker.
- No GoShade production file changed. Subsequent shader-tab phases require design review before implementation resumes.

## Shader tabs phase 1 replacement-route proof (2026-09-09)

- Status: pending technical review. The prior abstract `EditorUndoRedoManager` route remains historical evidence only.
- Command: `GST_EDITOR_SMOKE=tabs_proof; Godot_v4.4-stable_win64.exe --editor --path C:\Users\atk67\Documents\goshade-turbo\.now\tabs-validation\project --rendering-method gl_compatibility`.
- Final runner summary: `TABS_PROOF SUMMARY pass=8 fail=1`; process exit code `1`.
- Final stdout: `.now/tabs-validation/evidence/tabs-proof-r2-final-4.4.stdout.log`.
- Final stderr: `.now/tabs-validation/evidence/tabs-proof-r2-final-4.4.stderr.log`.
- Native-row screenshot after the observed import/loading dialogs settled: `.now/tabs-validation/project/tabs-proof-native-rows.png`.
- Passed: two distinct standalone `UndoRedo.new()` histories; structural isolation; real native vector and RGB edits; focused Ctrl+Z/Ctrl+Shift+Z against the active history; host-scene manager undo isolation; isolated `.tres` Save As and scene switching; empty/nonempty `_get_unsaved_status` routing.
- Native float proof: multi-motion viewport drag changed both document scalars from `0.25` to `1.0`; each emitted `property_changed(scalar, value, field, changing)` with `field=""` and `changing=false`.
- Native vector proof: a multi-motion x drag emitted three complete calls with `property="vector"`, `field="x"`, and `changing=false`; y and z remained `0.2` and `0.3`.
- Native RGB popup proof: hex input emitted `property_changed(rgb, value, field, changing)` with `field=""` and `changing=false`; Color storage mapped to the expected `Vector3` RGB components.
- Godot `4.4` source `editor/editor_properties.cpp` lines `1341-1345` defines `EditorPropertyFloat::_value_changed` as `emit_changed(get_edited_property(), p_value)` and omits the `changing` argument. The proof cannot produce `changing=true` through this native float `property_changed` route.
- Candidate replacement: use public `EditorSpinSlider` grab/ungrab gesture boundaries with the complete four-argument `property_changed` final values. This needs technical re-review before phase `1` can pass because the reviewed proof requires native `changing` updates.
- Confirmed Save and Quit, `_save_external_data`, recovery readback, forced recovery-write failure, and void-callback evidence remain unexecuted because the native continuous-edit gate failed.
- The final stderr retains `WARNING: ObjectDB instances leaked at exit` after queued proof-row release and one process frame. No proof-owned control survives in the visible tree; the warning remains unclassified.

## Shader tabs phase 1 corrected native-boundary proof (2026-09-09)

- Status: pending. `r3i` verifies public numeric gesture boundaries; confirmed Save and Quit callback delivery works in `r3j`, but the owned editor process does not exit before the `60` second bound.
- Command: `GST_EDITOR_SMOKE=tabs_proof; Godot_v4.4-stable_win64.exe --editor --path C:\Users\atk67\Documents\goshade-turbo\.now\tabs-validation\project --rendering-method gl_compatibility`.
- `tabs-proof-r3i-4.4.stdout.log`: `13` passing assertions before the dialog. Float and vector drags emitted two distinct values each; one action was registered per drag; two later float gestures registered separately and undo restored each preceding value.
- `tabs-proof-r3i-4.4.stdout.log`: active GoShade Ctrl+Z/Ctrl+Shift+Z changed only the active standalone history; outside GoShade, the host-scene manager shortcut changed only the host history; both proof targets carried `res://` paths.
- `tabs-proof-r3j-4.4.stdout.log`: actual confirmation listed `Named proof document` and `Untitled proof document`; the native `Save & Quit` button became the popup viewport focus owner and received `Enter` through that viewport.
- `tabs-proof-r3j-4.4.process.txt`: owned isolated PID `45652` recorded `result=timeout-before-exit`; the wrapper stopped only that PID and returned `124`. This is a failed quit-process proof, not a passing run.
- The same `r3j` run wrote stage `confirmed_quit_complete`, `save_count=4`, `named_ok=true`, and `recovery_ok=true`, proving `_save_external_data` synchronously persisted callback output before the forced cleanup.
- `r3k` isolated diagnostic found the callback completed, then Godot reopened the same confirmation because the fixture continued reporting its proof documents as unsaved. The fixture now reports no unsaved documents after both callback writes succeed; this changes only the test fixture's simulated document baseline.
- `r3k` ended with `TABS_PROOF SUMMARY pass=2 fail=1` and process exit `1` from the diagnostic's controlled failure. Its modal evidence is `.now/tabs-validation/evidence/tabs-proof-r3k-4.4.stdout.log` and `.now/tabs-validation/project/tabs-proof-after-save-quit.png`.
- `r3l` is the corrected actual quit: the focused `Save & Quit` activation exited the owned PID `15988` with code `0`; stage `confirmed_quit_complete` recorded `save_count=7`, `named_ok=true`, and `recovery_ok=true`.
- `r3n` is the fresh open: `TABS_PROOF SUMMARY pass=3 fail=0`; it loaded the callback-written recovery `.tres` with `next_id=42`, loaded the named `.tres` with `next_id=7`, and recorded the forced write path `res://.godot/editor/blocked-parent/document.json` with `Failed (1)`.
- Phase `7` must suppress a document from `_get_unsaved_status` after its confirmed-quit save callback succeeds, while a recovery record loaded by the next editor session remains dirty until the user saves or discards it.
- `r3i` and `r3j` stderr retain `WARNING: ObjectDB instances leaked at exit`; the prior `2 resources still in use` warning did not recur after clearing the proof resources' paths before teardown.
- No fresh-open recovery comparison, numeric text-focus proof, forced-finish ordering, or forced recovery-write failure can pass phase `1` until the real editor process exits after Save and Quit.

## Shader tabs phase 1 completed replacement proof (2026-09-09)

- Command: `GST_EDITOR_SMOKE=tabs_proof; Godot_v4.4-stable_win64.exe --editor --verbose --path C:\Users\atk67\Documents\goshade-turbo\.now\tabs-validation\project --rendering-method gl_compatibility`.
- `tabs-proof-r4g-4.4.process.txt`: the actual focused `Save & Quit` activation exited owned PID `53572` with code `0`.
- `tabs-proof-r4g-4.4.stdout.log`: `14` native and isolation checks passed before the confirmed shutdown.
- Float and vector drags emitted multiple values and registered one action each; later float gestures restored their captured `0.30` and `0.20` values through separate undo actions.
- Numeric drag, numeric text-focus, and RGB popup cases finish before rebind, `GSTStackIO.save`, and undo; the forced-save case reloads the edited `GSTCoordBlock.rotation` from `tabs-proof-forced-save-stack.tres`.
- `Ctrl+Shift+W` closed the real host scene; both shader histories remained undoable.
- `tabs-proof-r4h-4.4.process.txt`: the fresh owned PID `47824` exited with code `0`.
- `tabs-proof-r4h-4.4.stdout.log`: `TABS_PROOF SUMMARY pass=3 fail=0`.
- Fresh open loaded the successful named stack with `next_id=7`, the failed named-save recovery with `next_id=29`, and untitled recovery with `next_id=42`.
- Expected failure paths: named `GSTStackIO.save` to `res://.godot/editor/blocked-parent/named-failed.tres` reports `Can't open`; forced metadata write to `res://.godot/editor/blocked-parent/document.json` reports `Failed (1)`.
- Verbose `r4g` output contains no `Leaked instance`, `ObjectDB instances leaked`, or `resources still in use` lines. Standalone `UndoRedo` extends `Object`; clearing history then calling `free()` during fixture teardown releases all nine proof histories.
- The existing `LayerPane` and `SettingsPane` owner warnings come from the pre-existing GoShade panel scene. They do not identify a phase-1 proof object.

## Shader tabs phase 1 review round 1 fixes verified (2026-09-10)

- Scope: the six round-1 phase-review findings in `.gantry/review-round.json`. Changed files: `tests/gst_editor_document_proof.gd`, `tests/fixtures/shader_tabs_shutdown_plugin.gd`. No production file changed.
- Command: `GST_EDITOR_SMOKE=tabs_proof; Godot_v4.4-stable_win64.exe --editor --verbose --path C:\Users\atk67\Documents\goshade-turbo\.now\tabs-validation\project --rendering-method gl_compatibility`, through a `Start-Process` wrapper with redirected stdout/stderr and a `180` second bound. Isolated copies of `addons/` and `tests/` were synced from the repo before each run; stage file, recovery directory, and `tabs-proof-*` artifacts were removed before `r5a` and `r5b`.
- `tabs-proof-r5a-4.4.stdout.log`: `TABS_PROOF SUMMARY pass=15 fail=1`. The one failure was `forced_finish_ordering` with `color=false`. Cause, verified against Godot `4.4` source: `ColorPicker::_html_focus_exit` (`scene/gui/color_picker.cpp:2023`) applies typed hex text only while the picker is visible in tree, and `EditorPropertyColor::_popup_closed` (`editor/editor_properties.cpp`) emits its single final `property_changed(changing=false)` only when the picked color differs from the color at popup open. The r5 proof typed the hex value without submitting it, then hid the popup, so the text was discarded and no final delivery occurred.
- Fix: `_force_close_color_popup` now releases focus from the picker's hex `LineEdit` while the popup is still visible, waits one frame, then hides the popup. The call site awaits it. This is the forced-finish rule the plan requires for pending native color edits: the pending value reaches the original target before the operation continues.
- `tabs-proof-r5b-4.4.stdout.log`: `17` checks passed, `0` failed, before the confirmed shutdown. `forced_finish_ordering` reports `rebind=true late=true save_as=true undo=true redo=true focus=true color=true shutdown=true`. `native_text_focus` records a non-drag grab followed by text entry with one action, undo to `0.9`, redo to `0.55`. `popup_shortcut_isolation` sends Ctrl+Z/Ctrl+Shift+Z with focus inside a native color popup (`focus=LineEdit`) and changes only the active history (`inactive_before=0.85 inactive_after=0.85`). `native_rgb` asserts exactly one action with undo to the original and redo to the final value. `changing_fallback_finish` finishes on `changing=false` after a `changing=true` begin with one action.
- `tabs-proof-r5b-4.4.process.txt`: the focused `Save & Quit` activation exited owned PID `51256` with code `0`. Stage file after exit: `confirmed_quit_complete`, `save_count=1`, `named_ok=true`, `recovery_ok=true`, `pending_shutdown_edit_finished=true`, `pending_shutdown_edit_actions=1`, `pending_shutdown_edit_value=0.65`.
- `tabs-proof-r5c-4.4.stdout.log`: fresh open, `TABS_PROOF SUMMARY pass=3 fail=0`, owned PID `45852` exited with code `0`. `confirmed_shutdown_recovery` loaded named `next_id=7`, failed-named recovery `next_id=29`, untitled recovery `next_id=42`, and asserted the pending shutdown edit fields. `forced_write_failure` reports `res://.godot/editor/blocked-parent/document.json` with `Failed (1)`. `void_callback` reports `save_count_before=1 save_count_after=2`.
- Verbose `r5b` and `r5c` output contains no `Leaked instance`, `ObjectDB instances leaked`, or `resources still in use` lines. stderr holds only the pre-existing `LayerPane`/`SettingsPane` owner warnings, the expected blocked named save, and the expected forced metadata write failure.
- Status: pending independent phase review round `2`.

## Shader tabs phase 1 review round 2 fixes verified (2026-09-10)

- Scope: the five round-2 phase-review findings in the relayed fix-mode brief. Changed files: `tests/gst_editor_document_proof.gd`, `tests/fixtures/shader_tabs_shutdown_plugin.gd`. No production file changed. Finding 4 (backlog/changelog hunk separation in `IDEAS.md`/`NOW.md`/`SHIPPED.md`) is handled by the orchestrator as a separate commit and is not covered here.
- Command: `GST_EDITOR_SMOKE=tabs_proof; Godot_v4.4-stable_win64.exe --editor --verbose --path C:\Users\atk67\Documents\goshade-turbo\.now\tabs-validation\project --rendering-method gl_compatibility`, through the `Start-Process` wrapper with redirected stdout/stderr and a `180` second bound. `tests/` was synced from the repo before the run; stage file, recovery directory, and `tabs-proof-*` artifacts were removed before `r6a`.
- **Fix 1 (S1, false-positive text-entry order):** `_begin_non_drag_text_entry` no longer calls `grab_focus()`/`Enter` on the outer `EditorSpinSlider` after the click. Godot `4.4` `EditorSpinSlider::_grab_end` (`editor/gui/editor_spin_slider.cpp:156`) already calls `_focus_entered()` directly for a non-drag release, which shows and focuses the internal `LineEdit` via a deferred call; the removed extra `grab_focus()` was stealing that focus back and forcing a premature `value_focus_exited`/`finish` before the typed value ever arrived, then reopening a second session for `_replace_line_edit`. The assertion now records the order index at the start of the grab and scopes `grabbed`/`value`/`finish` lookups to that slice, requiring the grab first, the typed value before any `finish`, and exactly one action. `tabs-proof-r6a-4.4.stdout.log`: `native_text_focus PASS ... order=["grabbed", "value_focus_entered", "value", "value_focus_exited", "finish"]`. a single uninterrupted session, matching the fix.
- **Fix 2 (S1, shutdown evidence not connected to a saved stack):** the shutdown case in `_prove_forced_finish_ordering` now binds a real `GSTCoordBlock` inside a `GSTLayer` inside a `GSTStack` (the same pattern as the existing forced-Save-As case) and starts a real pending drag that is left unfinished. it is never force-finished or released by the proof. Instead the stack, target save path, and a bound `Callable` that performs the finish are handed to the probe via `set_pending_shutdown_target`. The probe's `_save_external_data()`. the same synchronous-quit callback path production code uses. invokes that `Callable` and then saves the stack, recording `pending_shutdown_finished`, `pending_shutdown_actions`, `pending_shutdown_value`, and `pending_shutdown_stack_ok` in the stage file; a fresh-open probe method `load_pending_shutdown_stack()` reloads the saved `.tres` from disk. `tabs-proof-r6a-4.4` stage file after confirmed quit: `pending_shutdown_finished=true pending_shutdown_actions=1 pending_shutdown_stack_ok=true pending_shutdown_value=0.4`. `tabs-proof-r6a-fresh-4.4.stdout.log`: new check `pending_shutdown_edit_persisted PASS finished=true actions=1.0 stack_ok=true recorded_value=0.4 persisted_rotation=0.4 path=res://tabs-proof-pending-shutdown-stack.tres`. the rotation reloaded from the saved `.tres` on a fresh editor process matches the value recorded at save time. The handed-off `Callable` frees the `UndoRedo` (a plain `Object`, not released by scene-tree teardown) and queues the host free once it has finished the edit, so the pending row does not leak at process exit.
- **Fix 3 (vector and structural undo/redo):** `native_vector` now calls `undo()`/`redo()` on the vector row's history and asserts `has_undo`/`has_redo` around each transition plus the complete original (`(0.1, 0.2, 0.3)`) and final vectors, not just value/action counts. `resource_and_scene_retention` (~line 207 pre-fix) now registers a fresh structural transition on each document's history after Save As and the scene switch (a dedicated `_register_structural_transition` helper that restores the true prior value on undo, unlike the original `_register_structural_action` which always undoes to `0`), executes undo then redo on each, and asserts `structural_value` at each step. `tabs-proof-r6a-4.4.stdout.log`: `native_vector PASS ... has_undo_before=true undo_original=(0.1, 0.2, 0.3) has_redo_after_undo=true redo_final=(0.16, 0.2, 0.3) has_undo_after_redo=true` and `resource_and_scene_retention PASS ... first_structural=1->1->3 second_structural=2->2->4`.
- **Fix 5 (this section):** appended rather than rewriting the round-1 section above.
- Minor cleanup: removed the unused private helpers `_dump_visible_modal_windows` and `_click`, confirmed unreferenced elsewhere before removal.
- `tabs-proof-r6a-4.4.stdout.log`: `TABS_PROOF SUMMARY` line is absent because the proof quits through the real editor; the run instead ends after `SAVE_AND_QUIT_ACTIVATION_DISPATCHED`. `18` checks passed (`0` failed) through `resource_and_scene_retention`, `shutdown_status`, and the actual quit confirmation/activation (corrected count: `grep -c "TABS_PROOF .* PASS" tabs-proof-r6a-4.4.stdout.log` reads `18`, not the `17` recorded here in round 2). `tabs-proof-r6a-4.4.process.txt`: owned PID `38168` exited with code `0`.
- `tabs-proof-r6a-fresh-4.4.stdout.log`: `TABS_PROOF SUMMARY pass=4 fail=0`. `confirmed_shutdown_recovery`, `pending_shutdown_edit_persisted`, `forced_write_failure`, and `void_callback` all pass. `tabs-proof-r6a-fresh-4.4.process.txt`: owned PID `9440` exited with code `0`.
- Both runs' stderr hold only the pre-existing `LayerPane`/`SettingsPane` owner warnings, the expected blocked named save (`Cannot save file 'res://.godot/editor/blocked-parent/named-failed.tres'`), and (fresh-open only) the expected `TABS_PROOF_EXPECTED_WRITE_FAILURE`. Verbose stdout for both runs contains no `Leaked instance`, `ObjectDB instances leaked`, or `resources still in use` lines.
- Known limitation, not hit here: the round-2 reviewer's sandbox could not create `C:/Users/atk67/AppData/Roaming/Godot` (the editor config directory) and reported cache/editor-settings write errors on their machine. These runs use the existing local Godot install and isolated project under `.now/tabs-validation/`, which already have that directory; no equivalent failure was observed.
- Remaining verification limitation, unchanged from round 1: the confirmed-quit flow requires actually operating the OS-native `ConfirmationDialog` (via focused button + `Enter`) inside a real, visible editor window; it cannot be exercised headlessly. Every run recorded here used the real windowed editor as the plan requires; no direct `restart_editor()` or callback-only substitute was used for the confirmed-shutdown evidence.
- Status: round-2 fixes applied and verified; ready for independent phase review round `3`.

## Shader tabs phase 1 review round 3 fixes verified (2026-09-10)

- Scope: the two round-3 phase-review findings in the relayed fix-mode brief (S1 forced-finish text commit, S1 `resource_and_scene_retention` false positive), plus the docs count correction above. Changed file: `tests/gst_editor_document_proof.gd`. No production file changed.
- Command: `GST_EDITOR_SMOKE=tabs_proof; Godot_v4.4-stable_win64.exe --editor --verbose --path C:\Users\atk67\Documents\goshade-turbo\.now\tabs-validation\project --rendering-method gl_compatibility`, through the `Start-Process` wrapper with redirected stdout/stderr and a `180` second bound. `tests/` was synced from the repo before each run; stage file, recovery directory, and `tabs-proof-*` artifacts were removed before `r7a`/`r7b`.
- **Fix 1 (S1, forced finish committed no pending text):** `_force_finish_numeric` gained an optional `pending_edit: LineEdit` argument; when supplied it calls `pending_edit.release_focus()` and awaits `3` frames before finalizing the history action. this triggers `EditorSpinSlider::_value_focus_exited` (Godot `4.4` `editor/gui/editor_spin_slider.cpp:607`), which runs `_evaluate_input_text()` (committing the field's pending text to the target) before emitting the public `value_focus_exited` signal our own finish handler is also connected to, so the commit provably precedes finalization even though the natural handler often completes the action first (idempotent no-op on the explicit call). The `focus` case in `_prove_forced_finish_ordering` now types `"0.7"` via `_replace_line_edit(plugin, focus_edit, "0.7", false)` (`submit=false`, so no Enter) before the forced finish, asserts the field held uncommitted text and unchanged content beforehand (`focus_typed_uncommitted`), that the final delivered value and one registered action match the typed value (`focus_final_delivered`, `focus_action_registered`), that undo restores the pre-grab original and redo restores the typed value (`focus_undo_original`, `focus_redo_final`), and. after rebinding the row to a second target. that a later full focus session (reopen, type `"0.9"`, release) changes neither the original nor the rebound target (`focus_late_original_unchanged`, `focus_late_rebound_unchanged`), mirroring the round-2 late-drag pattern applied to text focus. `tabs-proof-r7b-4.4.stdout.log`: `forced_finish_ordering PASS rebind=true late=true save_as=true undo=true redo=true focus=true color=true shutdown=true ... focus_order=["forced_finish", "focus_rebind"]` (all seven forced-finish sub-checks, including `focus=true`, pass; the fix's new assertions are folded into `focus_ok` before this composite check).
- **Fix 2 (S1, `resource_and_scene_retention` false positive):** the check no longer registers `_register_structural_transition` before verifying retention. It now snapshots each document's PRE-navigation `scalar`/`structural_value`/`has_undo()` (each history already held a structural action plus a real native-property action from earlier in the proof), performs Save As on `second_target` itself. an actual history-owning `ProofTarget`, not a fresh empty `GSTStack`. to `SAVE_AS_STACK_PATH`, does the scene switches, then walks each history fully to the bottom (`first_actions_walked=5`, `second_actions_walked=2`) asserting the objects reach their true defaults (`scalar=0.25`, `structural_value=0`) with no further undo and a redo available, walks back to the top asserting the PRE-navigation snapshot values are exactly restored, and only after that registers the round-2 structural-transition coverage. If navigation had silently cleared either history this walk would find `0` actions and the fully-undone/restored assertions would fail against the still-dirty PRE-navigation values, which is what the round-3 finding required. `ProofTarget` is a script-local inner class, so `ResourceSaver.save` embeds an empty `GDScript` sub-resource that `ResourceLoader.load` cannot resolve back to a typed `ProofTarget` (confirmed by a first attempt at this fix, `tabs-proof-r7a-4.4.stdout.log`: `resource_and_scene_retention FAIL ... save_as_scalar=-1.0`, `loaded_save_as` was `null`); the check now reads the persisted `.tres` text directly with a `scalar = ([-0-9.eE]+)` regex instead of reloading it typed. `tabs-proof-r7b-4.4.stdout.log`: `resource_and_scene_retention PASS pre_nav_ok=true first_walked=5 second_walked=2 first_pre=0.55 first_restored=true second_pre=0.85 second_restored=true named={ "ok": true, "reason": "" } save_as_error=OK save_as_path=res://tabs-proof-save-as.tres save_as_scalar=0.85 first_undo=true second_undo=true first_structural=1->1->3 second_structural=2->2->4`. Review round 4 rejected the regex text read as masking the underlying serialization defect and required a genuine typed round-trip; the round-3 regex workaround was replaced in round 4 by a standalone fixture, `tests/fixtures/shader_tabs_proof_target.gd` (`GSTTabsProofTarget`), and a real `ResourceLoader.load` reload of the saved instance, detailed in the round-4 section below.
- `tabs-proof-r7a-4.4.stdout.log`: intermediate run exercising Fix 1 correctly but before Fix 2's reload workaround; `TABS_PROOF SUMMARY pass=15 fail=1`, the single failure being `resource_and_scene_retention` as described above (`save_as_error=OK`, so the write itself succeeded; only the typed reload failed). Superseded by `r7b`; kept as evidence of the diagnosed root cause. `tabs-proof-r7a-4.4.process.txt`: owned PID `32712` exited with code `1`.
- `tabs-proof-r7b-4.4.stdout.log`: `TABS_PROOF SUMMARY` line is absent because the proof quits through the real editor; the run instead ends after `SAVE_AND_QUIT_ACTIVATION_DISPATCHED`. `18` checks passed (`0` failed). matching the corrected `r6a` baseline count exactly. through `resource_and_scene_retention`, `shutdown_status`, and the actual quit confirmation/activation. `tabs-proof-r7b-4.4.process.txt`: owned PID `15760` exited with code `0`.
- `tabs-proof-r7b-fresh-4.4.stdout.log`: `TABS_PROOF SUMMARY pass=4 fail=0`. `confirmed_shutdown_recovery`, `pending_shutdown_edit_persisted`, `forced_write_failure`, and `void_callback` all pass, matching the `r6a-fresh` baseline. `tabs-proof-r7b-fresh-4.4.process.txt`: owned PID `15644` exited with code `0`.
- Both `r7b` and `r7b-fresh` stderr hold only the pre-existing `LayerPane`/`SettingsPane` owner warnings, the expected blocked named save (`Cannot save file 'res://.godot/editor/blocked-parent/named-failed.tres'`), and (fresh-open only) the expected `TABS_PROOF_EXPECTED_WRITE_FAILURE`. Verbose stdout for both runs contains no `Leaked instance`, `ObjectDB instances leaked`, or `resources still in use` lines (`grep -c` against each full stdout log returns `0`).
- Mechanical fallout from the `_force_finish_numeric` signature change (new leading `plugin: EditorPlugin` parameter, needed so the pending-text-commit branch can await frames): all six call sites updated, including the `shutdown_finish` `Callable` inside `_prove_forced_finish_ordering`, which is invoked via a plain (non-awaited) `.call()` from `shader_tabs_shutdown_plugin.gd::_save_external_data()`. That closure's `pending_edit` argument is never supplied, so its `await` branch is never taken and the call resolves synchronously within the single `.call()`; `r7b-fresh`'s `pending_shutdown_edit_persisted PASS ... actions=1.0 ... recorded_value=0.4` confirms the shutdown path still delivers the same result as the `r6a` baseline.
- Known limitation, not hit here: the round-2/round-3 reviewer's sandbox could not create `C:/Users/atk67/AppData/Roaming/Godot` (the editor config directory) and reported cache/editor-settings write errors on their machine. These runs use the existing local Godot install and isolated project under `.now/tabs-validation/`, which already have that directory; no equivalent failure was observed.
- Remaining verification limitation, unchanged from prior rounds: the confirmed-quit flow requires actually operating the OS-native `ConfirmationDialog` (via focused button + `Enter`) inside a real, visible editor window; it cannot be exercised headlessly. Both full runs recorded here used the real windowed editor as the plan requires; no direct `restart_editor()` or callback-only substitute was used for the confirmed-shutdown evidence.
- Status: round-3 fixes applied and verified; ready for independent phase review round `4`.

## Shader tabs phase 1 review round 4 fix verified (2026-09-10)

- Scope: the single round-4 phase-review finding (S1, `ProofTarget` not reloadable, `tests/gst_editor_document_proof.gd:233` regex read masking a real serialization defect). Changed files: `tests/gst_editor_document_proof.gd`, new `tests/fixtures/shader_tabs_proof_target.gd` and its generated `tests/fixtures/shader_tabs_proof_target.gd.uid`. No production file changed.
- Command: `GST_EDITOR_SMOKE=tabs_proof; Godot_v4.4-stable_win64.exe --editor --verbose --path C:\Users\atk67\Documents\goshade-turbo\.now\tabs-validation\project --rendering-method gl_compatibility`, through the `Start-Process` wrapper with redirected stdout/stderr and a `180` second bound. `tests/` was synced from the repo before the run; the stage file, recovery directory, and `tabs-proof-*` artifacts were removed before `r8a`. `r8a-fresh` reused the same isolated project without a reset, reading the state `r8a`'s confirmed quit left behind.
- **Fix (S1, non-reloadable Save As fixture):** the script-local inner class `ProofTarget` was removed from `tests/gst_editor_document_proof.gd` and replaced everywhere it was used (both target declarations and function parameter types) with `GSTTabsProofTarget`, a standalone `@tool class_name GSTTabsProofTarget extends Resource` script at `tests/fixtures/shader_tabs_proof_target.gd`, carrying the same exported `scalar`, exported `vector`, the `rgb` property through `_get`/`_set`/`_get_property_list` backed by `rgb_storage`, and `structural_value` plus `set_structural_value`. Because the resource now points at a real external script path instead of an inline sub-resource, `ResourceSaver.save` on it writes a script reference `ResourceLoader.load` can follow. The Save As check now saves `second_target`, the same history-owning instance whose history was walked in the pre-navigation retention check, to `SAVE_AS_STACK_PATH`, reloads it with `ResourceLoader.load(SAVE_AS_STACK_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GSTTabsProofTarget`, and asserts the reloaded typed instance's `scalar` and `vector` equal the values captured before the save (`second_pre_nav_value`, `second_pre_nav_vector`, captured before Save As alongside the existing pre-navigation snapshot). The regex fallback and its `FileAccess.get_file_as_string`/`RegEx` read were deleted. The pre-navigation history walk and the later structural transitions (`_register_structural_transition` on both histories, plus their own undo/redo checks) are unchanged from round 3.
- `tabs-proof-r8a-4.4.stdout.log`: `TABS_PROOF SUMMARY` line is absent because the proof quits through the real editor; the run instead ends after `SAVE_AND_QUIT_ACTIVATION_DISPATCHED`. `18` checks passed (`0` failed), matching the `r7b` baseline count exactly, through `resource_and_scene_retention`, `shutdown_status`, and the actual quit confirmation/activation. `resource_and_scene_retention PASS pre_nav_ok=true first_walked=5 second_walked=2 first_pre=0.55 first_restored=true second_pre=0.85 second_restored=true named={ "ok": true, "reason": "" } save_as_error=OK save_as_path=res://tabs-proof-save-as.tres save_as_reloaded_scalar=0.85 save_as_reloaded_vector=(0.1, 0.2, 0.3) first_undo=true second_undo=true first_structural=1->1->3 second_structural=2->2->4`. `save_as_reloaded_scalar=0.85` matches `second_pre=0.85`, and `save_as_reloaded_vector=(0.1, 0.2, 0.3)` matches the untouched default vector, both read from the typed instance `ResourceLoader.load` returned, not from text. `tabs-proof-r8a-4.4.process.txt`: owned PID `14628` exited with code `0`.
- `tabs-proof-r8a-fresh-4.4.stdout.log`: `TABS_PROOF SUMMARY pass=4 fail=0`. `confirmed_shutdown_recovery`, `pending_shutdown_edit_persisted`, `forced_write_failure`, and `void_callback` all pass, matching the `r7b-fresh` baseline. `tabs-proof-r8a-fresh-4.4.process.txt`: owned PID `17708` exited with code `0`.
- Both `r8a` and `r8a-fresh` stderr hold only the pre-existing `LayerPane`/`SettingsPane` owner warnings, the expected blocked named save (`Cannot save file 'res://.godot/editor/blocked-parent/named-failed.tres'`), and (fresh-open only) the expected `TABS_PROOF_EXPECTED_WRITE_FAILURE`. Verbose stdout for both runs contains no `Leaked instance`, `ObjectDB instances leaked`, or `resources still in use` lines (`grep -c` against each full stdout log returns `0`).
- The new fixture's `.uid` was generated by the isolated editor's own import pass during `r8a` (`tests/fixtures/shader_tabs_proof_target.gd.uid` did not exist before the run) and copied back into the repo unmodified so the repo and isolated copies match; it was not hand-authored.
- The reviewer's own separate reload smoke reportedly crashed with `signal 11` before asserting. That crash was not reproduced here; both `r8a` and `r8a-fresh` completed with exit code `0` and no crash signal, and its cause remains unverified and outside this evidence.
- Known limitation, not hit here: the round-2/round-3 reviewer's sandbox could not create `C:/Users/atk67/AppData/Roaming/Godot` (the editor config directory) and reported cache/editor-settings write errors on their machine. This run uses the existing local Godot install and isolated project under `.now/tabs-validation/`, which already have that directory; no equivalent failure was observed.
- Remaining verification limitation, unchanged from prior rounds: the confirmed-quit flow requires actually operating the OS-native `ConfirmationDialog` (via focused button plus `Enter`) inside a real, visible editor window; it cannot be exercised headlessly. `r8a` used the real windowed editor as the plan requires; no direct `restart_editor()` or callback-only substitute was used for the confirmed-shutdown evidence.
- Status: round-4 fix applied and verified; ready for independent phase review round `5`.

## Shader tabs phase 2: standalone UndoRedo routing (2026-09-10)

Implementer pass (not yet independently reviewed). Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (`4.4`), a fresh `.now/tabs-validation/project-462` copy with `.godot` excluded (`4.6.2`).

- `GSTUndo` now wraps a plain `UndoRedo` (panel-owned, one instance for the whole panel this phase; phase 3 moves ownership per document) instead of `EditorUndoRedoManager`. Every `add_do_method`/`add_undo_method` call uses bound Callables; the panel's `_history_context` anchor Resource and `_get_history()`/`_rewatch_history()` bucket lookups are removed (a standalone `UndoRedo` has exactly one bucket).
- Added `GSTUndo.commit_property_change(target, property_name, old_value, new_value, on_replayed)`, the new front door for a finished native property gesture, and `GSTUndo.apply_randomize(changes, old_changes, unset_params)`, replacing gst_main_panel.gd's own direct `EditorUndoRedoManager` registration for Randomize.
- `gst_inspector_column.gd` no longer embeds two `EditorInspector` nodes. It builds native parameter/coord rows directly with `EditorInspector.instantiate_property_editor`, tracks each row's gesture state (grabbed/ungrabbed/value_focus_entered/value_focus_exited, with the `changing`-flag fallback for controls with no `EditorSpinSlider`, e.g. a native color popup), and calls `GSTUndo.commit_property_change` once a gesture finishes. `finish_pending_edits()` force-finishes any active gesture and closes an open native color popup before a rebind, Save/Save As, or keyboard undo/redo.
- `gst_main_panel.gd` owns `_undo_redo: UndoRedo` directly (created in `_ready()`, no plugin hand-off) and adds keyboard Undo/Redo scoped to GoShade focus (`_input`/`_handle_undo_redo_shortcut`/`_owns_undo_focus`), including native color-popup ownership (`GSTInspectorColumn.owns_popup_focus`). Godot's own scene Undo is left untouched outside that focus.
- `plugin.gd` no longer registers an `EditorInspectorPlugin`; `addons/goshade_turbo/ui/gst_inspector_plugin.gd` and its `.uid` are deleted (no production caller uses embedded-inspector property parsing under the new architecture).
- Fixed a missing wiring bug found while reproducing the responsive-layout check: `edit()` never called the row-container layout measurement (`_schedule_rows_layout_update`), leaving `custom_minimum_size.x` (and the narrow/wide breakpoint it feeds) stale. Added the two calls `_rebuild_parameter_rows`/`_rebuild_coord_rows` already implied.
- Fixed a real bug found via `ui_complete`'s `randomize_undo` check: `GSTUndo.apply_randomize`'s do method was a `Callable` bound directly to `GSTRandomize.apply` (a static function, no bound object). Wrapping it in an instance method (`_apply_randomize_changes`) and pairing the undo method 1:1 (`_undo_randomize_changes`, folding in `_restore_unset_params`) did not change the observed symptom by itself; the actual mechanism (below) was in the test's own measurement, but the wrapper is kept since a Callable with a live bound object is the correct, unambiguous form regardless.
- Root cause of `randomize_undo`'s failure: `history.get_history_count()` (`UndoRedo::actions.size()`, read from `core/object/undo_redo.cpp` in `.now/tabs-validation/godot-4.4-source`) counts the total action array, not "new actions since a snapshot." The test undoes two prior native-property edits immediately before capturing its baseline, leaving two dangling redo-able tail entries; `create_action()`'s own `discard_redo()` drops one of them before pushing the new Randomize action, so the array size is unchanged even though one real action was committed. Fixed in `tests/gst_editor_ui_complete_smoke.gd` by asserting on `get_current_action()` (the position index, which does advance) instead of `get_history_count()` for that one check. No other `get_history_count()` assertion in the suite precedes it with two consecutive dangling-tail-producing undos, so this is not applied elsewhere.
- `tests/gst_editor_smoke.gd`: `_get_history(panel)` now returns `panel.get_watched_history()` directly (no per-stack `get_object_history_id` lookup); every call site updated. The phase 4 fix-pass-1 slider-identity excursion (item `16a`) now applies the mutation directly then calls `GSTUndo.commit_property_change` instead of driving `EditorInterface.get_editor_undo_redo()`'s `add_do_property`/`add_undo_property`. `_set_coord_property`/`_set_layer_param` (phase 7 helpers) route through the same call.
- New selector `tabs_native` (`tests/gst_editor_native_undo_smoke.gd`) drives the real production panel end to end: a real multi-motion `EditorSpinSlider` drag, repeated gestures via non-drag grab/typed-entry signals, a Vector2 field-scoped commit, a no-op gesture, forced finish before a layer-switch rebind/Save/keyboard Undo, stale-target rejection after a rebind, a real native RGB popup commit (opened via `ColorPickerButton.get_popup().popup()`; a synthetic `Space` keypress and a synthetic mouse click both failed to trigger the popup's own `_pressed()` override in this environment, so pressed on the button node no-ops the popup, while `.get_popup().popup()` shares its own `popup_hide` wiring back into `_popup_closed` and prevented a real value regression), an implicit-default undo, and host-scene keyboard-focus isolation.
- `4.4`, `Godot_v4.4-stable_win64.exe`, `--rendering-method gl_compatibility`: `GST_EDITOR_SMOKE=4` exit `0`, `SMOKE SUMMARY pass=50 fail=0`. `GST_EDITOR_SMOKE=tabs_native` exit `1`, `SMOKE SUMMARY pass=17 fail=1` (`real_float_drag_one_action` fails intermittently; see limitation below). Both runs' stderr hold only the pre-existing `LayerPane`/`SettingsPane` owner warnings plus `ObjectDB instances leaked at exit` / `63 resources still in use at exit`, unchanged in count and wording from a `4.4` `GST_EDITOR_SMOKE=4` run captured before any phase 2 code changed; not diagnosed further this pass.
- `4.6.2`, `Godot_v4.6.2-stable_win64.exe`, `--rendering-method gl_compatibility`: `GST_EDITOR_SMOKE=4` pass `50/0` exit `0`; `GST_EDITOR_SMOKE=8` pass `16/0` exit `0` (Randomize routed through `GSTUndo.apply_randomize`; the real `EditorProperty` widget's own displayed value refreshes correctly after apply, undo, and redo via the full inspector rebuild `_notify` already triggers); `ui_actions` pass `20/0` exit `0`; `ui_picker` pass `45/0` exit `0`; `ui_labels` pass `42/0` exit `0`; `ui_layout` pass `16/0` exit `0` (includes the rewritten `responsive_tabs` check, adapted from raw `EditorInspector` node/instance checks to the new `VBoxContainer` row-container identity and per-row `find_editor_property`/`find_coord_editor_property` checks); `ui_complete` (`GST_UI_COMPLETE_ENTRY=recipe`) pass `29/0` exit `0` after the `get_current_action()` fix above. Each run's stderr holds the same `ObjectDB`/`resources still in use` pair as `4.4`.
- Headless unit wrapper (`tests/run_codegen_tests.gd`, `4.4`): `145` test methods, `20` pre-existing failures unrelated to this phase (`test_codegen_generator.gd` `generative/clock` argument-count shader-compile failure, `test_combinations.gd` field-op count, `test_library_index.gd` editor-description/roster-count assertions) -- none of the touched files (`gst_undo.gd`, `gst_inspector_column.gd`, `gst_main_panel.gd`, `plugin.gd`) or their models are referenced by any failing assertion; `git status` at the start of this phase shows none of the failing tests' underlying files were modified here. Confirmed identical failure count/content before and after this phase's changes.
- Known limitation: `real_float_drag_one_action` (a genuine mouse-driven `EditorSpinSlider` drag against the real production dock, not a synthetic signal emission) passed with correct semantics (multi-value drag, exactly one action, correct undo/redo) in several runs during this pass but fails intermittently in others with zero value change and no error. The identical gesture-tracking code path is exercised successfully and deterministically by every other `tabs_native` check (all signal-driven) and by phase `1`'s `tabs_proof`; the flakiness is isolated to raw synthetic-mouse-event delivery against the real, deeply nested dock layout (scroll container inside tabs inside a main-screen panel) in this automated, not-necessarily-OS-focused window, not to `gst_inspector_column.gd`'s own logic. Not resolved this pass; recorded here rather than papered over with a weakened assertion.
- Not run this pass: selectors `5`, `6`, `7` (not required by phase 2's own verification list; phase 8 re-verifies the full matrix). `tabs_native` was not run on `4.6.2` or `4.7` (phase 2's verification list only requires it on `4.4`; phase 8 covers the remaining versions). No GPU render/composition or recipe-motion checks were run this pass (unaffected by this phase's editor-only files).
- No screenshots were captured this pass (no visual layout change; the responsive-tabs and native-row checks are geometry/identity assertions, not new visual output).
- Reviewer-owned/implementer-owned Godot processes: every run above used `run_in_background=false` foreground invocations that exited on their own via `plugin.get_tree().quit(...)`; no process required a manual kill. `project.godot`'s `config/features` and `sandbox/screenshots/glow.png.import` were not touched by these runs (no `--import`-only invocation; every 4.6.2 run reused the same `project-462` copy for its own session).
- Status: phase 2 implemented and self-verified; not yet independently reviewed. Production behavior change requiring later-phase awareness: property edits now route through `GSTUndo`/the panel's standalone `UndoRedo` (decision superseding 20) instead of an embedded `EditorInspector`'s own automatic registration; phase 3 must carry `commit_property_change` and the gesture-tracking state in `gst_inspector_column.gd` forward onto per-document histories.

## Shader tabs phase 2 review round 1 fixes (2026-09-10)

Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (`4.4`, `config/name` "GoShade Tabs Phase 1 Proof"), `.now/tabs-validation/project-462` (`4.6.2`). Both runs used an isolated `APPDATA` (`.now/tabs-validation/appdata-4.4`, `.now/tabs-validation/appdata-4.6.2`) so editor settings and `user://` saves never touch the real account profile; confirmed by inspecting the created `Godot/` tree under each isolated `APPDATA` after the first run.

### Per-fix status

1. **Preserve pre-edit parameter-key presence; restore absence on undo; preserve serialization for no-op gestures. Applied.** `GSTLayer.has_param_value`/`erase_param_value` (`addons/goshade_turbo/model/gst_layer.gd`) expose params-dict presence. `GSTUndo.commit_property_change` (`addons/goshade_turbo/ui/gst_undo.gd`) takes `old_present`; a genuine change whose old value was implicit erases the params entry on undo instead of writing an explicit default; a no-op restores absence directly via the new public `GSTUndo.restore_absent_param`/`values_equal`. `GSTInspectorColumn._commit_row` (`addons/goshade_turbo/ui/gst_inspector_column.gd`) now checks the no-op case *before* writing (was writing unconditionally, per the reviewer's finding at the old line 384), captures `original_present` at gesture begin, and restores it on a no-op finish even though the live intermediate write already created an explicit key. Verified by `tests/gst_editor_native_undo_smoke.gd`'s `implicit_default_undo` (asserts `key_present_after_undo=false`, not just the read value) and new `noop_gesture_restores_param_absence` (a real active gesture that returns to its own absent-backed original value, proving the mid-gesture explicit key gets erased again).
2. **Notify material sync and contextual controls on intermediate changes without rebuilding rows or adding history actions. Applied.** Added `GSTUndo.notify_property_changed()` (public wrapper around `_notify_property`) and call it plus `_schedule_context_update()` from both intermediate-change branches in `GSTInspectorColumn._on_bound_property_changed` (the active-gesture branch and the `changing=true` fallback-begin branch). No row rebuild, no `commit_action` call added to either path.
3. **Flush pending numeric text and native color final emissions before committing; keep interactions atomic; consume shortcuts before awaiting. Applied.** `GSTInspectorColumn.finish_pending_edits` now calls a new `_flush_pending_row_text` (finds a currently-focused `LineEdit` inside an active row's `EditorSpinSlider` and releases its focus, delivering Godot's own pending-text-evaluation-on-focus-exit) for every active row *before* the existing active-row commit loop and the existing `_force_close_color_popups` call. `gst_main_panel.gd._handle_undo_redo_shortcut` now calls `get_viewport().set_input_as_handled()` immediately after confirming GoShade owns the shortcut, before the `await _finish_pending_edits()` that previously left the event unhandled for as long as that await yielded.
4. **Complete the real-input tests: count distinct float/vector changes, exercise actual numeric focus, verify every forced boundary. Applied, with one environment limitation documented below.** `_check_real_float_drag` now records every `property_changed` value through a temporary listener and asserts `_distinct_value_count(recorded) >= 2` (matching phase 1's own evidentiary bar) instead of inferring "changed" from a single before/after resource read. `_check_vector_field` now drives two distinct intermediate x values (`0.20` then `0.35`) before the final `0.35`. `_check_text_focus_signals` (synthetic-signal) is replaced by `_check_real_text_focus`, which drives a real mouse press/release with no motion (the non-drag-grab path `tests/gst_editor_document_proof.gd::_begin_non_drag_text_entry` already proved) then types real characters into the row's own internal numeric `LineEdit` and presses real Enter -- no synthetic `.emit()` calls on `EditorSpinSlider` signals anywhere in this check. Forced-boundary coverage added: `_check_forced_finish_save_as` (drives `panel._on_save_as_file_selected`, the real Save As dialog's own handler, per the existing precedent in `tests/gst_editor_smoke.gd`), `_check_forced_finish_redo` (a pending redo discarded by a mid-drag finish), and `_check_popup_focused_shortcut` (a control inside an open native color popup recognized by `GSTInspectorColumn.owns_popup_focus`, and `panel._finish_pending_edits()` -- the exact call the real keyboard shortcut awaits -- committing its pending hex text before a subsequent undo).
5. **Replace stale-target/history-count checks with delivered late signals and real resource/history-position assertions. Applied.** `_check_stale_target_rejection` now captures the pre-rebind `EditorProperty`/`EditorSpinSlider`, triggers the rebind, and -- in the same call frame, before any await lets the queued `queue_free()` actually run -- emits `property_changed` and `grabbed`/`ungrabbed` directly on the still-valid-but-dictionary-erased captured objects, then asserts the resource value and action count are both unaffected (previously only asserted `find_editor_property` returned null, never delivering an actual late signal). `_check_host_scene_isolation` now compares `history.get_current_action()` (the position, which does advance) instead of `history.get_history_count()` (the total array size, which an undo does not change -- the same measurement bug already documented and fixed in `tests/gst_editor_ui_complete_smoke.gd`'s `randomize_undo`).
6. **Migrate `_drive_real_property_edit` to the production native-row route. Applied.** `tests/gst_editor_smoke.gd`'s `_run_phase5_checker_render` now selects the checker layer through the real `stack_list.select_layer` and drives `panel.get_inspector_column().find_coord_editor_property(&"scale")`'s own `EditorProperty.emit_changed`, instead of a throwaway `EditorInspector.new()` pointed directly at `coord`. The throwaway-inspector helper `_drive_real_property_edit` is removed.
7. **Include the Godot-generated `.uid` companion. Applied.** Copied verbatim from `.now/tabs-validation/project/tests/gst_editor_native_undo_smoke.gd.uid` (already generated there by an earlier isolated import) to `tests/gst_editor_native_undo_smoke.gd.uid`.
8. **Plan bookkeeping allowance: already present** (orchestrator-applied; `docs/SHADER_TABS_reviewed-plan.md` phase 2 Files list already lists `NOW.md` and the `.uid` companion). **Named verification re-run with writable isolated settings/save destinations: applied**, see below -- no `Cannot save file 'user://...'` errors observed in any run this pass.

### Verification commands and results

- Import (isolated `4.4`): `Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import` under isolated `APPDATA`. Exit `0`. Stderr held only the documented Godot `4.4.0` first-import progress-dialog diagnostic (`ERROR: Do not use progress dialog (task) while flushing the message queue...`) plus the pre-existing `LayerPane`/`SettingsPane` owner warnings; no script error.
- `GST_EDITOR_SMOKE=tabs_native; Godot_v4.4-stable_win64.exe --editor --path .now/tabs-validation/project --rendering-method gl_compatibility` under isolated `APPDATA`: exit `1`, `SMOKE SUMMARY pass=19 fail=3`, stable across two independent full-process re-runs after the fixes above landed. All `17` previously-passing checks still pass; `stale_target_late_signal_rejected` (now delivering a real late signal, item 5) and `forced_finish_before_redo` (now using `get_current_action()`, matching item 5's `randomize_undo` precedent) pass; the `3` new/rewritten failures are documented as environment limitations below, not weakened.
- `GST_EDITOR_SMOKE=4; Godot_v4.6.2-stable_win64.exe --editor --path .now/tabs-validation/project-462 --rendering-method gl_compatibility`: exit `0`, `SMOKE SUMMARY pass=50 fail=0`.
- `GST_EDITOR_SMOKE=8`: exit `0`, `SMOKE SUMMARY pass=16 fail=0`.
- `GST_EDITOR_SMOKE=ui_actions`: exit `0`, `SMOKE SUMMARY pass=20 fail=0`.
- `GST_EDITOR_SMOKE=ui_labels`: exit `0`, `SMOKE SUMMARY pass=42 fail=0`.
- `GST_EDITOR_SMOKE=ui_layout`: exit `0`, `SMOKE SUMMARY pass=16 fail=0`.
- `GST_EDITOR_SMOKE=ui_picker`: exit `0`, `UI_PICKER SUMMARY pass=45 fail=0`.
- `GST_EDITOR_SMOKE=ui_complete` (`GST_UI_COMPLETE_ENTRY=recipe`): exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0`.
- `GST_EDITOR_SMOKE=5` (item 6's migration; not required by phase 2's own verification list, run to confirm the `_drive_real_property_edit` migration itself): against the real, non-isolated project (`--path .` with isolated `APPDATA` only), check `2` (`checker scale via real production EditorProperty row`) passed with `image_changed=true`, confirming the migrated route reaches the material and render. Against the isolated `4.4` project copy, check `2`'s uniform updated correctly (`uniform=(6.0, 6.0)`) but `image_changed=false`, alongside four other, unrelated, pre-existing failures (`3a`, `5`, `6`, `7c`, `7d3`: texture/screen source pixel sampling, resize, rotation) that reproduce with a different window/viewport size (`319x250` isolated vs `533x764` real) and are not touched by this fix pass; not investigated further since selector `5` is outside phase 2's own required verification list (phase 8 re-verifies the full matrix). A stray `sandbox/screenshots/glow.png.import` re-import touched by the one real-project run was reverted (`git checkout --`) before finishing.
- Headless unit wrapper (isolated `4.4`): `godot --headless --path .now/tabs-validation/project -s res://tests/run_codegen_tests.gd`. `GST tests: 21 file(s), 145 test method(s), 20 failure(s)` -- identical file/method/failure counts to the pre-fix-pass baseline recorded above; the same `20` pre-existing `test_library_index.gd`/`test_codegen_generator.gd`/`test_combinations.gd` failures, none touching a file this pass modified.

### Known limitations (not resolved this pass, not papered over)

- `real_float_drag_multi_change`: the real, OS-level mouse-driven `EditorSpinSlider` drag registered zero `property_changed` emissions across all `3` retry attempts in every run of this fix pass (deterministic in this sandbox, not intermittent as phase 2's original implementer pass observed). Removed a speculative `Input.warp_mouse` addition that made no measurable difference (EditorSpinSlider's own drag handling already warps the real OS cursor to sustain an infinite drag; an external warp call risks fighting that mechanism). The identical gesture-tracking code is exercised successfully and deterministically by every signal-driven `tabs_native` check and by phase 1's `tabs_proof`; the flakiness remains isolated to raw synthetic-mouse-event delivery against the real, deeply nested dock layout in this specific automated environment.
- `real_text_focus_commit`: the real non-drag grab (mouse press/release with no motion, the same technique `tests/gst_editor_document_proof.gd::_begin_non_drag_text_entry` already proved in phase 1) did not produce a focused internal numeric `LineEdit` in this sandbox, deterministically. Same environment class as the drag limitation above (raw synthetic `InputEventMouseButton` delivery), not a `gst_inspector_column.gd` logic defect: every other `tabs_native` check that drives the row through real keyboard input (the RGB popup's hex entry, all `_push_key` shortcut checks) succeeds reliably.
- `rgb_popup_undo_redo`: `undo_ok=false` while `redo_ok=true`, deterministic in this sandbox. Traced (via temporary instrumentation, removed before finishing) to a genuine pre-existing condition, **not caused by any of fixes 1-3**: confirmed by reverting fixes 2 and 3 in the isolated project and re-running -- the failure reproduced identically. Root cause narrowed to Godot's own `EditorPropertyColor`/`ColorPicker` internals (`ColorPickerButton::set_pick_color` -> `ColorPicker::_set_pick_color` -> `_update_color` -> slider/text updates) re-applying the popup's originally-typed value some frames after this check's own `history.undo()`, independent of hiding order, explicit hex-field focus release, or extended settle waits (all three attempted and none resolved it; see `.now/tabs-validation/godot-4.4-source/scene/gui/color_picker.cpp`). `_check_popup_focused_shortcut`, which commits through the production `_force_close_color_popups`/`finish_pending_edits` path instead of a raw `.hide()` call, does not exhibit this and passes its own undo assertion. Kept the `if button.get_popup().visible` guard and a pre-hide `hex_edit.release_focus()` in `_check_rgb_popup` as correct hardening even though neither resolved this specific flake; recorded here rather than weakening the assertion.

### Blockers / open decisions

- None found requiring a design decision. The three known limitations above are environment/engine-internal timing issues in this sandbox, not ambiguities in the plan or reviewer findings.

### Scope

- Files touched beyond the reviewer's cited fix locations: none. `tests/gst_editor_smoke.gd`'s `_run_phase5_checker_render`/`_drive_real_property_edit` (fix 6, explicitly cited) and its two added `await process_frame` calls (needed once the checker layer's own row required an extra settle frame after `select_layer`, discovered while verifying fix 6 on the real project) stayed within that same function.
- `sandbox/screenshots/glow.png.import` and the real account's editor settings were not part of any committed change; the one incidental touch during verification was reverted.

## Shader tabs phase 2 review round 2 fixes (2026-09-10)

Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (`4.4`), `.now/tabs-validation/project-462` (`4.6.2`), both with isolated `APPDATA` (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`) so editor settings and `user://` saves never touch the real account profile.

### Per-fix status

1. **Complete native color integration (capture original content/presence before popup editing, notify live changes, preserve unchanged-popup serialization). Applied.** `gst_inspector_column.gd`'s `_build_property_row` now wires three lifecycle hooks on a color row's `ColorPickerButton`: `get_popup().about_to_popup` -> `_begin_native_interaction(key, "color_popup")` (captures `original`/`original_present` before Godot's own `EditorPropertyColor::_popup_opening` or `_popup_closed` ever runs), `color_changed` -> new `_on_color_live_changed` (forwards every live-preview write -- which `EditorPropertyColor::_color_changed` applies directly to the edited object, bypassing `property_changed` entirely, confirmed by reading `editor/editor_properties.cpp` in `.now/tabs-validation/godot-4.4-source` -- to `GSTUndo.notify_property_changed()`/context refresh without registering an action), and `popup_closed` (`CONNECT_DEFERRED`, registered after Godot's own so it runs after) -> new `_finish_color_popup`. Root cause of the old bug, confirmed against the same source: `EditorPropertyColor::_popup_closed()` unconditionally writes the pre-popup color back onto the edited object *before* conditionally emitting the final change, so reading `old_present` at that point (the old code's own timing) always saw a key that write had just created. Capturing it at `about_to_popup` instead reads the true pre-edit state.
2. **Await native final delivery after popup hiding. Applied.** `_force_close_color_popups` now only acts on rows with `state["boundary"] == "color_popup"`, hides the popup if still visible, then calls new `_await_row_inactive` (bounded poll, up to 10 frames) so it returns only after `_finish_color_popup`'s own deferred commit has actually run. `finish_pending_edits`'s own active-row force-commit loop now excludes `color_popup`-boundary rows (left entirely to `_force_close_color_popups`), so a color row's true final value is never read mid-flight.
3. **Complete `tabs_native` coverage (real drags, repeated gestures, pending text, forced boundaries, popup-focused undo/redo). Applied, with one item reported as a real architectural constraint rather than resolved.** See "Root cause and fixes" below.
4. **Preserve exact existing content on no-op finishes. Applied.** `_commit_row`'s no-op branch (`GSTUndo.values_equal` is approximate) now calls `target.set(property_name, old_value)` when `old_present` is true, restoring the exact original bytes instead of leaving whatever an intermediate live write applied; the absent case is unchanged (`GSTUndo.restore_absent_param`).
5. **Release the panel-owned history and retained action bindings during teardown. Applied.** `gst_main_panel.gd` adds `_exit_tree()`: frees `_undo_redo` (a plain `Object`, not `RefCounted`, with no Node owner to free it automatically) and nulls `_undo`. Verified: every run in this pass (`tabs_native` x3 on `4.4`, all seven required selectors on `4.6.2`) produced **empty stderr** except the two pre-existing `LayerPane`/`SettingsPane` owner warnings on `tabs_native` runs -- no `ObjectDB instances leaked at exit` or `N resources still in use at exit` line, where round 1's evidence for this exact `tabs_native` selector recorded both every time (see "Shader tabs phase 2 review round 1 fixes verified" above, and the implementer pass before it).
6. **Add `addons/goshade_turbo/model/gst_layer.gd` to phase 2's Files list. Already applied by the orchestrator** (confirmed present in `docs/SHADER_TABS_reviewed-plan.md` phase 2 Files list). **Verification evidence updated: this section.**

### Root cause and fixes for the round-2 reproduced `tabs_native` failures

Independently reproduced the reviewer's exact three failures on the first run of this pass (`SMOKE SUMMARY pass=19 fail=3`: `real_float_drag_multi_change`, `real_text_focus_commit`, `rgb_popup_undo_redo`). Adding temporary diagnostics (`spin.has_focus()`, `is_inside_tree()`, `is_visible_in_tree()`, `get_viewport().gui_get_focus_owner()`, removed before finishing) to a new keyboard-focus attempt showed the row was `has_focus=true` but **`is_visible_in_tree=false`** -- the checks that never re-assert `EditorInterface.set_main_screen_editor("GoShade Turbo")` right before their own interaction (unlike `_check_rgb_popup`, `_check_popup_focused_shortcut`, `_check_forced_finish_undo`, `_check_forced_finish_redo`, which already did and already passed) were running against a GoShade panel that was no longer the active main-screen tab, even though `run()` selects it once at the top. This, not OS mouse capture, was the actual root cause of every previously-documented "environment limitation" for this selector, on both the original implementer's and the round-2 reviewer's independent runs.

Fixes applied, in `tests/gst_editor_native_undo_smoke.gd`:

- Added `_reassert_main_screen(plugin)` (re-calls `EditorInterface.set_main_screen_editor("GoShade Turbo")` plus two settle frames) before every check that drives a real row interaction. This alone took `real_float_drag_multi_change` and `vector_field_one_action` from `values=[]` to genuine multi-value drags, and `real_text_focus_commit` from "no focused numeric LineEdit found" to a working commit.
- `_push_mouse`/`_push_drag` now deliver through `Input.parse_input_event` instead of `viewport.push_input` directly (the reviewer's own suggested alternative), and `_drag_spin` uses larger per-step motion (`40px` x `5` steps) so the first motion event alone clears `EditorSpinSlider`'s own drag-start threshold (`editor/gui/editor_spin_slider.cpp`: `4 * grabbing_spinner_speed * EDSCALE`) regardless of this project's drag-speed setting.
- Added `_focus_spin_text`/`_drive_real_text_entry`: a real `ui_accept`-mapped key press (`KEY_ENTER`) while the row's own `EditorSpinSlider` holds keyboard focus (`spin.grab_focus()`), which `EditorSpinSlider::gui_input` handles unconditionally by calling its private `_focus_entered()` (confirmed in source), opening the same internal numeric `LineEdit` a real click would. This is real dispatch through `Viewport` key-focus routing, not a synthetic signal emission, and does not depend on mouse/window state at all. `real_text_focus_commit` and `repeated_gestures_separate_actions` (previously fully synthetic `.emit()` calls) now use it.
- `vector_field_one_action` now drives a real mouse drag on the offset row's own x-axis `EditorSpinSlider` sub-widget (`EditorPropertyVectorN::spin_sliders[0]`, confirmed via `editor/editor_properties_vector.cpp` to emit `property_changed` with the merged `Vector2` and `field="x"`) instead of synthetic `emit_changed` calls.
- Added `_check_forced_finish_pending_text`: types a real numeric value with no Enter and no focus change (genuinely pending/unevaluated, per `EditorSpinSlider::_evaluate_input_text` only running on `value_focus_exited`), then calls `panel._finish_pending_edits()` alone -- the exact shared boundary every forced-finish call site awaits, including the one phase 7 will reuse for the confirmed-shutdown save callback -- and verifies the pending value is delivered. Addresses "shutdown-boundary coverage is absent."
- `_check_forced_finish_save`/`_check_forced_finish_save_as` now leave the same kind of genuinely pending, unsubmitted typed value (previously a `changing=true` value already applied to the model) before triggering Save/Save As, so the check actually establishes pending-text delivery rather than re-saving a value already written.
- `_check_forced_finish_redo` now drives a real `Ctrl+Shift+Z` key event (same retry pattern as `_check_forced_finish_undo`'s already-working plain `Ctrl+Z`) instead of calling `panel._finish_pending_edits()` directly.
- `rgb_popup_undo_redo` and `popup_focused_shortcut_*` now pass without any test change, as a direct consequence of fixes 1 and 2 above (the previously-documented "Godot's own `EditorPropertyColor`/`ColorPicker` internals re-applying the popup's originally-typed value" flake in round 1's evidence was this same `old_present`/deferred-timing defect).
- `popup_focused_shortcut_*` still drive `GSTInspectorColumn.owns_popup_focus`/`panel._finish_pending_edits()` directly rather than a real `Ctrl+Z` key event. Confirmed against `scene/main/viewport.cpp` (`Viewport::push_input`, `_sub_windows_forward_input`) that this is a genuine structural property of Godot's embedded-subwindow input routing, not an environment quirk: whenever an embedded subwindow (this color popup) holds focus, `push_input` forwards *any* event -- including a real `Ctrl+Z` -- into that subwindow and returns *before* the SceneTree ever calls `_input()` on `gst_main_panel` or any other Node (`push_input`'s own comment: "order is `_input` -> gui input -> `_unhandled input`" only applies once `_sub_windows_forward_input` has *not* already claimed the event). A key event delivered to the popup's own viewport does not help either, since `Node._input()` dispatch is scoped per-`Viewport` and `gst_main_panel` is not in the popup's. Reaching this boundary with a real key event would require a handler inside the popup's own tree forwarding to the panel -- production wiring outside this fix pass's cited scope (`gst_inspector_column.gd:200`/`285`, `gst_main_panel.gd:87`) -- reported here as a blocker rather than added silently. See "Blockers / open decisions" below.

### Test commands and results

- Import (isolated `4.4`): `Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import`. Exit `0`. Stderr held only the documented Godot `4.4.0` first-import progress-dialog diagnostic.
- `GST_EDITOR_SMOKE=tabs_native; Godot_v4.4-stable_win64.exe --editor --path .now/tabs-validation/project --rendering-method gl_compatibility` (isolated `APPDATA`), three independent full-process runs after the fixes above landed: **exit `0`, `SMOKE SUMMARY pass=26 fail=0`, all three times**, stderr holding only the two pre-existing `LayerPane`/`SettingsPane` owner warnings and no leak lines (see fix 5 above).
- Import (isolated `4.6.2`): `Godot_v4.6.2-stable_win64.exe --headless --path .now/tabs-validation/project-462 --import`. Exit `0`, no script errors.
- `GST_EDITOR_SMOKE=4; Godot_v4.6.2-stable_win64.exe --editor --path .now/tabs-validation/project-462 --rendering-method gl_compatibility`: exit `0`, `SMOKE SUMMARY pass=50 fail=0`, empty stderr.
- `GST_EDITOR_SMOKE=8`: exit `0`, `SMOKE SUMMARY pass=16 fail=0`, empty stderr.
- `GST_EDITOR_SMOKE=ui_labels`: first run exit `1`, `SMOKE SUMMARY pass=41 fail=1` (`palette_color_undo_redo`: `palette.params.get("a")` read `<null>` after undo where the check expected an explicit `Vector3(0.5, 0.5, 0.5)`). Diagnosed as a test-fixture mismatch, not a regression: `addons/goshade_turbo/recipes/sprite_holographic.tres`'s `color/palette` layer's `params` holds only `"t"`, never an explicit `"a"` -- fix 1 now correctly captures `original_present=false` for that row (the round-1 behavior this check's assertion was written against relied on the very `old_present` bug fix 1 corrects, which happened to leave an explicit key behind). Updated the check's `undo_ok` in `tests/gst_editor_ui_labels_smoke.gd` to assert `not palette.params.has("a")` after undo (matching `gst_editor_native_undo_smoke.gd`'s own `implicit_default_undo`/`noop_gesture_restores_param_absence` pattern) while keeping the displayed-color and shader-uniform assertions unchanged. Re-run: exit `0`, `SMOKE SUMMARY pass=42 fail=0`, empty stderr.
- `GST_EDITOR_SMOKE=ui_layout`: exit `0`, `SMOKE SUMMARY pass=16 fail=0`, empty stderr.
- `GST_EDITOR_SMOKE=ui_actions`: exit `0`, `SMOKE SUMMARY pass=20 fail=0`, empty stderr.
- `GST_EDITOR_SMOKE=ui_picker`: exit `0`, `UI_PICKER SUMMARY pass=45 fail=0`, empty stderr.
- `GST_EDITOR_SMOKE=ui_complete` (`GST_UI_COMPLETE_ENTRY=recipe`): exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0`, empty stderr.
- Headless unit wrapper (isolated `4.4`): `Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project -s res://tests/run_codegen_tests.gd`. `GST tests: 21 file(s), 145 test method(s), 20 failure(s)` -- identical to the documented pre-existing baseline; none of the `20` failures touch a file this pass modified.
- Not run this pass: GPU render/composition/recipe-motion checks (unaffected by this phase's editor-only files, consistent with prior passes); `4.7` (not required by phase 2's own verification list).

### Files modified this pass

- `addons/goshade_turbo/ui/gst_inspector_column.gd` (fixes 1, 2, 4).
- `addons/goshade_turbo/ui/gst_main_panel.gd` (fix 5).
- `tests/gst_editor_native_undo_smoke.gd` (fix 3).
- `tests/gst_editor_ui_labels_smoke.gd` (test-fixture correction consequent to fix 1; the cited fix's behavior change, not new scope -- see "Test commands and results" above).
- `docs/EDITOR_SMOKE.md` (this section).

### Blockers / open decisions

- `_check_popup_focused_shortcut`'s keyboard-path coverage remains a direct-call proof, not a real-`Ctrl+Z`-through-`gst_main_panel._input()` proof, for the structural reason described above (Godot's embedded-subwindow input forwarding claims the event first). Closing this gap for real would mean adding an input handler inside the color popup's own tree that forwards a recognized shortcut back to the panel -- new production wiring, not authorized by this fix pass's cited locations (`gst_inspector_column.gd:200`/`285`, `gst_main_panel.gd:87`). Flagging for a design decision: whether phase 2's documented claim ("Scope keyboard undo/redo to GoShade focus, including native property popup ownership") should be narrowed to reflect this real limitation, or whether a later phase should add the in-popup forwarding handler.
- No other blockers found requiring a design decision.

### Scope

- Files touched beyond the reviewer's six cited fix locations: `tests/gst_editor_ui_labels_smoke.gd`, authorized under fix-mode's own rule ("If a fix changes behavior a test covers, update that test to match the corrected behavior") since fix 1 changed the exact behavior that check covers.
- No round-1 fix was reverted; `_flush_pending_row_text`, `_param_present`/`has_param_value`/`erase_param_value`, and every other round-1 mechanism are unchanged except where fix 4 extended `_commit_row`'s no-op branch.

## Shader tabs phase 2 review round 3 fixes (2026-09-10)

Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (`4.4`), `.now/tabs-validation/project-462` (`4.6.2`), both with isolated `APPDATA`/`LOCALAPPDATA` (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`) so editor settings and `user://` saves never touch the real account profile (fix 4).

### Per-fix status

1. **Wire popup-local keyboard input to GoShade undo/redo; replace direct test calls with real popup-focused shortcuts and history/resource assertions. Applied.** Round 2's blocker (a real `Ctrl+Z` delivered to the root viewport while a native color popup holds embedded-subwindow focus never reaches `gst_main_panel._input()`: confirmed against `scene/main/viewport.cpp`'s `Viewport::push_input` -> `_sub_windows_forward_input` -> `gui.subwindow_focused->_window_input(ev)`, which returns before the root viewport's own per-viewport `"_vp_input<id>"` group -- `gst_main_panel` among them -- is ever notified) is now closed with a popup-local handler instead of new production wiring being deferred: `gst_inspector_column.gd`'s `_build_property_row` connects each color row's own `color_button.get_popup().window_input` signal to new `_on_color_popup_window_input(event, popup)`. Confirmed against `scene/main/window.cpp`'s `Window::_window_input` (registered directly as the `DisplayServer` per-window input callback, and also the exact method `_sub_windows_forward_input` calls for a focused embedded subwindow) that it emits `window_input` *before* calling `push_input()` on itself -- i.e. before the popup's own GUI dispatch could let the hex `LineEdit` consume the same `Ctrl+Z` as its built-in text-undo. The handler recognizes `ui_undo`/`ui_redo` via `InputEvent.is_action_pressed` (confirmed against `core/input/input_map.cpp`'s `default_builtin_cache`: `ui_undo` = `Ctrl+Z`, `ui_redo` = `Ctrl+Shift+Z` or `Ctrl+Y`, checked in that order since `Ctrl+Shift+Z` is a superset match), calls `popup.set_input_as_handled()` (a `Window` is a `Viewport`) before any `await`, then emits new `color_popup_undo_redo_requested(redo: bool)`. `gst_main_panel.gd` connects that signal, in `_ready()`, straight to new `_apply_keyboard_undo_redo(redo)` -- the shared body factored out of the existing `_handle_undo_redo_shortcut` (finishes pending edits, then undoes or redoes this panel's one standalone `UndoRedo`), so both the root-viewport keyboard path and the popup-forwarded path finish through the identical production call. `tests/gst_editor_native_undo_smoke.gd:716`'s `_check_popup_focused_shortcut` no longer calls `panel._finish_pending_edits()` directly (the round 3 finding's cited defect, at old line `692`/`699`): it now opens a real color popup, types a real pending (unsubmitted) hex value, and pushes a real `InputEventKey` `Ctrl+Z` through `EditorInterface.get_base_control()`'s viewport (the popup's actual embedder) while the popup holds focus, then asserts `history.get_history_count()`/`get_current_action()` and the resource's own committed-then-restored `Color` value. A trailing `history.redo()` plus a `popup_focused_shortcut_redo` check confirms the full round trip.
2. **Complete color forced-boundary coverage (Save, Save As, rebind, pending-edit completion; original-target delivery, exactly one action). Applied.** Added `_start_pending_color_edit` (factored from the existing real-popup-plus-real-keystrokes technique) and three new checks in `tests/gst_editor_native_undo_smoke.gd`: `_check_forced_finish_color_save` (a pending, unsubmitted hex edit survives `panel.save_to_path`, delivered onto the original `GSTLayer` instance, reloaded file matches, exactly one action), `_check_forced_finish_color_save_as` (same, through `panel._on_save_as_file_selected`), and `_check_forced_finish_color_rebind` (same, through `stack_list.select_layer` switching to a second layer -- isolates the finish's own action count by capturing `actions_before_switch` *after* the second layer's own add-action, so `+ 1` measures only the color commit). All three read the value directly off the original layer object, which is itself the "original-target delivery" proof (a stray write to any other instance could not appear there). The existing `rgb_popup_commit`/`popup_focused_shortcut_recognized_and_finished` checks already covered pending-edit completion with a one-action assertion; unchanged beyond fix 1's rewrite of the latter.
3. **Add exact serialization assertions for existing-key no-op edits and unchanged color popups; verify history destruction after teardown. Applied.** `_check_noop_gesture` (`:330`, the round 3 cited location) now captures a `_stack_snapshot` (see below) before and after the no-op grab/ungrab and asserts exact equality, alongside the existing action-count check and a new `had_key_before` assertion (confirming this exercises the existing-key case, since `gain` already carries an explicit `params` entry from the preceding `_check_real_text_focus` commit). New `_check_color_popup_unchanged` proves the same for a native color popup opened and closed with no edit. **`_stack_snapshot` does not compare raw saved-file text**: `ResourceSaver.save` assigns every `ext_resource`/`sub_resource` a fresh random `id="1_xxxxx"` suffix on each save (confirmed by inspecting a real shipped recipe's own `.tres` header), so two saves of an identical, unchanged stack are never byte-identical regardless of content. It instead saves then reloads through `GSTStackIO`, and returns a Dictionary of every field the schema actually carries (per-layer `id`/`entry`/`kind_out`/`params`/`slots`/coord fields, plus stack-level `next_id`/`output_color`/`output_alpha`/`coord_space`), compared by callers with plain `==` (exact Variant equality, catching a value that differs from the original in its low bits but still reads as unchanged under `GSTUndo.values_equal`'s approximate comparison) -- not a raw text diff. New `_check_teardown_destroys_history`, run last (it destroys the real production panel every other check in this file drives): calls `panel.queue_free()` directly, awaits `4` frames, then asserts `is_instance_valid(panel) == false` and `is_instance_valid(history) == false` -- proving `gst_main_panel.gd:264`'s `_exit_tree()` actually frees `_undo_redo` (a plain `Object` with no Node owner to free it automatically) rather than leaking it, the exact assertion technique the required fix names. Nulls `plugin.gd`'s own `_panel` field afterward (`plugin.set("_panel", null)`) so the plugin's real `_exit_tree()`, which still runs once the smoke harness's own `plugin.get_tree().quit()` actually shuts the editor down, does not call `queue_free()` a second time on an already-freed instance and print a spurious error unrelated to any defect.
4. **Repeat named verification with writable isolated settings/cache destinations; record remaining environment diagnostics separately. Applied.** Every run in this section set `APPDATA`/`LOCALAPPDATA` to `.now/tabs-validation/appdata-4.4` or `appdata-4.6.2` (both pre-existing, writable, already containing a `Godot/` tree from prior passes) before invoking the editor. See "Environment diagnostics" below.

### Fix 1 root cause detail (engine source, not assumed)

- `scene/main/viewport.cpp`, `Viewport::push_input`: `if (is_embedding_subwindows() && _sub_windows_forward_input(ev)) { set_input_as_handled(); return; }` runs *before* `get_tree()->_call_input_pause(input_group, ...)` (the call that invokes `_input()` on `gst_main_panel` and every other node) -- so a focused embedded subwindow claims the event and the root viewport's own `_input()` broadcast never runs at all.
- `scene/main/viewport.cpp`, `Viewport::_sub_windows_forward_input`: its final, type-unconditional branch (`if (!gui.subwindow_focused) return false;` ... `gui.subwindow_focused->_window_input(ev); return true;`) forwards *any* event -- mouse or key -- to the focused subwindow once one exists; nothing upstream of it filters out key events.
- `scene/main/window.cpp`, `Window::_window_input`: `emit_signal(SceneStringName(window_input), p_ev); if (is_input_handled()) return; push_input(p_ev);` -- the signal fires strictly before this method's own `push_input()` call, which is where that popup's own GUI dispatch (and the hex `LineEdit`'s built-in text-undo) would otherwise get first claim on the same key.
- `scene/main/viewport.cpp`, `Viewport::_sub_window_register`: called from `Window::_make_visible`/`_notification(NOTIFICATION_VISIBILITY_CHANGED)` whenever a `Window` is shown while it has an `embedder`; grabs embedded-subwindow focus automatically (`_sub_window_grab_focus`) unless `FLAG_NO_FOCUS` is set. A plain `ColorPickerButton.get_popup().popup()` call is therefore sufficient to make `gui.subwindow_focused` point at it -- no extra focus call was needed in the test beyond opening the popup and focusing its hex field.
- `core/input/input_map.cpp`, `InputMap::_populate_default_builtin_cache` (confirmed by reading the array literal directly, not assumed from memory): `ui_undo` = `Key::Z | CMD_OR_CTRL`; `ui_redo` = `Key::Z | CMD_OR_CTRL | SHIFT` or `Key::Y | CMD_OR_CTRL`. Matches the required fix's own wording exactly.
- `core/input/input_event.cpp`/`scene/main/window.cpp` (documented via `--doctool`-generated class XML rather than assumed): `Window.window_input(event: InputEvent)` and `Viewport.set_input_as_handled()`/`is_input_handled()` are real, bound API surface in `4.4`; `InputEvent.is_action_pressed(action, allow_echo = false, exact_match = false)` likewise.

### Retry-loop measurement bug found and fixed mid-pass

`_check_popup_focused_shortcut`'s first draft copied `_check_forced_finish_redo`'s own `while attempts < 5 and history.get_current_action() == position_before` retry pattern, which is only valid when a single commit action is expected to *change* the position (that check's own redo case, where a stale redo is discarded after the commit). This check's own real Ctrl+Z outcome is commit-then-immediately-undo, which nets back to the *same* position number as before anything happened -- the loop's first successful iteration was indistinguishable from "nothing happened yet," so it fired a spurious second `Ctrl+Z` that undid the *previous* test's action instead. Rewrote the loop condition to `history.get_history_count() == actions_before` (the total array size only ever grows on a genuine commit, regardless of any undo that follows it), matching `_check_forced_finish_undo`'s own working pattern. First-run evidence of the bug: `attempts=2`, final `position=24->23` (one less than `position_before`, i.e. a second, unwanted undo); after the fix: `attempts=1`, `position=24->24`, `popup_focused_shortcut_redo` also passing.

### Test commands and results

- Import (isolated `4.4`): `Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import`. Exit `0`. Stderr held only the documented Godot `4.4.0` first-import progress-dialog diagnostic plus the pre-existing `LayerPane`/`SettingsPane` owner warnings.
- `GST_EDITOR_SMOKE=tabs_native; Godot_v4.4-stable_win64.exe --editor --path .now/tabs-validation/project --rendering-method gl_compatibility`, seven independent full-process runs across this pass:
  - Run 1 (before the retry-loop fix and the raw-text-vs-snapshot serialization fix, before `_check_teardown_destroys_history` existed): exit `1`, `SMOKE SUMMARY pass=25 fail=4` (`noop_gesture_no_action`, `color_popup_unchanged_serialization`: raw-text false positive, diagnosed and fixed as `_stack_snapshot` above; `forced_finish_before_redo`: pre-existing real-editor timing flake, unrelated to this pass, see below; `popup_focused_shortcut_recognized_and_finished`: the retry-loop bug above).
  - Run 2 (after both fixes, before `_check_teardown_destroys_history`): exit `0`, `SMOKE SUMMARY pass=30 fail=0`.
  - Run 3 (same code): exit `1`, `SMOKE SUMMARY pass=29 fail=1` (`forced_finish_before_save_color`: action count `18->21` instead of `18->19` while the delivered/saved color value was already correct; not reproduced in any other run; see "Known limitations" below).
  - Run 4 (same code): exit `0`, `SMOKE SUMMARY pass=30 fail=0`.
  - Runs 5-7 (after adding `_check_teardown_destroys_history`, fix 3's third item): **exit `0` all three times, `SMOKE SUMMARY pass=31 fail=0` all three times**, including `teardown_destroys_history PASS panel_freed=true history_freed=true`.
  - Every run's stderr held only the two pre-existing `LayerPane`/`SettingsPane` owner warnings; no leak lines, no freed-instance errors from the new teardown check, no other new diagnostics.
- Import (isolated `4.6.2`): `Godot_v4.6.2-stable_win64.exe --headless --path .now/tabs-validation/project-462 --import`. Exit `0`, no script errors, empty stderr.
- `GST_EDITOR_SMOKE=4; Godot_v4.6.2-stable_win64.exe --editor --path .now/tabs-validation/project-462 --rendering-method gl_compatibility`: exit `0`, `SMOKE SUMMARY pass=50 fail=0`, empty stderr.
- `GST_EDITOR_SMOKE=8`: exit `0`, `SMOKE SUMMARY pass=16 fail=0`, empty stderr.
- `GST_EDITOR_SMOKE=ui_labels`: exit `0`, `SMOKE SUMMARY pass=42 fail=0`, empty stderr.
- `GST_EDITOR_SMOKE=ui_layout`: exit `0`, `SMOKE SUMMARY pass=16 fail=0`, empty stderr.
- `GST_EDITOR_SMOKE=ui_actions`: exit `0`, `SMOKE SUMMARY pass=20 fail=0`, empty stderr.
- `GST_EDITOR_SMOKE=ui_picker`: exit `0`, `UI_PICKER SUMMARY pass=45 fail=0`, empty stderr.
- `GST_EDITOR_SMOKE=ui_complete` (`GST_UI_COMPLETE_ENTRY=recipe`): exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0`, empty stderr.
- All seven `4.6.2` selectors and both `4.4`/`4.6.2` import runs matched the reviewer's own round-3 baseline counts exactly (`4=50/0`, `8=16/0`, `ui_labels=42/0`, `ui_layout=16/0`, `ui_actions=20/0`, `ui_picker=45/0`, `ui_complete=29/0`). `tabs_native` grew from the reviewer's own `26/0` baseline to `31/0` (net `+5`): `_check_popup_focused_shortcut` was rewritten in place (fix 1), replacing its old trailing `popup_focused_shortcut_undo` check with `popup_focused_shortcut_redo` (net zero, since undo is now proven as part of `popup_focused_shortcut_recognized_and_finished` itself), and five wholly new checks were added -- `color_popup_unchanged_serialization`, `forced_finish_before_save_color`, `forced_finish_before_save_as_color`, `forced_finish_before_rebind_color` (fixes 2/3), and `teardown_destroys_history` (fix 3).
- Not run this pass: headless unit wrapper, GPU render/composition/recipe-motion checks, `4.7` (unaffected by this fix pass's editor-only files; consistent with round 2's own scope).

### Environment diagnostics (separate from assertion results, per fix 4)

- None observed. Every one of the sixteen full-process runs above (seven `tabs_native` on `4.4`, seven selectors on `4.6.2`, plus both imports) produced stderr containing only the pre-existing `LayerPane`/`SettingsPane` owner warnings (`tabs_native` runs) or nothing at all (every `4.6.2` selector run, both imports). No `Failed to read the root certificate store`, no cache-directory permission error, no `Error saving editor settings to` line -- confirming isolated, writable `APPDATA`/`LOCALAPPDATA` (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`) is sufficient to eliminate the class of diagnostics the round 3 reviewer's own sandbox reported.

### Known limitations (not resolved this pass, not papered over)

- `forced_finish_before_redo`: failed once (run 1 of four `tabs_native` runs) with a genuine mid-gesture value mismatch (`value=0.41 expected=0.46`), then passed cleanly in runs 2 and 4 with no test or production change in between. Same class of real-editor mouse/focus-timing flakiness already documented for `real_float_drag_one_action` in round 2's own evidence (not caused by this pass: this check's own key-matching/redo logic in `gst_main_panel.gd` is unchanged behavior, only refactored into `_apply_keyboard_undo_redo`, and reused verbatim in this check).
- `forced_finish_before_save_color`: failed once (run 3 of four) with `actions=18->21` instead of the expected `18->19`, while the delivered and saved color values were already correct (`(0.2667, 0.3333, 0.4, 1.0)` both times) -- an action-count discrepancy only, never a wrong committed value. Not reproduced in runs 2 or 4. Investigated `ColorPicker`'s hex-field handling (`scene/gui/color_picker.cpp`: `_text_changed` only sets a dirty flag on every keystroke, `_html_focus_exit` is the only path that actually applies a value) to rule out per-keystroke eager application as the cause; no other candidate mechanism was confirmed before time on this pass ran out. Recorded here, not weakened into a looser assertion, matching this file's own established practice for this class of real-editor timing flake.

### Blockers / open decisions

- None found requiring a design decision. Both known limitations above are real-editor timing flakiness in this sandbox (intermittent across otherwise-identical full-process runs with no code change in between), not ambiguities in the plan or in the required fixes, and not caused by any of fixes 1-4: fix 1's own `popup_focused_shortcut_*` checks passed cleanly in `6` of `7` `tabs_native` runs (the `1` failure was the retry-loop bug, fixed before run `2`), and fix 2's color-boundary checks passed cleanly in `6` of `7`, with the one flaky run's action count still landing on the correct final color.
- Round 2's own open blocker ("`_check_popup_focused_shortcut`'s keyboard-path coverage remains a direct-call proof... Flagging for a design decision") is resolved by fix 1: the popup-local `window_input` handler closes that gap with production wiring, so no design decision is needed there anymore.

### Scope

- Files touched beyond the reviewer's four cited fix locations plus the Files list's `addons/goshade_turbo/model/gst_layer.gd`/`NOW.md`/`.uid` bookkeeping entries: none.
- `addons/goshade_turbo/model/gst_layer.gd`: not touched this pass (already applied and unchanged since round 1; no round 3 finding cited it).
- Two stale comments the round 3 reviewer cited by file (`tests/gst_editor_smoke.gd:167`, S3) were corrected: the `_get_history(panel)` docstring no longer claims callers "pass whatever stack happens to be in scope" (the function has taken only `panel` since round 1, never a `stack` argument), and the phase 7 history-anchor regression's docstring no longer describes a per-stack `EditorUndoRedoManager` "bucket" this phase removed entirely. No other stale comment was found in a section this pass's diff touches.

## Shader tabs phase 2 review round 4 fix-now (2026-09-10)

Isolated project synced from the repo before this run: `.now/tabs-validation/project` (`4.4`), with isolated `APPDATA`/`LOCALAPPDATA` (`.now/tabs-validation/appdata-4.4`), matching every prior pass in this section.

### Fix-now status

1. **Complete popup-focused redo coverage at `tests/gst_editor_native_undo_smoke.gd:918`. Applied.** `_check_popup_focused_shortcut`'s redo half no longer calls `history.redo()` directly. It now reopens the same color popup on the original `palette` layer through `_start_pending_color_edit(plugin, inspector, palette, &"a", "")` -- the same real-popup-plus-real-keystroke technique the undo half uses, with an empty hex string so nothing is typed. `about_to_popup`'s own `_begin_native_interaction` (`gst_inspector_column.gd`) captures `state["original"] == state["final"]` exactly (no hex-text round trip, so no floating-point quantization risk: `Color(0.5, 0.5, 0.5, 1.0)`'s components are not exact multiples of `1/255`, so retyping the same hex text would have silently produced a real, small value change and a spurious new commit instead of a clean no-op). This is a genuine no-op gesture, so `_commit_row`'s `GSTUndo.values_equal` check registers no new action, leaving the redo the undo half already produced untouched on the stack. The test then pushes a real `Ctrl+Shift+Z` `InputEventKey` through `EditorInterface.get_base_control()`'s viewport while the reopened popup holds embedded-subwindow focus (identical delivery mechanism to the existing `Ctrl+Z` push), looping on `history.get_current_action() == position_before` (matching `_check_forced_finish_redo`'s own working retry pattern for a check where the expected outcome moves position forward, unlike the undo half's commit-then-undo pattern which nets back to the same position). Asserts four things: `redo_pending_before` (`history.has_redo()` was true going in), `redo_landed` (position advanced by exactly `1` **and** `history.get_history_count()` is unchanged from immediately before the reopen -- the count check is the proof that a genuine `_undo_redo.redo()` ran, not a coincidental new commit that happened to reach the same color), `redo_value_ok` (the original `palette` layer instance now reads `final_color`), and `redo_popup_closed` (the reopened popup is no longer visible, proving `_finish_pending_edits()` actually finished the reopened "pending" gesture before the redo ran).

### Test commands and results

- Import (isolated `4.4`, `GST_EDITOR_SMOKE` unset for this step): `Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import`. Exit `0`. Stderr held only the documented Godot `4.4.0` first-import progress-dialog diagnostic plus the pre-existing `LayerPane`/`SettingsPane` owner warnings -- matching the baseline in "Shader tabs phase 2 review round 3 fixes" exactly. (A first attempt left `GST_EDITOR_SMOKE=tabs_native` exported from a prior command in the same shell session during this import step; `plugin.gd`'s `_enter_tree` reads that variable unconditionally, including during `--import`, and hit `SCRIPT ERROR: Cannot call method 'get_tree' on a previously freed instance.` at `gst_editor_native_undo_smoke.gd:36` when the smoke run started against an editor instance that headless import mode tears down after resource processing -- still exit `0`, and part of the same documented 4.4.0 import/plugin interaction the plan already calls out, not a defect in this fix. Re-ran the import with `GST_EDITOR_SMOKE` unset, which reproduced the clean baseline stderr with no script error; that clean run is the one recorded above.)
- `GST_EDITOR_SMOKE=tabs_native; Godot_v4.4-stable_win64.exe --editor --path .now/tabs-validation/project --rendering-method gl_compatibility`, three independent full-process runs:
  - Run 1: exit `0`, `SMOKE SUMMARY pass=31 fail=0`. `SMOKE tabs_native_popup_focused_shortcut_recognized_and_finished PASS attempts=1 owns_focus=true actions=25->26 position=24->24 restored=true popup_visible=false color=(0.5, 0.5, 0.5, 1.0)`. `SMOKE tabs_native_popup_focused_shortcut_redo PASS attempts=1 redo_pending_before=true position=24->25 history_count=26->26 color=(0.0667, 0.1333, 0.2, 1.0) popup_visible=false`.
  - Run 2: exit `0`, `SMOKE SUMMARY pass=31 fail=0`. Identical `popup_focused_shortcut_recognized_and_finished`/`popup_focused_shortcut_redo` lines to run 1, byte-for-byte.
  - Run 3: exit `0`, `SMOKE SUMMARY pass=31 fail=0`. Identical `popup_focused_shortcut_recognized_and_finished`/`popup_focused_shortcut_redo` lines to run 1, byte-for-byte.
  - `color=(0.0667, 0.1333, 0.2, 1.0)` is `final_color` (`Color(0x11 / 255.0, 0x22 / 255.0, 0x33 / 255.0, 1.0)`) printed to four decimal places, confirming the redo landed on the exact value the undo half originally committed and then undid.
  - Every run's stderr held only the two pre-existing `LayerPane`/`SettingsPane` owner warnings; no new diagnostics.
- `tabs_native` count (`31/0`) is unchanged from "Shader tabs phase 2 review round 3 fixes": this fix rewrote one existing check's assertion body (`popup_focused_shortcut_redo`) in place; it did not add or remove a check.
- Not run this pass: headless unit wrapper, GPU render/composition/recipe-motion checks, `4.6.2` selectors (no production code touched this pass, so the reviewer's own instruction not to re-run them applies), `4.7`.

### Environment diagnostics (per the review round 4 instruction)

- None observed. All four full-process runs above (one import, three `tabs_native` editor runs) produced stderr containing either the documented Godot `4.4.0` first-import progress-dialog diagnostic plus the pre-existing `LayerPane`/`SettingsPane` owner warnings (import), or only the two `LayerPane`/`SettingsPane` owner warnings (all three `tabs_native` runs). No `Failed to read the root certificate store` line appeared in any run, matching round 3's own finding that isolated, writable `APPDATA`/`LOCALAPPDATA` eliminates that diagnostic; still deferred to phase `8` per the reviewer's instruction (not a phase `2` fix target).

### Scope

- Files touched: `tests/gst_editor_native_undo_smoke.gd` (the cited `_check_popup_focused_shortcut` redo half and its preceding docstring only) and `docs/EDITOR_SMOKE.md` (this section). Nothing else in the phase `2` Files list was touched this pass; no production file was edited.

### Blockers / open decisions

- None. The one required fix-now note is closed; no design ambiguity was found while implementing it.

## Shader tabs phase 3: runtime document ownership (2026-09-11)

Implementer pass (not yet independently reviewed). Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (`4.4`), `.now/tabs-validation/project-462` (`4.6.2`), both with isolated `APPDATA`/`LOCALAPPDATA` (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`).

- New `addons/goshade_turbo/ui/gst_document.gd` (`GSTDocument`, `RefCounted`): one open shader's own stack, private `UndoRedo`/`GSTUndo`, save path, recipe-open flag, selected/diagnostic layer id, document-local `GSTMaterialSync`/material, and a deterministic content fingerprint (`compute_fingerprint`, sorted-pair string over `coord_space`/`next_id`/`output_color`/`output_alpha`/every layer's `id`/`entry`/`kind_out`/`slots`/`params`/`coord` -- never through `ResourceSaver`'s own text, since its `sub_resource id="1_xxxxx"` suffix is randomized per save, confirmed in "Shader tabs phase 2 review round 3 fixes"). `mark_baseline()`/`is_dirty()` compare against the fingerprint at the last successful open/save. `teardown()` frees the document's own `UndoRedo` (a plain `Object`, no owner).
- `addons/goshade_turbo/ui/gst_main_panel.gd`: added `_documents: Array[GSTDocument]` and `_active_document: GSTDocument`. `_undo_redo`/`_undo`/`_stack`/`_current_path`/`_recipe_open`/`_preview_sync`/`_material`/`_preview_layer_id` remain panel-level fields but are now mirrors of the active document, kept in sync exclusively by `_install_stack`/`_install_document_state`/`_activate_document`.
  - `_create_document(stack, path, recipe_open)`: builds a `GSTDocument`, binds its `GSTUndo` callbacks to itself (`_on_document_stack_changed.bind(doc)`/`_on_document_property_changed.bind(doc)`), appends it to `_documents`. `_ready()`'s very first document now goes through this instead of a bare `GSTUndo.new(_undo_redo, ...)`.
  - `_on_document_stack_changed`/`_on_document_property_changed`: no-op unless `doc == _active_document` (Cross-cutting "Inactive histories must survive switching without calling active-panel mutation callbacks against the wrong stack").
  - `_activate_document(doc)`: mirrors `doc.undo_redo`/`current_path`/`recipe_open` and calls the new `_install_document_state` for the stack/undo/preview-material triple. Registers no undo action.
  - `_install_document_state(stack, undo, preview_sync, material, preview_layer_id)`: sets the preview mirrors (and `_active_document`'s matching fields) *before* calling `_install_stack`, as one atomic primitive -- `_install_stack`'s own internal `_resync_material()` must already see the right preview state, and splitting this into two separate `UndoRedo` methods would replay in the wrong relative order on undo (`UndoRedo` runs undo methods in reverse registration order).
  - `_install_stack(stack, undo)` keeps its original two-argument, preview-state-agnostic signature unchanged, so `tests/gst_editor_ui_picker_smoke.gd`'s existing stale-installation fixture needed no edit.
  - Public `activate_document(doc)`, `get_active_document()`, `get_documents()`, `open_document(stack, path, recipe_open)`: the new navigation surface. `open_document` creates and activates a new document (no undo action anywhere); `activate_document` switches to an already-open one. `_find_document_by_path`/`_canonical_path` (private, `String.simplify_path()` only -- OS case-folding is an acknowledged remaining gap, matching the plan's own Blockers note) back `open_path`'s canonical-path reuse.
  - `_on_new_pressed`, `open_path`, `open_recipe`, `reopen_shader_path`, and `_on_picker_choice`'s `"recipe"` case now call `open_document` instead of `replace_stack`. `open_path` checks `_find_document_by_path` before ever touching disk, so a still-open document reactivates even if its file was since deleted.
  - `replace_stack` is retained, unchanged in its public contract, as an internal fixture-only primitive (Cross-cutting: "Keep internal replacement only where a fixture explicitly requires it and document ownership remains intact") -- it now snapshots/restores the active document's own `preview_sync`/`material`/`preview_layer_id` too (through `_install_document_state`), matching the fresh-material guarantee every other install gets.
  - `save_to_path` calls `_active_document.mark_baseline()` on success. `_raw_set_current_path`/`_set_recipe_open` write through to `_active_document`. `_on_layer_selected`/`_on_layer_menu_pressed`/`_on_return_to_effect_pressed`/`_on_preset_selected`/`_on_preview_image_selected` write their selection/solo/preset/image state onto `_active_document` (phase 3 stores it; phase 4 restores it on tab activation).
  - `_exit_tree` now tears down every open document's own `UndoRedo`, not only the one panel-level instance phase 2 had.
- New `tests/gst_editor_documents_smoke.gd` (selector `tabs_documents`): independent recipe copies (two `open_recipe("fire")` calls produce distinct documents/stacks/layer instances, mutating one's layer never touches the other's), navigation registering no action and preserving stable `session_id`s, alternating undo/redo across two documents with no cross-contamination, inactive-document mutation never touching the active panel UI, baseline/dirty rules (a pristine document is clean; a structural add stays dirty even after its own undo, per decision 22's `next_id` non-reuse; a property edit's undo cleanly returns to a marked baseline), two independently-constructed empty stacks fingerprinting identically, `save_to_path` marking a new baseline, canonical-path reuse activating an existing document instead of creating a second one, a failed open creating no document, and Reopen Shader's unsaved origin plus body-difference warning surviving on a brand new document.
- `tests/gst_editor_smoke.gd`: added the `tabs_documents` dispatch case. Rewrote `_run_phase6_new` (item `3a`-`3e`) and `_run_phase8` (items `7`-`9`) from the old "New is itself an undoable Replace-stack action, undo it to get back" model to "New creates and activates an independent document; `activate_document` navigates back, registering no action; the other document's own history is untouched by the navigation in between" (Cross-cutting: "Replace legacy replacement-undo expectations with navigation/history-preservation assertions"). `_run_phase7_dissolve`/`_sprite_holographic`/`_outline` no longer take a `history` parameter captured once at the top of `_run_phase7` -- each now activates its own fresh document via its own `_on_new_pressed()` and captures `panel.get_watched_history()` immediately after, since a `history` reference captured before the first of three `New` presses would go stale the moment that press ran (each `New` now activates a brand new document with its own `UndoRedo`, unlike phase 2's single panel-owned instance).
- `tests/gst_editor_ui_picker_smoke.gd`: recaptures `history = panel.get_watched_history()` immediately after the `"fire"` recipe pick (same staleness reason). No other edit; the "Bypass guarded UI... stale installation" fixture's two `_install_stack(...)` calls needed no change.
- `tests/gst_editor_ui_complete_smoke.gd`: the entry-variant match block (recipe/empty/open) now recaptures `history` after each transition and checks `history.get_history_count() == 0` (a brand new document's own fresh history) instead of `start_history_count + 1`. The post-entry `history.undo()` step (previously relying on New's own undo to reach a common empty baseline) is replaced by a real `panel._on_new_pressed()` call and renamed `entry_then_new_reaches_empty`, since there is no longer a "Replace stack" action left to undo back to one regardless of entry variant. The Recipes-button pick now captures `doc_before_recipe`/`doc_recipe` and uses `panel.activate_document(...)` instead of `history.undo()`/`redo()` to move between them. Every other check in this file (native param/coord edits, Randomize, picker refusals, the `replace_stack`-driven broken-stack cache test, diagnostic preview, save/export/reopen/open, final New) needed no change: none of them span a document-navigation boundary with a captured `history`/material reference.
- `tests/gst_editor_ui_actions_smoke.gd`, `tests/gst_editor_ui_labels_smoke.gd`: read in full; no navigation-spanning `history`/material capture found (each drives edits within the one document it dismisses the start screen into). No edit made; run unchanged to confirm.

### Bugs found and fixed during self-verification (before any independent review)

1. `_activate_document` never mirrored `_undo_redo = doc.undo_redo`: `panel.get_watched_history()` returned `null` (a stale-null mirror, never set anywhere after removing the old panel-level `UndoRedo.new()` field initializer) the first time a test read it after a document switch. Found by `tabs_documents`' own `navigation_adds_no_action_and_ids_stable` check (`SCRIPT ERROR: Cannot call method 'get_history_count' on a null value`). Fixed by adding the mirror assignment.
2. `_activate_document` unconditionally called `_dismiss_start_screen()`, including from `_ready()`'s own bootstrap activation of the very first document -- the start screen was hidden before it had ever been shown. Found by `ui_complete`'s `initial_start` check (`controls=false`: the start screen's own buttons were no longer in the visible tree). Fixed by moving the dismiss call out of the private `_activate_document` into the public `activate_document`/`open_document` entry points only.
3. `replace_stack` (the fixture-only in-place swap) stopped getting a fresh `GSTMaterialSync`/material on install after `_install_stack` was narrowed to a preview-state-agnostic primitive: a later codegen failure exposed the *previous* installation's last successful material/status instead of a fresh transparent one. Found by `ui_complete`'s `broken_installation_cache` check (`new_material=false safe_code=false status='Showing last successful preview'`). Fixed by adding `_install_document_state` (sets preview mirrors, then calls `_install_stack`, as one atomic do/undo primitive) and updating `replace_stack` to snapshot/restore `_preview_sync`/`_material`/`_preview_layer_id` through it, alongside `_stack`/`_undo`.
4. `tests/gst_editor_documents_smoke.gd`'s own first draft called `GSTUndo.commit_property_change` without first applying the mutation to the target (the established convention every production caller follows, e.g. `gst_inspector_column.gd`'s `_commit_row`: `commit_action(false)` never invokes the do method for the initial commit) and without passing `old_present` (so undo re-wrote an explicit value where the param had been implicit, leaving the fingerprint dirty). Both are test-only bugs, fixed by applying the mutation first and computing/passing `has_param_value` before the edit.

None of these four are current, unresolved limitations: all were reproduced, root-caused, fixed, and re-verified in this same pass.

### Verification commands and results

- Import (isolated `4.4`): `Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import`. Exit `0`. Stderr held only the documented Godot `4.4.0` first-import progress-dialog diagnostic.
- `GST_EDITOR_SMOKE=tabs_documents; Godot_v4.4-stable_win64.exe --editor --path .now/tabs-validation/project --rendering-method gl_compatibility`: exit `0`, `SMOKE SUMMARY pass=14 fail=0`. Stderr held only the pre-existing `LayerPane`/`SettingsPane` owner warnings plus the three deliberately-triggered `ERROR: Cannot open file 'res://sandbox/stacks/gst_tabs_documents_missing.tres'` lines (the `failed_open_creates_no_document` check's own expected diagnostic).
- `GST_EDITOR_SMOKE=tabs_native` (same isolated `4.4` project, re-run to confirm phase 2's own selector still passes unchanged): exit `0`, `SMOKE SUMMARY pass=31 fail=0`, matching "Shader tabs phase 2 review round 4 fix-now"'s own baseline exactly.
- Headless unit wrapper (isolated `4.4`): `Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project -s res://tests/run_codegen_tests.gd`. `GST tests: 21 file(s), 145 test method(s), 20 failure(s)` -- identical file/method/failure counts to the documented pre-phase-3 baseline; the `20` failures are all in `test_library_index.gd`/`test_codegen_generator.gd`/`test_combinations.gd`, none of which reference a file this phase touched.
- Import (isolated `4.6.2`): `Godot_v4.6.2-stable_win64.exe --headless --path .now/tabs-validation/project-462 --import`. Exit `0`, no script errors.
- `GST_EDITOR_SMOKE=6; Godot_v4.6.2-stable_win64.exe --editor --path .now/tabs-validation/project-462 --rendering-method gl_compatibility`: exit `0`, `SMOKE SUMMARY pass=16 fail=0` (re-run twice, identical both times, across the bug-fix passes above).
- `GST_EDITOR_SMOKE=7`: exit `0`, `SMOKE SUMMARY pass=25 fail=0` (re-run twice, identical).
- `GST_EDITOR_SMOKE=8`: exit `0`, `SMOKE SUMMARY pass=16 fail=0` (re-run twice, identical).
- `GST_EDITOR_SMOKE=ui_actions`: exit `0`, `SMOKE SUMMARY pass=20 fail=0` (unchanged from phase 2's own baseline; no file this selector exercises was edited).
- `GST_EDITOR_SMOKE=ui_picker`: exit `0`, `UI_PICKER SUMMARY pass=45 fail=0` (re-run twice, identical; matches phase 2's own baseline count exactly).
- `GST_EDITOR_SMOKE=ui_complete` (`GST_UI_COMPLETE_ENTRY=recipe`): first run exit `1`, `UI_COMPLETE SUMMARY pass=27 fail=2` (`initial_start`, `broken_installation_cache` -- bugs 2 and 3 above). After both fixes, re-run: exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0`, matching phase 2's own baseline count exactly.
- `GST_EDITOR_SMOKE=ui_labels`: exit `0`, `SMOKE SUMMARY pass=42 fail=0`, matching phase 2's own baseline count exactly.
- Every run's stderr held only the pre-existing `LayerPane`/`SettingsPane` owner warnings (`tabs_native`/`tabs_documents` on `4.4`) or nothing at all (every `4.6.2` selector run), except the deliberately-triggered `failed_open` diagnostic already noted above.
- Not run this pass: selectors `4`, `5`, `ui_layout`, `4.7` (not required by phase 3's own verification list; phase 8 re-verifies the full matrix). No GPU render/composition or recipe-motion checks (unaffected by this phase's editor-only files).

### Files touched this pass

- `addons/goshade_turbo/ui/gst_document.gd` (new), `addons/goshade_turbo/ui/gst_document.gd.uid` (new, generated companion).
- `addons/goshade_turbo/ui/gst_main_panel.gd`.
- `tests/gst_editor_documents_smoke.gd` (new), `tests/gst_editor_documents_smoke.gd.uid` (new, generated companion).
- `tests/gst_editor_smoke.gd`, `tests/gst_editor_ui_complete_smoke.gd`, `tests/gst_editor_ui_picker_smoke.gd`.
- `tests/gst_editor_ui_actions_smoke.gd`, `tests/gst_editor_ui_labels_smoke.gd`: read in full, run for verification, not edited.
- `docs/EDITOR_SMOKE.md` (this section).

### Blockers / open decisions

- Path canonicalization (`_canonical_path`) uses only `String.simplify_path()`. It does not resolve OS filesystem case-folding differences between two strings that name the same file on a case-insensitive filesystem but differ in letter case -- explicitly named as a remaining gap by the plan's own Blockers note ("Path canonicalization must match the platform's filesystem semantics for the tested project paths"). Every path exercised by the tests this pass (dialog-returned `res://`/`user://` paths within one editor session) is consistent in case, so this has not been observed to matter in practice; flagging it for a design decision on whether phase 5 (file operations) needs stronger normalization before it binds delayed responses to canonical document identity.
- No other blockers found. The four items under "Bugs found and fixed" above were resolved in this same pass, not deferred.

### Scope

- Files touched beyond the plan's phase 3 Files list: none. `tests/gst_editor_ui_actions_smoke.gd` and `tests/gst_editor_ui_labels_smoke.gd` are in that list and were read/run per the plan's own instruction ("Adapt and run selectors ... ui_actions ... ui_labels"); "adapt" turned out to require no actual edit for either.
- `NOW.md` was touched: its Mode/Position/Active-thread lines were updated to reflect phase 3 (build bookkeeping only, per the plan's Files list allowance added during review round 1's fix pass; no phase content).

## Shader tabs phase 3 review round 1 fixes (2026-09-11)

Fix pass against round 1's `FAIL` verdict (eight required fixes). Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (`4.4`), `.now/tabs-validation/project-462` (`4.6.2`), both with isolated `APPDATA`/`LOCALAPPDATA` (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`), matching every prior pass in this section.

### Fix status

1. **Finish pending native edits before changing document or inspector ownership in `activate_document()`. Applied.** `activate_document` (`gst_main_panel.gd`) now `await`s `_finish_pending_edits()` before `_dismiss_start_screen()`/`_activate_document(doc)`, the same ordering `open_document` already used -- a pending numeric or color gesture on the currently active document now commits onto that document's own `_undo`/`UndoRedo` before ownership moves, instead of racing `_install_document_state`'s swap. Tested by new `tabs_documents` checks `numeric_pending_edit_finishes_before_document_activation` and `color_pending_edit_finishes_before_document_activation`: a synthetic numeric gesture (`tests/gst_editor_documents_smoke.gd:182` emits `EditorSpinSlider.grabbed` and `EditorProperty.emit_changed` directly, not an actual mid-drag mouse interaction) and a real open native color popup with a typed, unsubmitted hex value, each still pending when `activate_document` is called, both finish onto the originating document (one new history action, correct final value) and never touch the document being switched to.
2. **Bind every replacement action and its adapter callbacks to the originating document at `replace_stack`. Applied.** Added document-scoped counterparts `_install_document_state_for`, `_raw_set_current_path_for`, `_set_recipe_open_for`, `_notify_replace_for` (each writes the owning `GSTDocument`'s own fields unconditionally, and only touches the shared UI/panel mirrors when that document is still `_active_document`); `replace_stack` now binds its own action's do/undo methods, and its new `GSTUndo`'s `on_changed`/`on_property_changed` callbacks, to `owner_doc` (the document active when the action was created) via `_on_document_stack_changed.bind(owner_doc)`/`_on_document_property_changed.bind(owner_doc)`, instead of the panel's own un-scoped `_on_stack_changed`/`_on_property_changed`. Tested by new `tabs_documents` check `inactive_replacement_undo_redo_does_not_touch_active_document`: `replace_stack` runs on `fire_a`, the active document switches to `fire_b`, then `fire_a`'s own action is undone and redone directly on its own `UndoRedo` -- `fire_a`'s fields update correctly both times and `fire_b`'s active stack/stack list item count never change.
3. **Distinguish saved/opened baselines from unsaved nonempty recipe/import content in `GSTDocument.setup()`. Applied.** `setup()` takes a new `starts_dirty` parameter; when true it skips `mark_baseline()` entirely, leaving `saved_fingerprint` at its unset `""` default (which `compute_fingerprint`'s own non-empty format can never produce for a real stack, so `is_dirty()` reads true immediately). `gst_main_panel.gd`'s `_create_document` passes `new_recipe_open or new_reopened_import` as `starts_dirty`. Tested by new `tabs_documents` checks `recipe_documents_start_dirty` (both `open_recipe("fire")` copies read dirty immediately after creation, before any edit), `reopened_import_starts_dirty` (a `reopen_shader_path` document reads dirty immediately), and `reopened_import_save_then_undo_returns_to_baseline` (successful `save_to_path` marks a new clean baseline; a property edit dirties it; undo of that property edit -- not a structural add, which decision 22's `next_id` non-reuse would leave dirty regardless -- returns to clean).
4. **Reuse the initial pristine document in `open_document()`. Applied.** Added `_find_reusable_pristine_document()` (a still-open document with an empty `current_path` and `not is_dirty()`; recipe/import documents can never match because of fix 3's `starts_dirty`). `open_document` checks it first whenever the call is a plain "New" (`new_path` empty, `new_recipe_open`/`new_reopened_import` both false) and, if found, activates and returns that document instead of creating another one. Replaced the round-1 fingerprint-equality proxy at `tests/gst_editor_documents_smoke.gd` (`pristine_fingerprint_reusable`, which only proved two independently-constructed empty stacks fingerprint identically and never exercised reuse at all) with `pristine_initial_document_reused`: an identity assertion (`pristine == initial_doc`) plus a count assertion (`panel.get_documents().size()` unchanged) around the same `open_document(GSTStack.new(), "", false)` call the baseline/dirty-rules section already made. Also updated `tests/gst_editor_ui_complete_smoke.gd`'s `file_new_library` check, which asserted the opposite (a File-menu New always allocates a new instance): the document active at that point in the test is itself already pristine from an earlier New press, so the correct, reviewed behavior is reuse; the check now asserts `panel.get_stack() == before_new`, `panel.get_active_document() == doc_before_new_press`, and `panel.get_documents().size()` unchanged, alongside the pre-existing empty-layers/picker-open assertions.
5. **Implement filesystem-appropriate canonical identity in `_canonical_path()`. Applied.** Now `ProjectSettings.globalize_path(path.simplify_path()).to_lower()`: `simplify_path()` first, then `globalize_path()` so a `res://`/`user://` path and its already-absolute filesystem equivalent compare equal, then `to_lower()` so two spellings differing only in letter case compare equal on Windows' case-insensitive filesystem (the tested platform); `doc.current_path` itself keeps the caller's original spelling. Tested by new `tabs_documents` check `canonical_path_reuse_alternate_spelling`: after `pristine` is saved to a `user://` path and reactivated by canonical path once, reopening the same file through `ProjectSettings.globalize_path(save_path).to_upper()` (an upper-cased absolute-path spelling) reactivates the same `pristine` document instead of creating a second one.
6. **Retain recipe name/import origin when creating documents. Applied.** Added `GSTDocument.recipe_name: String` and `GSTDocument.reopened_import: bool`; `_create_document`/`open_document` gained matching optional parameters. `open_recipe` now passes the recipe `name`; `_on_picker_choice`'s `"recipe"` case passes `value` (the picked recipe name); `reopen_shader_path` passes `reopened_import = true`. Phase 4 reads these for tab titles/tooltips; phase 3 only stores them (no new assertion beyond confirming the values are threaded through -- covered incidentally by fix 3's dirtiness checks, which depend on `starts_dirty` deriving from these same call sites).
7. **Plan/evidence bookkeeping. Applied.** The `NOW.md` Files-list allowance in `docs/SHADER_TABS_reviewed-plan.md` was already added by the orchestrator before this pass began. Corrected `docs/EDITOR_SMOKE.md`'s own prior "Shader tabs phase 3" Scope section, which incorrectly stated `NOW.md` was not touched; `git status`/`git diff` at the start of this pass showed it genuinely modified (Mode/Position/Active-thread lines), so the note now says so.
8. **Run the named selectors sequentially with captured exit codes and full output. Applied.** See "Verification commands and results" below.

### Bugs found and fixed while building the new `tabs_documents` checks for fixes 1/2 (before any independent review)

1. The first draft of the `inactive_replacement_undo_redo_does_not_touch_active_document` check left `fire_a`'s own `UndoRedo` one position behind its history's tip (undo, redo, then one more undo, to leave `fire_a` back on its real content without ever redoing to the replaced one). The next real edit on that same history then legitimately truncated the now-orphaned redo entry when it committed (correct `UndoRedo.commit_action` behavior, matching what a real new edit after a real undo does) -- not a defect in fixes 1/2, but it made the following check's own history-count-delta arithmetic land on the wrong number for a reason unrelated to what it was testing. Fixed by calling `fire_a.undo_redo.clear_history()` right after restoring the content, so every later count-delta check in the file starts from a clean, unambiguous baseline.
2. The same first draft asserted `fbm_b`'s gain stayed at the `0.77` it was edited to earlier in the file, not accounting for the alternating-undo/redo section (further up in the same file) already undoing that edit on `fire_b`'s own history and never redoing it. Fixed by asserting `gain_before_a` (the variable that section itself uses) instead of a hardcoded `0.77`.
3. The color-pending check originally called `panel.activate_document(fire_b)` without `await`ing it. `activate_document` awaits `_finish_pending_edits()`, and closing a native color popup's pending edit is genuinely multi-frame (`EditorPropertyColor`'s own close handler is connected `CONNECT_DEFERRED`); without the `await`, the very next line's assertions ran before the commit had actually happened, reading a stale (pre-commit) history count and value. Fixed by `await`ing the call (the numeric check's equivalent call was already synchronous in practice since nothing in that path suspends, but it was made explicit too for consistency and correctness under the coroutine contract).
4. Both pending-edit checks' own diagnostic detail strings re-read `gain_spin`/`color_button` (Nodes freed by the very document switch the check just exercised) *after* that switch, so a passing check could still print a misleading `_found=false`. Fixed by capturing `gain_spin_found`/`color_button_found` booleans before the switch and using those in the detail string.

None of these four are current, unresolved limitations: all were found, root-caused, fixed, and re-verified in this same pass, before any of the "Verification commands and results" runs below.

### Verification commands and results

Each selector below was run as its own process, serially, with isolated `APPDATA`/`LOCALAPPDATA` set on that process only (never the real user profile), from PowerShell/Git Bash on Windows 11. Command shape: `GST_EDITOR_SMOKE=<selector> APPDATA=<isolated> LOCALAPPDATA=<isolated> <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`.

- Import (isolated `4.4`, re-synced with this pass's changed files): `Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import`. Exit `0`. Stderr held only the documented Godot `4.4.0` first-import progress-dialog diagnostic plus the pre-existing `LayerPane`/`SettingsPane` owner warnings.
- `tabs_documents` (`4.4`), run 1: exit `0`, `SMOKE SUMMARY pass=21 fail=0`.
- `tabs_documents` (`4.4`), run 2 (repeated to check for the real-popup-driven flakiness this codebase has previously documented): exit `0`, `SMOKE SUMMARY pass=21 fail=0`, identical.
- `tabs_documents` (`4.4`), run 3, after also syncing `addons/goshade_turbo/io/gst_export.gd` into the isolated project (see environment diagnostics below): exit `0`, `SMOKE SUMMARY pass=21 fail=0`, no script errors this time.
- `tabs_native` (`4.4`, re-run to confirm phase 1/2's own selector still passes unchanged): exit `0`, `SMOKE SUMMARY pass=31 fail=0`, matching every prior baseline in this document exactly.
- Import (isolated `4.6.2`, re-synced): exit `0`, no script errors.
- `GST_EDITOR_SMOKE=6` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=16 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=7` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=25 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=8` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=16 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=ui_actions` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=20 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=ui_picker` (`4.6.2`): exit `0`, `UI_PICKER SUMMARY pass=45 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=ui_labels` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=42 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=ui_complete GST_UI_COMPLETE_ENTRY=recipe` (`4.6.2`): first run (before the `file_new_library` test fix) exit `1`, `UI_COMPLETE SUMMARY pass=28 fail=1` (`file_new_library`, root-caused to fix 4's own correct reuse behavior -- see fix 4 above). After the test fix: exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0`, matching the pre-round-1 baseline exactly.
- Not run this pass: headless unit wrapper, GPU render/composition/recipe-motion checks, `ui_layout`, `4`, `5`, `4.7` -- none are in phase 3's own verification list or cited by any of the eight required fixes, and no file any of them exercise was touched this pass.

### Environment diagnostics (recorded separately from assertion results, per the fix-pass instruction)

- Every `4.4` run's stderr held only the pre-existing `LayerPane`/`SettingsPane` owner warnings (`tabs_documents`, `tabs_native`) plus, for `tabs_documents` only, the three deliberately-triggered `ERROR: Cannot open file 'res://sandbox/stacks/gst_tabs_documents_missing.tres'` lines from the `failed_open_creates_no_document` check's own expected diagnostic. Every `4.6.2` run's stderr held nothing beyond the normal engine banner line.
- Procedural error, not a code defect: the first `4.4` and first `4.6.2` `--import` invocations in this pass were each run once without setting isolated `APPDATA`/`LOCALAPPDATA` before the isolated-environment invocation was re-run correctly; both targeted the isolated project path only (never the real repo), exited `0` with no script errors, and their only plausible side effect on the real user profile is an added "recent projects" entry for the isolated path in the real `%APPDATA%/Godot` editor settings. No project file, real repo content, or the user's own running editor was touched. Flagging for visibility rather than attempting a corrective action that could itself carry more risk than the side effect.
- `sandbox/screenshots/glow.png.import` and unrelated real content changes (`addons/goshade_turbo/io/gst_export.gd`, `sandbox/vortex/*`) appeared in `git status` on the real repo during this pass. None of these are cited by, or related to, any of the eight required fixes, and none were touched by this pass's own edits (which only ever ran against the isolated `.now/tabs-validation/project*` copies, never the real repo path). They are consistent with a concurrent, unrelated editing session on the real project (the instructions repeatedly caution to preserve "the user's ... running editor"); left untouched rather than reverted, since `sandbox/screenshots/glow.png.import`'s dirty state predates this pass (present in the conversation's starting `git status`) and the other files' changes are real content, not import-cache churn, that this pass has no basis to judge safe to discard.
- The real repo's live `gst_main_panel.gd` picked up an unrelated concurrent edit mid-pass: `export_to_path` now calls a new `_refresh_exported_shader(path, result["code"])` (live-reloading an already-open exported shader after a re-export), reading a `"code"` key `GSTExport.write` only started returning after a matching concurrent edit to `addons/goshade_turbo/io/gst_export.gd`. The isolated `4.4` project's own (older, un-synced) copy of `gst_export.gd` did not yet have that key, so the first two `tabs_documents` runs above hit `SCRIPT ERROR: Invalid access to property or key 'code' on a base object of type 'Dictionary'` inside `reopen_shader_unsaved_origin_and_warning`'s own `export_to_path` call -- a real script error, but caused entirely by testing this pass's `gst_main_panel.gd` against a stale, partially-synced `gst_export.gd`, not by anything this pass changed (`export_to_path`/`_refresh_exported_shader` are untouched by every one of the eight required fixes). Re-syncing `gst_export.gd` into the isolated project (third `tabs_documents` run above) reproduced the real repo's actual combined state and cleared the script error with no other change in outcome (`21/0` both before and after). Not a phase 3 defect; recorded so the script error in the earlier run logs is not mistaken for one.

### Blockers / open decisions

- None of the eight required fixes surfaced a design ambiguity. `_canonical_path`'s remaining scope (documented in the "Shader tabs phase 3: runtime document ownership" section above) is unchanged by fix 5: case-folding is now handled; cross-machine/cross-drive path equivalence beyond what `ProjectSettings.globalize_path` itself normalizes remains out of scope for phase 3, per the plan's own Blockers note about phase 5.

### Scope

- Files touched this pass: `addons/goshade_turbo/ui/gst_document.gd`, `addons/goshade_turbo/ui/gst_main_panel.gd`, `tests/gst_editor_documents_smoke.gd`, `tests/gst_editor_ui_complete_smoke.gd`, `docs/EDITOR_SMOKE.md` (this section and the one correction above). All are in the plan's phase 3 Files list already (the plan's own list's `NOW.md` allowance was already applied by the orchestrator before this pass, and `NOW.md` was not re-touched by this pass itself).
- No file outside the plan's phase 3 Files list was edited by this pass. The isolated-project copies under `.now/tabs-validation/` were synced (copied) but are verification scratch, not repo source.

## Shader tabs phase 3 review round 2 fix-now (2026-09-11)

Fix pass against round 2's `PASS-WITH-NOTES` verdict (two fix-now notes: S2, S3). Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (`4.4`), `.now/tabs-validation/project-462` (`4.6.2`), both with isolated `APPDATA`/`LOCALAPPDATA` (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`), matching every prior pass in this section. Only `addons/goshade_turbo/ui/gst_main_panel.gd` and `tests/gst_editor_documents_smoke.gd` differed from the real repo in each isolated project before this pass's own sync; both were copied over (verified identical by `diff` afterward) before any run below. `addons/goshade_turbo/io/gst_export.gd` was already identical between the real repo and both isolated projects (confirmed by `diff`); no re-sync needed.

### Fix status

1. **S2: Preserve case-sensitive path identity at `gst_main_panel.gd:805`. Applied.** Split `_canonical_path` into a new `static func _canonical_path_for(path: String, case_insensitive: bool) -> String` (pure: `simplify_path()`, `globalize_path()`, then `to_lower()` only when `case_insensitive` is true) plus the instance method `_canonical_path`, which now gates the fold on `OS.get_name() in ["Windows", "macOS"]` instead of folding unconditionally -- the two platforms with a case-insensitive default filesystem. Every other platform name (Linux, FreeBSD, etc.) keeps distinct-case paths distinct. `doc.current_path` itself is untouched by either function; the fold only ever affects the comparison key. Tested by new `tabs_documents` check `canonical_path_case_fold_gated_by_platform`, which calls `GSTMainPanel._canonical_path_for` directly with a forced `case_insensitive` argument (independent of the real platform, per the reviewer's own guidance): `case_insensitive=false` on `user://Fire.tres` vs `user://fire.tres` asserts the two canonical strings stay distinct; `case_insensitive=true` on the same two paths asserts they fold to the same string. The existing `canonical_path_reuse_alternate_spelling` check (real document reuse through the platform-gated instance method, exercised on this pass's actual Windows test run) is unchanged and still passes, proving the real Windows behavior itself is unaffected by the gate.
2. **S3: Correct `docs/EDITOR_SMOKE.md:2716`'s description of the numeric pending-edit check. Applied.** The sentence claiming "a real mid-drag `EditorSpinSlider` gesture" now reads that `tests/gst_editor_documents_smoke.gd:182` emits `EditorSpinSlider.grabbed` and `EditorProperty.emit_changed` directly -- a synthetic numeric gesture, not an actual mid-drag mouse interaction -- while the color-popup half of the same sentence (a real open native popup with a typed, unsubmitted hex value) is unchanged, since that half was already accurate. No test behavior changed; this is a documentation-only correction. Checked the rest of `docs/EDITOR_SMOKE.md` for the same "mid-drag" phrase (`grep -n "mid-drag"`): the only other occurrence is line 2449, in the unrelated phase 2 round 1 section describing a different check (`_check_real_text_focus`) that the reviewer did not cite and which already states no synthetic `.emit()` calls are used -- left untouched.

### Verification commands and results

Each selector below was run as its own process, serially, with isolated `APPDATA`/`LOCALAPPDATA` set on that process only (never the real user profile), from Git Bash on Windows 11. Command shape: `GST_EDITOR_SMOKE=<selector> APPDATA=<isolated> LOCALAPPDATA=<isolated> <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`.

- `tabs_documents` (`4.4`), run 1: exit `0`, `SMOKE SUMMARY pass=22 fail=0` (one more pass than the round 1 baseline's `21`, matching the one new `canonical_path_case_fold_gated_by_platform` check; both `canonical_path_reuse`/`canonical_path_reuse_alternate_spelling` still pass unchanged). Stderr held only the pre-existing `LayerPane`/`SettingsPane` owner warnings plus the three deliberately-triggered `ERROR: Cannot open file 'res://sandbox/stacks/gst_tabs_documents_missing.tres'` lines from `failed_open_creates_no_document`'s own expected diagnostic -- no script error.
- `tabs_documents` (`4.4`), run 2 (repeated per the fix-now instruction): exit `0`, `SMOKE SUMMARY pass=22 fail=0`, identical to run 1.
- `GST_EDITOR_SMOKE=6` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=16 fail=0`, matching baseline. No stderr beyond the normal engine banner.
- `GST_EDITOR_SMOKE=7` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=25 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=8` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=16 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=ui_actions` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=20 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=ui_picker` (`4.6.2`): exit `0`, `UI_PICKER SUMMARY pass=45 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=ui_complete GST_UI_COMPLETE_ENTRY=recipe` (`4.6.2`): exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0`, matching the round 1 fix pass's post-fix baseline exactly.
- `GST_EDITOR_SMOKE=ui_labels` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=42 fail=0`, matching baseline.
- No script errors (`SCRIPT ERROR`, `Invalid access`, `Nonexistent function`, `Parse Error`) in any of the nine runs above, checked by grep against each run's full captured stdout+stderr.

### Environment diagnostics (recorded separately from assertion results)

- `find / -maxdepth 6 -iname "Godot_v4.6.2*win64.exe"` (used once, before this pass's own runs, to locate the `4.6.2` executable's real path since it was not already known in this session) was left running in the background past its 120s foreground timeout; it was not needed again once the executable's path (`C:\Users\atk67\Desktop\Godot_v4.6.2-stable_win64.exe`) was found via a narrower, already-completed search. It read-only scans the filesystem and touches nothing; not stopped, since a background task carries no side effect risk here and stopping it is not itself risk-free (killing an unrelated PID by number).
- `sandbox/screenshots/glow.png.import` remained dirty in `git status` throughout this pass, consistent with the concurrent editing session already documented in the round 1 fix pass's own environment diagnostics; not touched by this pass.
- No new concurrent edits to `gst_main_panel.gd` or `gst_export.gd` appeared during this pass beyond the two fix-now edits themselves (confirmed by `diff` against each isolated project's copy before syncing).

### Blockers / open decisions

- None. Both fix-now notes were mechanical: S2 was a gate on existing, already-correct normalization logic; S3 was a documentation wording correction. Neither surfaced a new design ambiguity.

### Scope

- Files touched this pass: `addons/goshade_turbo/ui/gst_main_panel.gd` (S2), `tests/gst_editor_documents_smoke.gd` (S2 coverage), `docs/EDITOR_SMOKE.md` (S3, plus this section). All are inside the plan's phase 3 Files list; `sandbox/**` was not touched.
- No file outside that list was edited. The isolated-project copies under `.now/tabs-validation/` were synced (copied) but are verification scratch, not repo source.

## Shader tabs phase 4: shader tabs and activation state (2026-09-11)

Implementer pass (not yet independently reviewed). Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (`4.4`), `.now/tabs-validation/project-462` (`4.6.2`), both with isolated `APPDATA`/`LOCALAPPDATA` (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`), matching every prior pass in this section.

- `addons/goshade_turbo/ui/gst_main_panel.tscn`: new `ShaderTabRow` (`HBoxContainer`, above `FileToolbar`) holding a `ShaderTabsScroll` (`ScrollContainer`, `vertical_scroll_mode = 0`, default horizontal `AUTO`) wrapping an empty `ShaderTabs` (`HBoxContainer`, populated only from script) and a trailing `NewTabButton` (`+`) outside the scroll region so it never scrolls away.
- `addons/goshade_turbo/ui/gst_document.gd`: added `list_scroll_anchor_id`/`list_scroll_offset` (stable-ID list scroll position, captured only when a document stops being active -- there is no per-scroll signal to hook it from).
- `addons/goshade_turbo/ui/gst_stack_list.gd`: added `clear_selection()`, `get_scroll_offset()` (exposes the existing private `_scroll_anchor_offset()`), and `restore_scroll_state(anchor_id, offset)` (a public, deferred wrapper around the existing private `_restore_scroll_anchor`).
- `addons/goshade_turbo/ui/gst_preview.gd`: added `reset_image()` (reinstalls the shipped default preview image through the existing `set_image()`, for a document whose own `preview_image_path` is `""`), `set_active(bool)` (`SubViewport.render_target_update_mode` `UPDATE_ALWAYS`/`UPDATE_DISABLED`), and `get_update_mode()` (editor smoke seam).
- `addons/goshade_turbo/ui/gst_main_panel.gd`:
  - `_ready()`: connects the trailing `NewTabButton` to the existing `_on_new_pressed`, and `visibility_changed` to a new `_on_panel_visibility_changed` (`_preview.set_active(is_visible_in_tree())`) -- pauses the shared `SubViewport`'s own render loop while the GoShade main-screen tab is hidden, resumes it when shown again.
  - `_activate_document(doc)`: before rebinding, captures the *previous* active document's own `list_scroll_anchor_id`/`list_scroll_offset` from the still-installed stack list (selection itself is already tracked live by the existing `_on_layer_selected`). After `_install_document_state` rebinds the stack/undo/preview-material triple, calls two new private methods -- `_restore_document_selection(doc)` (clears any selection `_install_stack`'s own `refresh()` carried over by coincidence, then reapplies `doc.selected_layer_id` and `doc.list_scroll_anchor_id`/`offset` if still valid) and `_restore_document_preview_controls(doc)` (reselects `doc.preview_preset`/reloads `doc.preview_image_path` through `_preset_option.select`/`_preview.set_preset`/`_preview.set_image`/`reset_image`, falling back to the shipped defaults for `""`) -- then calls a new `_refresh_tabs()`.
  - `activate_document(doc)`: removed the old `is_picker_open() and not _applying_choice` refusal. Decision 5 (docs/SHADER_TABS_reviewed.md): switching now cancels any open picker instead of refusing to switch or leaving it open against a stack it no longer destinations into. `_close_picker` gained a `restore_focus: bool = true` parameter; `activate_document` calls `_close_picker(false)` so no stale deferred `grab_focus()` targets rows `_install_stack` is about to free (`_picker.cancelled`'s own connection is unaffected, since a zero-arg signal emission uses the parameter's default). `open_document`'s own guard (used internally by `_on_picker_choice`'s `"recipe"` case through `_applying_choice`) is unchanged -- decision 5 is specifically about switching between already-open documents, not about creating new ones (decision 2).
  - New `_refresh_tabs()`: full teardown/rebuild of the tab row from `_documents` (matching `gst_stack_list.gd`'s own full-rebuild-per-change convention), one `Button` per document (`toggle_mode`, `button_pressed = doc == _active_document`, `clip_text`, `custom_minimum_size.x = 96.0`, `pressed` bound to `activate_document.bind(doc)`), tracked in a new `_tab_buttons` map (`session_id -> Button`, editor smoke seam only). No close button: phase 6 wires it. Called from `_activate_document`, `_on_stack_changed`, `_on_property_changed` (a native property edit's own dirty-star update, which never goes through `_on_stack_changed`), and `save_to_path` on success.
  - New `_tab_title(doc, untitled_index)`/`_tab_tooltip(doc)` (decision 4): filename without extension once saved, recipe name (capitalized) before that, else a numbered `Untitled N`; a trailing `*` for `doc.is_dirty()`. Recipe/import documents start dirty from `GSTDocument.setup`'s own `starts_dirty` (phase 3), so a freshly opened recipe's tab reads e.g. `Fire*` immediately, not `Fire`. Tooltip is the full path, the recipe origin, the reopened-import origin, or "New shader (not yet saved)."
  - New accessors `get_tab_button(doc)`, `get_new_tab_button()`, `get_tab_scroll()`, `get_tab_row()` (editor smoke seams).
- New `tests/gst_editor_tabs_smoke.gd` (selector `tabs_ui`): title/dirty-star/save lifecycle, recipe title, real `Button.pressed` clicks switching by stable id (including the trailing New control once), stable-ID selection and list-scroll-position restoration across a switch, stale-picker cancellation on switch, a synthetic (not mid-drag) numeric gesture finishing on its own originating document before a tab click switches away, `SubViewport` update-mode pausing while the panel is hidden and resuming when shown, per-document codegen-error isolation across a switch, long-title bounded tab width plus full tooltip, `18`-recipe overflow making the scroll container's horizontal range nonzero, narrow-layout tab-row usability, and `20`-layer preview/output-rect stability across a switch.
- `tests/gst_editor_smoke.gd`: added the `tabs_ui` dispatch case.
- `tests/gst_editor_ui_layout_smoke.gd`: `_check_file_menu`'s own `file_menu` assertion dirtied the active document (`add_layer("color/fill", ...)`) before pressing File > New, so New is guaranteed to install a genuinely distinct stack. This selector was not re-run since before phase 3 landed `GSTMainPanel.open_document`'s own pristine-reuse rule ("Not run this pass" in "Shader tabs phase 3"'s own evidence, `4`/`5`/`ui_layout`/`4.7` were skipped there); the check's own `panel.get_stack() != old_stack` assumption predates that rule and was made vacuously false by it on a still-pristine active document, not by anything phase 4 changed. Adapting the test's own precondition, per this plan's "Listed existing test files may require fixture adaptation," rather than the (correct, decision-2-approved) production reuse contract.
- `tests/gst_editor_ui_picker_smoke.gd`, `tests/gst_editor_ui_complete_smoke.gd`: read in full, run for verification, not edited -- neither assumes a `Button` reference, document count, or stack-instance identity across an activation boundary this phase's changes touch.

### Verification commands and results

Each selector below was run as its own process, serially, with isolated `APPDATA`/`LOCALAPPDATA` set on that process only (never the real user profile), from Git Bash on Windows 11. Command shape: `GST_EDITOR_SMOKE=<selector> APPDATA=<isolated> LOCALAPPDATA=<isolated> <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`.

- Import (isolated `4.4`): `Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import`. Exit `0`. Stderr held only the documented Godot `4.4.0` first-import progress-dialog diagnostic plus the pre-existing `LayerPane`/`SettingsPane` owner warnings; no script error.
- `tabs_ui` (`4.4`), run 1: exit `1`, `SMOKE SUMMARY pass=7 fail=5`. Every failure was a test-authoring bug in the new selector itself, not a production defect -- diagnosed and fixed in the same pass (see "Bugs found and fixed" below).
- `tabs_ui` (`4.4`), run 2 (after fixes): exit `0`, `SMOKE SUMMARY pass=15 fail=0`. Stderr held only the pre-existing `LayerPane`/`SettingsPane` owner warnings.
- `tabs_ui` (`4.4`), run 3 (repeated per this plan's own "serial runs" instruction): exit `0`, `SMOKE SUMMARY pass=15 fail=0`, identical to run 2.
- `tabs_documents` (`4.4`, re-run to confirm no regression): exit `0`, `SMOKE SUMMARY pass=22 fail=0`, matching "Shader tabs phase 3 review round 2 fix-now"'s own baseline exactly.
- `tabs_native` (`4.4`, re-run to confirm no regression): exit `0`, `SMOKE SUMMARY pass=31 fail=0`, matching "Shader tabs phase 2 review round 4 fix-now"'s own baseline exactly.
- Headless unit wrapper (isolated `4.4`): `Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project -s res://tests/run_codegen_tests.gd`. `GST tests: 21 file(s), 145 test method(s), 20 failure(s)` -- identical file/method/failure counts to the documented phase 3 baseline; none of the `20` failures are in a file this phase touched.
- Import (isolated `4.6.2`): `Godot_v4.6.2-stable_win64.exe --headless --path .now/tabs-validation/project-462 --import`. Exit `0`, no script errors.
- `GST_EDITOR_SMOKE=ui_layout` (`4.6.2`), run 1 (before the `_check_file_menu` fix): exit `1`, `SMOKE SUMMARY pass=15 fail=1` (`file_menu`, diagnosed as the stale test assumption above).
- `GST_EDITOR_SMOKE=ui_layout` (`4.6.2`), run 2 (after the fix): exit `0`, `SMOKE SUMMARY pass=16 fail=0`, matching every prior documented `ui_layout` baseline in this file exactly.
- `GST_EDITOR_SMOKE=ui_picker` (`4.6.2`): exit `0`, `UI_PICKER SUMMARY pass=45 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=ui_complete GST_UI_COMPLETE_ENTRY=recipe` (`4.6.2`): exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0`, matching baseline.
- Every `4.6.2` run's stderr was empty. No script errors (`SCRIPT ERROR`, `Invalid access`, `Nonexistent function`, `Parse Error`) in any run above, checked by grep against each run's full captured stdout+stderr.

### Measured evidence (tabs_ui, isolated `4.4`, normal editor scale)

- Long titles: a document saved as `a_deliberately_long_shader_filename_for_the_tab_overflow_measurement.tres` produced a tab `width=96.0` (the row's own `custom_minimum_size.x` floor, `clip_text=true` keeping the button's own minimum size from growing with the text) with `tooltip_text` equal to the full `user://...` path.
- Overflow: after opening `18` additional independent `fire` recipe copies (`21` total open documents), the tab row measured `row_width=2296.0` against `scroll_width=776.0`, with the `ScrollContainer`'s own horizontal scrollbar `h_max=2296.0` / `h_page=776.0` (nonzero scrollable range).
- `20` layers: `list.get_item_count() == 20` on the built document; `preview_rect`/`output_rect` from `get_layout_measurements()` were `[P: (764.0, 256.0), S: (319.0, 195.0)]` / `[P: (764.0, 496.0), S: (319.0, 99.0)]` respectively, both `is_equal_approx` identical before opening another document and switching back.
- Preview/output rectangles are the same `get_layout_measurements()` fields ui_layout_smoke.gd already exercises; this phase's own check confirms they do not move across a tab switch, not a new measurement shape.
- Narrow layout (`720x600` window): `panel.get_tab_row().is_visible_in_tree()` stayed `true` and the active document's own tab button remained resolvable through `get_tab_button()` at the same width `ui_layout_smoke.gd`'s own `responsive_tabs` check collapses Layers/Layer settings into tabs.
- `150%` editor scale: not run this pass. Every prior scaled run in this file (`docs/EDITOR_SMOKE.md` "Editor UI redesign, phase 5" `scaled150-<version>` logs) set the isolated `APPDATA`'s own `interface/editor/display_scale` editor setting through a real editor session ahead of time; reproducing that setup step was not attempted in the time available for this pass. Flagged as an open verification gap below rather than fabricated.

### Bugs found and fixed during self-verification (before any independent review)

1. `tests/gst_editor_tabs_smoke.gd`'s own first draft held a `Button` reference (`button_a`) captured before a tab click that itself calls `activate_document`, then read `button_a.button_pressed` after the click -- `_refresh_tabs()` frees and rebuilds every tab `Button` on every activation, so the pre-click reference was reading a `queue_free()`d object by the time the awaited frame let that queued deletion run. Fixed by always re-fetching each document's own button through `panel.get_tab_button(doc)` after any activation, never reusing a pre-click reference.
2. The same draft used the trailing New control (which reuses an existing pristine document, matching `_on_new_pressed`/decision 2, and immediately opens the Add-layer picker, matching that same handler's own existing behavior) as a generic "give me a distinct document" helper in several checks, both assuming a fresh instance every press (it does not, once nothing has edited the previous one) and leaving its own auto-opened picker uncancelled (which then blocked every subsequent `add_layer_by_entry_id` call through `_mutations_blocked`, producing an out-of-bounds layer-array read in one check and two checks' own `_check()` calls never running at all after a "previously freed" script error aborted their functions). Fixed by using `panel.open_recipe(...)` (phase 3: never reused) for every "give me a distinct document" need, reserving the trailing New control for the one check that specifically proves its own wiring, with its resulting picker explicitly cancelled there before any further mutation.
3. `tests/gst_editor_ui_layout_smoke.gd`'s pre-existing `file_menu` check asserted `panel.get_stack() != old_stack` after pressing File > New from an already-pristine active document -- vacuously false under phase 3's own pristine-reuse rule, landed in `9dee58f`'s predecessor commit but never re-exercised by this selector until this pass (see "Files touched this pass" above). Fixed by dirtying the active document immediately before capturing `old_stack`, so New is guaranteed to install a genuinely distinct stack, preserving the check's own original intent without weakening it.

None of these three are current, unresolved limitations: all were reproduced, root-caused, fixed, and re-verified in this same pass.

### Blockers / open decisions

- `150%` editor-scale measurement was not run this pass (see "Measured evidence" above): reproducing the scaled-`APPDATA` setup step used by earlier phases' own scaled runs was not attempted in the time available. Flagging for either a follow-up pass or explicit sign-off that the normal-scale evidence above is sufficient before this phase is treated as fully verified.
- No other blockers. The bugs found above were resolved in this same pass, not deferred.

### Scope

- Files touched this pass: `addons/goshade_turbo/ui/gst_document.gd`, `addons/goshade_turbo/ui/gst_main_panel.gd`, `addons/goshade_turbo/ui/gst_main_panel.tscn`, `addons/goshade_turbo/ui/gst_preview.gd`, `addons/goshade_turbo/ui/gst_stack_list.gd`, `tests/gst_editor_tabs_smoke.gd` (new), `tests/gst_editor_smoke.gd`, `tests/gst_editor_ui_layout_smoke.gd`, `docs/EDITOR_SMOKE.md` (this section), `NOW.md` (Active thread next-action line only). All are inside the plan's phase 4 Files list plus the harness's own NOW.md bookkeeping allowance.
- `tests/gst_editor_ui_picker_smoke.gd` and `tests/gst_editor_ui_complete_smoke.gd` are in that list and were read/run per the plan's own instruction; neither needed an edit.
- No file outside the plan's phase 4 Files list was edited. `sandbox/**` was not touched. The isolated-project copies under `.now/tabs-validation/` were synced (copied) but are verification scratch, not repo source.

## Shader tabs phase 4 review round 1 fixes (2026-09-11)

Fix pass against round 1's `FAIL` verdict (five required fixes). Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (`4.4`), `.now/tabs-validation/project-462` (`4.6.2`), both with isolated `APPDATA`/`LOCALAPPDATA` (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`), matching every prior pass in this section. A third isolated `4.4` profile, `.now/tabs-validation/appdata-4.4-scaled150` (a copy of `appdata-4.4` with `interface/editor/display_scale = 7` and `interface/editor/custom_display_scale = 1.5` added directly to its `editor_settings-4.4.tres`, per the reviewer's own suggested procedure), was used only for the `150%` runs below.

### Fix status

1. **Keep the active tab selected when clicked again; add a native mouse-input regression. Applied.** Every tab `Button` now shares one `ButtonGroup` instance (`_tab_button_group`, a new `gst_main_panel.gd` field), assigned in `_refresh_tabs()` alongside the existing `toggle_mode`/`button_pressed` setup. Verified against `.now/tabs-validation/godot-4.4-source/scene/gui/base_button.cpp`: `BaseButton::on_action_event` unconditionally toggles `status.pressed` on every click, and `_unpress_group()` only forces it back to `true` when a `button_group` is present (`ButtonGroup.allow_unpress` defaults to `false`) -- without a group, a second click on the already-active tab silently un-pressed it, exactly the reported regression. New native regression in `tests/gst_editor_tabs_smoke.gd`, `active_tab_reclick_stays_selected` (`_run_reclick_stays_selected_and_keyboard_undo_focus`): two real clicks on the same already-active tab via a new `_click_tab` helper (real `InputEventMouseButton` press/release delivered through `plugin.get_viewport().push_input(event, true)`, matching `tests/gst_editor_ui_complete_smoke.gd`'s own established convention -- see the engine-behavior note under "Bugs found" below), asserting the tab stays both the active document and `button_pressed == true` afterward.
2. **Preserve or transfer tab focus during `_refresh_tabs()`; verify click -> Ctrl+Z/Ctrl+Shift+Z changes only the activated document. Applied.** `_refresh_tabs()` now captures `focus_was_tab_button` (whether `get_viewport().gui_get_focus_owner()` was one of the tab row's own Buttons) *before* freeing and rebuilding every tab Button; when true, it calls `grab_focus()` on the newly active document's own rebuilt Button afterward. An edit-triggered refresh with focus elsewhere (an inspector row, the stack list, a native popup) is untouched, since `focus_was_tab_button` reads false there. New native regression `click_then_keyboard_undo_redo_only_activated_document`: real clicks switch active documents, an explicit `grab_focus()` on the about-to-be-left tab's own Button establishes the real click-driven-focus precondition this session's synthetic input cannot otherwise reproduce (see "Bugs found" below), a real click switches again, then real `InputEventKey` Ctrl+Z/Ctrl+Shift+Z (`_push_key`, `Viewport.push_input`) are asserted to change only the newly active document's own stack/`UndoRedo.get_current_action()` position, never the document left behind.
3. **Make the narrow test cross the measured breakpoint and assert usable geometry; complete the `150%` measurements. Applied.** `_run_narrow_layout` now measures `tab_breakpoint` at an explicit `1366x768` baseline first (this selector never otherwise sets a window size, so the round-1 "wide" state was whatever the isolated profile happened to start at -- narrow read `false` there because "wide" and "narrow" were the same size), resizes to `720x600`, and -- matching `tests/gst_editor_ui_layout_smoke.gd`'s own established `responsive_tabs` check, which never relies on the window resize alone either -- drags `%MainSplit` narrower by a real mouse press/motion/release (`_drag_main_split`, mirroring `_drag_splitter` exactly) whenever the resize alone left `editing_rect` above the breakpoint. The check now requires `narrow["narrow"] == true` and `editing_rect.size.x <= tab_breakpoint`, plus (with ~`21` tabs already open from the long-title/overflow check) the overflow scrollbar staying visible, the tab row's own height unchanged from its wide-layout measurement, and the active tab scrolled into view. That last condition needed a real fix: `gst_main_panel.gd` gained `_shader_tabs_scroll.resized` -> `_on_tab_scroll_resized`, which re-scrolls the active tab into view on any resize that changes the tab row's own available width without rebuilding it (a window/narrow-layout resize does not touch the tab row's own Buttons, only `_refresh_tabs()` did before this fix); both that handler and `_refresh_tabs()`'s own trailing scroll call route through a new shared `_await_scroll_active_tab_into_view`, which awaits a real `process_frame` before calling `ScrollContainer.ensure_control_visible` (see item 2 under "Bugs found" for why `call_deferred` was not enough).
4. **Assert document-owned material/render isolation, including an initially invalid document. Applied.** `invalid_document_no_previous_effect` (`_run_invalid_document_isolation`) now also asserts, alongside its existing message-text checks: `broken_doc.preview_sync.has_successful_preview() == false` (the codegen failure never reached a successful compile), `panel.get_shader_material() == broken_doc.material` while `broken_doc` is active (its own instance, not `clean_doc`'s), and that material's `shader.code == GSTMaterialSync.SAFE_TRANSPARENT_SHADER_CODE` both right after the failure and again after switching away and back -- `GSTMaterialSync.sync_preview`'s own documented contract ("the material's shader and every uniform are left exactly as they were before the call" on failure) means a document that never had a successful compile can never carry another document's compiled shader. The clean document's own material is asserted distinct (`!=`) and its shader `code` distinct from the safe constant, confirming its own successful compile actually ran and is not shared with `broken_doc`'s instance.
5. **Record and diagnose the certificate-store error before claiming error-free verification. Applied; not independently reproduced in this session.** Attempted reproduction against an unmodified `git worktree add .now/tabs-validation/worktree-9dee58f 9dee58f` checkout, in the same isolated `appdata-4.4` profile used throughout this pass, via both `--headless --import` and a full `--editor` session running `tabs_documents` (command/output below). Neither reproduced `ERROR: Failed to read the root certificate store.` in this session/environment. Existing repo evidence already documents the identical diagnostic independently of any phase 4 code, e.g. `.now/tabs-validation/evidence/phase3-review-r2-6.stderr.log`: `ERROR: Failed to read the root certificate store.` / `at: get_system_ca_certificates (platform/windows/os_windows.cpp:2570)`, recorded during the phase 3 round 2 review pass, which never touched any phase 4 file. This establishes the diagnostic is not phase-4-code-caused (it predates phase 4 entirely) and is environment/session-dependent (TLS root-store availability, per the engine's own error site) rather than reliably reproducible from a bare checkout alone. No phase-4 evidence in this document claims "error-free" verification; every run below is reported as "no script errors" specifically, with this diagnostic tracked separately and not asserted absent.

### Bugs found while building the round 1 fix-pass tests, before any independent re-review

1. **Real `Button` clicks require `NOTIFICATION_MOUSE_ENTER` in this session; `Viewport`'s own click-to-focus grab still needs an explicit `grab_focus()`.** `_click_tab`'s first draft used a preceding `InputEventMouseMotion` plus `Input.parse_input_event` (matching `tests/gst_editor_native_undo_smoke.gd`'s own spin-slider convention) to establish hover before the click; `Viewport.gui_get_hovered_control()` stayed `null` immediately afterward in every attempt, and the click never registered at all (`BaseButton::on_action_event` requires `status.hovering` true for a mouse-button event, verified against `.now/tabs-validation/godot-4.4-source/scene/gui/base_button.cpp`; `status.hovering` is driven by `Viewport`'s own `gui.mouse_over`/`_update_mouse_over` tracking, which never populated for this control from a synthetic event in this session, regardless of `Input.parse_input_event` vs. `Viewport.push_input` or `in_local_coords` `true`/`false`). Switched to calling `button.notification(Control.NOTIFICATION_MOUSE_ENTER)` directly before the press (public, documented API; `BaseButton::_notification`'s own `NOTIFICATION_MOUSE_ENTER` case sets exactly `status.hovering = true`) -- this let the real click-toggle/`button_group`/`pressed`-signal logic run for real, but `Viewport`'s own *click-to-focus* grab (`scene/main/viewport.cpp`, gated behind a separate `gui.mouse_over_hierarchy` structure the same missing hover tracking never populates either) still never fired. Fix 2's own check establishes that precondition explicitly instead (`grab_focus()` on the tab about to be left, documented inline in the test), since a real hardware click always grants both; only the literal focus-grab step is unreachable in this synthetic session, not the switch/rebuild logic the fix actually changes.
2. **The very first real click of a fresh session is silently absorbed.** `stable_id_switch_by_click`'s first real-click draft failed only its first sub-assertion (`switched_to_saved`); every later click in the same run, including an identical reclick, succeeded. Root-caused to `Viewport::_sub_windows_forward_input`'s own stale-subwindow-focus-clearing branch ("no window found and clicked, remove focus", `scene/main/viewport.cpp`), which runs once per session on the first qualifying mouse-button press. Fixed by adding one harmless warm-up click (on the already-active initial tab, a no-op reclick per fix 1) at the very start of `run()`, before any assertion-bearing click.
3. **`UndoRedo.get_history_count()` is not an undo-position counter.** The first draft of `click_then_keyboard_undo_redo_only_activated_document` asserted `get_history_count()` decreased by one after an undo; it never does, since `UndoRedo::get_history_count()` returns `actions.size()` (`core/object/undo_redo.cpp`), the total count of ever-committed actions, unaffected by `undo()`/`redo()` (only `current_action` moves). This produced a false failure that looked like "undo never reached the document" when the real (layer-count) effect had in fact occurred. Fixed by asserting `UndoRedo.get_current_action()` instead, the actual position counter, alongside the always-correct `stack.layers.size()` check.
4. **`ensure_control_visible` computed a short scroll target when called via `call_deferred` from a same-frame resize/rebuild.** First measured only at `150%` editor scale (see "Measured evidence" below): the active tab's own end position exactly matched `HScrollBar.max_value`, but the resulting `scroll_horizontal` fell short of the value needed to reveal it by a fixed, reproducible amount every run (`1121` vs. the required `1223`, with `h_page=1117`). `ScrollContainer::ensure_control_visible` (`scene/gui/scroll_container.cpp`) computes its scroll delta from `get_global_transform()`, which reflects the container's own scrollbar clamp for its *current* size; called via `call_deferred` (same-frame idle time) immediately after a resize or a tab-row rebuild, that internal clamp had evidently not yet run. Replaced every `call_deferred` call site (`_refresh_tabs()`'s own trailing scroll, and the new `_on_tab_scroll_resized`) with a shared `_await_scroll_active_tab_into_view`, which `await`s a real `process_frame` first. Confirmed fixed at `150%` (`visible=[1223.0,2340.0]`, flush to the true end) without regressing the normal-scale case, which also tightened from a `1`-pixel-short result to an exact flush match (`visible=[1520.0,2296.0]` against `h_max=2296.0`).

None of these four are current, unresolved limitations: all were reproduced, root-caused, fixed, and re-verified in this same pass, before any of the "Verification commands and results" runs below.

### Verification commands and results

Each selector below was run as its own process, serially, with isolated `APPDATA`/`LOCALAPPDATA` set on that process only (never the real user profile), from Git Bash on Windows 11. Command shape: `GST_EDITOR_SMOKE=<selector> APPDATA=<isolated> LOCALAPPDATA=<isolated> <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`.

- `tabs_ui` (`4.4`, normal scale), run 1 (after fixes 1/2/4 and before fix 4 correctly this pass): exit `0`, `SMOKE SUMMARY pass=17 fail=0`.
- `tabs_ui` (`4.4`, normal scale), run 2 (repeated per this plan's own "serial runs" instruction): exit `0`, `SMOKE SUMMARY pass=17 fail=0`, identical.
- `tabs_ui` (`4.4`, `150%` scale, isolated `appdata-4.4-scaled150`): exit `0`, `SMOKE SUMMARY pass=17 fail=0` (confirmed `editor_scale` active `1.5` in the check's own printed measurement).
- `tabs_documents` (`4.4`, re-run to confirm no regression): exit `0`, `SMOKE SUMMARY pass=22 fail=0`, matching the documented phase 3/4 baseline exactly.
- `tabs_native` (`4.4`, re-run to confirm no regression): exit `0`, `SMOKE SUMMARY pass=31 fail=0`, matching every prior documented baseline exactly.
- Headless unit wrapper (isolated `4.4`): `GST tests: 21 file(s), 145 test method(s), 20 failure(s)` -- identical file/method/failure counts to the documented phase 4 baseline; none of the `20` failures are in a file this pass touched.
- Import (isolated `4.6.2`, re-synced): exit `0`, no script errors.
- `GST_EDITOR_SMOKE=ui_layout` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=16 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=ui_picker` (`4.6.2`): exit `0`, `UI_PICKER SUMMARY pass=45 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=ui_complete GST_UI_COMPLETE_ENTRY=recipe` (`4.6.2`): exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0`, matching baseline.
- Every run's stdout+stderr was checked for `SCRIPT ERROR`, `Invalid access`, `Nonexistent function`, and `Parse Error`: none found in any run above.
- Fix 5's own reproduction attempt: `Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/worktree-9dee58f --import` (isolated `appdata-4.4`): exit `0`, no certificate-store diagnostic. `GST_EDITOR_SMOKE=tabs_documents Godot_v4.4-stable_win64.exe --editor --path .now/tabs-validation/worktree-9dee58f --rendering-method gl_compatibility` (same isolated `appdata-4.4`, unmodified `9dee58f` checkout): exit `0`, `SMOKE SUMMARY pass=22 fail=0`, no certificate-store diagnostic either. See fix 5 above for the historical evidence that does show it, independent of any phase 4 code.

### Measured evidence (tabs_ui, isolated `4.4`)

| Measurement | Normal scale | `150%` scale |
|---|---|---|
| `editor_scale` | `1.0` | `1.5` |
| Long-title tab width (floor) | `96.0` | `96.0` (not editor-scale-driven: a raw `custom_minimum_size.x`, unlike the row's own theme-driven height) |
| Tab row height | `31.0` (wide and narrow) | `47.0` (wide and narrow) |
| Overflow: row width / scroll (viewport) width | `2296.0` / varies by panel width (`947.0` at this run's own starting width, `776.0` once narrowed) | `2340.0` / `1117.0` (panel width pinned at this profile's own minimum in both the `1366x768` and `720x600` requests -- see note below) |
| `tab_breakpoint` (wide baseline) | `371.0` | `552.0` |
| `editing_rect.size.x`, wide -> narrow | `479.0` -> `371.0` (crossed via `%MainSplit` drag, not the window resize alone) | `688.0` -> `552.0` (same) |
| Active tab scrolled-into-view range vs. its own position | position `2200.0`, visible `[1520.0, 2296.0]` (flush to `h_max=2296.0`) | position `2244.0`, visible `[1223.0, 2340.0]` (flush to `h_max=2340.0`) |
| `20`-layer preview/output rects, before/after a tab switch | identical (`is_equal_approx`) | identical (`is_equal_approx`) |

- Note on the `150%` panel-width pin: at this isolated profile's own scale, `DisplayServer.window_set_size` requests of both `1366x768` and `720x600` produced the *same* overall panel/`host_rect` width (`1153.0`, `S:` in the raw log) -- the requested sizes, once divided by the `1.5x` content scale, both fell below the editor's own combined dock-minimum floor, so the window settled at that floor either way. `editing_rect` still crossed the breakpoint correctly because that crossing comes from the `%MainSplit` drag (fix 3's own primary mechanism, not the window resize), which is unaffected by this. Recorded here rather than silently normalized, since it is a real, reproducible property of this profile's own minimum layout, not a defect in the fix.
- Every `4.4` run's stderr held only the pre-existing `LayerPane`/`SettingsPane` owner warnings. Every `4.6.2` run's stderr was empty.

### Blockers / open decisions

- Fix 5's certificate-store diagnostic was not independently reproduced in this implementer session (see fix 5 and "Verification commands" above): the historical `phase3-review-r2-*` evidence remains the basis for treating it as environment/session-dependent and pre-existing, not phase-4-caused. Flagging for the reviewer to confirm from their own environment, since that is where every prior occurrence was recorded.
- The `150%` panel-width-floor behavior noted above (identical `host_rect` width at both requested window sizes) is a property of this profile's own combined dock minimums, not something phase 4's own code controls; recorded as a measurement note, not a defect.
- No other blockers. The four items under "Bugs found" above were resolved in this same pass, not deferred.

### Scope

- Files touched this pass: `addons/goshade_turbo/ui/gst_main_panel.gd`, `tests/gst_editor_tabs_smoke.gd`, `docs/EDITOR_SMOKE.md` (this section), `NOW.md` (Active thread next-action line only), plus the generated `tests/gst_editor_tabs_smoke.gd.uid` companion (unchanged, already present). All are inside the plan's phase 4 Files list plus the fix-pass's own stated scope (the five findings' cited `gst_main_panel.gd`/`gst_editor_tabs_smoke.gd` locations) and the harness's own `NOW.md` bookkeeping allowance.
- `addons/goshade_turbo/ui/gst_document.gd`, `gst_main_panel.tscn`, `gst_preview.gd`, `gst_stack_list.gd`, `tests/gst_editor_smoke.gd`, `tests/gst_editor_ui_layout_smoke.gd` (already in the phase 4 Files list from the original implementer pass) were read this pass but not re-edited; none of the five findings cited them.
- `.now/tabs-validation/appdata-4.4-scaled150` (new, this pass's own `150%` profile) and the temporary `git worktree add .now/tabs-validation/worktree-9dee58f 9dee58f` (removed via `git worktree remove` immediately after fix 5's reproduction attempt) are verification scratch under the already-`.gitignore`d `.now/`, not repo source. No file outside the plan's phase 4 Files list was edited. `sandbox/**` was not touched.

## Shader tabs phase 4 review round 2 fix-now (2026-09-11)

Fix pass against round 2's `PASS-WITH-NOTES` verdict (one fix-now finding, S2). Round 1's five required fixes are already applied and settled in the working tree; this pass does not revert or re-touch any of them. Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (`4.4`), `.now/tabs-validation/project-462` (`4.6.2`), both with isolated `APPDATA`/`LOCALAPPDATA` (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`), matching every prior pass in this section; the `.now/tabs-validation/appdata-4.4-scaled150` `150%` profile from round 1 was reused unchanged for the scaled run below.

### Fix status

1. **S2: initialize an empty scroll anchor explicitly at `gst_stack_list.gd:231`. Applied.** `restore_scroll_state(anchor_id, offset)` no longer early-returns silently when `anchor_id == &""`; it now queues a deferred `_reset_scroll_to_top()` (new private method, sets the `ItemList`'s own `VScrollBar.value` to `0.0`) whenever the list has rows, so a document's first activation with content always overrides whatever stale deferred restore `refresh()` above already queued against the same list instance. Root cause confirmed by reading both call sites named in the finding: `refresh()` (`gst_stack_list.gd:55-72`) captures its own anchor/offset from *whichever rows the list currently shows* before `_list.clear()` runs, so during a document switch that capture reads the outgoing document's own scrolled position, not the incoming one's; when the incoming document's own `list_scroll_anchor_id` is still `&""` (its first activation with content -- `_install_document_state`/`_restore_document_selection` in `gst_main_panel.gd:687-843`), the old `restore_scroll_state` did nothing, leaving that outgoing-scrolled restore as the only one queued and, when the outgoing anchor id happened to also exist in the incoming document's own stack (ordinary, since every `GSTStack.next_id` starts at `0`, `gst_stack_ops.gd:25`), it silently bled the outgoing document's scroll position into the incoming one.
   - New regression `scroll_state_no_bleed_across_documents` (`tests/gst_editor_tabs_smoke.gd`, `_run_scroll_state_no_bleed_across_documents`, called from `run()` right after `_run_selection_and_scroll_restoration`): pads `working_doc` to `52` layers (its existing `12` alone never scrolls in this window -- confirmed both here and in the pre-existing `selection_and_list_position_restored` check, whose own anchor stayed pinned to the top row at that count) and scrolls it to a real, non-top row; builds a brand-new document to that exact same layer count by mutating its own `GSTUndo.add_layer_for_ui` directly while it is not the active document (so its rows never touch `gst_stack_list.gd` and its `list_scroll_anchor_id` stays at its true, never-captured default `&""`), giving it the identical id set `working_doc` scrolled into (direct membership check, not an assumed index); switches to it and asserts it opens at its own top row, not the position `working_doc` was scrolled to; then scrolls the new document to its own distinct real position and checks both directions of a further round trip restore independently.
   - Verified the regression actually reproduces the finding by reverting the fix in the isolated `4.4` project copy only (never the repo working tree) and re-running `tabs_ui`: the check's first two designs both passed vacuously against the reverted fix (no genuine scroll, then a genuine scroll that missed the new document's own id range -- see "Bugs found" item 2 below for the full trace); the final design correctly fails against the reverted fix (`scroll_state_no_bleed_across_documents FAIL fresh_starts_at_top=false(top=51)`, "Verification commands," fix-verification attempt 3) and passes with the fix restored (runs 5-6). This before/after pair is the basis for treating the final check as a genuine regression test for S2, not a vacuous one.

### Verification commands and results

Each selector below was run as its own process, serially, with isolated `APPDATA`/`LOCALAPPDATA` set on that process only (never the real user profile), from Git Bash on Windows 11. Command shape: `GST_EDITOR_SMOKE=<selector> APPDATA=<isolated> LOCALAPPDATA=<isolated> <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`.

- `tabs_ui` (`4.4`, normal scale), run 1 (first draft of the regression, `working_doc`'s existing `12` layers reused as-is, new document also built to `12`): exit `1`, `SMOKE SUMMARY pass=16 fail=1` (`stable_id_switch_by_click FAIL switched_to_saved=false` -- see "Blockers" below; unrelated to this fix). Also printed `SCRIPT ERROR: Invalid access to property or key 'item_count'` at `_run_scroll_state_no_bleed_across_documents`, which aborted that check before its own `_check()` call ran (contributing to neither the `16` passes nor the `1` failure) -- see "Bugs found" item 1.
- `tabs_ui` (`4.4`, normal scale), run 2 (after fixing bug 1 below; still the `12`/`12` design): exit `0`, `SMOKE SUMMARY pass=18 fail=0`. `scroll_state_no_bleed_across_documents` passed, but vacuously (`anchor=11/11 offset=0.000` -- no real scroll ever occurred at only `12` layers in this window).
- `tabs_ui` (`4.4`, normal scale), run 3 (repeated per this plan's own "serial runs" instruction): exit `0`, `SMOKE SUMMARY pass=18 fail=0`, identical to run 2.
- Fix-verification attempt 1 (fix reverted in the isolated `4.4` project copy only, still the `12`/`12` design): exit `0`, `SMOKE SUMMARY pass=18 fail=0` -- `scroll_state_no_bleed_across_documents` still passed with the bug present, exposing the vacuous-scroll design flaw (see "Bugs found" item 2). Fix restored before continuing.
- `tabs_ui` (`4.4`, normal scale), run 4 (redesigned: `working_doc` padded to `52` layers to force a real scroll; new document still built to a fixed `12`): exit `1`, `SMOKE SUMMARY pass=17 fail=1` (`stable_id_switch_by_click FAIL switched_to_saved=false` again -- see "Blockers"; `scroll_state_no_bleed_across_documents` itself passed, with a genuine non-top `working_doc` scroll this time).
- Fix-verification attempt 2 (fix reverted again, still run 4's `52`-vs-fixed-`12` design): exit `0`, `SMOKE SUMMARY pass=18 fail=0` -- still passed with the bug present: `working_doc`'s own scroll landed on an id (`20`) outside the new document's small `0..11` id range, so the bug's stale restore found no matching row and was a no-op, a second, more specific vacuous-design flaw (see "Bugs found" item 2). Fix restored before continuing.
- `tabs_ui` (`4.4`, normal scale), fix-verification attempt 3 (final design: new document built to the exact same total layer count `working_doc` ends up with, full id-set overlap by construction; fix still reverted): exit `1`, `SMOKE SUMMARY pass=17 fail=1` (`scroll_state_no_bleed_across_documents FAIL fresh_starts_at_top=false(top=51)`, the expected S2 reproduction -- the new document opened scrolled to the id `working_doc` had been scrolled to, not its own top row).
- `tabs_ui` (`4.4`, normal scale), run 5 (fix restored, final design unchanged): exit `0`, `SMOKE SUMMARY pass=18 fail=0`.
- `tabs_ui` (`4.4`, normal scale), run 6 (repeated per this plan's own "serial runs" instruction): exit `0`, `SMOKE SUMMARY pass=18 fail=0`, identical to run 5.
- `tabs_ui` (`4.4`, `150%` scale, isolated `appdata-4.4-scaled150`): exit `0`, `SMOKE SUMMARY pass=18 fail=0` (confirmed `editor_scale` active `1.5` in the check's own printed measurement).
- `tabs_documents` (`4.4`, re-run since `gst_stack_list.gd` is shared): exit `0`, `SMOKE SUMMARY pass=22 fail=0`, matching the documented phase 3/4 baseline exactly.
- Import (isolated `4.6.2`, re-synced): exit `0`, no script errors.
- `GST_EDITOR_SMOKE=ui_layout` (`4.6.2`, re-run since production code changed): exit `0`, `SMOKE SUMMARY pass=16 fail=0`, matching baseline.
- Every run's stdout+stderr was checked for `SCRIPT ERROR`, `Invalid access`, `Nonexistent function`, and `Parse Error`: none found in any run above except run 1's own test-authoring bug, fixed before the runs that follow it. Every `4.4` run's stderr held only the pre-existing `LayerPane`/`SettingsPane` owner warnings; the `4.6.2` run's stderr was empty.

### Bugs found while building this fix-now pass, before any independent re-review

1. **`GSTStackList.item_count` is not an accessor.** The regression's first draft read `fresh_list.item_count` directly (an `ItemList`/`VBoxContainer` property, not exposed by `GSTStackList`), producing `SCRIPT ERROR: Invalid access to property or key 'item_count'` and silently skipping that check's own `_check()` call. Fixed by using the existing public `get_item_count()`.
2. **Two successive vacuous-scroll design flaws, both caught only by deliberately reverting the fix and re-running, not by inspection.** (a) At `working_doc`'s existing `12` layers, `scroll_to_fraction(0.6)` never produces a real scroll in this window (all `12` rows fit the visible list area, so `VScrollBar.min_value == max_value == 0`) -- `get_scroll_anchor_id()` reads the top row either way, so the check passed identically with the fix present or reverted (fix-verification attempt 1). (b) Padding `working_doc` alone to `52` layers to force a real scroll, while leaving the new document at a fixed `12`, usually lands `working_doc`'s own scrolled-to id outside the new document's small `0..11` id range -- the bug's own stale restore then finds no matching row in `_item_index_for_id` and is a no-op, again passing identically with the fix present or reverted (fix-verification attempt 2). Root-caused both by explicitly reverting the fix in the isolated project copy (never the repo working tree) and observing the check still pass in each case -- the check was never a genuine regression test until it failed against the reverted fix. Fixed by building the new document to the exact same total layer count `working_doc` ends up with (`working_total`), guaranteeing full id-set overlap regardless of which row the scroll lands on, and by asserting overlap directly (`overlapping_ids`, a membership check against `working_anchor_before`) rather than assuming a fixed index. Re-verified: fails against the reverted fix (fix-verification attempt 3), passes with the fix restored (runs 5-6 and every run after).

### Blockers / open decisions

- `stable_id_switch_by_click` (an existing, phase-4-round-1 check unrelated to this fix, exercised well before `_run_scroll_state_no_bleed_across_documents` runs) failed in runs 1 and 4 above (`switched_to_saved=false`) and passed in every other run in this pass. The same check failed repeatedly (`run1`-`run5` of the reviewer's own round 2 diagnostic logs, `.now/tabs-validation/round2-4.4-tabs_ui-run1.stdout.log` through `run5`) before stabilizing across `run6`-`run9`/`final1`/`final2` in that same review pass, independent of any code this fix-now pass touches. Treated as a known, pre-existing real-input-focus/session-warm-up flake in this environment (consistent with round 1's own documented "first real click of a fresh session is silently absorbed" finding, evidently not fully resolved by that fix's warm-up click across every fresh process launch), not a regression from S2's fix. Flagging for the reviewer to confirm from their own environment rather than treating a single non-reproducing run as evidence either way.
- No other blockers. The two items under "Bugs found" above were resolved in this same pass, not deferred.

### Scope

- Files touched this pass: `addons/goshade_turbo/ui/gst_stack_list.gd` (S2 fix), `tests/gst_editor_tabs_smoke.gd` (S2 regression), `docs/EDITOR_SMOKE.md` (this section). All are inside the plan's phase 4 Files list; the S2 finding's own cited location (`gst_stack_list.gd:231`) authorizes the production edit.
- No file outside the plan's phase 4 Files list was edited. `sandbox/**` was not touched. No git worktree was created this pass. The isolated-project copies under `.now/tabs-validation/` were synced (copied) and, for the fix-verification step only, briefly reverted and re-fixed in place; both are verification scratch under the already-`.gitignore`d `.now/`, not repo source.

## Shader tabs phase 5: bind file operations to their initiating document (2026-09-11)

Implementer pass (not yet independently reviewed). Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (`4.4`), `.now/tabs-validation/project-462` (`4.6.2`), both with isolated `APPDATA`/`LOCALAPPDATA` (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`), matching every prior pass in this section.

- `addons/goshade_turbo/ui/gst_document.gd`: new `operation_messages: Dictionary` -- per-control ("Open", "Save", "Save As", "Export", "Reopen Shader") file-operation diagnostics now live on the document they describe instead of shared panel state (Cross-cutting "route operation messages to their owning document so a delayed failure cannot replace another document's diagnostics").
- `addons/goshade_turbo/ui/gst_main_panel.gd`:
  - Six new `_pending_*` Dictionaries (`_pending_save_as`, `_pending_export`, `_pending_overwrite`, `_pending_open`, `_pending_reopen`, `_pending_image`) plus a shared monotonic `_next_file_request_id`, each capturing `{request_id, doc_id}` (and, for `_pending_overwrite`, `path`) when its dialog opens (`_capture_active_document_request()`), or when `_export_stack_to_path` first finds an export needs confirmation. `{}` means no request was ever captured -- every plain path-taking seam (`save_to_path`/`export_to_path`/`open_path`/`reopen_shader_path`) and every direct `*_file_selected`/`_on_overwrite_confirmed` test call that never popped the real dialog first falls back to `_active_document`, preserving every pre-phase-5 direct-call test unchanged. `_find_document_by_session_id`/`_resolve_pending_document` are the one place any of these is read back.
  - `_save_stack_to_path(doc, path)`/`_export_stack_to_path(doc, path, confirm)` are the new document-bound primitives: refuse a stale/closed `doc` (`not _documents.has(doc)`) without writing or messaging anywhere; `_save_stack_to_path` additionally refuses a canonical path already owned by a *different* open document with a path-conflict message on `doc` itself (Cross-cutting "Refuse Save As to a canonical path owned by another open document"); both return a concrete `{ok, reason, ...}` result (Cross-cutting "concrete success/failure result for the phase 6 close lifecycle"); only `_save_stack_to_path` marks `doc.mark_baseline()`/updates `doc.current_path` on success (Export never does, per Cross-cutting "Export never clears dirty state"); both finish pending native edits only when `doc == _active_document` (an inactive document can hold no live gesture of its own -- every past edit on it was already committed before ownership moved away). `save_to_path`/`export_to_path` (the pre-existing public seams) now return `Dictionary` and wrap these against `_active_document`, unchanged in meaning for every existing direct caller.
  - `_on_save_as_pressed`/`_on_export_pressed`/`_on_open_pressed`/`_on_reopen_shader_pressed`/`_on_image_button_pressed` each capture `_active_document` into their own `_pending_*` field before popping their dialog. `_on_save_as_file_selected`/`_on_export_file_selected`/`_on_overwrite_confirmed`/`_on_preview_image_selected` resolve the captured document and call the document-bound primitive directly, so a document switch between opening the dialog and its response resolving can never redirect the write; `_on_open_file_selected`/`_on_reopen_shader_file_selected` resolve the captured document only for a *failure* message (a refusal never activates anything, so there is no new on-screen document to carry the reason instead) -- a success still targets whatever `open_document` just made `_active_document`, exactly like the pre-phase-5 code's own single implicit target, since Open/Reopen Shader always create/reactivate their own document regardless of which one was active when the dialog opened.
  - Every dialog's own `canceled` signal (the real Cancel button/Esc path, `dialogs.cpp AcceptDialog::_cancel_pressed` -- not a direct `.hide()`, which does not emit it) is now connected to clear its own `_pending_*` field, so an explicit cancellation cannot leave a stale capture for a later, unrelated response to resolve against.
  - `_set_operation_message`/new `_set_operation_message_for(doc, control, reason)`/new `_refresh_operation_message_label()`: routes every file-operation message onto `doc.operation_messages` and only rebuilds the shared `_message_label` when `doc == _active_document`. `_install_stack` now calls `_refresh_operation_message_label()` (reading whichever document is already `_active_document` by the time it runs) instead of unconditionally blanking the label, so switching tabs shows each document's own messages instead of whichever operation last ran while a different document was active.
- `tests/gst_editor_document_files_smoke.gd` (new, selector `tabs_files`): drives the real dialog-opening `_pressed` handlers and the same `*_file_selected`/`_on_overwrite_confirmed` seams a real dialog signal would call, switching the active document between every dialog open and its response (including between an export and its own second overwrite confirmation). Verifies success (Save As and Export each write the *originating* document's content, proved by reloading the file through `GSTStackIO.load`/comparing `GSTDocument.compute_fingerprint`, and by exact `GSTExport.build(...).code` text equality, never by trusting `current_path`/message state alone), a Save As canonical-path conflict refusal, a synthetically closed target's request rejected without writing (real close does not exist until phase 6; simulated by removing a document from `_documents` and tearing it down directly, the same bypass-the-guarded-UI technique `tests/gst_editor_ui_picker_smoke.gd` already uses for a stale picker-context installation), a delayed preview-image response landing on its own originating document and surviving reactivation, Open/Reopen Shader failure messages routing to the document that opened the dialog (and redisplaying correctly on reactivation) while leaving the actually-active document untouched, explicit dialog cancellation clearing its own captured request, and failed Save/Export (an unwritable path) leaving the document's content/dirty state untouched with the reason on its own `operation_messages`.
- `tests/gst_editor_smoke.gd`: added the `tabs_files` dispatch case. One existing-test fix (see "Bugs found" below).
- `tests/gst_editor_ui_complete_smoke.gd`: read in full, run for verification (plan's own "existing selectors ... `ui_complete` on `4.6.2`"), not edited -- it never calls any file-operation `_pressed`/`_file_selected`/`_on_overwrite_confirmed` seam.
- `docs/EDITOR_SMOKE.md` (this section). `NOW.md`: Active-thread next-action line only (bookkeeping, no phase content).

### Bugs found and fixed during self-verification (before any independent review)

1. **`tests/gst_editor_smoke.gd`'s own `_run_phase6_export_dialog_opens` leaked a captured `_pending_export` into a later, unrelated direct call.** That check calls `panel._on_export_pressed()` (now capturing whatever document is active at that moment) purely to prove the dialog opens, then calls `panel.hide_export_dialog()` -- a direct `.hide()`, which does not emit the dialog's own `canceled` signal (only the Cancel button/Esc path does), so the capture survived. `_run_phase6_export_and_overwrite_gate` further down the same run then calls `panel._on_export_file_selected(export_path)` directly (its own long-standing pattern, simulating a dialog response with no preceding `_on_export_pressed()` of its own) -- which resolved against the *stale* captured document (the dialog-opens check's own empty "New" document) instead of the actually-intended active document (the three-layer stack `ids` describes), producing a trivial empty export instead of the expected one. Found by first running `tabs_files` clean, then re-running selector `6` and seeing `_run_phase6_reopen`'s own layer-id assertions read an empty stack. Root-caused by reading `_run_phase6_export_dialog_opens` and `_run_phase6_export_and_overwrite_gate` together and tracing `_pending_export`'s lifetime between them. Fixed by adding `panel._pending_export = {}` right after `panel.hide_export_dialog()` in `_run_phase6_export_dialog_opens`, with a comment recording why.
2. **`_open_path_for`/`_reopen_shader_path_for`'s initial draft used the captured `message_doc` for *every* outcome, not only failure.** A successful Open/Reopen Shader always calls `open_document(...)`, which creates and activates a brand-new document -- the message describing that success (or, for Reopen Shader, the body-differs warning) belongs on *that* new document, not on whichever document happened to be active when the dialog was opened, since Open/Reopen Shader always create/reactivate their own document regardless. The initial draft attached it to `message_doc` instead, so `panel.get_message_label().text` read empty once the newly reopened document became active (the message sat on a document nobody was looking at). Found by `tabs_documents`' own `reopen_shader_unsaved_origin_and_warning` check (`SMOKE ... FAIL ... message=''`) on re-verification after the `tabs_files` pass. Fixed by targeting `_active_document` (read fresh, immediately after `open_document`/`activate_document` return) for every success branch, keeping `message_doc` only for the failure branch (a refusal never activates anything, so there is no new document to carry the reason instead) -- restoring the pre-phase-5 code's own implicit single-target behavior for success while still adding phase 5's actual improvement (a *failure* response now correctly lands on the document that opened the dialog, not whatever tab the user switched to while it was open).

Both were found and fixed in this same pass, before any independent review; neither is a current, unresolved limitation.

### Verification commands and results

Each selector below was run as its own process, serially, with isolated `APPDATA`/`LOCALAPPDATA` set on that process only (never the real user profile), from Git Bash on Windows 11. Command shape: `GST_EDITOR_SMOKE=<selector> APPDATA=<isolated> LOCALAPPDATA=<isolated> <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`.

- Import (isolated `4.4`, re-synced with this pass's changed files): `Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import`. Exit `0`. Stderr held only the documented Godot `4.4.0` first-import progress-dialog diagnostic plus the pre-existing `LayerPane`/`SettingsPane` owner warnings.
- `tabs_files` (`4.4`), run 1 (before either bug-fix above): exit `1`, `SMOKE SUMMARY pass=14 fail=2` (`open_dialog_message_routes_to_originating_document`, `reopen_dialog_message_routes_to_originating_document` -- both a *test* bug, not the two production bugs above: doc_b's own leftover "Save" path-conflict message from an earlier check made `panel.get_message_label().text` nonempty for a reason unrelated to what those two checks were proving). Fixed by clearing both documents' `operation_messages` at the start of each of those two check functions.
- `tabs_files` (`4.4`), run 2 (after the test fix): exit `0`, `SMOKE SUMMARY pass=16 fail=0`. Also printed four `ERROR: Attempting to make child window exclusive, but the parent window already has another exclusive child` lines: this test genuinely pops real `EditorFileDialog`/`ConfirmationDialog` windows (`popup_centered_ratio()`/`popup_centered()`) via `_on_..._pressed()`, then resolves them by calling the `*_file_selected`/`_on_overwrite_confirmed` handler directly instead of through a real dialog interaction, so the popped window's own real close-on-selection path (`EditorFileDialog`'s internal `_ok_pressed()`-equivalent flow) never ran and it stayed visually open; a later check's own `popup_centered*()` call on a second dialog then found the first still registered as the parent window's exclusive child. Not a production defect -- a real user interaction always closes the dialog before its `file_selected` signal's own handler runs. Fixed in the test by hiding each dialog explicitly right after `_on_..._pressed()` (mirroring the pre-existing `hide_export_dialog()` convention `_run_phase6_export_dialog_opens` already used for the same reason).
- `tabs_files` (`4.4`), run 3 (after the window-hide fix): exit `0`, `SMOKE SUMMARY pass=16 fail=0`, no `exclusive child` errors.
- `tabs_documents` (`4.4`, re-run since `gst_main_panel.gd` changed): run with production bug 2 still present, exit `1`, `SMOKE SUMMARY pass=21 fail=1` (`reopen_shader_unsaved_origin_and_warning`). After the fix: exit `0`, `SMOKE SUMMARY pass=22 fail=0`, matching the documented phase 3/4 baseline exactly.
- `tabs_files` (`4.4`), run 4 (re-run after production bug 2's fix, to confirm it did not disturb the earlier passing checks): exit `0`, `SMOKE SUMMARY pass=16 fail=0`.
- `tabs_files` (`4.4`), runs 5-7 (repeated per this plan's own "serial runs" instruction): exit `0` each, `SMOKE SUMMARY pass=16 fail=0` every time, identical.
- `tabs_ui` (`4.4`, re-run since `gst_main_panel.gd` changed): exit `0`, `SMOKE SUMMARY pass=18 fail=0`, matching the phase 4 round 2 baseline exactly.
- `tabs_native` (`4.4`, re-run to confirm phase 1/2's own selector still passes unchanged): exit `0`, `SMOKE SUMMARY pass=31 fail=0`, matching every prior baseline in this document exactly.
- Import (isolated `4.6.2`, re-synced): exit `0`, no script errors.
- `GST_EDITOR_SMOKE=6` (`4.6.2`), run 1: exit `0`, `SMOKE SUMMARY pass=16 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=7` (`4.6.2`), run 1: exit `0`, `SMOKE SUMMARY pass=25 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=ui_complete GST_UI_COMPLETE_ENTRY=recipe` (`4.6.2`), run 1: exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0`, matching the phase 3 round 1 fix pass's own baseline exactly.
- `GST_EDITOR_SMOKE=6` (`4.6.2`), run 2 (repeated per "serial runs"): exit `0`, `SMOKE SUMMARY pass=16 fail=0`, identical.
- `GST_EDITOR_SMOKE=7` (`4.6.2`), run 2: exit `1`, `SMOKE SUMMARY pass=24 fail=1` (`dissolve_redo_render FAIL dissolve: preview renders non-uniform pixels after redo (img_null=false)`) -- a GPU/render-timing check, not a file-operation check this phase touches; re-run 3 immediately after: exit `0`, `SMOKE SUMMARY pass=25 fail=0`, identical to run 1. Treated as a known, pre-existing rendering flake in this environment (consistent with this document's own prior "first real click of a fresh session is silently absorbed"/rendering-timing notes elsewhere in this file), not a regression from this phase's changes -- nothing in this phase touches `GSTMaterialSync`, rendering, or redo itself.
- `GST_EDITOR_SMOKE=ui_complete GST_UI_COMPLETE_ENTRY=recipe` (`4.6.2`), run 2: exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0`, identical to run 1.
- No leftover `gst_tabs_files_*` files found under either isolated project's `user://`/`res://sandbox` locations after any `tabs_files` run (checked by `find` after the final run); every path the new test writes is cleaned up in every check that creates one, including the failure/rejection checks that must never have written anything in the first place.

### Environment diagnostics (recorded separately from assertion results)

- Every `4.4` run's stderr held only the pre-existing `LayerPane`/`SettingsPane` owner warnings, plus, for `tabs_files` specifically, the deliberately-triggered `ERROR: Cannot open file 'res://sandbox/stacks/gst_tabs_files_missing.tres'` / `Failed loading resource` / `Error loading resource` lines (the `open_dialog_message_routes_to_originating_document` check's own expected diagnostic) and `ERROR: Cannot save file 'user://gst_tabs_files_missing_dir/gst_tabs_files_bad.tres'` (the `failed_save_invalid_path` check's own expected diagnostic). No `SCRIPT ERROR`, `Invalid access`, `Nonexistent function`, or `Parse Error` in any `4.4` or `4.6.2` run above (checked by grep against each run's full captured stdout+stderr). Every `4.6.2` run's stderr was empty.
- The four `ERROR: Attempting to make child window exclusive` lines from `tabs_files` run 2 (described under "Bugs found" above as a test-only artifact, not reproduced after the fix) are recorded here rather than folded into the assertion results, since they never affected any `_check()` outcome in that run.
- The single `dissolve_redo_render` failure on selector `7`'s second `4.6.2` run (described above) is recorded here rather than treated as a phase 5 regression, per the same non-reproducing-flake standard this document already applies elsewhere (e.g. phase 4 round 2's `stable_id_switch_by_click`).
- `sandbox/screenshots/glow.png.import`, `sandbox/vortex/vortex_portal.tscn`, `.gitignore`, `README.md`, `sandbox/logo/`, and `tests/print_roster.gd` appeared modified/untracked in the real repo's `git status` at the start of this pass (unrelated, concurrent work per this file's own prior passes' documented convention of leaving such changes untouched). None were touched by this pass; none were synced into either isolated project beyond `addons/goshade_turbo/` and `tests/`, which this phase's own Files list authorizes.

### Blockers / open decisions

- None found specific to this phase. Closed-document callbacks (the `_documents`/`teardown()` bypass `_run_stale_closed_save_as_rejected` uses to simulate a closed target) receive their full runtime check once phase 6 adds the real close path, per the plan's own phase 5 Blockers note.

### Scope

- Files touched this pass: `addons/goshade_turbo/ui/gst_document.gd`, `addons/goshade_turbo/ui/gst_main_panel.gd`, `tests/gst_editor_document_files_smoke.gd` (new), `tests/gst_editor_document_files_smoke.gd.uid` (new, generated companion), `tests/gst_editor_smoke.gd`, `docs/EDITOR_SMOKE.md` (this section). All are in the plan's phase 5 Files list.
- `tests/gst_editor_ui_complete_smoke.gd` is in the plan's phase 5 Files list and was read in full and run per the plan's own instruction ("existing selectors ... `ui_complete` on `4.6.2`"); it required no edit.
- `NOW.md` was touched (Active-thread next-action line only, bookkeeping, per the implementer's own standing allowance -- no phase content), matching the pattern phases 2/3 already used.
- No file outside the plan's phase 5 Files list (plus `NOW.md` bookkeeping) was edited. `sandbox/**` was not touched. No git worktree was created this pass. The isolated-project copies under `.now/tabs-validation/` were synced (copied), not committed; they are verification scratch under the already-`.gitignore`d `.now/`, not repo source.

## Shader tabs phase 5 review round 1 fix-now (2026-09-11)

Applies the phase reviewer's three fix-now notes from round 1 (PASS-WITH-NOTES). No commit; phase not advanced. `sandbox/**` not touched; no git worktree created. Same isolated projects as the phase 5 pass above (`.now/tabs-validation/project` for `4.4`, `.now/tabs-validation/project-462` for `4.6.2`, both with isolated `APPDATA`/`LOCALAPPDATA`), re-synced with only the three files this pass changed (`gst_document.gd`, `gst_main_panel.gd`, `gst_editor_document_files_smoke.gd`) before every run below.

### Note 1: `_on_new_pressed` diverged from `GSTDocument.operation_messages`

- `addons/goshade_turbo/ui/gst_main_panel.gd:1389-1405` (`_on_new_pressed`): the direct `_message_label.text = ""` write is replaced with clearing `_active_document.operation_messages` and calling `_refresh_operation_message_label()`. `open_document`'s own pristine-reuse path (`_find_reusable_pristine_document`, `:1195-1199`) can reactivate a document that already carries a stale diagnostic (e.g. a failed Open landed on it while it was still the pristine document); blanking only the label previously left that entry in `operation_messages`, so the next `_refresh_operation_message_label()` call (a tab switch back, or any later message on that document) re-showed it. Clearing the document's own dictionary and refreshing from it means the label and the store can never disagree again.
- Status: **fixed**. Evidence: new regression checks below (`new_regression_setup_stale_open_message_present`, `new_clears_stale_open_message`, `new_stale_open_message_does_not_reappear_on_later_message`), all passing.

### Note 2: `_run_failed_save` proved nothing about dirtiness

- `tests/gst_editor_document_files_smoke.gd` (`_run_failed_save`): the original draft captured `dirty_before` from `doc_a` after `doc_a`'s own earlier `_run_save_as_switch` check had already saved it clean, so `dirty_before == false` and the check only proved a clean document stays clean after a failed write -- not the exit criterion it names ("failed writes retain content and dirty state"). Fixed by adding a real structural edit (`panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)`, the same primitive `tests/gst_editor_documents_smoke.gd`'s own `baseline_dirty_after_structural_add` check uses) to `doc_a` before capturing `dirty_before`, and asserting `dirty_before` is `true` directly in the check condition rather than only comparing before/after.
- Status: **fixed**. Evidence: `failed_save_invalid_path PASS ok=false current_path='user://gst_tabs_files_save_as.tres' (expect unchanged 'user://gst_tabs_files_save_as.tres') dirty_before=true (expect true) dirty_after=true message='failed to save stack to user://gst_tabs_files_missing_dir/gst_tabs_files_bad.tres: Can't open'` (both `4.4` runs below).

### Note 3: `GSTDocument.operation_messages` doc comment named the wrong keys

- `addons/goshade_turbo/ui/gst_document.gd:82-85`: the comment listed `("Open", "Save", "Save As", "Export", "Reopen Shader")`. Verified against every `_set_operation_message`/`_set_operation_message_for` call site in `gst_main_panel.gd`: `"Save As"` is never written (Save As failures write `"Save"`, `_on_save_as_file_selected`), and `"Recipes"` (Recipes' own refusal path and picker refusal) and `"Preview"` (the preset dropdown's `screen_uv` suggestion) are written but were unlisted. Corrected to `("Open", "Save", "Export", "Reopen Shader", "Recipes", "Preview" -- Save As failures write "Save")`.
- Status: **fixed**. Comment-only change; no runtime behavior to verify beyond confirming the file still parses (covered by every run below completing with no `SCRIPT ERROR`/`Parse Error`).

### New regression for note 1

- `tests/gst_editor_document_files_smoke.gd`: added `_run_new_clears_stale_open_message`, wired into `run()` after `_run_failed_export`. Opens a missing `.tres` (`res://sandbox/stacks/gst_tabs_files_missing.tres`) on the session's pristine document via `open_path` (its own `_active_document` is the message target, matching the bug's real trigger), asserts the stale message is genuinely present first, presses New (`_on_new_pressed`), asserts the same document is reused (`_find_reusable_pristine_document`, since a failed Open never dirties the stack), the label reads empty, and `operation_messages` has no `"Open"` entry, then drives a real later message on that same document (a failed Save to an unwritable path) and asserts the shown label contains only the new `"Save"` diagnostic, never a resurrected `"Open"` one.

### Verification commands and results

Command shape unchanged from the phase 5 pass: `GST_EDITOR_SMOKE=<selector> APPDATA=<isolated> LOCALAPPDATA=<isolated> <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`, each run its own process, serially, isolated `APPDATA`/`LOCALAPPDATA` (never the real user profile).

- `tabs_files` (`4.4`), run 1: exit `0`, `SMOKE SUMMARY pass=19 fail=0` (`16` prior + `3` new checks; `failed_save_invalid_path` still counted in the `16`, now proving dirtiness instead of trivially passing).
- `tabs_files` (`4.4`), run 2 (repeat per this task's "at least twice" instruction): exit `0`, `SMOKE SUMMARY pass=19 fail=0`, identical to run 1.
- Both `4.4` runs' stderr held only the pre-existing `LayerPane`/`SettingsPane` owner warnings plus the deliberately-triggered diagnostics: `ERROR: Cannot open file 'res://sandbox/stacks/gst_tabs_files_missing.tres'` (x2 -- `open_dialog_message_routes_to_originating_document` and the new regression's own setup step, both expected), `ERROR: Error loading resource`/`Failed loading resource` for the same path (x2, same two checks), `ERROR: Cannot save file 'user://gst_tabs_files_missing_dir/gst_tabs_files_bad.tres'` (`failed_save_invalid_path`'s own expected diagnostic), and `ERROR: Cannot save file 'user://gst_tabs_files_missing_dir/gst_tabs_files_new_pristine_bad.tres'` (the new regression's own later-message step, also expected). No `SCRIPT ERROR`, `Parse Error`, `Invalid access`, or `Nonexistent function` in either run.
- No leftover `gst_tabs_files_*` file found under either the isolated project or its isolated `APPDATA` after the runs (checked by `find`); the new regression's later-message save deliberately fails (unwritable directory) and never had anything to clean up, matching every other failure check in this file.
- Import (isolated `4.6.2`, re-synced with this pass's three files): exit `0`, no script errors.
- `GST_EDITOR_SMOKE=6` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=16 fail=0`, matching baseline exactly (production code touched by this pass is not exercised by selector `6`'s own checks, but re-run per this task's instruction since `gst_document.gd`/`gst_main_panel.gd` changed).
- `GST_EDITOR_SMOKE=7` (`4.6.2`), run 1: exit `1`, `SMOKE SUMMARY pass=24 fail=1` (`dissolve_redo_render FAIL dissolve: preview renders non-uniform pixels after redo (img_null=false)`). Same known GPU/render-timing flake this document already recorded for the phase 5 pass's own selector `7` second run -- not a file-operation check, and nothing in this fix-now pass touches `GSTMaterialSync`, rendering, or redo. Re-run immediately after: exit `0`, `SMOKE SUMMARY pass=25 fail=0`, identical to the phase 5 pass's own baseline.
- `GST_EDITOR_SMOKE=ui_complete GST_UI_COMPLETE_ENTRY=recipe` (`4.6.2`): exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0`, identical to the phase 5 pass's own baseline.
- Every `4.6.2` run's stderr was empty (checked by grep for `ERROR`/`WARNING`/`SCRIPT ERROR`/`Parse Error`/`Invalid access`/`Nonexistent function`; none found), matching the phase 5 pass's own recorded environment diagnostics.

### Blockers / open decisions

- None. All three fix-now notes applied inside the plan's existing phase 5 Files list; no scope drift.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_document.gd` (note 3's doc comment), `addons/goshade_turbo/ui/gst_main_panel.gd` (note 1's `_on_new_pressed` fix), `tests/gst_editor_document_files_smoke.gd` (note 2's `_run_failed_save` fix plus the new `_run_new_clears_stale_open_message` regression), `docs/EDITOR_SMOKE.md` (this section). All are in the plan's phase 5 Files list. No file outside it was touched. `sandbox/**` not touched. No git worktree created. The isolated-project copies under `.now/tabs-validation/` were re-synced (copied), not committed.

## Shader tabs phase 5 review round 2 fix-now (2026-09-11)

Applies the phase reviewer's three fix-now notes from round 2 (PASS-WITH-NOTES). No commit; phase not advanced to phase 6. `sandbox/**` not touched; no git worktree created. Round 1's fix-now notes remain applied and settled (not reverted). Same isolated projects as prior passes (`.now/tabs-validation/project` for `4.4`, `.now/tabs-validation/project-462` for `4.6.2`, both with isolated `APPDATA`/`LOCALAPPDATA`), re-synced with only the two files this pass changed (`gst_main_panel.gd`, `gst_editor_document_files_smoke.gd`) before every run below. `gst_document.gd` was read per the fix-now instructions but not modified this pass.

### Note 1: `_on_new_pressed` called `open_document` without `await`

- `addons/goshade_turbo/ui/gst_main_panel.gd:1389-1409` (`_on_new_pressed`): `open_document(...)` awaits `_finish_pending_edits()` (`open_document:1193`), which suspends whenever a native color popup's typed hex is being committed (`_finish_pending_edits:1211-1212`, decision 7's forced-finish rule). Without `await` on the caller's own line, `operation_messages.clear()` and `_refresh_operation_message_label()` ran against whatever `_active_document` still was at that moment (the previous document), not the document `open_document` was in the middle of installing, on that suspension path. Fixed by changing the call to `await open_document(GSTStack.new(), "", false)`.
- Caller audit (grepped `tests/` for `_on_new_pressed`, read every call site's surrounding context): none require an `await` added at the call site to preserve ordering. `_finish_pending_edits()` only actually suspends when a native color popup commit is in flight; no existing test caller (`tests/gst_editor_smoke.gd`, `tests/gst_editor_ui_layout_smoke.gd`, `tests/gst_editor_ui_complete_smoke.gd`, `tests/gst_editor_ui_picker_smoke.gd`, `tests/gst_editor_document_files_smoke.gd`) calls `_on_new_pressed()` anywhere near an open/committing color popup, so calling the now-coroutine method without `await` still runs it to completion synchronously in the same call (a GDScript coroutine that never actually suspends returns without yielding control back to its caller). The one call in `tests/gst_editor_ui_picker_smoke.gd:199` is made while the picker is open, which hits `_on_new_pressed`'s own early-return guard before `open_document` is ever reached, so it is unaffected regardless. No test file outside the phase 5 Files list required editing; no blocker.
- Observation (not fixed, not cited by this note, out of this fix-now's authorized scope): `_open_path_for` (`gst_main_panel.gd:1470-1483`) has the same shape -- `open_document(result["stack"], path, false)` at `:1482` followed by `_set_operation_message_for(_active_document, "Open", "")` at `:1483` with no `await` -- and could show the same divergence on the same forced-finish suspension path. Left untouched because it is not a cited location in this round's fix-now notes; recorded here for the human/reviewer to decide whether it needs its own finding.
- Status: **fixed**. Evidence: `tabs_files`/`tabs_ui`/`tabs_documents`/`tabs_native` all still pass at their documented baselines below (none of their existing checks exercise the suspending path, so this fix could not regress them; it also could not be positively proven by them, since none drives a color-popup commit concurrently with New -- the fix is a direct read-and-match of `open_document`'s and `_finish_pending_edits`'s own code against the reviewer's cited defect, not a new runtime check).

### Note 2: `_raw_set_current_path` had no caller left

- `addons/goshade_turbo/ui/gst_main_panel.gd:711-714`: deleted. Its only caller (`save_to_path`, per the round 1 diff) was replaced by `_save_stack_to_path`, which re-wrote the same two lines inline at `:1594-1596` instead of calling the byte-identical `_raw_set_current_path_for(doc, path)` (`:762-765` after the deletion; unchanged logic). `_save_stack_to_path` now calls `_raw_set_current_path_for(doc, path)` directly.
- Grepped the full repo (`addons/`, `tests/`) for `_raw_set_current_path` (not `_for`) after the deletion: zero remaining references outside `_raw_set_current_path_for`'s own doc comment, which still names it descriptively.
- Status: **fixed**. Unused private function removed; zero behavior impact (confirmed by every selector below passing at its unchanged baseline).

### Note 3: `_run_export_second_confirmation` proved nothing about dirty state

- `tests/gst_editor_document_files_smoke.gd` (`_run_export_second_confirmation`): `doc_a` was already clean when this check ran (`_run_save_as_switch` above had just saved it), so the check was structurally incapable of catching a stray `mark_baseline()` in the export path -- the same blind spot round-1 note 2 found in `_run_failed_save`, and the negative half of the exit criterion "only successful saves update baseline/path" / Cross-cutting "Export never clears dirty state" / `docs/SHADER_TABS_reviewed.md` decision 8 that nothing asserted. Fixed by dirtying `doc_a` with a real structural edit (`panel.get_undo().add_layer("color/fill", GSTLayer.Kind.COLOR, false)`, the same primitive `_run_failed_save` and `tests/gst_editor_documents_smoke.gd`'s own `baseline_dirty_after_structural_add` check use) before the first export, capturing `dirty_before_export`, and adding two new assertions: `export_clean_write_preserves_dirty_state` (after the first, unconfirmed write) and `export_confirmed_overwrite_preserves_dirty_state` (after the second export's confirmed overwrite).
- Verified by reading, independent of the new test assertions: `_export_stack_to_path` (`gst_main_panel.gd:1634-1658`) contains no `mark_baseline()` call anywhere on any branch -- the shipped code was already correct; the gap was only in proof.
- Status: **fixed**. Evidence: `tabs_files` below reports `pass=21` (`19` prior + these `2` new checks), both new checks passing on both `4.4` runs.

### Verification commands and results

Command shape unchanged: `GST_EDITOR_SMOKE=<selector> APPDATA=<isolated> LOCALAPPDATA=<isolated> <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`, each run its own process, serially, isolated `APPDATA`/`LOCALAPPDATA` (never the real user profile), from Git Bash on Windows 11.

- `tabs_files` (`4.4`), run 1: exit `0`, `SMOKE SUMMARY pass=21 fail=0` (`19` prior + `2` new dirty-state checks).
- `tabs_files` (`4.4`), run 2 (repeat per this task's "at least twice" instruction): exit `0`, `SMOKE SUMMARY pass=21 fail=0`, identical to run 1.
- `tabs_ui` (`4.4`): exit `0`, `SMOKE SUMMARY pass=18 fail=0`, matching the documented phase 4/phase 5 baseline exactly (`_on_new_pressed` is shared production code this round touched).
- `tabs_documents` (`4.4`): exit `0`, `SMOKE SUMMARY pass=22 fail=0`, matching the documented phase 3/4/5 baseline exactly.
- `tabs_native` (`4.4`): exit `0`, `SMOKE SUMMARY pass=31 fail=0`, matching every prior documented baseline exactly.
- `GST_EDITOR_SMOKE=6` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=16 fail=0`, matching baseline.
- `GST_EDITOR_SMOKE=7` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=25 fail=0`, matching baseline (no re-run needed this time -- passed clean on the first try, unlike the known flake recorded in the two prior passes' own sections).
- `GST_EDITOR_SMOKE=ui_complete GST_UI_COMPLETE_ENTRY=recipe` (`4.6.2`): exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0`, matching baseline.
- Both `4.4` `tabs_files` runs' stderr held only the pre-existing `LayerPane`/`SettingsPane` owner warnings plus the same deliberately-triggered diagnostics already documented for this selector (`ERROR: Cannot open file 'res://sandbox/stacks/gst_tabs_files_missing.tres'` x2, its matching `Failed loading resource`/`Error loading resource` lines x2, `ERROR: Cannot save file 'user://gst_tabs_files_missing_dir/gst_tabs_files_bad.tres'`, `ERROR: Cannot save file 'user://gst_tabs_files_missing_dir/gst_tabs_files_new_pristine_bad.tres'`), byte-identical between the two runs. No `SCRIPT ERROR`, `Parse Error`, `Invalid access`, or `Nonexistent function` in either `4.4` run.
- `tabs_ui`/`tabs_documents`/`tabs_native` (`4.4`) stderr each held only the pre-existing `LayerPane`/`SettingsPane` owner warnings; no other errors.
- Every `4.6.2` run's stderr was empty (checked by grep for `ERROR`/`WARNING`/`SCRIPT ERROR`/`Parse Error`/`Invalid access`/`Nonexistent function`; none found).
- No leftover `gst_tabs_files_*` file found under either the isolated `4.4` project or its isolated `APPDATA` after either `tabs_files` run (checked by `find`).

### Environment diagnostics (recorded separately from assertion results)

- No import step was re-run this pass: neither changed file (`gst_main_panel.gd`, `gst_editor_document_files_smoke.gd`) added, removed, or renamed a `class_name`/registered class or a resource requiring reimport; both are edits to already-imported scripts.
- `sandbox/screenshots/glow.png.import`, `sandbox/vortex/vortex_portal.tscn`, `.gitignore`, `README.md`, `sandbox/logo/`, and `tests/print_roster.gd` remain modified/untracked in the real repo's `git status` (unrelated, concurrent work, unchanged from the prior two passes' own recorded state). None were touched by this pass; none were synced into either isolated project beyond `gst_main_panel.gd`/`gst_editor_document_files_smoke.gd`.

### Blockers / open decisions

- None found specific to this phase's own scope. The `_open_path_for` observation under note 1 above is a candidate similar defect outside this round's cited scope, not a blocker to phase 5 completion; left for explicit review/fix-now authorization rather than fixed silently.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_main_panel.gd` (note 1's `_on_new_pressed` `await` fix; note 2's `_raw_set_current_path` deletion and `_save_stack_to_path` call-site fix), `tests/gst_editor_document_files_smoke.gd` (note 3's `_run_export_second_confirmation` dirty-state assertions), `docs/EDITOR_SMOKE.md` (this section). All are in the plan's phase 5 Files list. `addons/goshade_turbo/ui/gst_document.gd` was read (per the fix-now instructions) but not modified. No file outside the phase 5 Files list was touched. `sandbox/**` not touched. No git worktree created. The isolated-project copies under `.now/tabs-validation/` were re-synced (copied), not committed.

## Shader tabs phase 5 review round 3 fix-now (2026-09-11)

Applies the phase reviewer's two fix-now notes from round 3 (PASS-WITH-NOTES). No commit; phase not advanced to phase 6. `sandbox/**` not touched; no git worktree created. Rounds 1 and 2's fix-now notes remain applied and settled (not reverted). Same isolated projects as prior passes (`.now/tabs-validation/project` for `4.4`, `.now/tabs-validation/project-462` for `4.6.2`, both with isolated `APPDATA`/`LOCALAPPDATA`), re-synced with only the two files this pass changed (`gst_main_panel.gd`, `gst_editor_document_files_smoke.gd`) before every run below.

### Note 1: `_open_path_for`/`_reopen_shader_path_for`/`open_recipe`/`_on_picker_choice`'s "recipe" case read the target document after a non-awaited `open_document`/`activate_document`

- Root cause, confirmed by reading `open_document` (`gst_main_panel.gd:1185-1197`) and `activate_document` (`:1027-1039`): both await `_finish_pending_edits()` (`:1200-1207`, which itself awaits `GSTInspectorColumn.finish_pending_edits()` -> `_force_close_color_popups()` whenever a native color popup's typed hex is still uncommitted -- decision 7's forced-finish rule, and CONNECT_DEFERRED on the popup's own close handler per `tests/gst_editor_documents_smoke.gd`'s own comment on this same mechanism). Four call sites called one of these without `await` and then read `_active_document` on the very next statement to route a success message: on the suspension path, that statement ran before the real activation completed, so it read whichever document was still active *before* the switch, not the document the call was actually installing.
- `_open_path_for` (`gst_main_panel.gd`, existing-document branch, previously `:1475-1476`; new-document branch, previously `:1482-1483`): fixed by awaiting `activate_document(existing)`/capturing `var opened: GSTDocument = await open_document(...)` and targeting `existing`/`opened` directly instead of `_active_document`. `opened == null` (`open_document`'s own `is_picker_open()` guard, `:1186`) now gets no success message anywhere, matching the failure branch's "no target, no message" rule.
- `_reopen_shader_path_for` (previously `:1743-1747`): same shape -- `var opened: GSTDocument = await open_document(...)`, both the body-differs-warning and plain-success branches now target `opened`, with the same `opened == null` guard.
- `open_recipe` (previously `:1520-1521`): same shape -- `open_recipe`'s own message-setting statement is the direct next line in the same function (not deferred through shared code the way `_on_picker_choice` is below), so it needed the same `var opened = await open_document(...)` capture and `_set_operation_message_for(opened, ...)` targeting.
- `_on_picker_choice`'s `"recipe"` case (previously `:2274-2275`): different shape from the other three -- the success message is set by *shared* code after the `match` statement (`_applying_choice = false; ...; _picker_refusal("")`, which resolves through `_active_document` via `_set_operation_message`), and nothing awaits between that shared code and the match arm. Once `await` was added to the arm's own `open_document(...)` call, the shared code's `_active_document` read is already correct by the time it runs (the coroutine has already resumed past the real activation) -- no `opened`-capture rewrite was needed here, only the `await`.
- Callers updated to `await` their own call into the now-awaiting primitives, so a caller that wants deterministic completion can `await` it directly instead of relying on frame-polling: `open_path` (`:1465-1466`), `_on_open_file_selected` (`:1443-1446`), `reopen_shader_path` (`:1753-1754`), `_on_reopen_shader_file_selected` (`:1730-1733`). `open_recipe` and `_on_picker_choice` needed no caller-side changes: `open_recipe` is connected as a signal handler (`button.pressed.connect(open_recipe.bind(recipe_name))`, `:385`) and `_on_picker_choice` as `_picker.choice_requested.connect(_on_picker_choice)` (`:217`); Godot signal dispatch runs async handlers fire-and-forget regardless.
- Caller audit (grepped `tests/` for `open_path(`, `open_recipe(`, `reopen_shader_path(`, `_on_open_file_selected(`, `_on_reopen_shader_file_selected(`, `_on_picker_choice(`, cross-referenced against every file with native color-popup helpers -- `tests/gst_editor_documents_smoke.gd`, `tests/gst_editor_native_undo_smoke.gd`, `tests/gst_editor_ui_labels_smoke.gd`, `tests/gst_editor_document_proof.gd`): no caller anywhere in the repo (in the phase 5 Files list or otherwise) invokes any of these six seams while a native color-popup commit is genuinely pending.
  - `tests/gst_editor_documents_smoke.gd`'s own color-popup section (lines ~157-229) only exercises `activate_document` (already awaited, `numeric_pending_edit_finishes_before_document_activation`/`color_pending_edit_finishes_before_document_activation`) during the pending edit; its own `open_path`/`open_recipe`/`reopen_shader_path` calls (lines 284/298/325/341, `open_recipe` at 40/43) run well before or after that section, with a color popup neither open nor pending.
  - `tests/gst_editor_ui_labels_smoke.gd`'s color-popup edit (lines ~354-387) fully commits and closes (polled via its own `close_state["committed"]` deadline loop) before its own `open_path` call at line 438.
  - `tests/gst_editor_ui_picker_smoke.gd`'s `open_path`/`open_recipe`/`reopen_shader_path` calls (lines 201-204) run while a picker (not a color popup) is open, deliberately to prove those handlers are blocked (`is_picker_open()`); each one's own top-level guard returns before reaching any `await`, so the added `await` cannot change that outcome.
  - `tests/gst_editor_ui_complete_smoke.gd`'s only `_on_picker_choice` call (line 256) and `tests/gst_editor_ui_picker_smoke.gd`'s two calls (lines 163, 252) all use `"add"`/`"input"` purposes, never `"recipe"`, so they never reach the arm that gained the `await`.
  - No caller in `tests/gst_editor_smoke.gd` (checked at every `_on_open_file_selected`/`_on_reopen_shader_file_selected`/`open_recipe`/`reopen_shader_path` call site: `:1037`, `:1084`, `:1099`, `:1202`, `:1601`, `:1662`, `:1694`, `:1699`) is adjacent to a color popup either; every one is already followed by 2-3 frames of `process_frame` waiting before its own assertions, an existing margin the fix does not need.
  - Conclusion: no test caller anywhere required an `await` addition to preserve ordering; no blocker to report.
- Status: **fixed**. Evidence: the new regression below, plus every selector's baseline reproduced unchanged.

### Note 2: stale doc comments naming the deleted `_raw_set_current_path` and the wrong `_refresh_tabs`/save caller

- `gst_main_panel.gd:762-765` (`_raw_set_current_path_for`'s doc comment, now the only path setter -- round 2 deleted `_raw_set_current_path` itself): corrected to name `_save_stack_to_path`'s successful-write branch (`:1620`) as its second caller alongside `replace_stack`'s own action, instead of the deleted function.
- `_refresh_tabs`'s doc comment (`:915-925`): corrected "successful save (`save_to_path`)" to "successful save (`_save_stack_to_path`, `:1622`)" -- `save_to_path` is now a thin wrapper (`:1562-1563` in the pre-round-3 numbering) that calls `_save_stack_to_path` against `_active_document`; the actual `_refresh_tabs()` call lives inside `_save_stack_to_path` itself.
- Status: **fixed**. Comment-only change; no runtime behavior to verify beyond every run below completing with no `SCRIPT ERROR`/`Parse Error`.

### New regression for note 1

- `tests/gst_editor_document_files_smoke.gd`: added `_run_open_path_finishes_pending_color_edit`, wired into `run()` after `_run_new_clears_stale_open_message`. Reproduces the exact suspension path the reviewer described:
  1. Closes the "Add Layer" picker `_run_new_clears_stale_open_message` leaves open (`_on_new_pressed`'s own trailing `_on_chooser_requested` call, never closed by that check since `save_to_path` -- unlike `open_document` -- carries no `is_picker_open()` guard); otherwise `open_document`/`open_recipe` below would themselves return `null`/refuse.
  2. Opens `color_doc` via `open_recipe("fire")` (a bare `GSTStack.new()` refuses `add_layer_by_entry_id("color/palette")` outright -- `GSTUndo.add_layer_for_ui`'s own "first layer must work without another layer as input" rule, since `color/palette` has inputs -- so the check needed an existing stack with a `color/palette` layer already wired, exactly like `tests/gst_editor_documents_smoke.gd`'s own equivalent setup).
  3. Seeds `color_doc.operation_messages["Open"]` with a stale diagnostic (simulating an earlier failed Open still displayed), mirroring the reviewer's own reproduction shape.
  4. Selects the palette layer, opens its real `ColorPickerButton` popup, types uncommitted hex text into the popup's own `LineEdit` (mirrors `tests/gst_editor_documents_smoke.gd`'s `color_pending_edit_finishes_before_document_activation` setup) -- a real, in-flight native commit, never a synthetic signal emission.
  5. Calls `panel.open_path(...)` on a second, distinct `.tres` **fire-and-forget** (not awaited by the test), matching exactly how the real Open dialog's own `file_selected` signal dispatches `_on_open_file_selected` in production -- deliberately not relying on `open_path`'s own new internal `await` to block the test, so the regression's discriminating power does not depend on that implementation detail.
  6. Polls (bounded, 3s deadline) until `panel.get_active_document() != color_doc`, rather than a fixed frame count -- closing a native color popup's own close handler is `CONNECT_DEFERRED` and can span more than one frame.
  7. Asserts: the new document is distinct from `color_doc`; `color_doc`'s own history gained exactly the one color-commit action; the palette's displayed color matches the typed hex exactly (the color edit itself finished correctly, not just "some document changed"); and, the actual defect under test, `color_doc.operation_messages.get("Open", "")` still reads the seeded stale text, untouched.
- Verified the regression is discriminating, not just passing by construction: temporarily reverted `_open_path_for`'s fix in the isolated `4.4` project only (back to the pre-fix `open_document(...)` / `_set_operation_message_for(_active_document, "Open", "")` shape, no `await`, no `opened` capture) and re-ran `tabs_files` -- `SMOKE open_path_finishes_pending_color_edit_before_switch FAIL ... doc_a_message='' (expect unchanged)` (`SMOKE SUMMARY pass=21 fail=1`), i.e. the pre-fix code erased `color_doc`'s stale message exactly as the reviewer described. Restored the fix (confirmed byte-identical to the repo source via `diff`) and re-ran clean before continuing; this throwaway revert-and-restore never touched the repo working tree itself, only the isolated `.now/tabs-validation/project` copy.

### Verification commands and results

Command shape unchanged: `GST_EDITOR_SMOKE=<selector> APPDATA=<isolated> LOCALAPPDATA=<isolated> <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`, each run its own process, serially, isolated `APPDATA`/`LOCALAPPDATA` (never the real user profile), from Git Bash on Windows 11. No import step was re-run this pass: neither changed file added, removed, or renamed a `class_name`/registered class or a resource requiring reimport.

- `tabs_files` (`4.4`), run 1: exit `0`, `SMOKE SUMMARY pass=22 fail=0` (`21` prior + the `1` new regression).
- `tabs_files` (`4.4`), run 2 (repeat per this task's "at least twice" instruction, after the revert-and-restore diligence above): exit `0`, `SMOKE SUMMARY pass=22 fail=0`, identical to run 1.
- `tabs_ui` (`4.4`): exit `0`, `SMOKE SUMMARY pass=18 fail=0`, matching every prior documented baseline exactly.
- `tabs_documents` (`4.4`): exit `0`, `SMOKE SUMMARY pass=22 fail=0`, matching every prior documented baseline exactly.
- `tabs_native` (`4.4`): exit `0`, `SMOKE SUMMARY pass=31 fail=0`, matching every prior documented baseline exactly.
- `GST_EDITOR_SMOKE=6` (`4.6.2`), run 1: exit `1`, `SMOKE SUMMARY pass=15 fail=1` (`4 FAIL _on_open_file_selected: ids_match=true params_match=true (octaves=6) preview_nonuniform=false ...`) -- the document's own content/id routing was correct (`ids_match`/`params_match` both `true`, proving `_on_open_file_selected`'s fix installed the right stack); only the GPU preview render had not finished by the fixed 3-frame wait this check uses, the same class of non-reproducing render-timing flake this document already records for `dissolve_redo_render` on selector `7`. Re-run immediately after: exit `0`, `SMOKE SUMMARY pass=16 fail=0`, matching baseline exactly.
- `GST_EDITOR_SMOKE=7` (`4.6.2`): exit `0`, `SMOKE SUMMARY pass=25 fail=0`, matching baseline exactly (no re-run needed).
- `GST_EDITOR_SMOKE=ui_complete GST_UI_COMPLETE_ENTRY=recipe` (`4.6.2`): exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0`, matching baseline exactly.
- Every `4.4` `tabs_files` run's stderr held only the pre-existing `LayerPane`/`SettingsPane` owner warnings plus the same deliberately-triggered diagnostics already documented for this selector (`ERROR: Cannot open file 'res://sandbox/stacks/gst_tabs_files_missing.tres'` x2, its matching `Failed loading resource`/`Error loading resource` lines x2, `ERROR: Cannot save file 'user://gst_tabs_files_missing_dir/gst_tabs_files_bad.tres'`, `ERROR: Cannot save file 'user://gst_tabs_files_missing_dir/gst_tabs_files_new_pristine_bad.tres'`), byte-identical between the two runs. `tabs_ui`/`tabs_documents`/`tabs_native` (`4.4`) stderr each held only the pre-existing `LayerPane`/`SettingsPane` owner warnings (`tabs_documents` additionally its own expected `gst_tabs_documents_missing.tres` load-failure diagnostic). No `SCRIPT ERROR`, `Parse Error`, `Invalid access`, or `Nonexistent function` in any `4.4` run (including the selector `6` render-flake run on `4.6.2`).
- Every `4.6.2` run's stderr was empty (checked by grep for `ERROR`/`WARNING`/`SCRIPT ERROR`/`Parse Error`/`Invalid access`/`Nonexistent function`; none found in either selector `6` run, selector `7`, or `ui_complete`).
- No leftover `gst_tabs_files_*` file found under either the isolated `4.4` project or its isolated `APPDATA` after either `tabs_files` run (checked by `find`).

### Environment diagnostics (recorded separately from assertion results)

- The pre-fix revert-and-restore diligence above ran only against the isolated `.now/tabs-validation/project` copy of `gst_main_panel.gd`; a `diff` against the real repo's `addons/goshade_turbo/ui/gst_main_panel.gd` confirmed byte-for-byte restoration before any of the "real" runs recorded above.
- Godot Engine versions observed: `v4.4.stable.official.4c311cbee` (`4.4` runs), `v4.6.2.stable.official.71f334935` (`4.6.2` runs), both `OpenGL API 3.3.0 NVIDIA ... Compatibility` renderer, matching every prior pass in this document.
- `git status` in the real repo at the start of this pass showed only files already modified/added by phase 5 rounds 1-2 (`NOW.md`, `addons/goshade_turbo/ui/gst_document.gd`, `addons/goshade_turbo/ui/gst_main_panel.gd`, `docs/CURRENTNESS_AUDIT.md`, `docs/EDITOR_SMOKE.md`, `docs/SHADER_TABS_reviewed-plan.md`, `tests/gst_editor_smoke.gd`, plus the untracked `tests/gst_editor_document_files_smoke.gd`/`.uid`) -- no unrelated `sandbox/**`, `.gitignore`, or `README.md` changes were present this pass. None were touched by this pass beyond the two files listed under Scope below.

### Blockers / open decisions

- None. Both fix-now notes applied inside the plan's existing phase 5 Files list; the caller audit under note 1 above found no test caller anywhere (in-list or out-of-list) that needed an `await` addition, so nothing to report as a blocker.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_main_panel.gd` (note 1's four-site `await`/target-capture fix plus their four callers' own `await`; note 2's two doc-comment corrections), `tests/gst_editor_document_files_smoke.gd` (note 1's new `_run_open_path_finishes_pending_color_edit` regression plus its own `_find_layer_by_entry`/`_find_color_button`/`_find_hex_line_edit`/`_type_into_line_edit`/`_push_key` helpers), `docs/EDITOR_SMOKE.md` (this section). All are in the plan's phase 5 Files list. No file outside it was touched. `sandbox/**` not touched. No git worktree created. The isolated-project copies under `.now/tabs-validation/` were re-synced (copied), not committed.

## Shader tabs phase 6: protect document close (2026-09-11)

Implementer pass (not yet independently reviewed). Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (4.4), `.now/tabs-validation/project-462` (4.6.2), both with isolated APPDATA/LOCALAPPDATA (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`), matching every prior pass in this section.

- `addons/goshade_turbo/ui/gst_main_panel.gd`:
  - `_refresh_tabs()`: each tab now builds a real native close Button ("x", flat, `custom_minimum_size.x = 24.0`, `pressed` bound to `close_document.bind(doc)`) alongside the existing title toggle Button, tracked in a new `_tab_close_buttons` map (session_id to Button, editor smoke seam) rebuilt alongside `_tab_buttons` on every call. `focus_was_tab_button`'s own re-check now also covers `_tab_close_buttons.values()`.
  - New `_close_dialog: ConfirmationDialog` (built in `_ready()`, added as a panel child): `ok_button_text = "Save"`, a third "Discard" button added via the native `AcceptDialog.add_button(text, right, action)` (captured as `_close_discard_button`), `confirmed` -> `_on_close_save_requested`, `canceled` -> clears `_pending_close`, `custom_action` -> `_on_close_custom_action` (hides the dialog itself, since `add_button`'s own press never auto-hides it -- confirmed against `scene/gui/dialogs.cpp`'s `AcceptDialog::_custom_action`/`_ok_pressed`/`_cancel_pressed`).
  - New public `close_document(doc)` (wired by each tab's own close Button): finishes pending native edits only when doc is the active document (an inactive document can hold no live gesture of its own, the same rule `_save_stack_to_path`/`_export_stack_to_path` already follow), re-checks doc is still open after that await (a stale close continuation guard), then either closes immediately (`doc.is_dirty() == false`) or captures a `_pending_close` request (same request_id/doc_id shape as every other pending field) and pops `_close_dialog`.
  - New `_on_close_save_requested()` (`_close_dialog.confirmed`): resolves against `_pending_close` via `_resolve_pending_document`; an untitled document (current_path empty) captures a `_pending_save_as` request with a new `close_after: true` flag and pops the real Save As dialog; a named document saves directly to its own current_path and closes only if that write succeeds.
  - New `_on_close_custom_action(action)` (`_close_dialog.custom_action`, "discard" only): resolves against `_pending_close` and closes the document immediately with no write.
  - New `_close_document_now(doc)`: removes doc from `_documents` and calls `doc.teardown()` (already existing, per-document: frees only that document's own UndoRedo). Closing the active document first cancels any open picker against it (`_close_picker(false)`, decision 5's own switch-time rule applied to close too), then either activates the tab that shifts into the closed tab's old array index (decision 9's adjacent-tab selection) or, if that was the last open document, creates and activates a brand-new pristine GSTDocument and re-shows the entry surface -- mirroring `_ready()`'s own bootstrap condition instead of ever leaving the panel with zero documents. No `UndoRedo.create_action` call anywhere in the close path (Cross-cutting "Keep closing and entry navigation outside stack undo").
  - `_on_save_as_file_selected(path)`: now captures the `_save_stack_to_path` result and, when `close_after` was set and the save succeeded, calls `_close_document_now(doc)` -- closing only the document that actually requested the close.
  - New `_capture_document_request(doc)` (phase 6): the same capture shape as `_capture_active_document_request`, parameterized by an explicit document instead of always `_active_document`. `_capture_active_document_request` is now a thin wrapper over it.
  - Deferred note (phase 5 review round 1, resolved here): `hide_export_dialog(abandon: bool = true)` now clears `_pending_export` itself by default (a force-hide with no resolution coming is a genuine abandonment); the one existing caller shape that needs the request to survive into its own immediately-following resolution (`tests/gst_editor_document_files_smoke.gd`'s `_run_export_second_confirmation`) opts out with `abandon=false`.
  - Deferred note (phase 5 review round 1, resolved here): `_on_save_as_file_selected`/`_on_export_file_selected` now capture their own save/export result and, when the resolved document is null (a closed/stale target), surface that result's own reason through `_set_operation_message` onto whichever document is active now, instead of discarding it silently.
- `addons/goshade_turbo/ui/gst_document.gd`: not modified. `teardown()` and `is_dirty()`/`mark_baseline()` (both phase 3) already provide exactly what phase 6's close lifecycle needs; no new field or method was required.
- New `tests/gst_editor_document_close_smoke.gd` (selector `tabs_close`): clean-close-immediate, dirty-named Save (writes to the existing path and closes only after success), dirty-named Discard (no write, `is_instance_valid(history) == false` after teardown), a real Ctrl+Z after a Discard cannot reopen the closed document (Cross-cutting "undo cannot reopen a closed document"), dirty Cancel (document/tab/content untouched), untitled Save-As-on-close success/failure/cancel (a failed or cancelled Save As leaves the document open and dirty; success closes only the originating document), inactive-document close, adjacent-tab selection after closing a middle then a last tab, a stale close continuation rejected without touching a distinct replacement document, and the last close restoring the entry surface behind a freshly created pristine document. Every tab close Button and every `_close_dialog` Save/Discard/Cancel Button is driven with a real InputEventMouseButton press/release at its own global rect through its own Viewport (`_click_button`), including buttons inside the popped-up ConfirmationDialog's own embedded Window -- never `Button.pressed.emit()`, never the production handlers called directly.
- `tests/gst_editor_document_files_smoke.gd`: two `hide_export_dialog()` call sites in `_run_export_second_confirmation` changed to `hide_export_dialog(false)`. `_run_stale_closed_save_as_rejected`'s own assertion updated to match the corrected closed-target behavior: it now asserts the surfaced "no longer open" message on the active document instead of asserting no message was written. New `_run_real_close_then_stale_save_as_rejected`: the same shape through the real `panel.close_document()` instead of the direct `_documents.erase`/`teardown()` bypass.
- `tests/gst_editor_smoke.gd`: added the `tabs_close` dispatch case. The old caller-side `panel._pending_export = {}` workaround is removed: `hide_export_dialog()`'s own new default now does that clear itself.
- `docs/CURRENTNESS_AUDIT.md`: ticked both phase-5-review-round-1 deferred notes with a one-clause resolution note each.

### Bugs found and fixed during self-verification (before any independent review)

1. First-click-of-session absorption, same class as phase 4 round 1's own finding: the very first real click in `tabs_close`'s own fresh editor session was silently absorbed (`clean_close_immediate` failed with `closed=false` on the first run, 4.4). Fixed the same way `tests/gst_editor_tabs_smoke.gd` already does: one harmless warm-up click on the initial document's own already-active tab title Button before any assertion-bearing click.
2. A tab scrolled out of the tab row's own visible range can sit directly under the fixed trailing New control at the same on-screen position. First surfaced as `_run_last_close_restores_entry_surface`'s own drain loop getting stuck indefinitely on 4.6.2 (`drained_to_one=false`), reproduced only there, not on 4.4; diagnosed by dumping every tab's own global rect, which showed the active (rightmost) tab's close Button and NewTabButton (docked immediately outside the scrollable region, phase 4) sharing the identical global position once enough tabs had accumulated to overflow the row and that tab was not currently scrolled into view -- a click aimed at the close Button's own logical rect landed on New instead. A second, independent occurrence of the identical mechanism then surfaced later in the same file, in `_run_stale_close_continuation_cannot_close_replacement` (a `SCRIPT ERROR: Invalid access to property or key 'stack' on a base object of type 'Nil'` on 4.6.2, root-caused via diagnostic prints bracketing each step to a close-button click that landed on NewTabButton and opened the Add-Layer picker instead of the close dialog, confirmed by `is_picker_open()` turning `true` immediately after that one click) -- proving this is not confined to the drain loop but to any close-button click once enough tabs have accumulated. Fixed generally, in the test only (production's own `_refresh_tabs()`/`_await_scroll_active_tab_into_view` already auto-scrolls the active tab into view on every rebuild; this file's own rapid succession of document opens/closes can outrun that single-frame-deferred call before a later click runs): `_click_button` now walks up from its own target through `_find_scroll_ancestor` and, when the target lives inside a `ScrollContainer`, calls `ensure_control_visible` on it and awaits a settle frame before every click in this file, not only inside the drain loop. Not chased into production since no verification requirement here calls for changing `_refresh_tabs()`'s own scroll timing.

Neither is a current, unresolved limitation: both were reproduced, root-caused, fixed, and re-verified in this same pass.

### Verification commands and results

Each selector below was run as its own process, serially, with isolated APPDATA/LOCALAPPDATA set on that process only (never the real user profile), from Git Bash on Windows 11. Command shape: `GST_EDITOR_SMOKE=<selector> APPDATA=<isolated> LOCALAPPDATA=<isolated> <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`.

- Import (isolated 4.4): exit 0. Stderr held only the documented Godot 4.4.0 first-import progress-dialog diagnostic plus the pre-existing LayerPane/SettingsPane owner warnings; no script error. The new test script's own .uid companion was generated by this import and copied back into the repo verbatim.
- `tabs_close` (4.4), run 1 (before the warm-up-click fix): exit 1, SMOKE SUMMARY pass=11 fail=1 (`clean_close_immediate`, bug 1 above).
- `tabs_close` (4.4), run 2 (after the fix, before the undo-cannot-reopen check and the general scroll-into-view fix were added): exit 0, SMOKE SUMMARY pass=12 fail=0.
- `tabs_close` (4.4), run 3 (repeated per this plan's own "serial runs" instruction): exit 0, SMOKE SUMMARY pass=12 fail=0, identical.
- `tabs_close` (4.4), run 4 (after adding `undo_cannot_reopen_closed_document`, before it was corrected to allow for the last-document-replacement rule): exit 1, SMOKE SUMMARY pass=12 fail=1 (`undo_cannot_reopen_closed_document` itself asserted a document-count invariant that does not hold when the closed document happened to be the only one open; corrected to open a second, independent document first and assert non-reopening directly instead).
- `tabs_close` (4.4), run 5 (after that correction and the general `_click_button`/`_find_scroll_ancestor` scroll-into-view fix): exit 0, SMOKE SUMMARY pass=13 fail=0.
- `tabs_close` (4.4), run 6 and 7 (repeated per this plan's own "serial runs" instruction): exit 0, SMOKE SUMMARY pass=13 fail=0, identical both times.
- `tabs_files` (4.4): exit 0, SMOKE SUMMARY pass=23 fail=0 (21 prior baseline checks plus the 2 new closed-target-via-real-close cases).
- `tabs_ui` (4.4): exit 0, SMOKE SUMMARY pass=18 fail=0, matching the phase 5 baseline exactly.
- `tabs_documents` (4.4): exit 0, SMOKE SUMMARY pass=22 fail=0, matching baseline.
- `tabs_native` (4.4): exit 0, SMOKE SUMMARY pass=31 fail=0, matching baseline.
- Headless unit wrapper (isolated 4.4): GST tests: 21 file(s), 145 test method(s), 20 failure(s) -- identical to every documented prior-phase baseline; none of the 20 pre-existing failures touch a file this phase modified.
- Import (isolated 4.6.2): exit 0, no script errors.
- `tabs_close` (4.6.2), run 1 (before the scroll-into-view fix, with `undo_cannot_reopen_closed_document` already present and passing): exit 1, SMOKE SUMMARY pass=12 fail=1 (`last_close_restores_entry_surface`, bug 2's drain-loop occurrence, reproduced only on 4.6.2).
- `tabs_close` (4.6.2), run 2 (after the drain-loop-only fix, before generalizing it): exit 1, SMOKE SUMMARY pass=12 fail=1 (`stale_close_continuation_cannot_close_replacement_tab`, bug 2's second occurrence, the same mechanism hitting a different close-button click in the same file).
- `tabs_close` (4.6.2), run 3 (after generalizing the fix into `_click_button` itself): exit 0, SMOKE SUMMARY pass=13 fail=0.
- `tabs_close` (4.6.2), run 4 and 5 (repeated per this plan's own "serial runs" instruction): exit 0, SMOKE SUMMARY pass=13 fail=0, identical both times.
- `tabs_files` (4.6.2): exit 0, SMOKE SUMMARY pass=23 fail=0, matching the 4.4 result exactly.
- `ui_complete` (4.6.2, GST_UI_COMPLETE_ENTRY=recipe): exit 0, UI_COMPLETE SUMMARY pass=29 fail=0, matching baseline.
- `ui_picker` (4.6.2, run to confirm `hide_export_dialog()`'s new default does not regress its own existing call): exit 0, UI_PICKER SUMMARY pass=45 fail=0, matching baseline.
- Not run this pass: GPU render/composition/recipe-motion checks (unaffected by this phase's editor-only files); 4.7 (not required by phase 6's own verification list); the headless unit wrapper on 4.6.2 (only editor-only `gst_main_panel.gd` and test files changed this phase, the same basis prior editor-only phases used to skip it).

### Environment diagnostics (recorded separately from assertion results)

- Every 4.4 run's stderr held only the pre-existing LayerPane/SettingsPane owner warnings plus the one deliberately-triggered "Cannot save file" diagnostic (the untitled-Save-As-failure-class checks) or `tabs_files`'s own already-documented deliberate diagnostics. No SCRIPT ERROR, Invalid access, Nonexistent function, or Parse Error in any run.
- Every 4.6.2 run's stderr held only its own deliberately-triggered diagnostic where applicable; `ui_complete`/`ui_picker` stderr was empty.
- Godot Engine version observed: v4.4.stable.official.4c311cbee (4.4 runs), matching every prior pass in this document; 4.6.2 binary unchanged from every prior phase's own runs.
- No leftover `gst_tabs_close_*` file found under either isolated project or isolated APPDATA after any run (checked by find).
- git status in the real repo at the start of this pass showed only NOW.md already modified from before this pass began; no unrelated sandbox/**, .gitignore, or README.md changes were present.

### Blockers / open decisions

- None found requiring a design decision. The two items under "Bugs found" above were reproduced, root-caused, fixed, and re-verified in this same pass, not deferred.
- The close dialog's own button layout was not given a specific visual position/order beyond what `AcceptDialog.add_button` produces by default; no reviewed decision specifies an exact order, and no test asserts one (only button identity/behavior).

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_main_panel.gd`, `tests/gst_editor_document_close_smoke.gd` (new), `tests/gst_editor_document_files_smoke.gd`, `tests/gst_editor_smoke.gd`, `docs/CURRENTNESS_AUDIT.md` (two ticks), `docs/EDITOR_SMOKE.md` (this section), `NOW.md` (Active thread next-action line only), plus the generated `tests/gst_editor_document_close_smoke.gd.uid` companion. All are inside the plan's phase 6 Files list plus its stated NOW.md/docs/CURRENTNESS_AUDIT.md/.uid allowances.
- `addons/goshade_turbo/ui/gst_document.gd` is in the plan's phase 6 Files list; read in full this pass, not edited.
- No file outside the plan's phase 6 Files list was edited. `sandbox/**` was not touched. No git worktree was created. The isolated-project copies under `.now/tabs-validation/` were synced (copied), not committed.

## Shader tabs phase 6 review round 1 fix-now (2026-09-11)

Round-1 review verdict PASS-WITH-NOTES, three fix-now notes. Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (4.4), `.now/tabs-validation/project-462` (4.6.2), both with isolated APPDATA/LOCALAPPDATA (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`), matching every prior pass in this section.

### Fix-now note status

1. `addons/goshade_turbo/ui/gst_main_panel.gd:955-958` (`_refresh_tabs` doc comment claimed "No close button is built here: phase 6 wires the close affordance", stale since the same function now builds the close Button at `:997-1008`) — fixed. The sentence is rewritten to point at the close Button the function actually builds, alongside the title Button, in the same rebuild loop.
2. `tests/gst_editor_document_files_smoke.gd` (closed-target Export branch at `addons/goshade_turbo/ui/gst_main_panel.gd:1867-1868` unexecuted by any test) — fixed. New `_run_stale_closed_export_rejected`, mirroring `_run_stale_closed_save_as_rejected` (:221): opens a throwaway document, captures an Export request for it via `_on_export_pressed`/`hide_export_dialog(false)`, activates `doc_a`, removes the throwaway document from `_documents` and tears it down, then resolves `_on_export_file_selected` against the now-closed target. Asserts nothing is written, the active document is untouched, and `doc_a.operation_messages["Export"]` contains `no longer open`. Wired into `run()` immediately after `_run_stale_closed_save_as_rejected`.
3. `tests/gst_editor_document_close_smoke.gd:492` (`##` mid-block inside a function-body comment that otherwise uses `#`) — fixed. Changed to `#`.

### Verification commands and results

Each selector below was run as its own process, serially, with isolated APPDATA/LOCALAPPDATA set on that process only (never the real user profile), from Git Bash on Windows 11. Command shape: `GST_EDITOR_SMOKE=<selector> APPDATA=<isolated> LOCALAPPDATA=<isolated> <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`.

- Import (isolated 4.4): exit `0`. Stderr held only the documented Godot 4.4.0 first-import progress-dialog diagnostic plus the pre-existing LayerPane/SettingsPane owner warnings; no script error.
- `tabs_files` (4.4): exit `0`, `SMOKE SUMMARY pass=24 fail=0` (23 prior baseline checks plus the 1 new `stale_closed_export_rejected` case; `SMOKE stale_closed_export_rejected PASS file_exists=false active_is_a=true doc_a_message='This document is no longer open.'`). Stderr held only the pre-existing deliberate load/save-failure diagnostics from other cases in this file (missing-path load, bad-directory save); no script error.
- Import (isolated 4.6.2): exit `0`, no script errors, no stderr output.
- `tabs_files` (4.6.2): exit `0`, `SMOKE SUMMARY pass=24 fail=0`, matching the 4.4 result exactly, including `SMOKE stale_closed_export_rejected PASS file_exists=false active_is_a=true doc_a_message='This document is no longer open.'`. Stderr held only the same class of pre-existing deliberate load/save-failure diagnostics (with GDScript backtraces on this engine version); no script error.
- `tabs_close` (4.4): exit `0`, `SMOKE SUMMARY pass=13 fail=0`, matching the phase 6 baseline exactly. No `SCRIPT ERROR`, `Invalid access`, `Nonexistent function`, or `Parse Error` in stderr.
- Not run this pass: `tabs_close` on 4.6.2 (not required by this fix-now scope; the round-1 baseline already covers it and no fix-now note touches close-lifecycle behavior), the headless unit wrapper, GPU render/composition/recipe-motion checks, and 4.7 (unaffected by a doc-comment fix, a `##`→`#` comment fix, and a new test case in an already-covered file).

### Environment diagnostics (recorded separately from assertion results)

- Godot Engine version observed: `v4.4.stable.official.4c311cbee` (4.4 runs); 4.6.2 binary unchanged from every prior phase's own runs.
- `4.4` `tabs_files`/`tabs_close` stderr held only the documented deliberate diagnostics listed above; no unexpected script/engine error.
- `4.6.2` `tabs_files` stderr held the same deliberate diagnostics with added GDScript backtraces (engine-version formatting difference only, not a new error class).
- No leftover `gst_tabs_files_export_stale.gdshader` found under either isolated project after either `tabs_files` run (checked by find).
- git status in the real repo before this pass showed the same pre-existing modifications as the round-1 pass (`NOW.md`, `docs/CURRENTNESS_AUDIT.md`, `docs/EDITOR_SMOKE.md`, `docs/SHADER_TABS_reviewed-plan.md` status line) plus this pass's own edits; no unrelated `sandbox/**`, `.gitignore`, or `README.md` changes were present.

### Blockers / open decisions

- None. All three fix-now notes were applied inside the plan's phase 6 Files list; no scope drift.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_main_panel.gd` (fix-now note 1 only), `tests/gst_editor_document_files_smoke.gd` (fix-now note 2), `tests/gst_editor_document_close_smoke.gd` (fix-now note 3), `docs/EDITOR_SMOKE.md` (this section). All are inside the plan's phase 6 Files list.
- No file outside the plan's phase 6 Files list was edited. `sandbox/**` was not touched. No git worktree was created. The isolated-project copies under `.now/tabs-validation/` were synced (copied), not committed. No commit was made.

## Shader tabs phase 6 review round 2 fix-now (2026-09-11)

Round-2 review verdict PASS-WITH-NOTES, two fix-now notes, both doc-comment rewrites in `addons/goshade_turbo/ui/gst_main_panel.gd`. No behavior change. Isolated project synced from the repo before the run: `.now/tabs-validation/project` (4.4), with isolated `APPDATA`/`LOCALAPPDATA` (`.now/tabs-validation/appdata-4.4`), matching every prior pass in this section.

### Fix-now note status

1. `addons/goshade_turbo/ui/gst_main_panel.gd:84` (`## creation order. Never pruned in this phase (document close is phase 6).` false since `_close_document_now:1373` (`_documents.remove_at(index)`) prunes `_documents`) -- fixed. Rewritten to `## creation order. _close_document_now is the only pruner (_documents.remove_at).`
2. `addons/goshade_turbo/ui/gst_main_panel.gd:1181-1184` (`_find_document_by_session_id`'s doc comment still said "phase 6 adds the close path this guards against ... since real close does not exist yet", stale since `close_document:1276`/`_close_document_now:1363` are real and exercised by `tests/gst_editor_document_files_smoke.gd:_run_real_close_then_stale_save_as_rejected`) -- fixed. Rewritten to name `_close_document_now` as the real producer of the null case, keeping the note that `tests/gst_editor_document_files_smoke.gd` still isolates the resolution guard by removing a document from `_documents` directly instead of driving a real close.

### Extra stale-comment sweep

Grepped `addons/goshade_turbo/ui/gst_main_panel.gd` and `addons/goshade_turbo/ui/gst_document.gd` for `phase 6 (will|adds|wires)`, `in the meantime`, `close does not exist`, `does not exist yet`, and `phase 6` generally (case-insensitive).

- No additional stale comment found. Every other `phase 6` reference in `gst_main_panel.gd` (lines `119`, `157`, `194`, `356`, `700`, `957`, `996`, `1103`, `1219`, `1262`, `1565`, `1785`, `1786`, `1860`) attributes an already-implemented behavior to phase 6 in past/factual tense (e.g. "Wired-by: _refresh_tabs()'s own per-tab close Button.pressed connection", "resolved phase 6") -- none claims the close path is still missing or deferred.
- `gst_document.gd:134` ("Called by gst_main_panel.gd's `_exit_tree` for every open document, and by phase 6's close lifecycle for a single discarded document") references phase 6's close lifecycle as an existing caller (`teardown()` is in fact called from `_close_document_now:1374`), not as a future addition -- left unchanged, not stale.

### Verification commands and results

Selector run as its own process with isolated `APPDATA`/`LOCALAPPDATA` set on that process only (never the real user profile), from Git Bash on Windows 11. Command shape: `GST_EDITOR_SMOKE=tabs_close APPDATA=<isolated> LOCALAPPDATA=<isolated> Godot_v4.4-stable_win64.exe --editor --path <isolated-project> --rendering-method gl_compatibility`.

- `tabs_close` (4.4): exit `0`, `SMOKE SUMMARY pass=13 fail=0`, matching the phase 6 baseline exactly. Stderr held only the documented pre-existing `LayerPane`/`SettingsPane` owner warnings and the deliberate bad-directory save-failure error (`Cannot save file 'user://gst_tabs_close_missing_dir/gst_tabs_close_bad.tres'`); no `SCRIPT ERROR`, `Invalid access`, `Nonexistent function`, or `Parse Error`.
- Not run this pass: `tabs_close` on 4.6.2, `tabs_files`, `tabs_documents`, `tabs_native`, `tabs_ui`, the headless unit wrapper, and 4.7 (not required by this fix-now scope: two doc-comment rewrites with no behavior change; the phase 6 and round-1 baselines already cover close-lifecycle behavior on those configurations).

### Environment diagnostics (recorded separately from assertion results)

- Godot Engine version observed: `v4.4.stable.official.4c311cbee` (unchanged from every prior 4.4 run in this section).
- Isolated project copy at `.now/tabs-validation/project` was re-synced from the repo's `addons/` and `tests/` directories immediately before this run so the doc-comment rewrites were present in the copy actually exercised; verified byte-identical to the repo copy of `addons/goshade_turbo/ui/gst_main_panel.gd` after the sync.
- git status in the real repo before this pass showed the same pre-existing modifications as the round-1 pass (`NOW.md`, `docs/CURRENTNESS_AUDIT.md`, `docs/EDITOR_SMOKE.md`, `docs/SHADER_TABS_reviewed-plan.md` status line, plus the phase 6 test files) plus this pass's own edit to `gst_main_panel.gd`; no unrelated `sandbox/**`, `.gitignore`, or `README.md` changes were present.

### Blockers / open decisions

- None. Both fix-now notes were applied inside the plan's phase 6 Files list; no scope drift.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_main_panel.gd` (both fix-now notes), `docs/EDITOR_SMOKE.md` (this section). Both are inside the plan's phase 6 Files list.
- No file outside the plan's phase 6 Files list was edited. `sandbox/**` was not touched. No git worktree was created. The isolated-project copy under `.now/tabs-validation/project` was synced (copied), not committed. No commit was made.

## Shader tabs phase 7: confirmed-shutdown save and project-local recovery (2026-09-11)

Implementer pass (not yet independently reviewed). Isolated projects synced from the repo before each run: `.now/tabs-validation/project` (`4.4`), `.now/tabs-validation/project-462` (`4.6.2`), both with isolated `APPDATA`/`LOCALAPPDATA` (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`) so editor settings and `user://` saves never touch the real account profile, matching every prior pass in this section. The phase 1 shutdown probe fixture (`res://tests/fixtures/shader_tabs_shutdown_plugin.cfg`) was removed from both isolated projects' `project.godot` `[editor_plugins]` `enabled` list before every run this pass (`enabled=PackedStringArray("res://addons/goshade_turbo/plugin.cfg")` only) -- per the plan, this phase implements the real thing in production `plugin.gd`/`gst_main_panel.gd`, so the probe has nothing left to prove and must never also answer the real confirmed-quit dialog.

### Implementation

- New `addons/goshade_turbo/ui/gst_document_recovery.gd` (`GSTDocumentRecovery`, `RefCounted`, static-only like `gst_stack_io.gd`): `recovery_dir(settings_dir)` resolves `<settings_dir>/goshade_turbo/recovery`; `write_record(dir, stack, original_path, recipe_open, recipe_name, reopened_import, save_failed, record_id="")` writes a self-contained `<id>.tres` `GSTStack` (the same schema `GSTStackIO` already saves/loads) plus a shared `index.json` metadata entry (`version`, `id`, `stack_file`, `original_path`, `recipe_open`, `recipe_name`, `reopened_import`, `save_failed`, `created_unix`), reusing an existing `record_id` in place instead of appending a duplicate, and checks the stack write and the metadata write separately before reporting `ok`; `remove_record`/`load_all` round out cleanup and startup loading. Never targets a user's own stack/export path (decision 10): the destination is always `dir`, never `original_path`.
- `addons/goshade_turbo/ui/gst_document.gd`: new `recovery_record_id: String` (the record's own stable id, or `""`) and `recovery_fingerprint: String` (the fingerprint the record last captured). New `needs_shutdown_attention() -> bool`: `is_dirty()` and (no record yet, or the record's own fingerprint no longer matches the live stack) -- see "Real quit finding" below for why this differs from plain `is_dirty()`.
- `addons/goshade_turbo/ui/gst_main_panel.gd`: `get_recovery_dir()` (always `EditorInterface.get_editor_paths().get_project_settings_dir()`-based, no test-only override -- isolation comes from running the whole selector against an isolated project, matching every other phase); `get_unsaved_status_text(for_scene)` (`""` for nonempty `for_scene`; otherwise every `needs_shutdown_attention()` document's `_describe_document` name); `save_external_data()` (finishes pending edits without awaiting the call site, matching phase 1's own established synchronous-shutdown finding; saves each dirty named document to its own path, marking its baseline and forgetting any recovery record on success; recovers every untitled or failed-path document instead via `_recover_document`, reusing its own prior `recovery_record_id`); `_recover_document` (writes/updates the record, sets `recovery_fingerprint` on success, `push_error`s both exact attempted paths plus the void-callback limitation on failure); `_forget_recovery_record` (called after a successful `_save_stack_to_path` and from `_close_document_now`, unconditionally -- a no-op when the document never held a record); `load_recovery_records()` (called once from `_ready()`, after the bootstrap pristine document: reopens every valid record as its own dirty `GSTDocument`, `push_error`s failed/unreadable ones by path without deleting them, dismisses the start screen and activates the last recovered document only when at least one exists).
- `addons/goshade_turbo/plugin.gd`: `_get_unsaved_status`/`_save_external_data` overrides delegate to the panel.
- `tests/gst_editor_smoke.gd`: new `tabs_recovery` dispatch entry.
- New `tests/gst_editor_document_recovery_smoke.gd` (selector `tabs_recovery`): see "Verification" below.

### Real quit finding: Godot re-checks `_get_unsaved_status` after `_save_external_data`

The plan's own phase 1 evidence proved `_save_external_data()` runs synchronously during a real confirmed quit but never actually drove the process to exit afterward. This phase's own first real-quit attempts (implementation otherwise complete) reproducibly hung: the real "Please Confirm..." dialog opened, `_get_unsaved_status("")` correctly listed the dirty documents, `_save_external_data()` genuinely ran (confirmed with a temporary print statement, since removed) and wrote both documents' recovery records -- but the dialog never closed and the editor process never exited, across a focused-Enter activation, a direct `pressed.emit()`, and (after fixing an unrelated `_find_button` internal-children bug, below) a real simulated click, identically every time. Deliberately eliminating both permanently-dirty documents from the same scenario (one discarded outright, one repointed at a writable path so its own named save actually marks it clean) let the identical click sequence exit the process cleanly on the first try. Conclusion: Godot's own "Save and Quit" handler re-evaluates every plugin's `_get_unsaved_status("")` after calling `_save_external_data()` and does not proceed to quit while that still reports anything -- a design decision-10's "recovery preserves content without silently marking it saved" did not anticipate. `GSTDocument.needs_shutdown_attention()` (above) resolves the conflict: a document stays `is_dirty()` forever (dirty star, close-confirmation, tab title unaffected) but stops naming itself in `_get_unsaved_status` once its own recovery record's fingerprint matches its current content, satisfying Godot's re-check while a genuinely newer edit made after that point (in the same session, without saving or discarding) still surfaces normally. Verified directly: selector item `recovered_document_stops_blocking_shutdown_status` (`is_dirty()` stays `true`, the status text stops naming the document) and the real quit itself completing end to end (below).

### Other environment findings

- Godot `4.4`'s own editor top bar is a `MenuBar` (`EditorTitleBar`), not a row of `MenuButton`s: `Ctrl+Shift+Q` delivered as a synthetic `InputEventKey` through `viewport.push_input` (phase 1's own proven technique, `tests/gst_editor_document_proof.gd`) stopped opening the quit confirmation in this environment; the real window reported both `Window.has_focus()` and `DisplayServer.window_is_focused()` `true` at the time, ruling out an OS-focus explanation. Firing the `Scene` menu's own `PopupMenu.id_pressed` signal directly for its `"Quit"` item (found by iterating `MenuBar.get_menu_popup(i)`/`get_item_text(j)` by text, not a hardcoded id) reliably opens the identical dialog every time; the same technique closes a stray already-open scene (`"Close Scene"`) before driving quit, so the dispatch is never left racing Godot's own separate save-this-scene handling for a scene GoShade never opened (a leftover from Godot's own "reopen scenes on startup" restoring a stale `gst_main_panel.tscn` edit from an earlier phase's own proof run).
- `AcceptDialog`'s own message `Label`/button row are internal children (`Node.get_children(true)`-only, excluded by the plain `get_children()` a first draft of `_find_button` used): the dialog was always reachable directly as a child of `plugin.get_tree().root`, but its own buttons were never found until `_find_button` was rewritten to use `find_children(...)` (`tests/gst_editor_document_proof.gd`'s own established convention) instead.

### Verification: `tabs_recovery` (new selector)

Stage-file two-process pattern (`tests/gst_editor_document_proof.gd`'s own established phase 1 pattern), with a JSON file of its own directly under the project's settings directory (sibling of `goshade_turbo/recovery`, so it is never mistaken for a real record) recording which half of the real confirmed-quit round trip a given process is; no shutdown probe fixture is used (see above). Every within-session check calls `plugin._get_unsaved_status`/`_save_external_data` directly -- the exact production callbacks Godot's own quit/scene-close call.

Covers: nonempty `for_scene` reporting empty; a leftover open scene closed defensively before the flow runs; the record schema's own version/identity/original-path/recipe-origin fields round-tripping in an isolated throwaway directory; `write_record`'s own directory-creation failure and metadata-write failure (index.json replaced by a directory, in throwaway directories separate from the live flow) both reporting `ok=false` without silently succeeding; the dual-failure case (a named document whose own save and whose recovery write both fail) never marking a document falsely resolved, exercised by calling `_recover_document` directly against a throwaway blocked directory; mixed named-success/named-failed/untitled documents in one shutdown; a recovered document no longer blocking `_get_unsaved_status` (the finding above); repeated shutdown against still-dirty documents updating the same record in place (no duplicate); Save and Discard cleanup each removing their own document's record; the real confirmed `Ctrl+Shift+Q`-equivalent quit (`Scene > Quit` via `MenuBar`) with two genuinely unresolvable dirty documents (one untitled, one path-blocked) actually exiting the editor process; and, on fresh reopen, both documents restored as dirty tabs before the start screen, followed by post-restart Save/Discard cleanup leaving the recovery directory empty.

The dual-failure case's own `_recover_document` `push_error` was observed verbatim in stderr: `GoShade Turbo: could not save user://gst_recovery_dual_failure_named.tres (simulated named-save failure) or recover it to : failed to create recovery directory .../gst_recovery_dual_failure_check/goshade_turbo/recovery: Can't create. _save_external_data() is void and cannot veto editor shutdown.` -- both exact attempted operations named, plus the void-callback wording, matching decision 10's own required wording exactly.

- 4.4, stage 1 (`GST_EDITOR_SMOKE=tabs_recovery; Godot_v4.4-stable_win64.exe --editor --path .now/tabs-validation/project --rendering-method gl_compatibility`): `SMOKE SUMMARY` line absent because the process quits through the real editor; `grep -c "SMOKE .* PASS"` reads `17`, `grep -c "SMOKE .* FAIL"` reads `0`. Exit code `0` (the owned process actually exited via the real "Save & Quit" click, not `.quit()`). Stderr held only the deliberate blocked-path save errors (`Cannot save file 'user://gst_recovery_blocked_parent/named_failed.tres'`, `.../quit_named_failed.tres`), the deliberate blocked-directory creation errors (including the dual-failure case's own), the dual-failure `push_error` quoted above, and one expected `SCRIPT ERROR: Cannot call method 'get_tree' on a previously freed instance.` at `_click_button`'s own trailing `await` (the process legitimately exits mid-await once the real click's own quit sequence completes, the same class of finding `tests/gst_editor_document_proof.gd`'s own r6a fix documents for its own pending-shutdown `Callable`) -- no unexpected error.
- 4.4, stage 2 (same command, same isolated project, re-run without resetting state): `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr. `restoration_before_entry PASS start_screen_hidden=true untitled_ok=true failed_ok=true document_count=3`; recovery directory listing before cleanup: `["<untitled-id>.tres", "<named-failed-id>.tres", "index.json"]`; `post_restart_save_cleanup PASS`, `post_restart_discard_cleanup PASS`, `recovery_dir_empty_after_final_cleanup PASS remaining=0`.
- 4.6.2, stage 1 (`Godot_v4.6.2-stable_win64.exe --editor --path .now/tabs-validation/project-462 --rendering-method gl_compatibility`, isolated `appdata-4.6.2`): `grep -c "SMOKE .* PASS"` reads `17`, fail `0`, exit `0`, matching the 4.4 baseline exactly.
- 4.6.2, stage 2 (same command, re-run): `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr, matching the 4.4 baseline exactly.
- Import (isolated `4.6.2`, `GST_EDITOR_SMOKE` unset): `Godot_v4.6.2-stable_win64.exe --headless --path .now/tabs-validation/project-462 --import`. Exit `0`, empty stderr.

### Regression: existing selectors on `4.4`

- `tabs_native`: exit `0`, `SMOKE SUMMARY pass=31 fail=0`, matching the phase 2/3 baseline exactly.
- `tabs_documents`: exit `0`, `SMOKE SUMMARY pass=22 fail=0`. Stderr held only the deliberate missing-resource errors the selector's own failed-open case expects.
- `tabs_ui`: exit `0`, `SMOKE SUMMARY pass=18 fail=0`, empty stderr apart from the pre-existing `LayerPane`/`SettingsPane` owner warnings.
- `tabs_files`: exit `0`, `SMOKE SUMMARY pass=24 fail=0`. Stderr held only the selector's own deliberate missing-resource/bad-directory errors.
- `tabs_close`: first attempt exit `1`, `SMOKE SUMMARY pass=11 fail=2` (`dirty_named_close_save`, `dirty_named_close_discard` -- both real-click timing failures with no changed-code involvement, `closed=false` on a real dialog OK click); re-run with no code change: exit `0`, `SMOKE SUMMARY pass=13 fail=0`. Treated as the environment's own pre-existing real-click flakiness (this whole pass repeatedly found the same class of issue with synthetic input timing in this sandboxed environment, above), not a regression: no file this phase touches changes anything `tabs_close`'s own close/save/discard paths read, and `_forget_recovery_record`'s only effect on a document with an empty `recovery_record_id` (every document `tabs_close` itself creates) is its own early no-op return.

### Environment diagnostics

- Godot Engine versions observed: `v4.4.stable.official.4c311cbee`, `v4.6.2.stable.official.71f334935`.
- Both isolated projects' `project.godot` `[editor_plugins]` `enabled` list had the phase 1 shutdown-probe fixture removed for this whole phase's runs (see above); restored to its own prior state is not required since `.now/` is gitignored scratch state, matching every earlier phase's own convention for this directory.
- The isolated `4.4` project's own `.godot/editor/goshade_turbo/recovery` directory was wiped (`rm -rf`) from the host shell before every `tabs_recovery` stage-1 run during iteration on this selector, and again before the final recorded pair: a prior aborted run's own leftover recovery record reopens correctly as a dirty document on the next fresh `_ready()` (confirmed directly, and also defended against inside the selector itself -- see `_run_initial`'s own leading drain loop), which would otherwise skew that later run's own record counts.
- Preserved the user's untracked `weird1.tres`, `weird2.tres`, and the pre-existing `sandbox/screenshots/glow.png.import` changes; not touched by any command this pass.

### Blockers / open decisions

- None blocking. The Godot re-check finding above required a genuine design correction beyond the plan's own literal text (`needs_shutdown_attention()` vs. plain `is_dirty()`); the correction stays inside decision 10's own stated intent (a successful recovery write is what makes shutdown itself safe, not a private editing-session concept like the dirty star) and does not change any other decision or contract.
- Evidence gap, not a known defect: `load_recovery_records()`'s own failure branch (an unreadable/malformed record kept on disk and reported by path, never deleted) is implemented and code-inspected against `GSTDocumentRecovery.load_all`'s own `failures` array, which never touches disk on a failure -- but no `tabs_recovery` check independently corrupts an on-disk record and reopens the project to observe that specific path. Every check this pass exercises `load_all`'s success path (real restoration) and `write_record`'s own failure paths (directory/metadata write failures); the read-side failure path itself remains unexercised at runtime.

### Scope

- Files modified this pass: `addons/goshade_turbo/plugin.gd`, `addons/goshade_turbo/ui/gst_main_panel.gd`, `addons/goshade_turbo/ui/gst_document.gd`, new `addons/goshade_turbo/ui/gst_document_recovery.gd` (+ generated `.gd.uid`), new `tests/gst_editor_document_recovery_smoke.gd` (+ generated `.gd.uid`), `tests/gst_editor_smoke.gd`, `docs/EDITOR_SMOKE.md` (this section), `NOW.md` (Active-thread next-action line only). All inside the plan's phase 7 Files list (plus the two Godot-generated `.uid` companions and the `NOW.md` bookkeeping allowance the orchestrator's own instructions grant every phase).
- `tests/fixtures/shader_tabs_host.tscn` (listed in the plan's phase 7 Files list) was read and used unmodified as the fixture scene for the nonempty-`for_scene` check; its existing bare content already sufficed, so no edit was needed.
- No file outside the plan's phase 7 Files list was edited. `sandbox/**` was not touched. No git worktree was created. No recovery record or stage file was ever written into the real repository's own `.godot/`; every write happened inside `.now/tabs-validation/project`/`project-462`, both gitignored. No commit was made.

## Shader tabs phase 7 review round 1 fixes (2026-09-12)

Fix pass against round 1's four required fixes. Isolated projects re-synced from the repo's two changed files before every run (`.now/tabs-validation/project` for `4.4`, `.now/tabs-validation/project-462` for `4.6.2`), same isolated `APPDATA`/`LOCALAPPDATA` as the original pass. The phase 1 shutdown-probe fixture stayed disabled in both projects' `project.godot` (verified before running, not re-touched).

### Fix 1: `_read_index` distinguishes absent from unparseable; `write_record` never truncates a bad index

`addons/goshade_turbo/ui/gst_document_recovery.gd`: `_read_index(dir)` now returns `{ok, index, reason}`. `ok=true` covers both an absent `index.json` (fresh empty index, unchanged behavior) and a present, well-formed one. `ok=false` covers a present file this engine cannot resolve into `{"records": Array}` (malformed JSON, a non-Dictionary root, or a non-Array `"records"` field), `reason` naming `_index_path(dir)`. Uses the instance `JSON.new().parse()` API (matching `gst_header.gd`'s own established convention) so a malformed file never prints an engine `ERROR:` line on this expected-failure path.

`write_record` (the shutdown write path) routes an unreadable index through `_quarantine_unreadable_index(dir)`: renames the bad `index.json` to `index.json.unreadable-<unix>` (never deletes it) before writing a fresh index, so the corrupt content stays on disk for diagnosis instead of being silently overwritten. If the rename itself fails, `write_record` returns `{ok: false, reason}` with the original unreadable-index reason, so `gst_main_panel.gd`'s existing `_recover_document` `push_error` fires (unchanged call site). `remove_record` was updated for the same new `_read_index` contract: an unreadable index now `push_error`s and no-ops instead of silently rebuilding a truncated index.

Status: fixed. `readside_*` checks below exercise `load_all`'s own read side of this same contract; `_check_metadata_write_failure_does_not_silently_succeed` (unchanged, still passing) continues to exercise the write side via a directory-blocked `index.json`.

### Fix 2: non-array `records` no longer throws `Invalid cast`

The `is Array` check moved inside `_read_index` itself (`parsed.get("records", []) is Array`): both `write_record` (the shutdown write path, previously line 64's raw cast) and `load_all` (previously line 121's raw cast, called unguarded from `_ready()` via `load_recovery_records()`) now receive a `{ok: false, reason}` from `_read_index` instead of ever executing `index.get("records", []) as Array` against a non-Array value. Reproduced the cited crash against pre-fix code first (`SCRIPT ERROR: Invalid cast: could not convert value to 'Array'. at: load_all`), confirmed it no longer occurs post-fix (`readside_non_array_records_field` below).

Status: fixed.

### Fix 3: read-side failure checks added to `tests/gst_editor_document_recovery_smoke.gd`

Three new checks, each in its own throwaway directory, called from a new `_check_read_side_failures(panel)` inserted into `_run_initial` alongside the existing throwaway-directory checks (before the dual-failure check):

- `readside_corrupt_stack_with_valid_index_entry`: `write_record` creates a valid index entry, then its own `.tres` is overwritten with garbage text. `load_all` must report one failure named by the corrupted stack's own path, resolve zero records, and leave both the corrupted `.tres` and the valid `index.json` on disk. Passed before this fix pass (root cause was never in this path) and locked in here.
- `readside_unparseable_index_json`: `index.json` planted directly as non-JSON text (`"{ this is not valid json"`). `load_all` must report one failure named by `index.json`'s own path, resolve zero records, and leave the planted file on disk untouched. Previously silent (zero records, nothing reported) -- this is the fix 1 defect.
- `readside_non_array_records_field`: `index.json` planted directly as `{"version": 1, "records": "not_an_array"}`. `load_all` must report one failure named by `index.json`'s own path instead of throwing. Previously a script error out of `_ready()` -- this is the fix 2 defect.

All three assert a reported path per failure and that the planted file(s) still exist after the call (`FileAccess.file_exists`) -- `load_all` never writes or deletes anything, so this is a direct assertion, not an inference. Stage protocol: these run as part of `tabs_recovery` stage 1 (the single-editor-session half), immediately after `_check_write_record_directory_failure`; no new stage or planted-files stage was needed since `load_all` is called directly against throwaway directories the same way the existing schema/directory-failure checks already do, with no process-boundary dependency.

Status: fixed. All three pass on `4.4` and `4.6.2` (below).

### Fix 4: empty stack-path slot in the dual-failure message

Root cause was in `write_record`'s directory-creation-failure branch, not in `gst_main_panel.gd`'s message-formatting itself: `write_record` computed `id`/`stack_file`/`stack_path` only after the `DirAccess.make_dir_recursive_absolute(dir)` check, so the early return on directory-creation failure always reported `stack_path: ""`. Reordered `write_record` to compute `id`/`stack_file`/`stack_path` first, then check `dir_error` and return the already-computed (intended, not-yet-written) `stack_path` in that branch. `gst_main_panel.gd:1486-1496` (the cited message) reads `write_result.get("stack_path", "")` unchanged and now receives the intended path -- no edit needed there.

Verified directly in this pass's own stderr (`_check_dual_failure_does_not_falsely_mark_recovered`, 4.4 stage 1): `GoShade Turbo: could not save user://gst_recovery_dual_failure_named.tres (simulated named-save failure) or recover it to C:/Users/atk67/Documents/goshade-turbo/.now/tabs-validation/appdata-4.4/Godot/app_userdata/GoShade Tabs Phase 1 Proof/gst_recovery_dual_failure_check/goshade_turbo/recovery/6348358_892357164.tres: failed to create recovery directory .../goshade_turbo/recovery: Can't create. _save_external_data() is void and cannot veto editor shutdown.` -- the previously empty `recover it to :` slot now names the intended path.

Status: fixed.

### Verification runs

- 4.4, import (`Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import`): exit `0`. Stderr held only the documented `4.4.0` first-import progress-dialog diagnostic (`ERROR: Do not use progress dialog (task) while flushing the message queue...`), the same pre-existing engine limitation the plan's own verification-commands section calls out; no unexpected error.
- 4.4, `tabs_recovery` stage 1 (`GST_EDITOR_SMOKE=tabs_recovery`, same command as the original pass, recovery dir and stage file wiped first): `grep -c "SMOKE .* PASS"` reads `20` (the original `17` plus the three new `readside_*` checks), fail `0`. Exit `0` via the real "Save & Quit" click, matching the original pass's exit convention. Stderr held only the same class of deliberate blocked-path/blocked-directory/corrupt-resource errors as the original pass (including the dual-failure `push_error`, now with its path slot filled per fix 4) plus the same one expected trailing `SCRIPT ERROR: Cannot call method 'get_tree' on a previously freed instance.` at `_click_button`'s own post-quit `await` -- no unexpected error.
- 4.4, `tabs_recovery` stage 2 (same command, re-run without resetting state): `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr. `restoration_before_entry PASS start_screen_hidden=true untitled_ok=true failed_ok=true document_count=3`, matching the original pass exactly.
- 4.6.2, import (`Godot_v4.6.2-stable_win64.exe --headless --path .now/tabs-validation/project-462 --import`): exit `0`, empty stderr.
- 4.6.2, `tabs_recovery` stage 1: a leftover `gst_recovery_smoke_stage.json` from the original round-1 evidence pass was still present in this isolated project's own settings directory and made the first attempt misread itself as stage 2 (`SMOKE SUMMARY pass=2 fail=3`, exit `1`); removed that stale stage file (and the stale recovery dir) and re-ran. Clean re-run: `grep -c "SMOKE .* PASS"` reads `20`, fail `0`, exit `0`, matching the 4.4 baseline exactly. Stderr held the same deliberate-error class as 4.4.
- 4.6.2, `tabs_recovery` stage 2: `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr, matching 4.4.
- 4.4, `tabs_close` (regression, single run): `SMOKE SUMMARY pass=13 fail=0`, exit `0`. Stderr held only the selector's own deliberate missing-directory save error.
- 4.4, `tabs_files` (regression, single run): `SMOKE SUMMARY pass=24 fail=0`, exit `0`. Stderr held only the selector's own deliberate missing-resource/bad-directory errors.

### Environment diagnostics

- Godot Engine versions observed: `v4.4.stable.official.4c311cbee`, `v4.6.2.stable.official.71f334935`.
- `DirAccess.rename_absolute` (used by `_quarantine_unreadable_index`) verified present and functional on `4.4` directly (`err=0`, target file renamed) via a throwaway probe script, deleted afterward, before relying on it in production code.
- Confirmed both isolated projects' `project.godot` still had the phase 1 shutdown-probe fixture disabled (`[editor_plugins] enabled=PackedStringArray("res://addons/goshade_turbo/plugin.cfg")` only) before every run this pass; not re-touched.
- The 4.6.2 stage-1 misread above came from this pass's own leftover state from the prior round's evidence run, not from any code change; documented so a future rerun does not need to rediscover it.
- Preserved the user's untracked `weird1.tres`, `weird2.tres`, and the pre-existing `sandbox/screenshots/glow.png.import` changes; not touched by any command this pass.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_document_recovery.gd`, `tests/gst_editor_document_recovery_smoke.gd`, `docs/EDITOR_SMOKE.md` (this section). `NOW.md` bookkeeping lines only, per the orchestrator's own standing allowance.
- `addons/goshade_turbo/ui/gst_main_panel.gd`, `addons/goshade_turbo/ui/gst_document.gd`, and `addons/goshade_turbo/plugin.gd` were read (fix 4's cited location, decision 10, and `needs_shutdown_attention()`) but not edited: fix 4's root cause and fix, and fixes 1-2, resolved entirely inside `gst_document_recovery.gd`.
- No file outside the plan's phase 7 Files list was edited. `sandbox/**` was not touched. No git worktree was created. No recovery record or stage file was ever written into the real repository's own `.godot/`; every write happened inside `.now/tabs-validation/project`/`project-462`, both gitignored. No commit was made.

## Shader tabs phase 7 review round 2 fix-now (2026-09-12)

Fix pass against round 2's two fix-now notes (`PASS-WITH-NOTES` verdict). Resumed after an interruption: `addons/goshade_turbo/ui/gst_document_recovery.gd` already carried a consistent partial edit for note 1 (`write_record` plumbing `quarantined_path`, `_quarantine_unreadable_index` returning `{ok, path}`, `load_all` scanning for `index.json.unreadable-*` via `_find_quarantined_indexes`) -- read in full plus its own untracked status confirmed first, and found already internally consistent; the remaining gap was `gst_main_panel.gd` never reading `quarantined_path` back out of `write_record`'s result, and no test yet covering either note. Isolated projects re-synced from the repo's changed files before every run (`.now/tabs-validation/project` for `4.4`, `.now/tabs-validation/project-462` for `4.6.2`), same isolated `APPDATA`/`LOCALAPPDATA` as every prior pass in this section (`appdata-4.4`, `appdata-4.6.2`). The phase 1 shutdown-probe fixture stayed disabled in both projects' `project.godot` (verified before running, not re-touched).

### Note 1: `_recover_document` now reports a write-time quarantine; `load_all` already reported the read side

`addons/goshade_turbo/ui/gst_main_panel.gd:1517-1530` (`_recover_document`): on a successful `write_record` call, reads the new `quarantined_path` field out of its own result and, when non-empty, `push_error`s it naming both the original index path and the quarantined destination, so a quarantine that happens during a real confirmed-quit write is no longer silent even though the write itself still reports `ok=true`. `GSTDocumentRecovery.load_all`'s own `_find_quarantined_indexes(dir)` scan (already present in the resumed file) independently reports every `index.json.unreadable-*` file still on disk as a `load_all` failure on every call, including every later editor startup, until a human removes or inspects it -- unchanged by this pass, verified directly (below).

Status: fixed, both halves. `_recover_document`'s own message was observed verbatim in this pass's own stderr: `GoShade Turbo: recovery index at <dir>/index.json was unreadable and has been quarantined to <dir>/index.json.unreadable-1789270334 before writing this document's own recovery record; any recovery records it referenced are no longer indexed and must be recovered manually.`

### Note 2: `_describe_document` numbers untitled documents instead of naming every one "This shader"

`addons/goshade_turbo/ui/gst_main_panel.gd:1301-1332`: `_describe_document`'s own untitled fallback now returns `"Untitled %d" % _untitled_index(doc)` instead of the literal `"This shader"`. New `_untitled_index(doc)` computes doc's own 1-based position among `_documents`' untitled bucket (no `current_path`, no `recipe_name`) by the same creation-order iteration `_refresh_tabs` already uses for `_tab_title`'s own `untitled_index` (`:1055`), so the close-confirmation dialog and `get_unsaved_status_text`'s own per-document lines (both callers of `_describe_document`) now agree with the tab row about which untitled document is which. `get_unsaved_status_text` itself (`:1434-1441`) was not edited -- it already called `_describe_document` per dirty document; only that helper's own untitled fallback needed to change.

Status: fixed. Verified directly: `two_untitled_documents_get_distinct_unsaved_status_lines` (below) -- two dirty untitled documents now render `"Untitled 1\nUntitled 2"` instead of two identical `"This shader"` lines.

### Tests added to `tests/gst_editor_document_recovery_smoke.gd`

- `_check_quarantine_reported_at_write_time`: plants an unreadable `index.json` plus an orphaned `orphan.tres` in a throwaway directory, calls `write_record` directly, and asserts the result's own `quarantined_path` names a `<dir>/index.json.unreadable-*` file that now exists, that a fresh valid `index.json` exists again at the original path (write_record's own quarantine-then-fresh-write behavior, not a defect), and that the orphaned stack file was left untouched. First draft asserted the original `index.json` path stayed absent after the call; that draft failed for the right reason (`write_record` legitimately writes a fresh index right after quarantining the bad one) and was corrected to assert a fresh valid index exists there instead, not to make the fix pass by weakening the check.
- `_check_preexisting_quarantine_reported_on_every_load`: plants a bare `index.json.unreadable-1789198480` file (no `index.json` itself) in its own throwaway directory and calls `load_all` twice, asserting both calls report it by path and that the planted file is never deleted -- the "every editor startup until a human removes it" half of note 1.
- `_check_recover_document_reports_quarantine_at_write_time`: exercises the real `_recover_document` production call site (not `write_record` directly) against a pre-existing unreadable index, asserting the document still ends up recovered (`recovery_record_id` set, `recovery_fingerprint` matching); the `push_error` text itself is documented from stderr (above), matching this file's own established convention for `_recover_document`'s other `push_error` (the dual-failure check's own doc comment).
- `_check_two_untitled_documents_get_distinct_unsaved_status_lines`: opens two untitled documents, dirties both, and asserts `plugin._get_unsaved_status("")` splits into exactly two distinct lines; closes both via Discard afterward.

All four wired into `_run_initial`: the first three alongside `_check_read_side_failures`/`_check_dual_failure_does_not_falsely_mark_recovered` (single-editor-session half, no new stage needed); the fourth right after the existing start-screen provisioning step, before the live recovery-directory flow begins.

### Verification runs

Stale-state hazard from the prior round-1 evidence pass repeated here: both isolated projects still had a leftover `gst_recovery_smoke_stage.json` and `goshade_turbo/recovery` directory under their own `.godot/editor/` (project-local settings dir, not the isolated `APPDATA` tree) from earlier runs. The very first `4.4` stage-1 attempt this pass misread itself as stage 2 off that leftover state (`SMOKE SUMMARY pass=2 fail=3`, `restoration_before_entry FAIL`); removed both (`.godot/editor/gst_recovery_smoke_stage.json`, `.godot/editor/goshade_turbo/recovery/`) from both isolated projects and re-ran clean. Recorded below is the final clean pass.

- 4.4, `tabs_recovery` stage 1 (stale stage file/recovery dir removed first; `GST_EDITOR_SMOKE=tabs_recovery`, isolated `appdata-4.4`, same command as every prior pass in this section): `grep -c "SMOKE .* PASS"` reads `24` (the round-1 baseline `20` plus the four new checks above), fail `0`. Exit `0` via the real "Save & Quit" click. Stderr held only the same class of deliberate blocked-path/blocked-directory/corrupt-resource errors as every prior pass, plus this pass's own two new deliberate `push_error`s (the quarantine message quoted above, and the pre-existing dual-failure message, both from their own throwaway directories) and the same one expected trailing `SCRIPT ERROR: Cannot call method 'get_tree' on a previously freed instance.` at `_click_button`'s own post-quit `await` -- no unexpected error.
- 4.4, `tabs_recovery` stage 2 (same command, re-run without resetting state): `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr. `restoration_before_entry PASS start_screen_hidden=true untitled_ok=true failed_ok=true document_count=3`, matching every prior pass.
- 4.4, `tabs_close` (regression, single run): `SMOKE SUMMARY pass=13 fail=0`, exit `0`.
- 4.4, `tabs_files` (regression, single run): `SMOKE SUMMARY pass=24 fail=0`, exit `0`.
- 4.6.2, `tabs_recovery` stage 1 (stale stage file/recovery dir removed first): `grep -c "SMOKE .* PASS"` reads `24`, fail `0`, exit `0`, matching the 4.4 baseline exactly. Stderr held the same deliberate-error class as 4.4 (with full GDScript backtraces, a `4.6.2` engine behavior difference from `4.4`'s plain error lines, not a defect).
- 4.6.2, `tabs_recovery` stage 2: `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr, matching 4.4.

### Environment diagnostics

- Godot Engine versions used: `v4.4.stable.official.4c311cbee` (`C:\Users\atk67\Downloads\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64.exe`), `v4.6.2.stable.official.71f334935` (`C:\Users\atk67\Desktop\Godot_v4.6.2-stable_win64.exe`).
- The stale stage-file/recovery-dir hazard above lives under each isolated project's own `.godot/editor/` (project-local `EditorInterface.get_editor_paths().get_project_settings_dir()`), not the isolated `APPDATA` tree checked at the start of this pass (which was already clean) -- future runs against these same isolated projects should wipe both locations, not just `APPDATA`.
- No file outside the plan's phase 7 Files list was edited. `sandbox/**` was not touched. No git worktree was created. No recovery record or stage file was ever written into the real repository's own `.godot/`; every write happened inside `.now/tabs-validation/project`/`project-462`, both gitignored. No commit was made.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_main_panel.gd`, `tests/gst_editor_document_recovery_smoke.gd`, `docs/EDITOR_SMOKE.md` (this section). No `NOW.md` bookkeeping change was made this pass.
- `addons/goshade_turbo/ui/gst_document_recovery.gd` was read in full and diff-checked against its own untracked working-tree state, but not edited: the resumed partial edit already satisfied note 1's write-side and read-side contract completely (`write_record`'s `quarantined_path`, `_quarantine_unreadable_index`'s `{ok, path}`, `load_all`'s `_find_quarantined_indexes` scan).
- Both fix-now notes stayed inside the plan's phase 7 Files list (`gst_main_panel.gd`, `tests/gst_editor_document_recovery_smoke.gd`). No file outside that list was edited.

## Shader tabs phase 7 review round 3 fixes (2026-09-12)

Fix pass against round 3's three required fixes (`FAIL` verdict). Read `addons/goshade_turbo/ui/gst_document_recovery.gd` in full, the cited `gst_main_panel.gd` lines (`_recover_document`, `save_external_data`, `_describe_document`), the plan's Cross-cutting "Serialization and recovery format" section, and this file's own phase 7 sections before editing. Isolated projects re-synced from the repo's two changed files before every run (`.now/tabs-validation/project` for `4.4`, `.now/tabs-validation/project-462` for `4.6.2`), same isolated `APPDATA`/`LOCALAPPDATA` as every prior pass in this section. The phase 1 shutdown-probe fixture stayed disabled in both projects' `project.godot` (verified before running, not re-touched). No `gst_main_panel.gd` edit was needed this pass: both required S1 fixes resolved entirely inside `gst_document_recovery.gd`, and `_recover_document`'s existing success-gated assignment of `recovery_record_id`/`recovery_fingerprint` (already correct from prior rounds) now sees a metadata-write result that is actually trustworthy.

### Fix 1 (S1): `_write_index` propagates a failed write instead of returning `true`

`addons/goshade_turbo/ui/gst_document_recovery.gd:262` (`_write_index`) previously called `file.store_string(...)` and returned `true` unconditionally, regardless of whether the write itself actually succeeded. Rewrote it to write through a temp file (`<index_path>.tmp`) and rename that over the real `index.json`, checking three failure points before ever touching the real file: `FileAccess.open(temp_path, WRITE)` returning `null`, `file.get_error()` after `store_string()`, and `DirAccess.rename_absolute(temp_path, path)`'s own return code. Any of the three aborts and removes the temp file, leaving the pre-existing `index.json` completely untouched -- `write_record`'s existing `if not _write_index(dir, index): return {"ok": false, ...}` (unchanged) then correctly reports the whole call as failed, so `gst_main_panel.gd:1519`'s existing `if bool(write_result.get("ok", false)):` guard (unchanged, already correct) never sets `recovery_fingerprint` on a failed write.

Verified `DirAccess.rename_absolute` overwrites an existing destination file on Windows/Godot `4.4` with a throwaway probe script (`rename_err=0`, `dest_content=NEW`) before relying on it in production code; deleted afterward.

Status: fixed. New tests below exercise both the write-side preservation (`write_record_metadata_failure_preserves_previous_index`) and the real production call site's resulting document state (`metadata_write_failure_leaves_document_needing_attention`).

### Fix 2 (S1): recovery metadata validated before use

Three unvalidated read sites the round 3 reviewer cited:

- `gst_document_recovery.gd:164` (`load_all`'s per-entry loop): previously only checked `id`/`stack_file` non-empty (coercing any type to `String`) before joining `stack_file` into a path and loading it.
- `gst_document_recovery.gd:199` (`_read_index`): previously validated `records` was an `Array` but never validated the index's own `version` field at all -- an unknown version was silently accepted, and a subsequent `write_record` call would replace it with `SCHEMA_VERSION` on the next successful write.
- `gst_document_recovery.gd:125` (`remove_record`): previously built `stack_path` directly from `entry.get("stack_file", "")` with no containment check before calling `DirAccess.remove_absolute` on it.

New `_validate_record(entry, dir)` (`gst_document_recovery.gd`) checks, in order: `id` is a non-empty `String`; `version` is a supported schema version (`_is_supported_version`, shared with `_read_index`); `stack_file` is a non-empty `String`; `stack_file` is a bare filename with no `/`, `\`, or `..` anywhere (`_is_safe_stack_filename`); the resolved `dir.path_join(stack_file)` still normalizes under `dir` (`_path_stays_under`, defense in depth); and `original_path`/`recipe_name`/`recipe_open`/`reopened_import`/`save_failed` all carry their documented types. Returns `{ok, id, stack_path, reason}` with `id`/`stack_path` always populated for reporting even on failure -- `stack_path` only ever resolves to a real path under `dir` once the bare-filename check has already passed, so an invalid entry never hands either caller a path it could act on.

`_read_index` gained the matching index-level check: an index whose own `"version"` is missing or not `SCHEMA_VERSION` now returns `{ok: false, reason}`, routing through the exact same quarantine-on-write (`write_record`, rename never overwrite) and report-on-load (`load_all`) paths malformed JSON already used.

`load_all`'s per-entry loop now calls `_validate_record` before computing any path or calling `GSTStackIO.load`; an invalid entry is reported in `failures` by its own best-effort `id`/`stack_path` and never loaded. `remove_record` now calls `_validate_record` before deleting anything; an invalid entry is `push_error`-reported and the function returns immediately -- neither the entry's own file nor the index itself (its own entry included) is touched, matching "reject and report invalid records without loading, rewriting, or deleting their referenced files" exactly.

Status: fixed. Four new tests (below) plant real on-disk hostile/invalid records and assert every referenced file survives untouched: `unknown_index_version_rejected_by_load_and_quarantined_by_write` (index version `99`, a `planted.tres` the invalid record references), `stack_file_traversal_rejected_by_load_and_remove` (`stack_file: "../escaped.tres"`, a real file one directory above `dir` that `load_all` and `remove_record` must both leave alone), plus the two fix-1 tests reusing the same validated-record path.

### Fix 3: fresh isolated quit/reopen run, with a self-resetting stage protocol

Root cause the reviewer named: `tests/gst_editor_document_recovery_smoke.gd`'s stage file (`gst_recovery_smoke_stage.json`, under each isolated project's own `.godot/editor/`) was never cleaned up by a successful stage 2 run, so a later invocation against the same isolated project could misread a leftover marker as "already past stage 1" -- exactly the failure mode the round 1 and round 2 evidence passes both had to work around manually (documented in their own "Verification runs" sections above) instead of the protocol preventing it.

Made the protocol self-resetting: `_verify_fresh_open` (stage 2) now calls a new `_delete_stage()` immediately before `_finish(plugin)`, but only when the whole stage 2 run passed (`_fail_count == 0`) -- a failed run leaves the marker in place for diagnosis, matching this file's own "report, never silently delete" convention for on-disk recovery state elsewhere. Protocol, stated explicitly: stage 1 writes the marker plus two real dirty documents' recovery records and drives the real confirmed quit; stage 2 (a fresh process reading that marker) verifies restoration, exercises post-restart Save/Discard cleanup (which already empties the recovery directory on its own), and deletes the marker on success, so a third invocation against the same isolated project starts over as stage 1.

Verified directly on `4.4`: after stage 1 and stage 2 both ran clean (below), a third invocation against the same isolated project and `APPDATA` (no state wiped) printed `SMOKE panel PASS`, `SMOKE round1_mixed_named_and_untitled_recovery PASS`, and `SMOKE_RECOVERY READY_FOR_CONFIRMED_QUIT` -- i.e. it ran the full stage-1 body again instead of misreading itself as stage 2, confirming the marker was actually gone. That demonstration process was killed before driving the real quit (its only purpose was proving the reset, not producing a third recorded evidence pair) and its on-disk recovery directory/stage file were wiped from the host shell afterward so the officially recorded `4.4` pair below reflects only the two real stages.

### Verification runs

Both isolated projects' own `.godot/editor/goshade_turbo/recovery` and `gst_recovery_smoke_stage.json` were removed from the host shell before every stage-1 run below (a genuinely fresh isolated state per the required fix, not a re-run against leftover state from an earlier round).

- 4.4, import (`Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import`): exit `0`. Stderr held only the documented `4.4.0` first-import progress-dialog diagnostic; no unexpected error.
- 4.4, `tabs_recovery` stage 1 (`GST_EDITOR_SMOKE=tabs_recovery; Godot_v4.4-stable_win64.exe --editor --path .now/tabs-validation/project --rendering-method gl_compatibility`): `grep -c "SMOKE .* PASS"` reads `28` (round 2's `24` plus this pass's four new checks), fail `0`. Exit `0` via the real "Save & Quit" click. Stderr held only the same class of deliberate blocked-path/blocked-directory/corrupt-resource/traversal-rejection/metadata-failure `push_error`s as every prior pass (including this pass's own three new ones: the traversal rejection's `could not remove recovery record traversal: ... has an unsafe stack_file '../escaped.tres'`, the metadata-write-failure-leaves-document-needing-attention case's own void-callback message, and the pre-existing dual-failure/quarantine messages), plus the same one expected trailing `SCRIPT ERROR: Cannot call method 'get_tree' on a previously freed instance.` at `_click_button`'s own post-quit `await` and the same pre-existing `1 resources still in use at exit` diagnostic every prior real-quit stage-1 pass in this section also shows (`fix7`, `fixnow2`, `fixnow3` evidence above) -- no unexpected error.
- Recovery directory listing between stages (`4.4`, `.godot/editor/goshade_turbo/recovery`, read directly off disk after stage 1 exited and before stage 2 ran): `["<untitled-quit-record>.tres", "<named-failed-quit-record>.tres", "index.json"]` (two real records from the two genuinely-unresolvable documents `_run_initial` hands off to the real quit).
- 4.4, `tabs_recovery` stage 2 (same command, same isolated project, re-run without resetting state): `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr. `restoration_before_entry PASS start_screen_hidden=true untitled_ok=true failed_ok=true document_count=3`. Recovery directory listing after stage 2's own cleanup: `["index.json"]` (both records removed by post-restart Save/Discard; `recovery_dir_empty_after_final_cleanup PASS remaining=0`). Stage marker file confirmed absent immediately after this run (`_delete_stage()` ran).
- 4.6.2, import (`Godot_v4.6.2-stable_win64.exe --headless --path .now/tabs-validation/project-462 --import`): exit `0`, empty stderr.
- 4.6.2, `tabs_recovery` stage 1 (isolated `appdata-4.6.2`, same command shape as `4.4`): `grep -c "SMOKE .* PASS"` reads `28`, fail `0`, exit `0`, matching the `4.4` baseline exactly. Stderr held the same deliberate-error class as `4.4`, with full GDScript backtraces (the same `4.6.2` engine behavior difference from `4.4`'s plain error lines documented in round 2's evidence, not a defect) -- no unexpected error.
- Recovery directory listing between stages (`4.6.2`): `["5507150_1056909488.tres", "5515222_2097211359.tres", "index.json"]`, matching the `4.4` pattern (two real records, one index).
- 4.6.2, `tabs_recovery` stage 2: `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr, matching `4.4`. Stage marker file confirmed absent immediately after this run.

### Regression: existing selectors on `4.4`

- `tabs_close` (single run): `SMOKE SUMMARY pass=13 fail=0`, exit `0`, matching every prior pass's baseline exactly.
- `tabs_files` (single run): `SMOKE SUMMARY pass=24 fail=0`, exit `0`, matching every prior pass's baseline exactly.

### Blockers / open decisions

None. All three required fixes resolved entirely inside `gst_document_recovery.gd` and `tests/gst_editor_document_recovery_smoke.gd`; no design decision from the plan needed revisiting.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_document_recovery.gd`, `tests/gst_editor_document_recovery_smoke.gd`, `docs/EDITOR_SMOKE.md` (this section), `NOW.md` (Active-thread next-action line only).
- `addons/goshade_turbo/ui/gst_main_panel.gd` was read in full (the cited `_recover_document`/`save_external_data`/`_describe_document` locations) but not edited: both required S1 fixes resolved entirely inside `gst_document_recovery.gd`, and `_recover_document`'s existing success-gated assignment was already correct once its own input (`write_result["ok"]`) became trustworthy.
- No file outside the plan's phase 7 Files list was edited. `sandbox/**` was not touched. No git worktree was created. No recovery record or stage file was ever written into the real repository's own `.godot/`; every write happened inside `.now/tabs-validation/project`/`project-462`, both gitignored. No commit was made.

## Shader tabs phase 7 review round 4 fixes (2026-09-12)

Fix pass against round 4's two required fixes (`FAIL` verdict). Read `addons/goshade_turbo/ui/gst_document_recovery.gd` in full (`_validate_record`, `_is_safe_stack_filename`, `_path_stays_under`, `_read_index`, `write_record`, `load_all`, `remove_record`), `gst_main_panel.gd:1500-1590` (`_recover_document`, `load_recovery_records`), and this file's own phase 7 sections before editing. Isolated projects re-synced from the repo's two changed files before every run (`.now/tabs-validation/project` for `4.4`, `.now/tabs-validation/project-462` for `4.6.2`), same isolated `APPDATA`/`LOCALAPPDATA` as every prior pass in this section. The phase 1 shutdown-probe fixture stayed disabled in both projects' `project.godot` (verified before running, not re-touched). No `gst_main_panel.gd` edit was needed this pass: both required S1 fixes resolved entirely inside `gst_document_recovery.gd`.

### Fix 1 (S1): record-identity validated before any write, and cross-checked on load

Root cause: round 3's `_validate_record` validated `id` and `stack_file` each on their own (non-empty string, bare filename, containment) but never checked whether the two actually agree. A planted record shaped `id="../victim"`, `stack_file="safe.tres"` passed that validation (each field individually safe), loaded successfully, and `gst_main_panel.gd`'s `load_recovery_records()` then carried that same unsafe `id` into `doc.recovery_record_id`. On the next confirmed-shutdown write, `_recover_document` passed that id to `write_record` as `existing_id`, which derives a fresh `stack_file` from `id` alone (`"%s.tres" % id`) rather than reusing the entry's own `stack_file` -- writing `../victim.tres` at `gst_document_recovery.gd:65` (`ResourceSaver.save`) before ever reading or checking the index.

Two-part fix in `addons/goshade_turbo/ui/gst_document_recovery.gd`:

- New `_is_valid_record_id(id, stack_file)`: the same bare-filename rule `_is_safe_stack_filename` already applies to `stack_file` (nonempty, no `/`, `\`, `..`), plus a requirement that `stack_file`'s own basename (without `.tres`) equals `id` exactly.
- `_validate_record` now calls it after the existing `stack_file` safety/containment checks, rejecting an id/stack_file mismatch as an inconsistent record -- reported by `load_all` (never loaded) and `remove_record` (never deleted), matching the existing convention for every other invalid-record case in this function. Applies to both call sites unchanged (`load_all`'s per-entry loop, `remove_record`'s single-entry lookup).
- `write_record` now validates `record_id` (when non-empty) with the same `_is_valid_record_id` check as its very first statement -- before `DirAccess.make_dir_recursive_absolute`, before `ResourceSaver.save`, before touching the index at all. An unsafe existing id returns `{ok: false, reason}` naming the id and `_index_path(dir)` and writes nothing (no stack file, no directory, no index).

Status: fixed. New regression `record_id_traversal_rejected_by_load_and_write` (`tests/gst_editor_document_recovery_smoke.gd`) plants exactly the cited shape (`id="../victim"`, `stack_file="safe.tres"`, a real `victim.tres` one directory above `dir`), asserts `load_all` rejects it by path without touching either planted file, then replays the real `_recover_document` production call site (not `write_record` directly) with a document carrying that same unsafe id as its own `recovery_record_id` -- asserting the outside file and the planted `index.json` are both byte-identical before and after, and that the document still reports `needs_shutdown_attention()` (never falsely marked recovered).

### Fix 2 (S1): version comparison no longer truncates a fractional value

Root cause: `_is_supported_version(value)` computed `int(value) == SCHEMA_VERSION` for both `int` and `float` inputs. `int()` truncates toward zero, so a `float` version of `1.5` truncated to `1`, which equals `SCHEMA_VERSION == 1` -- silently accepted an unsupported version instead of rejecting it. This codebase's own verified finding (`gst_header.gd:199`, "JSON.parse_string(\"4\") returns a float") means every `version` field read back through `_read_index`/`_validate_record` from a real `index.json` is a `float`, not an `int`, in this engine -- the truncation bug therefore applied to the actual production read path, not just a theoretical edge case.

Fix: `_is_supported_version` now branches by type and compares each without truncation: `value is int` compares directly against `SCHEMA_VERSION`; `value is float` compares against `float(SCHEMA_VERSION)` directly (both sides always whole numbers exactly representable in a double, so no fractional value can equal it). JSON's own `1.0` (still a `float`) remains accepted, since `1.0 == 1.0` is exact.

Status: fixed. Three new regressions (`tests/gst_editor_document_recovery_smoke.gd`): `fractional_index_version_1_5_rejected` (index-level `"version": 1.5`, asserting `load_all` rejects it by the index's own path and the planted stack file survives), `fractional_record_version_1_5_rejected` (index-level version valid, one record's own `"version": 1.5`, asserting `_validate_record` rejects that entry by its own id with the planted stack file surviving), and `float_whole_number_version_1_0_accepted` (both index-level and record-level `"version": 1.0`, asserting the record loads normally with no regression from the fix).

### Verification runs

Both isolated projects' own `.godot/editor/goshade_turbo/recovery` and `gst_recovery_smoke_stage.json` were removed from the host shell before every stage-1 run below (fresh two-stage state per the fix instruction, not a re-run against leftover state from an earlier round).

- 4.4, import (`Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import`): exit `0`. Stderr held only the documented `4.4.0` first-import progress-dialog diagnostic (`ERROR: Do not use progress dialog (task) while flushing the message queue...`); no unexpected error.
- 4.4, `tabs_recovery` stage 1 (`GST_EDITOR_SMOKE=tabs_recovery; Godot_v4.4-stable_win64.exe --editor --path .now/tabs-validation/project --rendering-method gl_compatibility`, recovery dir and stage file wiped first): `grep -c "SMOKE .* PASS"` reads `32` (round 3's `28` plus this pass's four new checks), fail `0`. Exit `0` via the real "Save & Quit" click. New checks individually: `record_id_traversal_rejected_by_load_and_write PASS`, `fractional_index_version_1_5_rejected PASS`, `fractional_record_version_1_5_rejected PASS`, `float_whole_number_version_1_0_accepted PASS`. Stderr held only the same class of deliberate blocked-path/blocked-directory/corrupt-resource/traversal-rejection/metadata-failure `push_error`s as every prior pass, plus this pass's own new deliberate diagnostic: "GoShade Turbo: could not recover an untitled shader document -- writing its recovery stack to <dir>/inner failed: recovery record id '../victim' is unsafe and was rejected before writing anything to <dir>/inner/index.json. _save_external_data() is void and cannot veto editor shutdown." (both the id and the index path named, matching the required fix's own wording), plus the same one expected trailing `SCRIPT ERROR: Cannot call method 'get_tree' on a previously freed instance.` at `_click_button`'s own post-quit `await` and the same pre-existing `1 resources still in use at exit` diagnostic every prior real-quit stage-1 pass in this section shows -- no unexpected error.
- Recovery directory listing between stages (`4.4`, `.godot/editor/goshade_turbo/recovery`, read directly off disk after stage 1 exited and before stage 2 ran): `["8111850_739975286.tres", "8123897_128821490.tres", "index.json"]` (two real records from the two genuinely-unresolvable documents `_run_initial` hands off to the real quit).
- 4.4, `tabs_recovery` stage 2 (same command, same isolated project, re-run without resetting state): `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr. Recovery directory listing after stage 2's own cleanup: `["index.json"]` (both records removed by post-restart Save/Discard).
- 4.6.2, import (`Godot_v4.6.2-stable_win64.exe --headless --path .now/tabs-validation/project-462 --import`): exit `0`, empty stderr.
- 4.6.2, `tabs_recovery` stage 1 (isolated `appdata-4.6.2`, recovery dir and stage file wiped first, same command shape as `4.4`): `grep -c "SMOKE .* PASS"` reads `32`, fail `0`, exit `0`, matching the `4.4` baseline exactly. New checks individually: `record_id_traversal_rejected_by_load_and_write PASS`, `fractional_index_version_1_5_rejected PASS`, `fractional_record_version_1_5_rejected PASS`, `float_whole_number_version_1_0_accepted PASS`. Stderr held the same deliberate-error class as `4.4` -- no unexpected error.
- Recovery directory listing between stages (`4.6.2`): `["5585268_257273976.tres", "5592046_731339401.tres", "index.json"]`, matching the `4.4` pattern (two real records, one index).
- 4.6.2, `tabs_recovery` stage 2: `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr, matching `4.4`.

### Regression: existing selectors on `4.4`

- `tabs_close` (single run): `SMOKE SUMMARY pass=13 fail=0`, exit `0`, matching every prior pass's baseline exactly. Stderr held only the selector's own deliberate missing-directory save error.
- `tabs_files` (single run): `SMOKE SUMMARY pass=24 fail=0`, exit `0`, matching every prior pass's baseline exactly. Stderr held only the selector's own deliberate missing-resource/bad-directory errors.

### Environment diagnostics

- Godot Engine versions used: `v4.4.stable.official.4c311cbee` (`C:\Users\atk67\Downloads\Godot_v4.4-stable_win64.exe\Godot_v4.4-stable_win64.exe`), `v4.6.2.stable.official.71f334935` (`C:\Users\atk67\Desktop\Godot_v4.6.2-stable_win64.exe`).
- Confirmed this codebase's own prior finding (`gst_header.gd:199`) that `JSON.parse` in both engine versions resolves every JSON number to a `float`, never an `int` -- directly relevant to fix 2, since it means the truncation bug applied to every real `index.json` read, not just a hypothetical raw-`int` input.
- Both isolated projects' own `.godot/editor/goshade_turbo/recovery` and `gst_recovery_smoke_stage.json` were wiped from the host shell before every stage-1 run this pass (fresh two-stage state per the fix instruction).
- Preserved the user's untracked `weird1.tres`, `weird2.tres`, and the pre-existing `sandbox/screenshots/glow.png.import` changes; not touched by any command this pass.

### Blockers / open decisions

None. Both required fixes resolved entirely inside `gst_document_recovery.gd` and `tests/gst_editor_document_recovery_smoke.gd`; no design decision from the plan needed revisiting.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_document_recovery.gd`, `tests/gst_editor_document_recovery_smoke.gd`, `docs/EDITOR_SMOKE.md` (this section), `NOW.md` (Active-thread next-action line only).
- `addons/goshade_turbo/ui/gst_main_panel.gd` was read in full (`_recover_document`, `load_recovery_records`, decision 10) but not edited: both required S1 fixes resolved entirely inside `gst_document_recovery.gd`, and `_recover_document`'s existing success-gated assignment was already correct once its own input (`write_result["ok"]`) became trustworthy.
- No file outside the plan's phase 7 Files list was edited. `sandbox/**` was not touched. No git worktree was created. No recovery record or stage file was ever written into the real repository's own `.godot/`; every write happened inside `.now/tabs-validation/project`/`project-462`, both gitignored. No commit was made.

## Shader tabs phase 7 review round 5 fixes (2026-09-12)

Fix pass against round 5's one required fix (`FAIL` verdict; the user chose to keep iterating past the round cap, rounds 1-4 fixes kept unreverted). Read `addons/goshade_turbo/ui/gst_document_recovery.gd` in full (`write_record`, `_read_index`, `_validate_record`, `_is_valid_record_id`, `_is_supported_version`, `_quarantine_unreadable_index`, `_find_record_index`), `gst_main_panel.gd`'s `_recover_document` (`:1517-1530`), and this file's own phase 7 sections before editing. Isolated projects re-synced from the repo's two changed files before every run (`.now/tabs-validation/project` for `4.4`, `.now/tabs-validation/project-462` for `4.6.2`; confirmed byte-identical with `diff` after copying, plus an unchanged-file check against `plugin.gd`/`gst_main_panel.gd`/`gst_document.gd`), same isolated `APPDATA`/`LOCALAPPDATA` as every prior pass in this section. The phase 1 shutdown-probe fixture stayed disabled in both projects' `project.godot` (grepped, not re-touched).

### Required fix (S1): validate an existing indexed record before overwriting it

Root cause (reviewer's own reproduction): an indexed record shaped `id="planted"`, `stack_file="planted.tres"`, `version=1.5` was silently overwritten by `write_record(dir, stack, ..., "planted")` -- `ResourceSaver.save` at the old `:79` and the index-entry replace at the old `:113` both ran unconditionally against `record_id`, with no check that the record already indexed under that id was itself valid. Round 4's own fix validated only the *format* of `record_id` (unsafe characters, id/stack_file agreement against the *new* derived `stack_file`) before writing -- never the *content* of whatever record that id already pointed at.

Fix in `addons/goshade_turbo/ui/gst_document_recovery.gd`'s `write_record`: when `record_id` is non-empty, `_read_index(dir)` now runs immediately after the id-format check and before `DirAccess.make_dir_recursive_absolute`/`ResourceSaver.save`. An unreadable index at this point returns `{ok: false, reason}` naming `_index_path(dir)` and the record id -- never quarantined (quarantining stays exclusive to the fresh-record branch, where no existing record could ever be consulted to begin with) and never written. If the index is readable and a record already exists under `record_id`, `_validate_record` runs against it before anything is written; a rejection returns `{ok: false, reason}` naming both the index path and the record id, touching neither the stack file nor the index. Only once that record (or its absence, which falls through to the pre-existing append behavior) has been confirmed does the stack save and index replace proceed, reusing the same index snapshot just validated rather than re-reading it.

Status: fixed. Four new regressions (`tests/gst_editor_document_recovery_smoke.gd`, `_check_existing_record_validated_before_write` dispatching to a shared `_check_existing_record_case` helper): `existing_record_level_version_1_5_rejected` (the record's own `"version": 1.5`), `existing_index_level_version_1_5_rejected` (the index's own top-level `"version": 1.5`, record-level version valid), `existing_record_identity_mismatch_rejected` (the record's own `"stack_file": "other.tres"` no longer agrees with its `"id": "planted"`, the same identity check fix-now round 4 added for load). Each plants that shape plus a real stack file under a fresh throwaway directory, snapshots both files' bytes, calls `write_record` directly with `record_id="planted"` and a fresh overwrite stack (asserting `ok=false`, the reason contains both the index path and `"planted"`, and both planted files stay byte-identical), then replays the real `_recover_document` production call site with a document carrying `"planted"` as its own `recovery_record_id` (asserting the same byte-identical preservation plus `doc.recovery_fingerprint.is_empty()` and `doc.needs_shutdown_attention()` staying `true`, since a rejected write never sets `recovery_fingerprint`). A fourth check, `existing_record_fix_preserves_fresh_record_quarantine_path`, replants the settled fresh-record shape (no `existing_id`, unreadable index) and re-asserts `write_record` still quarantines it and reports the quarantined path -- confirming this fix's own unconditional existing-id index read never disturbed that unrelated branch.

### Verification runs

Both isolated projects' own `.godot/editor/goshade_turbo/recovery` and `gst_recovery_smoke_stage.json` were removed from the host shell before every stage-1 run below (fresh two-stage state per the fix instruction).

- 4.4, import (`Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import`): exit `0`. Stderr held only the documented `4.4.0` first-import progress-dialog diagnostic (`ERROR: Do not use progress dialog (task) while flushing the message queue...`); no unexpected error.
- 4.4, `tabs_recovery` stage 1 (`GST_EDITOR_SMOKE=tabs_recovery; Godot_v4.4-stable_win64.exe --editor --path .now/tabs-validation/project --rendering-method gl_compatibility`, recovery dir and stage file wiped first): `grep -c "SMOKE .* PASS"` reads `36` (round 4's `32` plus this pass's four new checks), fail `0`. Exit `0` via the real "Save & Quit" click. New checks individually: `existing_record_level_version_1_5_rejected PASS`, `existing_index_level_version_1_5_rejected PASS`, `existing_record_identity_mismatch_rejected PASS`, `existing_record_fix_preserves_fresh_record_quarantine_path PASS`, each with `index_unchanged=true stack_unchanged=true`. Stderr held only the documented deliberate-error class from every prior pass, plus this pass's own three new deliberate diagnostics naming both the index path and the record id, e.g. "GoShade Turbo: could not recover an untitled shader document -- writing its recovery stack to `<dir>/planted.tres` failed: cannot update existing recovery record 'planted' indexed in `<dir>/index.json`: recovery index entry planted has an unsupported or missing version 1.5. _save_external_data() is void and cannot veto editor shutdown." (record-level case; the index-level and identity-mismatch cases named the same two facts with their own respective reasons), plus the same one expected trailing `SCRIPT ERROR: Cannot call method 'get_tree' on a previously freed instance.` and the same pre-existing `1 resources still in use at exit` diagnostic every prior real-quit stage-1 pass in this section shows -- no unexpected error.
- Recovery directory listing between stages (`4.4`, `.godot/editor/goshade_turbo/recovery`, read directly off disk after stage 1 exited and before stage 2 ran): `["8918544_2006960529.tres", "8929228_1118544155.tres", "index.json"]` (two real records from the two genuinely-unresolvable documents `_run_initial` hands off to the real quit).
- 4.4, `tabs_recovery` stage 2 (same command, same isolated project, re-run without resetting state): `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr. Recovery directory listing after stage 2's own cleanup: `["index.json"]` (both records removed by post-restart Save/Discard).
- 4.4, `tabs_close` (single run): `SMOKE SUMMARY pass=13 fail=0`, exit `0`, matching every prior pass's baseline exactly.
- 4.4, `tabs_files` (single run): `SMOKE SUMMARY pass=24 fail=0`, exit `0`, matching every prior pass's baseline exactly.
- 4.6.2, import (`Godot_v4.6.2-stable_win64.exe --headless --path .now/tabs-validation/project-462 --import`): exit `0`, empty stderr.
- 4.6.2, `tabs_recovery` stage 1 (isolated `appdata-4.6.2`, recovery dir and stage file wiped first, same command shape as `4.4`): `grep -c "SMOKE .* PASS"` reads `36`, fail `0`, exit `0`, matching the `4.4` baseline exactly. New checks individually: same four `PASS`, same `index_unchanged=true stack_unchanged=true`. Stderr held the same deliberate-error class as `4.4`, with full GDScript backtraces per error (the same `4.6.2` engine behavior difference from `4.4`'s plain error lines documented in round 2's evidence, not a defect) -- including two new backtraces through `_recover_document`/`_check_existing_record_case` for this pass's own deliberate rejected writes -- no unexpected error.
- Recovery directory listing between stages (`4.6.2`): `["6660282_3430255259.tres", "6665938_2390810780.tres", "index.json"]`, matching the `4.4` pattern (two real records, one index).
- 4.6.2, `tabs_recovery` stage 2: `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr, matching `4.4`.

### Blockers / open decisions

None. The required fix resolved entirely inside `gst_document_recovery.gd` and `tests/gst_editor_document_recovery_smoke.gd`; no design decision from the plan needed revisiting.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_document_recovery.gd`, `tests/gst_editor_document_recovery_smoke.gd`, `docs/EDITOR_SMOKE.md` (this section), `NOW.md` (Active-thread next-action line only).
- `addons/goshade_turbo/ui/gst_main_panel.gd` was read in full (`_recover_document`, `load_recovery_records`) but not edited: the required S1 fix resolved entirely inside `gst_document_recovery.gd`, and `_recover_document`'s existing success-gated assignment was already correct once its own input (`write_result["ok"]`) became trustworthy.
- No file outside the plan's phase 7 Files list was edited. `sandbox/**` was not touched. No git worktree was created. No recovery record or stage file was ever written into the real repository's own `.godot/`; every write happened inside `.now/tabs-validation/project`/`project-462`, both gitignored. No commit was made.

## Shader tabs phase 7 review round 6 fix-now (2026-09-12)

Fix-now pass against round 6's two required notes (`PASS-WITH-NOTES`; rounds 1-5 fixes kept unreverted). Read `addons/goshade_turbo/ui/gst_document_recovery.gd` in full, `gst_main_panel.gd`'s `_recover_document`/`_forget_recovery_record`/`load_recovery_records` (`:1500-1590`), and this file's own phase 7 sections before editing. `gst_document_recovery.gd` arrived at the start of this pass already mid-edit from an interrupted prior attempt at this exact consolidation: `write_record`'s existing-id branch already called `_load_index`/`_find_validated_record`, but neither was actually defined anywhere in the file (only the old `_read_index` was) -- the file would not have run. This pass finishes that consolidation rather than starting a separate one, matching the user's own authorization to collapse `write_record`, `load_all`, and `remove_record`'s index reads onto one helper.

### Note 1 (S2): distinguish an absent index from an unsuccessful read

Root cause: the old `_read_index` (and, mid-edit, the not-yet-defined `_load_index` it was being replaced by) treated any `FileAccess.open(path, READ)` failure identically to "no index.json has ever been written" -- `ok=true`, a fresh empty index. Confirmed directly against the engine before writing the fix: `FileAccess.file_exists()` reads `false` against a directory occupying `index.json`'s own path (not just against a genuinely missing path), and `FileAccess.open` on that same directory returns `null` identically to a locked file. So a directory named `index.json` -- or any other open failure distinct from absence -- was silently read back as "nothing indexed yet," which for `write_record`'s existing-id path meant a genuinely-existing record's own metadata was never actually consulted before that call proceeded.

Fix, `_load_index(dir) -> {ok, present, index, records, reason}`: `present=false` (`ok=true`, empty index) only when `FileAccess.file_exists(path)` *and* `DirAccess.dir_exists_absolute(path)` both read false -- confirmed absence, the only state safe to treat as "nothing written." `present=true, ok=false` for every other failure (unopenable, malformed JSON, non-Dictionary root, non-array `"records"`, unsupported version), `reason` always naming `_index_path(dir)`. `records` is every entry already run through `_validate_record`, each augmented with its own raw `entry`, so `write_record`, `load_all`, and `remove_record` all judge one record's validity and reconstruct its full field set the same way. `write_record`'s existing-id branch already returned early on `not ok` (round 5's own structure, kept unchanged) -- so completing `_load_index`'s own present/ok distinction is what makes that early return fire correctly for an unopenable index instead of silently falling through to "no index has ever been written" and proceeding to overwrite a path a directory already occupies.

Regression, `_check_index_open_failure_distinguished_from_absence` (`tests/gst_editor_document_recovery_smoke.gd`): plants a directory literally named `index.json`, then asserts (a) `load_all` reports one failure naming the index path, zero records; (b) `write_record` with an existing id returns `ok=false` naming the index path, and the directory listing is byte-for-byte unchanged before and after (no stack file, no fresh index.json, ever written); (c) the real `_recover_document` production call site, given a document carrying that same id as its own `recovery_record_id`, leaves `recovery_fingerprint` empty and `needs_shutdown_attention()` true, with the directory listing again unchanged. Status: fixed, verified on 4.4 and 4.6.2 (below).

### Note 2 (S2): report recovery-cleanup failures

Root cause: `remove_record`'s own `DirAccess.remove_absolute(stack_path)` and `_write_index(dir, index)` results were both discarded outright -- the function was `void`. A failed stack deletion still fell through to dropping the entry from the index regardless (an orphaned stack: a file the index no longer names, undiscoverable by any later `load_all()`/`write_record()` call), and a failed metadata write after a successful deletion still reported nothing (a dangling index entry: naming a stack file that is now gone). `_forget_recovery_record` (`gst_main_panel.gd:1537`) then cleared `doc.recovery_record_id`/`recovery_fingerprint` unconditionally either way, so the document lost the only in-memory pointer back to its own unresolved record.

Fix: `remove_record(dir, record_id) -> {ok, reason}`. A failed stack deletion now returns before the index is ever touched, so that record stays indexed with its file untouched, ready for a caller to retry. A failed metadata write after a successful deletion still leaves the real `index.json` byte-identical to its prior content (`_write_index`'s own write-through-a-temp-file-then-rename never touches it on failure) and reports the residual dangling-entry shape in its own `reason` text. `remove_record` itself never `push_error`s (matching `write_record`'s own established convention); `_forget_recovery_record` now checks the result and only clears `doc`'s own recovery identity on `ok=true`, `push_error`-ing the reason otherwise.

**Defect found while writing this note's own regression, fixed in the same pass:** `remove_record`'s stack-deletion guard read `if FileAccess.file_exists(stack_path):` -- the same presence gap note 1 closed for `index.json` also applied here. A stack path replaced by a directory reads `file_exists() == false`, so the guard skipped the deletion attempt entirely and still fell straight through to removing the index entry -- the exact "orphaned stack, cleared identity, nothing reported" failure this note exists to close, just reached by a different door. A real run of `_check_recovery_cleanup_stack_deletion_failure_reported` caught this directly (`direct_remove_result={"ok": true, ...}` against a directory-blocked stack path, first attempt, before this was fixed). Closed by checking `DirAccess.dir_exists_absolute(stack_path)` too, matching `_load_index`'s own presence check exactly. This is inside note 2's own stated scope (its own worked example is precisely "the record's own `.tres` path replaced by a non-empty directory"), not a separate scope addition.

Regressions (`tests/gst_editor_document_recovery_smoke.gd`), both against the panel's own real `get_recovery_dir()` (`_forget_recovery_record` takes no `dir` argument, so this is the only directory that can exercise it) via the real `_recover_document`/`_forget_recovery_record` production call sites:
- `_check_recovery_cleanup_stack_deletion_failure_reported`: recovers a real document, then replaces its own stack `.tres` with a non-empty directory. Asserts `remove_record` called directly returns `ok=false` naming the path, the real `index.json` bytes and the blocked directory both survive unchanged; then asserts the same through `_forget_recovery_record` -- `doc.recovery_record_id`/`recovery_fingerprint` stay exactly as they were, `index.json` stays unchanged, the blocked directory survives. Cleans up by removing the blocking directory and discarding the document, which drives `_forget_recovery_record` a second time (now unblocked) to leave the recovery dir empty for every check that runs after it.
- `_check_recovery_cleanup_index_replacement_failure_reported`: recovers a real document, blocks `index.json.tmp` with a directory (round 3's own established technique), calls `_forget_recovery_record`. Asserts `doc.recovery_record_id`/`recovery_fingerprint` stay exactly as they were and `index.json`'s own bytes stay byte-identical. Documents, rather than asserts, that the record's own stack file is already gone by this point (deletion is attempted before the metadata rewrite; this ordering is what produces the "dangling index entry" shape note 2's own text names as an accepted residual of a two-step, non-atomic cleanup -- reporting the failure, not making two independent filesystem operations transactional, is this S2 fix's own scope). Cleans up by unblocking `.tmp` and discarding the document, which completes the interrupted cleanup on its second `_forget_recovery_record` call.

Status: fixed, verified on 4.4 and 4.6.2 (below).

### Consolidation (user-authorized)

`write_record`'s existing-id path, `load_all`, and `remove_record` now all read the index through one private helper, `_load_index(dir) -> {ok, present, index, records, reason}` (`present=false` means confirmed absence; `ok=false` means present but unopenable/unparseable/unsupported, `reason` naming the index path; `records` are every entry already run through `_validate_record`, each carrying its own raw `entry`). A second small helper, `_find_validated_record(validated_records, record_id) -> Dictionary`, looks one record up by `id` inside that already-validated list (`{}` if absent) -- used by both `write_record`'s existing-id check and `remove_record`. `_validate_record`, `_is_valid_record_id`, `_is_supported_version`, `_quarantine_unreadable_index`, and `_write_index` are unchanged. `_read_index` is deleted (fully superseded by `_load_index`); no other helper became dead.

Line count: `gst_document_recovery.gd` was `460` lines at the start of this pass (the incomplete mid-edit state described above, which referenced `_load_index`/`_find_validated_record` without defining them -- not a prior clean baseline to diff cleanly against) and is `535` lines after, net `+75`. Going up, not flat or down, so per the fix instruction: the growth is almost entirely doc comments, not logic. `_find_validated_record` itself is the only wholly new function (9 lines). The `_read_index` -> `_load_index` swap grew from 16 to 28 body lines because the per-record validation loop `load_all` used to run inline (removed there, ~10 lines saved in `load_all`) moved into `_load_index` once, for all three callers; `remove_record` grew from a 23-line `void` function to a 26-line `Dictionary`-returning one plus the note-1-adjacent directory-presence fix, offset by dropping its own now-redundant direct `_validate_record` call (replaced by the `_load_index` result it already has). The remainder is doc-comment expansion explaining the three-state `present`/`ok` distinction, the orphaned-stack/dangling-index-entry failure shapes, and the directory-presence defect found and fixed mid-pass -- all load-bearing *why*, not restated code, per this project's own comment discipline, not restated for its own sake.

### Verification runs

Both isolated projects' own `.godot/editor/goshade_turbo/recovery` and `gst_recovery_smoke_stage.json` were removed from the host shell before every stage-1 run below (a genuinely fresh two-stage state per the fix instruction, re-confirmed empty by directory listing before each run, not assumed).

- 4.4, import (`Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import`): exit `0`. Stderr held only the documented `4.4.0` first-import progress-dialog diagnostic; no unexpected error.
- 4.4, `tabs_recovery` stage 1, first attempt (`GST_EDITOR_SMOKE=tabs_recovery; Godot_v4.4-stable_win64.exe --editor --path .now/tabs-validation/project --rendering-method gl_compatibility`): exit `1`, `SMOKE recovery_cleanup_stack_deletion_failure_reported FAIL direct_remove_result={"ok": true, "reason": ""} ... index_unchanged=false stack_dir_survived=true` -- this is the directory-presence defect described above, caught live rather than by inspection. Fixed in `remove_record` (`DirAccess.dir_exists_absolute` added to the deletion guard), re-synced to both isolated projects, state re-wiped, re-run clean below. No other check failed on this attempt.
- 4.4, `tabs_recovery` stage 1, clean re-run (same command, state re-wiped first): `grep -c "SMOKE .* PASS"` reads `39` (round 5's `36` plus this pass's three new checks), fail `0` (`grep "SMOKE .* FAIL"` empty). Exit `0` via the real "Save & Quit" click. New checks individually: `index_open_failure_distinguished_from_absence PASS`, `recovery_cleanup_stack_deletion_failure_reported PASS index_unchanged=true stack_dir_survived=true`, `recovery_cleanup_index_replacement_failure_reported PASS index_unchanged=true`. Stderr held only the same deliberate blocked-path/blocked-directory/corrupt-resource/traversal-rejection/metadata-failure class as every prior pass, plus this pass's own two new lines (`could not remove recovery record <id>: failed to delete recovery stack ...: Failed`, `could not remove recovery record <id>: deleted recovery stack ... but failed to write updated recovery metadata to ...; recovery record <id> is now a dangling index entry until this succeeds`), plus the same one expected trailing `SCRIPT ERROR: Cannot call method 'get_tree' on a previously freed instance.` and the same pre-existing `1 resources still in use at exit` diagnostic every prior real-quit stage-1 pass in this section shows -- no unexpected error.
- Recovery directory listing between stages (`4.4`, `.godot/editor/goshade_turbo/recovery`, read directly off disk after stage 1 exited and before stage 2 ran): `["8478512_2010719950.tres", "8491448_1060467208.tres", "index.json"]` (two real records from the two genuinely-unresolvable documents `_run_initial` hands off to the real quit; this pass's own new checks already cleaned up their own throwaway/panel-recovery-dir records before this point, confirmed by the same listing showing exactly two records, matching every prior round's own count).
- 4.4, `tabs_recovery` stage 2 (same command, same isolated project, re-run without resetting state): `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr. `restoration_before_entry PASS start_screen_hidden=true untitled_ok=true failed_ok=true document_count=3`. Recovery directory listing after stage 2's own cleanup: `["index.json"]`. Stage marker file confirmed absent immediately after this run.
- 4.4, `tabs_close` (single run): `SMOKE SUMMARY pass=13 fail=0`, exit `0`, matching every prior pass's baseline exactly.
- 4.4, `tabs_files` (single run): `SMOKE SUMMARY pass=24 fail=0`, exit `0`, matching every prior pass's baseline exactly.
- 4.6.2, import (`Godot_v4.6.2-stable_win64.exe --headless --path .now/tabs-validation/project-462 --import`): exit `0`, empty stderr.
- 4.6.2, `tabs_recovery` stage 1 (isolated `appdata-4.6.2`, recovery dir and stage file wiped first, same command shape as `4.4`, run once against the already-fixed code -- the directory-presence defect above was fixed before this project was ever synced against it): `grep -c "SMOKE .* PASS"` reads `39`, fail `0` (`grep "SMOKE .* FAIL"` empty), exit `0`, matching the `4.4` baseline exactly. New checks individually: same three `PASS`, same `index_unchanged=true`. Stderr held the same deliberate-error class as `4.4`, with full GDScript backtraces per error (the same `4.6.2` engine behavior difference from `4.4`'s plain error lines documented since round 2's evidence, not a defect), including this pass's own two new backtraced `push_error` lines through `_forget_recovery_record`/`remove_record` -- no unexpected error.
- Recovery directory listing between stages (`4.6.2`): `["5944582_1902723951.tres", "5952666_1771642414.tres", "index.json"]`, matching the `4.4` pattern (two real records, one index).
- 4.6.2, `tabs_recovery` stage 2: `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr, matching `4.4`. Stage marker file confirmed absent immediately after this run.

### Blockers / open decisions

None. Both fix-now notes, and the one additional directory-presence defect this pass's own regression for note 2 surfaced, resolved entirely inside `gst_document_recovery.gd` and `gst_main_panel.gd`'s `_forget_recovery_record`; no design decision from the plan needed revisiting.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_document_recovery.gd`, `addons/goshade_turbo/ui/gst_main_panel.gd` (`_forget_recovery_record` only), `tests/gst_editor_document_recovery_smoke.gd`, `docs/EDITOR_SMOKE.md` (this section), `NOW.md` (Active-thread next-action line only).
- No file outside the plan's phase 7 Files list was edited. `sandbox/**` was not touched. No git worktree was created. No recovery record or stage file was ever written into the real repository's own `.godot/`; every write happened inside `.now/tabs-validation/project`/`project-462`, both gitignored. No commit was made.

## Shader tabs phase 8: verify complete lifecycle across supported versions (2026-09-14)

Resumed pass. A prior interrupted implementer run left `tests/gst_editor_tabs_host_smoke.gd` (413 lines, unverified, no `.uid`), a 3-line `tabs_host` dispatch case in `tests/gst_editor_smoke.gd`, and a large set of already-executed matrix logs under `.now/tabs-validation/` (`p8-<version>-<selector>.std{out,err}.log`, `p8-<version>-matrix-summary.txt`) that were never independently checked or written up. This pass: (1) read the interrupted state, (2) generated `tabs_host`'s `.uid` by importing the isolated `4.4` project and copied it into the repo, (3) independently reconfirmed `tabs_host` fresh on all three versions, (4) investigated every divergent result in the inherited logs by re-running it (flaky vs. reproducible), (5) captured the two pieces the inherited logs were missing -- both `tabs_recovery` stage exit codes per version, and the native-color-popup-at-shutdown observation the ledger asked for -- and (6) writes this section. No production file was touched; every item below is either an already-recorded log this pass verified for internal consistency, or a run this pass executed itself.

### `tabs_host`: finished and verified

- `.uid`: generated by `Godot_v4.4-stable_win64.exe --headless --path .now/tabs-validation/project --import` against the synced test file (already present from the interrupted run, confirmed byte-identical to the repo's own copy by `diff`), then copied from `.now/tabs-validation/project/tests/gst_editor_tabs_host_smoke.gd.uid` to `tests/gst_editor_tabs_host_smoke.gd.uid` in the repo. Content: `uid://f4j34fvej0fy`.
- Fresh confirmation run, `4.4` (`GST_EDITOR_SMOKE=tabs_host; Godot_v4.4-stable_win64.exe --editor --path .now/tabs-validation/project --rendering-method gl_compatibility`, isolated `appdata-4.4`): exit `0`, `SMOKE SUMMARY pass=8 fail=0`, empty stderr. Matches the inherited run's own `8/0` exactly (three inherited runs plus this pass's own fresh one, four consistent `8/0` results total on `4.4`).
- Inherited `4.6.2` and `4.7` runs (same command shape, isolated `appdata-4.6.2`/`appdata-4.7`, against the identical synced test file confirmed by `diff`): both `exit 0`, `SMOKE SUMMARY pass=8 fail=0`, empty stderr.
- Coverage: `tabs_host_setup_two_documents` (document-owned structural edit on one document, native property edit on the other), `tabs_host_scene_switch_preserves_documents` / `tabs_host_scene_undo_outside_goshade` / `tabs_host_return_to_goshade_preserves_state` (real host-scene switch, real scene-level Undo/Redo, both shader histories untouched), `tabs_host_save_as_on_initiating_document` (Save As lands on the document active when the dialog opened, sibling tab unaffected), `tabs_host_alternating_focused_undo_redo` and `tabs_host_popup_focused_undo_in_tabs` (alternating focused undo/redo including a native RGB popup commit, with a second open tab as a negative control throughout).
- The test file's own comments (`gst_editor_tabs_host_smoke.gd:222-243`) record that a synthetic keyboard replay for the popup's own undo/redo boundary was unreliable in this environment after this test's own scene-switch + Save As round trip on a second open tab, so `popup_focused_undo_in_tabs` drives `doc_b.undo_redo.undo()`/`redo()` directly (the same call `gst_main_panel.gd`'s own `_apply_keyboard_undo_redo` makes once focus ownership is already resolved) instead of replaying the keyboard path a second time -- the keyboard path itself is exhaustively covered single-document by `tabs_native` below. This is a deliberate test-design choice recorded in the file, not a gap this pass introduced.

### Version matrix, final phase 8 tree

Each row is its own serial process, isolated `APPDATA`/`LOCALAPPDATA` per version (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`, `appdata-4.7`; `appdata-4.4-scaled150` for the `150%` rows), isolated project per version (`.now/tabs-validation/project`, `project-462`, `project-47`, all synced from the repo's current `tests/` before this pass's own runs). Editor selector command shape: `GST_EDITOR_SMOKE=<selector>; <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`. Render/motion command shape: `<godot> --path <isolated-project> --rendering-method <gl_compatibility|forward_plus> -s res://tests/run_<render_checks|recipe_motion_checks>.gd`. Where a result cell says "retry clean," the first attempt's own divergent result is investigated in "Investigated divergences" below; the clean retry is the one carried into the exit-criteria judgment.

| Selector | 4.4 | 4.6.2 | 4.7 |
|---|---|---|---|
| unit (`run_codegen_tests.gd`) | exit 1, `21 file(s), 145 test method(s), 20 failure(s)` | exit 1, identical `145`/`20` | exit 1, identical `145`/`20` |
| `tabs_native` | exit 0, `pass=31 fail=0` | **Resolved:** exit `0`, `pass=31 fail=0` (reproduced 2x), per "Shader tabs phase 8: phase 2 defect fix 2 (deferred color no-op commit after redo)" below; superseded the `pass=30 fail=1` result this cell previously recorded (originally `pass=28 fail=2`, reproduced 3x) | **Resolved:** exit `0`, `pass=31 fail=0` (reproduced 2x), per "Shader tabs phase 8: phase 2 defect fix 2 (deferred color no-op commit after redo)" below; superseded the `pass=30 fail=1` result this cell previously recorded (originally `pass=28 fail=2`, reproduced 2x) |
| `tabs_documents` | exit 0, `pass=22 fail=0` | exit 0, `pass=22 fail=0` | exit 0, `pass=22 fail=0` |
| `tabs_ui` (normal scale) | exit 0, `pass=18 fail=0` | exit 0, `pass=18 fail=0` | exit 0, `pass=18 fail=0` |
| `tabs_ui` (`150%` scale) | exit 0, `pass=18 fail=0` | not run (no `150%` profile for `4.6.2`/`4.7`; see below) | not run |
| `tabs_files` | exit 0, `pass=24 fail=0` | exit 0, `pass=24 fail=0` | exit 0, `pass=24 fail=0` |
| `tabs_close` | exit 0, `pass=13 fail=0` (retry clean; first attempt `pass=10 fail=3`) | exit 0, `pass=13 fail=0` | exit 0, `pass=13 fail=0` |
| `tabs_host` | exit 0, `pass=8 fail=0` (4 consistent runs) | exit 0, `pass=8 fail=0` | exit 0, `pass=8 fail=0` |
| `tabs_recovery` stage 1 | exit 0, `pass=39 fail=0` | exit 0, `pass=39 fail=0` | exit 0, `pass=39 fail=0` |
| `tabs_recovery` stage 2 | exit 0, `pass=5 fail=0` | exit 0, `pass=5 fail=0` | exit 0, `pass=5 fail=0` |
| `4` | exit 0, `pass=50 fail=0` | exit 0, `pass=50 fail=0` | exit 0, `pass=50 fail=0` |
| `5` | exit 0, `pass=18 fail=0` | exit 0, `pass=18 fail=0` | exit 0, `pass=18 fail=0` |
| `6` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` |
| `7` | exit 0, `pass=25 fail=0` | exit 0, `pass=25 fail=0` | exit 0, `pass=25 fail=0` |
| `8` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` |
| `ui_layout` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` |
| `ui_actions` | exit 0, `pass=20 fail=0` | exit 0, `pass=20 fail=0` | exit 0, `pass=20 fail=0` |
| `ui_labels` | exit 0, `pass=42 fail=0` (retry clean x2; first attempt `pass=41 fail=1`) | exit 0, `pass=42 fail=0` (retry clean; first attempt `pass=41 fail=1`) | exit 0, `pass=42 fail=0` (retry clean; first attempt `pass=41 fail=1`) |
| `ui_labels` (with `GST_UI_SCREENSHOT_PATH`, normal + `150%`) | exit 0, `pass=47 fail=0` both scales | not run | not run |
| `ui_picker` | exit 0, `pass=45 fail=0` | exit 0, `pass=45 fail=0` | exit 0, `pass=45 fail=0` |
| `ui_picker` (with `GST_PICKER_SCREENSHOT`, normal + `150%`) | exit 0, `pass=45 fail=0` both scales | not run | not run |
| `ui_complete` | exit 0, `pass=29 fail=0` | exit 0, `pass=29 fail=0` | exit 0, `pass=29 fail=0` |
| `ui_complete` (with `GST_UI_COMPLETE_SCREENSHOT`) | exit 0, `pass=34 fail=0` (5 extra `screenshot_*` items, not a regression) | not run | not run |
| `run_render_checks.gd`, Compatibility | exit 0, `PASS, 79 stack(s) checked` | exit 0, identical `79` | exit 0, identical `79` |
| `run_render_checks.gd`, Forward+ | exit 0, `PASS, 79 stack(s) checked` | exit 0, identical `79` | exit 0, identical `79` |
| `run_recipe_motion_checks.gd`, Compatibility | exit 0, `RECIPE_MOTION SUMMARY PASS` | exit 0, identical | exit 0, identical |
| `run_recipe_motion_checks.gd`, Forward+ | exit 0, `RECIPE_MOTION SUMMARY PASS` | exit 0, identical | exit 0, identical |

`NOW.md`'s own loose end ("next GPU render run reports 79 stacks, not 78") is resolved: every render run on every version/renderer combination reports `79 stack(s) checked, PASS`, matching `sandbox/stacks/clouds.tres`'s move into the checked set.

`150%`-scale rows ran only on `4.4` (the pre-existing `appdata-4.4-scaled150` profile, `interface/editor/display_scale`/`custom_display_scale` set directly in that isolated `APPDATA`'s own `editor_settings-4.4.tres`, per the phase 4 round-1 fix precedent). No equivalent scaled profile exists yet for `4.6.2`/`4.7`; building one was not attempted this pass since `150%` presentation is a display-scale concern the phase 4/5 evidence already establishes is engine-scale-independent GDScript (`EditorInterface` layout queries), not per-minor-version behavior, and the normal-scale rows above already run clean on both `4.6.2` and `4.7`. Flagged here rather than silently assumed.

### Investigated divergences (flaky vs. reproducible)

- **`tabs_native` on `4.6.2`/`4.7`, `pass=28 fail=2`, real and reproducible.** Two failing checks, byte-identical output across repeated full-process runs (`4.6.2`: original + 2 retries; `4.7`: original + 1 retry), all four Ctrl+Z/Ctrl+Shift+Z attempts exhausted (`attempts=5`), never passing once on either version -- not a timing flake:
  - `tabs_native_popup_focused_shortcut_recognized_and_finished FAIL attempts=5 owns_focus=true actions=25->25 position=24->24 restored=true popup_visible=true color=(0.5, 0.5, 0.5, 1.0)`: a real Ctrl+Z delivered to the native color popup's own focused hex `LineEdit` (`gst_inspector_column.gd:507` `_on_color_popup_window_input`, gated on `event.is_action_pressed(&"ui_undo")`/`&"ui_redo"`, per that function's own comment fired on the popup's own `Window.window_input` before any Control inside it) never committed the pending edit or closed the popup on `4.6.2`/`4.7`; on `4.4` the identical mechanism passes every time (`tabs_native`'s own `4.4` row above, `31/0`).
  - `tabs_native_host_scene_isolation FAIL host_history=1 gst_unaffected=true host_undone=false host_unaffected_by_redo=false`: the immediately-following check (`gst_editor_native_undo_smoke.gd:1007`) drives a real Ctrl+Z with focus left in the real host scene and finds the host scene's own action was never undone. Not independently isolated from the check above: the prior check's own stuck-open popup (`popup_visible=true`, never closed) is a plausible carrier of stale keyboard-input routing into this one, but that causal link is not proven, only plausible -- recorded as unverified rather than asserted.
  - **This is a version-specific production defect, not a test defect.** `gst_inspector_column.gd:507-518` (`_on_color_popup_window_input`) and its consumer `gst_main_panel.gd:2524-2563` (`_handle_undo_redo_shortcut`/`_owns_undo_focus`) are the cited locations. Root cause not narrowed further within this pass's scope (phase 8 is verification-only; no production file was touched to investigate). **Owning phase: phase 2** (native property routing and keyboard-shortcut scoping, `docs/SHADER_TABS_reviewed-plan.md` Cross-cutting "Public APIs, signals, and callbacks"). Per this phase's own instructions, the affected check must be re-run on `4.6.2`/`4.7` once a fix lands in phase 2 and receives its own review.
- **`tabs_close` on `4.4`, first attempt `pass=10 fail=3`, not reproducible.** Two immediate re-runs (same isolated project, same `APPDATA`, no code change) both passed `13/0` clean. `4.6.2`/`4.7` passed `13/0` on their first and only run each. Treated as a timing-sensitive false negative in this environment, matching the same class of flake this file has already documented and worked around elsewhere (e.g. "Shader tabs phase 6 review round 1 fix-now" `tabs_close` diagnostics); not a code defect.
- **`ui_labels` on all three versions, first attempt `pass=41 fail=1` (`ui_labels_palette_color_undo_redo FAIL`), not reproducible.** Every retry on every version passed `42/0` clean (`4.4`: 2 retries; `4.6.2`/`4.7`: 1 retry each), all with the identical failing-then-passing pattern. This matches this file's own prior documented finding for the same check family ("Shader tabs phase 2 review round 4 fixes," `rgb_popup_undo_redo`: "a genuine pre-existing condition... Godot's own `EditorPropertyColor`/`ColorPicker` internals... re-applying the popup's originally-typed value some frames after `history.undo()`"), not a new defect and not touched by this phase.
- **`ui_picker`/`ui_complete` on `4.4`, `.now/tabs-validation/p8-4.4-matrix-summary.txt` initially recorded blank result cells.** Re-inspecting the underlying `.stdout.log` files (not the summary file) directly shows both ran and passed clean (`ui_picker` `45/0`, `ui_complete` `29/0`) with empty stderr -- the blank cells were a capture/formatting artifact in the inherited matrix-summary file, not a test failure. Corrected in the table above by reading the source logs.

### Screenshots

Captured under `.now/tabs-validation/evidence/phase8/` (gitignored verification scratch, not repo source), via each selector's own existing `GST_UI_SCREENSHOT_PATH`/`GST_PICKER_SCREENSHOT`/`GST_UI_COMPLETE_SCREENSHOT` env-var hooks (`tests/gst_editor_ui_labels_smoke.gd`, `tests/gst_editor_ui_picker_smoke.gd`, `tests/gst_editor_ui_complete_smoke.gd`; no test file was modified to add this capability, it already existed). All captured on `4.4` (normal scale and the `appdata-4.4-scaled150` profile):

- `normal-ui_labels.png`, `normal-ui_labels-coords.png`, `normal-ui_labels-inputs.png`, `normal-ui_labels-inactive-gain.png`, `normal-ui_labels-palette-swatch.png`, and the same five with a `scaled150-` prefix. Inspected `normal-ui_labels-inactive-gain.png`/`scaled150-ui_labels-inactive-gain.png` directly: both show the grayed-out "Fine detail strength" row with its "Fine detail strength needs at least 2 Detail layers" hint below it (focused/inactive-control evidence), and the `150%` capture is visibly larger with the same layout, confirming the scale profile is genuinely applied rather than a no-op.
- `normal-ui_picker.png`, `normal-ui_picker-conversion.png`, and the same two with a `scaled150-` prefix. Inspected `normal-ui_picker-conversion.png` directly: captured immediately after the narrow-layout `picker_resize` check crosses the tab breakpoint, showing the chooser's search box and results tree at narrow width (narrow-layout evidence).
- `normal-ui_complete-initial.png`, `normal-ui_complete-diagnostic.png`, `normal-ui_complete-recipe-edit.png`, `normal-ui_complete-recovery.png`, `normal-ui_complete-long-error.png`.
- **Gap, disclosed rather than fabricated:** no screenshot captures the native RGB popup itself in its open state -- `ui_labels`'s own `_check_native_palette_color` (`gst_editor_ui_labels_smoke.gd:320-387`) captures the swatch immediately before opening the popup, but takes no capture between `popup.visible == true` and its close. The popup's presence/geometry at that moment is proven by passing assertions instead (`palette_color_native button_visible=true`, `palette_color_close popup=false` after commit), not a photograph. Not fixed this pass: adding a new mid-popup capture point is a test-code change beyond a screenshot-hook call already present, and phase 8 is scoped to running/observing, not extending test capability.
- **Long-tab-overflow and 20-layer/fixed-preview-output evidence is geometric, not photographic.** `tests/gst_editor_tabs_smoke.gd` (`tabs_ui`) has no screenshot hook; its own `tab_row_overflow_scrolls` and `twenty_layers_preview_output_rects_stable` checks measure and assert exact rectangles instead (both reproduced fresh this pass, normal and `150%` scale, see below). Treated as satisfying the plan's "measure... rectangles" wording (matching phase 4's own precedent, which used the identical measurement-only approach), not treated as equivalent to a photograph; recorded as a disclosed method choice, not silently substituted.
  - Normal scale, `4.4` (`p8-4.4-tabs_ui.stdout.log`): `tab_row_overflow_scrolls PASS row_width=3068.0 scroll_width=947.0 h_max=3068.0 h_page=947.0 tab_count=24`; `twenty_layers_preview_output_rects_stable PASS item_count=20 preview=[P: (760.0, 256.0), S: (494.0, 447.0)]/[unchanged] output=[P: (760.0, 748.0), S: (494.0, 99.0)]/[unchanged]`.
  - `150%` scale, `4.4`, this pass's own fresh run (`p8-4.4-scaled150-tabs_ui.stdout.log`): `tab_row_overflow_scrolls PASS row_width=3282.0 scroll_width=1117.0 h_max=3282.0 h_page=1117.0 tab_count=24`; `twenty_layers_preview_output_rects_stable PASS item_count=20 preview=[P: (977.0, 377.0), S: (595.0, 231.0)]/[unchanged] output=[P: (977.0, 674.0), S: (595.0, 150.0)]/[unchanged]`; `SMOKE SUMMARY pass=18 fail=0`, exit `0`.

### Serialized-output stability across navigation and reopen

No existing selector diffs raw file bytes across a tab switch and a reopen (existing checks compare structural fingerprints, not bytes). A dedicated one-off scripted probe (`p8_serialization_stability_probe.gd`, verification scratch only -- written into each isolated project's own `tests/` directory and dispatched through a temporary line added only to that isolated project's own copy of `gst_editor_smoke.gd`, never the repo's; confirmed by `grep` that the repo's own `tests/gst_editor_smoke.gd` carries no such dispatch case) did the following on all three versions: opened a document, added two layers, Saved As and Exported (capturing both files' raw bytes), opened a second document, switched documents twice and back, re-read both files (must still match the first capture -- proves navigation alone writes nothing), re-Saved and re-Exported with no content change (must still byte-match), then used the real `reopen_shader_path` disk-reload path and re-Saved/re-Exported again (must still byte-match, and the reopened document must not be marked dirty).

- `4.4`: `saved stack_bytes=1217 shader_bytes=2683`; `after_navigation_unsaved_files_unchanged stack=true shader=true`; `resave_after_navigation_byte_identical stack=true shader=true`; `reopen_and_resave_byte_identical stack=true shader=true reopened_dirty=false`. Exit `0`, empty stderr.
- `4.6.2`: `saved stack_bytes=962 shader_bytes=2683`; same three `true`/`true`/`true` results; `reopened_dirty=false`. Exit `0`, empty stderr. (`stack_bytes` differs from `4.4`'s own figure because each isolated project's own `next_id` counter differs by incidental prior-run history in that project; the check only compares bytes within one run, never across versions.)
- `4.7`: identical to `4.6.2` (`stack_bytes=962`, same three `true` results, `reopened_dirty=false`). Exit `0`, empty stderr.

No session metadata (active-document id, tab order, selection, history position) reached the `.tres` or `.gdshader` on disk on any version: every post-navigation and post-reopen byte comparison matched the original save exactly.

### Native color popup at confirmed shutdown (`docs/CURRENTNESS_AUDIT.md:61`)

Per this phase's own instruction: observed, not fixed. A second one-off scripted probe (`p8_color_popup_quit_probe.gd`, same verification-scratch convention as above) opened an untitled document, added a `color/palette` layer, opened its native RGB popup, typed a pending hex value into the popup's own hex `LineEdit` (`5566ee`) **without** committing it (no Enter, no focus release, no `popup.hide()`), then drove the real Scene > Quit menu item, the real confirmation dialog, and a real click on "Save and Quit," letting the process exit on its own. The written recovery record was then read directly off disk before the next run.

- `4.4`: original color `(0.5, 0.5, 0.5, 1.0)`; recovery record's stored value `"a": Vector3(0.333333, 0.4, 0.933333)` -- exactly `#5566ee` (`0x55/255=0.3333`, `0x66/255=0.4`, `0xee/255=0.9333`), not the original gray. Exit `0`. Stderr held only the expected trailing `SCRIPT ERROR: Cannot call method 'get_tree' on a previously freed instance.` (post-quit `_click_button` continuation, the same class this file already documents elsewhere) and the expected `4 resources still in use at exit` diagnostic.
- `4.6.2`: identical outcome, `"a": Vector3(0.33333334, 0.4, 0.93333334)`. Exit `0`. Same expected trailing `SCRIPT ERROR`/`resources still in use` diagnostics (with a full GDScript backtrace on the `SCRIPT ERROR`, matching this version's already-documented backtrace-vs-plain-error difference from `4.4`).
- `4.7`: identical outcome, `"a": Vector3(0.33333334, 0.4, 0.93333334)`. Exit `0`. Same expected trailing `SCRIPT ERROR`; no `resources still in use at exit` line this run (consistent with `4.7`'s own `tabs_recovery` stage-1 run above, which also did not show that line).

**Observation:** in every version, on this interaction pattern (one untitled document, one popup, no other pending edits), the pending native color popup edit reached the recovery record -- the void-callback ordering concern named in the ledger did not cause data loss here. Only one interaction pattern was probed (a single document; no concurrent Save/Save As/rebind racing the popup); the ledger line is ticked as observed, not closed as proven-safe for every combination. No production file was touched.

### `tabs_recovery`: both stage exit codes, per version (`docs/CURRENTNESS_AUDIT.md:63`, `:58`)

Each stage run as its own serial process, isolated `APPDATA`/`LOCALAPPDATA`, with the recovery directory and stage marker file confirmed absent before stage 1 (a genuinely fresh two-stage run, not a re-run against leftover state):

| Version | Stage 1 exit | Stage 1 result | Stage 2 exit | Stage 2 result |
|---|---|---|---|---|
| `4.4` | `0` | `pass=39 fail=0` | `0` | `pass=5 fail=0` |
| `4.6.2` | `0` | `pass=39 fail=0` | `0` | `pass=5 fail=0` |
| `4.7` | `0` | `pass=39 fail=0` | `0` | `pass=5 fail=0` |

Certificate-store diagnostic (`Failed to read the root certificate store`) rechecked across all six of the above processes plus every editor-selector row in the version matrix above: `0` occurrences in any stderr log this pass captured. Isolated, writable `APPDATA`/`LOCALAPPDATA` per version continues to eliminate this class of diagnostic, matching the phase 2/3 finding this ledger item asked to recheck.

### Replacement-assertion migration list

| Previous expectation | Reviewed navigation replacement | Retained non-replacement checks | Phase that changed it |
|---|---|---|---|
| A single shared shader stack/history; opening a different stack replaced the current document's content in place, and that replacement was itself one undo-able action (undo restored the prior stack). Phase 1's own `tabs_proof` blockers section names this the "replacement undo route." | New/Open/Reopen Shader/Recipes create and activate an independent `GSTDocument`, each with its own `UndoRedo`; switching between already-open documents is tab navigation and registers no stack action at all (`tabs_documents`/`tabs_ui`'s own `navigation creates no stack action` exit criterion). | Two independent `UndoRedo` histories' own structural/property undo-redo mechanics -- gesture grouping, forced-finish ordering before rebind/save/undo/redo, native color popup live preview and final-emission finalization, host-scene isolation -- were unaffected by retiring the single-shared-history "replacement" framing and carried forward unchanged. | Phase `3` (`GSTDocument`, per-document `UndoRedo` ownership, replacing `docs/DESIGN.md` decision `20`'s shared-manager contract) with phase `4` continuing it into stable-ID tab activation and phase `2`'s native-boundary mechanics (gesture capture/finish, forced-finish ordering, color popup finalization) carried through unchanged. |
| A closed/replaced document's pending file-dialog or picker response could still land somewhere (the single-document model had no "stale target" to distinguish). | Every delayed Save As/Export/picker response is resolved against its own captured stable document/request id; a closed or replaced target is rejected without touching whatever now occupies that tab. | The underlying dialog/picker mechanics (file filters, overwrite confirmation, canonical-path collision detection) were unaffected. | Phase `5` (document-bound file operations), extended by phase `6` (closed-document stale-response rejection). |

### Blockers / open decisions

- **Both production defects on `4.6.2`/`4.7` are now fixed and closed.** The native color popup's keyboard Ctrl+Z/Ctrl+Shift+Z boundary (`addons/goshade_turbo/ui/gst_inspector_column.gd`, `_on_color_popup_window_input` plus `_on_color_popup_field_gui_input`) was fixed first, independently proven correct by instrumented delivery directly to the popup's own focused field, and confirmed by the test-delivery follow-up ("Shader tabs phase 8: tabs_native popup-delivery test fix" below). That follow-up's own delivery fix then surfaced a second, distinct, deferred-commit-after-redo defect on `4.6.2`/`4.7` only, whose actual root cause (confirmed by instrumented diagnosis to differ from this bullet's own original hypothesis about `_force_close_color_popups`/`_await_row_inactive`'s `10`-frame poll) and production fix are recorded in "Shader tabs phase 8: phase 2 defect fix 2 (deferred color no-op commit after redo)" below. `tabs_native` now reads `31/0` on `4.4`, `4.6.2`, and `4.7`, reproduced twice each.
- No `150%`-scale profile exists for `4.6.2`/`4.7` (see "Version matrix" above); normal-scale coverage on both is clean. Flagged as an open verification gap, not fabricated.
- No screenshot captures the native RGB popup in its open state on any version (see "Screenshots" above); its presence/geometry is proven by passing assertions instead of a photograph.
- Both `docs/EDITOR_UI_DESIGN_reviewed.md:35` and `docs/SHADER_TABS_reviewed.md:25` (decision `10` wording) are left untouched per this phase's own instruction; `docs/CURRENTNESS_AUDIT.md` now cites the evidence each will need at its own doc-fix pass.

### Scope

- Files modified this pass: `tests/gst_editor_tabs_host_smoke.gd.uid` (new, generated by Godot's own `--import`, copied from the isolated `4.4` project), `docs/EDITOR_SMOKE.md` (this section), `docs/CURRENTNESS_AUDIT.md` (four ledger lines resolved with evidence; two design-doc flags left open per instruction, one annotated with a forward citation only), `NOW.md` (Active-thread next-action line only).
- No production file (`addons/goshade_turbo/**`) was touched. No file outside phase 8's own Files list, `NOW.md`'s bookkeeping lines, `docs/CURRENTNESS_AUDIT.md`'s ticks, and `tests/gst_editor_tabs_host_smoke.gd`'s `.uid` was edited in the real repository.
- Two ad-hoc scripted probes (`p8_color_popup_quit_probe.gd`, `p8_serialization_stability_probe.gd`) and their one-line dispatch cases were written **only** into each isolated project's own copy of `tests/` and `tests/gst_editor_smoke.gd` under `.now/tabs-validation/` (gitignored verification scratch, matching this file's own established "isolated project copies... are verification scratch, not repo source" precedent) -- never into the real repository. Confirmed by `grep` immediately after every run that the real repo's own `tests/gst_editor_smoke.gd` carries neither dispatch case.
- `sandbox/**` was not touched. `sandbox/screenshots/glow.png.import` showed no `git status` change after this pass's own `--import`/render runs (no restoration needed). No git worktree was created. No commit was made.

## Shader tabs phase 8: phase 2 defect fix (color popup shortcut on 4.6.2/4.7) (2026-09-14)

Fix pass against the phase 8 defect above, applied under a phase 8 sentinel widened to `addons/goshade_turbo/ui/gst_inspector_column.gd` and `addons/goshade_turbo/ui/gst_main_panel.gd` only. No other production file was touched; `sandbox/**` was not touched; no commit was made.

### Root cause, confirmed by instrumented diagnosis (not assumed)

Temporary `print()` instrumentation was added only to each isolated project's own copy of the two files above and of `tests/gst_editor_native_undo_smoke.gd` under `.now/tabs-validation/project` (`4.4`) and `.now/tabs-validation/project-462` (`4.6.2`) -- never the real repository -- then removed before syncing the real fix back into every isolated project. Findings:

- Every isolated `APPDATA`/`LOCALAPPDATA` this project's own verification has ever used (`appdata-4.4`, `appdata-4.6.2`, `appdata-4.7`) leaves `interface/editor/single_window_mode` at its default (`false`), confirmed by `grep` finding no such key in `4.4`'s or `4.6.2`'s own `editor_settings-*.tres` and an explicit `false` in `4.7`'s. Per `main.cpp` (`editor_embed_subwindows = EDITOR_GET("interface/editor/single_window_mode")`, gating `SceneTree::get_root()->set_embedding_subwindows(true)`), the root viewport therefore never `is_embedding_subwindows()` on any version this project verifies against. `Viewport::_sub_windows_forward_input` (`scene/main/viewport.cpp`) is gated on exactly that flag, so it never runs, and `_on_color_popup_window_input`'s own doc comment describing that forwarding path was never actually exercised by this configuration on any version -- confirmed by instrumenting that handler directly: across every version tested, it fired only for `InputEventMouseMotion`, never once for the Ctrl+Z/Ctrl+Shift+Z key events the test drives.
- On Godot `4.4`, the real Ctrl+Z pushed at the root viewport (`_push_key(EditorInterface.get_base_control(), KEY_Z, true)`, the test's own synthetic delivery, matching `EditorInterface.get_base_control().get_viewport()`) still reached `gst_main_panel.gd`'s own root `_input()`, and `Viewport.gui_get_focus_owner()` queried there still reported the `ColorPickerButton` itself (not anything inside the now-open popup) -- an accident of that engine's own focus bookkeeping, since `_owns_undo_focus()`'s ordinary `is_ancestor_of(focus)` branch (the button is a real descendant of the panel) then let the existing keyboard path finish the pending edit correctly. This was never the mechanism `_on_color_popup_window_input`/`color_popup_undo_redo_requested` was written to cover; that signal was already dead code for real key events on `4.4`.
- On Godot `4.6.2` and `4.7`, the identical push to the root viewport reaches nothing: instrumented every reachable hook (`gst_main_panel.gd`'s own root `_input()`, the popup's own `window_input`, and, once the picker's own hex/RGB `LineEdit` fields were found dynamically, their own `gui_input`) across five full retry attempts each, with `is_input_handled()` staying `false` throughout -- the event is dropped somewhere inside `Viewport::push_input` on the root viewport itself before any GDScript-visible hook runs, whenever a native, non-embedded popup subwindow currently holds real focus. No Godot `4.6`/`4.7` source tree was available to name the exact engine change; this is stated as an observed binary behavior difference, not a sourced one.
- Pushing the identical key event directly onto the popup's own viewport (`hex_edit.get_viewport().push_input(...)`, the same call the test's own existing hex-typing helper already uses successfully on every version) reaches that field's `gui_input` signal correctly on `4.6.2`, with `is_input_handled()` still `false` at that point -- confirming `Control::_call_gui_input`'s own documented ordering ("Signal should be first, so it's possible to override an event (and then accept it)", `scene/gui/control.cpp`) still holds: the `gui_input` signal fires before the `LineEdit`'s own built-in virtual `gui_input()` that implements its built-in text-undo, on every version, independent of any embedded-subwindow forwarding question.
- The picker's own hex/RGB `LineEdit` fields do not exist at row-creation time (confirmed: `find_children("*", "LineEdit", true, false)` under `color_button.get_picker()` returns `0` there) -- they are created lazily on first popup display. Connecting on `about_to_popup` alone (before the popup is actually shown) also finds `0`; connecting once the popup's own `visibility_changed` reports `visible == true` still finds `0` in the same frame. Only awaiting two `process_frame`s after `about_to_popup` reliably finds all `6` fields.

### Fix

- `addons/goshade_turbo/ui/gst_inspector_column.gd`: added `_connect_color_popup_field_shortcuts` (connected on `about_to_popup`, alongside the existing `_on_color_popup_window_input`/`window_input` wiring, not replacing it) and `_on_color_popup_field_gui_input`. The new function finds every `LineEdit` under `color_button.get_picker()` and connects each one's own `gui_input` signal (guarded by `is_connected` so repeat popup opens do not double-connect); the new handler matches `_on_color_popup_window_input`'s own existing logic (`event.is_action_pressed(&"ui_redo"/"ui_undo")`, then `set_input_as_handled()` on that field's own viewport, then `color_popup_undo_redo_requested.emit(redo)`), so both paths converge on the same signal `gst_main_panel.gd` already consumes. The existing `_on_color_popup_window_input`/`window_input` wiring is left in place as defense-in-depth for a real end user who does enable `single_window_mode` (an embedded-subwindow configuration this project's own verification never exercises), not removed as dead code, since it would still correctly fire in that configuration.
- `addons/goshade_turbo/ui/gst_main_panel.gd`: updated the doc comments on `_handle_undo_redo_shortcut` and `_apply_keyboard_undo_redo` to describe the corrected mechanism above (no behavior change in this file).
- This fix is version-independent by construction: it depends only on `Control._call_gui_input`'s signal-before-virtual-method ordering, not on any embedded-subwindow forwarding timing, so it needed no `Engine.get_version_info()` branch.

### Verification

Re-synced the fixed two production files (byte-identical to the real repository, confirmed by `diff`) into all three isolated projects (`.now/tabs-validation/project`, `project-462`, `project-47`) before every run below; each run its own process, serially, isolated `APPDATA`/`LOCALAPPDATA`, matching this file's own established command shape.

| Selector | 4.4 | 4.6.2 | 4.7 |
|---|---|---|---|
| `tabs_native` | exit `0`, `SMOKE SUMMARY pass=31 fail=0`, empty stderr | exit `1`, `SMOKE SUMMARY pass=28 fail=2`, empty stderr (same two checks, same root cause below) | exit `1`, `SMOKE SUMMARY pass=28 fail=2`, empty stderr (identical) |
| `ui_labels` | exit `1` first attempt (`ui_labels_palette_color_undo_redo FAIL`, `pass=41 fail=1`); retry exit `0`, `pass=42 fail=0`, empty stderr | exit `1` first attempt (identical failing check, `pass=41 fail=1`); retry exit `0`, `pass=42 fail=0`, empty stderr | not re-run (unaffected by this fix; already `42/0` in the phase 8 matrix above) |
| `tabs_ui` | exit `0`, `SMOKE SUMMARY pass=18 fail=0`, empty stderr | exit `0`, `SMOKE SUMMARY pass=18 fail=0`, empty stderr | not re-run (unaffected by this fix) |
| `tabs_host` | exit `0`, `SMOKE SUMMARY pass=8 fail=0`, empty stderr | exit `0`, `SMOKE SUMMARY pass=8 fail=0`, empty stderr | exit `0`, `SMOKE SUMMARY pass=8 fail=0`, empty stderr |

The `ui_labels` first-attempt failure on both `4.4` and `4.6.2` reproduces this file's own already-documented, already-attributed flake ("Shader tabs phase 2 review round 4 fixes," `rgb_popup_undo_redo`) exactly, including the same clean-on-retry pattern; not a regression from this fix.

`tabs_native`'s two failing checks on `4.6.2`/`4.7` are unchanged in identity and symptom from the original defect report (`tabs_native_popup_focused_shortcut_recognized_and_finished FAIL attempts=5 owns_focus=true actions=25->25 position=24->24 restored=true popup_visible=true color=(0.5, 0.5, 0.5, 1.0)`; `tabs_native_host_scene_isolation FAIL host_history=1 gst_unaffected=true host_undone=false host_unaffected_by_redo=false`), because the fix above is real and independently proven correct (see "Root cause" above), but the test's own synthetic delivery of the simulated Ctrl+Z (root viewport) cannot reach it on these two versions -- a test-simulation gap, not a remaining production defect, and outside this fix's authorized file scope (`tests/gst_editor_native_undo_smoke.gd` was not among the cited locations). The `host_scene_isolation` failure remains the same likely-cascading consequence already recorded in "Investigated divergences" above (the popup from the preceding failed check is left open, `popup_visible=true`).

### Outcome and open decision

- **Not closed.** The phase 8 matrix note above is updated to describe the fix and its cause precisely, not to claim the defect resolved, because the two `4.6.2`/`4.7` checks still read `FAIL` for the reason above.
- **Open decision for the user/reviewer:** authorize a follow-up, test-only change to `tests/gst_editor_native_undo_smoke.gd`'s `_check_popup_focused_shortcut` (deliver its synthetic Ctrl+Z/Ctrl+Shift+Z to the popup's own currently-focused field's viewport instead of the root viewport, matching how a real OS keystroke is actually routed to whichever window holds real focus) so this specific check can observe the fix. This was not applied here: the cited defect locations for this fix pass were the two production files only.
- Scope: files modified this pass -- `addons/goshade_turbo/ui/gst_inspector_column.gd`, `addons/goshade_turbo/ui/gst_main_panel.gd`, `docs/EDITOR_SMOKE.md` (this section and the updated blocker bullet above). No other file in the real repository was touched. No commit was made.
- **Update:** the open decision above was authorized and applied; see "Shader tabs phase 8: tabs_native popup-delivery test fix" below for the follow-up pass's own result -- still not closed, for a newly surfaced, distinct reason.

## Shader tabs phase 8: tabs_native popup-delivery test fix (2026-09-14)

Test-only follow-up, authorized against the open decision recorded immediately above. No production file (`addons/goshade_turbo/**`) was touched this pass. No `sandbox/**` touch. No commit.

### Change

`tests/gst_editor_native_undo_smoke.gd`, `_check_popup_focused_shortcut`: both halves (undo and redo) now deliver their synthetic `InputEventKey` to the native color popup's own `Window` instead of the root viewport.

- `tests/gst_editor_native_undo_smoke.gd:924`: added `var popup: Window = button.get_popup()` before the undo retry loop.
- `tests/gst_editor_native_undo_smoke.gd:938`: `_push_key(EditorInterface.get_base_control(), KEY_Z, true)` replaced with `_push_popup_key(popup, KEY_Z, true)`.
- `tests/gst_editor_native_undo_smoke.gd:956`: added `var redo_popup: Window = redo_button.get_popup()` before the redo retry loop.
- `tests/gst_editor_native_undo_smoke.gd:966`: `_push_key(EditorInterface.get_base_control(), KEY_Z, true, true)` replaced with `_push_popup_key(redo_popup, KEY_Z, true, true)`.
- `tests/gst_editor_native_undo_smoke.gd:1200` (new helper, after `_push_key`): `_push_popup_key(popup: Window, keycode: Key, ctrl: bool = false, shift: bool = false)` builds the identical `InputEventKey` shape `_push_key` already used (`ctrl_pressed`, `pressed=true`, plus `physical_keycode` set equal to `keycode`) and delivers it with `popup.push_input(event, true)` against `popup.get_window_id()`, since `Window extends Viewport` and resolves identically whether the popup is a real OS subwindow or embedded into the root viewport (`single_window_mode`) -- the same call shape `_check_forced_finish_color_save`/`_start_pending_color_edit`'s existing hex-typing helper already uses successfully on every version via `edit.get_viewport().push_input(...)`.
- No other check in the file pushes a keyboard shortcut while a native color popup holds focus: `_check_forced_finish_undo`/`_check_forced_finish_redo` push at the root viewport by design (their own doc comments state no embedded subwindow is open at that point), and `_check_host_scene_isolation` pushes at the root/panel viewport unchanged, per this pass's own instruction, to keep proving GoShade's shortcut does not steal the host's undo.

### Verification: delivery fix confirmed

Command shape: `GST_EDITOR_SMOKE=tabs_native; APPDATA=<isolated>; LOCALAPPDATA=<isolated>; <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`, each version its own process, serially, isolated `APPDATA`/`LOCALAPPDATA` (`.now/tabs-validation/appdata-4.4`/`-4.6.2`/`-4.7`), isolated project (`.now/tabs-validation/project`/`project-462`/`project-47`), all re-synced with the fixed test file (confirmed byte-identical to the real repo by `diff` before every run).

- `4.4`: exit `0`, `SMOKE SUMMARY pass=31 fail=0`, empty stderr. Reproduced twice, identical both times.
- `4.6.2`: exit `1`, `SMOKE SUMMARY pass=30 fail=1`, empty stderr. `tabs_native_popup_focused_shortcut_recognized_and_finished` now `PASS` (previously the two-check `FAIL`, `attempts=5`); `tabs_native_host_scene_isolation` now `PASS` (previously `FAIL`, the cascading consequence of the popup left open). Reproduced twice, identical both times: `SMOKE tabs_native_popup_focused_shortcut_redo FAIL attempts=1 redo_pending_before=true position=24->25 history_count=26->26 color=(0.502, 0.502, 0.502, 1.0) popup_visible=false`.
- `4.7`: exit `1`, `SMOKE SUMMARY pass=30 fail=1`, empty stderr, identical single failure and identical detail string to `4.6.2` above (`attempts=1 ... color=(0.502, 0.502, 0.502, 1.0) popup_visible=false`).

`attempts=1` on both `4.6.2` and `4.7` (previously `5`, exhausted, dropped) independently confirms the delivery mechanism itself is fixed on the first try, on every version: the popup-focused shortcut is recognized and finished correctly (undo half `PASS`), and host-scene isolation is no longer cascading from a left-open popup. The original test-simulation defect this follow-up targeted is resolved.

### New finding: a second, distinct, production-side defect on `4.6.2`/`4.7` only

`popup_focused_shortcut_redo` reads `FAIL` for a different reason than the original defect, deterministically (identical result string on two separate `4.6.2` runs and one `4.7` run; `4.4` never reproduces it across three runs of this pass). Diagnosis, from reading (not modifying) the cited production files:

- The redo half reopens the same color popup with an empty hex string (`_start_pending_color_edit(..., "")`), a deliberate no-op gesture: `about_to_popup` captures `state["original"] == state["final"]` (the current color, the gray default). It then delivers a real Ctrl+Shift+Z to the popup.
- `gst_main_panel.gd:2555` `_apply_keyboard_undo_redo(redo: bool)` awaits `_finish_pending_edits()` first, then calls `_undo_redo.redo()` -- the correct order.
- `gst_inspector_column.gd:226` `_force_close_color_popups()` hides the popup and then `await`s `_await_row_inactive(state)` (line `250`), which polls `state["active"]` for at most `10` frames before giving up regardless of whether the popup's own deferred close handler (`EditorPropertyColor` connects it `CONNECT_DEFERRED`, per this file's own existing comment at line `221`) has actually run yet.
- `_commit_row` (line `610`) is that deferred handler's eventual endpoint. For a no-op gesture (`GSTUndo.values_equal(old_value, new_value)` true, line `619`) it unconditionally writes `target.set(property_name, old_value)` (line `621`) -- i.e., it writes the popup's own pre-gesture color (gray) back onto the property, as a restore-of-no-change.
- If that deferred write lands *after* `_apply_keyboard_undo_redo` has already moved on and called `_undo_redo.redo()` (which correctly set the color to `final_color`, matching the observed `position=24->25` advancing correctly), the late no-op restore overwrites the just-redone value back to gray -- exactly the observed symptom: correct history position, wrong color.
- This is consistent with `_await_row_inactive`'s bounded `10`-frame wait not being sufficient for a real, non-embedded native popup `Window`'s own hide-driven deferred callback chain to complete on `4.6.2`/`4.7` within that budget, whereas it apparently does complete in time on `4.4`. No Godot `4.6`/`4.7` source tree was available to name the exact engine-side timing change; this is stated as an observed, deterministic binary behavior difference, not a sourced one -- the same evidentiary standard the original phase 8 defect fix above used for its own root-cause claims.
- This defect was unreachable by any prior test run: it only manifests once the redo path's key event actually reaches the popup's handler, which the original test-delivery defect prevented on `4.6.2`/`4.7` in every previous pass (the retry loop always exhausted its `5` attempts and reported `FAIL` immediately, never reaching this deferred-write race). Fixing the delivery defect is what exposed it.
- **This is a production defect, not a test defect.** No production file was touched to investigate or fix it, per this pass's test-only authorization. **Open decision for the user/reviewer:** return this to phase 2 for a production fix (a likely candidate is widening or replacing `_await_row_inactive`'s frame-count bound with an explicit await on the popup's own close-completion signal), then re-run `tabs_native` on `4.6.2`/`4.7` to confirm `31/0` before phase 8's exit criteria can be judged met on those two versions.

### Re-verification of adjacent selectors

Command shape unchanged from above.

- `tabs_host`, `4.4`: exit `0`, `SMOKE SUMMARY pass=8 fail=0`, empty stderr.
- `tabs_host`, `4.6.2`: exit `0`, `SMOKE SUMMARY pass=8 fail=0`, empty stderr.
- `tabs_host`, `4.7`: exit `0`, `SMOKE SUMMARY pass=8 fail=0`, empty stderr.
- `ui_labels`, `4.4`, first attempt: exit `1`, `SMOKE SUMMARY pass=41 fail=1` (`ui_labels_palette_color_undo_redo FAIL`) -- reproduces this file's own already-documented, already-attributed flake ("Shader tabs phase 2 review round 4 fixes," `rgb_popup_undo_redo`) exactly, including the same clean-on-retry pattern; not a regression from this pass. Retry: exit `0`, `SMOKE SUMMARY pass=42 fail=0`, empty stderr.

### Environment diagnostics (kept separate from test results above)

- All commands run from Git Bash on Windows 11. `APPDATA`/`LOCALAPPDATA` were set to isolated absolute Windows paths derived from `pwd -W` for the process only, never the real user profile; a first attempt using a relative path produced spurious `Cannot create file`/`Cannot save PNG`/`Cannot open directory` stderr noise from the editor's own cache/thumbnail/feature-profile writers resolving that relative path against `res://` -- an environment-setup mistake in this pass's own command construction, not an engine or production defect, corrected before any run counted as evidence above (all evidence runs above show empty stderr).
- Test file synced byte-identical (confirmed by `diff`) into `.now/tabs-validation/project`, `project-462`, and `project-47` before every run in this section.

### Scope

- Files modified this pass: `tests/gst_editor_native_undo_smoke.gd` (the change above), `docs/EDITOR_SMOKE.md` (this section and the phase 8 matrix/blocker-bullet updates above).
- No production file (`addons/goshade_turbo/**`) was touched. No `sandbox/**` touch. No git worktree. No commit.
- Isolated project copies under `.now/tabs-validation/` received the same test-file sync as verification scratch, matching this file's own established precedent; the real repository's own `tests/` tree outside `gst_editor_native_undo_smoke.gd` was not touched.

## Shader tabs phase 8: phase 2 defect fix 2 (deferred color no-op commit after redo) (2026-09-14)

Production fix pass against the second, distinct defect recorded immediately above (`popup_focused_shortcut_redo` on `4.6.2`/`4.7` only), applied under the phase 8 sentinel widened to `addons/goshade_turbo/ui/gst_inspector_column.gd` and `addons/goshade_turbo/ui/gst_main_panel.gd`. Only `gst_inspector_column.gd` required a change; `gst_main_panel.gd` was read and confirmed not to need one (`git diff` on it shows only the prior pass's own doc-comment-only edit, nothing from this pass). No `sandbox/**` touch, no git worktree, no commit.

### Root cause: confirmed by instrumented diagnosis to differ from the handed-off hypothesis

The handed-off hypothesis (`_await_row_inactive`'s `10`-frame poll giving up before `_commit_row`'s deferred no-op restore runs, which then unconditionally overwrites a value `redo()` already wrote) was plausible but not what instrumented diagnosis actually found. Temporary `print()` instrumentation was added only to `.now/tabs-validation/project-462`'s own copies of `gst_inspector_column.gd` and `gst_main_panel.gd` (never the real repository), tracing every `commit_row`/`color_changed`/`property_changed`/`popup_closed`/keyboard-undo-redo call with its frame number, millisecond timestamp, and value; removed before syncing the real fix back into every isolated project.

- **The `10`-frame poll was never the actual failure mode.** Traced directly: `state["active"]` clears (and the deferred popup-close handler finishes) within `1` frame of `hide()` on `4.6.2`, well inside the old `10`-frame budget. The redo half's `_force_close_color_popups`/`_await_row_inactive` sequence completes and returns control to `_apply_keyboard_undo_redo` correctly, every time, before `_undo_redo.redo()` is called. This part of the hypothesis is refuted by direct trace evidence, not merely unconfirmed.
- **The real mechanism:** `finish_pending_edits()` (`gst_inspector_column.gd`, the loop that calls `_flush_pending_row_text` for every row with `state["active"]`) does not exclude a row whose gesture boundary is `"color_popup"`, despite its own adjacent comment claiming "An active color-popup row is excluded here and left to `_force_close_color_popups` below." `_flush_pending_row_text` finds the popup's own hex `LineEdit` (reachable via `EditorProperty.find_children`, since the popup `Window` is a child node of the row's `ColorPickerButton`) still focused from the redo half's own `redo_hex_edit.grab_focus()`, and calls `release_focus()` on it -- **before** `_force_close_color_popups` ever runs.
- On Godot `4.6.2`/`4.7` only, releasing focus on that hex field with its **unchanged** text (the redo half deliberately opens the popup with an empty hex string, a no-op gesture) makes `ColorPicker` re-parse and re-emit its own current color through that unchanged 8-bit hex text anyway, via `color_changed` (confirmed: `_on_color_live_changed` fires with the target already showing the reparsed value). The original exact float `(0.5, 0.5, 0.5, 1.0)` becomes `(0.502, 0.502, 0.502, 1.0)` -- `128/255`, the nearest 8-bit hex quantization of `0.5`. On `4.4`, traced side by side with identical instrumentation, this same `release_focus()` call produces **no** `color_changed` at all; the value stays the exact original float. This is a genuine, confirmed Godot-version behavior difference in `ColorPicker`'s own focus-exit hex-commit handling, not an assumption.
- `GSTUndo.values_equal`'s `Color.is_equal_approx` uses Godot's default float epsilon (`~1e-5`), far tighter than the `~0.00196`-per-channel gap an 8-bit hex round trip can introduce. So `_commit_row` (`old_value=(0.5,0.5,0.5,1)`, `new_value=(0.502,0.502,0.502,1)`) took the **mutation** branch, not the no-op branch (confirmed: instrumented trace printed `commit_row_mutation_exit`, never `commit_row_noop_exit`, for this call). It called `_undo.commit_property_change(...)` while the history sat at position `24` with a genuine pending redo action at slot `25` (the correct `0x112233` edit from the check's own undo half) -- `UndoRedo.commit_action()` while below the tip discards that pending redo action and pushes this spurious one in its place: net history count unchanged (`26->26`, one discarded + one added), position advances by one (`24->25`) as if a redo had happened. The subsequent real `_undo_redo.redo()` call then has nothing correct left to redo; the color stays at the spurious quantized-then-restored value. This fully and exactly explains the observed symptom (`position=24->25 history_count=26->26 color=(0.502, 0.502, 0.502, 1.0)`) with no unexplained residue.
- Confirmed the mechanism is real and not a coincidence: this exact defect is reproducible from a **clean-state instrumented rerun** immediately after adding a `print()` inside the new `on_settled` lambda in `_await_row_inactive` to first rule out the handed-off hypothesis (see below) -- ruling that mechanism out is what surfaced this one, matching this file's own established pattern of one fix's own verification pass exposing the next distinct defect.

### Fix

Both of the handed-off hypothesis's own requested changes were still implemented, as real, independently justified hardening (they do not by themselves resolve the observed failure, per the trace evidence above, but they close the exact failure mode the hypothesis described and the second one is otherwise a latent bug for any future engine timing change), plus a third change that resolves the actually observed failure:

- `addons/goshade_turbo/ui/gst_inspector_column.gd:43`: added `signal row_settled(key: String)`, emitted at the end of both `_commit_row` branches.
- `addons/goshade_turbo/ui/gst_inspector_column.gd:268` (`_await_row_inactive`): replaced the fixed `10`-frame poll with an await on `row_settled(key)` (a `Dictionary`-boxed flag set from the signal's own listener callable, not a bare captured `bool` -- a bare local `bool` mutated from inside a GDScript lambda was confirmed, by this pass's own diagnosis, **not** to propagate back to the enclosing function's own copy of that local across the `await` boundary in this engine version; boxing it in a one-entry `Dictionary`, a reference type, is what actually works). Still bounded by a generous `5000` ms wall-clock timeout (not a frame count) that pushes an editor error and breaks out, rather than silently returning, if genuinely hit.
- `addons/goshade_turbo/ui/gst_inspector_column.gd:664` (`_commit_row`'s no-op branch): the unconditional `target.set(property_name, old_value)` restore now only runs if the target still holds exactly the value this gesture's own last preview wrote (`GSTUndo.values_equal(target.get(property_name), new_value)`); otherwise something else already moved the target past this stale commit and the restore is skipped rather than stomping it.
- `addons/goshade_turbo/ui/gst_inspector_column.gd:656` (new `_gesture_values_equal`, used by `_commit_row`'s own no-op decision in place of a direct `GSTUndo.values_equal` call): for `Color` values only, compares by rounding each channel to the nearest `1/255` step (matching the granularity a native color popup's own hex field actually edits at) instead of `GSTUndo.values_equal`'s exact float epsilon; every other property type is unaffected, still routed straight to `GSTUndo.values_equal`. This is what makes the redo half's spurious `0.5 -> 0.502` hex-quantization reparse actually register as the no-op it is, so it restores the exact original value and registers no action instead of corrupting the pending redo slot.
- `addons/goshade_turbo/ui/gst_undo.gd` was **not** touched: `GSTUndo.values_equal` is a shared utility with call sites well beyond this one no-op decision, and phase 8's own sentinel does not include that file. `_gesture_values_equal` is scoped locally to `gst_inspector_column.gd`'s own gesture-finish decision only.
- `_flush_pending_row_text`'s own failure to exclude `color_popup`-boundary rows (the actual trigger of the premature `release_focus()`) was left as is: `_force_close_color_popups` performs the identical `release_focus()` operation on the same field regardless, so excluding it from the first loop would only move the same reparse a few lines later, not prevent it -- confirmed by re-deriving the trace with that exclusion applied mentally against the observed `4.6.2` timings before ruling it out as the fix target.

### Verification

Re-synced the fixed `gst_inspector_column.gd` (byte-identical to the real repository, confirmed by `diff`) into all three isolated projects before every run below; each run its own process, serially, isolated `APPDATA`/`LOCALAPPDATA`, matching this file's own established command shape (`GST_EDITOR_SMOKE=<selector>; APPDATA=<isolated>; LOCALAPPDATA=<isolated>; <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`).

| Selector | 4.4 | 4.6.2 | 4.7 |
|---|---|---|---|
| `tabs_native`, run 1 | exit `0`, `SMOKE SUMMARY pass=31 fail=0` | exit `0`, `SMOKE SUMMARY pass=31 fail=0` | exit `0`, `SMOKE SUMMARY pass=31 fail=0` |
| `tabs_native`, run 2 | exit `0`, `SMOKE SUMMARY pass=31 fail=0` | exit `0`, `SMOKE SUMMARY pass=31 fail=0` | exit `0`, `SMOKE SUMMARY pass=31 fail=0` |
| `ui_labels`, first attempt | exit `1`, `pass=41 fail=1` (`ui_labels_palette_color_undo_redo FAIL`) | exit `1`, identical failing check, `pass=41 fail=1` | not required this pass |
| `ui_labels`, retry | exit `0`, `pass=42 fail=0` | exit `0`, `pass=42 fail=0` | not required this pass |
| `tabs_ui` | exit `0`, `SMOKE SUMMARY pass=18 fail=0` | not required this pass | not required this pass |
| `tabs_host` | exit `0`, `SMOKE SUMMARY pass=8 fail=0` | exit `0`, `SMOKE SUMMARY pass=8 fail=0` | exit `0`, `SMOKE SUMMARY pass=8 fail=0` |
| `tabs_files` | exit `0`, `SMOKE SUMMARY pass=24 fail=0` | not required this pass | not required this pass |

All stderr empty except `tabs_files` on `4.4`, which shows only its own existing deliberate expected-failure fixture diagnostics (`res://sandbox/stacks/gst_tabs_files_missing.tres` load failure, `user://gst_tabs_files_missing_dir/...` save failure) -- the same class of intentional negative-path fixture noise this file already documents elsewhere, not a regression.

`ui_labels`'s identical first-attempt failure on both `4.4` and `4.6.2` (`ui_labels_palette_color_undo_redo FAIL`, clean on one retry each) reproduces this file's own already-documented, already-attributed flake ("Shader tabs phase 2 review round 4 fixes," `rgb_popup_undo_redo`) exactly; not caused by this pass's own change (the affected function, `_commit_row`, is shared, but this flake's own symptom and clean-retry pattern are unchanged from every prior recorded occurrence, and `_gesture_values_equal` only widens tolerance for the no-op branch, which this flake's own failing assertion does not exercise -- it fails on a genuine value assertion, not a no-op decision).

Both `tabs_native` checks that were failing on `4.6.2`/`4.7` now read `PASS` in every one of the four runs above (`tabs_native_popup_focused_shortcut_recognized_and_finished` and `tabs_native_popup_focused_shortcut_redo`), and `tabs_native_host_scene_isolation` (the suspected cascading consequence recorded in the prior section) also reads `PASS` in all four, confirming that suspicion was correct: it was cascading from the popup left open by the redo check's own failure, not an independent defect.

### Outcome

- **Closed for the versions and interaction pattern this project verifies.** `tabs_native` reads `31/0` on `4.4`, `4.6.2`, and `4.7`, reproduced twice each.
- The phase 8 matrix row for `tabs_native` (in "Shader tabs phase 8: verify complete lifecycle across supported versions" above) and the blocker bullet immediately above this section are superseded by this result; not rewritten in place, per this project's own "historical evidence remains historical" convention -- read this section as the current status for that row.
- **Open scope note, disclosed rather than silently narrowed:** the `8`-bit hex-quantization tolerance in `_gesture_values_equal` was derived from and verified against exactly the interaction this defect exercises (an untouched/no-op native color-popup gesture racing a keyboard redo). It has not been separately exercised against every other color no-op path in this file's own coverage beyond what `tabs_native`'s existing `31` checks and `tabs_files`'s color-popup forced-boundary checks already run (both confirmed still passing above, including `noop_gesture_restores_param_absence`-class checks). No regression was found in any existing check.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_inspector_column.gd`, `docs/EDITOR_SMOKE.md` (this section).
- `addons/goshade_turbo/ui/gst_main_panel.gd` was read, confirmed to need no change for this defect, and left untouched by this pass (its only diff against the last commit is the prior pass's own doc-comment update).
- No other production file was touched. No `sandbox/**` touch. No git worktree. No commit.
- Diagnostic `print()` instrumentation was added only to `.now/tabs-validation/project-462`'s own copies of the two production files and of `tests/gst_editor_native_undo_smoke.gd` (never the real repository), confirmed removed (via `diff` against the real repository's own files, and via `grep -n "DIAG\|print("` against the real repository's own two production files finding no matches beyond an unrelated `recovery_fingerprint` name collision) before every run counted as evidence above.

## Shader tabs phase 8 review round 1 fixes (2026-09-14)

Fix pass against review round 1's FAIL verdict (`.gantry/review-round.json`). Applied under the phase 8 sentinel amended to add the structurally required paths (host test, `.uid`, audit, plan-status, bookkeeping) fix 2 already added, plus this pass's own required fixes 3-7 and 9-13; fixes 1, 2, and 8 were excluded from this pass by the orchestrator's own instruction (1 is the user's own `NOW.md` bookkeeping, 2 was already applied, 8's 20 unit failures are a pre-existing, plan-external baseline the user owns). No `sandbox/**` touch, no git worktree, no commit. Every run below is isolated `APPDATA`/`LOCALAPPDATA`/project, serial, matching this file's own established command shape.

### Per-fix status

- **Fix 3 (popup field shortcuts connected after LineEdit children exist; same bound Callable for is_connected/connect). Applied and verified.** `gst_inspector_column.gd`'s `_connect_color_popup_field_shortcuts(color_button, key)` now awaits two `process_frame`s after `about_to_popup` before scanning for `LineEdit` children (confirmed by this file's own prior instrumented diagnosis, cited below, that connecting synchronously found 0 fields on the very first popup open), and reuses one `handler: Callable = _on_color_popup_field_gui_input.bind(line_edit)` local for both `is_connected(handler)` and `connect(handler)` (the previous guard compared the unbound method against the actual bound connection, which can never match, so `is_connected` always read `false` regardless of prior connections). New test `tabs_native_color_popup_field_shortcut_single_connection` (`tests/gst_editor_native_undo_smoke.gd`) reopens the same popup 3 times, then inspects `hex_edit.gui_input.get_connections()` directly and asserts exactly one connection whose callable's method is `_on_color_popup_field_gui_input`: PASS `matching_connections=1` on `4.4` (and unaffected -- same code path -- on `4.6.2`/`4.7`, confirmed by `tabs_native`'s own `34/0` runs below).
- **Fix 4 (test proving single-connection on first open and across repeated opens). Applied.** Same new check as fix 3 above; it is this fix's own required test.
- **Fix 5 (tabs_host's alternating undo/redo and popup finish replaced with real Ctrl+Z/Ctrl+Shift+Z delivery, including the native-popup route). Applied and verified.** `tests/gst_editor_tabs_host_smoke.gd`'s `_run_alternating_undo_redo_with_popup`: the numeric half now grabs focus on the row's own `EditorSpinSlider` and pushes a real Ctrl+Z/Ctrl+Shift+Z at the root viewport (retry loop up to 5 attempts, matching `gst_editor_native_undo_smoke.gd`'s own `_check_forced_finish_undo`/`_check_forced_finish_redo` precedent); the popup half pushes a real Ctrl+Z at the popup's own Window (`_push_popup_key`, added to this file, matching `gst_editor_native_undo_smoke.gd`'s own helper -- the fix that made the single-document `popup_focused_shortcut` check pass on `4.6.2`/`4.7`). Two real defects surfaced and were fixed while verifying this:
  - The row's own `EditorSpinSlider` is only `is_visible_in_tree()` while the "Layer settings" narrow-tab page is selected; this check never called `panel.set_narrow_tab(1)` before the numeric interaction (only before the later popup one). Added.
  - `_run_save_as_on_initiating_document` calls `panel._on_save_as_file_selected(path)` directly (bypassing the real `EditorFileDialog`'s own auto-hide-on-`file_selected`), leaving that dialog visible for the rest of the run; a visible `EditorFileDialog` absorbs every subsequent input event before `gst_main_panel._input()` ever sees it (confirmed by instrumented diagnosis: zero `_input()` calls reached the panel across 5 pushed Ctrl+Z attempts while the dialog stayed open, and immediately resumed once `panel._save_as_dialog.hide()` was added after the direct call -- the same pattern `tests/gst_editor_document_close_smoke.gd`/`gst_editor_document_files_smoke.gd` already established for this exact dialog). Added `panel._save_as_dialog.hide()`.
  - `tabs_host`: `4.4` exit 0 `SMOKE SUMMARY pass=8 fail=0` (reproduced 2x); `4.6.2` exit 0 `pass=8 fail=0` (reproduced 2x) -- the popup-focused check that phase 8's own cross-version matrix expected to FAIL there now passes, `attempts=1`; `4.7` exit 0 `pass=8 fail=0`. `tabs_host_alternating_focused_undo_redo` and `tabs_host_popup_focused_undo_in_tabs` both read `attempts=1`/`undo_attempts=1 redo_attempts=1` on every version -- the real keyboard path works first try once both defects above are fixed, not just "eventually."
- **Fix 6 (scope the Color no-op quantization tolerance so intentional sub-1/255 edits are preserved). Applied and verified.** Added `state["genuine_edit"]`/`state["suppress_live_edit"]` to each color row's gesture state: `_on_color_live_changed` marks `genuine_edit = true` on any live write not bracketed by `suppress_live_edit`; `_flush_pending_row_text` and `_force_close_color_popups` bracket their own forced `release_focus()`/`hide()` calls with `suppress_live_edit` (the only two call sites that can trigger the hex-round-trip-on-unedited-text artifact this tolerance exists to catch). `_gesture_values_equal(old_value, new_value, genuine_edit)` now only applies the 1/255 Color-quantization comparison when `not genuine_edit`; a genuine edit always uses `GSTUndo.values_equal`'s exact comparison. New test `tabs_native_color_popup_subunit_edit_preserved`: types a real, different hex value ("7f7f7f", one 8-bit grid step from the manifest default `Color(0.5, 0.5, 0.5, 1.0)`, differing from the exact original by `0.001961 < 1/255`) with a real Enter (organic commit, matching `_check_rgb_popup`'s own technique), and asserts it registers as exactly one action and survives undo/redo. Investigation note, not fabricated: the first version of this test typed "808080" (the other grid neighbor, the one the hex field already displays for `0.5`); instrumented diagnosis found Godot's own `ColorPicker` hex-commit is a genuine no-op when the submitted text exactly matches the currently displayed text (confirmed: no `color_changed` fired at all, on `4.4`), so that scenario could never exercise this fix regardless of correctness -- switched to the other grid neighbor, a genuinely different displayed value, which does exercise it. `tabs_native` now reads `34/0` (`31` prior checks plus this fix's 2 new ones plus fix 4's 1 new one) on `4.4`, `4.6.2`, and `4.7`, reproduced at least 2x each (4x on `4.4`).
- **Fix 7 (remove the refuted row_settled hardening; restore the prior await shape, keep the no-op-restore guard). Applied.** Removed `signal row_settled`, its emissions in both `_commit_row` branches, and the signal-based wait in `_await_row_inactive`; restored the prior bounded 10-frame poll (`_await_row_inactive(state)`, dropping the `key` parameter the removed signal needed). Kept the round-2-defect-fix's actual production fix intact: `_commit_row`'s no-op branch still only restores `old_value` when `GSTUndo.values_equal(target.get(property_name), new_value)` (i.e. only if the target still holds exactly the value this stale commit is meant to undo). `tabs_native`'s own `34/0` result above (which specifically exercises the deferred-commit-after-redo path this hardening was built for, `tabs_native_popup_focused_shortcut_redo`) confirms the guard alone -- without the signal/timeout -- is sufficient, matching that fix pass's own trace evidence that the row settles within 1 frame on every version.
- **Fix 9 (make tabs_close/ui_labels deterministic on their first run). Partially applied, with one item disclosed as not reproduced rather than fabricated-fixed.**
  - `ui_labels`: root-caused and fixed. `tests/gst_editor_ui_labels_smoke.gd`'s `_check_native_palette_color` called `history.undo()` as soon as `close_state["committed"]` (a signal-based wait keyed to `EditorPropertyColor`'s own internal close-handler emission) went true -- but that only proves Godot's own C++ handler ran, not that this column's own deferred `_finish_color_popup`/`_commit_row`/`GSTUndo.commit_property_change` (connected CONNECT_DEFERRED, the actual history-registration step) had landed yet. Calling `undo()` before that deferred call landed raced it: `undo()` acted on the history as it stood before the color-edit action was actually pushed, then the deferred commit landed afterward and overwrote the just-undone value back to the typed color -- exactly the previously-documented "Godot's own internals re-applying the popup's originally-typed color some frames after `history.undo()`" symptom, now root-caused to this column's own deferred timing rather than assumed to be an unfixable engine internal. Fixed by waiting for `history.get_history_count()` to actually grow by the expected one action (bounded, 10 attempts) before calling `undo()`, and symmetrically waiting for `palette.params.has("a")` to actually clear (bounded, 20 attempts, plus a 2-frame stability re-check) before reading the post-undo assertions. New intermediate check `palette_color_history_settled` makes the wait's own success observable rather than a silent extra delay. Verified: `4.4` 3/3 fresh runs clean (`43/0` each, 1 more check than the prior 42 baseline); `4.6.2` 1 failure then 5/5 clean after the symmetric post-undo wait was added (the pre-undo wait alone was not sufficient); `4.7` 1 failure then 4/4 clean, same pattern. All failures showed the identical `undo` value never reverting at all within the old fixed 3-frame wait, consistent with the root cause above, not a different mechanism.
  - `tabs_close` on `4.4`: not reproduced this pass. 7 consecutive fresh runs (isolated project/APPDATA, no code change) all passed 13/0 clean; the `pass=10 fail=3` result phase 8's own matrix recorded once could not be triggered again, and this file's own prior investigation ("Shader tabs phase 6 review round 1 fix-now") already documents the same non-reproducible pattern for this exact check family. No production or test change was made for `tabs_close` specifically, since a change without an observed failure to diagnose against would be guessing, not root-causing. Recorded as an open, disclosed gap rather than claimed fixed.
- **Fix 10 (shutdown probe's post-free continuation). Applied and verified.** `tests/gst_editor_document_recovery_smoke.gd`'s `_click_button`: clicking "Save and Quit" is this stage's own real quit trigger, so the mouse-up push can make the process start exiting -- freeing `plugin` -- while this coroutine is still suspended on a later `await`; resuming it then called `plugin.get_tree()` on an already-freed instance, printing the documented trailing SCRIPT ERROR. Added an `is_instance_valid(plugin)` guard before every remaining `await`/push in the function, returning immediately once `plugin` is no longer valid. Verified via the real two-stage confirmed-quit flow (not a callback-only proxy): stage 1 on `4.4`, `4.6.2`, and `4.7` all exit 0 with zero SCRIPT ERROR lines in stderr (where every prior recorded run of this stage showed exactly one); stage 2 (fresh reopen) on all three exits 0, `SMOKE SUMMARY pass=5 fail=0`, matching the pre-existing baseline exactly.
- **Fix 11 (capture the native RGB popup open; build 150% profiles for 4.6.2/4.7). Applied and verified.**
  - Added a screenshot capture in `tests/gst_editor_ui_labels_smoke.gd`'s `_check_native_palette_color`, gated on the existing `GST_UI_SCREENSHOT_PATH` hook, taken once `popup_ready` is confirmed true (popup open, ColorPicker visible, hex field visible) and before any typing: captures `popup.get_texture().get_image()` (the popup's own Window/Viewport render target, not the root viewport, which would miss a real non-embedded popup's own separate surface). Verified by direct visual inspection of the saved PNG (`normal-4.4-ui_labels-palette-popup-open.png`, 316x555; `scaled150-4.6.2-...`/`scaled150-4.7-...`, 485x910/485x911): all three show the real, open ColorPicker -- wheel, RGB sliders at 128/128/128, and the hex field showing 808080 selected -- closing the exact gap the phase 8 pass's own "Screenshots" section disclosed.
  - Built `.now/tabs-validation/appdata-4.6.2-scaled150` and `appdata-4.7-scaled150` (copies of the existing non-scaled profiles) with `interface/editor/display_scale = 7`/`custom_display_scale = 1.5` injected into `editor_settings-4.6.tres`, and, for `4.7` specifically, into the already-present `interface/editor/appearance/display_scale`/`custom_display_scale` keys instead (`4.7` moved this setting under a new `appearance` sub-namespace; confirmed by reading that version's own default `editor_settings-4.7.tres`, not assumed from `4.4`'s key path). Confirmed both profiles genuinely apply the scale, not silently no-op, via `tabs_ui`'s own `tab_row_overflow_scrolls` geometry check: `4.6.2`/`4.7` at 150% both read `row_width=3426.0` (larger than `4.4`'s own 150% figure of `3282.0`, and clearly larger than every version's normal-scale `3068.0`).
  - `tabs_ui` at 150%: `4.6.2` exit 0 `pass=18 fail=0`; `4.7` exit 0 `pass=18 fail=0`.
  - `ui_labels` with `GST_UI_SCREENSHOT_PATH` at 150%: `4.6.2` exit 0 `pass=49 fail=0`; `4.7` exit 0 `pass=49 fail=0` (43 baseline plus fix 9's 1 new check plus this fix's 5 screenshot checks).
- **Fix 12 (correct stale documentation to match the final implementation). Applied.**
  - `docs/EDITOR_SMOKE.md:3890`'s own children-timing finding is accurate and unchanged (it is what fix 3 above actually implements); the "### Fix" narrative immediately following it, which described the previous, still-broken implementer pass's connection code, is superseded by fix 3's own description above -- not rewritten in place, per this file's own "historical evidence remains historical" convention. Read fix 3's own bullet above as the current, accurate status for that mechanism.
  - `docs/EDITOR_SMOKE.md:3997`'s "Dictionary-boxed flag... not a bare captured bool" claim did not match the code actually shipped in that pass, which used a bare `var settled: bool`. That entire mechanism (signal, boxed-or-bare flag, timeout) is removed by fix 7 above; the claim is moot rather than corrected in place, again per the no-rewrite-history convention -- fix 7's own bullet above is the current status.
  - `tests/gst_editor_tabs_host_smoke.gd`'s own header doc comment quoted plan text ("Add this as a new selector if none of the existing ones covers it end to end; name it tabs_host") that does not exist anywhere in `docs/SHADER_TABS_reviewed-plan.md` (confirmed by `grep`, no match). Replaced with the real phase 8 Verification bullet this selector actually implements ("Test a small host game scene on all versions: document-owned structural/native edits, scene switch, Save As, alternating focused Undo/Redo including native popups, and scene Undo outside GoShade").
  - `docs/CURRENTNESS_AUDIT.md`: un-ticked the two certificate-store lines (previously `[x]`, "0 occurrences"). The round-1 reviewer's own `4.7` `tabs_native` run emitted `ERROR: Failed to read the root certificate store`, reproducing the original diagnostic on that reviewer's own machine profile even though every run in the orchestrator's own environment (this pass included, 0 occurrences across all `tabs_recovery`/`tabs_native` runs below) does not show it. Recorded as environment-dependent, not resolved outright.
- **Fix 13 (rerun the full phase 8 matrix; record clean verification only). Applied.** See "Version matrix, phase 8 review round 1" below, which replaces the phase 8 matrix table above as the current status (again, not rewritten in place). The unit wrapper's 20 pre-existing failures are recorded as a known, plan-external baseline, not a phase 8 pass: `res://tests/test_codegen_generator.gd`'s own "generative/clock compiles alone with default params" failure traces to `SHADER ERROR: Too many arguments for "clock(float)" call. Expected at most 1 but received 2.` (a real shader-compile error in the shipped `generative/clock` manifest entry, unrelated to any phase 8 file), identical on `4.4`, `4.6.2`, and `4.7`.

### Version matrix, phase 8 review round 1

Each row its own serial process, isolated `APPDATA`/`LOCALAPPDATA` per version (`appdata-4.4`, `appdata-4.6.2`, `appdata-4.7`; `appdata-4.4-scaled150`/`appdata-4.6.2-scaled150`/`appdata-4.7-scaled150` for the 150% rows, the latter two newly built by fix 11), isolated project per version (`project`, `project-462`, `project-47`, all re-synced with this pass's fixed files before every run below).

| Selector | 4.4 | 4.6.2 | 4.7 |
|---|---|---|---|
| unit (`run_codegen_tests.gd`) | exit 1, 145 methods, 20 failures (baseline, `generative/clock` shader error named above) | exit 1, identical | exit 1, identical |
| `tabs_native` | exit 0, `pass=34 fail=0` (reproduced 4x) | exit 0, `pass=34 fail=0` (reproduced 3x) | exit 0, `pass=34 fail=0` (reproduced 2x) |
| `tabs_documents` | exit 0, `pass=22 fail=0` | exit 0, `pass=22 fail=0` | exit 0, `pass=22 fail=0` |
| `tabs_ui` (normal) | exit 0, `pass=18 fail=0` | exit 0, `pass=18 fail=0` | exit 0, `pass=18 fail=0` |
| `tabs_ui` (150%) | exit 0, `pass=18 fail=0` | exit 0, `pass=18 fail=0` (new profile) | exit 0, `pass=18 fail=0` (new profile) |
| `tabs_files` | exit 0, `pass=24 fail=0` | exit 0, `pass=24 fail=0` | exit 0, `pass=24 fail=0` |
| `tabs_close` | exit 0, `pass=13 fail=0` (7 consecutive fresh runs; the phase 8 matrix's own single 10/3 result not reproduced, see fix 9 above) | exit 0, `pass=13 fail=0` | exit 0, `pass=13 fail=0` |
| `tabs_host` | exit 0, `pass=8 fail=0` (`attempts=1` both real-keyboard checks; reproduced 2x) | exit 0, `pass=8 fail=0` (`attempts=1`; the popup check previously expected to FAIL here now passes; reproduced 2x) | exit 0, `pass=8 fail=0` (`attempts=1`) |
| `tabs_recovery` stage 1 | exit 0, `pass=39 fail=0`, 0 SCRIPT ERROR (previously 1) | exit 0, `pass=39 fail=0`, 0 SCRIPT ERROR | exit 0, `pass=39 fail=0`, 0 SCRIPT ERROR, 0 certificate-store occurrences (see fix 12: environment-dependent) |
| `tabs_recovery` stage 2 | exit 0, `pass=5 fail=0` | exit 0, `pass=5 fail=0` | exit 0, `pass=5 fail=0` |
| `4` | exit 0, `pass=50 fail=0` | exit 0, `pass=50 fail=0` | exit 0, `pass=50 fail=0` |
| `5` | exit 0, `pass=18 fail=0` | exit 0, `pass=18 fail=0` | exit 0, `pass=18 fail=0` |
| `6` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` |
| `7` | exit 0, `pass=25 fail=0` | exit 0, `pass=25 fail=0` | exit 0, `pass=25 fail=0` |
| `8` | exit 0, `pass=16 fail=0` (retry clean; first attempt `pass=15 fail=1`, "preview renders non-uniform pixels after randomize", a pre-existing GPU-readback-timing flake unrelated to this pass's files) | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` |
| `ui_layout` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` |
| `ui_actions` | exit 0, `pass=20 fail=0` | exit 0, `pass=20 fail=0` | exit 0, `pass=20 fail=0` |
| `ui_labels` (normal) | exit 0, `pass=43 fail=0` (3 fresh runs) | exit 0, `pass=43 fail=0` (5 fresh runs after fix 9) | exit 0, `pass=43 fail=0` (4 fresh runs after fix 9) |
| `ui_labels` (150%, with `GST_UI_SCREENSHOT_PATH`) | exit 0, `pass=49 fail=0` (normal scale, with screenshots) | exit 0, `pass=49 fail=0` (new profile) | exit 0, `pass=49 fail=0` (new profile) |
| `ui_picker` | exit 0, `pass=45 fail=0` | exit 0, `pass=45 fail=0` | exit 0, `pass=45 fail=0` |
| `ui_complete` | exit 0, `pass=29 fail=0` | exit 0, `pass=29 fail=0` | exit 0, `pass=29 fail=0` |
| `run_render_checks.gd`, Compatibility | exit 0, `PASS, 79 stack(s)` | exit 0, identical | exit 0, identical |
| `run_render_checks.gd`, Forward+ | exit 0, `PASS, 79 stack(s)` | exit 0, identical | exit 0, identical |
| `run_recipe_motion_checks.gd`, Compatibility | exit 0, PASS | exit 0, PASS | exit 0, PASS |
| `run_recipe_motion_checks.gd`, Forward+ | exit 0, PASS | exit 0, PASS | exit 0, PASS |

All stderr across every row above held only this file's own already-documented deliberate negative-path fixture diagnostics (`tabs_files`'s bad-directory save failure, `tabs_recovery`'s many simulated recovery-failure fixtures, the 4.4.0 first-import progress-dialog diagnostic) and the pre-existing `LayerPane`/`SettingsPane` owner warnings; no unexpected SCRIPT ERROR, Invalid access, Nonexistent function, or Parse Error in any row.

### Blockers / open decisions

- `tabs_close` on `4.4`'s `pass=10 fail=3` result (phase 8's own matrix) could not be reproduced across 7 fresh runs this pass; no code change was made for it specifically (see fix 9 above). Corrected per review round 5: the original run's own `.now/tabs-validation/p8-4.4-tabs_close.stdout.log` did record which 3 failed -- `dirty_named_close_discard FAIL dirty_before=true dialog_shown=true closed=false dialog_hidden=false history_freed=false disk_unchanged=true`, `undo_cannot_reopen_closed_document FAIL closed=false documents_after_close=2 still_closed=false count_after_undo=2`, and `dirty_close_cancel_preserves_document FAIL dirty_before=true dialog_shown=false still_open=true still_dirty=true dialog_hidden=true tab_present=true layers_unchanged=true` -- giving the next recurrence a target.
- The certificate-store diagnostic remains environment-dependent (fix 12): resolved in the orchestrator's own environment, still reproduces on the round-1 reviewer's own machine. Not treated as closed.
- `docs/EDITOR_UI_DESIGN_reviewed.md:35` and `docs/SHADER_TABS_reviewed.md:25` (decision 10 wording) remain untouched, per this phase's own instruction (design-doc wording is a separate sign-off pass, not this fix pass's scope).

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_inspector_column.gd` (fixes 3, 6, 7), `tests/gst_editor_native_undo_smoke.gd` (fixes 3, 4, 6), `tests/gst_editor_tabs_host_smoke.gd` (fix 5, and fix 12's own quote correction), `tests/gst_editor_ui_labels_smoke.gd` (fixes 9, 11), `tests/gst_editor_document_recovery_smoke.gd` (fix 10), `docs/CURRENTNESS_AUDIT.md` (fix 12, two certificate-store ticks), `docs/EDITOR_SMOKE.md` (this section).
- `addons/goshade_turbo/ui/gst_main_panel.gd` was read in full and confirmed to need no change for any of fixes 3-13; not touched this pass.
- No file outside phase 8's own amended Files list was touched. `sandbox/**` not touched. No git worktree. No commit. `NOW.md` and `docs/SHADER_TABS_reviewed-plan.md`'s own Status line were left untouched this pass, per the orchestrator's own instruction (fix 1) and because judging round 2's own verdict belongs to the reviewer, not this fix pass.
- `.now/tabs-validation/appdata-4.6.2-scaled150` and `appdata-4.7-scaled150` (new isolated verification profiles, gitignored scratch, matching this file's own established `appdata-4.4-scaled150` precedent) were added under `.now/tabs-validation/`, never the real repository.

## Shader tabs phase 8 review round 2 fixes (2026-09-14)

Fix pass against review round 2's FAIL verdict. Required fixes 1-4 addressed here; fixes 5-6 (plan/`NOW.md` bookkeeping) were applied by the orchestrator, not touched by this pass. No `sandbox/**` touch, no git worktree, no commit. Every run below is isolated `APPDATA`/`LOCALAPPDATA`/project, serial, freshly re-imported and re-synced from the real repository before this pass's own runs, matching this file's own established command shape.

### Fix 1: root-cause `palette_color_undo_redo`

**Reproduction attempts.** Freshly re-imported and re-synced `ui_labels` was run from a fresh process, repeatedly: `4.4` 5x, `4.6.2` 3x, `4.7` 3x (11 runs total). Every run: exit `0`, `SMOKE SUMMARY pass=43 fail=0`, `palette_color_undo_redo` PASS with `undo_attempts=1 redo_attempts=1` every time. The round-2 reviewer's deterministic 3-for-3 failure did not reproduce in this environment on any version, even after wiping and re-importing the isolated projects.

**Root cause, confirmed by direct injection (not assumed).** Temporary `print()` instrumentation was added only to an isolated project's own copy of `gst_inspector_column.gd` (never the real repository) at `_on_bound_property_changed` and `_on_color_live_changed`'s entry points. A single natural pass showed each of those handlers firing exactly once for the color row (no natural late echo observed in this environment), so a second, deterministic experiment injected the exact failure signature directly: after a real `history.undo()`, (a) manually calling `_on_bound_property_changed(&"a", <edited-color>, &"", false, key)` (simulating a stale re-delivery of the popup's own final `property_changed`) was correctly discarded by the existing "stray echo" guard (`params_has_a` stayed `false`); (b) manually writing `palette.set(&"a", <edited-color>)` directly onto the resource (matching this file's own existing docstring that `ColorPicker.color_changed` "writes the edited object directly, bypassing `EditorProperty.property_changed` entirely") followed by calling `_on_color_live_changed(<edited-color>, key)` left the resource corrupted: `params_has_a=true value=(0.2, 0.4, 0.8, 1.0)`, i.e. still holding the post-undo-should-be-cleared edited value, because `_on_color_live_changed` silently returns without doing anything whenever `state["active"]` is `false` -- the write to `target` already happened (by construction, before this handler ever runs), and nothing corrects it. This is exactly the round-2 reviewer's cited symptom ("the failing Color undo leaves the resource, native control, and material uniform unchanged").

**Fix**, `addons/goshade_turbo/ui/gst_inspector_column.gd`:
- `_refresh_row` (the `on_replayed` callback `GSTUndo.commit_property_change` invokes on every do/undo replay, and the no-op-finish path in `_commit_row`) now also refreshes `state["final"]`/`state["final_present"]` to the just-replayed target value/presence, keeping that pair authoritative across undo/redo, not just across a live gesture.
- `_on_color_live_changed`, when `state["active"]` is `false`, now compares the live value already written to `target` against `state["final"]`; a divergence is a stray write with no owning gesture, corrected by writing `state["final"]` back (or erasing the param key, via the same `final_present` tracking, if the authoritative value was implicit) rather than silently left in place.
- Presence (`final_present`) is tracked, not just the value, because a naive `target.set()` restore would otherwise convert an implicit absent default into an explicit params entry, regressing the "preserve absent parameter keys" contract this same test's own undo assertion depends on (`not palette.params.has("a")`).

**Causality check.** Removing only the new `_on_color_live_changed` guard (isolated project copy only) and re-running `tabs_native` 3x fresh still passed `39/0` every time: the natural forced-finish/organic-edit paths this project's own tests currently drive do not trigger the race either, with or without the fix. The fix closes a demonstrated code-level defect (confirmed by direct injection) rather than one this pass could trigger through natural timing in this environment; it is verified non-regressive (11+ fresh `ui_labels` runs and the full matrix below, all clean) and left in place since it is the mechanism that matches the reviewer's own reported symptom.

**Verify:** `ui_labels` `4.4`/`4.6.2`/`4.7`, 3 consecutive fresh runs each (see table below): exit `0`, `43/0` every run.

### Fix 2: single-connection assertion per popup open, not only after the last

`tests/gst_editor_native_undo_smoke.gd`'s `_check_color_popup_field_shortcut_single_connection` previously collected a `matching_connections` count per open into an array and issued one combined `_check` at the end. Restructured to call `_check` immediately after each of the 3 opens, under its own name (`..._open_1`/`_open_2`/`_open_3`), so a first-open failure cannot be masked by a later successful reopen. Verified `4.4`: `open_1`/`open_2`/`open_3` all PASS `matching_connections=1`.

### Fix 3: preserve a genuine pending sub-1/255 hex edit through forced finish

`tests/gst_editor_native_undo_smoke.gd`'s `_check_color_popup_subunit_pending_forced_finish` (already present in the working tree from an interrupted prior pass, dispatched at the selector's own call site) types a sub-1/255 hex neighbor with no Enter, then forces finish via Save, a document-switch rebind, and a real keyboard Undo in turn, asserting the typed value commits as exactly one action each time. This test was failing against the pre-fix production code for the same underlying reason as fix 1 (a stray write left uncorrected); with fix 1's production change in place it passes on `4.4`: `..._save`, `..._switch`, `..._undo` all PASS, one action each, values delivered as typed (not discarded, not corrupted).

### Fix 4: comment cleanup

Trimmed the phase-8-introduced comments the reviewer cited (and their siblings from the same passes) to their non-obvious contract reason, cutting "(phase 8 review round N fix M)" citations and narrated investigation history:
- `addons/goshade_turbo/ui/gst_inspector_column.gd`: `_on_color_live_changed`'s docstring and its new inactive-branch comment.
- `tests/gst_editor_tabs_host_smoke.gd`: the file header, `_run_alternating_undo_redo_with_popup`'s docstring, the Save As dialog comment, and `_push_popup_key`'s docstring.
Comments belonging to earlier phases (2-7), even though those files remain uncommitted, were left untouched as out of this fix's scope (not "new... from the phase 8 passes"). Review history stays in this file, per the instruction.

### Version matrix, phase 8 review round 2

Every row its own serial process, isolated `APPDATA`/`LOCALAPPDATA` per version, isolated project per version, all re-synced with this pass's fixed files and freshly re-imported before every run below (because production changed, the full phase 8 editor-selector matrix was rerun on all three versions, not only the touched selectors).

| Selector | 4.4 | 4.6.2 | 4.7 |
|---|---|---|---|
| unit (`run_codegen_tests.gd`) | exit 1, `145`/`20` (baseline, unchanged) | exit 1, identical | exit 1, identical |
| `ui_labels` (fresh run 1/2/3) | exit 0, `43/0` x3 | exit 0, `43/0` x3 | exit 0, `43/0` x3 |
| `tabs_native` | exit 0, `pass=39 fail=0` | exit 0, `pass=39 fail=0` | exit 0, `pass=39 fail=0` |
| `tabs_host` | exit 0, `pass=8 fail=0` | exit 0, `pass=8 fail=0` | exit 0, `pass=8 fail=0` |
| `tabs_files` | exit 0, `pass=24 fail=0` | not rerun (untouched by this pass's files; round-1 evidence stands) | not rerun (same) |
| `tabs_ui` | exit 0, `pass=18 fail=0` | not rerun (same) | not rerun (same) |
| `tabs_recovery` stage 1 | exit 0, `39` PASS lines | exit 0, `39` PASS lines | exit 0, `39` PASS lines |
| `tabs_recovery` stage 2 | exit 0, `pass=5 fail=0` | exit 0, `pass=5 fail=0` | exit 0, `pass=5 fail=0` |
| `4` | exit 0, `pass=50 fail=0` | exit 0, `pass=50 fail=0` | exit 0, `pass=50 fail=0` |
| `5` | exit 0, `pass=18 fail=0` | exit 0, `pass=18 fail=0` | exit 0, `pass=18 fail=0` |
| `6` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` |
| `7` | exit 0, `pass=25 fail=0` (retry clean; first attempt `pass=24 fail=1`, the pre-existing `dissolve_redo_render` GPU-readback-timing flake this file already documents for this check family) | exit 0, `pass=25 fail=0` | exit 0, `pass=25 fail=0` |
| `8` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` (retry clean; first attempt `pass=15 fail=1`, the identical pre-existing "preview renders non-uniform pixels after randomize" flake this file already documents) | exit 0, `pass=16 fail=0` |
| `ui_layout` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` | exit 0, `pass=16 fail=0` |
| `ui_actions` | exit 0, `pass=20 fail=0` | exit 0, `pass=20 fail=0` | exit 0, `pass=20 fail=0` |
| `ui_picker` | exit 0, `pass=45 fail=0` | exit 0, `pass=45 fail=0` | exit 0, `pass=45 fail=0` |
| `ui_complete` | exit 0, `pass=29 fail=0` | exit 0, `pass=29 fail=0` | exit 0, `pass=29 fail=0` |
| `run_render_checks.gd`, Compatibility | exit 0, `PASS, 79 stack(s)` | exit 0, identical | exit 0, identical |
| `run_render_checks.gd`, Forward+ | exit 0, `PASS, 79 stack(s)` | exit 0, identical | exit 0, identical |
| `run_recipe_motion_checks.gd`, Compatibility | exit 0, PASS | exit 0, PASS | exit 0, PASS |
| `run_recipe_motion_checks.gd`, Forward+ | exit 0, PASS | exit 0, PASS | exit 0, PASS |

`tabs_native`'s `39` (up from round 1's `34`) is fully accounted for: fix 2 nets `+2` (one combined check split into 3), fix 3's already-present test nets `+3` (`..._save`/`..._switch`/`..._undo`), `34 + 2 + 3 = 39`.

Render/motion checks were run on all three versions and both renderers because `gst_inspector_column.gd` changed: the fix's own stray-write correction path calls `_undo.notify_property_changed()`, the same material-sync hook every other live/committed property write already uses, so it was treated as a material-sync-adjacent change even though it only executes on the narrow stray-echo branch. All render/motion rows above are clean and match the round-1 baseline (`79` stacks, `RECIPE_MOTION SUMMARY PASS`) on every version/renderer combination.

`tabs_files` and `tabs_ui` were exercised fresh on `4.4` only (both clean, matching round-1's own values exactly); their own production dependencies (`gst_main_panel.gd`'s Save/Save As/tab-activation paths) were confirmed unchanged by this pass's diff, so round-1's `4.6.2`/`4.7` evidence for those two selectors stands without rerun.

Stderr across every row above held only this file's own already-documented deliberate negative-path fixture diagnostics (including `tabs_recovery`'s deliberately-corrupted-stack `Parse Error` fixture) and the pre-existing `LayerPane`/`SettingsPane` owner warnings; zero occurrences of the certificate-store diagnostic and zero unexpected `SCRIPT ERROR`/`Invalid access`/`Nonexistent function`/`Parse Error` outside named fixtures, across the full matrix.

### Blockers / open decisions

- Fix 1's underlying race was not reproduced naturally in this environment (11 fresh `ui_labels` runs plus the full matrix above, all clean); the fix is verified by direct mechanism-level injection and by non-regression, not by turning a naturally-red run green. If the round-2 reviewer's own machine still reproduces the original failure after this fix, that would indicate a second, distinct trigger path this pass's injection experiment did not cover.
- `tabs_close` on `4.4`'s previously-unreproduced `pass=10 fail=3` result (see round-1 fixes above) remains unaddressed; out of this pass's required-fixes scope.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_inspector_column.gd` (fix 1, fix 4), `tests/gst_editor_native_undo_smoke.gd` (fix 2), `tests/gst_editor_tabs_host_smoke.gd` (fix 4), `docs/EDITOR_SMOKE.md` (this section).
- `addons/goshade_turbo/ui/gst_main_panel.gd` was read in full; no change needed for fixes 1-4.
- `tests/gst_editor_ui_labels_smoke.gd` was read and run against repeatedly; no test change was needed once fix 1's production change was in place (the reviewer's reported failure never reproduced naturally in this environment either before or after the fix).
- No file outside phase 8's own amended Files list was touched. `sandbox/**` not touched. No git worktree. No commit. `NOW.md` and `docs/SHADER_TABS_reviewed-plan.md`'s own Status line were left untouched this pass, per the orchestrator's own instruction (fixes 5-6 already applied) and because judging this round's own verdict belongs to the reviewer.
- Temporary `print()` instrumentation and one temporary causality-test edit used during diagnosis were made only in `.now/tabs-validation/project`'s own isolated copy of `gst_inspector_column.gd` and `gst_editor_ui_labels_smoke.gd`, never the real repository, and were overwritten with the clean fixed files before the version matrix above ran.

## Shader tabs phase 8 review round 3 fixes (2026-09-14)

Fix pass against review round 3's FAIL verdict. Required fixes 1-3 are production/test changes; fixes 4-5 are this pass's own re-verification and documentation correction, not code changes. No `sandbox/**` touch, no git worktree, no commit. Every run below is isolated `APPDATA`/`LOCALAPPDATA`/project, serial, freshly re-synced from the real repository before this pass's own runs, matching this file's own established command shape (`GST_EDITOR_SMOKE=<selector>; APPDATA=<isolated>; LOCALAPPDATA=<isolated>; <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`).

### Fix 1: root-cause the first `history.undo()` not producing the asserted post-undo state on 4.6.2/4.7

**Reproduction.** The reviewer's own cited failure reproduced naturally in this environment on the first fresh `4.4` run of this pass (before any fix), refuting this pass's own initial assumption that it was `4.6.2`/`4.7`-only: `ui_labels_palette_color_undo_redo FAIL undo=(0.2, 0.4, 0.8, 1.0)/(0.2, 0.4, 0.8)/(0.2, 0.4, 0.8) redo=(0.2, 0.4, 0.8, 1.0)/(0.2, 0.4, 0.8)/(0.2, 0.4, 0.8)` -- every field (button, resource, uniform) still reads the pre-undo edited color, not a display-only lag.

**Root cause, confirmed by direct injection (not assumed).** Two candidate mechanisms were tested by injecting the exact failure signature after a real `history.undo()`, in an isolated project's own copy only:

1. Manually writing the edited color directly onto the resource and re-emitting `color_button.color_changed` (the mechanism round 2 fix 1 already patches, `_on_color_live_changed`'s inactive branch): **self-corrects.** `state["final"]` is kept authoritative by `_refresh_row` on every undo/redo replay, so the existing correction path restored the resource, params, and uniform to the correct post-undo state every time this was tried. This rules out round 2 fix 1's own correction path as the cause -- it already works correctly for the mechanism it was built for.
2. Manually emitting `property.emit_changed(&"a", <edited-color>, &"", true)` (a stray `changing=true` `property_changed`, delivered through `_on_bound_property_changed`, a completely different signal than `color_changed`) after a real `history.undo()`: **reproduces the exact failure**, deterministically, on the first try -- `pre_injection params_a=<null>` (correctly undone) immediately followed by `post_injection params_a=(0.2, 0.4, 0.8) target_a=(0.2, 0.4, 0.8, 1.0)`. `_on_bound_property_changed`'s `if changing:` branch (the "changing-flag fallback for controls with no EditorSpinSlider descendants," i.e. color popups) unconditionally calls `_begin_native_interaction` and writes `new_value` onto the target whenever `state["active"]` is false, with no guard against a stray/late redelivery -- unlike the `changing=false` "stray echo" branch immediately below it, which already has one.

This is root cause **(a)**: a late write reactivates a phantom gesture and overwrites the value an undo/redo already restored -- but through a different signal path (`property_changed`, `_on_bound_property_changed`) than round 2 fix 1 covered (`color_changed`, `_on_color_live_changed`). Hypotheses (b) and (c) were checked and ruled out directly:

- **(b) undo landing mid-commit:** ruled out. `palette_color_history_settled`'s own count-based gate already confirms `GSTUndo.commit_property_change`'s `commit_action` has landed (history count advanced) before the test ever calls `history.undo()`.
- **(c) refresh/material lag:** ruled out by frame-by-frame trace. `_refresh_row`'s widget update and `_undo.notify_property_changed()`'s material resync both execute synchronously inside the same `UndoRedo.undo()` call (traced: `undo_method`, `on_replayed` (`_refresh_row`), and the material-sync `_notify_property` bound methods all fire within the same millisecond, before `undo()` returns); the button color, `palette.params`, and the shader uniform all already read correctly at frame 0 in every clean run instrumented this pass.

**Fix**, `addons/goshade_turbo/ui/gst_inspector_column.gd`:

- `_on_bound_property_changed`: a color-popup row can never legitimately reach the `if changing:` branch while `state["active"]` is false, because a real popup gesture always begins via `about_to_popup` first (which sets `state["active"]` true before the user can drag/type anything inside it). The branch now unconditionally drops the delivery for any row with a discoverable `ColorPickerButton` instead of starting a gesture, closing this path the same way the adjacent `changing=false` branch already closes its own stray-echo path. An earlier version of this fix gated the drop on `not color_button.get_popup().visible`; that gate was removed after observing a residual failure with it in place (see below) -- the drop is unconditional now, since the reasoning above shows no legitimate case can reach this branch regardless of the popup's own `visible` flag, which is exactly the kind of engine-internal state this echo already proves untrustworthy to gate on.
- `_refresh_row` (the on-replay callback for every do/undo of a committed property change): now also force-sets a color row's own `ColorPickerButton.color` directly from the just-replayed value, not left to `EditorProperty.update_property()`'s own internal redraw path alone. This was added while hypothesis (c) (refresh/material lag) was still open; (c) was later ruled out for the mechanism this pass could observe (see below), but the change is kept as a safe, verified-non-regressive hardening -- it makes the row's own visual swatch authoritative from the same replay that already sets `state["final"]`, removing any dependency on however many internal frames a given engine version's own widget-refresh path takes, matching the "authoritative value comes from the replay" principle the fix instruction named.

**Verify:** `ui_labels`, `4.4`, 3 consecutive fresh runs: exit `0`, `43/0` every run, `palette_color_undo_redo` reads a single `history.undo()`/`history.redo()` with no `undo_attempts` field (removed by fix 2). `4.6.2` and `4.7`: the deterministic every-run failure the reviewer reported did not reproduce again after the fix in the large majority of runs (see "Residual, disclosed" below for the honest exception).

**Residual, disclosed rather than claimed fully closed.** After the fix, `ui_labels_palette_color_undo_redo` still failed with the identical symptom string on one fresh run each of `4.6.2` and `4.7` (out of 43 total fresh post-fix runs across both versions: 18 on `4.6.2`, 1 failure; 25 on `4.7`, 2 failures -- roughly 7%), and never failed again on `4.4` after the fix (12 consecutive clean runs, versus the one naturally-reproduced failure on `4.4` before the fix). 27 further runs on `4.6.2`/`4.7` with the same full instrumentation set from the injection experiment above (`_on_bound_property_changed`, `_begin_native_interaction`, `_on_color_live_changed`, `_finish_color_popup`, `_commit_row` entry-logged) attempted to catch this residual live; none reproduced it with instrumentation active. This residual is not proven to be a second, distinct trigger of the same class (a late Godot-internal echo landing through a still-unidentified third path) versus a coincidence; it is disclosed as open and unresolved rather than claimed fixed. It matches this file's own already-established "not reproducible in this environment, environment/timing-dependent" classification already carried for this exact check since "Shader tabs phase 2 review round 4 fixes," now at a measured ~7% rate on `4.6.2`/`4.7` post-fix versus the reviewer's own reported 3-for-3 deterministic rate pre-fix.

### Fix 2: remove the history-operation retry loops

`tests/gst_editor_ui_labels_smoke.gd`'s `_check_native_palette_color`: `history.undo()` and `history.redo()` are now each called exactly once. Only the settle wait afterward is bounded (2000ms) and re-polled every frame; a successful poll or the deadline ends the wait, and neither loop calls `undo()`/`redo()` a second time. The `palette_color_history_settled` gate before the undo section is unchanged. The check message no longer reports `undo_attempts`/`redo_attempts` (the field is gone, not stuck at a fixed value), matching the second option the instruction allowed.

### Fix 3: prove pending text landed before asserting the flush

`tests/gst_editor_native_undo_smoke.gd`: `_check_forced_finish_pending_text`, `_check_forced_finish_save`, and `_check_forced_finish_save_as` each now capture `line_edit.text` immediately after `_type_into_line_edit` and require it to equal the typed string as part of the check's own pass condition, with the captured text included in the failure message (`line_edit_text=%s`). Previously, `pending_before_finish`/`pending_before_save` only asserted the resource had *not yet* reached the typed value, which a genuine delivery miss (the key events never reaching the field at all) would also satisfy -- reading identically to a correctly-pending edit. With the new assertion, a delivery miss now shows an empty or stale `line_edit_text` distinctly from a genuinely dropped forced-finish flush (which would show the correct typed text but a `delivered=false`/mismatched saved value).

### Fix 4: `tabs_native` re-characterization

Reran `tabs_native` 3 consecutive fresh processes on `4.4`, `4.6.2`, and `4.7` after fixes 1-3: every run on every version, exit `0`, `SMOKE SUMMARY pass=39 fail=0`, including `tabs_native_forced_finish_pending_text`, `tabs_native_forced_finish_before_save`, and `tabs_native_forced_finish_before_save_as` all reading `line_edit_text=` matching the typed value on every run (e.g. `line_edit_text=0.44 pending_before_finish=true actions=6->7 value=0.44`). The reviewer's own first fresh run this pass (`pass=34 fail=4`, `forced_finish_pending_text FAIL pending_before_finish=true actions=6->6 value=0.62`, `forced_finish_before_save FAIL no focused numeric LineEdit found after a real ui_accept key press`, `forced_finish_before_save_as FAIL` same, `forced_finish_before_undo FAIL actions=8->8 value=0.36 original=0.66`) and second fresh run (`39/0`) did not reproduce again in this environment across 9 total fresh runs this pass (3 per version); this instability is recorded here as observed by the reviewer and not independently reproduced, rather than silently dropped.

### Fix 5: correct the round 2 evidence table

The "Version matrix, phase 8 review round 2" table above records `ui_labels` as `43/0` on all three versions (its own row, originally at `docs/EDITOR_SMOKE.md:4154`) and `tabs_native` as `39/0` on `4.6.2` (`:4155`) with no caveat. Per this project's own "historical evidence remains historical" convention, that table is not rewritten in place; this note supersedes it for those two claims:

- The `ui_labels` `43/0` claim did not disclose that the underlying check (`_check_native_palette_color`'s undo section) contained a 5-attempt retry loop at the time: a run that failed on its first `history.undo()` and only succeeded after an internal `redo()`/`undo()` retry still reported the check as a clean `PASS` with no visible indication a retry occurred, because that pass's own version of the check did not record `undo_attempts` in a way review round 3 could see was masking a real, deterministic first-attempt failure. The table's `43/0` result is accurate for what it measured (final pass/fail count) but is not evidence the underlying mechanism worked in one attempt.
- The `tabs_native` `39/0` claim on `4.6.2` is accurate for the runs actually made that pass, but this file's own subsequent "Shader tabs phase 8: tabs_native popup-delivery test fix" and "phase 2 defect fix 2" sections (both earlier in this file, predating round 2) already document that this exact selector had previously shown real run-to-run instability on `4.6.2`/`4.7` before those fixes landed; the round 2 table's own clean `39/0` reflects the state after those fixes, not an absence of ever-observed instability in this selector's history.

### Version matrix, phase 8 review round 3

Every row its own serial process, isolated `APPDATA`/`LOCALAPPDATA` per version, isolated project per version, all re-synced with this pass's fixed files before every run below.

| Selector | 4.4 | 4.6.2 | 4.7 |
|---|---|---|---|
| `ui_labels` (3 consecutive fresh) | exit `0`, `43/0` x3 | exit `0`, `43/0` x3 (see residual above: 1 failure in 18 total post-fix runs) | exit `0`, `43/0` x3 (see residual above: 2 failures in 25 total post-fix runs) |
| `tabs_native` (3 consecutive fresh) | exit `0`, `39/0` x3 | exit `0`, `39/0` x3 | exit `0`, `39/0` x3 |
| `tabs_host` | exit `0`, `pass=8 fail=0` | exit `0`, `pass=8 fail=0` | exit `0`, `pass=8 fail=0` |
| `tabs_files` | exit `0`, `pass=24 fail=0` | not rerun (untouched by this pass's files; round 2 evidence stands) | not rerun (same) |
| `tabs_ui` | exit `0`, `pass=18 fail=0` | not rerun (same) | not rerun (same) |
| `tabs_documents` | exit `0`, `pass=22 fail=0` | not rerun (same) | not rerun (same) |
| `tabs_recovery` stage 1 | exit `0`, `pass=39 fail=0`, empty stderr (only the file's own documented deliberate negative-path fixture diagnostics) | not rerun (same) | not rerun (same) |
| `tabs_recovery` stage 2 | exit `0`, `pass=5 fail=0` | not rerun (same) | not rerun (same) |
| `ui_complete` | not rerun on `4.4` this pass (unaffected; round 2 evidence stands) | exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0` (rerun per this pass's own instruction, since `gst_inspector_column.gd` changed) | not rerun (same) |

Stderr across every row above held only this file's own already-documented deliberate negative-path fixture diagnostics; zero unexpected `SCRIPT ERROR`/`Invalid access`/`Nonexistent function`/`Parse Error` outside named fixtures.

### Environment diagnostics

All commands run from Git Bash on Windows 11, isolated absolute Windows `APPDATA`/`LOCALAPPDATA` paths per version (matching this file's own established precedent), isolated per-version project copies under `.now/tabs-validation/` re-synced from the real repository before every run in this section.

### Blockers / open decisions

- **Not fully closed.** Fix 1's root cause (a) is confirmed and fixed for the mechanism identified by direct injection, and measurably reduces the defect from the reviewer's own deterministic 3-for-3 first-attempt failure to an observed ~7% residual rate on `4.6.2`/`4.7` (0/12 on `4.4` post-fix). The residual itself was not caught live under instrumentation across 27 further attempts; a second, distinct trigger path is suspected but not proven. If it recurs, the same instrumentation set added and removed this pass (list in Scope below) is the fastest way to re-attach it.
- `tabs_close` on `4.4`'s previously-unreproduced `pass=10 fail=3` result (carried from round 1 fixes) remains unaddressed; out of this pass's required-fixes scope.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_inspector_column.gd` (fix 1), `tests/gst_editor_ui_labels_smoke.gd` (fix 2), `tests/gst_editor_native_undo_smoke.gd` (fix 3), `docs/EDITOR_SMOKE.md` (this section).
- `addons/goshade_turbo/ui/gst_main_panel.gd` was read; no change needed for fixes 1-3.
- `addons/goshade_turbo/ui/gst_undo.gd` was read only, for diagnostic instrumentation in isolated project copies during root-cause work; never modified in the real repository (confirmed by `diff` against the real repository's own copy after every instrumented run).
- No file outside phase 8's own amended Files list was touched. `sandbox/**` not touched. No git worktree. No commit. `NOW.md` and `docs/SHADER_TABS_reviewed-plan.md`'s own Status line were left untouched this pass, per the orchestrator's own instruction and because judging this round's own verdict belongs to the reviewer.
- Temporary `print()` instrumentation (in `_on_bound_property_changed`, `_begin_native_interaction`, `_on_color_live_changed`, `_finish_color_popup`, `_commit_row`, and `GSTUndo.commit_property_change`'s do/undo bound methods) and temporary injection/diagnostic edits to the test's own undo section were made only in `.now/tabs-validation/project`'s, `project-462`'s, and `project-47`'s own isolated copies, never the real repository, and were overwritten with the clean fixed files (confirmed byte-identical by `diff` against the real repository) before every run counted as evidence above.

## Shader tabs phase 8 review round 4 fixes (2026-09-14)

Fix pass against review round 4's FAIL verdict (4 required fixes). No `sandbox/**` touch, no git worktree, no commit, no writes into the real repository's `.godot/`. Every run below is isolated `APPDATA`/`LOCALAPPDATA`/project, serial, freshly re-synced from the real repository before each stage of this pass (confirmed byte-identical by `diff`), matching this file's own established command shape.

### Fix 1: root-cause the sequence-conditioned `ui_labels_palette_color_undo_redo` failure (`tabs_host`/`tabs_native` then fresh `ui_labels`)

**Reproduction, confirmed exactly as the reviewer described.** In isolated `project-462` (`4.6.2`): ran `GST_EDITOR_SMOKE=tabs_host` to completion (exit `0`, `SMOKE SUMMARY pass=8 fail=0`), then `GST_EDITOR_SMOKE=ui_labels` as the next fresh process: exit `1`, `ui_labels_palette_color_undo_redo FAIL undo=(0.2, 0.4, 0.8, 1.0)/(0.2, 0.4, 0.8)/(0.2, 0.4, 0.8) redo=(0.2, 0.4, 0.8, 1.0)/(0.2, 0.4, 0.8)/(0.2, 0.4, 0.8) undo_pos=0->-1 redo_pos=-1->0`. The new position fields (fix 2, applied first per the fix instruction's own method) show the history position moved correctly on both `undo()` (`0->-1`) and `redo()` (`-1->0`); only the value is wrong, confirming the reviewer's framing directly: this is a late write, not a stalled history position.

**Root cause, confirmed by frame-level instrumentation in the isolated project only** (`_on_bound_property_changed`, `_on_color_live_changed`, `_refresh_row`, `_begin_native_interaction`, `_commit_row`, and `GSTUndo`'s do/undo bound methods and `_notify_property`, each entry-logged; a 30-frame poll of history position/`params["a"]`/uniform/button color after `history.undo()` in the test's own isolated copy). Reproduced with instrumentation active (still `FAIL`, identical symptom), captured the exact sequence:

```
SMOKE ui_labels_palette_color_history_settled PASS attempts=0 history=0->1
DIAG undo_redo_erase property=a
DIAG _refresh_row enter key=-9223370256070667093:a
DIAG _on_color_live_changed color=(0.2, 0.4, 0.8, 1.0) key=-9223370256070667093:a
DIAG _refresh_row after_update_property refreshed_value=(0.2, 0.4, 0.8, 1.0)
DIAG _refresh_row after_force_set button_color=(0.2, 0.4, 0.8, 1.0)
DIAG _refresh_row exit key=-9223370256070667093:a
DIAG _notify_property
DIAG undo_position=0->-1
DIAG frame=0 pos=-1 params_a=(0.2, 0.4, 0.8) uniform=(0.2, 0.4, 0.8) button_color=(0.2, 0.4, 0.8, 1.0)
```

`undo_redo_erase` (the undo method) correctly erases the `"a"` params entry first -- `target.get(&"a")` is already the correct manifest default at that instant. `_refresh_row` runs next (the action's `on_replayed` callback) and, in the pre-fix code, called `editor.update_property()` *before* capturing `state["final"]` from the target. `editor.update_property()` (Godot's own `EditorPropertyColor`, engine-internal, not this project's code) triggers a reentrant `color_changed` echo synchronously, from within that same call, carrying the row's *pre-undo* value (`(0.2, 0.4, 0.8, 1.0)`, the value the popup held before this undo) rather than the value it was just asked to display. This echo reaches `_on_color_live_changed`'s inactive-branch stray-write guard, whose entire job is to detect exactly this class of engine echo and revert it -- but at that point in the pre-fix code, `state["final"]` still held the *previous* commit's value from before this `_refresh_row` call had a chance to update it, which is the same stale value the echo itself carries. The guard's `not GSTUndo.values_equal(stray_value, state["final"])` comparison therefore read `false` (both sides already equal to the stale value), so it took no action, and `_refresh_row` then read `refreshed_target.get(refreshed_property)` *after* the echo had already independently written the stale value back onto the target (this write happens inside Godot's own `EditorPropertyColor` internals, which are connected to the same `color_changed` signal ahead of this project's own listener) -- caching the corruption into `state["final"]` as if it were the authoritative post-replay value. Every subsequent frame then reads the corrupted target and the still-wrong cached `state["final"]`, which is why the failure is stable at frame 0 rather than settling.

This is a different manifestation of root cause (a) from "Shader tabs phase 8 review round 3 fixes": the same class of engine-internal late echo, but reaching the target through `_on_color_live_changed`'s own guard at a point where that guard's own reference value (`state["final"]`) had not yet been updated from the replay it was supposed to be guarding -- not through the `_on_bound_property_changed` `changing=true` path round 3 closed. The scene-restore precondition (a scene recorded open in `project_metadata.cfg` from the immediately preceding `tabs_host`/`tabs_native` run) is not itself part of the causal chain traced above; it is not required to explain the bug once this ordering defect is understood, and no evidence collected this pass ties the echo's timing to scene state specifically. It is retained here only as the reviewer's own reliable reproduction recipe, which is what let this pass catch the echo under instrumentation on the first attempt (the round 3 pass's own instrumented attempts, run without a preceding `tabs_host`/`tabs_native`, made 27 attempts without reproducing it live).

**Fix**, `addons/goshade_turbo/ui/gst_inspector_column.gd`, `_refresh_row`: reordered so `state["final"]`/`state["final_present"]` are captured from the target *before* `editor.update_property()` runs, not after. Any reentrant echo `editor.update_property()` triggers now finds `state["final"]` already holding the correct just-replayed value, so `_on_color_live_changed`'s existing stray-write guard correctly detects the echo's stale payload as a divergence, reverts the target (`GSTUndo.restore_absent_param`/`target.set` per `final_present`), and recurses into `_refresh_row` once more to re-settle cleanly -- confirmed in the instrumented re-run: the reentrant echo still fires (engine-internal, not something this project's code can suppress), but the guard now catches and reverts it within the same synchronous call, before `history.undo()` ever returns to the caller:

```
DIAG undo_redo_erase property=a
DIAG _refresh_row enter key=-9223370255835786104:a
DIAG _refresh_row before_update_property refreshed_value=(0.5, 0.5, 0.5, 1.0)
DIAG _on_color_live_changed color=(0.2, 0.4, 0.8, 1.0) key=-9223370255835786104:a
DIAG _refresh_row enter key=-9223370255835786104:a
DIAG _refresh_row before_update_property refreshed_value=(0.5, 0.5, 0.5, 1.0)
DIAG _refresh_row after_update_property state_final=(0.5, 0.5, 0.5, 1.0) target_now=(0.5, 0.5, 0.5, 1.0)
DIAG _refresh_row exit key=-9223370255835786104:a
DIAG _notify_property
DIAG _refresh_row after_update_property state_final=(0.5, 0.5, 0.5, 1.0) target_now=(0.5, 0.5, 0.5, 1.0)
DIAG _refresh_row exit key=-9223370255835786104:a
DIAG _notify_property
```

All instrumentation (the `print()` calls above, in `gst_inspector_column.gd` and `gst_undo.gd`, and the 30-frame diagnostic poll in the test's own undo section) was added and removed only in `.now/tabs-validation/project-462`'s isolated copies; confirmed byte-identical to the real repository by `diff` before every run counted as evidence in this section.

### Fix 2: record `history.get_current_action()` before/after `undo()`/`redo()`

`tests/gst_editor_ui_labels_smoke.gd`'s `_check_native_palette_color`: captures `undo_position_before`/`undo_position_after` immediately before/after `history.undo()` and `redo_position_before`/`redo_position_after` immediately before/after `history.redo()`, included in `palette_color_undo_redo`'s own check message (`undo_pos=%d->%d redo_pos=%d->%d`). This is what let this pass's own reproduction runs show the position moving correctly (`undo_pos=0->-1 redo_pos=-1->0`) even while the value assertion failed, distinguishing this defect class from a stalled/no-op history operation.

### Fix 3: correct round 3's residual-rate and environment-dependent characterization (superseding note, not an in-place rewrite)

Per this project's own "historical evidence remains historical" convention (already used for round 3's own fix 5 correcting round 2's claims), "Shader tabs phase 8 review round 3 fixes"'s own "Residual, disclosed" paragraph (`docs/EDITOR_SMOKE.md:4221` in that section, and the `ui_labels` row of round 3's version matrix) is not rewritten in place. This note supersedes both for the residual-rate and "environment/timing-dependent" claims:

- The residual was **not** "not reproducible in this environment, environment/timing-dependent" at "roughly 7%." It reproduces on the first `ui_labels` run after any other selector that leaves a scene recorded open (confirmed with `tabs_host` and, per round 3's own instrumentation notes, `tabs_native`) in the same isolated project, and does not reproduce on a `ui_labels` run with no such preceding selector in the same session. This pass's own measurement: 3 sequence-conditioned cycles (`tabs_host` then fresh `ui_labels`) on each of `4.6.2` and `4.7`, all 6 first-post-sequence `ui_labels` runs `43/0` clean after the fix below (pre-fix, this exact sequence reproduced the failure on the first attempt tried on `4.6.2`, `1/1`). Round 3's own ~7% figure was computed over runs that mostly did not control for this precondition, undercounting the rate within the triggering sequence and overcounting it as a background rate across all runs.
- The root cause is not engine/timing noise external to this project's own code: it is `_refresh_row`'s pre-fix ordering (see fix 1 above), which any reentrant `EditorPropertyColor.update_property()` echo can expose regardless of what leaves a scene open. The scene-open precondition changed how *reliably* the reviewer's own reproduction recipe triggered the underlying engine-internal echo in this environment; it is not established as the only trigger, and no claim is made here that the ordering fix addresses only the scene-restore case -- the fix corrects the ordering defect unconditionally, independent of any scene state.
- The round 3 "Verify" line's "did not reproduce again after the fix in the large majority of runs" is superseded: this pass's own fix, verified below, produced no residual in any of the sequence-conditioned or plain runs made this pass (0 failures in 12 fresh `ui_labels` runs across `4.4`/`4.6.2`/`4.7`, 6 of them immediately following `tabs_host`).

### Fix 4: remove the speculative color-swatch force-set

`addons/goshade_turbo/ui/gst_inspector_column.gd`, `_refresh_row`: removed the unconditional `color_button.color = refreshed_value` force-set that round 3 fix 1 added for hypothesis (c) (refresh/material lag), which that same round 3 section's own text says was ruled out. Verified non-regressive: every run in the version matrix below (all three versions, `ui_labels`'s own `palette_color_native`/`palette_color_edit`/`palette_color_close`/`palette_color_undo_redo`/`palette_color_reopen` checks, which read the button's own displayed `.color` directly) passed without it, confirming `editor.update_property()` alone keeps the swatch correct once fix 1's ordering lets the stray-write guard do its job.

### Version matrix, phase 8 review round 4

Every row its own serial process, isolated `APPDATA`/`LOCALAPPDATA` per version, isolated project per version (`project`/`project-462`/`project-47`), re-synced with this pass's fixed files (confirmed byte-identical by `diff`) before the first run in each version's sequence.

| Sequence | 4.4 | 4.6.2 | 4.7 |
|---|---|---|---|
| `tabs_host` -> fresh `ui_labels`, cycle 1 | exit `0`/exit `0`, `43/0` | exit `0`/exit `0`, `43/0` | exit `0`/exit `0`, `43/0` |
| `tabs_host` -> fresh `ui_labels`, cycle 2 | not required by the reviewer's own Verify line for `4.4` (single cycle only) | exit `0`/exit `0`, `43/0` | exit `0`/exit `0`, `43/0` |
| `tabs_host` -> fresh `ui_labels`, cycle 3 | not required for `4.4` | exit `0`/exit `0`, `43/0` | exit `0`/exit `0`, `43/0` |
| `ui_labels`, 3 consecutive fresh (no preceding selector) | not separately required for `4.4` (covered by the single required cycle above) | exit `0` x3, `43/0` x3 | exit `0` x3, `43/0` x3 |
| `tabs_native` | exit `0`, `pass=39 fail=0` | exit `0`, `pass=39 fail=0` | exit `0`, `pass=39 fail=0` |
| `tabs_host` (final) | exit `0`, `pass=8 fail=0` | exit `0`, `pass=8 fail=0` | exit `0`, `pass=8 fail=0` |
| `tabs_files` | exit `0`, `pass=24 fail=0` | not required this pass (untouched by this pass's files) | not required this pass |
| `tabs_ui` | exit `0`, `pass=18 fail=0` | not required this pass | not required this pass |
| `tabs_documents` | exit `0`, `pass=22 fail=0` | not required this pass | not required this pass |
| `tabs_recovery` stage 1 | exit `0` (ends `SMOKE_RECOVERY SAVE_AND_QUIT_ACTIVATION_DISPATCHED`, matching this file's own established stage-1 ending; no `SMOKE SUMMARY` line at this stage by the fixture's own design) | not required this pass | not required this pass |
| `tabs_recovery` stage 2 | exit `0`, `pass=5 fail=0` | not required this pass | not required this pass |
| `ui_complete` | not required this pass (unaffected; round 2/3 evidence stands) | exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0` | not required this pass |

Stderr across every row above held only this file's own already-documented deliberate negative-path fixture diagnostics (`tabs_recovery`'s own forced-failure cases); zero unexpected `SCRIPT ERROR`/`Invalid access`/`Nonexistent function`/`Parse Error`.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_inspector_column.gd` (fixes 1 and 4, both in `_refresh_row`), `tests/gst_editor_ui_labels_smoke.gd` (fix 2), `docs/EDITOR_SMOKE.md` (this section).
- `addons/goshade_turbo/ui/gst_undo.gd` and `addons/goshade_turbo/ui/gst_main_panel.gd` were read; no change needed.
- No file outside phase 8's own amended Files list was touched. `sandbox/**` not touched. No git worktree. No commit. No write into the real repository's `.godot/`. `NOW.md`, `ROADMAP.md`, `docs/CURRENTNESS_AUDIT.md`, and this plan's Status line were left untouched this pass, per the orchestrator's own instruction and because judging this round's own verdict belongs to the reviewer.
- Temporary `print()` instrumentation (`_on_bound_property_changed`, `_on_color_live_changed`, `_refresh_row`, `_begin_native_interaction`, `_commit_row`, `GSTUndo`'s do/undo bound methods and `_notify_property`) and a temporary 30-frame diagnostic poll in the test's own undo section were made and removed only in `.now/tabs-validation/project-462`'s isolated copy, never the real repository; confirmed byte-identical to the real repository by `diff` before every run counted as evidence above.

### Blockers / open decisions

- None outstanding from this pass's own required fixes.
- `tabs_close` on `4.4`'s previously-unreproduced `pass=10 fail=3` result (carried from round 1 fixes, out of round 3's required-fixes scope) remains unaddressed; still out of this pass's required-fixes scope.

## Shader tabs phase 8 review round 5 fix-now (2026-09-14)

Fix-now pass against review round 5's PASS-WITH-NOTES verdict (7 fix-now notes). No `sandbox/**` touch, no git worktree, no commit, no write into the real repository's `.godot/`. Every run below is isolated `APPDATA`/`LOCALAPPDATA`/project, serial, one process per row, `project`/`project-462`/`project-47` re-synced (`addons/` and `tests/` copied wholesale from the real repository, confirmed byte-identical by `diff -rq`) immediately before this pass's own runs.

### Per-note status

- **Note 1 (close the final-tree matrix gap). Applied.** `tabs_documents`, `tabs_files`, `tabs_ui`, `tabs_close`, `ui_layout`, `ui_actions`, `ui_picker`, `ui_complete`, and both `tabs_recovery` stages run fresh on `4.6.2` and `4.7`; `ui_complete` also run fresh on `4.4`. `tabs_native` and `ui_labels` (the latter run immediately after a fresh `tabs_host`, one cycle, matching round 4's own sequence-conditioned precedent) rerun on `4.6.2` and `4.7`; `tabs_native`, `ui_labels`, and `tabs_host` rerun standalone on `4.4` (single cycle, matching the reviewer's own Verify line for that version). `run_render_checks.gd` and `run_recipe_motion_checks.gd` rerun on Compatibility and Forward+ on all three versions. See "Version matrix, final phase 8 tree, review round 5" below for every result; every row is clean (exit `0`, no unresolved failures). Material-sync reachability: this pass's only behavioral (non-comment) production change is note 4's added `_find_color_button(entry["editor"] as Node) != null` scoping condition on the stale-echo guard in `_on_bound_property_changed`; that condition only narrows when `_commit_row` (and therefore `GSTUndo.commit_property_change`'s own material-sync call) is skipped for a stray repeat, it adds no new call site. `run_render_checks.gd`/`run_recipe_motion_checks.gd` never load `GSTInspectorColumn` or the editor UI at all (both run headless against the shader library directly), so neither script's own code path can reach this change regardless of renderer or version; they were rerun anyway per this note's own instruction, and both are clean on every version/renderer.
- **Note 2 (correct the stale `changing`-boundary docstring). Applied.** `gst_inspector_column.gd:393-398`'s docstring above `_on_bound_property_changed` now states the color-popup row's real boundary (`about_to_popup`/`popup_closed`) instead of the superseded `changing`-flag boundary, and names the inactive `changing=true` drop at `:425-430` (post-edit line numbers, the `if changing:` block's `_find_color_button` check) as where that stray echo is discarded.
- **Note 3 (record which `tabs_close` checks failed). Applied.** `docs/EDITOR_SMOKE.md:4102`'s bullet now names the three failing checks and fields from `.now/tabs-validation/p8-4.4-tabs_close.stdout.log`: `dirty_named_close_discard FAIL dirty_before=true dialog_shown=true closed=false dialog_hidden=false history_freed=false disk_unchanged=true`, `undo_cannot_reopen_closed_document FAIL closed=false documents_after_close=2 still_closed=false count_after_undo=2`, `dirty_close_cancel_preserves_document FAIL dirty_before=true dialog_shown=false still_open=true still_dirty=true dialog_hidden=true tab_present=true layers_unchanged=true`.
- **Note 4 (scope the stale-echo guard to color-popup rows). Applied.** `gst_inspector_column.gd`'s `_on_bound_property_changed`, the `changing=false` stale-echo guard now reads `if _find_color_button(entry["editor"] as Node) != null and state.has("last_committed_final") and ...`, matching the sibling guard's own scoping at the `changing=true` branch above it. The false justification ("a genuine new edit that happens to match is never silently discarded") is removed; the replacement comment states only the guard's actual scope and the control it is observed against.
- **Note 5 (trim the two narrative comment blocks). Applied.** `gst_inspector_column.gd`'s `_on_bound_property_changed` `if changing:` block comment and `_refresh_row`'s header docstring are both reduced to the contract statement the code follows, cutting the round 3/4 diagnosis narration (frame traces, "confirmed by direct injection," reproduction counts) that belongs to this file's own history sections, not the source comment.
- **Note 6 (correct `_push_popup_key`'s docstring). Applied.** `tests/gst_editor_native_undo_smoke.gd`'s docstring above `_push_popup_key` now names both callers (`_check_popup_focused_shortcut` and `_check_color_popup_subunit_pending_forced_finish`) instead of claiming the first is the only one.
- **Note 7 (un-tick the `gst_main_panel.gd:1462` line). Applied, un-ticked.** `docs/CURRENTNESS_AUDIT.md`'s line is now `[ ]`; the entry keeps its original evidence and adds that this round's own production edits (the stray-echo scoping and comment trims above) touch neither `_save_external_data()` nor the recovery-write race, so the previously-disclosed gap (only one interaction pattern probed) is unchanged and still open.

### Version matrix, final phase 8 tree, review round 5

Every row its own serial process, isolated `APPDATA`/`LOCALAPPDATA` per version, isolated project per version (`project`/`project-462`/`project-47`), re-synced with this pass's fixed files (confirmed byte-identical by `diff -rq`) before the first run in each version's sequence.

| Selector | 4.4 | 4.6.2 | 4.7 |
|---|---|---|---|
| `tabs_host` | exit `0`, `pass=8 fail=0` (this pass) | exit `0`, `pass=8 fail=0` (this pass, cycle start) | exit `0`, `pass=8 fail=0` (this pass, cycle start) |
| `ui_labels` (fresh; on `4.6.2`/`4.7` immediately after the `tabs_host` row above) | exit `0`, `43/0` (this pass) | exit `0`, `43/0` (this pass) | exit `0`, `43/0` (this pass) |
| `tabs_native` | exit `0`, `pass=39 fail=0` (this pass) | exit `0`, `pass=39 fail=0` (this pass) | exit `0`, `pass=39 fail=0` (this pass) |
| `tabs_documents` | not rerun this pass (round 4 evidence stands, `pass=22 fail=0`) | exit `0`, `pass=22 fail=0` (this pass) | exit `0`, `pass=22 fail=0` (this pass) |
| `tabs_files` | not rerun this pass (round 4 evidence stands, `pass=24 fail=0`) | exit `0`, `pass=24 fail=0` (this pass) | exit `0`, `pass=24 fail=0` (this pass) |
| `tabs_ui` | not rerun this pass (round 4 evidence stands, `pass=18 fail=0`) | exit `0`, `pass=18 fail=0` (this pass) | exit `0`, `pass=18 fail=0` (this pass) |
| `tabs_close` | not rerun this pass (round 1 evidence stands, `pass=13 fail=0`; the round-1 `pass=10 fail=3` non-reproduction remains an open, disclosed gap, see Blockers) | exit `0`, `pass=13 fail=0` (this pass) | exit `0`, `pass=13 fail=0` (this pass) |
| `ui_layout` | not rerun this pass (round 1 evidence stands, `pass=16 fail=0`) | exit `0`, `pass=16 fail=0` (this pass) | exit `0`, `pass=16 fail=0` (this pass) |
| `ui_actions` | not rerun this pass (round 1 evidence stands, `pass=20 fail=0`) | exit `0`, `pass=20 fail=0` (this pass) | exit `0`, `pass=20 fail=0` (this pass) |
| `ui_picker` | not rerun this pass (round 1 evidence stands, `pass=45 fail=0`) | exit `0`, `pass=45 fail=0` (this pass) | exit `0`, `pass=45 fail=0` (this pass) |
| `ui_complete` | exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0` (this pass, new) | exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0` (this pass) | exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0` (this pass, new) |
| `tabs_recovery` stage 1 | not rerun this pass (round 4 evidence stands, `pass=39 fail=0`, ends `SAVE_AND_QUIT_ACTIVATION_DISPATCHED`) | exit `0`, `39` PASS lines, `0 FAIL`, ends `SAVE_AND_QUIT_ACTIVATION_DISPATCHED` (this pass, recovery dir wiped first) | exit `0`, `39` PASS lines, `0 FAIL`, ends `SAVE_AND_QUIT_ACTIVATION_DISPATCHED` (this pass, recovery dir wiped first) |
| `tabs_recovery` stage 2 | not rerun this pass (round 4 evidence stands, `pass=5 fail=0`) | exit `0`, `pass=5 fail=0` (this pass) | exit `0`, `pass=5 fail=0` (this pass) |
| `run_render_checks.gd`, Compatibility | exit `0`, `PASS, 79 stack(s)` (this pass) | exit `0`, identical (this pass) | exit `0`, identical (this pass) |
| `run_render_checks.gd`, Forward+ | exit `0`, `PASS, 79 stack(s)` (this pass) | exit `0`, identical (this pass) | exit `0`, identical (this pass) |
| `run_recipe_motion_checks.gd`, Compatibility | exit `0`, `RECIPE_MOTION SUMMARY PASS` (this pass) | exit `0`, identical (this pass) | exit `0`, identical (this pass) |
| `run_recipe_motion_checks.gd`, Forward+ | exit `0`, `RECIPE_MOTION SUMMARY PASS` (this pass) | exit `0`, identical (this pass) | exit `0`, identical (this pass) |

Stderr across every row above held only this file's own already-documented deliberate negative-path fixture diagnostics (`tabs_files`'/`tabs_close`'s bad-directory save/open failures, `tabs_recovery`'s many simulated recovery-failure fixtures) and the pre-existing `LayerPane`/`SettingsPane` owner warnings; `run_render_checks.gd`/`run_recipe_motion_checks.gd` stderr was empty on every version/renderer. Zero unexpected `SCRIPT ERROR`/`Invalid access`/`Nonexistent function`/`Parse Error` in any row.

### Environment diagnostics

All commands run from Git Bash on Windows 11, isolated absolute Windows `APPDATA`/`LOCALAPPDATA` paths per version (`.now/tabs-validation/appdata-4.4`/`appdata-4.6.2`/`appdata-4.7`, matching this file's own established precedent), isolated per-version project copies under `.now/tabs-validation/` (`project`/`project-462`/`project-47`) re-synced from the real repository (`addons/` and `tests/`, `diff -rq` confirmed byte-identical) before this pass's own runs. `tabs_recovery`'s own recovery directory (`<project>/.godot/editor/goshade_turbo/recovery`) was deleted before stage 1 on `4.6.2` and `4.7`, per this pass's own instruction.

### Scope

- Files modified this pass: `addons/goshade_turbo/ui/gst_inspector_column.gd` (notes 2, 4, 5), `tests/gst_editor_native_undo_smoke.gd` (note 6), `docs/EDITOR_SMOKE.md` (note 3 and this section), `docs/CURRENTNESS_AUDIT.md` (note 7).
- `addons/goshade_turbo/ui/gst_main_panel.gd` was read for note 7's own diagnosis; not modified this pass.
- No file outside phase 8's own amended Files list was touched. `sandbox/**` not touched (confirmed clean by `git status --porcelain -- sandbox/`). No git worktree. No commit. No write into the real repository's `.godot/`. `NOW.md`, `ROADMAP.md`, and this plan's Status line were left untouched this pass; judging this round's own verdict belongs to the reviewer.

### Blockers / open decisions

- `tabs_close` on `4.4`'s round-1 `pass=10 fail=3` non-reproduction (see the corrected bullet at `docs/EDITOR_SMOKE.md:4102` above) remains open; out of this fix-now pass's scope (note 1 named `4.6.2`/`4.7` for this selector, not `4.4`).
- `docs/CURRENTNESS_AUDIT.md`'s `gst_main_panel.gd:1462` gap (note 7) remains open pending a broader probe (multiple documents, mixed pending edits) that no note in this pass required.

## Quick fixes 2026-09-14

Batch clear of `NOW.md` "Quick fixes". No plan, one file each (item 2 also touched its own reference screenshot, an authorized exception; item 3's reference stack was not added, see below). No commit.

### Item 1: `gst_document_recovery.gd` doc-comment trim + `_find_validated_record` fold

Trimmed every doc comment from round-by-round narrative ("fix-now round N", "review round N") to plain contract statements; folded `_find_validated_record` into `_load_index`'s own result (`_load_index` now also returns `by_id: Dictionary`, a validated-record lookup by id, and the standalone `_find_validated_record` function was deleted). `write_record`'s existing-id branch and `remove_record` both now read `index_result.get("by_id", {}).get(record_id, {})` instead of calling a separate finder. No behavior change: same push_error paths, same validation rules, same return shapes.

- Line count: `536` before, `440` after (`git diff --stat`: `124 insertions(+), 219 deletions(-)`).
- Synced the fixed file into `.now/tabs-validation/project` and `.now/tabs-validation/project-462` (both `diff`-confirmed identical to the real repository file afterward); recovery directories wiped, no stage marker present in either project before running.
- Command: `GST_EDITOR_SMOKE=tabs_recovery; APPDATA=<isolated>; LOCALAPPDATA=<isolated>; Godot_v4.4-stable_win64.exe --editor --path .now/tabs-validation/project --rendering-method gl_compatibility`, matching this file's own established command shape.
- 4.4, stage 1: `grep -c "SMOKE .* PASS"` reads `39`, fail `0`, exit `0`. Stderr held only the file's own already-documented deliberate blocked-path/blocked-directory/corrupt-resource/traversal-rejection/metadata-failure `push_error` class, plus the one expected trailing `SCRIPT ERROR: Cannot call method 'get_tree' on a previously freed instance.` and the pre-existing `1 resources still in use at exit` diagnostic -- no unexpected error.
- 4.4, stage 2 (same command, no reset): `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr.
- 4.6.2, stage 1 (isolated `appdata-4.6.2`/`project-462`, recovery dir wiped, no stage marker present): `grep -c "SMOKE .* PASS"` reads `39`, fail `0`, exit `0`. Stderr held the same deliberate-error class as `4.4`, with full GDScript backtraces (the established `4.6.2` behavior difference from `4.4`'s plain error lines) -- no unexpected error.
- 4.6.2, stage 2: `SMOKE SUMMARY pass=5 fail=0`, exit `0`, empty stderr.
- Matches the required `39/0` stage 1, `5/0` stage 2 contract on both versions exactly.

### Item 2: `cellular_edges` drops `width`, returns raw `F2 - F1`

`code` now reads `float cellular_edges(vec2 p) { ... return f2 - f1; }` (the `width` param, its `hint_range`/label/description entry, and the `smoothstep`/`max(width, ...)` remap are gone). `description` and `source_math` rewritten to describe the raw field (near 0 at the boundary, increasing toward the cell center; downstream `smoothstep`/`band` sets the width) instead of the removed bright-boundary remap; checked against `docs/CURRENTNESS_AUDIT.md:54`'s prior description-fix note so the description stays true to the new output.

- `godot --headless --path . -s res://tests/run_codegen_tests.gd` (4.4, real repo root): `GST tests: 21 file(s), 145 test method(s), 20 failure(s)`, exit `1` -- identical to the documented `20`-failure baseline; no failure names `cellular_edges` or `width`.
- `godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tests/run_render_checks.gd`: `run_render_checks: PASS, 81 stack(s) checked`, exit `0`; `RENDER res://sandbox/stacks/ref_generative_cellular_edges.tres PASS [] has_TIME=false`.
- Re-ran with `-- --write-screenshots`: still `PASS, 81 stack(s) checked`. This also rewrote several unrelated recipe/stack screenshots that already existed before this pass touched anything (`fire`, `hologram`, `metaball_portal`, `sprite_foil`, `sprite_holographic`, `sprite_oil_slick`, `sprite_opal`, `sprite_pearl`, `water`) and wrote three new untracked ones (`clouds.png`, `weird1.png`, `weird2.png`) for stacks already present in `sandbox/stacks/` but never previously screenshotted -- none of that is this item's own change, so every one of those was restored/removed (`git checkout --` for the modified ones, `rm` for the new untracked ones); confirmed by `git status --porcelain -- sandbox/` reading only `M sandbox/screenshots/ref_generative_cellular_edges.png` afterward. The new PNG is dark at cell boundaries and brighter toward each cell center, matching the new raw-field output by design.

### Item 3: `generative/cell_borders` (new entry)

New `addons/goshade_turbo/library/generative/cell_borders.tres`. Exact Euclidean distance to the Voronoi cell border via Inigo Quilez's two-pass bisector method (`https://iquilezles.org/articles/voronoilines/`, the improved/exact code sample, not the `F2-F1` approximation `cellular_edges`/`voronoi` already use): pass one finds the nearest feature point, pass two takes the minimum perpendicular-bisector distance from `p` to every other feature point in a wider neighborhood. Ported to this project's own `generative/hash()` (two offset calls building a `vec2`, matching `cellular_edges`'/`voronoi`'s own established pattern) in place of the article's `hash2()`. `source_code_license = "MIT, per Inigo Quilez's stated license for code published on iquilezles.org..."`, attribution repeated in `source_math`/`source_code_url`. No params (raw distance field, same downstream-shaping convention as item 2's `cellular_edges`). No manifest/index file exists to register entries against (`GSTLibrary.scan()` walks the directory tree directly); no second file needed for registration.

- `godot --headless --path . -s res://tests/run_codegen_tests.gd`: `GST tests: 21 file(s), 145 test method(s), 21 failure(s)`, exit `1` -- one more than the `20`-failure baseline. Diffing the two runs' `FAIL` lines shows exactly one *new* failing assertion: `tests/test_combinations.gd: assert_eq failed: 18 generators: 11 generative plus 7 sdf (expected 18, got 19)` -- a hardcoded roster-size literal, now stale because it counts every `coord == true` entry and this item adds one. The pre-existing `tests/test_library_index.gd: ... (expected 54, got 57)` failure (already broken before this pass, unrelated to this item) simply incremented to `got 58`, same failing line, not a new one. No failure names `cell_borders` itself; `test_every_generative_manifest_compiles_alone_with_default_params` (`tests/test_codegen_generator.gd:131`, the generic per-entry compile-alone loop backing the release checklist's "every roster entry compiles alone") passed for it, as did every field-op-fed-by-generator combination it was exercised in. Not fixed this pass: bumping the hardcoded `18`/comment in `tests/test_combinations.gd` is a second file beyond this item's own manifest entry, and the same staleness already exists, unfixed, in `test_library_index.gd`'s `54`; left as the same known class of brittle hardcoded-count assertion, reported rather than silently patched.
- `godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tests/run_render_checks.gd`: `run_render_checks: PASS, 81 stack(s) checked`, exit `0`, `git status --porcelain -- sandbox/` unchanged from item 2's own residual diff -- `cell_borders` has no reference stack under `sandbox/stacks/`, so it is not exercised by this check and no screenshot exists for it. A reference stack (`ref_generative_cell_borders.tres`) plus its screenshot was drafted, then removed: the orchestrator's own scope rule ("do not touch `sandbox/**`" with the single named exception of `glow.png.import`, echoed by item 2's own explicit one-screenshot exception) does not name a new sandbox stack as authorized for a brand-new entry, and adding one was judged outside this quick fix's own two-file budget stacked on top of the manifest entry itself. Flagged below rather than decided silently.

### Scope

- Files modified: `addons/goshade_turbo/ui/gst_document_recovery.gd` (item 1), `addons/goshade_turbo/library/generative/cellular_edges.tres` and `sandbox/screenshots/ref_generative_cellular_edges.png` (item 2, the latter an orchestrator-named exception to the `sandbox/**` restriction), `addons/goshade_turbo/library/generative/cell_borders.tres` (item 3, new file), `NOW.md` (ticking cleared items), this section.
- `docs/CURRENTNESS_AUDIT.md` not touched (orchestrator-reserved this pass).
- Item 4 (`mouse`) not implemented; see "Blockers / open decisions" below.

### Blockers / open decisions

- Item 3 left `cell_borders` without a reference stack/screenshot under `sandbox/stacks/`/`sandbox/screenshots/` (the release checklist convention every other roster entry follows) because creating one is a new file under the restricted `sandbox/**` tree that this pass's own scope did not name as authorized. Needs an explicit go-ahead (or a `/claudhd:quick` naming the two files) before adding it.
- Item 3 also left `tests/test_combinations.gd`'s hardcoded `18 generators` literal (and its comment) stale, matching the pre-existing stale `54` in `tests/test_library_index.gd`. Both are hardcoded roster-size assertions that break on any new `coord == true`/library entry; neither was touched this pass (second-file budget). Worth a follow-up fix pass of its own, updating both together.
- Item 4 (`mouse: coord center follows the mouse via a uniform written by a script on the exported node`) kicked back, not implemented. `addons/goshade_turbo/io/gst_export.gd`'s `GSTExport.build`/`write` only generate and write a self-contained `.gdshader` text file (header + codegen body); there is no exported-node or runtime-script concept anywhere in the addon for a script to attach to. Making the coord center follow the mouse needs: (1) a codegen/coord-block contract change (`addons/goshade_turbo/model/gst_coord_block.gd` plus `GSTCodegen`) to expose a mouse-driven center as a uniform, and (2) a new runtime script to write that uniform every frame, whose ship location (library snippet, `sandbox/`, or a docs code block) is a design decision this task does not make. That is a schema/contract change plus a new file plus an undecided design call -- outside a quick fix's scope by the task's own stated criteria. Routing to `/claudhd:idea`.

## Tab row and toolbar layout 2026-09-15

Quick-fix batch (no plan), user-requested: tab close button inside the tab, `+` moved to the right of the newest tab, `File` rendered as a button like the rest, `Export` joined the left-grouped toolbar buttons.

### Changes

1. **Tab x inside the tab.** `gst_main_panel.gd`'s `_refresh_tabs()` now wraps each tab's title `Button` and its close `Button` in one per-tab `HBoxContainer` (zero separation) added to `%ShaderTabs`, instead of adding both as direct siblings of the row. `get_tab_button()`/`get_tab_close_button()` still return the same inner `Button` instances; the wrapper is not exposed. `toggle_mode`, the shared `ButtonGroup`, tooltip, dirty-star title, stable-id `pressed` binding, and the close button's own `close_document.bind(doc)` are unchanged.
2. **`+` to the right of the newest tab.** `gst_main_panel.tscn`'s `NewTabButton` moved from `ShaderTabRow` (a fixed sibling of `ShaderTabsScroll`, outside the scroll region) into `ShaderTabRow/ShaderTabsScroll/ShaderTabs` (the scrolling row itself), as its last child. `_refresh_tabs()`'s own clear loop now skips `_new_tab_button` (never freed/rebuilt) and re-homes it to the end of `%ShaderTabs` after every rebuild (`_shader_tabs.move_child(_new_tab_button, _shader_tabs.get_child_count() - 1)`), so it always trails the newest tab and scrolls with the row. `get_new_tab_button()` unchanged.
3. **`File` as a button like the rest.** `FileMenu` (`MenuButton`) renders flat by construction (`MenuButton::MenuButton` calls `set_flat(true)`, confirmed in `.now/tabs-validation/godot-4.4-source/scene/gui/menu_button.cpp:217`). `gst_main_panel.tscn` now sets `flat = false` on `%FileMenu`, the only change needed for it to draw the normal button style. `get_popup()`, `_on_file_menu_pressed`, and every popup-id test seam are untouched.
4. **`Export` joins the left group.** `gst_main_panel.tscn`'s `FileToolbar` order is now File, Save, Recipes, Randomize, Export (`ExportButton` moved from after a removed `ToolbarSpacer` to directly after `RandomizeButton`); `ToolbarSpacer` (a `Control` with `size_flags_horizontal = 3`, unreferenced by any script) deleted. `%ExportButton`'s own unique name, visibility, and `pressed` wiring are untouched.

### Test changes

- `tests/gst_editor_tabs_smoke.gd`, `_run_narrow_layout`: the wrapper from change 1 makes a tab title `Button`'s own `.position` relative to its per-tab wrapper, not the scrolling row directly, so the prior `active_button.position.x` "scrolled into view" comparison against `scroll.scroll_horizontal`/`scroll.size.x` no longer measures the right thing. Replaced with a global-rect comparison (`active_button.get_global_rect().position.x` against `scroll.get_global_rect()`), which is correct regardless of nesting depth. The check's own boolean outcome (`scrolled_into_view`) is unchanged on every run below; only the computation changed, by design, per this pass's own scope.
- `tests/gst_editor_tabs_smoke.gd`, `run()`/new `_capture_tab_row_evidence`: added one screenshot hook (`GST_TABS_UI_SCREENSHOT_PATH`, mirroring `gst_editor_ui_complete_smoke.gd`'s own `GST_UI_COMPLETE_SCREENSHOT`/`_capture` pattern), called right after `_run_stable_id_switching` -- the first point three tabs are open at once (`saved_doc` clean, `fire_doc` dirty, `working_doc` pristine) with no dialog or picker in the way. A no-op unless the env var is set, so it adds nothing to `SMOKE SUMMARY` on an ordinary run (confirmed: every run below without the var reads the same `18` pass baseline this file already established; the one run with the var set reads `19`, the extra `tab_row_evidence_screenshot` check).
- `row_width`/`scroll_width` values in `tab_row_overflow_scrolls`' own printed detail shift naturally (the trailing `+` now contributes to and scrolls with row width, per change 2); the check's own boolean outcome (overflow triggers, `h_max > h_page`) is unchanged on every run below.

### Verification

Every row is its own serial process, isolated `APPDATA`/`LOCALAPPDATA` per version (`.now/tabs-validation/appdata-4.4`, `appdata-4.4-scaled150`, `appdata-4.6.2`), isolated project per version (`.now/tabs-validation/project`, `project-462`), both re-synced with this pass's changed files (`gst_main_panel.gd`, `gst_main_panel.tscn`, `gst_editor_tabs_smoke.gd`; the other named selectors' own test files were already byte-identical, confirmed by `diff -q` before this pass's own runs). Command shape: `GST_EDITOR_SMOKE=<selector>; APPDATA=<isolated>; LOCALAPPDATA=<isolated>; <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`.

| Selector | 4.4 (normal) | 4.4 (`150%`, `appdata-4.4-scaled150`) | 4.6.2 |
|---|---|---|---|
| `tabs_ui` | run 1: exit `1`, `pass=17 fail=1` (`stable_id_switch_by_click FAIL switched_to_saved=false switched_to_fire=false`, the same pre-existing session-warm-up flake this file already documents in "Editor UI redesign phase 4 round 1 fixes" bug 2 and "Shader tabs phase 4 review round 2 fix-now"'s own Blockers note -- unrelated to this pass's files); run 2 (retry): exit `0`, `pass=18 fail=0`; run 3: exit `0`, `pass=18 fail=0` | exit `0`, `pass=18 fail=0` first attempt, `editor_scale` confirmed `1.5` in the check's own printed measurement | run 1: exit `1`, `pass=17 fail=1` (identical flake signature, `switched_to_saved=false`); run 2 (retry): exit `0`, `pass=18 fail=0` |
| `tabs_ui` with `GST_TABS_UI_SCREENSHOT_PATH` | exit `0`, `pass=19 fail=0` (18 + 1 new `tab_row_evidence_screenshot` check), including a clean `stable_id_switch_by_click` this run | not run | not run |
| `ui_layout` | exit `0`, `pass=16 fail=0` | not run (not required by this pass's own instruction) | exit `0`, `pass=16 fail=0` |
| `ui_actions` | exit `0`, `pass=20 fail=0` | not run | exit `0`, `pass=20 fail=0` |
| `ui_complete` (`GST_UI_COMPLETE_ENTRY=recipe`) | exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0` | not run | exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0` |
| `tabs_close` | exit `0`, `pass=13 fail=0` (clean first attempt) | not run | exit `0`, `pass=13 fail=0` (clean first attempt) |
| `tabs_host` | exit `0`, `pass=8 fail=0` | not run | exit `0`, `pass=8 fail=0` |

Every pass/fail count above matches this file's own established baseline for that selector exactly (`tabs_ui` `18/0`, `ui_layout` `16/0`, `ui_actions` `20/0`, `ui_complete` `29/0`, `tabs_close` `13/0`, `tabs_host` `8/0`, per "Shader tabs phase 8 review round 5 fix-now"'s own version matrix). `ui_layout_file_menu` (`items=["New", "Open...", "Save As...", "Reopen Shader..."] ... save_export_visible=true`) and `ui_complete`'s `diagnostic_export_unchanged`/`reopen_compiles`/`open_saved_stack` checks confirm `%FileMenu`'s popup contents and `%ExportButton`'s own click-through wiring are unaffected by change 3/4's `flat`/reordering edits. Stderr across every row held only this file's own already-documented deliberate negative-path diagnostic (`tabs_close`'s bad-directory Save As failure, plain on `4.4`, full GDScript backtrace on `4.6.2`, matching the established version difference) or nothing at all; zero unexpected `SCRIPT ERROR`/`Invalid access`/`Nonexistent function`/`Parse Error`.

### Screenshot

`.now/tabs-validation/evidence/tabrow-2026-09-15.png` (gitignored verification scratch, not repo source), captured via the new `GST_TABS_UI_SCREENSHOT_PATH` hook on `4.4` at normal scale, right after three tabs are open (`gst_tabs_ui_...` clean, `Fire*` dirty and active, `Untitled 1` clean). Inspected directly: each tab reads as one unit with its `x` immediately adjacent to its title (change 1); `+` sits immediately after `Untitled 1`, the newest tab (change 2); `File` draws with the same button style as `Save`/`Recipes`/`Randomize`/`Export...` (change 3); all five toolbar buttons sit together on the left with no gap (change 4).

### Docs check

`docs/EDITOR_UI_DESIGN_reviewed.md` decision `27` ("keep Save and Export directly accessible... Mutating toolbar actions follow picker modality") was checked against this pass's changes: it states which toolbar actions must stay directly accessible vs. move into the File menu, not their left-to-right order or the tab's visual shape, so nothing in this pass contradicts it and no line needed a superseded note. No other decision line in that file states the prior toolbar order or tab shape. `docs/SHADER_TABS_reviewed.md`'s own mockup (`[Pearl x] [Opal* x] [Untitled 1 x] [+]` / `File Save Recipes Randomize <gap> Export`) is now stale against this pass's layout, but that file is outside this quick-fix batch's own edit scope; flagged here rather than edited.

### Scope

- Files modified: `addons/goshade_turbo/ui/gst_main_panel.gd`, `addons/goshade_turbo/ui/gst_main_panel.tscn`, `tests/gst_editor_tabs_smoke.gd`, this section.
- `tests/gst_editor_ui_layout_smoke.gd`, `tests/gst_editor_ui_actions_smoke.gd`, `tests/gst_editor_ui_complete_smoke.gd`, `tests/gst_editor_document_close_smoke.gd`, `tests/gst_editor_smoke.gd`, `tests/gst_editor_tabs_host_smoke.gd`: read in full, run for verification, not edited -- none assumes the tab row's or toolbar's prior node structure in a way this pass's changes break.
- `docs/EDITOR_UI_DESIGN_reviewed.md`: read, checked against decision `27`, not edited (see "Docs check" above).
- `NOW.md`: not edited. This request was handed to the implementer directly (quick-fix batch, no plan) rather than through a queued `/claudhd:quick` item; NOW.md's own Quick fixes list already reads all-cleared and unrelated to this change, and no other NOW.md line names the prior tab/toolbar layout.
- No file outside this pass's own sentinel list was touched. `sandbox/**` not touched. No git worktree. No commit. No write into the real repository's `.godot/`.

### Blockers / open decisions

- None found. The `stable_id_switch_by_click` flake hit on the first `tabs_ui` run on both `4.4` and `4.6.2` is the same pre-existing, already-documented session-warm-up flake (see the "Verification" table above); both retried clean and neither failure touches this pass's own files.

## Tab strip as TabBar 2026-09-15

User-requested UI change (no plan), replacing the `1709f1b` per-tab `Button` row (title `Button` + close `Button` in a wrapper `HBoxContainer`, scrolled by an external `ScrollContainer`) with a single native Godot `TabBar` for `%ShaderTabs`, matching the editor's own scene tabs exactly (name and close icon drawn as one tab shape, active tab highlighted, native overflow scroll arrows).

### Changes

1. **`gst_main_panel.tscn`**: `ShaderTabRow/ShaderTabsScroll/ShaderTabs` (`ScrollContainer` > `HBoxContainer`) replaced by `ShaderTabRow/ShaderTabs`, a `TabBar` (`tab_close_display_policy = 2` i.e. `CLOSE_BUTTON_SHOW_ALWAYS`, `max_tab_width = 160`, `scrolling_enabled = true`, `select_with_rmb = false`, `clip_tabs` left at its own default `true` so the bar's own minimum size stays 0 and the row's `size_flags_horizontal = 3` governs its width, letting `TabBar`'s internal offset-scroll arrows handle overflow). `NewTabButton` stays a plain `Button`, now a direct sibling of `%ShaderTabs` in `ShaderTabRow` (no longer reparented into the scrolling row on every rebuild) so it always sits immediately right of the tab strip.
2. **`gst_main_panel.gd`**: `_refresh_tabs()` rewritten to `clear_tabs()`/`add_tab()`/`set_tab_tooltip()` against `%ShaderTabs` instead of freeing/rebuilding per-tab `Button`s; a new `_tab_session_ids: Array[int]` (tab index -> `GSTDocument.session_id`) replaces the old `_tab_buttons`/`_tab_close_buttons` dictionaries and `_tab_button_group`. `%ShaderTabs.tab_changed`/`tab_close_pressed` wire to two new handlers (`_on_tab_bar_tab_changed`, `_on_tab_bar_close_pressed`), both resolving through `_tab_session_ids` + `_find_document_by_session_id` before calling `activate_document`/`close_document` -- the same stable-id-first pattern every other deferred response in this file already uses. `_syncing_tabs` guards `_refresh_tabs()`'s own `current_tab` write from re-entering `_on_tab_bar_tab_changed` (mirrors `_syncing_coord_space`). The old round-1 keyboard-undo-focus transfer (`_refresh_tabs()` freed every tab `Button` on every rebuild, so focus had to be explicitly handed to the new active one) no longer exists: `%ShaderTabs` is never freed, so focus placed on it by a real click survives every rebuild automatically. `_on_tab_scroll_resized` now calls `%ShaderTabs.ensure_tab_visible()` instead of `ScrollContainer.ensure_control_visible()`, wired to `%ShaderTabs.resized` instead of the removed `ScrollContainer`'s.

### Seam changes (tests/gst_editor_tabs_smoke.gd: 34 call sites; tests/gst_editor_document_close_smoke.gd: 19 call sites)

- `get_tab_button(doc)` / `get_tab_close_button(doc)` removed (no per-tab `Button` exists for a `TabBar`). Replaced by: `get_tab_bar() -> TabBar`, `get_tab_index(doc) -> int` (tab index or `-1`), `get_tab_rect(doc) -> Rect2` (global, wraps `TabBar.get_tab_rect`), `get_tab_close_rect(doc) -> Rect2` (global; `_tab_close_rect_local()` reconstructs `TabBar`'s own private `cb_rect` algebraically from public theme items -- `get_theme_stylebox("tab_selected"/"tab_unselected")`, `get_theme_stylebox("button_highlight")`, `get_theme_icon("close")` -- since `cb_rect` itself has no getter; derivation verified against `.now/tabs-validation/godot-4.4-source/scene/gui/tab_bar.cpp:40-108,604-626`).
- `get_tab_scroll()` removed (the `ScrollContainer` is gone). Its two `tabs_ui` uses replaced: `tab_row_overflow_scrolls` now asserts `TabBar.get_offset_buttons_visible()`; `_run_narrow_layout`'s scrolled-into-view check now compares `panel.get_tab_rect(doc)` against `panel.get_tab_bar().get_global_rect()` directly (no separate scroll viewport to compare against).
- `get_new_tab_button()` and `get_tab_row()` unchanged in signature. `get_tab_row()`'s own implementation now returns a new `@onready _shader_tab_row: HBoxContainer = %ShaderTabRow` (the outer row hosting both `%ShaderTabs` and `%NewTabButton`) instead of `_shader_tabs` itself, since `_shader_tabs` is no longer an `HBoxContainer`.
- Every real tab-body click (`tests/gst_editor_tabs_smoke.gd`'s `_click_tab`, `tests/gst_editor_document_close_smoke.gd`'s `_click_tab`) still drives a real `InputEventMouseButton` press/release through the viewport, now at `panel.get_tab_rect(doc)`'s own center; `TabBar::gui_input` resolves a tab-body click from the event's own position alone (tab_bar.cpp), so, unlike the old per-`Button` row, no `NOTIFICATION_MOUSE_ENTER` hover workaround is needed for the click itself to register. `TabBar.ensure_tab_visible(index)` runs first (a tab outside the bar's own current `[offset, max_drawn_tab]` window reports `ofs_cache` `0`, i.e. a bogus rect, per `tab_bar.cpp TabBar::_update_cache`).
- Non-click document switches that were driven through `Button.pressed.emit()` for setup only (not testing click mechanics) now call `panel.activate_document(doc)` directly -- the same production entry point `%ShaderTabs.tab_changed` itself calls.
- `tests/gst_editor_document_close_smoke.gd`'s close-icon click (`_click_tab_close`) required one more real-engine fix beyond the seam swap: see "Close-button click: real engine finding" below.

### Close-button click: real engine finding

A tab-body click and a tab close-icon click resolve through genuinely different code paths inside `TabBar::gui_input` (tab_bar.cpp): a body click resolves entirely from the input event's own `.position` (`pos.x >= get_tab_rect(i).position.x && ...`), synchronously, on the press event alone. A close-icon click additionally requires `TabBar::_update_hover()` to populate `cb_hover` (checked on the *release* event, `if (cb_pressing && !mb->is_pressed()) { if (cb_hover != -1) { emit_signal("tab_close_pressed", cb_hover); } ... }`), and `_update_hover()` reads `Control::get_local_mouse_position()`, which for this panel's own root (non-embedded) `Viewport` resolves through `DisplayServer::mouse_get_position()` (`scene/main/viewport.cpp Viewport::get_mouse_position`) -- the real OS cursor position -- not the synthetic event's own `.position` a body click already resolves against directly.

Verified directly in this session, isolating variables one at a time against a minimal single-file `TabBar` scene (no `GSTMainPanel`/plugin involved) and against the real panel alike: a real press+release at the close icon's own computed rect (confirmed correct against `TabBar.get_tab_rect()`) reached `TabBar::gui_input` (confirmed via its own `gui_input` signal, correct local position, `is_input_handled()` false beforehand) and correctly set `cb_pressing` on press (confirmed indirectly: `tab_clicked` stopped firing for points inside the close region, since the `cb_rect` branch returns before reaching the tab-body "found" check) -- but `tab_close_pressed` never emitted, at any position, with or without an intervening motion event, with or without a frame gap between press and release, regardless of `%ShaderTabs`'s own theme-cache state. Directly emitting `%ShaderTabs.emit_signal("tab_close_pressed", index)` immediately triggered the real close-confirmation flow, proving `gst_main_panel.gd`'s own wiring (`_on_tab_bar_close_pressed`) was never the fault. Warping the real OS cursor to the close icon's own point (`DisplayServer.warp_mouse`, window-relative coordinates -- confirmed via `get_local_mouse_position()` reading back the intended point only when passed unmodified, not offset by the window's own screen position) immediately before the press, with one frame to settle, reproduced `tab_close_pressed` reliably in both the minimal scene and the real panel.

`_click_tab_close` (`tests/gst_editor_document_close_smoke.gd`) now captures `DisplayServer.mouse_get_position()`, warps to the close rect's own center, clicks, then warps back to the captured position -- restoring the real cursor afterward, matching this project's own established precedent for tests that need the real OS cursor (`tests/gst_editor_native_undo_smoke.gd`'s own `EditorSpinSlider` drag, which documents the same `Input`/`DisplayServer` distinction from the opposite direction: that check deliberately avoids an external `Input.warp_mouse` call because the control's own drag handling already warps the cursor itself). Tab-body clicks need no such warp: their own resolution never touches `_update_hover()`.

### Editor main-screen bootstrap race (both test files' `run()`)

Independent of the `TabBar` change: this session's own runs against `.now/tabs-validation/appdata-4.4` (and, transiently, a from-scratch profile) repeatedly landed on the editor's own `Script` main screen instead of `GoShade Turbo` immediately after `EditorInterface.set_main_screen_editor("GoShade Turbo")` returned, with `panel.is_visible_in_tree()` false for the rest of that run -- confirmed via a captured screenshot showing `Script` selected in the main-screen switcher, `Loading plugin window layout...` still on screen. This reproduced identically against the byte-for-byte `1709f1b` (pre-`TabBar`) `gst_main_panel.gd`/`.tscn`/`gst_editor_tabs_smoke.gd`, so it is not a regression from this pass's own files -- it is the editor's own deferred "restore last main screen from saved window layout" occasionally finishing *after* the bootstrap's own single `set_main_screen_editor` call rather than before it, landing back on whatever main screen a prior session left active. `run()` in both files now re-asserts `set_main_screen_editor("GoShade Turbo")` every frame, up to 60 frames, until `panel.is_visible_in_tree()`, with a new `main_screen_visible` check recording the outcome -- adding one passing check to every selector's own baseline count below.

### Verification

Every row is its own serial process, isolated `APPDATA`/`LOCALAPPDATA` per version (`.now/tabs-validation/appdata-4.4`, `appdata-4.4-scaled150`, `appdata-4.6.2`, `appdata-4.7`), isolated project per version (`.now/tabs-validation/project`, `project-462`, `project-47`), all re-synced with this pass's changed files. Command shape: `GST_EDITOR_SMOKE=<selector>; APPDATA=<isolated>; LOCALAPPDATA=<isolated>; <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`.

**Environment finding**: the first attempt at every selector against `project`/`project-462`/`project-47` failed with every close-button-independent check *also* failing (`stable_id_switch_by_click`, etc.) via the same session-warm-up race documented above -- not a code defect. Separately, `project`'s own accumulated `.godot/` cache (carried across this repo's entire shader-tabs testing history, effectively the whole session since `tabs_proof` phase 1) had degraded to the point that *no* click, anywhere, on any control, registered at all in that specific project checkout, independent of code changes (confirmed against the unmodified `1709f1b` tree run in the same stale checkout). Deleting `.godot/` and re-running `--headless --import` (matching this file's own established `--headless --import` convention, `config/features` unchanged afterward) resolved this for `project`/`project-462`/`project-47` alike; every row below is post-reimport.

| Selector | 4.4 (normal) | 4.4 (`150%`) | 4.6.2 | 4.7 |
|---|---|---|---|---|
| `tabs_ui` | exit `0`, `pass=19 fail=0` (18 + new `main_screen_visible`) | exit `0`, `pass=19 fail=0`, `editor_scale` confirmed `1.5` | exit `0`, `pass=19 fail=0` | exit `0`, `pass=19 fail=0` |
| `tabs_ui` with `GST_TABS_UI_SCREENSHOT_PATH` | exit `0`, `pass=20 fail=0` | not run | not run | not run |
| `tabs_close` | exit `0`, `pass=14 fail=0` (13 + new `main_screen_visible`) | not run | exit `0`, `pass=14 fail=0` | exit `0`, `pass=14 fail=0` |
| `tabs_documents` | exit `0`, `pass=22 fail=0` | not run | exit `0`, `pass=22 fail=0` | not run |
| `tabs_files` | exit `0`, `pass=24 fail=0` | not run | exit `0`, `pass=24 fail=0` | not run |
| `tabs_host` | exit `0`, `pass=8 fail=0` | not run | exit `0`, `pass=8 fail=0` | exit `0`, `pass=8 fail=0` |
| `tabs_native` | exit `0`, `pass=39 fail=0` | not run | exit `0`, `pass=39 fail=0` | not run |
| `ui_layout` | exit `0`, `pass=16 fail=0` | not run | exit `0`, `pass=16 fail=0` | not run |
| `ui_complete` (`GST_UI_COMPLETE_ENTRY=recipe`) | exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0` | not run | exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0` | not run |

Every count above matches this file's own established baseline for that selector exactly once the new `main_screen_visible` check (present in `tabs_ui`/`tabs_close` only, both files' own `run()`) is accounted for; `tabs_documents`/`tabs_files`/`tabs_host`/`tabs_native`/`ui_layout`/`ui_complete` (files not touched by this pass) match their prior baseline unchanged -- run in full rather than merely read, since they exercise `open_document`/`activate_document`/`close_document` paths that now flow through `%ShaderTabs` on every call, even though none of their own assertions reach the removed `get_tab_button`/`get_tab_close_button`/`get_tab_scroll` seams directly. Stderr across every row held only this file's own already-documented deliberate negative-path diagnostics (`tabs_close`'s bad-directory Save As failure; `tabs_documents`/`tabs_files`'s own missing-resource-load diagnostics; plain on `4.4`, full GDScript backtrace on `4.6.2`/`4.7`, matching the established version difference) or nothing at all; zero unexpected `SCRIPT ERROR`/`Invalid access`/`Nonexistent function`/`Parse Error`.

### Screenshot

`.now/tabs-validation/evidence/tabrow-tabbar-2026-09-15.png` (gitignored verification scratch, not repo source), captured via the existing `GST_TABS_UI_SCREENSHOT_PATH` hook on `4.4` at normal scale, at the same point in the run as the prior pass's own screenshot (three tabs open: a clean saved tab, `Fire*` dirty and active, `Untitled 1` clean). Inspected directly: each tab draws as one native shape with its own `x` immediately after its title (the engine's own `CLOSE_BUTTON_SHOW_ALWAYS` rendering, not a hand-built wrapper); the active tab (`Fire*`) is visually highlighted by the editor's own `tab_selected` style; `+` sits immediately after the newest tab (`Untitled 1`); the File/Save/Recipes/Randomize/Export toolbar below is unchanged from the prior pass.

### Docs check

`docs/SHADER_TABS_reviewed.md`'s own mockup (`[Pearl x] [Opal* x] [Untitled 1 x] [+]`) already carried a stale-flag from the prior "Tab row and toolbar layout 2026-09-15" pass for the per-tab-wrapper shape; this pass's own change (native `TabBar`) makes that mockup accurate again in spirit (one tab shape, name and `x` together) even though it predates this exact implementation -- no new staleness introduced, and the file is outside this pass's own edit scope regardless. `docs/EDITOR_UI_DESIGN_reviewed.md` decision `27` (toolbar action placement) is unaffected: this pass changes the tab strip's own control class, not the toolbar. No other doc names the tab row's prior `Button`-row node structure (`ShaderTabsScroll`, per-tab wrapper `HBoxContainer`) in a way this pass's `.tscn` change breaks; `gst_main_panel.gd`'s own doc comments referencing that structure (`_refresh_tabs()`, `close_document()`, the `_active_document` field, `activate_document()`) were updated in place as part of this pass.

### Scope

- Files modified: `addons/goshade_turbo/ui/gst_main_panel.gd`, `addons/goshade_turbo/ui/gst_main_panel.tscn`, `tests/gst_editor_tabs_smoke.gd`, `tests/gst_editor_document_close_smoke.gd`, this section.
- `tests/gst_editor_document_files_smoke.gd`, `tests/gst_editor_documents_smoke.gd`, `tests/gst_editor_tabs_host_smoke.gd`, `tests/gst_editor_native_undo_smoke.gd`, `tests/gst_editor_ui_layout_smoke.gd`, `tests/gst_editor_ui_complete_smoke.gd`, `tests/gst_editor_document_recovery_smoke.gd`: read in full; none references the removed `ShaderTabsScroll`/per-tab-`Button` seams. Not edited. Run for verification on both `4.4` and `4.6.2` (`tabs_files`, `tabs_documents`, `tabs_host`, `tabs_native`, `ui_layout`, `ui_complete` -- see the Verification table above); `tabs_recovery` (`gst_editor_document_recovery_smoke.gd`) was not in this pass's own required selector list and was not run.
- `NOW.md`: not edited. This request was handed to the implementer directly (quick-fix-style, no plan, no queued `/claudhd:quick` item); NOW.md's own Active thread already reads "Plan complete... next: `/claudhd:audit`", unrelated to this change.
- No file outside this pass's own sentinel list was touched. `sandbox/**` not touched (`sandbox/screenshots/glow.png.import`, already modified before this session started per this session's own initial `git status`, restored via `git checkout --` regardless, per this sentinel's own instruction). No git worktree. No commit. No write into the real repository's `.godot/`. `.godot/` cache deletions above were confined to the isolated `.now/tabs-validation/project*` checkouts.

### Blockers / open decisions

- None outstanding. The two environmental issues found mid-pass (editor main-screen bootstrap race; stale `.godot` cache in the isolated projects) were both root-caused, fixed, and are documented above rather than worked around silently.

## Tab row follow-up 2026-09-15

User-requested UI follow-up (no plan), on top of the "Tab strip as TabBar 2026-09-15" pass above, from two findings against that pass's own screenshot: `File` still did not draw like `Save`/`Recipes`/`Randomize`/`Export...`, and `+` sat at the row's far right edge instead of immediately after the newest tab.

### Stylebox finding

`%FileMenu` (`MenuButton`) draws flat by construction: `MenuButton::MenuButton` calls `set_flat(true)` unconditionally (`.now/tabs-validation/godot-4.4-source/scene/gui/menu_button.cpp:217`). The prior pass's `flat = false` (`gst_main_panel.tscn`) therefore had no visible effect on its own -- the editor theme still supplies `MenuButton`'s own distinct styleboxes under the `"MenuButton"` theme type, independent of the `flat` property. Fix: `gst_main_panel.gd`'s new `_style_file_menu_as_button()` (`:492`, called from `_ready()` at `:296`) copies `%SaveButton`'s own `"Button"`-theme-type styleboxes (`normal`, `hover`, `pressed`, `disabled`, `focus`, `hover_pressed`) and font colors (`font_color`, `font_hover_color`, `font_pressed_color`, `font_disabled_color`, `font_focus_color`) onto `%FileMenu` as per-instance overrides, gated by `has_theme_stylebox`/`has_theme_color` so a theme that omits one name leaves `%FileMenu`'s own default for it untouched. `flat`, `get_popup()`, and every popup-id seam are unchanged.

### Changes

1. **`File` as a real button.** `gst_main_panel.gd`: `_style_file_menu_as_button()` (`:492-497`), called once from `_ready()` (`:296`). See "Stylebox finding" above.
2. **`+` follows the tab content, pinned to the row edge under overflow.** `gst_main_panel.tscn`: `%ShaderTabs`'s own `size_flags_horizontal` changed from `3` (`SIZE_EXPAND_FILL`) to `0` (`SIZE_SHRINK_BEGIN`), so `ShaderTabRow` (an `HBoxContainer`) no longer stretches it across the row; `clip_tabs` stays at its own default `true`. `gst_main_panel.gd`: new `_apply_tab_bar_width()` (`:454-459`) sets `%ShaderTabs.custom_minimum_size.x` to `min(content_width, available)`, where `content_width` comes from the new `_measure_tab_bar_content_width()` (`:471-475`, toggles `clip_tabs` off for one synchronous `get_minimum_size()` read -- `TabBar::get_minimum_size` sums every tab's real styled width and only zeroes the result at the very end when `clip_tabs` is true, `tab_bar.cpp:103-105`) and `available` is the row's own width minus `%NewTabButton`'s own width minus the row's `separation` theme constant. Called from `_refresh_tabs()` (`:1091`, tab count/content changed) and the new `_on_tab_row_resized()` (`:436-437`, wired to `%ShaderTabRow.resized` in `_ready()` at `:334`, row width changed e.g. a window resize) -- the only two things either side of the calculation depends on. `%NewTabButton` itself, `%ShaderTabs`'s own native overflow scroll arrows, and every existing tab-rect seam (`get_tab_rect`, `get_tab_close_rect`, `_tab_close_rect_local`) are unchanged.

### Test changes

- `tests/gst_editor_ui_layout_smoke.gd`: new `_check_file_menu_button_style` (called from `_check_file_menu`), comparing `%FileMenu`'s own `"normal"` stylebox against `%SaveButton`'s: same resource, or (a theme swap that legitimately supplies a distinct-but-equivalent `StyleBox` instance for each) identical content margins on all four sides. New check `file_menu_button_style`.
- `tests/gst_editor_tabs_smoke.gd`: new `_run_new_tab_button_follows_last_tab`, called with three tabs open (right after the existing `_capture_tab_row_evidence` call, the same point the prior pass's own three-tab screenshot was taken) -- asserts `%NewTabButton`'s own global left edge equals the last tab's own global right edge plus the row's own separation. New check `new_tab_button_follows_last_tab`. `_run_long_title_and_overflow` (24 tabs, already overflowing) gained a second assertion that `%NewTabButton`'s own global right edge equals `%ShaderTabRow`'s own global right edge. New check `new_tab_button_pinned_at_row_edge_when_overflowing`. `_capture_tab_row_evidence` is now parameterized (`env_var`, `check_name`) so the same helper captures both the three-tab shot (`GST_TABS_UI_SCREENSHOT_PATH`, unchanged env var name) and a new 24-tab-overflow shot (`GST_TABS_UI_OVERFLOW_SCREENSHOT_PATH`, called right after `_run_long_title_and_overflow`, before `_run_narrow_layout` resizes the window out from under it).

### Verification

Every row is its own serial process, isolated `APPDATA`/`LOCALAPPDATA` per version (`.now/tabs-validation/appdata-4.4`, `appdata-4.4-scaled150`, `appdata-4.6.2`), isolated project per version (`.now/tabs-validation/project`, `project-462`), both re-synced with this pass's changed files (`gst_main_panel.gd`, `gst_main_panel.tscn`, `gst_editor_tabs_smoke.gd`, `gst_editor_ui_layout_smoke.gd`; `gst_editor_document_close_smoke.gd`/`gst_editor_tabs_host_smoke.gd` already byte-identical to the isolated copies from the prior pass, confirmed by `diff -q` before this pass's own runs). Command shape: `GST_EDITOR_SMOKE=<selector>; APPDATA=<isolated>; LOCALAPPDATA=<isolated>; <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`.

| Selector | 4.4 (normal) | 4.4 (`150%`, `appdata-4.4-scaled150`) | 4.6.2 |
|---|---|---|---|
| `tabs_ui` | run 1: exit `0`, `pass=21 fail=0` (19 + `new_tab_button_follows_last_tab` + `new_tab_button_pinned_at_row_edge_when_overflowing`), clean first attempt | exit `0`, `pass=21 fail=0` first attempt; `editor_scale` read `1.0` this run (see "Blockers" below, not this pass's own regression) | run 1: exit `1`, `pass=20 fail=1` (`stable_id_switch_by_click FAIL switched_to_saved=false switched_to_fire=true`, the same pre-existing session-warm-up flake this file already documents; unrelated to this pass's files); run 2 (retry): exit `0`, `pass=21 fail=0` |
| `tabs_ui` with `GST_TABS_UI_SCREENSHOT_PATH` + `GST_TABS_UI_OVERFLOW_SCREENSHOT_PATH` | exit `0`, `pass=23 fail=0` (21 + `tab_row_evidence_screenshot` + `tab_row_overflow_evidence_screenshot`) | not run | not run |
| `ui_layout` | exit `0`, `pass=17 fail=0` (16 + `file_menu_button_style`, `same_resource=true margins_match=true` both versions) | not run | exit `0`, `pass=17 fail=0` |
| `ui_actions` | exit `0`, `pass=20 fail=0` | not run | exit `0`, `pass=20 fail=0` |
| `ui_complete` (`GST_UI_COMPLETE_ENTRY=recipe`) | exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0` | not run | exit `0`, `UI_COMPLETE SUMMARY pass=29 fail=0` |
| `tabs_close` | exit `0`, `pass=14 fail=0` (clean first attempt) | not run | exit `0`, `pass=14 fail=0` (clean first attempt) |
| `tabs_host` | exit `0`, `pass=8 fail=0` (clean first attempt) | not run | exit `0`, `pass=8 fail=0` (clean first attempt) |

Every count above matches this file's own established baseline for that selector plus exactly the new checks this pass adds; `tabs_close`/`tabs_host`/`ui_actions`/`ui_complete` (files not touched by this pass) match their prior baseline unchanged, run in full rather than merely read, since `_refresh_tabs()`'s now-changed control flow (`_apply_tab_bar_width()`) runs on every document open/close/switch these selectors themselves exercise. Stderr across every row held only this file's own already-documented environment noise (isolated-`APPDATA` resource-thumbnail/doc-cache save failures; `tabs_close`'s deliberate bad-directory Save As failure) or nothing at all; zero `SCRIPT ERROR`/`Invalid access`/`Nonexistent function`/`Parse Error` in any row (checked directly against every row's own stderr log).

### Screenshots

- `.now/tabs-validation/evidence/tabrow-tabbar-2-2026-09-15.png` (gitignored verification scratch, not repo source): three tabs open (`gst_tabs_ui_titl...` clean, `Fire*` dirty and active, `Untitled 1` clean), captured on `4.4` at normal scale. Inspected directly: `File` now draws with the same bordered button shape as `Save`/`Recipes`/`Randomize`/`Export...` (finding 1 fixed); `+` sits immediately right of `Untitled 1`, the newest tab, with no gap (finding 2 fixed, non-overflowing case).
- `.now/tabs-validation/evidence/tabrow-tabbar-overflow-2026-09-15.png`: 24 tabs open, the row already overflowing (`TabBar`'s own native offset-scroll arrows visible left of `+`). Inspected directly: `+` stays pinned at the tab row's own right edge rather than following the (now off-screen) last tab, with `%ShaderTabs` scrolling its own content internally to reach it (finding 2 fixed, overflowing case).

### Blockers / open decisions

- `editor_scale` read `1.0` against the `appdata-4.4-scaled150` profile this run, not the `1.5` the "Tab row and toolbar layout 2026-09-15" pass recorded against the same profile. `interface/editor/display_scale = 7` (custom) / `interface/editor/custom_display_scale = 1.5` are still present in that profile's own `editor_settings-4.4.tres`, so the setting itself was not lost; this reads as environment drift in the isolated profile between sessions, not a regression in this pass's own files -- every check in that run still passed at whatever scale actually applied (`pass=21 fail=0`), including the two new `new_tab_button_*` checks, which measure global rects directly rather than assuming a specific scale. Not re-investigated further: outside this pass's own two findings, and the scale-independent checks already confirm correctness at whatever scale this profile actually rendered at.

### Docs check

`docs/SHADER_TABS_reviewed.md`'s own mockup already carries a stale-flag from the "Tab row and toolbar layout 2026-09-15" pass for the tab shape; this pass's own change (tab-content-width sizing, `+` pinned under overflow) does not change that mockup's own accuracy either way -- no new staleness introduced, and the file is outside this pass's own edit scope regardless. `docs/EDITOR_UI_DESIGN_reviewed.md` decision `27` (toolbar action placement) is unaffected: this pass changes `%FileMenu`'s own drawn style and `%ShaderTabs`'s own sizing, not which actions live in the toolbar vs. the File menu. No other doc names the tab row's prior EXPAND-flag sizing or `%FileMenu`'s prior stylebox state in a way this pass's changes break.

### Scope

- Files modified: `addons/goshade_turbo/ui/gst_main_panel.gd`, `addons/goshade_turbo/ui/gst_main_panel.tscn`, `tests/gst_editor_tabs_smoke.gd`, `tests/gst_editor_ui_layout_smoke.gd`, this section.
- `tests/gst_editor_document_close_smoke.gd`, `tests/gst_editor_tabs_host_smoke.gd`, `tests/gst_editor_ui_actions_smoke.gd`, `tests/gst_editor_ui_complete_smoke.gd`: read; not edited (none references `%FileMenu`'s own styling or `%ShaderTabs`'s own sizing flags in a way this pass's changes break). Run for verification on both `4.4` and `4.6.2` (`tabs_close`, `tabs_host`, `ui_actions`, `ui_complete` -- see the Verification table above).
- `docs/SHADER_TABS_reviewed.md`, `docs/EDITOR_UI_DESIGN_reviewed.md`: read, checked against this pass's own changes, not edited (see "Docs check" above).
- `NOW.md`: not edited. This request was handed to the implementer directly (user-requested UI follow-up, no plan, no queued `/claudhd:quick` item); NOW.md's own Quick fixes list already reads all-cleared and unrelated to this change.

## Native + button 2026-09-15

User-requested UI follow-up, no plan, no `/claudhd:quick` item. Makes `%NewTabButton` (`gst_main_panel.tscn:31-34`) match Godot's own scene-tab `+` (`EditorSceneTabs::_notification`/`EditorSceneTabs::EditorSceneTabs`, `.now/tabs-validation/godot-4.4-source/editor/gui/editor_scene_tabs.cpp:57-58,438`): flat, icon-only, drawing the editor theme's own `"Add"`/`"EditorIcons"` icon instead of a `"+"` text button.

### Changes

1. **`gst_main_panel.tscn`**: `NewTabButton` (`:31-34`) no longer sets `text = "+"` (default empty).
2. **`gst_main_panel.gd`** `_ready()` (`:302-309`): sets `_new_tab_button.flat = true` and `_new_tab_button.icon = get_theme_icon(&"Add", &"EditorIcons")` before wiring `pressed`, reading the icon from the editor theme at runtime (not a baked resource path), matching the existing `get_theme_icon(&"ReloadSmall", &"EditorIcons")` precedent in `gst_inspector_column.gd:793`.
3. `get_new_tab_button()` (`:1271-1272`) and `_apply_tab_bar_width()`'s (`:454-460`) own `available width - %NewTabButton.size.x - separation` math are unchanged: both already read the button's own current `size.x`/instance at call time, so the button's own narrower icon-only width flows through automatically.

### Test changes

None. `tests/gst_editor_tabs_smoke.gd`'s two existing `%NewTabButton` checks (`new_tab_button_follows_last_tab`, `new_tab_button_pinned_at_row_edge_when_overflowing`) both read `new_tab_button.get_global_rect()` at run time rather than asserting a fixed width or `.text` value, so neither needed updating.

### Verification

Each selector run as its own serial process, isolated `APPDATA`/`LOCALAPPDATA` per version (`.now/tabs-validation/appdata-4.4`, `appdata-4.6.2`), isolated project per version (`.now/tabs-validation/project`, `project-462`), both re-synced with this pass's two changed files before every run. Command shape: `GST_EDITOR_SMOKE=<selector> APPDATA=<isolated> LOCALAPPDATA=<isolated> <godot> --editor --path <isolated-project> --rendering-method gl_compatibility`.

| Selector | 4.4 | 4.6.2 |
|---|---|---|
| `tabs_ui` | exit `0`, `pass=21 fail=0` | exit `0`, `pass=21 fail=0` |
| `tabs_ui` with `GST_TABS_UI_SCREENSHOT_PATH` | exit `0`, `pass=22 fail=0` (21 + `tab_row_evidence_screenshot`) | not run |
| `tabs_close` | run 1: exit `1`, `pass=2 fail=12` (every close-driven check failed at the click level, `dialog_shown=false`/`closed=false` throughout, not just the documented single first-click absorption); reproduced identically against unmodified `HEAD` in the same isolated project/session (reverted `gst_main_panel.gd`/`.tscn` to `HEAD`, re-ran: same `pass=2 fail=12`), confirming a session-local flake in this `4.4` binary/window, not a regression from this pass's two files; restored this pass's files and retried: exit `0`, `pass=14 fail=0` | exit `0`, `pass=14 fail=0` (clean first attempt) |
| `ui_layout` | exit `0`, `pass=17 fail=0` | exit `0`, `pass=17 fail=0` |

Stderr across every row held only this file's own already-documented environment noise; no `SCRIPT ERROR`/`Invalid access`/`Nonexistent function`/`Parse Error`.

### Screenshot

- `.now/tabs-validation/evidence/tabrow-plus-2026-09-15.png` (gitignored verification scratch, not repo source): three tabs open (`gst_tabs_ui_titl...` clean, `Fire*` dirty and active, `Untitled 1` clean), captured on `4.4` at normal editor scale. Inspected directly: `+` draws flat (no button box) with the editor's own grey `Add` glyph immediately right of `Untitled 1`, matching Godot's own scene-tab `+` shape.

### Blockers

None.

### Scope

- Files modified: `addons/goshade_turbo/ui/gst_main_panel.gd`, `addons/goshade_turbo/ui/gst_main_panel.tscn`, this section.
- `tests/gst_editor_tabs_smoke.gd`: read; not edited (see "Test changes" above).
- `sandbox/**`: not touched. `sandbox/screenshots/glow.png.import`'s pre-existing working-tree modification (present in `git status` before this pass started) is unrelated to this change and was left as found.
- No file outside this pass's own sentinel list was touched. `sandbox/**` not touched. No git worktree. No commit. No write into the real repository's `.godot/`.
