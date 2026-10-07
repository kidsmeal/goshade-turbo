# Library

## Files
- One hand-written `GSTManifestEntry` `.tres` per function. Adding a function is adding a file. (`DESIGN.md d5`, `PLAN.md` Decisions made at planning)
- Path `addons/goshade_turbo/library/<folder>/<name>.tres`; `id` is `<folder>/<name>` and matches the path. (`GSTManifestEntry.id`)
- Folders: `generative`, `sdf`, `fieldops`, `color`, `source`, `filter`. Taxonomy follows LYGIA's folder layout. (`DESIGN.md d15`, `docs/LIBRARY.md`)
- Manifests are load-only. No code path calls `ResourceSaver.save` on a file under `library/`. (`PLAN.md` Decisions made at planning, `GSTManifestEntry` class doc)
- `GSTLibrary.add_entry` returns `false` and records a duplicate `function`; it never raises. (`PLAN.md` phase 1)

## Fields
- `description`: one line. Carries no design-doc references. (`DESIGN.md d5`, `a96f875`)
- `source_math`: required. Cites where the math comes from. (`DESIGN.md d15`, `docs/LIBRARY.md:80`)
- `source_code_url` and `source_code_license`: set only when code was copied from a permissive source. (`DESIGN.md d15`, `GSTManifestEntry`)
- Own constructions say so in `source_math`, with the author and date. (`docs/TUTORIAL_CELL_BORDERS.md` "What you own after part 2", `c1ee595`)
- Every `inputs` and `params` item defines `label` and `description`. (`GSTManifestEntry.inputs`, `.params`, `EDITOR_UI d30`)
- Labels are function-specific, never one generic rename of `a`, `b` or `t`. (`EDITOR_UI d30`)
- `editor: "color_rgb"` presents a `vec3` param as a native RGB picker without alpha. (`EDITOR_UI d31`)
- `depends` lists every manifest id the body calls. (`GSTManifestEntry.depends`, `docs/TUTORIAL_CELL_BORDERS.md` step 9)

## Licensing
- Formulas are not copyrightable; code is. Cite the math, write the code, record a license only when code was copied. (`DESIGN.md d15`)
- Copied code keeps its license notice in the export header. (`gst_codegen.gd` `MIT_PERMISSION_NOTICE`, `d466191`)

## Code
- Normal entry: one top-level function named `function`. (`PLAN.md cross-cutting`, manifest `code` contracts)
- Source entry: empty `code`. (`PLAN.md cross-cutting`)
- Filter entry: inline body template using the `GST_` tokens. See `codegen.md`. (`PLAN.md B10`)
- Generators are called as `fn(coord, params...)`, params in manifest order. Signature and `params` agree in order. (`docs/TUTORIAL_CELL_BORDERS.md` steps 7, 8a)
- Guard every divisor where it is made so it never reaches zero. (`docs/TUTORIAL_CELL_BORDERS.md` step 8b)

## Ranges and defaults
- Slider ranges and defaults live in the manifest, never in docs. (`DESIGN.md d5`)
- Every slider produces a visible change across its whole range. (`DESIGN.md` release checklist, tuning item)
- A generator whose default render is uniform is a defaults defect. (`PLAN.md` phase 8, `checker.tres`)
- Every stored recipe and reference-stack param lies inside its manifest range. (`PLAN.md` phase 8, `tests/test_recipe_roundtrip.gd`)

## Per-entry requirements
- Compiles alone in the preview. (`DESIGN.md` release checklist)
- Has a reference stack at default sliders under `sandbox/stacks/`. (`DESIGN.md` release checklist)
- Passes the combination tests. (`DESIGN.md` release checklist)
- After a library change, regenerate the `docs/LIBRARY.md` table with `godot --headless --path . -s res://tests/print_roster.gd`. (`docs/LIBRARY.md:10-14`)

## Picker presentation
- Function names only. No display names, no thumbnails. (`DESIGN.md d19`, `EDITOR_UI` Scope)
- Each row shows function name, kind signature and description. (`DESIGN.md d19`, `EDITOR_UI d12`)

## Recipes
- Each recipe is a `.tres` stack under `addons/goshade_turbo/recipes/`. (`DESIGN.md` Recipes)
- A recipe uses roster entries only and passes the rendered checks. (`DESIGN.md` release checklist)
- Opening a recipe creates an independent editable copy. (`SHADER_TABS d2`)
