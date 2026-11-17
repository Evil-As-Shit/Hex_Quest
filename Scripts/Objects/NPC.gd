extends Interactable

@export var dialogue_ids: Array[String] = ["NPC000"]


func _interact(_player: Hexy) -> void:
	DialogueController.object_interacted(dialogue_ids)
