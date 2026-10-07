# Conventions

## GDScript
- Tabs for indentation. (`PLAN.md` header)
- Static types on every declaration and return. (`PLAN.md` header)
- `snake_case` file and member names. (`PLAN.md` header)
- `PascalCase` `class_name` with the `GST` prefix. (`PLAN.md` header, `DESIGN.md` status line)
- `@export` for inspector-facing fields. (`PLAN.md` header)
- Double-quoted strings. (`PLAN.md` header)
- Addon scripts start with `@tool`. (verified by reading `gst_codegen.gd:1`, `gst_uniform_names.gd:1`, `gst_manifest_entry.gd:1`)
- `##` doc comments state contracts, not change history. (`docs/dev/NOW.md` quick fix on `gst_document_recovery.gd`)

## Layout
- Addon code under `addons/goshade_turbo/`: `model/`, `codegen/`, `io/`, `library/`, `ui/`, `recipes/`, `assets/`. (`PLAN.md` phases 1 to 6, verified by glob)
- Project root is the sandbox: reference stacks in `sandbox/stacks/`, tests in `tests/`. (`DESIGN.md d18`)

## Files
- `*.gd.uid` files are committed and never hand-edited. (`PLAN.md` phase 1 files)
- `project.godot` `config/features` stays `"4.4"`. Reset it after an editor run rewrites it. (`PLAN.md cross-cutting`, `DESIGN.md d17`)
- Library manifests are never re-saved by any engine version. (`PLAN.md cross-cutting`)
- Generated output stays gitignored: `sandbox/screenshots/`. (`d01c967`, `.gitignore`)
- The GitHub archive holds only the addons folder. (`5eef235`)

## Code rules
- A public accessor that exists only for the editor smoke carries the doc line `Wired-by: none (editor smoke seam)`. (`PLAN.md cross-cutting`)
- An accessor with neither that line nor a live caller is dead code. (`PLAN.md cross-cutting`)
- A new `class_name` script requires a re-import before `-s` runs. (`docs/TESTING.md`, `PLAN.md` verified engine facts)

## Commits
- Subject: imperative, lowercase, max 60 chars, one change. (`~/.claude/CLAUDE.md` Commits, `git log`)
- Optional scope prefix in the existing style: `docs/dev:`, `docs:`, `README:`, `sandbox:`, `library:`, `recipes/<name>:`, `logo:`, `ci:`, `plugin:`. (`git log`, e.g. `262953b`, `8a790e1`, `c898aed`, `a96f875`)
- Version bumps use `bump plugin version to <x.y.z>`. (`056604d`, `264f206`)

## Docs layout
- `README.md`: showcase and shortest paths. (`74c1e7d`, `c94dd36`)
- User docs in `docs/`: `USAGE.md`, `TESTING.md`, `LIBRARY.md`, `TUTORIAL_<topic>.md`. (`74c1e7d`)
- Design, plans, audits and ClauDHD state in `docs/dev/`. (`d553ac3`, `a771428`)
- Stable rules in `docs/canon/`.
- A `*_reviewed.md` design supersedes its draft. (`docs/dev/CURRENTNESS_AUDIT.md` Likely Shipped)
- `docs/dev/EDITOR_SMOKE.md` is append-only; later sections supersede earlier ones. (`docs/dev/CURRENTNESS_AUDIT.md` Likely Shipped)
- The addon `README.md` matches the root README wording. (`3fd47e6`)

## Attribution
- The README discloses AI authorship and names the hand-written exceptions. (`0a0bf5b`, `8e4e6fd`, `c1ee595`)
- Design and log docs carry no AI tool attributions. (`9b2fb0e`)
- Every library function cites its math source in `docs/LIBRARY.md`. (`DESIGN.md d15`, `README.md` Attribution)
