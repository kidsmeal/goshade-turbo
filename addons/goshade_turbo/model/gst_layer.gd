@tool
class_name GSTLayer
extends Resource

## One stack entry: a manifest function instance with its own slots and params.
## Design: docs/DESIGN.md, Data model.

enum Kind {
	FIELD,
	COLOR,
}

## Stable id, assigned once at creation. Never reused (decision 22).
@export var id: StringName = &""
## Manifest id, e.g. "generative/fbm".
@export var entry: String = ""
## Copied from the manifest at creation. Fixed for the life of the layer.
@export var kind_out: Kind = Kind.FIELD
## slot_name (String) -> referenced layer id (StringName).
@export var slots: Dictionary = {}
## param_name (String) -> tuned value (Variant, type per manifest param schema).
@export var params: Dictionary = {}
## Generators only. Null for operators.
@export var coord: GSTCoordBlock = null
