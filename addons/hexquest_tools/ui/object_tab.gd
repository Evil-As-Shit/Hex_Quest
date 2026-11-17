@tool
extends HSplitContainer
## Builds new objects, NPCs, seats, lamps, props and rooms: pick the sprite visually, tune the
## collision and interaction areas against a live preview, attach dialogue, and (optionally) drop the
## result straight into the open scene, already assigned to a room.

const Ctx := preload("res://addons/hexquest_tools/hq_context.gd")
const Config := preload("res://addons/hexquest_tools/hq_config.gd")
const Factory := preload("res://addons/hexquest_tools/core/object_factory.gd")
const SceneTools := preload("res://addons/hexquest_tools/core/scene_tools.gd")
const RegionPicker := preload("res://addons/hexquest_tools/ui/region_picker.gd")
const ObjectPreview := preload("res://addons/hexquest_tools/ui/object_preview.gd")
const IdList := preload("res://addons/hexquest_tools/ui/id_list_editor.gd")

const ROOM_TYPE := 4 # after the four object types in Factory.Type

var _region: Rect2 = Rect2(0, 0, 16, 16)
var _region_on: Rect2 = Rect2()
var _picking_on: bool = false
var _building: bool = false

var _type: OptionButton
var _name: LineEdit
var _sheet: OptionButton
var _zoom: OptionButton
var _grid: SpinBox
var _picker: Control
var _preview: Control
var _rx: SpinBox
var _ry: SpinBox
var _rw: SpinBox
var _rh: SpinBox
var _pick_box: HBoxContainer
var _pick_off: Button
var _pick_on: Button
var _origin: OptionButton
var _shape_box: VBoxContainer
var _blocks: CheckBox
var _cw: SpinBox
var _ch: SpinBox
var _iw: SpinBox
var _ih: SpinBox
var _iy: SpinBox
var _dialogue_box: VBoxContainer
var _ids: Control
var _room_box: VBoxContainer
var _start_revealed: CheckBox
var _place: CheckBox
var _room_pick: OptionButton
var _create: Button
var _status: Label


func _init() -> void:
	name = "Objects"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_form()
	_build_sheet_side()
	visibility_changed.connect(func(): if visible: refresh())


func _ready() -> void:
	# Don't load the spritesheets yet: on a fresh clone the editor starts plugins before the first image
	# import has finished. They're loaded when the tab is first shown (visibility_changed -> refresh).
	_on_type_changed(0)


func refresh() -> void:
	_fill_sheets()
	_fill_rooms()


# ============ layout ============

func _spin(min_v: float, max_v: float, value: float, step: float = 1.0) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.value_changed.connect(func(_v): _on_param_changed())
	return s


func _row(label: String, a: Control, b: Control = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Ctx.label(label)
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(a)
	if b:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	return row


func _build_form() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)

	_type = OptionButton.new()
	for n in Factory.TYPE_NAMES:
		_type.add_item(n)
	_type.add_item("Room (hidden until entered)")
	_type.item_selected.connect(_on_type_changed)
	form.add_child(_row("What to make", _type))
	_name = Ctx.line_edit("e.g. Grandma")
	_name.text_changed.connect(func(_t): _update_status_path())
	form.add_child(_row("Name", _name))

	form.add_child(HSeparator.new())
	form.add_child(Ctx.label("Sprite: pick a sheet on the right, drag to select the art", true))
	var rr := HBoxContainer.new()
	form.add_child(rr)
	_rx = _spin(0, 8192, 0)
	_ry = _spin(0, 8192, 0)
	_rw = _spin(1, 4096, 16)
	_rh = _spin(1, 4096, 16)
	for pair in [["x", _rx], ["y", _ry], ["w", _rw], ["h", _rh]]:
		rr.add_child(Ctx.label(pair[0]))
		rr.add_child(pair[1])
	_pick_box = HBoxContainer.new()
	form.add_child(_pick_box)
	_pick_box.add_child(Ctx.label("Selecting the"))
	_pick_off = Ctx.button("Off look")
	_pick_off.toggle_mode = true
	_pick_off.button_pressed = true
	_pick_off.pressed.connect(func(): _set_picking(false))
	_pick_box.add_child(_pick_off)
	_pick_on = Ctx.button("On look")
	_pick_on.toggle_mode = true
	_pick_on.pressed.connect(func(): _set_picking(true))
	_pick_box.add_child(_pick_on)
	_origin = OptionButton.new()
	_origin.add_item("Feet (bottom centre)")
	_origin.add_item("Centre")
	_origin.tooltip_text = "Where the object's position is. Feet is right for anything that stands on the floor (it sorts correctly against Hexy)."
	_origin.item_selected.connect(func(_i): _on_param_changed())
	form.add_child(_row("Position is at", _origin))

	_shape_box = VBoxContainer.new()
	form.add_child(_shape_box)
	_shape_box.add_child(HSeparator.new())
	_blocks = CheckBox.new()
	_blocks.text = "Blocks movement (Hexy can't walk through)"
	_blocks.button_pressed = true
	_blocks.toggled.connect(func(_b): _on_param_changed())
	_shape_box.add_child(_blocks)
	_cw = _spin(1, 512, 7)
	_ch = _spin(1, 512, 6)
	_shape_box.add_child(_row("Solid size  w × h", _cw, _ch))
	_iw = _spin(0, 512, 21)
	_ih = _spin(0, 512, 14)
	_iy = _spin(-512, 512, -3, 0.5)
	_shape_box.add_child(_row("Press-E area  w × h", _iw, _ih))
	_shape_box.add_child(_row("Press-E area  y", _iy))

	_dialogue_box = VBoxContainer.new()
	form.add_child(_dialogue_box)
	_dialogue_box.add_child(HSeparator.new())
	_dialogue_box.add_child(Ctx.label("What it says (dialogue_ids)"))
	_ids = IdList.new()
	_dialogue_box.add_child(_ids)

	_room_box = VBoxContainer.new()
	form.add_child(_room_box)
	_room_box.add_child(HSeparator.new())
	_start_revealed = CheckBox.new()
	_start_revealed.text = "Visible from the start (like the balcony)"
	_room_box.add_child(_start_revealed)
	_room_box.add_child(Ctx.label("Rooms are hidden until Hexy walks into them. After creating, reshape the two polygons (walls and floor area) in the 2D editor.", true))

	form.add_child(HSeparator.new())
	_place = CheckBox.new()
	_place.text = "Also place it in the open scene"
	_place.button_pressed = true
	form.add_child(_place)
	_room_pick = OptionButton.new()
	form.add_child(_row("Reveal with room", _room_pick))
	_create = Ctx.button("Create")
	_create.pressed.connect(_on_create)
	form.add_child(_create)
	_status = Ctx.label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(_status)


func _build_sheet_side() -> void:
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(side)
	var bar := HBoxContainer.new()
	side.add_child(bar)
	bar.add_child(Ctx.label("Sheet"))
	_sheet = OptionButton.new()
	_sheet.item_selected.connect(func(_i): _load_sheet())
	bar.add_child(_sheet)
	bar.add_child(Ctx.label("Zoom"))
	_zoom = OptionButton.new()
	for z in [1, 2, 3, 4, 6]:
		_zoom.add_item("%d×" % z, z)
	_zoom.select(2)
	_zoom.item_selected.connect(func(i: int): _picker.zoom = _zoom.get_item_id(i))
	bar.add_child(_zoom)
	bar.add_child(Ctx.label("Grid"))
	_grid = SpinBox.new()
	_grid.min_value = 1
	_grid.max_value = 128
	_grid.value = 16
	_grid.tooltip_text = "Selections snap to this many pixels (1 = pixel-exact)"
	_grid.value_changed.connect(func(v: float): _picker.grid = int(v))
	bar.add_child(_grid)

	var vsplit := VSplitContainer.new()
	vsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(vsplit)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 160)
	vsplit.add_child(scroll)
	_picker = RegionPicker.new()
	_picker.rect_changed.connect(func(r: Rect2): _set_region(r))
	scroll.add_child(_picker)

	var lower := VBoxContainer.new()
	lower.custom_minimum_size = Vector2(0, 300) # the preview is the part you tune against, so give it room
	vsplit.add_child(lower)
	lower.add_child(Ctx.label("Preview:  red + = object position,  blue = solid,  green = press-E area", true))
	var pscroll := ScrollContainer.new()
	pscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lower.add_child(pscroll)
	_preview = ObjectPreview.new()
	pscroll.add_child(_preview)


# ============ data ============

func _fill_sheets() -> void:
	var keep: Variant = _sheet.get_item_metadata(_sheet.selected) if _sheet.selected >= 0 else Config.DEFAULT_SPRITESHEET
	_sheet.clear()
	var seen := {}
	for dir in Config.SPRITE_DIRS:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".png"):
				var path: String = dir + f
				if not seen.has(path):
					seen[path] = true
					_sheet.add_item(path.replace("res://Assets/", ""))
					_sheet.set_item_metadata(_sheet.item_count - 1, path)
	for i in _sheet.item_count:
		if _sheet.get_item_metadata(i) == keep:
			_sheet.select(i)
	if _sheet.item_count > 0 and _sheet.selected < 0:
		_sheet.select(0)
	_load_sheet()


func _load_sheet() -> void:
	if _sheet.selected < 0:
		return
	var tex := load(str(_sheet.get_item_metadata(_sheet.selected))) as Texture2D
	_picker.texture = tex
	_preview.texture = tex
	_sync_region_ui()


func _fill_rooms() -> void:
	var keep := _room_pick.get_item_text(_room_pick.selected) if _room_pick.selected >= 0 else ""
	_room_pick.clear()
	_room_pick.add_item("(none: visible from the start)")
	var root := Ctx.scene_root()
	if root:
		for room in SceneTools.find_rooms(root):
			_room_pick.add_item(str(room.name))
			_room_pick.set_item_metadata(_room_pick.item_count - 1, room)
	for i in _room_pick.item_count:
		if _room_pick.get_item_text(i) == keep:
			_room_pick.select(i)


func _set_picking(on: bool) -> void:
	_picking_on = on
	_pick_on.button_pressed = on
	_pick_off.button_pressed = not on
	_set_region(_region_on if on else _region)


func _set_region(r: Rect2) -> void:
	if _picking_on:
		_region_on = r
	else:
		_region = r
	_sync_region_ui()


# Shows whichever region is being edited (off or on look) without changing either.
func _sync_region_ui() -> void:
	var r := _region_on if _picking_on else _region
	_building = true
	_rx.value = r.position.x
	_ry.value = r.position.y
	_rw.value = r.size.x
	_rh.value = r.size.y
	_building = false
	_picker.rect = r
	if _type.selected == Factory.Type.LAMP:
		_picker.other_rect = _region if _picking_on else _region_on
	else:
		_picker.other_rect = Rect2()
	_update_preview()


func _on_param_changed() -> void:
	if _building:
		return
	var r := Rect2(_rx.value, _ry.value, _rw.value, _rh.value)
	if r != (_region_on if _picking_on else _region):
		if _picking_on:
			_region_on = r
		else:
			_region = r
		_picker.rect = r
	_update_preview()


func _on_type_changed(index: int) -> void:
	var is_room := index == ROOM_TYPE
	var is_lamp := index == Factory.Type.LAMP
	_shape_box.visible = not is_room
	_origin.get_parent().visible = not is_room
	_dialogue_box.visible = index == Factory.Type.NPC
	_room_box.visible = is_room
	_pick_box.visible = is_lamp
	_room_pick.get_parent().visible = not is_room
	if is_lamp and _region_on.size.x <= 0:
		_region_on = Rect2(_region.position + Vector2(_region.size.x, 0), _region.size)
	if not is_lamp:
		_set_picking(false)
	_sync_region_ui()
	if not is_room:
		var d := Factory.defaults_for(index)
		_building = true
		_blocks.button_pressed = d["blocks"]
		_cw.value = d["collision_size"].x
		_ch.value = d["collision_size"].y
		_iw.value = d["interact_size"].x
		_ih.value = d["interact_size"].y
		_iy.value = -d["collision_size"].y / 2.0
		_building = false
	_iw.get_parent().visible = index != Factory.Type.PROP
	_ih.get_parent().visible = index != Factory.Type.PROP
	_iy.get_parent().visible = index != Factory.Type.PROP
	_create.text = "Create room" if is_room else "Create " + ["NPC", "seat", "lamp", "prop"][index]
	_update_preview()
	_update_status_path()


func _update_preview() -> void:
	var p: Control = _preview
	p.region = _region
	p.feet_origin = _origin.selected == 0
	p.blocks = _blocks.button_pressed and _type.selected != ROOM_TYPE
	p.collision_size = Vector2(_cw.value, _ch.value)
	var interactive := _type.selected != Factory.Type.PROP and _type.selected != ROOM_TYPE
	p.interact_size = Vector2(_iw.value, _ih.value) if interactive else Vector2.ZERO
	p.interact_offset = Vector2(0, _iy.value) if p.feet_origin else Vector2(0, _iy.value + _ch.value / 2.0)
	p.refresh()


func _update_status_path() -> void:
	if _status.modulate != Color.WHITE:
		return
	var dir := Config.ROOM_SCENE_DIR if _type.selected == ROOM_TYPE else Config.OBJECT_SCENE_DIR
	var nm := Factory.sanitize_name(_name.text) if _name.text.strip_edges() != "" else "…"
	_status.text = "Will be saved as %s%s.tscn" % [dir, nm]


# ============ creating ============

func _fail(msg: String) -> void:
	_status.text = "⚠ " + msg
	_status.modulate = Color(1, 0.5, 0.5)


func _on_create() -> void:
	_status.modulate = Color.WHITE
	var type := _type.selected
	if _name.text.strip_edges() == "":
		_fail("Give it a name first.")
		return
	if _region.size.x <= 0 or _region.size.y <= 0 or _sheet.selected < 0:
		_fail("Select the sprite on the sheet first.")
		return
	var texture_path := str(_sheet.get_item_metadata(_sheet.selected))
	var node: Node
	var scene_path: String
	if type == ROOM_TYPE:
		node = Factory.build_room({"name": _name.text, "texture": texture_path, "region": _region, "start_revealed": _start_revealed.button_pressed})
		scene_path = Factory.unique_scene_path(Config.ROOM_SCENE_DIR, _name.text)
	else:
		var interactive := type != Factory.Type.PROP
		var ids: Array = _ids.ids if type == Factory.Type.NPC else []
		node = Factory.build_object({
			"type": type, "name": _name.text, "texture": texture_path,
			"region": _region, "region_on": _region_on if _region_on.size.x > 0 else _region,
			"origin": "feet" if _origin.selected == 0 else "center",
			"blocks": _blocks.button_pressed,
			"collision_size": Vector2(_cw.value, _ch.value),
			"interact_size": Vector2(_iw.value, _ih.value) if interactive else Vector2.ZERO,
			"interact_offset": Vector2(0, _iy.value) if _origin.selected == 0 else Vector2(0, _iy.value + _ch.value / 2.0),
			"dialogue_ids": ids,
		})
		scene_path = Factory.unique_scene_path(Config.OBJECT_SCENE_DIR, _name.text)
	var err := Factory.save_scene(node, scene_path)
	node.free()
	if err != OK:
		_fail("Couldn't save %s (%s)" % [scene_path, error_string(err)])
		return
	Ctx.rescan_files()
	var msg := "✔ Created " + scene_path
	if type == Factory.Type.NPC and _ids.ids.is_empty():
		msg += "\nIt has no dialogue yet: add lines above, or set dialogue_ids on it later."
	if _place.button_pressed:
		msg += _place_in_scene(scene_path, type)
	_status.text = msg
	_status.modulate = Color(0.6, 1, 0.6)


# Adds the new scene to the open scene (undoable), under YSort, and lists it in the chosen room.
func _place_in_scene(scene_path: String, type: int) -> String:
	var root := Ctx.scene_root()
	if root == null:
		return "\nNo scene is open, so it wasn't placed. Drag it in from the FileSystem dock."
	var inst := (load(scene_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	var parent := SceneTools.ysort_of(root)
	var base := str(inst.name)
	var n := 2
	while parent.has_node(NodePath(str(inst.name))):
		inst.name = "%s%d" % [base, n]
		n += 1
	var pos := Vector2.ZERO
	for sel in Ctx.editor().get_selection().get_selected_nodes():
		if sel is Node2D and sel != parent and not SceneTools.is_room(sel):
			pos = (sel as Node2D).position + Vector2(16, 0)
			break
	inst.position = pos

	var ur := Ctx.undo_redo()
	ur.create_action("Add " + str(inst.name))
	ur.add_do_method(parent, "add_child", inst, true)
	ur.add_do_property(inst, "owner", root)
	ur.add_do_reference(inst)
	ur.add_undo_method(parent, "remove_child", inst)
	var room: Node = _room_pick.get_item_metadata(_room_pick.selected) if (type != ROOM_TYPE and _room_pick.selected > 0) else null
	var assigned := ""
	if room != null and is_instance_valid(room):
		var old := SceneTools.reveal_nodes_of(room)
		var updated := old.duplicate()
		updated.append(NodePath(str(room.get_path_to(parent)) + "/" + str(inst.name)))
		SceneTools.add_make_editable(ur, root, room)
		ur.add_do_property(room, "reveal_nodes", updated)
		ur.add_undo_property(room, "reveal_nodes", old)
		assigned = " and added to %s's reveal list" % room.name
	ur.commit_action()
	var selection := Ctx.editor().get_selection()
	selection.clear()
	selection.add_node(inst)
	return "\n✔ Placed %s in the scene%s. Drag it into position (Ctrl+Z undoes this)." % [inst.name, assigned]
