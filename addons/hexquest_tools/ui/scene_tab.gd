@tool
extends VBoxContainer
## Overview of the open scene: which objects belong to which room (and so stay hidden until the
## room is entered), plus tools to assign them, by hand or automatically from where they stand.

const Ctx := preload("res://addons/hexquest_tools/hq_context.gd")
const SceneTools := preload("res://addons/hexquest_tools/core/scene_tools.gd")

var _info: Label
var _tree: Tree
var _room_pick: OptionButton
var _auto_dialog: ConfirmationDialog
var _auto_tree: Tree
var _auto_data: Dictionary = {} # room -> [nodes]


func _init() -> void:
	name = "Scene & Rooms"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	add_child(bar)
	var refresh_btn := Ctx.button("Refresh")
	refresh_btn.pressed.connect(refresh)
	bar.add_child(refresh_btn)
	bar.add_child(VSeparator.new())
	bar.add_child(Ctx.label("Add selected nodes to"))
	_room_pick = OptionButton.new()
	bar.add_child(_room_pick)
	var assign := Ctx.button("Assign", "Selected nodes in the scene tree will be hidden until Hexy enters this room")
	assign.pressed.connect(_on_assign_selected)
	bar.add_child(assign)
	bar.add_child(VSeparator.new())
	var auto := Ctx.button("Auto-assign by position…", "Finds objects standing inside a room's floor area")
	auto.pressed.connect(_on_auto)
	bar.add_child(auto)
	var remove := Ctx.button("Remove from room", "Makes the selected row visible from the start again")
	remove.pressed.connect(_on_remove)
	bar.add_child(remove)

	_info = Ctx.label("", true)
	add_child(_info)
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = 4
	_tree.column_titles_visible = true
	for i in 4:
		_tree.set_column_title(i, ["Node", "Kind", "Says", "Status"][i])
		_tree.set_column_expand(i, i != 1)
	_tree.set_column_custom_minimum_width(1, 110)
	_tree.hide_root = true
	_tree.item_activated.connect(_on_activated)
	add_child(_tree)

	_auto_dialog = ConfirmationDialog.new()
	_auto_dialog.title = "Auto-assign by position"
	_auto_dialog.min_size = Vector2i(520, 380)
	_auto_dialog.ok_button_text = "Assign checked"
	var box := VBoxContainer.new()
	_auto_dialog.add_child(box)
	box.add_child(Ctx.label("These objects are standing inside a room's floor area but aren't hidden with it yet.\nUncheck anything that shouldn't be."))
	_auto_tree = Tree.new()
	_auto_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_auto_tree.hide_root = true
	box.add_child(_auto_tree)
	_auto_dialog.confirmed.connect(_apply_auto)
	add_child(_auto_dialog)
	visibility_changed.connect(func(): if visible: refresh())


func refresh() -> void:
	_tree.clear()
	_room_pick.clear()
	var root := Ctx.scene_root()
	if root == null:
		_info.text = "Open a scene (like The Apartments) to see its rooms and objects."
		return
	var db := Ctx.get_db()
	var rooms := SceneTools.find_rooms(root)
	for room in rooms:
		_room_pick.add_item(str(room.name))
		_room_pick.set_item_metadata(_room_pick.item_count - 1, room)
	var tree_root := _tree.create_item()
	var assigned := {}
	for room in rooms:
		var paths := SceneTools.reveal_nodes_of(room)
		var item := _tree.create_item(tree_root)
		item.set_text(0, "🚪 %s  (%d hidden until entered)" % [room.name, paths.size()])
		item.set_text(1, "Room")
		item.set_metadata(0, {"node": room})
		item.set_custom_color(0, Color(1, 0.85, 0.4))
		for path in paths:
			var node: Node = room.get_node_or_null(path)
			var row := _tree.create_item(item)
			if node == null:
				row.set_text(0, str(path))
				row.set_text(3, "⚠ node not found")
				row.set_custom_color(3, Color(1, 0.5, 0.5))
				row.set_metadata(0, {"room": room, "path": path})
				continue
			assigned[node] = true
			_fill_row(row, node, db)
			row.set_metadata(0, {"node": node, "room": room, "path": path})
	var loose := _tree.create_item(tree_root)
	loose.set_text(0, "Visible from the start (not in any room)")
	loose.set_custom_color(0, Color(0.7, 0.9, 1))
	var loose_count := 0
	for node in SceneTools.room_candidates(root):
		if not assigned.has(node):
			var row := _tree.create_item(loose)
			_fill_row(row, node, db)
			row.set_metadata(0, {"node": node})
			loose_count += 1
	_info.text = "%s: %d room%s, %d object%s outside any room. Double-click a row to select it in the scene." % [root.name, rooms.size(), "" if rooms.size() == 1 else "s", loose_count, "" if loose_count == 1 else "s"]


func _fill_row(row: TreeItem, node: Node, db: RefCounted) -> void:
	row.set_text(0, str(node.name))
	var script: Script = node.get_script()
	row.set_text(1, script.resource_path.get_file().get_basename() if script else node.get_class())
	var ids: Variant = node.get("dialogue_ids")
	if ids is Array:
		var status := ""
		if ids.is_empty():
			status = "⚠ no dialogue"
			row.set_text(2, "(nothing)")
		else:
			row.set_text(2, db.label_for(str(ids[0]), 40) + ("  +%d more" % (ids.size() - 1) if ids.size() > 1 else ""))
			for id in ids:
				if not db.has_id(str(id)):
					status = "⚠ '%s' doesn't exist" % id
					break
		if status != "":
			row.set_text(3, status)
			row.set_custom_color(3, Color(1, 0.6, 0.4))


func _selected_meta() -> Dictionary:
	var item := _tree.get_selected()
	return item.get_metadata(0) if item and item.get_metadata(0) is Dictionary else {}


func _on_activated() -> void:
	var meta := _selected_meta()
	var node: Node = meta.get("node")
	if node != null and is_instance_valid(node) and Ctx.editor() != null:
		var sel := Ctx.editor().get_selection()
		sel.clear()
		sel.add_node(node)
		Ctx.editor().edit_node(node)


# ---- changing assignments (always undoable) ----

func _commit(changes: Dictionary, action: String) -> void:
	var ur := Ctx.undo_redo()
	if ur == null or changes.is_empty():
		return
	ur.create_action(action)
	for room in changes:
		ur.add_do_property(room, "reveal_nodes", changes[room])
		ur.add_undo_property(room, "reveal_nodes", SceneTools.reveal_nodes_of(room))
	ur.commit_action()
	refresh()


func _path_for(room: Node, node: Node) -> NodePath:
	return room.get_path_to(node)


func _on_assign_selected() -> void:
	var root := Ctx.scene_root()
	if root == null or _room_pick.selected < 0 or Ctx.editor() == null:
		return
	var target: Node = _room_pick.get_item_metadata(_room_pick.selected)
	var nodes := Ctx.editor().get_selection().get_selected_nodes().filter(func(n): return n is Node2D and not SceneTools.is_room(n) and n != target and not n is CharacterBody2D)
	if nodes.is_empty():
		_info.text = "Select the objects to add in the Scene dock first (not the room itself or Hexy)."
		return
	var changes := {}
	for room in SceneTools.find_rooms(root): # a node can only belong to one room
		var list := SceneTools.reveal_nodes_of(room)
		var changed := false
		for node in nodes:
			var existing := list.filter(func(p): return room.get_node_or_null(p) == node)
			for p in existing:
				if room != target:
					list.erase(p)
					changed = true
		if room == target:
			for node in nodes:
				if not list.any(func(p): return room.get_node_or_null(p) == node):
					list.append(_path_for(room, node))
					changed = true
		if changed:
			changes[room] = list
	_commit(changes, "Assign to " + str(target.name))


func _on_remove() -> void:
	var meta := _selected_meta()
	if not meta.has("room"):
		return
	var room: Node = meta["room"]
	var list := SceneTools.reveal_nodes_of(room)
	list.erase(meta["path"])
	_commit({room: list}, "Remove from " + str(room.name))


func _on_auto() -> void:
	var root := Ctx.scene_root()
	if root == null:
		return
	_auto_data = SceneTools.suggest_assignments(root)
	_auto_tree.clear()
	var tree_root := _auto_tree.create_item()
	if _auto_data.is_empty():
		_info.text = "Nothing to assign: every object inside a room's floor area is already listed."
		return
	for room in _auto_data:
		var room_item := _auto_tree.create_item(tree_root)
		room_item.set_text(0, "🚪 " + str(room.name))
		for node in _auto_data[room]:
			var it := _auto_tree.create_item(room_item)
			it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			it.set_checked(0, true)
			it.set_editable(0, true)
			it.set_text(0, str(node.name))
			it.set_metadata(0, {"room": room, "node": node})
	_auto_dialog.popup_centered()


func _apply_auto() -> void:
	var changes := {}
	var tree_root := _auto_tree.get_root()
	if tree_root == null:
		return
	for room_item in tree_root.get_children():
		for it in room_item.get_children():
			if it.is_checked(0):
				var meta: Dictionary = it.get_metadata(0)
				var room: Node = meta["room"]
				if not changes.has(room):
					changes[room] = SceneTools.reveal_nodes_of(room)
				changes[room].append(_path_for(room, meta["node"]))
	_commit(changes, "Auto-assign objects to rooms")
