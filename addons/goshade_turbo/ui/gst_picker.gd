@tool
class_name GSTPicker
extends PopupPanel

## Grouped-by-taxonomy-folder entry picker (decision 19): function name, kind
## signature, description. No display names, no thumbnails. `open_for_add()`
## shows every entry; `open_for_slot(kind)` pre-filters to entries whose
## output kind matches. Search filters the currently shown set.

signal entry_picked(entry_id: String)

@onready var _search: LineEdit = %Search
@onready var _tree: Tree = %Tree

var _library: GSTLibrary = null
var _has_kind_filter: bool = false
var _kind_filter: GSTLayer.Kind = GSTLayer.Kind.FIELD


func _ready() -> void:
	_search.text_changed.connect(_on_search_changed)
	_tree.item_activated.connect(_on_item_activated)


func open_for_add(library: GSTLibrary) -> void:
	_library = library
	_has_kind_filter = false
	_search.text = ""
	_populate()
	popup_centered()


func open_for_slot(library: GSTLibrary, kind: GSTLayer.Kind) -> void:
	_library = library
	_has_kind_filter = true
	_kind_filter = kind
	_search.text = ""
	_populate()
	popup_centered()


func _kind_label(kind: GSTLayer.Kind) -> String:
	return "field" if kind == GSTLayer.Kind.FIELD else "color"


func _kind_signature(entry: GSTManifestEntry) -> String:
	var input_labels: Array[String] = []
	for input: Dictionary in entry.inputs:
		input_labels.append(_kind_label(input["kind"] as GSTLayer.Kind))
	return "(%s) -> %s" % [", ".join(input_labels), _kind_label(entry.kind_out)]


func _taxonomy_folder(entry_id: String) -> String:
	var slash: int = entry_id.find("/")
	if slash == -1:
		return entry_id
	return entry_id.substr(0, slash)


func _populate() -> void:
	_tree.clear()
	if _library == null:
		return
	var root: TreeItem = _tree.create_item()
	_tree.hide_root = true
	var folder_items: Dictionary = {}
	var ids: Array = _library.entries.keys()
	ids.sort()
	for entry_id: String in ids:
		var entry: GSTManifestEntry = _library.get_entry(entry_id)
		if _has_kind_filter and entry.kind_out != _kind_filter:
			continue
		var folder: String = _taxonomy_folder(entry_id)
		if not folder_items.has(folder):
			var folder_item: TreeItem = _tree.create_item(root)
			folder_item.set_text(0, folder)
			folder_item.set_selectable(0, false)
			folder_items[folder] = folder_item
		var row: TreeItem = _tree.create_item(folder_items[folder])
		row.set_text(0, "%s %s - %s" % [entry.function, _kind_signature(entry), entry.description])
		row.set_metadata(0, entry.id)
	_apply_search_filter(_search.text)


func _on_search_changed(text: String) -> void:
	_apply_search_filter(text)


## Sets the search box text and applies the filter immediately. Test helper
## (tests/gst_editor_smoke.gd): setting LineEdit.text alone does not emit
## text_changed.
func set_search_text(text: String) -> void:
	_search.text = text
	_apply_search_filter(text)


## Hides leaf rows whose function name does not contain the search text, and
## hides a folder row once every child under it is hidden.
func _apply_search_filter(text: String) -> void:
	var needle: String = text.to_lower()
	var root: TreeItem = _tree.get_root()
	if root == null:
		return
	for folder_item: TreeItem in root.get_children():
		var any_visible: bool = false
		for row: TreeItem in folder_item.get_children():
			var entry_id: String = row.get_metadata(0)
			var entry: GSTManifestEntry = _library.get_entry(entry_id)
			var visible: bool = needle.is_empty() or entry.function.to_lower().contains(needle)
			row.visible = visible
			if visible:
				any_visible = true
		folder_item.visible = any_visible


## Every entry id currently loaded into the tree, regardless of search text
## (post kind-filter). Test/introspection helper (tests/gst_editor_smoke.gd).
func get_all_entry_ids() -> Array[String]:
	var out: Array[String] = []
	var root: TreeItem = _tree.get_root()
	if root == null:
		return out
	for folder_item: TreeItem in root.get_children():
		for row: TreeItem in folder_item.get_children():
			out.append(row.get_metadata(0) as String)
	return out


## Every entry id currently visible in the tree (post kind-filter and post
## search-filter). Test/introspection helper (tests/gst_editor_smoke.gd).
func get_visible_entry_ids() -> Array[String]:
	var out: Array[String] = []
	var root: TreeItem = _tree.get_root()
	if root == null:
		return out
	for folder_item: TreeItem in root.get_children():
		if not folder_item.visible:
			continue
		for row: TreeItem in folder_item.get_children():
			if row.visible:
				out.append(row.get_metadata(0) as String)
	return out


func _on_item_activated() -> void:
	var selected: TreeItem = _tree.get_selected()
	if selected == null:
		return
	var entry_id: Variant = selected.get_metadata(0)
	if entry_id == null:
		return
	entry_picked.emit(entry_id as String)
	hide()
