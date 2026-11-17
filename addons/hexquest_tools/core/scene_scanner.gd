@tool
extends RefCounted
## Finds (and rewrites) `dialogue_ids` in .tscn files by reading them as text, so it works on every
## scene in the project whether or not it is open.

## All scene files in the project (skips .godot and addons).
static func find_scenes(dir: String = "res://") -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		var full := dir.path_join(name)
		if da.current_is_dir():
			if not name.begins_with(".") and name != "addons":
				out.append_array(find_scenes(full))
		elif name.ends_with(".tscn"):
			out.append(full)
		name = da.get_next()
	da.list_dir_end()
	return out


## [{"scene": path, "node": "NPC2", "ids": ["NPC002", "NPC000"]}, ...]
static func scan_dialogue_refs() -> Array:
	var out: Array = []
	var id_rx := RegEx.create_from_string("\"([^\"]*)\"")
	for scene in find_scenes():
		var node := ""
		for line in FileAccess.get_file_as_string(scene).split("\n"):
			if line.begins_with("[node name=\""):
				node = line.get_slice("\"", 1)
			elif line.begins_with("dialogue_ids"):
				var ids: Array = []
				for m in id_rx.search_all(line):
					ids.append(m.get_string(1))
				out.append({"scene": scene, "node": node, "ids": ids})
	return out


## Replaces "old_id" with "new_id" inside every dialogue_ids line. Returns the scene paths that changed.
static func rename_in_scenes(old_id: String, new_id: String) -> PackedStringArray:
	var changed := PackedStringArray()
	for scene in find_scenes():
		var text := FileAccess.get_file_as_string(scene)
		if not text.contains("\"%s\"" % old_id):
			continue
		var lines := text.split("\n")
		var touched := false
		for i in lines.size():
			if lines[i].begins_with("dialogue_ids") and lines[i].contains("\"%s\"" % old_id):
				lines[i] = lines[i].replace("\"%s\"" % old_id, "\"%s\"" % new_id)
				touched = true
		if touched:
			var f := FileAccess.open(scene, FileAccess.WRITE)
			f.store_string("\n".join(lines))
			f.close()
			changed.append(scene)
	return changed
