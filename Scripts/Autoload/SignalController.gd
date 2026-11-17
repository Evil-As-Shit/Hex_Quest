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
signal dialogue_released # a hold ended (see GameData.hold_dialogue): the held line moves on by itself

# World
signal hexy_location(area_name: String)
signal interaction_check
signal room_revealed(room_id: StringName)

# Tags (GameData.dialogue_tags)
signal tag_added(tag: String) # a new tag was just unlocked during play
signal tag_removed(tag: String)
signal tags_loaded # every tag was replaced at once (save loaded, or new game)

# Phone
signal toggle_phone
signal phone_interacted
