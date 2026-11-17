extends SceneTree
## Headless test for the satellite -> apartments transition ("Off I go then!" -> full-screen animation -> next level):
##     godot --headless -s res://Tests/transition_test.gd
## Uses its own save file (user://transition_test_save.json); your real save is untouched.

const SAT := "res://The Game/1 - TheSat/Scenes/the_satellite.tscn"
const APARTMENTS := "res://The Game/2 - The Apartments/The Apartments.tscn"
const TEST_SAVE := "user://transition_test_save.json"
const TRIGGER := "SAT011" # "Off I go then!"

var failures := 0
var finished := false
var save_manager: Node
var game_data: Node
var dialogue_controller: GDScript
var error_log := ErrorCounter.new()


## Fails the test on any engine/script error printed during the run (they don't stop a test on their own).
class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		errors.append("%s (%s:%d)" % [rationale if rationale != "" else code, file.get_file(), line])
		_mutex.unlock()


func _initialize() -> void:
	OS.add_logger(error_log)
	save_manager = root.get_node("SaveManager")
	game_data = root.get_node("GameData")
	dialogue_controller = load("res://Scripts/Core/DialogueController.gd")
	create_timer(60.0).timeout.connect(func():
		check(false, "test finished within 60s")
		finish())
	_run()


func check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		failures += 1


func finish() -> void:
	if finished:
		return
	finished = true
	check(error_log.errors.is_empty(), "no errors were printed (%s)" % [error_log.errors])
	OS.remove_logger(error_log)
	DirAccess.remove_absolute(TEST_SAVE)
	print("\n%s (%d failure%s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures, "" if failures == 1 else "s"])
	quit(0 if failures == 0 else 1)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func press(action: String) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		root.push_input(e)
		await frames(1)


func phone_of(scene: Node) -> Node:
	for n in scene.find_children("*", "Control", true, false):
		if n.get_script() != null and n.get_script().resource_path == "res://Scripts/UI/Phone.gd":
			return n
	return null


func _run() -> void:
	save_manager.save_path = TEST_SAVE
	# An old save from the apartments: arriving there by the story must NOT load it.
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "scene": APARTMENTS, "game": {"dialogue_tags": ["OLD_APARTMENTS_TAG"]}, "nodes": {}}))
	f.close()
	game_data.reset()
	save_manager._skip_next_load = true # start the satellite fresh, as New Game would
	change_scene_to_file(SAT)
	await frames(5)

	print("\n== Satellite setup ==")
	check(current_scene != null and current_scene.scene_file_path == SAT, "the satellite is running")
	var transition: Node = current_scene.find_child("LevelTransition", true, false)
	check(transition != null, "the_satellite.tscn has a LevelTransition")
	if transition == null:
		finish()
		return
	check(transition.trigger_dialogue_id == TRIGGER, "it's triggered by %s ('Off I go then!')" % TRIGGER)
	check(transition.next_scene == APARTMENTS, "it leads to The Apartments")
	check(transition.duration > 0.0, "it shows for a set time (%.1f s, set in the scene)" % transition.duration)
	check(not transition.visible, "hidden until triggered")
	var screen: AnimatedSprite2D = transition.screen
	var tex := screen.sprite_frames.get_frame_texture("default", 0)
	check(tex != null and tex.get_size() == Vector2(1080, 720), "full-screen 1080x720 animation frame")
	transition.duration = 0.5 # keep the test quick

	var ph := phone_of(current_scene)
	check(ph != null, "the satellite has the phone")
	if ph != null:
		ph.load_state({"charge": 5})

	print("\n== 'Off I go then!' ==")
	var door: Node = current_scene.find_child("Door", true, false)
	game_data.add_tag("SAT_005_check")
	game_data.add_tag("SAT_TEST_TAG")
	dialogue_controller.object_interacted(door.dialogue_ids)
	check(game_data.dialogue_id == TRIGGER, "the Door says 'Off I go then!' (%s)" % game_data.dialogue_id)
	await create_timer(0.6).timeout # typing finishes
	check(not transition.visible, "nothing happens while the line is still up")
	await press("interact") # closes the line
	check(transition.visible and transition.is_playing and screen.is_playing(), "pressing E starts the full-screen animation")
	check(game_data.is_in_cutscene, "input is blocked during it")
	await press("phone")
	check(not game_data.is_using_phone, "the phone can't be opened during it")
	await create_timer(0.2).timeout
	check(current_scene.scene_file_path == SAT, "still on the satellite before the time is up")

	var waited := 0.0
	while (current_scene == null or current_scene.scene_file_path != APARTMENTS) and waited < 5.0:
		await create_timer(0.1).timeout
		waited += 0.1
	await frames(5)

	print("\n== The Apartments ==")
	check(current_scene != null and current_scene.scene_file_path == APARTMENTS, "then The Apartments loads")
	check(not game_data.is_in_cutscene, "input works again")
	check(game_data.has_tag("SAT_TEST_TAG") and game_data.has_tag("SAT_005_check"), "dialogue tags carried over")
	check(not game_data.has_tag("OLD_APARTMENTS_TAG"), "an old Apartments save was NOT loaded over the new progress")
	var ph2 := phone_of(current_scene)
	check(ph2 != null and ph2.charge == 5, "the phone's battery carried over (%s)" % [ph2.charge if ph2 else "no phone"])
	var saved := JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE)) as Dictionary
	check(saved != null and saved.get("scene", "") == APARTMENTS, "the game saved in The Apartments, so Load Game continues there")
	check(saved != null and (saved["game"]["dialogue_tags"] as Array).has("SAT_TEST_TAG"), "...with the carried-over tags")

	finish()
