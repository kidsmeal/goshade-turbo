@tool
class_name GSTIncludeWalk
extends RefCounted

## Depth-first walk over GSTManifestEntry.depends, deduped by manifest id.


## Every entry reachable from `root_ids` through `depends`, post-order
## (dependencies before the entry), each id visited once.
## An id missing from `library` is skipped; the caller reports missing manifests.
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
