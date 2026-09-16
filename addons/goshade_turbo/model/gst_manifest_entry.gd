@tool
class_name GSTManifestEntry
extends Resource

## One hand-written library function. Load-only: no code path in this addon
## calls ResourceSaver.save on a file under addons/goshade_turbo/library/.

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
## description: String}]. label and description are required editor
## metadata; assignment and codegen use name and kind.
@export var inputs: Array[Dictionary] = []
## Slider schema: [{name, type, min, max, default, label, description}].
## label and description are required editor metadata; serialization and
## uniform names use name. Optional editor: "color_rgb" presents a vec3 as a
## native RGB color picker.
@export var params: Array[Dictionary] = []
## True for generators: the layer carries a coord block.
@export var coord: bool = false
## True for filters. GSTStackOps.assign_slot refuses any input for this slot
## that is not a "source/texture" or "source/screen" layer; filter-of-filter
## is refused.
##
## Filter calling convention: filters cannot be GLSL functions. `TEXTURE`
## inside a user function fails with `Unknown identifier`, and `TEXTURE`
## passed as a `sampler2D` argument prints
## `ERROR: Condition "!actions.custom_samplers.has(...)"` on every compile
## (Godot 4.6.2). A plain `uniform sampler2D` would require the user to bind
## the node texture by hand on every exported shader.
##
## So a filter's `code` is an inline body template, expanded by GSTCodegen
## into a `{ }` block inside `fragment()` per filter layer, so two filter
## layers never collide on the template's locals. The template is plain
## statements (no function signature or braces) using four tokens:
## - `GST_SAMPLE(p)` -> `texture(TEXTURE, p)` for a "source/texture" source,
##   `texture(gst_screen_texture, p)` for a "source/screen" source.
## - `GST_UV` -> `UV` or `SCREEN_UV`, matching the wired source, not the
##   stack's coord space: neighbor-offset math is defined in raw UV space.
## - `GST_OUT` -> the layer's own fragment() local (`l<id>`); the template
##   assigns to it instead of returning.
## - `GST_PARAM(name)` -> the param's uniform name.
## No `gst_self_texture` uniform exists; `source/texture` reads TEXTURE
## directly.
@export var samples_source: bool = false
## Other manifest ids this function's body calls. Depth-first, deduped by id.
@export var depends: Array[String] = []
## Raw GLSL. Three contracts, keyed by is_source() and `samples_source`:
## - Normal entry (both false): one top-level function declaration, name
##   matches `function`, emitted once at file scope by the include walk.
## - Source entry (is_source() == true): empty. GSTCodegen._source_body_lines
##   reads the built-in directly and never emits it at file scope.
## - Filter entry (samples_source == true): an inline body template, never
##   emitted at file scope, expanded per layer into a `{ }` block inside
##   `fragment()` using the four GST_ tokens above.
@export var code: String = ""


## True for a source entry ("source/texture", "source/screen"), identified by
## the "source/" id prefix. Source entries carry no function body.
func is_source() -> bool:
	return id.begins_with("source/")
