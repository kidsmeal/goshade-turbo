extends SceneTree

## Prints the README "Library" table from the manifests:
## `godot --headless --path . -s res://tests/print_roster.gd`
## One markdown row per entry under addons/goshade_turbo/library/, sorted by
## id. Read-only: manifests are never re-saved by the plugin. Paste the
## output over the table in README.md after any library change.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var library: GSTLibrary = GSTLibrary.new()
	library.scan()
	var ids: Array = library.entries.keys()
	ids.sort()
	print("| id | function | kind signature | source_math |")
	print("|---|---|---|---|")
	for id: String in ids:
		var entry: GSTManifestEntry = library.get_entry(id)
		print("| `%s` | `%s` | %s | %s |" % [id, entry.function, _signature(entry), entry.source_math.replace("|", "\\|")])
	quit(0)


func _signature(entry: GSTManifestEntry) -> String:
	var inputs: Array[String] = []
	for input: Dictionary in entry.inputs:
		inputs.append(_kind(int(input["kind"])))
	var text: String = "(%s) -> %s" % [", ".join(inputs), _kind(entry.kind_out)]
	if entry.is_source():
		text += " (source)"
	elif entry.samples_source:
		text += " (filter)"
	elif entry.coord:
		text += " (generator)"
	return text


func _kind(kind: int) -> String:
	return "color" if kind == GSTLayer.Kind.COLOR else "field"
