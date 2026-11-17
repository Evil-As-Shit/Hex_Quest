@tool
extends RefCounted
## Measures whether a line of text fits in the in-game dialogue box, using the same width/height
## constants as DialogueBox.gd and the game's default theme font. It's an estimate, but a good one.

const Config := preload("res://addons/hexquest_tools/hq_config.gd")

static var _theme_label: Label # only used to look up the game's default font / size / line spacing
static var _constants: Dictionary = {}


## {"lines": int, "needed": float, "available": float, "overflow": bool}
## Uses the font API directly (a Label only wraps correctly a frame after it enters the tree).
static func measure(text: String, has_portrait: bool) -> Dictionary:
	var box: Vector2 = _box_size(has_portrait)
	if _theme_label == null:
		_theme_label = Label.new()
	var font := _theme_label.get_theme_font("font")
	var font_size := _theme_label.get_theme_font_size("font_size")
	var spacing := _theme_label.get_theme_constant("line_spacing")
	var wrapped := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, box.x, font_size, -1,
			TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	var line_height := font.get_height(font_size)
	var lines := maxi(1, int(round(wrapped.y / line_height)))
	var needed := lines * line_height + (lines - 1) * spacing
	return {"lines": lines, "needed": needed, "available": box.y, "overflow": needed > box.y + 0.5}


static func _box_size(has_portrait: bool) -> Vector2:
	if _constants.is_empty():
		var script := load(Config.DIALOGUE_BOX_SCRIPT) as GDScript
		if script:
			_constants = script.get_script_constant_map()
	var key := "LABEL_SIZE_PORTRAIT" if has_portrait else "LABEL_SIZE_FULL"
	return _constants.get(key, Vector2(305, 90) if has_portrait else Vector2(400, 90))
