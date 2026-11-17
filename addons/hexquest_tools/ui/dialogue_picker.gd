@tool
extends ConfirmationDialog
## Pick an existing dialogue line from a searchable list.

const Ctx := preload("res://addons/hexquest_tools/hq_context.gd")

signal picked(id: String)

var _filter: LineEdit
var _list: ItemList


func _init() -> void:
	title = "Pick a dialogue line"
	min_size = Vector2i(560, 440)
	ok_button_text = "Pick"
	var box := VBoxContainer.new()
	add_child(box)
	_filter = Ctx.line_edit("Search by id, text or tag…")
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_t): _fill())
	box.add_child(_filter)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(_i): _accept())
	box.add_child(_list)
	confirmed.connect(_accept)


func popup_picker() -> void:
	_filter.text = ""
	_fill()
	popup_centered()
	_filter.grab_focus()


func _fill() -> void:
	_list.clear()
	var db := Ctx.get_db()
	var needle := _filter.text.to_lower()
	for e in db.entries:
		var id := str(e.get("id", ""))
		var hay := (id + " " + str(e.get("text", "")) + " " + str(e.get("tagRequired", "")) + " " + str(e.get("tagAdd", ""))).to_lower()
		if needle == "" or hay.contains(needle):
			var suffix := ""
			if str(e.get("tagRequired", "")) != "":
				suffix = "   [needs %s]" % e["tagRequired"]
			var i := _list.add_item(db.label_for(id, 70) + suffix)
			_list.set_item_metadata(i, id)


func _accept() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	picked.emit(str(_list.get_item_metadata(sel[0])))
	hide()
