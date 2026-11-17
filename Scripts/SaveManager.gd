# Autoloaded Singleton
extends Node
## Saves and loads the game to a single JSON file in the player's user folder.
##
## How it works: any node that has something worth saving joins the "persist" group and provides
##     get_save_id() -> String      (unique and stable)
##     save_state()  -> Dictionary  (JSON-friendly values only: numbers, strings, bools, arrays)
##     load_state(data: Dictionary)
## SaveManager collects those, plus GameData, into the file. To make something new saveable,
## add_to_group(SaveManager.GROUP) in its _ready() and add those three functions.
##
## Controls: F5 quick save, F9 quick load, F10 deletes the save and restarts (debug builds only).

signal game_saved
signal game_loaded

const GROUP := &"persist"
const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

# Dev switches
const LOAD_ON_START := true # restore the last save when the game scene starts
const AUTOSAVE_ON_REVEAL := true # save whenever a room is revealed
const AUTOSAVE_ON_QUIT := true # save on Esc / closing the window

## Where the save lives. A var (not just the const) so tests can point it somewhere else.
var save_path: String = SAVE_PATH

var _enabled: bool = false # only game scenes that contain a GameController save/load
var _is_loading: bool = false
var _toast: Label
var _toast_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SignalController.room_revealed.connect(_on_room_revealed)
	_build_toast()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_save"):
		if not _enabled:
			_show_toast("Saving is off in this scene")
		elif save_game():
			_show_toast("Game saved")
	elif event.is_action_pressed("quick_load"):
		if not _enabled:
			_show_toast("Loading is off in this scene")
		elif has_save():
			load_game()
		else:
			_show_toast("No save to load")
	elif event.is_action_pressed("delete_save") and OS.is_debug_build():
		new_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and AUTOSAVE_ON_QUIT:
		save_game()


## Called by GameController when a game scene is ready.
func register_scene() -> void:
	_enabled = true
	if LOAD_ON_START and has_save():
		# Deferred so every node in the scene has finished _ready() first.
		load_game.call_deferred(false)


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func quit_game() -> void:
	if AUTOSAVE_ON_QUIT:
		save_game()
	get_tree().quit()


## Stable id for saving a node that doesn't pick its own: its path inside the current scene.
func node_id(node: Node) -> String:
	var scene := get_tree().current_scene
	if scene != null and scene.is_ancestor_of(node):
		return str(scene.get_path_to(node))
	return str(node.get_path())


# --- Saving ---

func save_game() -> bool:
	var scene := get_tree().current_scene
	if not _enabled or _is_loading or scene == null:
		return false

	var nodes := {}
	for node in get_tree().get_nodes_in_group(GROUP):
		if node.has_method("save_state"):
			nodes[node.get_save_id()] = node.save_state()

	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"scene": scene.scene_file_path,
		"game": GameData.save_state(),
		"nodes": nodes,
	}

	# Write to a temp file, then rename over the real one, so a crash mid-save can't corrupt it.
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: can't write %s (%s)" % [temp_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(temp_path, save_path)
	if err != OK:
		push_error("SaveManager: couldn't finish saving (%s)" % error_string(err))
		return false
	game_saved.emit()
	return true


# --- Loading ---

## Restores the saved game. With allow_scene_change = false (used on startup) it only loads
## a save that belongs to the scene that's already running.
func load_game(allow_scene_change: bool = true) -> void:
	if not _enabled or _is_loading:
		return
	var data := _read_save()
	if data.is_empty():
		return

	var scene := get_tree().current_scene
	var wanted_scene: String = data.get("scene", "")
	if wanted_scene != "" and scene != null and scene.scene_file_path != wanted_scene:
		if not allow_scene_change:
			return
		_is_loading = true
		if get_tree().change_scene_to_file(wanted_scene) != OK:
			push_error("SaveManager: can't open saved scene %s" % wanted_scene)
			_is_loading = false
			return
		await get_tree().process_frame # old scene freed
		await get_tree().process_frame # new scene ready

	_is_loading = true
	_apply(data)
	_is_loading = false
	game_loaded.emit()
	_show_toast("Game loaded")


func _apply(data: Dictionary) -> void:
	_close_open_ui()
	GameData.load_state(data.get("game", {}))
	var saved_nodes: Dictionary = data.get("nodes", {})
	for node in get_tree().get_nodes_in_group(GROUP):
		if not node.has_method("load_state"):
			continue
		var id: String = node.get_save_id()
		if saved_nodes.has(id): # nodes added since the save was made keep their defaults
			node.load_state(saved_nodes[id])


func _read_save() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: can't read %s (%s)" % [save_path, error_string(FileAccess.get_open_error())])
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		push_error("SaveManager: save file is corrupt (%s)" % json.get_error_message())
		return {}
	var data: Dictionary = json.data
	var version := int(data.get("version", 0))
	if version > SAVE_VERSION:
		push_error("SaveManager: save is from a newer version of the game (v%d)" % version)
		return {}
	return _migrate(data, version)


## Upgrade old saves here when the format changes, e.g.
##     if from_version < 2: data["game"]["something"] = default; data["version"] = 2
func _migrate(data: Dictionary, _from_version: int) -> Dictionary:
	return data


## Fresh start: delete the save, reset the game state, reload the scene.
func new_game() -> void:
	if has_save():
		DirAccess.remove_absolute(save_path)
	GameData.reset()
	_close_open_ui()
	get_tree().reload_current_scene()
	_show_toast("Save deleted - new game")


# Close the phone / dialogue box through their normal signals so they tidy up after themselves.
func _close_open_ui() -> void:
	if GameData.is_using_phone:
		SignalController.toggle_phone.emit()
	if GameData.is_in_dialogue:
		SignalController.close_dialogue.emit()


func _on_room_revealed(_room_id: StringName) -> void:
	if AUTOSAVE_ON_REVEAL:
		save_game()


# --- "Game saved" toast ---

func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_toast = Label.new()
	_toast.position = Vector2(20, 14)
	_toast.modulate.a = 0.0
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	layer.add_child(_toast)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.2)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
