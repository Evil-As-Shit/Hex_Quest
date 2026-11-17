extends SceneTree
## Headless test for the main menu (New Game / Load Game):
##     godot --headless -s res://Tests/menu_test.gd
## Uses its own save file (user://menu_test_save.json); your real save is untouched.

const MENU := "res://The Game/0 - Main Menu/Main_Menu.tscn"
const SAT := "res://The Game/1 - TheSat/Scenes/the_satellite.tscn"
const TEST_SAVE := "user://menu_test_save.json"

var failures := 0
var finished := false
var save_manager: Node
var game_data: Node
var error_log := ErrorCounter.new()


## Collects every engine/script error printed while the test runs: a script error (like calling a method on a
## null viewport) doesn't stop the test by itself, so the test fails on any error at the end instead.
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
		root.push_input(e) # straight to the viewport (headless mode doesn't flush Input's event buffer)
		await frames(1)


func write_fake_save(tag: String) -> void:
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "saved_at": "test", "scene": SAT, "game": {"dialogue_tags": [tag]}, "nodes": {}}))
	f.close()


func open_menu() -> Node:
	change_scene_to_file(MENU)
	await frames(3)
	return current_scene.find_child("MainMenuBox", true, false) if current_scene else null


func _run() -> void:
	save_manager.save_path = TEST_SAVE
	DirAccess.remove_absolute(TEST_SAVE)

	print("\n== Menu, no save ==")
	var box := await open_menu()
	check(box != null, "Main_Menu.tscn contains the MainMenuBox")
	if box == null:
		finish()
		return
	check(current_scene.scene_file_path == MENU, "the menu is running")
	check(ProjectSettings.get_setting("application/run/main_scene") == ResourceUID.path_to_uid(MENU) or ProjectSettings.get_setting("application/run/main_scene") == MENU, "the menu is the project's startup scene")
	check(box.title.text == "Hex Quest" and box.title.visible, "title says 'Hex Quest'")
	check(box.new_game_button.text == "New Game" and box.load_game_button.text == "Load Game", "New Game and Load Game buttons")
	check(box.new_game_button.has_focus(), "New Game has focus")
	check(box.load_game_button.disabled, "Load Game is greyed out with no save")
	check(not save_manager._enabled, "saving is off on the menu")

	print("\n== New Game with a save asks first ==")
	write_fake_save("OLD_GAME_TAG")
	box.refresh()
	check(not box.load_game_button.disabled, "Load Game is enabled once there's a save")
	box.new_game_button.pressed.emit()
	check(box.confirm.visible and not box.buttons.visible and box.confirm_no.has_focus(), "New Game shows the 'overwrite?' question, with No focused")
	box.confirm_no.pressed.emit()
	check(not box.confirm.visible and box.buttons.visible and box.new_game_button.has_focus(), "No goes back to the menu")
	check(current_scene.scene_file_path == MENU and FileAccess.file_exists(TEST_SAVE), "...still on the menu, save untouched")

	# Real key presses this time (E), like a player: Yes changes scene from inside the input handler.
	await press("interact") # New Game (focused)
	check(box.confirm.visible and box.confirm_no.has_focus(), "E on New Game opens the question")
	await press("ui_cancel")
	check(not box.confirm.visible and box.new_game_button.has_focus(), "Esc backs out of the question")
	await press("interact")
	box.confirm_yes.grab_focus()
	await press("interact") # Yes: this used to error (get_viewport() was null once the menu left the tree)
	await frames(6)
	check(current_scene != null and current_scene.scene_file_path == SAT, "Yes starts TheSat (%s)" % (current_scene.scene_file_path if current_scene else "none"))
	check(not game_data.has_tag("OLD_GAME_TAG"), "...as a fresh game: the old save was not loaded")
	check(save_manager._enabled, "...with saving on")

	print("\n== Load Game ==")
	write_fake_save("OLD_GAME_TAG")
	box = await open_menu()
	check(box != null and not save_manager._enabled, "back on the menu, saving off again")
	if box != null:
		box.load_game_button.grab_focus()
		await press("interact") # Load Game by key, also a scene change from inside the input handler
		await frames(8)
		check(current_scene != null and current_scene.scene_file_path == SAT, "Load Game opens the saved scene")
		check(game_data.has_tag("OLD_GAME_TAG"), "...and restores the save")

	print("\n== The menu never saves itself ==")
	box = await open_menu()
	var before := FileAccess.get_file_as_string(TEST_SAVE)
	check(not save_manager.save_game(), "save_game() refuses on the menu")
	check(FileAccess.get_file_as_string(TEST_SAVE) == before, "...and the save file is unchanged")

	finish()
