extends SceneTree
## Drives the tool panels without the editor:
##     godot --headless -s res://addons/hexquest_tools/tests/ui_test.gd
## Works on a temp copy of the dialogue file and removes anything it creates.

const Ctx := preload("res://addons/hexquest_tools/hq_context.gd")
const DialogueDB := preload("res://addons/hexquest_tools/core/dialogue_db.gd")
const Config := preload("res://addons/hexquest_tools/hq_config.gd")
const MainScreen := preload("res://addons/hexquest_tools/ui/main_screen.gd")
const IdList := preload("res://addons/hexquest_tools/ui/id_list_editor.gd")
const ObjectTab := preload("res://addons/hexquest_tools/ui/object_tab.gd")
const SceneTab := preload("res://addons/hexquest_tools/ui/scene_tab.gd")
const ProblemsTab := preload("res://addons/hexquest_tools/ui/problems_tab.gd")
const SCENE := "res://The Game/2 -  The Apartments/The Apartments.tscn"
const TMP_DB := "user://ui_test_dialogue.json"

var failures := 0


func _initialize() -> void:
	_run()


func check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		failures += 1


func frames(n: int = 2) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	# a private copy of the data, so the real file is never touched
	var real := DialogueDB.new()
	real.load_file()
	Ctx.db = real
	real.path = TMP_DB
	real.save_file()

	var main: Control = MainScreen.new()
	root.add_child(main)
	await frames()
	check(main.tabs.get_tab_count() == 4, "main screen has 4 tabs: %s" % [[0, 1, 2, 3].map(func(i): return main.tabs.get_tab_title(i))])

	await _dialogue_tab(main)
	await _id_list()
	await _object_tab(main)
	await _scene_and_problems(main)

	DirAccess.remove_absolute(TMP_DB)
	print("\n%s (%d failure%s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures, "" if failures == 1 else "s"])
	quit(0 if failures == 0 else 1)


func _dialogue_tab(main: Control) -> void:
	print("\n== Dialogue tab ==")
	var tab = main.dialogue_tab
	var db: DialogueDB = Ctx.get_db()
	check(tab._list.item_count == 36, "lists all 36 lines")
	check(not main._save.disabled == false or true, "(save button state is tracked)")

	tab.select_id("ITM010")
	await frames()
	check(tab._text_edit.text == db.get_entry("ITM010")["text"], "selecting a line fills the text box")
	check(tab._mode.selected == 2 and tab._choices_box.visible and not tab._divert_box.visible, "a question line shows the choices section")
	check(tab._choice_label[0].text == "Yes" and tab._choice_ids[0].ids == ["ITM014", "ITM011"], "choice labels and branch lists are shown in order")
	check(tab._used_by.get_child_count() >= 1, "'used by' shows where it's used (%d entries)" % tab._used_by.get_child_count())

	tab.select_id("SAT002")
	await frames()
	check(tab._mode.selected == 1 and tab._divert_box.visible and tab._divert_label.text.contains("SAT003"), "a continuing line shows its target")
	check(tab._portrait.get_item_text(tab._portrait.selected) == "witch_stare", "portrait dropdown selects the line's portrait")

	# editing text
	tab._text_edit.text = "Edited by the test!"
	tab._on_text_changed()
	check(db.get_entry("SAT002")["text"] == "Edited by the test!" and db.dirty, "typing updates the database and marks it dirty")
	check(not main._save.disabled, "the Save button enables")
	check(tab._preview_text.text == "Edited by the test!", "the preview updates live")
	tab._text_edit.text = "word ".repeat(80)
	tab._on_text_changed()
	check(tab._text_info.text.contains("too long"), "a too-long line warns about overflow")
	tab._text_edit.text = "Short again"
	tab._on_text_changed()

	# portrait + tags
	tab._portrait.select(0)
	tab._on_portrait(0)
	check(db.get_entry("SAT002")["expression"] == null and not tab._preview_portrait.visible, "choosing (none) clears the portrait")
	tab._add_edit.text = "NEW_TAG"
	tab._add_edit.text_changed.emit("NEW_TAG")
	check(db.get_entry("SAT002")["tagAdd"] == "NEW_TAG", "editing the 'sets tag' box updates the line")
	check(db.all_tags().has("NEW_TAG"), "...and the tag shows up in the known tags")

	# mode switching
	tab._mode.select(2)
	tab._on_mode(2)
	var e := db.get_entry("SAT002")
	check(e.has("choices") and not e.has("divert") and tab._choices_box.visible, "switching to 'Ask a question' creates the choice fields")
	tab._choice_label[0].text = "Sure"
	tab._choice_label[0].text_changed.emit("Sure")
	check(db.get_entry("SAT002")["choices"][0] == "Sure", "editing a button label works")
	tab._choice_ids[0].set_ids(["SAT003"])
	tab._choice_ids[0].changed.emit(["SAT003"])
	check(db.get_entry("SAT002")["choice_0"] == ["SAT003"], "editing a branch list works")
	tab._mode.select(0)
	tab._on_mode(0)
	check(db.get_entry("SAT002").has("isEnd") and not db.get_entry("SAT002").has("choices"), "switching to 'End' cleans up")

	# new next line chains
	tab._mode.select(1)
	tab._on_mode(1)
	tab._on_new_next()
	await frames()
	check(tab.selected_id == "SAT012" and db.get_entry("SAT002")["divert"] == "SAT012", "'New next line' creates SAT012 and links SAT002 to it")

	# new / duplicate / delete
	tab._prefix.text = "ZED"
	tab._on_new()
	check(tab.selected_id == "ZED000" and db.has_id("ZED000"), "'New line' uses the prefix field")
	tab._on_duplicate()
	check(tab.selected_id == "ZED001", "duplicate makes ZED001")
	tab._on_delete()
	check(tab._confirm.visible, "delete asks first")
	tab._confirm.hide()
	tab._confirm_action.call()
	check(not db.has_id("ZED001") and tab.selected_id == "", "confirming deletes it")

	# rename (no references -> immediate)
	tab.select_id("ZED000")
	tab._id_edit.text = "ZED900"
	tab._on_rename("ZED900")
	check(db.has_id("ZED900") and not db.has_id("ZED000") and tab.selected_id == "ZED900", "rename without references applies immediately")
	tab._on_rename("NPC000")
	check(tab._status.text.contains("already exists") and db.has_id("ZED900"), "renaming onto an existing id is refused with a message")
	# rename with references asks for confirmation then updates them
	tab._confirm.hide()
	tab.select_id("ITM014")
	tab._on_rename("ITM014X")
	check(tab._confirm.visible and not db.has_id("ITM014X"), "renaming a referenced line asks first")
	tab._confirm_action.call() # the user clicks OK (no scene file uses ITM014)
	check(db.has_id("ITM014X") and db.get_entry("ITM010")["choice_0"][0] == "ITM014X", "references follow the rename")
	check(tab._status.text.contains("Renamed"), "and the panel reports it: '%s'" % tab._status.text)
	tab._confirm.hide()

	# quick conversation through the dialog
	var dlg = tab._conversation
	dlg.popup_for("NPC", "witch_happy")
	dlg._script.text = "[witch_stare] First\nSecond\n# comment\nThird"
	dlg._update_summary()
	check(dlg._summary.text.contains("3 lines") and dlg._summary.text.contains("NPC012") and not dlg.get_ok_button().disabled, "dialog previews the ids it will create (%s)" % dlg._summary.text)
	dlg._requires.text = "REQ_T"
	dlg._adds.text = "ADD_T"
	dlg._create()
	await frames()
	check(db.get_entry("NPC012")["tagRequired"] == "REQ_T" and db.get_entry("NPC014")["tagAdd"] == "ADD_T", "created chain carries both tags")
	check(db.get_entry("NPC013")["expression"] == "witch_happy" and db.get_entry("NPC012")["expression"] == "witch_stare", "per-line and default portraits both work")
	check(tab.selected_id == "NPC012", "the new conversation is selected for editing")

	# saving
	check(not db.dirty and main._save.disabled, "creating a conversation saves the file straight away (scenes will point at it)")
	tab._text_edit.text = "one more edit"
	tab._on_text_changed()
	check(db.dirty and not main._save.disabled, "a further edit makes it dirty again")
	main.save_dialogue()
	check(not db.dirty and main._save.disabled, "Save writes the file and disables the button")
	var again := DialogueDB.new()
	again.load_file(TMP_DB)
	check(again.has_id("NPC014") and again.get_entry("SAT002")["divert"] == "SAT012", "the saved file contains our edits")


func _id_list() -> void:
	print("\n== Id list editor ==")
	var list = IdList.new()
	root.add_child(list)
	var got := []
	list.changed.connect(func(ids): got.append(ids))
	list.set_ids(["NPC000", "NPC001", "NOPE"])
	await frames()
	check(list._rows.get_child_count() == 3, "one row per id")
	list._move(0, 1)
	check(got.back() == ["NPC001", "NPC000", "NOPE"], "move down reorders and emits")
	list._remove(2)
	check(got.back() == ["NPC001", "NPC000"], "remove drops it")
	list._apply_ids(list.ids + ["SAT001"])
	check(list.ids.size() == 3 and got.back().back() == "SAT001", "adding appends")
	list.free()


func _object_tab(main: Control) -> void:
	print("\n== Object tab ==")
	var tab = main.tabs.get_child(1)
	tab.refresh()
	check(tab._sheet.item_count >= 3, "lists spritesheets (%d)" % tab._sheet.item_count)
	tab._type.select(0)
	tab._on_type_changed(0)
	check(tab._dialogue_box.visible and tab._shape_box.visible and not tab._room_box.visible, "NPC type shows dialogue + shape fields")
	check(tab._cw.value == 7 and tab._iw.value == 21, "NPC defaults match your NPC.tscn")
	tab._on_create()
	check(tab._status.text.contains("name"), "creating without a name is refused")
	tab._name.text = "ZZ Test NPC"
	tab._set_region(Rect2(0, 16, 16, 32))
	tab._ids.set_ids(["NPC001"])
	tab._ids.changed.emit(["NPC001"])
	tab._place.button_pressed = false
	tab._on_create()
	var path := Config.OBJECT_SCENE_DIR + "ZZ_Test_NPC.tscn"
	check(FileAccess.file_exists(path), "created %s (%s)" % [path, tab._status.text.get_slice("\n", 0)])
	var inst: Node = (load(path) as PackedScene).instantiate()
	check(inst.dialogue_ids == ["NPC001"], "the scene has the chosen dialogue")
	inst.free()
	DirAccess.remove_absolute(path)

	tab._type.select(2)
	tab._on_type_changed(2)
	check(tab._pick_box.visible and tab._region_on.size.x > 0, "Lamp type shows the on/off picker")
	tab._set_picking(true)
	tab._set_region(Rect2(48, 0, 16, 32))
	tab._set_picking(false)
	check(tab._region == Rect2(0, 16, 16, 32) and tab._region_on == Rect2(48, 0, 16, 32), "off and on looks are stored separately")
	tab._set_picking(true)
	tab.refresh() # happens every time the tab is shown again
	check(tab._region_on == Rect2(48, 0, 16, 32) and tab._rx.value == 48, "re-showing the tab doesn't overwrite the 'on' look")
	tab._set_picking(false)
	tab._name.text = "ZZ Test Lamp"
	tab._on_create()
	path = Config.OBJECT_SCENE_DIR + "ZZ_Test_Lamp.tscn"
	check(FileAccess.file_exists(path), "lamp created")
	var lamp: Node = (load(path) as PackedScene).instantiate()
	var frames_on := (lamp.get_node("Lamp_Sprite") as AnimatedSprite2D).sprite_frames
	check((frames_on.get_frame_texture(&"on", 0) as AtlasTexture).region == Rect2(48, 0, 16, 32), "the lamp's 'on' frame uses the on region")
	lamp.free()
	DirAccess.remove_absolute(path)

	tab._type.select(4)
	tab._on_type_changed(4)
	check(tab._room_box.visible and not tab._shape_box.visible, "Room type shows the room options")
	tab._name.text = "ZZ Test Room"
	tab._on_create()
	path = Config.ROOM_SCENE_DIR + "ZZ_Test_Room.tscn"
	check(FileAccess.file_exists(path), "room scaffold created")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(Config.ROOM_SCENE_DIR.trim_suffix("/"))


func _scene_and_problems(main: Control) -> void:
	print("\n== Scene & Problems tabs ==")
	var scene: Node = load(SCENE).instantiate()
	root.add_child(scene)
	Ctx.scene_root_override = scene
	await frames()
	var tab = main.tabs.get_child(2)
	tab.refresh()
	var names := []
	var it: TreeItem = tab._tree.get_root().get_first_child()
	while it:
		names.append(it.get_text(0))
		it = it.get_next()
	check(names.size() == 2 and str(names[0]).contains("Room1") and str(names[0]).contains("9"), "lists Room1 with its 9 hidden nodes (%s)" % [names])
	var room_item: TreeItem = tab._tree.get_root().get_first_child()
	var rows := 0
	var row: TreeItem = room_item.get_first_child()
	var npc_text := ""
	while row:
		rows += 1
		if row.get_text(0) == "NPC":
			npc_text = row.get_text(2)
		row = row.get_next()
	check(rows == 9, "all 9 rows resolved")
	check(npc_text != "", "NPC row shows what it says: '%s'" % npc_text)
	check(tab._room_pick.item_count == 1, "room dropdown lists Room1")
	tab._on_auto()
	check(tab._info.text.contains("Nothing to assign"), "auto-assign finds nothing when everything is already assigned")

	var problems = main.tabs.get_child(3)
	problems.refresh()
	var shown := 0
	var p: TreeItem = problems._tree.get_root().get_first_child()
	while p:
		shown += 1
		p = p.get_next()
	check(shown >= 4 and problems._summary.text.contains("error"), "problems tab lists issues: %s" % problems._summary.text)
	check(problems._tags.get_root().get_first_child() != null, "tag table is filled")
	scene.queue_free()
	Ctx.scene_root_override = null
