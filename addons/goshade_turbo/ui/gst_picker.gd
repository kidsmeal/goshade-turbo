@tool
class_name GSTPicker
extends PanelContainer

## Embedded chooser view for the editing area. The owner supplies eligible
## rows and owns destination validation, mutation, refusal lifetime, and close.

signal choice_requested(choice: Dictionary)
signal cancelled()
signal tab_changed(tab: int)

@onready var _heading: Label = %Heading
@onready var _close_button: Button = %CloseButton
@onready var _tabs: TabBar = %Tabs
@onready var _search: LineEdit = %Search
@onready var _tree: Tree = %Tree
@onready var _selected_details: Label = %SelectedDetails
@onready var _refusal: Label = %Refusal

var _rows: Array[Dictionary] = []
var _has_tabs: bool = false
var _suppress_tab_signal: bool = false
var _ignore_item_activated: bool = false


func _ready() -> void:
	_apply_opaque_panel_style()
	_close_button.pressed.connect(_on_cancel_requested)
	_tabs.tab_changed.connect(_on_tabs_tab_changed)
	_search.text_changed.connect(_on_search_changed)
	_search.text_submitted.connect(_on_search_submitted)
	_search.gui_input.connect(_on_search_gui_input)
	_tree.item_mouse_selected.connect(_on_tree_item_mouse_selected)
	_tree.item_activated.connect(_on_tree_item_activated)
	_tree.item_selected.connect(_update_selected_details)
	_tree.gui_input.connect(_on_tree_gui_input)
	_tree.set_column_title(0, "Function")
	_tree.set_column_title(1, "Kind")
	_tree.set_column_title(2, "Description")
	_tree.set_column_expand(0, true)
	_tree.set_column_expand(1, true)
	_tree.set_column_expand(2, true)
	_tree.resized.connect(_update_column_widths)
	_update_column_widths.call_deferred()


func open_choices(heading: String, rows: Array[Dictionary], has_tabs: bool = false, initial_tab: int = 0) -> void:
	_heading.text = heading
	_heading.tooltip_text = heading
	_has_tabs = has_tabs
	_tabs.visible = has_tabs
	_suppress_tab_signal = true
	_tabs.current_tab = clampi(initial_tab, 0, maxi(0, _tabs.tab_count - 1))
	_suppress_tab_signal = false
	_search.text = ""
	set_refusal("")
	set_choices(rows)
	show()
	_search.call_deferred("grab_focus")


## Replaces the owner's eligible rows while preserving query and tab state.
func set_choices(rows: Array[Dictionary]) -> void:
	_rows.clear()
	for row: Dictionary in rows:
		_rows.append(row.duplicate(true))
	_populate()


## Changes the active choice source without clearing the search query.
func switch_tab(index: int) -> void:
	if not _has_tabs:
		return
	var bounded_index: int = clampi(index, 0, maxi(0, _tabs.tab_count - 1))
	_suppress_tab_signal = true
	_tabs.current_tab = bounded_index
	_suppress_tab_signal = false
	tab_changed.emit(bounded_index)


func set_refusal(reason: String) -> void:
	_refusal.text = reason
	_refusal.visible = not reason.strip_edges().is_empty()


func set_search_text(text: String) -> void:
	_search.text = text
	_apply_search_filter(text)


func get_search_control() -> LineEdit:
	return _search


func get_results_tree() -> Tree:
	return _tree


func get_tab_index() -> int:
	return _tabs.current_tab


## Every current choice value, regardless of the search filter.
func get_all_entry_ids() -> Array[String]:
	var values: Array[String] = []
	for row: Dictionary in _rows:
		values.append(String(row.get("value", "")))
	return values


## Every current choice value whose title or description matches the query.
func get_visible_entry_ids() -> Array[String]:
	var values: Array[String] = []
	for row: Dictionary in get_visible_rows():
		values.append(String(row.get("value", "")))
	return values


func get_visible_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var root: TreeItem = _tree.get_root()
	if root == null:
		return rows
	for folder_item: TreeItem in root.get_children():
		if not folder_item.visible:
			continue
		for item: TreeItem in folder_item.get_children():
			if not item.visible:
				continue
			var data: Variant = item.get_metadata(0)
			if typeof(data) == TYPE_DICTIONARY:
				rows.append((data as Dictionary).duplicate(true))
	return rows


## Activates an existing visible row through the same path as mouse and Enter.
func activate_value(value: String) -> bool:
	for item: TreeItem in _visible_items():
		var data: Variant = item.get_metadata(0)
		if typeof(data) == TYPE_DICTIONARY and String((data as Dictionary).get("value", "")) == value:
			item.select(0)
			return _activate_item(item)
	return false


func _populate() -> void:
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	var folders: Dictionary = {}
	for source_row: Dictionary in _rows:
		var row: Dictionary = source_row.duplicate(true)
		var category: String = String(row.get("category", ""))
		if category.is_empty():
			category = "Other"
		if not folders.has(category):
			var folder_item: TreeItem = _tree.create_item(root)
			folder_item.set_text(0, category)
			folder_item.set_tooltip_text(0, category)
			for column: int in range(3):
				folder_item.set_selectable(column, false)
			folder_item.set_collapsed(false)
			folders[category] = folder_item
		var item: TreeItem = _tree.create_item(folders[category] as TreeItem)
		var title: String = String(row.get("title", ""))
		var kind: String = String(row.get("kind", ""))
		var description: String = String(row.get("description", ""))
		var conversion: String = String(row.get("conversion", ""))
		var kind_or_conversion: String = conversion if not conversion.is_empty() else kind
		item.set_text(0, title)
		item.set_text(1, kind_or_conversion)
		item.set_text(2, description)
		item.set_tooltip_text(0, title)
		item.set_tooltip_text(1, kind_or_conversion)
		item.set_tooltip_text(2, description)
		item.set_metadata(0, row)
	_apply_search_filter(_search.text)
	_update_selected_details()
	_update_column_widths()


func _apply_search_filter(text: String) -> void:
	var needle: String = text.strip_edges().to_lower()
	var root: TreeItem = _tree.get_root()
	if root == null:
		return
	for folder_item: TreeItem in root.get_children():
		var any_visible: bool = false
		for item: TreeItem in folder_item.get_children():
			var data: Variant = item.get_metadata(0)
			var visible_row: bool = false
			if typeof(data) == TYPE_DICTIONARY:
				var row: Dictionary = data as Dictionary
				var title: String = String(row.get("title", "")).to_lower()
				var description: String = String(row.get("description", "")).to_lower()
				visible_row = needle.is_empty() or title.contains(needle) or description.contains(needle)
			item.visible = visible_row
			any_visible = any_visible or visible_row
		folder_item.visible = any_visible
	_update_selected_details()


func _visible_items() -> Array[TreeItem]:
	var items: Array[TreeItem] = []
	var root: TreeItem = _tree.get_root()
	if root == null:
		return items
	for folder_item: TreeItem in root.get_children():
		if not folder_item.visible:
			continue
		for item: TreeItem in folder_item.get_children():
			if item.visible:
				items.append(item)
	return items


func _first_or_selected_visible_item() -> TreeItem:
	var items: Array[TreeItem] = _visible_items()
	if items.is_empty():
		return null
	var selected: TreeItem = _tree.get_selected()
	if selected != null and items.has(selected):
		return selected
	return items[0]


func _move_from_search(direction: int) -> void:
	var items: Array[TreeItem] = _visible_items()
	if items.is_empty():
		return
	var selected: TreeItem = _tree.get_selected()
	var selected_index: int = items.find(selected)
	var target_index: int = 0 if direction > 0 else items.size() - 1
	if selected_index != -1:
		target_index = clampi(selected_index + direction, 0, items.size() - 1)
	items[target_index].select(0)
	_tree.grab_focus()


func _activate_item(item: TreeItem) -> bool:
	if item == null:
		return false
	var data: Variant = item.get_metadata(0)
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var choice: Dictionary = (data as Dictionary).duplicate(true)
	if not choice.has("value"):
		return false
	choice_requested.emit(choice)
	return true


func _update_selected_details() -> void:
	var item: TreeItem = _tree.get_selected()
	if item == null or not item.visible or item.get_parent() == null or not item.get_parent().visible:
		_selected_details.text = ""
		_selected_details.visible = false
		return
	var data: Variant = item.get_metadata(0)
	if typeof(data) != TYPE_DICTIONARY:
		_selected_details.text = ""
		_selected_details.visible = false
		return
	var row: Dictionary = data as Dictionary
	var kind: String = String(row.get("kind", ""))
	var conversion: String = String(row.get("conversion", ""))
	var details: Array[String] = [String(row.get("title", ""))]
	if not conversion.is_empty():
		details.append(conversion)
	elif not kind.is_empty():
		details.append(kind)
	var description: String = String(row.get("description", ""))
	if not description.is_empty():
		details.append(description)
	_selected_details.text = "\n".join(details)
	_selected_details.tooltip_text = description
	_selected_details.visible = true


func _on_search_changed(text: String) -> void:
	_apply_search_filter(text)


func _on_search_submitted(_text: String) -> void:
	_activate_item(_first_or_selected_visible_item())


func _on_search_gui_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed:
		return
	match key_event.keycode:
		KEY_DOWN:
			_move_from_search(1)
			_search.accept_event()
		KEY_UP:
			_move_from_search(-1)
			_search.accept_event()
		KEY_ESCAPE:
			if not key_event.echo:
				cancelled.emit()
			_search.accept_event()


func _on_tree_gui_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed:
		return
	if key_event.keycode == KEY_ESCAPE:
		if not key_event.echo:
			cancelled.emit()
		_tree.accept_event()


func _on_tree_item_mouse_selected(_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	_ignore_item_activated = true
	_reset_item_activated_guard.call_deferred()
	_activate_item(_tree.get_selected())


func _on_tree_item_activated() -> void:
	if _ignore_item_activated:
		_ignore_item_activated = false
		return
	_activate_item(_first_or_selected_visible_item())


func _reset_item_activated_guard() -> void:
	_ignore_item_activated = false


func _on_tabs_tab_changed(tab: int) -> void:
	if not _suppress_tab_signal:
		tab_changed.emit(tab)


func _on_cancel_requested() -> void:
	cancelled.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		cancelled.emit()
		get_viewport().set_input_as_handled()


func _update_column_widths() -> void:
	if _tree == null:
		return
	var narrow: bool = _tree.size.x < 600.0
	_tree.set_column_custom_minimum_width(0, 0)
	_tree.set_column_custom_minimum_width(1, 0)
	_tree.set_column_custom_minimum_width(2, 0)
	_tree.set_column_expand_ratio(0, 45 if narrow else 35)
	_tree.set_column_expand_ratio(1, 30 if narrow else 25)
	_tree.set_column_expand_ratio(2, 25 if narrow else 40)
	_update_kind_column_rows()


func _update_kind_column_rows() -> void:
	var root: TreeItem = _tree.get_root()
	if root == null:
		return
	var font: Font = _tree.get_theme_font(&"font", &"Tree")
	var font_size: int = _tree.get_theme_font_size(&"font_size", &"Tree")
	var text_width: float = float(_tree.get_column_width(1))
	text_width -= float(_tree.get_theme_constant(&"h_separation", &"Tree"))
	text_width -= float(_tree.get_theme_constant(&"inner_item_margin_left", &"Tree"))
	text_width -= float(_tree.get_theme_constant(&"inner_item_margin_right", &"Tree"))
	text_width = maxf(1.0, text_width)
	var row_vertical_padding: float = float(
		_tree.get_theme_constant(&"inner_item_margin_top", &"Tree")
		+ _tree.get_theme_constant(&"inner_item_margin_bottom", &"Tree")
	)
	for folder_item: TreeItem in root.get_children():
		for item: TreeItem in folder_item.get_children():
			var data: Variant = item.get_metadata(0)
			if typeof(data) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = data as Dictionary
			var kind: String = String(row.get("kind", ""))
			var conversion: String = String(row.get("conversion", ""))
			var source_text: String = conversion if not conversion.is_empty() else kind
			var text: String = _wrap_tree_text(source_text, text_width, font, font_size)
			item.set_text(1, text)
			var line_count: int = text.count("\n") + 1
			var row_height: int = ceili(font.get_height(font_size) * line_count + row_vertical_padding)
			item.set_custom_minimum_height(row_height if line_count > 1 else 0)


func _wrap_tree_text(source_text: String, maximum_width: float, font: Font, font_size: int) -> String:
	var words: PackedStringArray = source_text.replace("\n", " ").split(" ", false)
	var lines: Array[String] = []
	var current_line: String = ""
	for word: String in words:
		var candidate: String = word if current_line.is_empty() else "%s %s" % [current_line, word]
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= maximum_width:
			current_line = candidate
			continue
		if not current_line.is_empty():
			lines.append(current_line)
			current_line = ""
		if font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= maximum_width:
			current_line = word
			continue
		var pieces: Array[String] = _split_tree_word(word, maximum_width, font, font_size)
		for index: int in range(pieces.size() - 1):
			lines.append(pieces[index])
		current_line = pieces[-1]
	if not current_line.is_empty():
		lines.append(current_line)
	return "\n".join(lines)


func _split_tree_word(word: String, maximum_width: float, font: Font, font_size: int) -> Array[String]:
	var pieces: Array[String] = []
	var current_piece: String = ""
	for index: int in range(word.length()):
		var character: String = word.substr(index, 1)
		var candidate: String = current_piece + character
		if not current_piece.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > maximum_width:
			pieces.append(current_piece)
			current_piece = character
		else:
			current_piece = candidate
	if not current_piece.is_empty():
		pieces.append(current_piece)
	return pieces


func _apply_opaque_panel_style() -> void:
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	var base_color: Color = get_theme_color(&"base_color", &"Editor")
	base_color.a = 1.0
	panel_style.bg_color = base_color
	add_theme_stylebox_override(&"panel", panel_style)
