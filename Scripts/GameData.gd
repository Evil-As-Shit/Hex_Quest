# Autoloaded Singleton
extends Node
## Shared game state. Anything that must survive a save/load goes through
## save_state()/load_state() here, or lives on a node in the "persist" group (see SaveManager).

const DIALOGUE_PATH := "res://Assets/dialogue.txt"
# preload (instead of the global class name) so this autoload also works on a fresh clone,
# before Godot has built its global class cache.
const _Parser := preload("res://Scripts/DialogueParser.gd")

var dict_dialogue: Dictionary = {}

var time_dialogue: float = 0.025 # seconds per typed character
var dialogue_id: String = ""
var dialogue_choice_id: int = 0

var flag_displaying_dialogue: bool = false
var flag_waiting_dialogue_prompt: bool = false
var flag_waiting_dialogue_next: bool = false

var is_using_phone: bool = false
var is_in_dialogue: bool = false

## Tags unlocked by dialogue. Used as a set (the value is always true), so lookups are
## O(1) and showing the same line twice can't add duplicates.
var dialogue_tags: Dictionary = {}

var move_input_vector: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Loaded once here for every scene (GameController / tests no longer need to).
	dict_dialogue = _Parser.loadDB(DIALOGUE_PATH, "dialogue")
	


func add_tag(tag: String) -> void:
	if tag == "PHONE_CHARGE":
		SignalController.battery_charge.emit(0)
	dialogue_tags[tag] = true


func has_tag(tag: String) -> bool:
	return dialogue_tags.has(tag)


func save_state() -> Dictionary:
	return {"dialogue_tags": dialogue_tags.keys()}


func load_state(data: Dictionary) -> void:
	dialogue_tags.clear()
	for tag in data.get("dialogue_tags", []):
		dialogue_tags[str(tag)] = true


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
	move_input_vector = Vector2.ZERO
