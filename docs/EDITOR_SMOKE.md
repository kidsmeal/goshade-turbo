# Editor smoke results

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
