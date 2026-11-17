@tool
extends ConfirmationDialog
## "Quick conversation": type what is said, one box per line, and it creates the whole chain of
## linked dialogue lines (each continues to the next, the last one ends the conversation).

const Ctx := preload("res://addons/hexquest_tools/hq_context.gd")
const DialogueDB := preload("res://addons/hexquest_tools/core/dialogue_db.gd")

## Emitted after the lines have been created and saved. `ids` is the new chain, first to last.
signal created(ids: PackedStringArray)

var _prefix: LineEdit
var _requires: LineEdit
var _adds: LineEdit
var _portrait: OptionButton
var _script: TextEdit
var _summary: Label


func _init() -> void:
	title = "Quick conversation"
	min_size = Vector2i(620, 520)
	ok_button_text = "Create lines"
	var box := VBoxContainer.new()
	add_child(box)

	var help := Ctx.label("One line of text = one dialogue box. Start a line with [portrait_name] to change the portrait\nfor that line (e.g. [witch_happy] Hello!). Lines starting with # are ignored.", true)
	box.add_child(help)

	var script_box := TextEdit.new()
	script_box.custom_minimum_size = Vector2(0, 200)
	script_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	script_box.placeholder_text = "[witch_happy] Hello there!\nHow are you doing today?\n[witch_stare] ...Never mind."
	script_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	script_box.text_changed.connect(_update_summary)
	box.add_child(script_box)
	_script = script_box

	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	grid.add_child(Ctx.label("Id prefix"))
	_prefix = Ctx.line_edit("NPC")
	_prefix.text_changed.connect(func(_t): _update_summary())
	grid.add_child(_prefix)
	grid.add_child(Ctx.label("Default portrait"))
	_portrait = OptionButton.new()
	grid.add_child(_portrait)
	grid.add_child(Ctx.label("Only shows if tag"))
	_requires = Ctx.line_edit("(optional) first line needs this tag")
	grid.add_child(_requires)
	grid.add_child(Ctx.label("Sets tag at the end"))
	_adds = Ctx.line_edit("(optional) set when the conversation finishes")
	grid.add_child(_adds)

	_summary = Ctx.label("")
	box.add_child(_summary)
	confirmed.connect(_create)


func popup_for(prefix: String = "NPC", default_portrait: String = "") -> void:
	_prefix.text = prefix
	_script.text = ""
	_requires.text = ""
	_adds.text = ""
	_portrait.clear()
	_portrait.add_item("(none)")
	var names := Ctx.portrait_names()
	for n in names:
		_portrait.add_item(n)
	var idx := names.find(default_portrait)
	_portrait.select(idx + 1 if idx >= 0 else 0)
	_update_summary()
	popup_centered()
	_script.grab_focus()


func _update_summary() -> void:
	var lines := DialogueDB.parse_script(_script.text)
	var prefix := _prefix.text.strip_edges()
	var ok_btn := get_ok_button()
	if lines.is_empty() or prefix == "":
		_summary.text = "Type at least one line."
		ok_btn.disabled = true
		return
	var db := Ctx.get_db()
	var first := db.next_id(prefix)
	var number := first.substr(prefix.length()).to_int()
	var last := "%s%0*d" % [prefix, first.length() - prefix.length(), number + lines.size() - 1]
	_summary.text = "Will create %d line%s: %s%s" % [lines.size(), "" if lines.size() == 1 else "s", first, "" if lines.size() == 1 else " … " + last]
	ok_btn.disabled = false


func _create() -> void:
	var db := Ctx.get_db()
	var lines := DialogueDB.parse_script(_script.text)
	var portrait: Variant = null if _portrait.selected <= 0 else _portrait.get_item_text(_portrait.selected)
	var ids := db.create_conversation(lines, _prefix.text.strip_edges(), _requires.text.strip_edges(), _adds.text.strip_edges(), portrait)
	if not ids.is_empty():
		db.save_file() # scenes will point at these, so don't leave them only in memory
		created.emit(ids)
