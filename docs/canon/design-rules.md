# Design rules

## Who it is for
- Target user has no shader knowledge, clicks controls, sees the result, ships it. (`DESIGN.md` "What it is")
- A new user chooses an effect, changes it through named controls and exports it without shader terms explained elsewhere. (`EDITOR_UI` intro, verification list)

## The owner test
- Every feature and iteration answers: "Does this make the stack more expressive without making the stack harder to understand?" (`.claude/CLAUDE.md`, `V0_2 d34`, owner rule 2026-09-24, `ad739e6`)

## Stack shape (locked)
- The stack is a linear, typed, downward-referencing list of whole-function layers. (`V0_2 d34`, `.claude/CLAUDE.md`)
- No free-form wiring, no forward references, no inline expression node, no canvas. (`V0_2 d34`)
- No separate graph or dependency panel; it is a canvas under another name. (`V0_2 d35` beats)
- A free-form node graph is a non-goal. (`docs/dev/ROADMAP.md` Non-goals `r-0921-1`)
- What the stack keeps: canonical reading order, one-line json header, no invalid wiring by construction, randomize that always compiles, per-layer license and tests, single-pass codegen with no cycle check. (`V0_2 d34`)
- What the stack gives up: fan-in beyond a layer's declared inputs, shader types other than `canvas_item`, arbitrary topology. (`V0_2 d34`)

## Scope
- Shader type is `canvas_item` only. (`DESIGN.md d1`)
- Particle process shaders are never new layers in the canvas stack; they would be a separate stack type. (`DESIGN.md` Expansions)
- Blend, opacity and mask are layers, never per-layer properties. One way to do one thing. (`DESIGN.md d14`)
- Export writes one self-contained `.gdshader` with no runtime dependency on the addon. (`DESIGN.md d6`)
- Preview and export compile the same text through one code path. (`DESIGN.md d6`)
- Hand edits to exported shaders are allowed; export asks before overwriting a differing body. (`DESIGN.md d9`)
- Godot minimum `4.4`. No API newer than `4.4`. Tested on `4.4`, `4.6`, `4.7`. (`DESIGN.md d17`, `README.md` Requirements)

## Library ownership
- The function library is this project's own MIT code. (`DESIGN.md d15`)
- No LYGIA code: its Prosperity 3.0 license would land inside every user's game. (`DESIGN.md d15`)

## Randomize
- Randomize sets sliders inside manifest ranges, so it always renders. (`DESIGN.md d16`)
- Structural randomize (random layers and wiring) requires the rendered checks that reject blank and non-finite output. (`DESIGN.md d16`)

## Reviewing a feature
- A decision records the alternative it beat. (`DESIGN.md` Locked decisions preamble, every `V0_2` decision)
- Every feature is checked against the stack shape before it is designed. (`V0_2 d34`)
