extends Node

class_name DialogueParser

## Reads a JSON file shaped like {"<table>": [{"id": "...", ...}, ...]}
## and returns {id: entry}. Returns an empty Dictionary (and logs why) on failure.
static func loadDB(json_path: String, table: String) -> Dictionary:
	var result := {}
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("DialogueParser: can't open %s (%s)" % [json_path, error_string(FileAccess.get_open_error())])
		return result

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("DialogueParser: JSON error in %s at line %d: %s" % [json_path, json.get_error_line(), json.get_error_message()])
		return result

	if not (json.data is Dictionary) or not json.data.has(table):
		push_error("DialogueParser: %s has no '%s' table" % [json_path, table])
		return result

	for entry in json.data[table]:
		result[entry["id"]] = entry
	return result
