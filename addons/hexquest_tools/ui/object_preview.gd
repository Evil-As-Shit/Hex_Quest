@tool
extends Control
## Draws the object the way the builder will make it: the sprite, its origin (the feet), the
## "blocks movement" box (blue) and the "press E here" area (green). Everything is in game pixels, zoomed.

var texture: Texture2D
var region: Rect2 = Rect2(0, 0, 16, 16)
var feet_origin: bool = true
var blocks: bool = true
var collision_size: Vector2 = Vector2(8, 6)
var interact_size: Vector2 = Vector2.ZERO
var interact_offset: Vector2 = Vector2.ZERO
var zoom: int = 6


func refresh() -> void:
	# Work out how much room we need around the origin.
	var sprite_rect := _sprite_rect()
	var parts: Array[Rect2] = [sprite_rect]
	if blocks:
		parts.append(_collision_rect())
	if interact_size.x > 0:
		parts.append(_interact_rect())
	var bounds := parts[0]
	for p in parts:
		bounds = bounds.merge(p)
	var margin := 12
	custom_minimum_size = bounds.size * zoom + Vector2(margin * 2, margin * 2)
	queue_redraw()


func _sprite_rect() -> Rect2:
	if feet_origin:
		return Rect2(Vector2(-region.size.x / 2.0, -region.size.y), region.size)
	return Rect2(-region.size / 2.0, region.size)


func _collision_rect() -> Rect2:
	var c := Vector2(0, -collision_size.y / 2.0) if feet_origin else Vector2.ZERO
	return Rect2(c - collision_size / 2.0, collision_size)


func _interact_rect() -> Rect2:
	return Rect2(interact_offset - interact_size / 2.0, interact_size)


func _draw() -> void:
	var margin := 12.0
	# merge the same bounds as refresh() to find where the origin sits inside the control
	var bounds := _sprite_rect()
	if blocks:
		bounds = bounds.merge(_collision_rect())
	if interact_size.x > 0:
		bounds = bounds.merge(_interact_rect())
	var origin := Vector2(margin, margin) + (-bounds.position) * zoom
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.2, 0.24))
	if texture:
		var s := _sprite_rect()
		draw_texture_rect_region(texture, Rect2(origin + s.position * zoom, s.size * zoom), region)
	if interact_size.x > 0:
		var i := _interact_rect()
		var r := Rect2(origin + i.position * zoom, i.size * zoom)
		draw_rect(r, Color(0.3, 1, 0.4, 0.18))
		draw_rect(r, Color(0.3, 1, 0.4, 0.9), false, 2.0)
	if blocks:
		var c := _collision_rect()
		var r2 := Rect2(origin + c.position * zoom, c.size * zoom)
		draw_rect(r2, Color(0.3, 0.6, 1, 0.3))
		draw_rect(r2, Color(0.3, 0.6, 1, 1), false, 2.0)
	draw_line(origin + Vector2(-6, 0), origin + Vector2(6, 0), Color.RED, 2.0)
	draw_line(origin + Vector2(0, -6), origin + Vector2(0, 6), Color.RED, 2.0)
