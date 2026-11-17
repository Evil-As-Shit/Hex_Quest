extends Node
## All gameplay input lives here. Other scripts just react to GameData / SignalController.
## Uses the input ACTIONS from Project Settings (interact, phone, move_*), not hard-coded keys,
## so rebinding works and it behaves on non-QWERTY layouts.

func _process(_delta: float) -> void:
	if GameData.is_using_phone or GameData.is_in_dialogue:
		GameData.move_input_vector = Vector2.ZERO
	else:
		GameData.move_input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SaveManager.quit_game()
	elif event.is_action_pressed("interact"):
		_on_interact()
	elif event.is_action_pressed("phone"):
		_on_phone()


func _on_interact() -> void:
	if GameData.is_using_phone:
		SignalController.phone_interacted.emit()
	elif GameData.flag_displaying_dialogue:
		DialogueController.finish()
	elif GameData.flag_waiting_dialogue_prompt:
		DialogueController.choose()
	elif GameData.flag_waiting_dialogue_next:
		if not GameData.dialogue_held: # a held line moves on by itself when released
			DialogueController.next()
	else:
		SignalController.interaction_check.emit()


func _on_phone() -> void:
	# The phone can be closed any time, but only opened when no dialogue is on screen.
	var dialogue_active := GameData.flag_displaying_dialogue \
			or GameData.flag_waiting_dialogue_prompt \
			or GameData.flag_waiting_dialogue_next
	if GameData.is_using_phone or not dialogue_active:
		SignalController.toggle_phone.emit()
