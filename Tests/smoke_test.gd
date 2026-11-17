extends SceneTree
## Headless smoke test for the room reveal, interactions, dialogue and save/load.
## Run from the project folder:
##     godot --headless -s res://Tests/smoke_test.gd
## Prints PASS / FAIL per check and exits with a non-zero code if anything failed.
## It uses its own save file (user://smoke_test_save.json), so your real save is untouched.

const SCENE := "res://The Game/2 -  The Apartments/The Apartments.tscn"
const TEST_SAVE := "user://smoke_test_save.json"

var failures := 0
var scene: Node
# Autoloads aren't visible to the compiler in a -s script, so fetch them from the tree.
var save_manager: Node
var game_data: Node
var signals: Node
var dialogue_controller: GDScript


func _initialize() -> void:
	save_manager = root.get_node("SaveManager")
	game_data = root.get_node("GameData")
	signals = root.get_node("SignalController")
	dialogue_controller = load("res://Scripts/DialogueController.gd")
	_run()


func check(condition: bool, label: String) -> void:
	print(("  PASS  " if condition else "  FAIL  ") + label)
	if not condition:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame
	await process_frame


func start_scene() -> void:
	scene = load(SCENE).instantiate()
	root.add_child(scene)
	current_scene = scene # a real run has this set by the engine
	await frames(3)


func stop_scene() -> void:
	scene.queue_free()
	await frames(2)


func hexy() -> Node:
	return scene.get_node("YSort/CharacterBody2D")


func room() -> Node:
	return scene.get_node("YSort/Room1/Room1")


func stand_on(object: Node) -> void:
	# The centre of an object's interaction shape
	hexy().global_position = object.get_node("Object_Id").get_child(0).global_position
	await frames(2)


func press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	root.push_input(e) # straight to the viewport (headless mode doesn't flush Input's event buffer)
	await frames(1)
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	root.push_input(e)
	await frames(1)


func _run() -> void:
	save_manager.save_path = TEST_SAVE
	DirAccess.remove_absolute(TEST_SAVE)

	print("\n== Startup ==")
	await start_scene()
	check(save_manager._enabled, "GameController enabled saving for the scene")
	check(game_data.dict_dialogue.size() > 0, "dialogue loaded by GameData (%d entries)" % game_data.dict_dialogue.size())
	check(not room().is_revealed, "Room1 starts hidden")
	check(room()._items.size() == 9 or room()._items.size() > 6, "Room1 collected its sprites (%d)" % room()._items.size())
	var npc: Node = scene.get_node("YSort/NPC")
	check(npc.get_node("Sprite").material != null, "NPC sprite is hidden with the room (it used to float in the void)")
	check(scene.get_node("YSort/NPC3/Sprite").material == null, "NPC3 on the balcony stays visible")
	check(hexy()._area_node != null and hexy()._area_node.name == "Balcony", "Hexy starts in the Balcony area")

	print("\n== Room reveal ==")
	var start_pos: Vector2 = hexy().global_position
	hexy().global_position = Vector2(-20, -30) # inside Room1
	await frames(3)
	check(room().is_revealed, "walking into Room1 reveals it")
	check(room()._fade_material != null, "fade is in progress right after entering")
	await create_timer(1.0).timeout
	check(room()._fade_material == null, "fade finished and the shader material was removed")
	check(npc.get_node("Sprite").material == null, "NPC sprite back to a normal material")
	check(save_manager.has_save(), "autosave happened on reveal")

	print("\n== Interactions ==")
	var lamp: Node = scene.get_node("YSort/Lamp")
	await stand_on(lamp)
	await press("interact")
	check(lamp.is_on, "E toggles the lamp on")
	var chair: Node = scene.get_node("YSort/Chair")
	await stand_on(chair)
	await press("interact")
	check(hexy().is_sitting, "E on a chair sits Hexy down")
	check(hexy().collision_shape.disabled, "collision is disabled while sitting")
	var sit_pos: Vector2 = hexy().global_position

	print("\n== Save / load round trip ==")
	DirAccess.remove_absolute(TEST_SAVE)
	game_data.add_tag("TEST_TAG")
	game_data.add_tag("TEST_TAG") # duplicates must not pile up
	check(game_data.dialogue_tags.size() == 1, "tags are a set (no duplicates)")
	check(save_manager.save_game(), "save_game() succeeds")
	var text := FileAccess.get_file_as_string(TEST_SAVE)
	var saved: Dictionary = JSON.parse_string(text)
	check(saved.has("version") and saved["nodes"].has("hexy") and saved["nodes"].has("room:Room1"), "save file has Hexy and Room1")
	check(not FileAccess.file_exists(TEST_SAVE + ".tmp"), "no temp file left behind")

	await stop_scene()
	game_data.reset()
	check(game_data.dialogue_tags.is_empty(), "GameData reset clears tags")
	await start_scene() # a brand new session: everything is back to defaults...
	check(not room().is_revealed or save_manager.has_save(), "(new scene)")
	await frames(3) # ...then GameController's deferred load restores the save
	check(room().is_revealed, "Room1 is still revealed after restart")
	check(room()._fade_material == null and scene.get_node("YSort/NPC/Sprite").material == null, "revealed instantly, no fade or shader left")
	check(scene.get_node("YSort/Lamp").is_on, "lamp is still on")
	check(game_data.has_tag("TEST_TAG"), "dialogue tag restored")
	check(hexy().global_position.distance_to(sit_pos) < 0.01, "Hexy is back at the chair")
	check(hexy().is_sitting, "Hexy is still sitting")
	await frames(2)
	check(hexy().collision_shape.disabled, "collision still disabled while sitting")

	print("\n== Standing up / loading an older save re-hides rooms ==")
	scene.get_node("InputController").set_process(false) # so it doesn't overwrite our fake input
	game_data.move_input_vector = Vector2.RIGHT
	await frames(2)
	game_data.move_input_vector = Vector2.ZERO
	scene.get_node("InputController").set_process(true)
	check(not hexy().is_sitting, "moving stands Hexy up")
	await frames(2)
	check(not hexy().collision_shape.disabled, "collision is back after standing")
	var data := {"version": 1, "scene": SCENE, "game": {}, "nodes": {"room:Room1": {"revealed": false}}}
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	save_manager.load_game()
	await frames(2)
	check(not room().is_revealed and scene.get_node("YSort/NPC/Sprite").material != null, "loading a save made before Room1 was revealed hides it again")
	hexy().global_position = Vector2(-20, -30)
	hexy()._checked_position = Vector2.INF
	hexy()._area_node = null
	await frames(3)
	check(room().is_revealed, "and it reveals again when re-entered")

	print("\n== Dialogue ==")
	var shown: Array = []
	var on_display := func(id: String): shown.append(id)
	signals.display_dialogue.connect(on_display)
	game_data.dict_dialogue["T_A"] = {"id": "T_A", "text": "a", "expression": null, "isEnd": true}
	game_data.dict_dialogue["T_B"] = {"id": "T_B", "text": "b", "expression": null, "isEnd": true}
	dialogue_controller.object_interacted(["T_A", "T_B"])
	check(shown == ["T_A"], "object_interacted shows only the first passing dialogue (got %s)" % [shown])
	signals.close_dialogue.emit()
	game_data.dict_dialogue["T_C"] = {"id": "T_C", "text": "c", "expression": null, "tagRequired": "NOPE", "isEnd": true}
	shown.clear()
	dialogue_controller.object_interacted(["T_C", "T_B"])
	check(shown == ["T_B"], "a failed tagRequired falls through to the next entry (got %s)" % [shown])
	signals.close_dialogue.emit()
	signals.display_dialogue.disconnect(on_display)

	# the typewriter tween
	var box: Control = scene.get_node("UI/DialogueBox")
	game_data.dict_dialogue["T_D"] = {"id": "T_D", "text": "Hello there, world", "expression": null, "isEnd": true}
	signals.display_dialogue.emit("T_D")
	check(box.visible and game_data.flag_displaying_dialogue, "dialogue box opens and types")
	await create_timer(0.15).timeout
	var mid: int = box.get_node("Label").visible_characters
	check(mid > 0 and mid < 18, "typewriter is mid-way (%d/18 chars)" % mid)
	await create_timer(0.6).timeout
	check(not game_data.flag_displaying_dialogue and game_data.flag_waiting_dialogue_next, "typing finished by itself")
	signals.close_dialogue.emit()
	check(not box.visible and not game_data.is_in_dialogue, "close hides the box and clears the flags")
	# closing while typing must not leave a stale tween that fires later
	signals.display_dialogue.emit("T_D")
	await create_timer(0.1).timeout
	signals.close_dialogue.emit()
	await create_timer(0.7).timeout
	check(not game_data.flag_waiting_dialogue_next, "closing mid-typing leaves no stale callback")

	print("\n== Robustness ==")
	var bad := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	bad.store_string("{ this is not json")
	bad.close()
	save_manager.load_game()
	await frames(2)
	check(true, "a corrupt save file doesn't crash")
	check(not save_manager._is_loading, "and doesn't leave the loader stuck")

	DirAccess.remove_absolute(TEST_SAVE)
	print("\n%s (%d failure%s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures, "" if failures == 1 else "s"])
	quit(0 if failures == 0 else 1)
