extends Node
## Put one of these in every playable scene. It tells SaveManager the scene is ready,
## which turns saving on for this scene and restores the last save (if there is one).

func _ready() -> void:
	SaveManager.register_scene()
