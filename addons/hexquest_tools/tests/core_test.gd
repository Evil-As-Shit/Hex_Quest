extends SceneTree
## Headless test for the HexQuest Tools core (no editor needed):
##     godot --headless -s res://addons/hexquest_tools/tests/core_test.gd
## Uses temporary files under res://Tests/_tmp/ and user://, and cleans them up.

const DialogueDB := preload("res://addons/hexquest_tools/core/dialogue_db.gd")
const Validator := preload("res://addons/hexquest_tools/core/validator.gd")
const Metrics := preload("res://addons/hexquest_tools/core/dialogue_metrics.gd")
const Scanner := preload("res://addons/hexquest_tools/core/scene_scanner.gd")
const Factory := preload("res://addons/hexquest_tools/core/object_factory.gd")
const SceneTools := preload("res://addons/hexquest_tools/core/scene_tools.gd")
const SCENE := "res://The Game/2 - The Apartments/The Apartments.tscn"
const TMP := "res://Tests/_tmp"

var failures := 0
var scene: Node


func _initialize() -> void:
	_run()


func check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame
	await process_frame


func press(action: String) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		root.push_input(e)
		await frames(1)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	await _test_db()
	await _test_validator_and_scanner()
	await _test_factory_in_game()
	_test_instanced_room_saves()
	# clean up
	for f in DirAccess.get_files_at(TMP):
		DirAccess.remove_absolute(TMP.path_join(f))
	DirAccess.remove_absolute(TMP)
	print("\n%s (%d failure%s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures, "" if failures == 1 else "s"])
	quit(0 if failures == 0 else 1)


func _test_db() -> void:
	print("\n== DialogueDB ==")
	var db := DialogueDB.new()
	check(db.load_file(), "loads dialogue.txt")
	# the expected count and prefix order are read straight from the file, so adding a line doesn't break this
	var id_rx := RegEx.create_from_string("\"id\"\\s*:\\s*\"([^\"]+)\"")
	var file_ids := []
	var file_prefixes := PackedStringArray()
	for m in id_rx.search_all(FileAccess.get_file_as_string(DialogueDB.new().path)):
		file_ids.append(m.get_string(1))
		var pre := DialogueDB.prefix_of(m.get_string(1))
		if not file_prefixes.has(pre):
			file_prefixes.append(pre)
	check(file_ids.size() > 0 and db.entries.size() == file_ids.size(), "%d entries, as many as dialogue.txt has ids (%d)" % [db.entries.size(), file_ids.size()])
	check(DialogueDB.kind_of(db.get_entry("ITM010")) == DialogueDB.Kind.CHOICES, "ITM010 is a question")
	check(DialogueDB.kind_of(db.get_entry("SAT002")) == DialogueDB.Kind.DIVERT, "SAT002 continues")
	check(DialogueDB.kind_of(db.get_entry("SAT001")) == DialogueDB.Kind.END, "SAT001 ends")

	var on_disk := FileAccess.get_file_as_string(DialogueDB.new().path)
	var same := db.to_json_text() == on_disk
	if not same:
		var a := db.to_json_text().split("\n")
		var b := on_disk.split("\n")
		for i in mini(a.size(), b.size()):
			if a[i] != b[i]:
				print("    first difference, line %d:\n      ours: %s\n      file: %s" % [i + 1, a[i], b[i]])
				break
	check(same, "saving an untouched database reproduces the file byte-for-byte")

	# the expected next ids come from the data (it grows), not hard-coded numbers
	var npc_max := -1
	for e in db.entries:
		var eid := str(e["id"])
		if eid.begins_with("NPC") and eid.substr(3).is_valid_int():
			npc_max = maxi(npc_max, eid.substr(3).to_int())
	var n1 := "NPC%03d" % (npc_max + 1)
	var n2 := "NPC%03d" % (npc_max + 2)
	var n3 := "NPC%03d" % (npc_max + 3)
	check(db.next_id("NPC") == n1, "next NPC id is one past the highest, %s (%s)" % [n1, db.next_id("NPC")])
	check(db.next_id("SAT") == "SAT012", "next SAT id skips the gap and uses the max (%s)" % db.next_id("SAT"))
	check(db.next_id("BRAND") == "BRAND000", "a new prefix starts at 000")
	check(DialogueDB.prefix_of("NPC012") == "NPC" and DialogueDB.prefix_of("A_B_7") == "A_B_", "prefix_of")
	check(db.prefixes() == file_prefixes and file_prefixes.has("TABLE"), "prefixes in file order %s" % [db.prefixes()])

	# references / reachability
	var refs := db.references_to("ITM014")
	check(refs.size() == 1 and refs[0]["id"] == "ITM010" and refs[0]["via"] == "choice_0", "references_to finds the choice branch")
	check(db.reachable_from("SAT002") == PackedStringArray(["SAT002", "SAT003"]), "reachable_from follows diverts")

	# conversation builder
	var lines := DialogueDB.parse_script("# comment\n[witch_happy] Hello there!\n\nSecond line\n[witch_stare]   Third")
	check(lines.size() == 3 and lines[0]["expression"] == "witch_happy" and lines[1]["expression"] == null and lines[2]["text"] == "Third", "parse_script")
	var ids := db.create_conversation(lines, "NPC", "NEEDS_X", "DID_Y", "witch_smug")
	check(ids == PackedStringArray([n1, n2, n3]), "create_conversation ids are consecutive %s" % [ids])
	var first := db.get_entry(n1)
	var last := db.get_entry(n3)
	check(first.get("divert") == n2 and first.get("tagRequired") == "NEEDS_X", "first line diverts and carries the required tag")
	check(db.get_entry(n2)["expression"] == "witch_smug", "default portrait applies to lines without one")
	check(last["isEnd"] == true and last["tagAdd"] == "DID_Y" and not last.has("divert"), "last line ends and adds the tag")
	check(db.dirty, "database is marked dirty")

	# rename updates references
	check(db.rename_id("ITM014", "ITM099") == "", "rename works")
	check(db.get_entry("ITM010")["choice_0"][0] == "ITM099", "rename updated the choice list that used it")
	check(db.rename_id("ITM099", "NPC000") != "", "rename onto an existing id is refused")
	check(db.rename_id("ITM099", "9bad") != "", "rename to an invalid id is refused")

	# kinds
	var e := db.get_entry("NPC013")
	db.set_kind(e, DialogueDB.Kind.CHOICES)
	check(e["choices"] == ["Yes", "No"] and e.has("choice_0") and not e.has("divert"), "set_kind CHOICES")
	db.set_kind(e, DialogueDB.Kind.END)
	check(e["isEnd"] == true and not e.has("choices") and not e.has("choice_0"), "set_kind END cleans up choice keys")

	# duplicate / delete / save+reload
	var dup := db.duplicate_entry("SAT001")
	check(dup == "SAT012" and db.get_entry(dup)["text"] == db.get_entry("SAT001")["text"], "duplicate_entry")
	db.delete_entry(dup)
	check(not db.has_id(dup), "delete_entry")
	var tmp_path := TMP + "/db.json"
	db.path = tmp_path
	check(db.save_file() and not db.dirty, "save_file writes and clears dirty")
	var db2 := DialogueDB.new()
	check(db2.load_file(tmp_path) and db2.entries.size() == db.entries.size() and db2.to_json_text() == db.to_json_text(), "save -> load round trip is lossless")

	# empty optional fields are dropped on save, and expression is always present
	var db3 := DialogueDB.new()
	db3.add_entry({"id": "A000", "text": "x", "tagAdd": "", "isEnd": true})
	var out: Dictionary = JSON.parse_string(db3.to_json_text())["dialogue"][0]
	check(not out.has("tagAdd") and out.has("expression") and out["expression"] == null, "empty fields dropped, expression kept as null")
	check(db.changed_on_disk() == false, "changed_on_disk is false right after saving")


func _test_validator_and_scanner() -> void:
	print("\n== Validator + scanner (on your real data) ==")
	var db := DialogueDB.new()
	db.load_file()
	var refs := Scanner.scan_dialogue_refs()
	var names := []
	for r in refs:
		names.append(r["node"])
	check(refs.size() >= 8, "scene scan found %d objects with dialogue_ids" % refs.size())
	# (the Apartments NPC is now called Charater_Test; match scenes by file rather than by a node name)
	var scenes_seen := []
	for r in refs:
		if not scenes_seen.has(r["scene"]):
			scenes_seen.append(r["scene"])
	check(scenes_seen.has(SCENE) and names.has("Charater_Test") and names.has("Table"), "found Apartments nodes (%s…)" % [names.slice(0, 6)])
	check(scenes_seen.any(func(s): return s.contains("the_satellite")) and names.has("shoe_rack") and names.has("Door"), "found Satellite nodes too")
	var problems := Validator.run(db, refs)
	var counts := [0, 0, 0]
	for p in problems:
		counts[p["sev"]] += 1
	print("    real data: %d errors, %d warnings, %d info" % counts)
	for p in problems:
		if p["sev"] != Validator.Severity.INFO:
			print("      [%s] %s %s %s" % [["ERROR", "WARN", "info"][p["sev"]], p["id"], "(%s)" % p["node"] if p["node"] != "" else "", p["msg"]])

	# synthetic problems
	var bad := DialogueDB.new()
	bad.add_entry({"id": "A000", "text": "one", "divert": "A999"})
	bad.add_entry({"id": "A001", "text": "dead end"})
	bad.add_entry({"id": "A001", "text": "dupe", "isEnd": true})
	bad.add_entry({"id": "A002", "text": "loop a", "divert": "A003"})
	bad.add_entry({"id": "A003", "text": "loop b", "divert": "A002"})
	bad.add_entry({"id": "A004", "text": "q", "choices": ["Only one"], "choice_0": [], "choice_1": ["A777"]})
	bad.add_entry({"id": "A005", "text": "needs", "tagRequired": "NOBODY_ADDS", "isEnd": true})
	bad.add_entry({"id": "A006", "text": "portrait", "expression": "nope_nope", "isEnd": true})
	bad.add_entry({"id": "A007", "text": "", "isEnd": true})
	bad.add_entry({"id": "A008", "text": "word ".repeat(80), "isEnd": true})
	bad.add_entry({"id": "B000", "text": "always", "isEnd": true})
	bad.add_entry({"id": "B001", "text": "hidden", "tagRequired": "NOBODY_ADDS", "isEnd": true})
	var all := Validator.run(bad, [{"scene": "res://x.tscn", "node": "Obj", "ids": ["B000", "B001", "MISSING"]}])
	var text := ""
	for p in all:
		text += p["msg"] + "\n"
	for expected in ["doesn't exist", "Dead end", "Duplicate id", "loop", "exactly 2 labels", "leads nowhere", "no line adds it", "Portrait 'nope_nope'", "Empty text", "too long", "can never show"]:
		check(text.contains(expected), "detects: " + expected)
	check(text.contains("Uses dialogue 'MISSING'"), "detects a scene using a missing id")

	# text measurement
	check(not Metrics.measure("Short.", false)["overflow"], "short text fits")
	var m: Dictionary = Metrics.measure("word ".repeat(80), true)
	check(m["overflow"] and m["lines"] > 4, "long text overflows (%d lines)" % m["lines"])

	# scene rename on a temp scene
	var tmp_scene := TMP + "/_rename_me.tscn"
	var f := FileAccess.open(tmp_scene, FileAccess.WRITE)
	f.store_string('[gd_scene format=3]\n\n[node name="Root" type="Node2D"]\n\n[node name="Guy" type="Node2D" parent="."]\ndialogue_ids = Array[String](["ZZ_OLD", "NPC000"])\n')
	f.close()
	var changed := Scanner.rename_in_scenes("ZZ_OLD", "ZZ_NEW")
	check(changed == PackedStringArray([tmp_scene]), "rename_in_scenes touched only the one scene (%s)" % [changed])
	check(FileAccess.get_file_as_string(tmp_scene).contains('["ZZ_NEW", "NPC000"]'), "...and rewrote the id in place, keeping the rest")


func _test_factory_in_game() -> void:
	print("\n== ObjectFactory + SceneTools, in the running game ==")
	var sheet := Factory.new()
	var texture_path := "res://Assets/Sprites/Objects/Objects_Spritesheet.png"
	var specs := {
		"npc": {"type": Factory.Type.NPC, "name": "Grandma", "texture": texture_path, "region": Rect2(0, 16, 16, 32), "dialogue_ids": ["NPC000"]},
		"seat": {"type": Factory.Type.SEAT, "name": "Stool", "texture": texture_path, "region": Rect2(0, 0, 16, 16)},
		"lamp": {"type": Factory.Type.LAMP, "name": "Torch", "texture": texture_path, "region": Rect2(16, 0, 16, 32), "region_on": Rect2(32, 0, 16, 32)},
		"prop": {"type": Factory.Type.PROP, "name": "Crate", "texture": texture_path, "region": Rect2(0, 0, 16, 16)},
	}
	var paths := {}
	for key in specs:
		var s: Dictionary = specs[key]
		var d := Factory.defaults_for(s["type"])
		for k in d:
			s[k] = d[k]
		var obj := Factory.build_object(s)
		paths[key] = Factory.unique_scene_path(TMP, s["name"])
		check(Factory.save_scene(obj, paths[key]) == OK, "%s scene saved to %s" % [key, paths[key].get_file()])
		obj.free()
	check(Factory.unique_scene_path(TMP, "Grandma") == TMP + "/Grandma2.tscn", "unique_scene_path avoids overwriting")

	var npc_inst: Node = (load(paths["npc"]) as PackedScene).instantiate()
	check(npc_inst.get_node_or_null("Object_Id/Interact_Area") != null and npc_inst.get_node_or_null("Collision") != null and npc_inst.get_node_or_null("Sprite") != null, "NPC has Sprite, Collision and Object_Id/Interact_Area")
	check(npc_inst.get_script().resource_path.ends_with("NPC.gd") and npc_inst.dialogue_ids == ["NPC000"], "NPC has the NPC script and its dialogue ids")
	check(npc_inst.collision_layer == 4 and npc_inst.get_node("Object_Id").collision_layer == 4, "NPC is on the objects layer")
	check((npc_inst.get_node("Sprite") as Sprite2D).position == Vector2(-8, -32) and not (npc_inst.get_node("Sprite") as Sprite2D).centered, "sprite anchored at the feet, like your NPC.tscn")
	npc_inst.free()

	scene = load(SCENE).instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(3)
	var save_manager := root.get_node("SaveManager")
	save_manager.save_path = TMP.replace("res://", "user://") + "_save.json"
	var ysort := SceneTools.ysort_of(scene)
	check(ysort.name == "YSort", "ysort_of finds YSort")
	var hexy := scene.get_node("YSort/CharacterBody2D")
	var game_data := root.get_node("GameData")

	var placed := {}
	var x := 0.0
	for key in paths:
		var inst: Node2D = (load(paths[key]) as PackedScene).instantiate()
		inst.position = Vector2(-40 + x, -20)
		x += 18.0
		ysort.add_child(inst)
		inst.owner = scene
		placed[key] = inst
	await frames(2)

	# NPC: interacting shows its dialogue
	hexy.global_position = placed["npc"].get_node("Object_Id/Interact_Area").global_position
	await frames(2)
	await press("interact")
	check(game_data.is_in_dialogue and game_data.dialogue_id == "NPC000", "a built NPC starts its dialogue when Hexy presses E")
	root.get_node("SignalController").close_dialogue.emit()
	await frames(1)

	# Seat: interacting sits
	hexy.global_position = placed["seat"].get_node("Object_Id/Interact_Area").global_position
	await frames(2)
	await press("interact")
	check(hexy.is_sitting, "a built Seat makes Hexy sit")
	hexy.current_state = 0 # stand again (IDLE)
	await frames(2)

	# Lamp: interacting toggles, and the state is saveable
	var lamp: Node = placed["lamp"]
	hexy.global_position = lamp.get_node("Object_Id/Interact_Area").global_position
	await frames(2)
	await press("interact")
	check(lamp.is_on and lamp.get_node("Lamp_Sprite").animation == &"on", "a built Lamp toggles on")
	check(lamp.get_save_id().ends_with("Torch"), "...and has a save id (%s)" % lamp.get_save_id())

	# Prop: nothing to interact with
	check(placed["prop"].get_node_or_null("Object_Id") == null and placed["prop"].get_script() == null, "a Prop has no interaction and no script")

	# Rooms + assignment suggestions
	var rooms := SceneTools.find_rooms(scene)
	# the Apartments now has two rooms (Room2 is an instanced scene); Room1 comes first in tree order
	check(rooms.size() == 2 and rooms[0].room_id == &"Room1" and rooms[1].room_id == &"Room2", "find_rooms finds Room1 and Room2")
	check(SceneTools.reveal_nodes_of(rooms[0]).size() == 9, "Room1 lists its 9 revealed nodes")
	check(SceneTools.room_of(scene, scene.get_node("YSort/Lamp")) == rooms[0], "room_of maps Lamp -> Room1")
	var crate: Node2D = placed["prop"]
	crate.global_position = Vector2(-20, -30) # inside Room1's floor
	var suggestions := SceneTools.suggest_assignments(scene)
	check(suggestions.has(rooms[0]) and suggestions[rooms[0]].has(crate), "an unassigned prop inside Room1 is suggested for it")
	check(not suggestions[rooms[0]].has(scene.get_node("YSort/Lamp")), "already-assigned objects aren't suggested again")
	check(not SceneTools.room_candidates(scene).has(hexy), "Hexy is never a candidate")

	# Room scaffold
	var room_spec := {"name": "Kitchen", "texture": "res://Assets/Sprites/Environments/TheApartments_Spritesheet.png", "region": Rect2(96, 0, 144, 216), "start_revealed": false}
	var room_scene := Factory.build_room(room_spec)
	var room_path := TMP + "/Kitchen.tscn"
	check(Factory.save_scene(room_scene, room_path) == OK, "room scaffold saved")
	room_scene.free()
	var kitchen: Node = (load(room_path) as PackedScene).instantiate()
	var area := kitchen.get_node("Kitchen")
	check(SceneTools.is_room(area) and area.room_id == &"Kitchen" and area.collision_layer == 2 and not area.monitoring, "scaffold has a Room.gd area on the areas layer")
	check(kitchen.collision_layer == 8 and kitchen.get_node("Kitchen_Sprite") != null and kitchen.get_node("Kitchen_Collision") != null, "...plus a walls body and a sprite")
	kitchen.free()

	scene.queue_free()
	await frames(2)
	DirAccess.remove_absolute(TMP.replace("res://", "user://") + "_save.json")


# Stands in for EditorUndoRedoManager (editor-only): records the do/undo steps so the test can replay them.
class UndoRecorder:
	var do_calls: Array = []
	var undo_calls: Array = []
	func add_do_method(obj: Object, method: StringName, a: Variant, b: Variant) -> void:
		do_calls.append([obj, method, [a, b]])
	func add_undo_method(obj: Object, method: StringName, a: Variant, b: Variant) -> void:
		undo_calls.append([obj, method, [a, b]])


# Regression: Room2 is an instanced scene, and assigning objects to it used to be silently dropped on
# save because "Editable Children" wasn't on for the instance.
func _test_instanced_room_saves() -> void:
	print("\n== Assigning to a room inside an instanced scene survives saving ==")
	var edit_root: Node = (load(SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var room2: Node = edit_root.get_node("YSort/Room2/Room2")
	# The real scene may already have Editable Children on for Room2; start from "off" to test the fix.
	edit_root.set_editable_instance(edit_root.get_node("YSort/Room2"), false)
	var needs := SceneTools.instances_needing_editable(edit_root, room2)
	check(needs == [edit_root.get_node("YSort/Room2")], "Room2's instance is reported as needing Editable Children")
	check(SceneTools.instances_needing_editable(edit_root, edit_root.get_node("YSort/Room1/Room1")).is_empty(), "Room1 (built in the scene) needs nothing")

	var rec := UndoRecorder.new()
	SceneTools.add_make_editable(rec, edit_root, room2)
	check(rec.do_calls.size() == 1 and rec.undo_calls.size() == 1, "one do + one undo step added")
	for c in rec.do_calls:
		(c[0] as Object).callv(c[1], c[2])
	# Table isn't in Room2's list in any saved version, so finding it after reload proves the save worked.
	var list := SceneTools.reveal_nodes_of(room2)
	list.append(room2.get_path_to(edit_root.get_node("YSort/Table")))
	room2.set("reveal_nodes", list)

	var packed := PackedScene.new()
	var path := TMP + "/apartments_copy.tscn"
	check(packed.pack(edit_root) == OK and ResourceSaver.save(packed, path) == OK, "scene packed and saved")
	edit_root.free()
	var back: Node = (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved := SceneTools.reveal_nodes_of(back.get_node("YSort/Room2/Room2"))
	check(saved.has(NodePath("../../Table")), "the new entry is still in Room2's list after save + reload (got %s)" % [saved])
	back.free()

	for c in rec.undo_calls:
		check(c[1] == &"set_editable_instance" and c[2][1] == false, "undo turns Editable Children back off")
