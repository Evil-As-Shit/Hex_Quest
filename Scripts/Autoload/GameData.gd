# Autoloaded Singleton
extends Node
## Shared game state. Anything that must survive a save/load goes through
## save_state()/load_state() here, or lives on a node in the "persist" group (see SaveManager).

const DIALOGUE_PATH := "res://Assets/Data/dialogue.txt"
# preload (instead of the global class name) so this autoload also works on a fresh clone,
# before Godot has built its global class cache.
const _Parser := preload("res://Scripts/Core/DialogueParser.gd")

var dict_dialogue: Dictionary = {}

var time_dialogue: float = 0.025 # seconds per typed character
var dialogue_id: String = ""
var dialogue_choice_id: int = 0

var flag_displaying_dialogue: bool = false
var flag_waiting_dialogue_prompt: bool = false
var flag_waiting_dialogue_next: bool = false

var is_using_phone: bool = false
var is_in_dialogue: bool = false
## While true, the line on screen can't be skipped with interact; release_dialogue() advances it.
var dialogue_held: bool = false
## A full-screen cutscene/transition is playing: no moving, interacting or phone.
var is_in_cutscene: bool = false

## Tags unlocked by dialogue. Used as a set (the value is always true), so lookups are
## O(1) and showing the same line twice can't add duplicates.
var dialogue_tags: Dictionary = {}

var move_input_vector: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Loaded once here for every scene (GameController / tests no longer need to).
	dict_dialogue = _Parser.loadDB(DIALOGUE_PATH, "dialogue")
	


## Systems that care about a tag (the phone battery, for example) listen to
## SignalController.tag_added instead of being special-cased here.
func add_tag(tag: String) -> void:
	if dialogue_tags.has(tag):
		return
	dialogue_tags[tag] = true
	SignalController.tag_added.emit(tag)


## For tags that describe a state that can end (like PHONE_CHARGE_ZERO), not a one-off event.
func remove_tag(tag: String) -> void:
	if dialogue_tags.erase(tag):
		SignalController.tag_removed.emit(tag)


func has_tag(tag: String) -> bool:
	return dialogue_tags.has(tag)


## Keeps the current dialogue line on screen until release_dialogue() is called (for lines that wait
## on something happening, like "Charging phone..."). Only for lines without choices.
func hold_dialogue() -> void:
	dialogue_held = true


## Ends a hold and moves the held line on (to its divert, or closes it if it's an end line).
func release_dialogue() -> void:
	if not dialogue_held:
		return
	dialogue_held = false
	SignalController.dialogue_released.emit()


func save_state() -> Dictionary:
	return {"dialogue_tags": dialogue_tags.keys()}


func load_state(data: Dictionary) -> void:
	dialogue_tags.clear()
	for tag in data.get("dialogue_tags", []):
		dialogue_tags[str(tag)] = true
	SignalController.tags_loaded.emit()


## Back to a fresh new game (dialogue loaded, nothing unlocked).
func reset() -> void:
	dialogue_tags.clear()
	dialogue_id = ""
	dialogue_choice_id = 0
	flag_displaying_dialogue = false
	flag_waiting_dialogue_prompt = false
	flag_waiting_dialogue_next = false
	is_using_phone = false
	is_in_dialogue = false
	dialogue_held = false
	is_in_cutscene = false
	move_input_vector = Vector2.ZERO
	SignalController.tags_loaded.emit()
