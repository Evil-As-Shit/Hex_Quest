@tool
extends HSplitContainer
## The dialogue editor: every line in dialogue.txt, with a form to edit it and a live preview.

const Ctx := preload("res://addons/hexquest_tools/hq_context.gd")
const DialogueDB := preload("res://addons/hexquest_tools/core/dialogue_db.gd")
const Metrics := preload("res://addons/hexquest_tools/core/dialogue_metrics.gd")
const Validator := preload("res://addons/hexquest_tools/core/validator.gd")
const Scanner := preload("res://addons/hexquest_tools/core/scene_scanner.gd")
const Picker := preload("res://addons/hexquest_tools/ui/dialogue_picker.gd")
const IdList := preload("res://addons/hexquest_tools/ui/id_list_editor.gd")
const ConversationDialog := preload("res://addons/hexquest_tools/ui/conversation_dialog.gd")

const MODE_LABELS := ["End the conversation", "Continue to another line", "Ask a question (2 choices)", "⚠ Nothing yet (dead end)"]

var db: DialogueDB
var selected_id: String = ""
var _building: bool = false
var _scene_refs: Array = []
var _problems: Array = []

# left side
var _filter: LineEdit
var _list: ItemList
var _prefix: LineEdit
# form
var _form: VBoxContainer
var _id_edit: LineEdit
var _status: Label
var _used_by: HFlowContainer
var _problem_label: Label
var _req_edit: LineEdit
var _text_edit: TextEdit
var _text_info: Label
var _portrait: OptionButton
var _portrait_thumb: TextureRect
var _add_edit: LineEdit
var _mode: OptionButton
var _divert_box: VBoxContainer
var _divert_label: Label
var _choices_box: VBoxContainer
var _choice_label: Array[LineEdit] = []
var _choice_ids: Array = []
var _preview_portrait: TextureRect
var _preview_text: Label
# dialogs
var _picker: ConfirmationDialog
var _conversation: ConfirmationDialog
var _confirm: ConfirmationDialog
var _confirm_action: Callable


func _init() -> void:
	name = "Dialogue"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_left()
	_build_form()
	_build_dialogs()


func _ready() -> void:
	db = Ctx.get_db()
	db.changed.connect(_on_db_changed)
	refresh()


# ============ layout ============

func _build_left() -> void:
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	add_child(left)
	_filter = Ctx.line_edit("Search id, text, tag…")
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_t): _fill_list())
	left.add_child(_filter)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int): _select(str(_list.get_item_metadata(i))))
	left.add_child(_list)
	var new_row := HBoxContainer.new()
	left.add_child(new_row)
	new_row.add_child(Ctx.label("Prefix"))
	_prefix = Ctx.line_edit("NPC")
	_prefix.text = "NPC"
	_prefix.custom_minimum_size = Vector2(60, 0)
	new_row.add_child(_prefix)
	var new_btn := Ctx.button("＋ New line", "Create an empty line with the next free id for this prefix")
	new_btn.pressed.connect(_on_new)
	new_row.add_child(new_btn)
	var row2 := HBoxContainer.new()
	left.add_child(row2)
	var dup := Ctx.button("Duplicate")
	dup.pressed.connect(_on_duplicate)
	row2.add_child(dup)
	var del := Ctx.button("Delete")
	del.pressed.connect(_on_delete)
	row2.add_child(del)
	var conv := Ctx.button("Quick conversation…", "Write several lines at once: they're created and linked for you")
	conv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	conv.pressed.connect(func(): _conversation.popup_for(_prefix.text.strip_edges(), _current_portrait()))
	row2.add_child(conv)


func _build_form() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form)

	# id
	var id_row := HBoxContainer.new()
	_form.add_child(id_row)
	id_row.add_child(Ctx.label("Id"))
	_id_edit = Ctx.line_edit()
	_id_edit.tooltip_text = "Press Enter to rename. Everything that points at this line is updated."
	_id_edit.text_submitted.connect(_on_rename)
	id_row.add_child(_id_edit)
	_status = Ctx.label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form.add_child(_status)
	_used_by = HFlowContainer.new()
	_form.add_child(_used_by)
	_problem_label = Ctx.label("")
	_problem_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problem_label.modulate = Color(1, 0.75, 0.4)
	_form.add_child(_problem_label)

	_form.add_child(HSeparator.new())
	_form.add_child(Ctx.label("Only shown if this tag is set (optional)"))
	_req_edit = _tag_row(func(t: String): _set_field("tagRequired", t))

	_form.add_child(Ctx.label("Text"))
	_text_edit = TextEdit.new()
	_text_edit.custom_minimum_size = Vector2(0, 90)
	_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text_edit.text_changed.connect(_on_text_changed)
	_form.add_child(_text_edit)
	_text_info = Ctx.label("", true)
	_form.add_child(_text_info)

	_form.add_child(Ctx.label("Portrait"))
	var portrait_row := HBoxContainer.new()
	_form.add_child(portrait_row)
	_portrait = OptionButton.new()
	_portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_portrait.item_selected.connect(_on_portrait)
	portrait_row.add_child(_portrait)
	_portrait_thumb = TextureRect.new()
	_portrait_thumb.custom_minimum_size = Vector2(60, 73)
	_portrait_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait_row.add_child(_portrait_thumb)

	_form.add_child(Ctx.label("Sets this tag when the line is shown (optional)"))
	_add_edit = _tag_row(func(t: String): _set_field("tagAdd", t))

	_form.add_child(HSeparator.new())
	_form.add_child(Ctx.label("After this line…"))
	_mode = OptionButton.new()
	for m in MODE_LABELS:
		_mode.add_item(m)
	_mode.item_selected.connect(_on_mode)
	_form.add_child(_mode)

	_divert_box = VBoxContainer.new()
	_form.add_child(_divert_box)
	_divert_label = Ctx.label("")
	_divert_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_divert_box.add_child(_divert_label)
	var divert_buttons := HBoxContainer.new()
	_divert_box.add_child(divert_buttons)
	var pick := Ctx.button("Pick line…")
	pick.pressed.connect(func(): _picker.popup_picker())
	divert_buttons.add_child(pick)
	var next_new := Ctx.button("＋ New next line", "Create a new line and continue to it")
	next_new.pressed.connect(_on_new_next)
	divert_buttons.add_child(next_new)
	var go := Ctx.button("Go to it →")
	go.pressed.connect(func():
		var target := str(_entry().get("divert", ""))
		if db.has_id(target):
			select_id(target))
	divert_buttons.add_child(go)

	_choices_box = VBoxContainer.new()
	_form.add_child(_choices_box)
	for i in 2:
		_choices_box.add_child(Ctx.label("Button %d text" % (i + 1)))
		var le := Ctx.line_edit("Yes" if i == 0 else "No")
		le.text_changed.connect(_on_choice_label.bind(i))
		_choices_box.add_child(le)
		_choice_label.append(le)
		_choices_box.add_child(Ctx.label("Lines shown if button %d is picked" % (i + 1), true))
		var list := IdList.new()
		list.default_prefix = "NPC"
		list.changed.connect(_on_choice_ids.bind(i))
		_choices_box.add_child(list)
		_choice_ids.append(list)

	_form.add_child(HSeparator.new())
	_form.add_child(Ctx.label("Preview (roughly how it looks in game)"))
	var preview := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.17, 0.12, 0.25)
	style.set_content_margin_all(10)
	preview.add_theme_stylebox_override("panel", style)
	_form.add_child(preview)
	var prow := HBoxContainer.new()
	preview.add_child(prow)
	_preview_portrait = TextureRect.new()
	_preview_portrait.custom_minimum_size = Vector2(60, 73)
	_preview_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prow.add_child(_preview_portrait)
	_preview_text = Ctx.label("")
	_preview_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_text.custom_minimum_size = Vector2(240, 80)
	prow.add_child(_preview_text)


func _tag_row(on_change: Callable) -> LineEdit:
	var row := HBoxContainer.new()
	_form.add_child(row)
	var le := Ctx.line_edit("TAG_NAME")
	le.text_changed.connect(func(t: String): if not _building: on_change.call(t.strip_edges()))
	row.add_child(le)
	var menu := MenuButton.new()
	menu.text = "Existing ▾"
	menu.tooltip_text = "Pick a tag that's already used somewhere"
	menu.about_to_popup.connect(func():
		var popup := menu.get_popup()
		popup.clear()
		for t in db.all_tags():
			popup.add_item(t))
	menu.get_popup().index_pressed.connect(func(i: int):
		var tag := menu.get_popup().get_item_text(i)
		le.text = tag
		if not _building:
			on_change.call(tag))
	row.add_child(menu)
	return le


func _build_dialogs() -> void:
	_picker = Picker.new()
	_picker.picked.connect(func(id: String): _set_divert(id))
	add_child(_picker)
	_conversation = ConversationDialog.new()
	_conversation.created.connect(func(ids: PackedStringArray):
		refresh()
		select_id(ids[0]))
	add_child(_conversation)
	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(func(): if _confirm_action.is_valid(): _confirm_action.call())
	add_child(_confirm)


# ============ data -> UI ============

func refresh() -> void:
	db = Ctx.get_db()
	_scene_refs = Scanner.scan_dialogue_refs()
	_problems = Validator.run(db, _scene_refs)
	_fill_list()
	if selected_id != "" and db.has_id(selected_id):
		_select(selected_id)
	else:
		_select("")


func _fill_list() -> void:
	_list.clear()
	var needle := _filter.text.to_lower()
	var bad := {}
	for p in _problems:
		if p["sev"] == Validator.Severity.ERROR and p["id"] != "":
			bad[p["id"]] = true
	for e in db.entries:
		var id := str(e.get("id", ""))
		var hay := (id + " " + str(e.get("text", "")) + " " + str(e.get("tagRequired", "")) + " " + str(e.get("tagAdd", ""))).to_lower()
		if needle != "" and not hay.contains(needle):
			continue
		var i := _list.add_item(db.label_for(id, 40))
		_list.set_item_metadata(i, id)
		if bad.has(id):
			_list.set_item_custom_fg_color(i, Color(1, 0.45, 0.45))
		if id == selected_id:
			_list.select(i)


func select_id(id: String) -> void:
	_filter.text = ""
	_fill_list()
	_select(id)
	for i in _list.item_count:
		if _list.get_item_metadata(i) == id:
			_list.select(i)
			_list.ensure_current_is_visible()


func _entry() -> Dictionary:
	return db.get_entry(selected_id)


func _current_portrait() -> String:
	var e := _entry()
	return str(e.get("expression", "")) if e.get("expression") != null else ""


func _select(id: String) -> void:
	selected_id = id
	_form.get_parent().visible = id != ""
	if id == "":
		return
	var e := _entry()
	if e.is_empty():
		return
	_building = true
	_id_edit.text = id
	_status.text = ""
	_req_edit.text = str(e.get("tagRequired", ""))
	_text_edit.text = str(e.get("text", ""))
	_add_edit.text = str(e.get("tagAdd", ""))
	_fill_portraits(e)
	var kind := DialogueDB.kind_of(e)
	_mode.select({DialogueDB.Kind.END: 0, DialogueDB.Kind.DIVERT: 1, DialogueDB.Kind.CHOICES: 2, DialogueDB.Kind.NONE: 3}[kind])
	_divert_box.visible = kind == DialogueDB.Kind.DIVERT
	_choices_box.visible = kind == DialogueDB.Kind.CHOICES
	_show_divert(e)
	if kind == DialogueDB.Kind.CHOICES:
		var labels: Array = e.get("choices", ["", ""])
		for i in 2:
			_choice_label[i].text = str(labels[i]) if i < labels.size() else ""
			_choice_ids[i].set_ids(e.get("choice_%d" % i, []))
	_building = false
	_refresh_info()
	_refresh_used_by()


func _fill_portraits(e: Dictionary) -> void:
	_portrait.clear()
	_portrait.add_item("(none)")
	var names := Ctx.portrait_names()
	for n in names:
		_portrait.add_item(n)
	var current := _current_portrait()
	if current == "" or current == "null":
		_portrait.select(0)
	else:
		var idx := names.find(current)
		if idx < 0:
			_portrait.add_item("%s (file missing!)" % current)
			idx = names.size()
		_portrait.select(idx + 1)


func _show_divert(e: Dictionary) -> void:
	var target := str(e.get("divert", ""))
	if target == "":
		_divert_label.text = "Continues to: (not chosen yet)"
	elif db.has_id(target):
		_divert_label.text = "Continues to: " + db.label_for(target, 80)
	else:
		_divert_label.text = "Continues to: %s  (this line doesn't exist!)" % target


# Preview, character count / overflow, and problems for the selected line.
func _refresh_info() -> void:
	var e := _entry()
	if e.is_empty():
		return
	var portrait := _current_portrait()
	var tex := Ctx.portrait_texture(portrait)
	_portrait_thumb.texture = tex
	_preview_portrait.texture = tex
	_preview_portrait.visible = tex != null
	var text := str(e.get("text", ""))
	_preview_text.text = text
	_preview_text.custom_minimum_size.x = 305 if tex != null else 400
	var m := Metrics.measure(text, tex != null)
	_text_info.text = "%d characters · %d line%s" % [text.length(), m["lines"], "" if m["lines"] == 1 else "s"]
	if m["overflow"]:
		_text_info.text += " · ⚠ too long: it won't fit in the dialogue box"
		_text_info.modulate = Color(1, 0.6, 0.3)
	else:
		_text_info.text += " · fits the dialogue box"
		_text_info.modulate = Color(1, 1, 1, 0.6)
	var msgs: PackedStringArray = []
	for p in Validator.run(db, _scene_refs):
		if p["id"] == selected_id and p["sev"] != Validator.Severity.INFO:
			msgs.append("• " + p["msg"])
	_problem_label.text = "\n".join(msgs)
	_problem_label.visible = not msgs.is_empty()


func _refresh_used_by() -> void:
	for c in _used_by.get_children():
		_used_by.remove_child(c)
		c.queue_free()
	var refs := db.references_to(selected_id)
	var any := false
	for r in refs:
		var b := Ctx.button("← " + str(r["id"]), "Used by %s (%s)" % [r["id"], r["via"]])
		b.flat = true
		b.pressed.connect(select_id.bind(str(r["id"])))
		_used_by.add_child(b)
		any = true
	for r in _scene_refs:
		if (r["ids"] as Array).has(selected_id):
			var b := Ctx.button("📦 %s  (%s)" % [r["node"], r["scene"].get_file().get_basename()], "Open " + r["scene"])
			b.flat = true
			b.pressed.connect(func(): if Ctx.editor() != null: Ctx.editor().open_scene_from_path(r["scene"]))
			_used_by.add_child(b)
			any = true
	if not any:
		_used_by.add_child(Ctx.label("Not used by any object or line yet", true))
	else:
		_used_by.add_child(Ctx.label("", true))


# ============ UI -> data ============

func _commit() -> void:
	db.touch(self)
	_fill_list()
	_refresh_info()


func _set_field(key: String, value: Variant) -> void:
	if _building or selected_id == "":
		return
	_entry()[key] = value
	_commit()


func _on_text_changed() -> void:
	if _building or selected_id == "":
		return
	_entry()["text"] = _text_edit.text
	_commit()


func _on_portrait(index: int) -> void:
	if _building or selected_id == "":
		return
	var chosen: Variant = null if index == 0 else _portrait.get_item_text(index)
	if chosen != null and str(chosen).ends_with("(file missing!)"):
		return
	_entry()["expression"] = chosen
	_commit()


func _on_mode(index: int) -> void:
	if _building or selected_id == "":
		return
	var kinds := [DialogueDB.Kind.END, DialogueDB.Kind.DIVERT, DialogueDB.Kind.CHOICES, DialogueDB.Kind.NONE]
	db.set_kind(_entry(), kinds[index])
	_commit()
	_select(selected_id)


func _set_divert(target: String) -> void:
	if selected_id == "":
		return
	_entry()["divert"] = target
	_commit()
	_show_divert(_entry())


func _on_new_next() -> void:
	if selected_id == "":
		return
	var prefix := DialogueDB.prefix_of(selected_id)
	var id := db.new_entry(prefix, self)
	db.get_entry(id)["expression"] = _entry().get("expression")
	_entry()["divert"] = id
	db.touch(self)
	select_id(id)


func _on_choice_label(text: String, index: int) -> void:
	if _building or selected_id == "":
		return
	var labels: Array = _entry().get("choices", ["", ""])
	labels = labels.duplicate()
	labels.resize(2)
	labels[index] = text
	_entry()["choices"] = labels
	_commit()


func _on_choice_ids(ids: Array, index: int) -> void:
	if _building or selected_id == "":
		return
	_entry()["choice_%d" % index] = ids
	_commit()


func _on_new() -> void:
	var prefix := _prefix.text.strip_edges()
	if prefix == "":
		prefix = "NPC"
	var id := db.new_entry(prefix, self)
	select_id(id)


func _on_duplicate() -> void:
	if selected_id == "":
		return
	select_id(db.duplicate_entry(selected_id, self))


func _on_delete() -> void:
	if selected_id == "":
		return
	var users: Array = db.references_to(selected_id)
	var scene_users := 0
	for r in _scene_refs:
		if (r["ids"] as Array).has(selected_id):
			scene_users += 1
	_confirm.title = "Delete " + selected_id
	_confirm.dialog_text = "Delete this line?"
	if not users.is_empty() or scene_users > 0:
		_confirm.dialog_text += "\n\nWarning: %d other line%s and %d object%s point at it. They'll show an error in the Problems tab until you fix them." % [users.size(), "" if users.size() == 1 else "s", scene_users, "" if scene_users == 1 else "s"]
	_confirm_action = func():
		var gone := selected_id
		db.delete_entry(gone, self)
		selected_id = ""
		refresh()
	_confirm.popup_centered()


func _on_rename(new_id: String) -> void:
	new_id = new_id.strip_edges()
	var old_id := selected_id
	if old_id == "" or new_id == old_id:
		return
	var scene_hits := 0
	for r in _scene_refs:
		if (r["ids"] as Array).has(old_id):
			scene_hits += 1
	var entry_hits := db.references_to(old_id).size()
	var do_rename := func():
		var err := db.rename_id(old_id, new_id, self)
		if err != "":
			_status.text = "⚠ " + err
			_status.modulate = Color(1, 0.5, 0.5)
			_id_edit.text = old_id
			return
		var files := Scanner.rename_in_scenes(old_id, new_id) if scene_hits > 0 else PackedStringArray()
		if not files.is_empty():
			Ctx.rescan_files()
		selected_id = new_id
		refresh()
		_select(new_id)
		_status.text = "Renamed. Updated %d line reference%s and %d scene file%s." % [entry_hits, "" if entry_hits == 1 else "s", files.size(), "" if files.size() == 1 else "s"]
		if not files.is_empty():
			_status.text += " If Godot asks to reload a scene, say yes."
		_status.modulate = Color(0.6, 1, 0.6)
	if entry_hits + scene_hits == 0:
		do_rename.call()
		return
	_confirm.title = "Rename " + old_id
	_confirm.dialog_text = "Rename %s to %s?\n\n%d line reference%s and %d object%s will be updated (scene files are edited on disk)." % [old_id, new_id, entry_hits, "" if entry_hits == 1 else "s", scene_hits, "" if scene_hits == 1 else "s"]
	_confirm_action = do_rename
	_confirm.popup_centered()


func _on_db_changed(source: Object) -> void:
	if source == self:
		return
	refresh()
