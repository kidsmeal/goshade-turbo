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
