# Autoloaded Singleton
extends Node
## Global event bus.
## Declare every signal WITH its parameters, and fire it with
## `SignalController.some_signal.emit(args)` instead of `emit_signal("some_signal", args)`:
## typos are caught by the editor and the call is slightly faster.

# Dialogue
signal display_dialogue(id: String)
signal finish_dialogue
signal close_dialogue

# World
signal hexy_location(area_name: String)
signal interaction_check
signal room_revealed(room_id: StringName)

# Phone
signal toggle_phone
signal phone_interacted
signal battery_charge(amount: int)
