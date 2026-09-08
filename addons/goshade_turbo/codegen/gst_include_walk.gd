@tool
class_name GSTIncludeWalk
extends RefCounted

## Depth-first walk over GSTManifestEntry.depends, deduped by manifest id.
## Design: docs/DESIGN.md, Codegen rules ("Include walk: depth first over
## depends, dedupe by id, emit function bodies before fragment()").


## Returns every entry reachable from `root_ids` through `depends`, each
## entry's dependencies ordered before the entry itself (post-order), each
## id visited once regardless of how many roots or dependents reach it.
## An id missing from `library` is silently skipped: codegen's own callers
## are responsible for reporting a missing manifest as a data problem.
static func walk(root_ids: Array[String], library: GSTLibrary) -> Array[GSTManifestEntry]:
	var visited: Dictionary = {}
	var order: Array[GSTManifestEntry] = []
	for root_id: String in root_ids:
		_visit(root_id, library, visited, order)
	return order


static func _visit(id: String, library: GSTLibrary, visited: Dictionary, order: Array[GSTManifestEntry]) -> void:
	if visited.has(id):
		return
	visited[id] = true
	var entry: GSTManifestEntry = library.get_entry(id)
	if entry == null:
		return
	for dep_id: String in entry.depends:
		_visit(dep_id, library, visited, order)
	order.append(entry)
