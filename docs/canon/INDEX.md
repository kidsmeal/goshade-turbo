# Canon

Stable rules a worker reads before a ticket. Rules and references only. Status, plans and open questions live in `docs/dev/`.

## Files

| File | Topic |
|---|---|
| `design-rules.md` | scope, the owner test, the locked stack shape, non-goals |
| `stack-model.md` | kinds, layer roles, references, identity, output, coord spaces |
| `codegen.md` | shader text: names, emission order, `TIME`, filters, header |
| `library.md` | manifest entries, citations, licensing, ranges, recipes |
| `editor-ui.md` | panel labels, pickers, messages, undo, documents |
| `conventions.md` | GDScript style, file rules, commits, docs layout |
| `testing.md` | runners, what each checks, version matrix |
| `naming.md` | product, class, file, shader and UI names |
| `glossary.md` | terms |

## Source refs

- `DESIGN.md d<n>`: decision `n` in `docs/dev/DESIGN.md`.
- `EDITOR_UI d<n>`: decision `n` in `docs/dev/EDITOR_UI_DESIGN_reviewed.md`.
- `SHADER_TABS d<n>`: decision `n` in `docs/dev/SHADER_TABS_reviewed.md`.
- `V0_2 d<n>`: decision `n` in `docs/dev/V0_2_DESIGN_reviewed.md`.
- `PLAN.md B<n>`: blocker resolution `B<n>` in `docs/dev/PLAN.md`.
- `PLAN.md cross-cutting`: the Cross-cutting concerns section of `docs/dev/PLAN.md`.
- A 7-char hex value is a commit hash.

## Recorded supersedes
- `EDITOR_UI` supersedes the output placement in `DESIGN.md d12` and the picker and solo presentation in `DESIGN.md d13`. (`docs/dev/EDITOR_UI_DESIGN_reviewed.md:17`)
- `DESIGN.md d20` (revised 2026-09-09) supersedes the shared-manager undo, embedded inspector routing and replacement undo in `EDITOR_UI d7` and `d30`. (`docs/dev/SHADER_TABS_reviewed.md:43`)
- `SHADER_TABS d8` supersedes the file-operation message lifetime in `EDITOR_UI d6`. (`docs/dev/EDITOR_UI_DESIGN_reviewed.md:35`)
- A `*_reviewed.md` design supersedes its draft. (`docs/dev/CURRENTNESS_AUDIT.md` Likely Shipped)