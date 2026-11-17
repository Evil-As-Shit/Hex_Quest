extends SceneTree
## Headless smoke test for the room reveal, interactions, dialogue and save/load.
## Run from the project folder:
##     godot --headless -s res://Tests/smoke_test.gd
## Prints PASS / FAIL per check and exits with a non-zero code if anything failed.
## It uses its own save file (user://smoke_test_save.json), so your real save is untouched.

const SCENE := "res://The Game/2 - The Apartments/The Apartments.tscn"
const TEST_SAVE := "user://smoke_test_save.json"

var failures := 0
var scene: Node
# Autoloads aren't visible to the compiler in a -s script, so fetch them from the tree.
var save_manager: Node
var game_data: Node
var signals: Node
var dialogue_controller: GDScript
var finished := false


func _initialize() -> void:
	save_manager = root.get_node("SaveManager")
	game_data = root.get_node("GameData")
	signals = root.get_node("SignalController")
	dialogue_controller = load("res://Scripts/Core/DialogueController.gd")
	# A script error inside the awaiting _run() silently abandons it, so the quit below would never be
	# reached. This watchdog makes sure the test always ends, with a failure, instead of hanging.
	create_timer(120.0).timeout.connect(_on_watchdog)
	_run()


func _on_watchdog() -> void:
	check(false, "test finished within 120s (a script error or a stuck wait aborted the run)")
	finish()


func check(condition: bool, label: String) -> void:
	print(("  PASS  " if condition else "  FAIL  ") + label)
	if not condition:
		failures += 1


## Fails (instead of crashing the run) when a node the test needs isn't there.
func need(node: Node, label: String) -> bool:
	check(node != null, "found " + label)
	return node != null


func finish() -> void:
	if finished:
		return
	finished = true
	DirAccess.remove_absolute(TEST_SAVE)
	print("\n%s (%d failure%s)" % ["ALL PASSED" if failures == 0 else "FAILED", failures, "" if failures == 1 else "s"])
	quit(0 if failures == 0 else 1)


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
	return scene.get_node_or_null("YSort/CharacterBody2D")


func room() -> Node:
	return scene.get_node_or_null("YSort/Room1/Room1")


## The NPC-script object that Room1 hides (its name has changed over time, so find it by script).
func npc() -> Node:
	var r := room()
	if r == null:
		return null
	for path in r.reveal_nodes:
		var n := r.get_node_or_null(path)
		if n != null and n.get_script() != null and n.get_script().resource_path.ends_with("/NPC.gd") and n.get_node_or_null("Sprite") != null:
			return n
	return null


## The phone (the UI node running Phone.gd), found by script since it's nested in the UI scene.
func phone() -> Node:
	var ui := scene.get_node_or_null("UI")
	if ui == null:
		return null
	for n in ui.find_children("*", "Control", true, false):
		if n.get_script() != null and n.get_script().resource_path == "res://Scripts/UI/Phone.gd":
			return n
	return null


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
	if not (need(hexy(), "Hexy") and need(room(), "Room1") and need(npc(), "an NPC hidden by Room1")):
		finish()
		return
	check(save_manager._enabled, "GameController enabled saving for the scene")
	check(game_data.dict_dialogue.size() > 0, "dialogue loaded by GameData (%d entries)" % game_data.dict_dialogue.size())
	check(not room().is_revealed, "Room1 starts hidden")
	check(room()._items.size() == 9 or room()._items.size() > 6, "Room1 collected its sprites (%d)" % room()._items.size())
	check(npc().get_node("Sprite").material != null, "NPC sprite is hidden with the room (it used to float in the void)")
	# (the old balcony NPC is gone; the Balcony's own sprite is likewise not part of Room1)
	var balcony_sprite := scene.get_node_or_null("YSort/Balcony/Balcony_Sprite")
	check(balcony_sprite != null and balcony_sprite.material == null, "the Balcony stays visible (not part of Room1)")
	check(hexy()._area_node != null and hexy()._area_node.name == "Balcony", "Hexy starts in the Balcony area")
	# a new game starts with a dead phone, and the phone keeps PHONE_CHARGE_ZERO set while it is
	if need(phone(), "the phone (Phone.gd under UI)"):
		check(phone().battery_state == 0 and game_data.has_tag("PHONE_CHARGE_ZERO"), "fresh scene: phone battery is DEAD and PHONE_CHARGE_ZERO is set")

	print("\n== Room reveal ==")
	var start_pos: Vector2 = hexy().global_position
	hexy().global_position = Vector2(-20, -30) # inside Room1
	await frames(3)
	check(room().is_revealed, "walking into Room1 reveals it")
	check(room()._fade_material != null, "fade is in progress right after entering")
	await create_timer(1.0).timeout
	check(room()._fade_material == null, "fade finished and the shader material was removed")
	check(npc().get_node("Sprite").material == null, "NPC sprite back to a normal material")
	check(save_manager.has_save(), "autosave happened on reveal")

	print("\n== Interactions ==")
	var lamp: Node = scene.get_node_or_null("YSort/Lamp")
	var chair: Node = scene.get_node_or_null("YSort/Chair")
	if not (need(lamp, "Lamp") and need(chair, "Chair")):
		finish()
		return
	await stand_on(lamp)
	await press("interact")
	check(lamp.is_on, "E toggles the lamp on")
	await stand_on(chair)
	await press("interact")
	check(hexy().is_sitting, "E on a chair sits Hexy down")
	check(hexy().collision_shape.disabled, "collision is disabled while sitting")
	var sit_pos: Vector2 = hexy().global_position

	print("\n== Save / load round trip ==")
	DirAccess.remove_absolute(TEST_SAVE)
	var tags_before: int = game_data.dialogue_tags.size() # (the phone may keep a tag of its own set)
	game_data.add_tag("TEST_TAG")
	game_data.add_tag("TEST_TAG") # duplicates must not pile up
	check(game_data.dialogue_tags.size() == tags_before + 1 and game_data.has_tag("TEST_TAG"), "tags are a set (no duplicates)")
	check(save_manager.save_game(), "save_game() succeeds")
	var text := FileAccess.get_file_as_string(TEST_SAVE)
	var saved: Dictionary = JSON.parse_string(text)
	check(saved.has("version") and saved["nodes"].has("hexy") and saved["nodes"].has("room:Room1"), "save file has Hexy and Room1")
	check(not FileAccess.file_exists(TEST_SAVE + ".tmp"), "no temp file left behind")

	await stop_scene()
	game_data.reset()
	# (only the phone's dead-battery tag may be re-added by a reset)
	check(not game_data.has_tag("TEST_TAG") and game_data.dialogue_tags.keys().all(func(t): return t == "PHONE_CHARGE_ZERO"), "GameData reset clears tags")
	await start_scene() # a brand new session: everything is back to defaults...
	if not (need(hexy(), "Hexy (after restart)") and need(room(), "Room1 (after restart)") and need(npc(), "the NPC (after restart)") and need(scene.get_node_or_null("YSort/Lamp"), "Lamp (after restart)") and need(scene.get_node_or_null("InputController"), "InputController")):
		finish()
		return
	check(not room().is_revealed or save_manager.has_save(), "(new scene)")
	await frames(3) # ...then GameController's deferred load restores the save
	check(room().is_revealed, "Room1 is still revealed after restart")
	check(room()._fade_material == null and npc().get_node("Sprite").material == null, "revealed instantly, no fade or shader left")
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
	check(not room().is_revealed and npc().get_node("Sprite").material != null, "loading a save made before Room1 was revealed hides it again")
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
	var box: Control = scene.get_node_or_null("UI/DialogueBox")
	if not need(box, "UI/DialogueBox"):
		finish()
		return
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

	print("\n== Phone battery ==")
	var ph := phone()
	if need(ph, "the phone (Phone.gd under UI)"):
		var sprite: AnimatedSprite2D = ph.battery_sprite
		var overlay: AnimatedSprite2D = ph.charging_sprite
		var screen: AnimatedSprite2D = ph.screen
		var top_frame := sprite.sprite_frames.get_frame_count("Charges") - 1
		game_data.reset() # a fresh game: dead battery, phone off
		check(ph.battery_state == 0 and ph.charge == 0 and sprite.animation == &"Ded" and game_data.has_tag("PHONE_CHARGE_ZERO"), "reset: battery dead ('Ded'), PHONE_CHARGE_ZERO set")
		check(screen.sprite_frames.has_animation(ph.ANIM_OFF) and screen.sprite_frames.has_animation(ph.ANIM_ON), "Phone_Bool has the turn-off/on animations Phone.gd uses (%s, %s)" % [ph.ANIM_OFF, ph.ANIM_ON])
		check(not ph.is_powered_on and screen.visible and screen.animation == ph.ANIM_OFF and ph.home.disabled, "dead phone is switched off: black screen, buttons disabled")
		check(ph.max_charge == 1 + sprite.sprite_frames.get_frame_count("Charges"), "levels: dead, dying, then one per 'Charges' frame (max %d)" % ph.max_charge)
		# Q still opens and closes a dead phone, but it stays off
		signals.toggle_phone.emit()
		check(game_data.is_using_phone and not ph.is_powered_on and not ph._powering_on and not ph.home.has_focus(), "a dead phone opens, stays off, Home not focused")
		signals.toggle_phone.emit()
		check(not game_data.is_using_phone, "...and closes")

		game_data.load_state({"dialogue_tags": ["PHONE_CHARGE", "PHONE_CHARGE_FULL"]})
		check(ph.battery_state == 3 and ph.charge == ph.max_charge and not game_data.has_tag("PHONE_CHARGE_ZERO"), "loading charged tags: battery FULL")
		check(sprite.animation == &"Charges" and sprite.frame == top_frame, "FULL battery shows the last 'Charges' frame (frame %d)" % sprite.frame)
		check(ph.is_powered_on and not screen.visible and not ph.home.disabled, "a charged phone loads switched on")
		game_data.load_state({"dialogue_tags": ["PHONE_CHARGE"]}) # saved mid-charge (quit while charging)
		check(ph.battery_state == 0 and not game_data.has_tag("PHONE_CHARGE"), "a save from mid-charge loads as dead, ready to charge again")
		ph.load_state({"charge": 5}) # the phone's own save data
		check(ph.charge == 5 and sprite.animation == &"Charges" and sprite.frame == 3 and ph.is_powered_on, "a saved level 5 loads as 'Charges' frame 3, phone on")
		check(ph.save_state() == {"charge": 5} and ph.is_in_group("persist"), "the phone saves its level")

		# Draining: down to 'Dying', then dead -> the phone switches itself off
		ph.add_charge(-(ph.charge - 1))
		check(ph.charge == 1 and sprite.animation == &"Dying" and sprite.is_playing() and ph.is_powered_on, "level 1: 'Dying' plays, phone still on")
		# (this phone was powered on by a load, with no animation: Phone_Bool is still parked on the last
		# turn-off frame from startup, which is exactly when the turn-off animation used to get skipped)
		var off_frames_seen := {}
		var see_frame := func(): off_frames_seen[screen.frame] = true
		screen.frame_changed.connect(see_frame)
		ph.add_charge(-1)
		check(ph.charge == 0 and sprite.animation == &"Ded" and game_data.has_tag("PHONE_CHARGE_ZERO"), "level 0: 'Ded'")
		check(not ph.is_powered_on and screen.visible and screen.animation == ph.ANIM_OFF and screen.is_playing() and ph.home.disabled, "...and the phone plays its turn-off animation and locks its buttons")
		check(screen.frame == 0, "the turn-off animation starts from its first frame (frame %d)" % screen.frame)
		var off_count := screen.sprite_frames.get_frame_count(ph.ANIM_OFF)
		var off_wait := 0.0
		while screen.is_playing() and off_wait < 3.0:
			await create_timer(0.05).timeout
			off_wait += 0.05
		screen.frame_changed.disconnect(see_frame)
		off_frames_seen[0] = true # frame 0 is shown without a frame_changed
		check(off_frames_seen.size() == off_count and screen.frame == off_count - 1, "...shows all %d frames and stays on the last (saw %d)" % [off_count, off_frames_seen.size()])
		# F6 (debug builds): drain by one
		ph.add_charge(3)
		await press("debug_drain_battery")
		check(ph.charge == 2, "F6 (debug_drain_battery) drains the battery by one (3 -> %d)" % ph.charge)
		ph.add_charge(ph.max_charge)
		check(game_data.has_tag("PHONE_CHARGE_FULL"), "refilled: PHONE_CHARGE_FULL set")
		ph.add_charge(-1)
		check(not game_data.has_tag("PHONE_CHARGE_FULL"), "below full: PHONE_CHARGE_FULL cleared (so the charger offers again)")

		# The whole charger flow, as the player sees it
		var charger: Node = scene.get_node_or_null("YSort/Charger")
		if need(charger, "YSort/Charger"):
			game_data.reset()
			dialogue_controller.object_interacted(charger.dialogue_ids)
			check(game_data.dialogue_id == "ITM010", "dead phone: the charger asks to charge (%s)" % game_data.dialogue_id)
			await create_timer(1.2).timeout # let the question finish typing
			game_data.dialogue_choice_id = 0 # "Yes"
			dialogue_controller.choose()
			check(game_data.dialogue_id == "ITM011" and ph.battery_state == 1 and game_data.dialogue_held, "Yes: 'Charging phone...' shows, battery CHARGING, line held")
			check(overlay.visible and overlay.is_playing() and overlay.animation == &"Charging", "Battery_Charging plays over the battery")
			await create_timer(0.5).timeout # typing done, charge still in its first loop
			await press("interact")
			check(game_data.dialogue_id == "ITM011" and box.visible, "interact can't skip the held 'Charging phone...' line")
			# speed the animation up and record each level change: what the battery shows, and which sweep frame
			# was covering it at that moment
			# (the first step may already have happened at normal speed: note where we are, so only real changes
			# get a sweep frame recorded)
			var steps: Array = [ph.charge] if ph.charge > 0 else []
			var shown_after: Array = ["%s:%d" % [sprite.animation, sprite.frame]] if ph.charge > 0 else []
			var sweep_frames: Array = []
			var record := func():
				if steps.is_empty() or steps[-1] != ph.charge:
					steps.append(ph.charge)
					shown_after.append("%s:%d" % [sprite.animation, sprite.frame])
					sweep_frames.append(overlay.frame)
			overlay.frame_changed.connect(record)
			overlay.speed_scale = 40.0
			var waited := 0.0
			while game_data.dialogue_id != "ITM012" and waited < 10.0:
				await create_timer(0.05).timeout
				waited += 0.05
			overlay.speed_scale = 1.0
			overlay.frame_changed.disconnect(record)
			var expected: Array = range(1, ph.max_charge + 1)
			check(steps == expected, "the battery goes up one level per charging loop, up to full (%s)" % [steps])
			check(shown_after.size() >= 3 and str(shown_after[0]).begins_with("Dying:") and shown_after[1] == "Charges:0" and shown_after[-1] == "Charges:%d" % top_frame, "it shows Dying, then each Charges frame in turn (%s)" % [shown_after])
			check(sweep_frames.all(func(f): return f == ph.charge_step_frame), "every level change happens on sweep frame %d, while it covers the battery (%s)" % [ph.charge_step_frame, sweep_frames])
			check(ph.charge_step_frame == 10, "charge_step_frame is the fully-covering sweep frame (10)")
			check(game_data.dialogue_id == "ITM012" and box.visible and not game_data.dialogue_held, "when full, the dialogue moves on to 'Phone is Charged!!!' by itself")
			check(ph.battery_state == 3 and game_data.has_tag("PHONE_CHARGE_FULL") and not game_data.has_tag("PHONE_CHARGE"), "battery FULL; PHONE_CHARGE_FULL set, PHONE_CHARGE cleared")
			check(not overlay.visible, "the charging overlay is hidden again")
			check(not ph.is_powered_on and screen.visible, "the phone stays off until it's opened")
			signals.close_dialogue.emit()
			dialogue_controller.object_interacted(charger.dialogue_ids)
			check(game_data.dialogue_id == "ITM014", "charged phone: the charger says it's already charged (%s)" % game_data.dialogue_id)
			signals.close_dialogue.emit()

			# Opening the charged phone turns it on (once), then the UI works again
			screen.speed_scale = 20.0
			signals.toggle_phone.emit()
			check(ph._powering_on and screen.visible and screen.animation == &"Turn_Phone_On", "opening it plays the turn-on animation")
			check(ph.home.disabled, "...with the buttons still locked while it plays")
			waited = 0.0
			while not ph.is_powered_on and waited < 5.0:
				await create_timer(0.05).timeout
				waited += 0.05
			screen.speed_scale = 1.0
			check(ph.is_powered_on and not screen.visible and not ph.home.disabled and ph.home.has_focus(), "then the screen clears, buttons work, Home has focus")
			signals.toggle_phone.emit()
			signals.toggle_phone.emit()
			check(ph.is_powered_on and not ph._powering_on and screen.animation == &"Turn_Phone_On" and not screen.visible, "opening it again doesn't replay the turn-on animation")
			signals.toggle_phone.emit()

	print("\n== Robustness ==")
	var bad := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	bad.store_string("{ this is not json")
	bad.close()
	save_manager.load_game()
	await frames(2)
	check(true, "a corrupt save file doesn't crash")
	check(not save_manager._is_loading, "and doesn't leave the loader stuck")

	finish()
