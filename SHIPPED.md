# SHIPPED

Finished work, newest first. Written automatically at the commit boundary; run `/claudhd:audit` to catch up any commit that bypassed the guard. This file records completed work so progress stays visible.

<!-- last-sha: 9b3b15d3efbd6ab1c2c391227b7f62f930f18eb9 -->

### 2026-09-24
- README: show the portal shader on a GPUParticles2D vortex `fd45f13`
- add a vortex portal gif and its frame recorder `4b77f2b`
- add the stack expressiveness test as a design rule `ad739e6`
- GoShade Turbo 0.1.2
- README: cut the AI-use line to what was AI-written `8e4e6fd`
- credit the four handwritten library entries to kidsmeal `c1ee595`
- README: disclose AI authorship of code, tests and docs `0a0bf5b`
- ROADMAP: record v0.1.1 as the first published release `f180086`
- bump plugin version to 0.1.1 `3dc4f29`
- addon README: match the root README wording `3fd47e6`
- ci: remove the gitlab mirror workflow `4740dc0`

### 2026-09-23
- README: rewrite for users new to shaders `c94dd36`
- plugin.cfg: match the description to the README intro `be14990`
- add recipe gallery renders and their render script `a215fc5`
- ci: limit the gitlab mirror to this repo and a read-only token `5b13dea`
- ci: run codegen tests on Godot 4.4.1, 4.6.2, 4.7 `310cf4b`
- logo: remove the unused Bruno Ace SC font `ee980d0`
- plugin: skip the editor smoke hook when tests/ is absent `d200549`
- library: drop design-doc references from picker descriptions `a96f875`
- ROADMAP: remove ClauDHD template placeholder items `7740809`
- docs: move process docs to docs/dev `d553ac3`
- v0.2 design: add dependency marks in the stack list (decision 35) `f82a9d0`
- add LICENSE and README inside the addon folder `050705c`
- sandbox: stop tracking render-check screenshots `d01c967`
- logo: add Godot import file for the GT icon `49e5671`
- logo: add 256px GT icon for the asset library `edc4a60`

### 2026-09-22
- README: center the logo and badge header
- README: split usage, tests, library into docs, add tuning gif `74c1e7d`

### 2026-09-21
- add github action mirroring every push to gitlab `2a843aa`
- v0.2 design: lock stack shape, record VisualShader trial (decision 34) `95d8647`

### 2026-09-20
- ROADMAP: v0.1 moved to Shipped, Now pointer at r-0916-1
- Activate r-0916-1: v0.2 thread enters design mode, roadmap wording restated
- v0.2 design: param links amended to base plus amount (decisions 29, 30)
- NOW.md cursor: v0.1.0 tag and zip moved to 85c2762
- generative/clock: wave param, sine default; triangle and sawtooth kept `85c2762`
- README: library table regenerated from the manifests, 61 functions
- NOW.md cursor: v0.1.0 shipped, next is the README roster count and v0.2 start
- NOW.md cursor: tuning pass done, next action is the tag move and GitHub release gates
- Release checklist: tuning pass ticked, all 61 reference stacks swept in editor `0c0c606`
- Slider step in PROPERTY_HINT_RANGE hint strings; fieldops ease and ratchet ref stacks; fieldops and filter sweep signed off `4dcc506`

### 2026-09-19
- Tuning pass fixes: soft slider max, sine-free hash, perlin quintic fade and gain, snoise 0..1 and fbm centered on 0.5, dither hashes FRAGCOORD `e5e833e`

### 2026-09-18
- Picker text slicing resolved as upstream godotengine/godot#83975; cell_borders tutorial and screenshot import companions added; NOW.md thread set to the v0.1 tuning pass `ecb3796`

### 2026-09-16
- library: three cell border entries, rounded, per-plate, edge-warped `51e2504`
- v0.2 design board: layer ops, texture param and source/image, param links, custom layer with save-as-entry, user recipes; roadmap intent added, two ideas promoted `417f549`
- Comments trimmed to technical content: phase numbers, plan-doc references, decision and fix-pass ids, and version history removed across addons, tests, and sandbox; 5226 comment lines to 3087, code untouched `011de03`

### 2026-09-15
- Test wrappers remove the .recovery_mode_lock that a headless --import leaves on Godot 4.4 and 4.6, so the next editor launch does not offer Recovery Mode
- Tab row: size the TabBar synchronously after add and close so the scroll arrows appear only on real overflow
- Tab row: draw the new-tab button as the editor's flat Add icon, matching the scene tabs
- Tab strip as native TabBar: close x inside the tab, + after the newest tab, File menu drawn with the Button style
- Tab row: close control beside the title, New tab after the newest tab, File drawn as a button, Export in the left toolbar group
- Audit 2026-09-15: refresh CURRENTNESS_AUDIT.md and RUNTIME_VERIFICATION_QUEUE.md after the shader tabs plan

### 2026-09-11
- sandbox/vortex: save the particle process params and black fill in the scene (`cb39a72`)
- Recipes: metaball_portal is the vortex stack, drop dead hue_shift, ball size and spawn knobs (`f6bb0fa`)
- Export: reload the editor's cached Shader after writing, vortex of vortexes in the particle shader (`589f893`)
- sandbox/vortex: let the exported shader drive the scene, wire fill into the base mix (`583ea7e`)

### 2026-09-10
- Triage: quick-fix three ideas, re-capture inbox through vocab.js (`cc2e59f`)
- Add sandbox/vortex: GPUParticles2D metaball vortex scene on the portal export (`6f32f14`)
- Add fieldops/ratchet and generative/clock, file session ideas (content) (`00e8128`)
- Add fieldops/ratchet and generative/clock, file session ideas (`cc5c54e`)
- Add fieldops/ease and rewrite every input and param tooltip (`2662767`)

### 2026-09-09
- hook probe 3: minimal command (`1c12c10`)
- hook probe 2: pending and verify diagnostics (`1fa7a14`)
- NOW.md: enforcement opt-in and the auto-commit grant (`8b635fb`)
- NOW.md: Astra reviewer-only measurement protocol (`c1de73a`)
- NOW.md: clouds stack moved, push debt cleared (`4a24300`)
- Backfill SHIPPED.md, refresh NOW.md cursor, move clouds stack to sandbox (`017b936`)

### 2026-09-15
- DESIGN.md: re-verify prior art 2026-09-15, add Sprite Shader Mixer, CompositeMaterial, Godot 4.7 live preview, Material Maker
- Add Godot-generated .uid and .import companions for sandbox/logo, print_roster, and the regenerated cellular_edges reference
- DESIGN.md: re-verify prior art 2026-09-15, add Sprite Shader Mixer, CompositeMaterial, Material Maker 1.6, Godot 4.7 inline preview

### 2026-09-14
- NOW.md: mouse coord-center chore moved from quick fixes to IDEAS.md
- Quick fixes: trim the recovery module to one validated-index loader, cellular_edges returns raw F2 - F1, add generative/cell_borders (iq bisector, MIT); log phase 8 deferred notes
- Shader tabs phase 8: verify the full lifecycle on Godot 4.4, 4.6.2, and 4.7, fixing the native color popup undo boundary on 4.6.2 and 4.7

### 2026-09-12
- Shader tabs phase 7: save dirty documents on confirmed shutdown with validated project-local recovery records

### 2026-09-11
- Shader tabs phase 6: protect document close with a document-bound Save, Discard, or Cancel lifecycle
- Shader tabs phase 5: bind Save, Save As, Export, and dialog responses to their initiating document
- Shader tabs phase 4: add the shader tab row with stable-ID activation, state restoration, and active-only preview rendering
- Logo: render the README wordmark through the plugin's own export, README cleanup, roster generator
- NOW.md: phase 3 committed, next action phase 4
- Shader tabs phase 3: add GSTDocument runtime ownership with per-document history and baselines
- NOW.md: phase 2 committed, next action phase 3

### 2026-09-10
- Shader tabs phase 2: route stack edits through a panel-owned UndoRedo with native property rows
- Shader tabs phase 1: prove per-document UndoRedo, native gestures, and confirmed-quit recovery on Godot 4.4
- Add sandbox/vortex: GPUParticles2D metaball vortex scene on the portal export `6f32f14`
- Add fieldops/ratchet and generative/clock, file session ideas (content) `00e8128`
- Add fieldops/ratchet and generative/clock, file session ideas `cc5c54e`
- Add fieldops/ease and rewrite every input and param tooltip `2662767`

### 2026-09-09
- Ignore Codex adapter state files under .gantry
- Ignore Codex adapter state files under .gantry
- hook probe: reconcile and verify after trust
- Fix preview transparency, recipe motion, and inactive control guidance `9f765a9`
- Use native RGB picker for palette Color center `f488370`
- Fix simplex noise seams across renderers and save clouds stack `42a052f`
- Editor UI phase 5: entry flow, preview recovery, and complete verification `8d5c923`

### 2026-09-08
- Editor UI phase 4: embedded contextual choosers `a3469da`
- Editor UI phase 3: readable native property labels `68d0c6e`
- Editor UI phase 2: atomic additions and typed conversion fixes `161a27b`
- Editor UI phase 1: full-height layout and preview allocation `1c7ae37`
- Phase 8: roster completion, recipes, randomize, release checklist `a3ba9a8`
- Phase 7: three-recipe proof and rendered-check harness `8b28321`
- Phase 6: persistence and export `f4eae56`
- Phase 5: preview column `6dd38c2`
- Phase 4: editor main screen UI and undo `0d29792`
- Phase 3: codegen sources, filters, color ops, alpha `fd09382`
- Phase 2: codegen core, generators and field ops `eba28be`

### 2026-09-07
- Phase 1: scaffold, data model, layer identity, test runner `a1fe516`
- Add design doc, 8-phase plan, and ClauDHD scaffold `26ab753`
