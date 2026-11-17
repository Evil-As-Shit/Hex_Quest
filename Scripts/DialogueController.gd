extends Node

class_name DialogueController

static func finish() -> void:
	SignalController.finish_dialogue.emit()


static func choose() -> void:
	SignalController.close_dialogue.emit()
	var choice: String = "choice_%s" % GameData.dialogue_choice_id
	object_interacted(GameData.dict_dialogue[GameData.dialogue_id][choice])


static func next() -> void:
	var dialogue: Dictionary = GameData.dict_dialogue[GameData.dialogue_id]
	if _is_true(dialogue.get("isEnd", false)):
		SignalController.close_dialogue.emit()
	elif dialogue.has("divert"):
		display_dialogue(dialogue["divert"])
	else:
		push_error("DialogueController: %s has neither 'isEnd' nor 'divert'" % dialogue["id"])
		SignalController.close_dialogue.emit()


## Shows the FIRST dialogue in the list whose tag requirement is met
## (an entry with no "tagRequired" always passes), and ignores the rest.
static func object_interacted(dialogue_ids: Array) -> void:
	for dialogue_id in dialogue_ids:
		var dialogue: Dictionary = GameData.dict_dialogue[dialogue_id]
		if not dialogue.has("tagRequired") or GameData.has_tag(dialogue["tagRequired"]):
			display_dialogue(dialogue_id)
			return
	push_warning("DialogueController: no dialogue meets its requirements: %s" % [dialogue_ids])


static func display_dialogue(dialogue_id: String) -> void:
	SignalController.display_dialogue.emit(dialogue_id)
	var dialogue: Dictionary = GameData.dict_dialogue[dialogue_id]
	if dialogue.has("tagAdd"):
		GameData.add_tag(dialogue["tagAdd"])


# Accepts the real boolean `true` as well as the old string "true" from hand-edited data.
static func _is_true(value: Variant) -> bool:
	return value == true or str(value) == "true"
