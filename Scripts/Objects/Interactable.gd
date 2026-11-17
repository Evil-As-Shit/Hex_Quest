class_name Interactable
extends StaticBody2D
## Base class for anything Hexy can press E on (lamps, chairs, NPCs...).
##
## The scene needs an Area2D child named "Object_Id" on the "objects" collision layer.
## Hexy finds that area, then calls interact() on its parent. Override _interact().
## No signals, no instance-id bookkeeping, and objects that aren't being interacted with do nothing.

## Pin this if you want a stable save id for an object that has state (otherwise its scene path is used).
@export var save_id: String = ""


func interact(player: Hexy) -> void:
	_interact(player)


func _interact(_player: Hexy) -> void:
	pass


func get_save_id() -> String:
	return save_id if save_id != "" else SaveManager.node_id(self)
