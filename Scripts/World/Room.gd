class_name Room
extends Area2D
## A room that stays hidden until Hexy walks into it. On entering, the room and everything listed in
## `reveal_nodes` pixel-fade in, and then stay revealed forever (saved with the game).
##
## Setup: put this script on the room's Area2D (the one on the "areas" layer that Hexy detects), and
## list in `reveal_nodes` the room's sprite plus every object inside it. Each entry can be a single
## sprite or a whole object scene (lamp, chair, NPC...): every Sprite2D / AnimatedSprite2D / TileMap
## underneath it is hidden and revealed together. Objects stay in the YSort node so they still depth-sort
## with Hexy; this list is what ties them to the room.

const REVEAL_SHADER: Shader = preload("res://Assets/Shaders/pixel_reveal.gdshader")

## Defaults to the node's name. Must be unique per room (it's part of the save file).
@export var room_id: StringName = &""
## Rooms Hexy starts in (or that are always visible) don't need hiding.
@export var start_revealed: bool = false
@export_range(0.0, 5.0, 0.05) var fade_time: float = 0.7
## 1 = fade in single pixels, 2 = chunky 2x2 blocks, etc.
@export_range(1, 8) var pixel_block_size: int = 1
@export var reveal_nodes: Array[NodePath] = []

var is_revealed: bool = false

var _items: Array[CanvasItem] = []
var _original_materials: Dictionary = {} # CanvasItem -> the material it had before we hid it
var _fade_material: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	if room_id == &"":
		room_id = name
	add_to_group(SaveManager.GROUP)
	for path in reveal_nodes:
		var root := get_node_or_null(path)
		if root == null:
			push_warning("Room '%s': reveal node '%s' not found" % [room_id, path])
		else:
			_collect_visuals(root)
	if start_revealed:
		is_revealed = true
	else:
		_hide()


## Hexy calls this on walking into the area.
func on_player_entered(_player: Node) -> void:
	reveal()


func reveal(animate: bool = true) -> void:
	if is_revealed:
		return
	is_revealed = true
	if animate:
		SignalController.room_revealed.emit(room_id) # SaveManager autosaves on this
	if not animate or fade_time <= 0.0 or _fade_material == null:
		_restore_materials()
		return
	_kill_tween()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_reveal, 0.0, 1.0, fade_time)
	# Once fully visible, go back to the normal material: no per-pixel work for the rest of the game.
	_tween.finished.connect(_restore_materials)


func _set_reveal(amount: float) -> void:
	if _fade_material:
		_fade_material.set_shader_parameter("reveal", amount)


func _collect_visuals(node: Node) -> void:
	if (node is Sprite2D or node is AnimatedSprite2D or node is TileMap) and not _items.has(node):
		_items.append(node as CanvasItem)
	for child in node.get_children():
		_collect_visuals(child)


# One material per room, so rooms fade independently. Shared by all of the room's sprites.
func _hide() -> void:
	_kill_tween()
	if _fade_material == null:
		_fade_material = ShaderMaterial.new()
		_fade_material.shader = REVEAL_SHADER
		_fade_material.set_shader_parameter("block_size", float(pixel_block_size))
	_fade_material.set_shader_parameter("reveal", 0.0)
	for item in _items:
		if not is_instance_valid(item):
			continue
		if not _original_materials.has(item):
			_original_materials[item] = item.material
		item.material = _fade_material


func _restore_materials() -> void:
	for item in _original_materials:
		if is_instance_valid(item):
			item.material = _original_materials[item]
	_original_materials.clear()
	_fade_material = null


func _kill_tween() -> void:
	if _tween:
		_tween.kill()
		_tween = null


# --- Save / load (see SaveManager) ---

func get_save_id() -> String:
	return "room:%s" % room_id


func save_state() -> Dictionary:
	return {"revealed": is_revealed}


func load_state(data: Dictionary) -> void:
	_kill_tween()
	if data.get("revealed", false):
		is_revealed = true
		_restore_materials() # instantly visible, no fade
	else:
		is_revealed = false
		_hide()
