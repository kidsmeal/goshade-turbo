@tool
class_name GSTManifestEntry
extends Resource

## One hand-written library function. Design: docs/DESIGN.md, Manifest entry.
## Load-only. No code path in this addon calls ResourceSaver.save on a file
## under addons/goshade_turbo/library/ (decision 5, planning decision).

## Manifest id, e.g. "generative/fbm". Matches the .tres path under library/.
@export var id: String = ""
## GLSL function name. Must be unique across the whole roster.
@export var function: String = ""
@export var description: String = ""
## Citation for the underlying math (url or text reference).
@export var source_math: String = ""
## Set only when code was copied from a permissive source. Empty otherwise.
@export var source_code_url: String = ""
@export var source_code_license: String = ""
@export var kind_out: GSTLayer.Kind = GSTLayer.Kind.FIELD
## Operator slots: [{name: String, kind: GSTLayer.Kind, label: String,
## description: String}]. Label and description are required editor metadata;
## assignment and codegen continue to use name and kind.
@export var inputs: Array[Dictionary] = []
## Slider schema: [{name, type, min, max, default, label, description}]. Label
## and description are required editor metadata; serialization and uniform
## generation continue to use the original parameter name.
@export var params: Array[Dictionary] = []
## True for generators (decision 4): the layer carries a coord block.
@export var coord: bool = false
## True for filters (decision 21). GSTStackOps.assign_slot refuses any input
## for this slot that is not a "source/texture" or "source/screen" layer (B6;
## filter-of-filter is refused).
##
## Filter calling convention (docs/PLAN.md Blocker B10): filters cannot be
## GLSL functions. `TEXTURE` inside a user function fails with
## `Unknown identifier`, and `TEXTURE` passed as a `sampler2D` argument
## prints `ERROR: Condition "!actions.custom_samplers.has(...)"` on every
## compile (verified, Godot 4.6.2). A plain `uniform sampler2D` would need
## the user to bind the node texture by hand on every exported shader,
## breaking decision 6 (self-contained export).
##
## So a filter's `code` is not a function: it is an inline body template,
## expanded by GSTCodegen into a `{ }` block inside `fragment()` per filter
## layer, one block per layer so two filter layers in one stack never
## collide on the template's own locals. The template is written as plain
## statements (no wrapping function signature or braces) using four tokens:
## - `GST_SAMPLE(p)` -> `texture(TEXTURE, p)` for a "source/texture" source,
##   `texture(gst_screen_texture, p)` for a "source/screen" source.
## - `GST_UV` -> `UV` or `SCREEN_UV`, matching the wired source -- not the
##   stack's space_coord, since neighbor-offset math (blur radius, pixel
##   cell size) is defined in raw UV/SCREEN_UV space.
## - `GST_OUT` -> the layer's own fragment() local (`l<id>`); the template
##   assigns to it instead of returning.
## - `GST_PARAM(name)` -> the param's uniform name.
## No `gst_self_texture` uniform exists; `source/texture`'s own direct read
## is unaffected and still reads TEXTURE literally (decision 10).
@export var samples_source: bool = false
## Other manifest ids this function's body calls. Depth-first, deduped by id.
@export var depends: Array[String] = []
## Raw GLSL. Three contracts, keyed by is_source() and `samples_source`
## (docs/PLAN.md Cross-cutting concern "Manifest code contracts", B10):
## - Normal entry (is_source() == false, samples_source == false): one
##   top-level function declaration, name matches `function`, emitted once
##   at file scope by the include walk.
## - Source entry (is_source() == true, "source/texture", "source/screen"):
##   empty. Codegen reads the built-in directly (decision 10) in
##   _source_body_lines and never emits a source entry's code at file scope.
## - Filter entry (samples_source == true): an inline body template, never
##   emitted at file scope, expanded per layer into a `{ }` block inside
##   `fragment()` using the four GST_ tokens documented above.
@export var code: String = ""


## True for a source entry ("source/texture", "source/screen"), identified by
## the "source/" id prefix (docs/PLAN.md Cross-cutting concern "Manifest code
## contracts", B10). Source entries carry no function body; `code` is always
## empty and GSTCodegen never emits it at file scope.
func is_source() -> bool:
	return id.begins_with("source/")
