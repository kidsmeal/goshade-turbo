# IDEAS (capture, do not chase)

When an idea comes up mid-task, it is recorded here in one line. Do NOT open a new chat for it; the current thread survives. Triage regularly: each idea is promoted to the roadmap (verbatim - no rewording), sent to the quick-fixes batch, kept parked, or dropped. The readiness gate lives at `/claudhd:start` activation, not at promotion, so vague wording is legal here.

Capture: `/claudhd:idea <your idea>` in any chat.
Harvest: `/claudhd:harvest` to backfill ideas from past sessions you never recorded.
Triage: `/claudhd:triage` to review this list, one tap-card at a time.

Legend: `[ ]` new, `[~]` promoted (to ROADMAP.md, or to the quick-fixes batch), `[x]` done or dropped.

## Inbox

- [ ] live read-only code panel beside the preview showing codegen output on every stack change (gst_material_sync already has the string)
- [ ] fork-to-entry: from the code panel, write a new .tres from a selected function and swap the layer to it
- [ ] param driven by a field layer: wire any param to a layer output instead of a slider (clock -> tent -> ratchet.amount); subsumes time-animated params
- [ ] centered origin: uv space defaults offset to -0.5 or gains a centered coord space, so generators stop needing Position -0.5 by hand (recipes do it manually, sprite_opal.tres:38)
- [ ] generative/cell_borders: exact distance to voronoi edge, iq two-pass bisector algorithm, MIT port with source_code_license set
- [ ] cellular_edges: drop the width param, return raw F2 - F1 and let smoothstep/band set width downstream
- [ ] exercise entries, all own construction: fieldops tent, band, quantize, pingpong, wave, threshold; generative rings, rays, spiral, dots, grain, scanlines; filter vignette, mirror, kaleidoscope, wave_distort; color tint, alpha_from_luma, two_tone
- [ ] filter/plot: draw a field as a curve against UV.y, book-of-shaders style, as a teaching view for the code panel
- [ ] mouse: coord center follows the mouse via a uniform written by a script on the exported node
