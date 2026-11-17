@tool
extends VBoxContainer
## An ordered list of dialogue ids: reorder, remove, jump to the line, add existing lines or create a
## new conversation. Used for an object's dialogue_ids, for question branches, and in the inspector.
##
## The game shows the FIRST line in the list whose tag requirement is met, so the order matters.

const Ctx := preload("res://addons/hexquest_tools/hq_context.gd")
const Picker := preload("res://addons/hexquest_tools/ui/dialogue_picker.gd")
const ConversationDialog := preload("res://addons/hexquest_tools/ui/conversation_dialog.gd")

signal changed(ids: Array)

var ids: Array = []
var default_prefix: String = "NPC"
var show_hint: bool = true

var _rows: VBoxContainer
var _hint: Label
var _picker: ConfirmationDialog
var _conversation: ConfirmationDialog


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint = Ctx.label("The first line whose tag requirement is met is the one shown, so put conditional lines first and a plain fallback last.", true)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(200, 0)
	add_child(_hint)
	_rows = VBoxContainer.new()
	add_child(_rows)
	var bar := HBoxContainer.new()
	add_child(bar)
	var add_existing := Ctx.button("＋ Existing line…", "Pick a line that already exists")
	add_existing.pressed.connect(func(): _picker.popup_picker())
	bar.add_child(add_existing)
	var add_new := Ctx.button("＋ New conversation…", "Write new lines and add them here")
	add_new.pressed.connect(_on_new)
	bar.add_child(add_new)
	_picker = Picker.new()
	_picker.picked.connect(func(id: String): _apply_ids(ids + [id]))
	add_child(_picker)
	_conversation = ConversationDialog.new()
	_conversation.created.connect(func(new_ids: PackedStringArray): _apply_ids(ids + Array(new_ids)))
	add_child(_conversation)


func set_ids(new_ids: Array) -> void:
	ids = new_ids.duplicate()
	_rebuild()


func _apply_ids(new_ids: Array) -> void:
	ids = new_ids
	_rebuild()
	changed.emit(ids.duplicate())


func _on_new() -> void:
	var prefix := default_prefix
	if not ids.is_empty():
		var p := Ctx.DialogueDB.prefix_of(str(ids[0]))
		if p != "":
			prefix = p
	_conversation.popup_for(prefix)


func _rebuild() -> void:
	_hint.visible = show_hint
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var db := Ctx.get_db()
	for i in ids.size():
		var id := str(ids[i])
		var row := HBoxContainer.new()
		var text := Ctx.label(db.label_for(id, 44))
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.clip_text = true
		text.custom_minimum_size = Vector2(120, 0)
		text.tooltip_text = db.label_for(id, 400)
		if not db.has_id(id):
			text.modulate = Color(1, 0.4, 0.4)
		row.add_child(text)
		var req := str(db.get_entry(id).get("tagRequired", ""))
		if req != "":
			var tag := Ctx.label("needs " + req, true)
			tag.tooltip_text = "Only shown once the tag '%s' has been set" % req
			row.add_child(tag)
		var edit := Ctx.button("Edit", "Open this line in the Dialogue tab")
		edit.disabled = not db.has_id(id)
		edit.pressed.connect(Ctx.open_dialogue.bind(id))
		row.add_child(edit)
		var up := Ctx.button("▲")
		up.disabled = i == 0
		up.pressed.connect(_move.bind(i, -1))
		row.add_child(up)
		var down := Ctx.button("▼")
		down.disabled = i == ids.size() - 1
		down.pressed.connect(_move.bind(i, 1))
		row.add_child(down)
		var remove := Ctx.button("✕", "Remove from this list (the line itself is kept)")
		remove.pressed.connect(_remove.bind(i))
		row.add_child(remove)
		_rows.add_child(row)


func _move(index: int, delta: int) -> void:
	var copy := ids.duplicate()
	var item = copy[index]
	copy.remove_at(index)
	copy.insert(index + delta, item)
	_apply_ids(copy)


func _remove(index: int) -> void:
	var copy := ids.duplicate()
	copy.remove_at(index)
	_apply_ids(copy)
