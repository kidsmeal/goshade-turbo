@tool
class_name GSTCoordBlock
extends Resource

## Generator coord transform: scale/offset/rotation/scroll plus two optional
## field-kind warp inputs. Design: docs/DESIGN.md, decision 4 and Data model.

const EDITOR_METADATA: Dictionary = {
	&"scale": {
		"label": "Scale",
		"description": "Multiplies coordinates before the function runs. Higher values repeat and shrink features.",
	},
	&"offset": {
		"label": "Position",
		"description": "Offsets coordinates in the selected coordinate space.",
	},
	&"rotation": {
		"label": "Rotation",
		"description": "Rotates coordinates around the coordinate origin, in radians.",
	},
	&"scroll": {
		"label": "Movement speed",
		"description": "Moves coordinates over time, in coordinate units per second.",
	},
	&"warp_x": {
		"label": "Horizontal distortion",
		"description": "Selects an earlier layer that distorts horizontal coordinates.",
	},
	&"warp_y": {
		"label": "Vertical distortion",
		"description": "Selects an earlier layer that distorts vertical coordinates.",
	},
	&"warp_strength": {
		"label": "Distortion strength",
		"description": "Scales the horizontal and vertical distortion inputs.",
	},
}

@export var scale: Vector2 = Vector2.ONE
@export var offset: Vector2 = Vector2.ZERO
@export var rotation: float = 0.0
@export var scroll: Vector2 = Vector2.ZERO
## Field-kind layer id, or empty when unset.
@export var warp_x: StringName = &""
## Field-kind layer id, or empty when unset.
@export var warp_y: StringName = &""
@export var warp_strength: float = 0.0

const EDITOR_VISIBLE_PROPERTIES: Array[StringName] = [
	&"scale",
	&"offset",
	&"rotation",
	&"scroll",
	&"warp_strength",
]


## The native coordinate inspector shows this whitelist. Distortion references
## use filtered selector rows; every other field keeps its storage usage.
func _validate_property(property: Dictionary) -> void:
	if StringName(property.get("name", &"")) not in EDITOR_VISIBLE_PROPERTIES:
		property["usage"] = int(property.get("usage", 0)) & ~PROPERTY_USAGE_EDITOR


static func get_editor_metadata(property: StringName) -> Dictionary:
	var metadata: Variant = EDITOR_METADATA.get(property, {})
	return metadata as Dictionary if metadata is Dictionary else {}
