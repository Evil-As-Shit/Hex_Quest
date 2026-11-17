extends Interactable

const SIT_OFFSET := Vector2(0, -3)


func _interact(player: Hexy) -> void:
	if not player.is_sitting:
		player.sit_at(global_position + SIT_OFFSET)
