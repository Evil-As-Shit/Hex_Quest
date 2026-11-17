@tool
extends RefCounted
## In-memory copy of dialogue.txt with everything the editor needs: queries, edits, id generation,
## rename/delete, conversation building, and saving in the game's own format.
## No editor dependencies, so it can also be used from tests and scripts.

const Config := preload("res://addons/hexquest_tools/hq_config.gd")

## Emitted after any edit. `source` is whoever made it (so a panel can ignore its own edits).
signal changed(source: Object)
## Emitted after the file has been written.
signal saved

## Keys are always written in this order (matches your existing file). Unknown keys are kept, at the end.
const KEY_ORDER := ["id", "tagRequired", "text", "expression", "tagAdd", "isEnd", "divert", "choices", "choice_0", "choice_1"]

enum Kind {NONE, END, DIVERT, CHOICES}

var path: String = Config.DIALOGUE_PATH
var entries: Array = [] # Array[Dictionary], in file order
var dirty: bool = false
var error: String = ""
var _mtime: int = 0
var _index: Dictionary = {} # id -> first entry with that id


# ---------- load / save ----------

func load_file(from_path: String = "") -> bool:
	if from_path != "":
		path = from_path
	entries.clear()
	error = ""
	dirty = false
	if not FileAccess.file_exists(path):
		_mtime = 0
		_reindex()
		return true # a missing file is just an empty database; it's created on save
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		error = "%s: line %d: %s" % [path, json.get_error_line(), json.get_error_message()]
		_reindex()
		return false
	var data: Variant = json.data
	if not (data is Dictionary) or not (data.get("dialogue") is Array):
		error = "%s doesn't contain a \"dialogue\" list" % path
		_reindex()
		return false
	for e in data["dialogue"]:
		if e is Dictionary:
			entries.append(_ordered(e))
	_mtime = FileAccess.get_modified_time(path)
	_reindex()
	changed.emit(null)
	return true


func save_file() -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		error = "Can't write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
		return false
	file.store_string(to_json_text())
	file.close()
	_mtime = FileAccess.get_modified_time(path)
	dirty = false
	saved.emit()
	return true


## True if the file on disk is newer than what we loaded (someone edited it outside the tool).
func changed_on_disk() -> bool:
	return FileAccess.file_exists(path) and FileAccess.get_modified_time(path) != _mtime


func to_json_text() -> String:
	var out: Array = []
	for e in entries:
		out.append(_serialize(e))
	return JSON.stringify({"dialogue": out}, "\t", false) + "\n" # false = keep our key order


# ---------- queries ----------

func has_id(id: String) -> bool:
	return _index.has(id)


func get_entry(id: String) -> Dictionary:
	return _index.get(id, {})


func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		out.append(str(e.get("id", "")))
	return out


## Distinct id prefixes in file order, e.g. ["SAT", "ITM", "NPC"].
func prefixes() -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids():
		var p := prefix_of(id)
		if p != "" and not out.has(p):
			out.append(p)
	return out


static func prefix_of(id: String) -> String:
	var i := id.length()
	while i > 0 and id[i - 1].is_valid_int():
		i -= 1
	return id.substr(0, i)


func next_id(prefix: String) -> String:
	var highest := -1
	var width := 3
	for id in ids():
		if prefix_of(id) == prefix and id.length() > prefix.length():
			var digits := id.substr(prefix.length())
			highest = maxi(highest, digits.to_int())
			width = maxi(width, digits.length())
	return "%s%0*d" % [prefix, width, highest + 1]


static func kind_of(e: Dictionary) -> Kind:
	# Same order the game checks them in.
	if e.has("choices"):
		return Kind.CHOICES
	if e.get("isEnd", false) == true:
		return Kind.END
	if e.has("divert"):
		return Kind.DIVERT
	return Kind.NONE


## What a line displays in lists: "ID  text…"
func label_for(id: String, max_chars: int = 48) -> String:
	var e := get_entry(id)
	if e.is_empty():
		return "%s  (missing)" % id
	var t: String = str(e.get("text", "")).replace("\n", " ")
	if t.length() > max_chars:
		t = t.substr(0, max_chars - 1) + "…"
	return "%s  %s" % [id, t]


## {tag: [ids that add it]}
func tags_added() -> Dictionary:
	return _tag_map("tagAdd")


## {tag: [ids that require it]}
func tags_required() -> Dictionary:
	return _tag_map("tagRequired")


func all_tags() -> PackedStringArray:
	var seen := {}
	for t in tags_added():
		seen[t] = true
	for t in tags_required():
		seen[t] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


## Lines that point at `id`: [{"id": "NPC003", "via": "divert"}, ...]
func references_to(id: String) -> Array:
	var out: Array = []
	for e in entries:
		var from := str(e.get("id", ""))
		if e.get("divert", "") == id:
			out.append({"id": from, "via": "divert"})
		for key in ["choice_0", "choice_1"]:
			if e.get(key) is Array and (e[key] as Array).has(id):
				out.append({"id": from, "via": key})
	return out


## Every id a conversation can reach from `start` (following diverts and both choice branches).
func reachable_from(start: String) -> PackedStringArray:
	var seen := PackedStringArray()
	var todo := [start]
	while not todo.is_empty():
		var id: String = todo.pop_back()
		if seen.has(id) or not has_id(id):
			continue
		seen.append(id)
		var e := get_entry(id)
		if e.get("divert", "") != "":
			todo.append(e["divert"])
		for key in ["choice_0", "choice_1"]:
			if e.get(key) is Array:
				todo.append_array(e[key])
	return seen


# ---------- edits ----------

func touch(source: Object = null) -> void:
	dirty = true
	_reindex()
	changed.emit(source)


func add_entry(e: Dictionary, source: Object = null) -> void:
	entries.append(_ordered(e))
	touch(source)


## A fresh, empty "end of conversation" line. Returns its id.
func new_entry(prefix: String, source: Object = null) -> String:
	var id := next_id(prefix)
	add_entry({"id": id, "text": "", "expression": null, "isEnd": true}, source)
	return id


func duplicate_entry(id: String, source: Object = null) -> String:
	var src := get_entry(id)
	if src.is_empty():
		return ""
	var copy: Dictionary = src.duplicate(true)
	copy["id"] = next_id(prefix_of(id))
	add_entry(copy, source)
	return copy["id"]


func delete_entry(id: String, source: Object = null) -> void:
	for i in entries.size():
		if entries[i].get("id") == id:
			entries.remove_at(i)
			break
	touch(source)


## Switch what happens after a line. Cleans up the keys of the other kinds.
func set_kind(e: Dictionary, kind: Kind) -> void:
	for key in ["isEnd", "divert", "choices", "choice_0", "choice_1"]:
		e.erase(key)
	match kind:
		Kind.END:
			e["isEnd"] = true
		Kind.DIVERT:
			e["divert"] = ""
		Kind.CHOICES:
			e["choices"] = ["Yes", "No"]
			e["choice_0"] = []
			e["choice_1"] = []


## Renames an id and updates every divert / choice list that pointed at it.
## (Scene files are handled separately: SceneScanner.rename_in_scenes.) Returns an error message or "".
func rename_id(old_id: String, new_id: String, source: Object = null) -> String:
	if old_id == new_id:
		return ""
	var rx := RegEx.create_from_string(Config.ID_PATTERN)
	if rx.search(new_id) == null:
		return "Ids must start with a letter and use only letters, digits and _"
	if has_id(new_id):
		return "'%s' already exists" % new_id
	for e in entries:
		if e.get("id") == old_id:
			e["id"] = new_id
		if e.get("divert", "") == old_id:
			e["divert"] = new_id
		for key in ["choice_0", "choice_1"]:
			if e.get(key) is Array:
				var list: Array = e[key]
				for i in list.size():
					if list[i] == old_id:
						list[i] = new_id
	touch(source)
	return ""


# ---------- conversation building ----------

## Splits pasted text into lines. Each non-empty line is one dialogue box; "[expression] text"
## picks a portrait; lines starting with # are comments. Returns [{"text", "expression"}].
static func parse_script(script: String) -> Array:
	var out: Array = []
	var rx := RegEx.create_from_string("^\\[([A-Za-z0-9_]+)\\]\\s*(.*)$")
	for raw in script.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var expression: Variant = null
		var m := rx.search(line)
		if m:
			expression = m.get_string(1)
			line = m.get_string(2)
		out.append({"text": line, "expression": expression})
	return out


## Creates a chain of lines (each diverts to the next, the last ends the conversation).
## `lines` is what parse_script returns. Returns the new ids, first to last.
func create_conversation(lines: Array, prefix: String, requires_tag: String = "", adds_tag: String = "", default_expression: Variant = null, source: Object = null) -> PackedStringArray:
	var new_ids := PackedStringArray()
	if lines.is_empty():
		return new_ids
	# Reserve all ids up front so they are consecutive.
	var first := next_id(prefix)
	var number := first.substr(prefix.length()).to_int()
	var width := first.length() - prefix.length()
	for i in lines.size():
		new_ids.append("%s%0*d" % [prefix, width, number + i])
	for i in lines.size():
		var expression: Variant = lines[i].get("expression", null)
		if expression == null or str(expression) == "":
			expression = default_expression
		var e := {"id": new_ids[i]}
		if i == 0 and requires_tag != "":
			e["tagRequired"] = requires_tag
		e["text"] = lines[i].get("text", "")
		e["expression"] = expression
		if i == lines.size() - 1:
			if adds_tag != "":
				e["tagAdd"] = adds_tag
			e["isEnd"] = true
		else:
			e["divert"] = new_ids[i + 1]
		entries.append(_ordered(e))
	touch(source)
	return new_ids


# ---------- internals ----------

func _tag_map(key: String) -> Dictionary:
	var out := {}
	for e in entries:
		var tag := str(e.get(key, ""))
		if tag != "":
			if not out.has(tag):
				out[tag] = []
			out[tag].append(str(e.get("id", "")))
	return out


func _reindex() -> void:
	_index.clear()
	for e in entries:
		var id := str(e.get("id", ""))
		if not _index.has(id):
			_index[id] = e


# Known keys first in KEY_ORDER, then any unknown keys. In memory, empty values are kept so the UI can hold a half-edited line.
func _ordered(e: Dictionary) -> Dictionary:
	var out := {}
	for key in KEY_ORDER:
		if e.has(key):
			out[key] = e[key]
	for key in e:
		if not out.has(key):
			out[key] = e[key]
	if not out.has("expression"):
		var rebuilt := {}
		for key in out: # keep "expression" in its canonical slot
			rebuilt[key] = out[key]
			if key == "text":
				rebuilt["expression"] = null
		out = rebuilt
	return out


# What is written to disk: empty optional fields are dropped.
func _serialize(e: Dictionary) -> Dictionary:
	var out := {}
	var ordered := _ordered(e)
	for key in ordered:
		var v: Variant = ordered[key]
		match key:
			"tagRequired", "tagAdd", "divert":
				if str(v) == "":
					continue
			"isEnd":
				if v != true:
					continue
			"expression":
				if v == null or str(v) == "" or str(v) == "null":
					v = null
		out[key] = v
	return out
