extends GSTTestBase

## Layer id allocation: monotonic, never reused. Design decision 22.


func test_ids_monotonic_and_never_reused_across_add_delete_add() -> void:
	var stack: GSTStack = GSTStack.new()
	var a: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	var b: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	assert_eq(a.id, &"0", "first layer gets id 0")
	assert_eq(b.id, &"1", "second layer gets id 1")
	assert_eq(stack.next_id, 2, "next_id advances past both allocated ids")

	GSTStackOps.remove_layer(stack, a.id)
	var c: GSTLayer = GSTStackOps.add_layer(stack, "generative/hash", GSTLayer.Kind.FIELD, true)
	assert_eq(c.id, &"2", "id 0 is not reused after its layer is deleted")
	assert_eq(stack.next_id, 3, "next_id keeps advancing after delete")


func test_generator_layer_allocates_a_coord_block() -> void:
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "generative/fbm", GSTLayer.Kind.FIELD, true)
	assert_not_null(layer.coord, "a generator layer carries a coord block (decision 4)")


func test_operator_layer_has_no_coord_block() -> void:
	var stack: GSTStack = GSTStack.new()
	var layer: GSTLayer = GSTStackOps.add_layer(stack, "fieldops/invert", GSTLayer.Kind.FIELD, false)
	assert_null(layer.coord, "an operator layer has no coord block (decision 4)")


func test_kind_out_is_copied_from_the_manifest_kind_at_creation() -> void:
	var stack: GSTStack = GSTStack.new()
	var color_layer: GSTLayer = GSTStackOps.add_layer(stack, "source/texture", GSTLayer.Kind.COLOR, false)
	assert_eq(color_layer.kind_out, GSTLayer.Kind.COLOR, "kind_out matches the kind passed at creation")
