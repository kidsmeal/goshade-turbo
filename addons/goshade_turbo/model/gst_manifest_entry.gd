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
## Operator slots: [{name: String, kind: GSTLayer.Kind}].
@export var inputs: Array[Dictionary] = []
## Slider schema: [{name, type, min, max, default}].
@export var params: Array[Dictionary] = []
## True for generators (decision 4): the layer carries a coord block.
@export var coord: bool = false
## True for filters (decision 21): every input slot must resolve to a source layer.
@export var samples_source: bool = false
## Other manifest ids this function's body calls. Depth-first, deduped by id.
@export var depends: Array[String] = []
## Raw GLSL: one top-level function declaration, name matches `function`.
@export var code: String = ""
