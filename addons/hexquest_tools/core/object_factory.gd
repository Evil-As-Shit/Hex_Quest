@tool
extends RefCounted
## Builds object and room scenes with exactly the structure the game expects:
##   StaticBody2D (script) > sprite + CollisionShape2D + Area2D "Object_Id" > CollisionShape2D
## "Object_Id" is how Hexy finds things to interact with; Lamp.gd needs its sprite named "Lamp_Sprite".

const Config := preload("res://addons/hexquest_tools/hq_config.gd")

enum Type {NPC, SEAT, LAMP, PROP}
const TYPE_NAMES := ["NPC / talkable object", "Seat (Hexy sits on it)", "Lamp / on-off toggle", "Prop (decoration only)"]


## Sensible starting sizes per type, relative to the object's feet (origin = bottom centre).
static func defaults_for(type: int) -> Dictionary:
	match type:
		Type.NPC:
			return {"blocks": true, "collision_size": Vector2(7, 6), "interact_size": Vector2(21, 14)}
		Type.SEAT:
			return {"blocks": true, "collision_size": Vector2(8, 6), "interact_size": Vector2(14, 14)}
		Type.LAMP:
			return {"blocks": true, "collision_size": Vector2(3, 7), "interact_size": Vector2(11, 21)}
	return {"blocks": true, "collision_size": Vector2(8, 6), "interact_size": Vector2.ZERO}


static func sanitize_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		out += ch if (ch.is_valid_identifier() or ch.is_valid_int() or ch == "_") else "_"
	return out if out != "" else "NewObject"


## spec: {type, name, texture (path), region: Rect2, region_on: Rect2 (lamp only), origin: "feet"|"center",
##        blocks: bool, collision_size: Vector2, interact_size: Vector2, interact_offset: Vector2,
##        dialogue_ids: Array}
static func build_object(spec: Dictionary) -> StaticBody2D:
	var type: int = spec.get("type", Type.NPC)
	var texture := load(spec["texture"]) as Texture2D
	var region: Rect2 = spec["region"]
	var feet: bool = spec.get("origin", "feet") == "feet"

	var root := StaticBody2D.new()
	root.name = sanitize_name(spec.get("name", "NewObject"))
	root.collision_layer = Config.LAYER_OBJECTS
	root.collision_mask = 0
	match type:
		Type.NPC:
			root.set_script(load(Config.NPC_SCRIPT))
		Type.SEAT:
			root.set_script(load(Config.CHAIR_SCRIPT))
		Type.LAMP:
			root.set_script(load(Config.LAMP_SCRIPT))

	if type == Type.LAMP:
		var sprite := AnimatedSprite2D.new()
		sprite.name = "Lamp_Sprite" # Lamp.gd looks for exactly this name
		var frames := SpriteFrames.new()
		frames.remove_animation(&"default")
		var on_region: Rect2 = spec.get("region_on", region)
		for pair in [[&"off", region], [&"on", on_region]]:
			frames.add_animation(pair[0])
			frames.set_animation_loop(pair[0], false)
			frames.set_animation_speed(pair[0], 5.0)
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = pair[1]
			frames.add_frame(pair[0], atlas)
		sprite.sprite_frames = frames
		sprite.animation = &"off"
		sprite.offset = Vector2(0, -region.size.y / 2.0) if feet else Vector2.ZERO
		root.add_child(sprite)
	else:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		sprite.region_enabled = true
		sprite.region_rect = region
		if feet:
			sprite.centered = false
			sprite.position = Vector2(-region.size.x / 2.0, -region.size.y)
		root.add_child(sprite)

	var csize: Vector2 = spec.get("collision_size", Vector2(8, 6))
	if spec.get("blocks", true) and csize.x > 0 and csize.y > 0:
		var collision := CollisionShape2D.new()
		collision.name = "Collision"
		var shape := RectangleShape2D.new()
		shape.size = csize
		collision.shape = shape
		collision.position = Vector2(0, -csize.y / 2.0) if feet else Vector2.ZERO
		root.add_child(collision)

	var isize: Vector2 = spec.get("interact_size", Vector2.ZERO)
	if type != Type.PROP and isize.x > 0 and isize.y > 0:
		var area := Area2D.new()
		area.name = "Object_Id" # Hexy.interact_nearby() looks for this area
		area.collision_layer = Config.LAYER_OBJECTS
		area.collision_mask = 0
		area.monitoring = false
		area.position = spec.get("interact_offset", Vector2(0, -csize.y / 2.0))
		var area_shape := CollisionShape2D.new()
		area_shape.name = "Interact_Area"
		var rect := RectangleShape2D.new()
		rect.size = isize
		area_shape.shape = rect
		area.add_child(area_shape)
		root.add_child(area)

	if type == Type.NPC:
		var ids: Array[String] = []
		for id in spec.get("dialogue_ids", []):
			ids.append(str(id))
		root.set("dialogue_ids", ids)

	_set_owner_recursive(root, root)
	return root


## A room scaffold like your Room1: walls body + sprite, and a Room.gd area to reveal it.
## spec: {name, texture (path), region: Rect2, start_revealed: bool}
static func build_room(spec: Dictionary) -> StaticBody2D:
	var room_name := sanitize_name(spec.get("name", "NewRoom"))
	var region: Rect2 = spec["region"]
	var half := region.size / 2.0

	var root := StaticBody2D.new()
	root.name = room_name
	root.collision_layer = Config.LAYER_WALLS
	root.collision_mask = 0

	var sprite := Sprite2D.new()
	sprite.name = room_name + "_Sprite"
	sprite.texture = load(spec["texture"]) as Texture2D
	sprite.region_enabled = true
	sprite.region_rect = region
	root.add_child(sprite)

	var walls := CollisionPolygon2D.new() # starter back wall: reshape it to your room
	walls.name = room_name + "_Collision"
	walls.polygon = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, -half.y + 4), Vector2(-half.x, -half.y + 4)])
	root.add_child(walls)

	var area := Area2D.new()
	area.name = room_name
	area.collision_layer = Config.LAYER_AREAS
	area.collision_mask = 0
	area.monitoring = false
	area.set_script(load(Config.ROOM_SCRIPT))
	area.set("room_id", StringName(room_name))
	area.set("start_revealed", spec.get("start_revealed", false))
	root.add_child(area)

	var floor_poly := CollisionPolygon2D.new() # starter floor area: reshape it to your room
	floor_poly.name = room_name + "_Area"
	floor_poly.polygon = PackedVector2Array([Vector2(-half.x, 0), Vector2(half.x, 0), Vector2(half.x, half.y), Vector2(-half.x, half.y)])
	area.add_child(floor_poly)

	_set_owner_recursive(root, root)
	return root


static func save_scene(root: Node, path: String) -> int:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		return err
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return ResourceSaver.save(packed, path)


## "Grandma" in a folder -> res://Scenes/Objects/Grandma.tscn, or Grandma2.tscn if that exists.
static func unique_scene_path(dir: String, scene_name: String) -> String:
	var base := dir.path_join(sanitize_name(scene_name))
	var path := base + ".tscn"
	var n := 2
	while FileAccess.file_exists(path):
		path = "%s%d.tscn" % [base, n]
		n += 1
	return path


static func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive(child, owner)
