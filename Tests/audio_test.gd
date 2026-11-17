extends SceneTree
## Headless test for AudioManager and where each sound plays:
##     godot --headless -s res://Tests/audio_test.gd
## (Headless Godot has no sound card, so this checks WHEN sounds are triggered, via AudioManager.sound_played.)

const APARTMENTS := "res://The Game/2 - The Apartments/The Apartments.tscn"
const MENU := "res://The Game/0 - Main Menu/Main_Menu.tscn"
const TEST_SAVE := "user://audio_test_save.json"

var failures := 0
var finished := false
var audio: Node
var game_data: Node
var signals: Node
var save_manager: Node
var played: Array[StringName] = []
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
	audio = root.get_node("AudioManager")
	game_data = root.get_node("GameData")
	signals = root.get_node("SignalController")
	save_manager = root.get_node("SaveManager")
	audio.sound_played.connect(func(n: StringName): played.append(n))
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


func count(sound: StringName) -> int:
	return played.count(sound)


func phone_of(scene: Node) -> Node:
	for n in scene.find_children("*", "Control", true, false):
		if n.get_script() != null and n.get_script().resource_path == "res://Scripts/UI/Phone.gd":
			return n
	return null


func _run() -> void:
	save_manager.save_path = TEST_SAVE
	DirAccess.remove_absolute(TEST_SAVE)
	await frames(1) # autoloads run _ready() after _initialize(): AudioManager's players don't exist before this

	print("\n== Setup ==")
	check(AudioServer.get_bus_index(&"Music") >= 0 and AudioServer.get_bus_index(&"SFX") >= 0, "Music and SFX buses exist")
	check(audio._music.bus == &"Music" and audio._talk.bus == &"SFX" and audio._sfx[0].bus == &"SFX", "music on Music, effects and talking on SFX")
	var all_loaded := true
	for sfx_name in audio.SFX:
		all_loaded = all_loaded and audio.SFX[sfx_name] is AudioStream
	check(all_loaded and audio.SFX.size() == 6, "all 6 sound effects load (%s)" % [audio.SFX.keys()])
	check(audio.TALK.resource_path.ends_with("blip.wav"), "the talking sound is blip.wav")

	game_data.reset()
	save_manager._skip_next_load = true
	change_scene_to_file(APARTMENTS)
	await frames(5)
	var box: Control = current_scene.get_node_or_null("UI/DialogueBox")
	var ph := phone_of(current_scene)
	if box == null or ph == null:
		check(false, "found the dialogue box and phone")
		finish()
		return

	print("\n== Talking blip ==")
	var line := "Hi, Hexy... ok?" # spaces and punctuation stay silent
	var letters := 0
	for c in line:
		if c.to_upper() != c.to_lower():
			letters += 1
	game_data.dict_dialogue["T_AUDIO"] = {"id": "T_AUDIO", "text": line, "expression": null, "isEnd": true}
	game_data.time_dialogue = 0.05 # slow enough that each frame shows at most one new character
	played.clear()
	signals.display_dialogue.emit("T_AUDIO")
	await create_timer(line.length() * 0.05 + 0.3).timeout
	check(letters == 8 and count(&"blip") == letters, "one blip per letter, none for spaces/punctuation (%d blips for %d letters)" % [count(&"blip"), letters])
	check(not audio.is_talking(), "the blip stops when the line has finished typing")
	signals.close_dialogue.emit()
	game_data.dict_dialogue["T_SILENT"] = {"id": "T_SILENT", "text": "... !? ...", "expression": null, "isEnd": true}
	played.clear()
	signals.display_dialogue.emit("T_SILENT")
	await create_timer(0.8).timeout
	check(count(&"blip") == 0, "a line with no letters is silent")
	signals.close_dialogue.emit()
	game_data.dict_dialogue["T_LONG"] = {"id": "T_LONG", "text": "A long line that gets skipped part way through it.", "expression": null, "isEnd": true}
	signals.display_dialogue.emit("T_LONG")
	await create_timer(0.3).timeout
	await press("interact") # skip the typing
	await create_timer(0.15).timeout
	played.clear()
	await create_timer(0.3).timeout
	check(count(&"blip") == 0 and not audio.is_talking(), "skipping with E stops the blips")
	signals.close_dialogue.emit()
	game_data.time_dialogue = 0.025

	print("\n== Phone ==")
	played.clear()
	signals.toggle_phone.emit()
	check(count(&"phone_open") == 1, "opening the phone: phone_open")
	signals.toggle_phone.emit()
	check(count(&"phone_close") == 1, "closing it: phone_close")
	ph.load_state({"charge": 1})
	played.clear()
	ph.add_charge(-1)
	check(count(&"phone_ded") == 1, "battery runs out: phone_ded")
	played.clear()
	ph.charging_sprite.speed_scale = 40.0
	game_data.add_tag("PHONE_CHARGE")
	var waited := 0.0
	while ph.battery_state == 1 and waited < 5.0:
		await create_timer(0.05).timeout
		waited += 0.05
	ph.charging_sprite.speed_scale = 1.0
	check(count(&"phone_charged") == 1, "charging finishes: phone_charged")
	played.clear()
	signals.toggle_phone.emit()
	check(count(&"phone_open") == 1 and count(&"phone_boot") == 0, "opening the charged phone: phone_open at once, boot sound not yet")
	check(is_equal_approx(ph.boot_sound_delay, 1.0), "boot sound delay is 1 second")
	await create_timer(0.8).timeout
	check(count(&"phone_boot") == 0, "...still no boot sound at 0.8 s")
	await create_timer(0.35).timeout
	check(count(&"phone_boot") == 1 and played.find(&"phone_open") < played.find(&"phone_boot"), "phone_boot plays after the 1 s delay")
	var on_wait := 0.0
	while not ph.is_powered_on and on_wait < 3.0:
		await create_timer(0.05).timeout
		on_wait += 0.05
	signals.toggle_phone.emit()
	await frames(2)
	played.clear()
	signals.toggle_phone.emit()
	await create_timer(1.2).timeout
	check(count(&"phone_boot") == 0, "...and no boot sound once it's on")
	signals.toggle_phone.emit()
	# Dies again within the delay: the pending boot sound is dropped
	ph.add_charge(-ph.max_charge)
	ph.add_charge(ph.max_charge)
	await frames(2)
	played.clear()
	signals.toggle_phone.emit() # starts turning on
	ph.add_charge(-ph.max_charge) # ...and the battery runs out straight away
	await create_timer(1.2).timeout
	check(count(&"phone_boot") == 0, "if the phone dies during the delay, no boot sound")
	signals.toggle_phone.emit()

	print("\n== ui_noise: phone ==")
	ph.load_state({"charge": ph.max_charge}) # on, no animation
	played.clear()
	signals.toggle_phone.emit()
	await frames(2)
	check(ph.home.has_focus() and count(&"ui_noise") == 0, "opening the phone (focus on Home) is silent")
	await press("ui_up")
	var phone_focus := ph.get_viewport().gui_get_focus_owner()
	check(phone_focus != null and phone_focus != ph.home and count(&"ui_noise") == 1, "moving the selection on the phone plays ui_noise (now on %s)" % [phone_focus.name if phone_focus else "nothing"])
	await press("interact") # pressing a phone button
	check(count(&"ui_noise") == 1, "pressing a phone button doesn't")
	signals.toggle_phone.emit()

	print("\n== ui_noise: dialogue choices ==")
	game_data.dict_dialogue["T_CHOICE"] = {"id": "T_CHOICE", "text": "Pick", "expression": null, "choices": ["A", "B"], "choice_0": ["T_SILENT"], "choice_1": ["T_SILENT"]}
	signals.display_dialogue.emit("T_CHOICE")
	await create_timer(0.4).timeout # typed; the choices appear with the first one focused
	played.clear()
	await frames(2)
	check(box.get_node("Button0").has_focus() and count(&"ui_noise") == 0, "choices appearing is silent")
	await press("ui_right")
	check(box.get_node("Button1").has_focus() and count(&"ui_noise") == 1, "moving between choices plays ui_noise")
	await press("interact") # choose
	await frames(2)
	check(count(&"ui_noise") == 1, "choosing an option doesn't")
	await press("interact") # finish typing the next line
	await press("interact") # advance / close it
	check(count(&"ui_noise") == 1, "advancing dialogue doesn't")
	signals.close_dialogue.emit()

	print("\n== Menu music ==")
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE) # a save, so Load Game can be selected
	f.store_string("{\"version\":1,\"scene\":\"\",\"game\":{},\"nodes\":{}}")
	f.close()
	played.clear()
	change_scene_to_file(MENU)
	await frames(5)
	var menu: Node = current_scene.find_child("MainMenuBox", true, false)
	check(count(&"music") == 1 and audio.current_music() == menu.music and audio._music.playing, "the menu starts its music (%s)" % audio.current_music().get_file())
	check(is_equal_approx(audio._music.volume_db, 0.0), "at full volume straight away, no fade-in (%.1f dB)" % audio._music.volume_db)
	check(audio._music.stream != null and audio._music.stream.get_length() > 300.0, "it's the full track (%.0f s)" % (audio._music.stream.get_length() if audio._music.stream else 0.0))

	print("\n== ui_noise: main menu ==")
	check(menu.new_game_button.has_focus() and count(&"ui_noise") == 0, "the menu opening (focus on New Game) is silent")
	await press("ui_down")
	check(menu.load_game_button.has_focus() and count(&"ui_noise") == 1, "down to Load Game: ui_noise")
	await press("ui_up")
	check(menu.new_game_button.has_focus() and count(&"ui_noise") == 2, "up to New Game: ui_noise")
	await press("ui_up") # already at the top: the focus doesn't move
	check(count(&"ui_noise") == 2, "no sound when the selection can't move")
	await press("interact") # New Game with a save: the question opens with No focused
	check(menu.confirm_no.has_focus() and count(&"ui_noise") == 2, "the question opening (focus on No) is silent")
	await press("ui_left")
	check(menu.confirm_yes.has_focus() and count(&"ui_noise") == 3, "No -> Yes: ui_noise")
	await press("ui_cancel")
	check(menu.new_game_button.has_focus() and count(&"ui_noise") == 3, "Esc back to the menu is silent")

	DirAccess.remove_absolute(TEST_SAVE)
	menu.refresh()
	menu.new_game_button.pressed.emit() # no save now, so New Game starts straight away
	check(audio.current_music() == "", "New Game fades the music out")
	await create_timer(1.3).timeout
	check(not audio._music.playing, "...and it has stopped after the fade")

	finish()
