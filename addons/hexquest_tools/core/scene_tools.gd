@tool
extends RefCounted
## Helpers for working with rooms and objects inside an open scene.

const Config := preload("res://addons/hexquest_tools/hq_config.gd")


static func is_room(node: Node) -> bool:
	var script: Script = node.get_script()
	return script != null and script.resource_path == Config.ROOM_SCRIPT


static func is_interactable(node: Node) -> bool:
	var script: Script = node.get_script()
	return script != null and script.resource_path.begins_with("res://Scripts/Objects/")


static func find_rooms(scene_root: Node) -> Array:
	var out: Array = []
	_collect(scene_root, out)
	return out


static func _collect(node: Node, out: Array) -> void:
	if is_room(node):
		out.append(node)
	for child in node.get_children():
		_collect(child, out)


## The node objects live under (so they depth-sort with Hexy).
static func ysort_of(scene_root: Node) -> Node:
	var n := scene_root.get_node_or_null(Config.YSORT_NODE)
	return n if n != null else scene_root


static func reveal_nodes_of(room: Node) -> Array[NodePath]:
	var out: Array[NodePath] = []
	for p in room.get("reveal_nodes"):
		out.append(p)
	return out


## Nodes under the YSort that could belong to a room: not Hexy, not a room itself.
static func room_candidates(scene_root: Node) -> Array:
	var out: Array = []
	for child in ysort_of(scene_root).get_children():
		if child is CharacterBody2D or not (child is Node2D) or _contains_room(child):
			continue
		out.append(child)
	return out


static func _contains_room(node: Node) -> bool:
	if is_room(node):
		return true
	for c in node.get_children():
		if _contains_room(c):
			return true
	return false


## World-space polygons of a room's floor area.
static func room_polygons(room: Node2D) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for child in room.get_children():
		if child is CollisionPolygon2D:
			var poly := PackedVector2Array()
			for p in (child as CollisionPolygon2D).polygon:
				poly.append((child as CollisionPolygon2D).global_transform * p)
			out.append(poly)
	return out


## {room node: [candidate nodes whose origin is inside the room's area]}, skipping nodes already assigned.
static func suggest_assignments(scene_root: Node) -> Dictionary:
	var out := {}
	var rooms := find_rooms(scene_root)
	var assigned := {}
	for room in rooms:
		for path in reveal_nodes_of(room):
			var n: Node = room.get_node_or_null(path)
			if n:
				assigned[n] = true
	for room in rooms:
		var polys := room_polygons(room)
		var found: Array = []
		for node in room_candidates(scene_root):
			if assigned.has(node):
				continue
			for poly in polys:
				if Geometry2D.is_point_in_polygon((node as Node2D).global_position, poly):
					found.append(node)
					break
		if not found.is_empty():
			out[room] = found
	return out


## Which room (if any) lists this node in reveal_nodes.
static func room_of(scene_root: Node, node: Node) -> Node:
	for room in find_rooms(scene_root):
		for path in reveal_nodes_of(room):
			if room.get_node_or_null(path) == node:
				return room
	return null
