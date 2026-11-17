@tool
extends Control
## Shows a spritesheet; drag to select the part of it you want. Snaps to a grid (set grid = 1 for
## pixel-exact). `rect` is in texture pixels. A second, dimmer rectangle can be shown (e.g. a lamp's "on" look).

signal rect_changed(rect: Rect2)

var texture: Texture2D : set = set_texture
var zoom: int = 3 : set = set_zoom
var grid: int = 16 : set = set_grid
var rect: Rect2 = Rect2() : set = set_rect
var other_rect: Rect2 = Rect2() : set = set_other_rect
var _drag_from := Vector2i(-1, -1)


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_CROSS


func set_texture(t: Texture2D) -> void:
	texture = t
	_resize()


func set_zoom(z: int) -> void:
	zoom = maxi(1, z)
	_resize()


func set_grid(g: int) -> void:
	grid = maxi(1, g)
	queue_redraw()


func set_rect(r: Rect2) -> void:
	rect = r
	queue_redraw()


func set_other_rect(r: Rect2) -> void:
	other_rect = r
	queue_redraw()


func _resize() -> void:
	custom_minimum_size = (texture.get_size() * zoom) if texture else Vector2(64, 64)
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	var size_px := texture.get_size() * zoom
	# a checkerboard so transparent pixels are visible
	var tile := 8
	for y in range(0, int(size_px.y), tile):
		for x in range(0, int(size_px.x), tile):
			var c := Color(0.22, 0.22, 0.25) if ((x / tile + y / tile) % 2 == 0) else Color(0.28, 0.28, 0.32)
			draw_rect(Rect2(x, y, mini(tile, int(size_px.x) - x), mini(tile, int(size_px.y) - y)), c)
	draw_texture_rect(texture, Rect2(Vector2.ZERO, size_px), false)
	if grid * zoom >= 6:
		var line := Color(1, 1, 1, 0.12)
		for x in range(0, int(texture.get_width()) + 1, grid):
			draw_line(Vector2(x * zoom, 0), Vector2(x * zoom, size_px.y), line)
		for y in range(0, int(texture.get_height()) + 1, grid):
			draw_line(Vector2(0, y * zoom), Vector2(size_px.x, y * zoom), line)
	if other_rect.size.x > 0:
		var o := Rect2(other_rect.position * zoom, other_rect.size * zoom)
		draw_rect(o, Color(0.3, 0.8, 1.0, 0.18))
		draw_rect(o, Color(0.3, 0.8, 1.0, 0.9), false, 2.0)
	if rect.size.x > 0:
		var r := Rect2(rect.position * zoom, rect.size * zoom)
		draw_rect(r, Color(1, 0.85, 0.2, 0.2))
		draw_rect(r, Color(1, 0.85, 0.2, 1.0), false, 2.0)


func _gui_input(event: InputEvent) -> void:
	if texture == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_from = _cell_at(event.position)
			_apply(_drag_from, _drag_from)
		else:
			_drag_from = Vector2i(-1, -1)
	elif event is InputEventMouseMotion and _drag_from.x >= 0 and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_apply(_drag_from, _cell_at(event.position))


func _cell_at(pos: Vector2) -> Vector2i:
	var tex_pos := pos / float(zoom)
	var max_cell := Vector2i(int(texture.get_width()) / grid - 1, int(texture.get_height()) / grid - 1)
	return Vector2i(clampi(int(floor(tex_pos.x / grid)), 0, max_cell.x), clampi(int(floor(tex_pos.y / grid)), 0, max_cell.y))


func _apply(a: Vector2i, b: Vector2i) -> void:
	var top_left := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var bottom_right := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y)) + Vector2i.ONE
	rect = Rect2(Vector2(top_left) * grid, Vector2(bottom_right - top_left) * grid)
	queue_redraw()
	rect_changed.emit(rect)
