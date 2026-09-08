@tool
class_name GSTStack
extends Resource

## The saved unit of work: an ordered layer stack plus output wiring.
## Design: docs/DESIGN.md, Data model.

enum CoordSpace {
	UV,
	SCREEN_UV,
	LOCAL,
}

@export var coord_space: CoordSpace = CoordSpace.UV
## Order is stack order. Index 0 is bottom.
@export var layers: Array[GSTLayer] = []
## Color-kind layer id.
@export var output_color: StringName = &""
## Field-kind layer id, or the literal "texture" / "color_alpha" / "none".
@export var output_alpha: StringName = &"none"
## Monotonic. Never reused across add/delete/add (decision 22).
@export var next_id: int = 0
