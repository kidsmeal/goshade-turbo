@tool
class_name GSTCoordBlock
extends Resource

## Generator coord transform: scale/offset/rotation/scroll plus two optional
## field-kind warp inputs. Design: docs/DESIGN.md, decision 4 and Data model.

@export var scale: Vector2 = Vector2.ONE
@export var offset: Vector2 = Vector2.ZERO
@export var rotation: float = 0.0
@export var scroll: Vector2 = Vector2.ZERO
## Field-kind layer id, or empty when unset.
@export var warp_x: StringName = &""
## Field-kind layer id, or empty when unset.
@export var warp_y: StringName = &""
@export var warp_strength: float = 0.0
