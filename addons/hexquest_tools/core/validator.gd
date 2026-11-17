@tool
extends RefCounted
## Checks dialogue data (and the scenes that use it) for things that would break or confuse the game.

const Config := preload("res://addons/hexquest_tools/hq_config.gd")
const DialogueDB := preload("res://addons/hexquest_tools/core/dialogue_db.gd")
const Metrics := preload("res://addons/hexquest_tools/core/dialogue_metrics.gd")

enum Severity {ERROR, WARNING, INFO}


## `scene_refs` is SceneScanner.scan_dialogue_refs(). Returns problems sorted worst-first:
## [{"sev": Severity, "id": dialogue id or "", "scene": path or "", "node": name or "", "msg": text}]
static func run(db: DialogueDB, scene_refs: Array) -> Array:
	var out: Array = []

	# ---- duplicate ids
	var seen := {}
	for e in db.entries:
		var id := str(e.get("id", ""))
		if id == "":
			out.append(_p(Severity.ERROR, "", "A line has no id"))
		elif seen.has(id):
			out.append(_p(Severity.ERROR, id, "Duplicate id: only the first '%s' is used, the others are ignored" % id))
		seen[id] = true

	var added := db.tags_added()
	var used_ids := {} # ids referenced from somewhere

	for e in db.entries:
		var id := str(e.get("id", ""))
		var kind := DialogueDB.kind_of(e)
		if str(e.get("text", "")).strip_edges() == "":
			out.append(_p(Severity.WARNING, id, "Empty text"))

		# ---- what happens after the line
		var set_kinds := 0
		for key in ["isEnd", "divert", "choices"]:
			if e.has(key):
				set_kinds += 1
		if set_kinds > 1:
			out.append(_p(Severity.WARNING, id, "Has more than one of isEnd / divert / choices. The game uses choices first, then isEnd, then divert"))
		match kind:
			DialogueDB.Kind.NONE:
				out.append(_p(Severity.ERROR, id, "Dead end: no isEnd, divert or choices, so the conversation can't finish properly"))
			DialogueDB.Kind.DIVERT:
				var target := str(e["divert"])
				used_ids[target] = true
				if target == "":
					out.append(_p(Severity.ERROR, id, "Continues to nothing (divert is empty)"))
				elif not db.has_id(target):
					out.append(_p(Severity.ERROR, id, "Continues to '%s', which doesn't exist" % target))
				elif _loops(db, id):
					out.append(_p(Severity.WARNING, id, "Leads into a loop: the conversation never ends"))
			DialogueDB.Kind.CHOICES:
				_check_choices(db, e, id, out, used_ids)

		# ---- tags
		var req := str(e.get("tagRequired", ""))
		if req != "" and not added.has(req):
			out.append(_p(Severity.WARNING, id, "Requires tag '%s', but no line adds it (fine if code sets it)" % req))

		# ---- portrait
		var expression: Variant = e.get("expression")
		var has_portrait := false
		if expression != null and str(expression) != "" and str(expression) != "null":
			var file := Config.PORTRAIT_DIR + str(expression) + ".png"
			if ResourceLoader.exists(file):
				has_portrait = true
			else:
				out.append(_p(Severity.WARNING, id, "Portrait '%s' not found (%s)" % [expression, file]))

		# ---- text fits the box?
		var m := Metrics.measure(str(e.get("text", "")), has_portrait)
		if m["overflow"]:
			out.append(_p(Severity.WARNING, id, "Text is too long for the dialogue box (%d lines, only about %d px of height fit)" % [m["lines"], int(m["available"])]))

	# ---- scenes
	for ref in scene_refs:
		for id in ref["ids"]:
			used_ids[id] = true
			if not db.has_id(id):
				out.append(_p(Severity.ERROR, "", "Uses dialogue '%s', which doesn't exist" % id, ref["scene"], ref["node"]))
		_check_priority_order(db, ref["ids"], out, ref["scene"], ref["node"], "")

	# ---- unused lines (informational)
	for e in db.entries:
		var id := str(e.get("id", ""))
		if not used_ids.has(id) and not _referenced_by_entries(db, id):
			out.append(_p(Severity.INFO, id, "Not used by any object in a scene or by another line (fine if code uses it)"))

	out.sort_custom(func(a, b): return a["sev"] < b["sev"])
	return out


static func _check_choices(db: DialogueDB, e: Dictionary, id: String, out: Array, used_ids: Dictionary) -> void:
	var labels: Variant = e.get("choices")
	if not (labels is Array) or (labels as Array).size() != 2:
		out.append(_p(Severity.ERROR, id, "'choices' must contain exactly 2 labels (the dialogue box has 2 buttons)"))
	else:
		for i in 2:
			if str(labels[i]).strip_edges() == "":
				out.append(_p(Severity.ERROR, id, "Choice %d has no label" % (i + 1)))
	for i in 2:
		var key := "choice_%d" % i
		var list: Variant = e.get(key)
		if not (list is Array) or (list as Array).is_empty():
			out.append(_p(Severity.ERROR, id, "Choice %d leads nowhere (%s is empty)" % [i + 1, key]))
			continue
		for target in list:
			used_ids[target] = true
			if not db.has_id(str(target)):
				out.append(_p(Severity.ERROR, id, "Choice %d leads to '%s', which doesn't exist" % [i + 1, target]))
		_check_priority_order(db, list, out, "", "", id)


# A list of ids is checked top to bottom and the FIRST one whose tag requirement is met is shown.
# So any entry after one with no tagRequired can never appear.
static func _check_priority_order(db: DialogueDB, ids: Array, out: Array, scene: String, node: String, from_id: String) -> void:
	var unconditional := ""
	for id in ids:
		if unconditional != "":
			var msg := "'%s' can never show: '%s' above it has no tag requirement, so it always wins" % [id, unconditional]
			out.append(_p(Severity.WARNING, from_id, msg, scene, node))
			continue
		var e := db.get_entry(str(id))
		if not e.is_empty() and str(e.get("tagRequired", "")) == "":
			unconditional = str(id)


static func _loops(db: DialogueDB, start: String) -> bool:
	var seen := {}
	var id := start
	while db.has_id(id):
		if seen.has(id):
			return true
		seen[id] = true
		var e := db.get_entry(id)
		if e.get("divert", "") == "":
			return false
		id = str(e["divert"])
	return false


static func _referenced_by_entries(db: DialogueDB, id: String) -> bool:
	return not db.references_to(id).is_empty()


static func _p(sev: Severity, id: String, msg: String, scene: String = "", node: String = "") -> Dictionary:
	return {"sev": sev, "id": id, "scene": scene, "node": node, "msg": msg}
