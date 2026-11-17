@tool
extends EditorProperty
## Replaces the plain array editor for `dialogue_ids` in the Inspector with the HexQuest list editor.

const IdList := preload("res://addons/hexquest_tools/ui/id_list_editor.gd")

var _list: Control
var _updating: bool = false


func _init() -> void:
	_list = IdList.new()
	_list.show_hint = false # the Inspector is narrow; the order rule is explained in the tooltip below
	tooltip_text = "The game shows the FIRST line in this list whose tag requirement is met.\nPut conditional lines first and a plain fallback last."
	add_child(_list)
	set_bottom_editor(_list)
	_list.changed.connect(_on_changed)


func _update_property() -> void:
	var value: Variant = get_edited_object().get(get_edited_property())
	_updating = true
	_list.set_ids(value if value is Array else [])
	_updating = false


func _on_changed(ids: Array) -> void:
	if _updating:
		return
	var typed: Array[String] = []
	for id in ids:
		typed.append(str(id))
	emit_changed(get_edited_property(), typed)
