@tool
extends VBoxContainer
## Everything that's wrong or suspicious across the dialogue file and all scenes, plus a tag overview.

const Ctx := preload("res://addons/hexquest_tools/hq_context.gd")
const Validator := preload("res://addons/hexquest_tools/core/validator.gd")
const Scanner := preload("res://addons/hexquest_tools/core/scene_scanner.gd")

const SEV_TEXT := ["✖ Error", "⚠ Warning", "ℹ Info"]
const SEV_COLOR := [Color(1, 0.45, 0.45), Color(1, 0.8, 0.4), Color(0.7, 0.8, 1)]

var _summary: Label
var _show_info: CheckBox
var _tree: Tree
var _tags: Tree


func _init() -> void:
	name = "Problems"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	add_child(bar)
	var refresh_btn := Ctx.button("Check everything")
	refresh_btn.pressed.connect(refresh)
	bar.add_child(refresh_btn)
	_show_info = CheckBox.new()
	_show_info.text = "Show info (unused lines)"
	_show_info.toggled.connect(func(_b): refresh())
	bar.add_child(_show_info)
	_summary = Ctx.label("")
	bar.add_child(_summary)

	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_tree = Tree.new()
	_tree.columns = 3
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "")
	_tree.set_column_title(1, "Where")
	_tree.set_column_title(2, "What")
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 110)
	_tree.set_column_custom_minimum_width(1, 220)
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 200)
	_tree.item_activated.connect(_on_activated)
	split.add_child(_tree)
	_tags = Tree.new()
	_tags.columns = 3
	_tags.column_titles_visible = true
	_tags.set_column_title(0, "Tag")
	_tags.set_column_title(1, "Set by")
	_tags.set_column_title(2, "Needed by")
	_tags.hide_root = true
	_tags.custom_minimum_size = Vector2(0, 140)
	_tags.item_activated.connect(func():
		var it := _tags.get_selected()
		if it and it.get_metadata(0) != null:
			Ctx.open_dialogue(str(it.get_metadata(0))))
	split.add_child(_tags)
	visibility_changed.connect(func(): if visible: refresh())


func refresh() -> void:
	var db := Ctx.get_db()
	var problems := Validator.run(db, Scanner.scan_dialogue_refs())
	_tree.clear()
	var root := _tree.create_item()
	var counts := [0, 0, 0]
	for p in problems:
		counts[p["sev"]] += 1
		if p["sev"] == Validator.Severity.INFO and not _show_info.button_pressed:
			continue
		var it := _tree.create_item(root)
		it.set_text(0, SEV_TEXT[p["sev"]])
		it.set_custom_color(0, SEV_COLOR[p["sev"]])
		if p["id"] != "":
			it.set_text(1, str(p["id"]))
			it.set_metadata(0, {"id": p["id"]})
		if p["node"] != "":
			it.set_text(1, "%s  (%s)" % [p["node"], p["scene"].get_file().get_basename()])
			it.set_metadata(0, {"scene": p["scene"]})
		it.set_text(2, p["msg"])
	_summary.text = "   %d error%s · %d warning%s · %d info" % [counts[0], "" if counts[0] == 1 else "s", counts[1], "" if counts[1] == 1 else "s", counts[2]]
	_summary.modulate = SEV_COLOR[0] if counts[0] > 0 else (SEV_COLOR[1] if counts[1] > 0 else Color(0.6, 1, 0.6))
	if problems.is_empty():
		var ok := _tree.create_item(root)
		ok.set_text(0, "✔ All good")
	_fill_tags(db)


func _fill_tags(db: RefCounted) -> void:
	_tags.clear()
	var root := _tags.create_item()
	var added: Dictionary = db.tags_added()
	var required: Dictionary = db.tags_required()
	for tag in db.all_tags():
		var it := _tags.create_item(root)
		it.set_text(0, tag)
		var by: Array = added.get(tag, [])
		var need: Array = required.get(tag, [])
		it.set_text(1, ", ".join(PackedStringArray(by)) if not by.is_empty() else "(nothing)")
		it.set_text(2, ", ".join(PackedStringArray(need)) if not need.is_empty() else "(nothing)")
		if by.is_empty():
			it.set_custom_color(1, SEV_COLOR[1])
		if need.is_empty():
			it.set_custom_color(2, SEV_COLOR[2])
		var jump: Array = by if not by.is_empty() else need
		it.set_metadata(0, jump[0] if not jump.is_empty() else null)


func _on_activated() -> void:
	var it := _tree.get_selected()
	if it == null or not (it.get_metadata(0) is Dictionary):
		return
	var meta: Dictionary = it.get_metadata(0)
	if meta.has("id"):
		Ctx.open_dialogue(meta["id"])
	elif meta.has("scene") and Ctx.editor() != null:
		Ctx.editor().open_scene_from_path(meta["scene"])
