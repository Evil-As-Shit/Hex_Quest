extends CanvasLayer
## A full-screen animation between levels. Drop LevelTransition.tscn into a level, set which dialogue line
## triggers it and which level comes next: when the player closes that line (E on its last page), the
## animation covers the screen for `duration` seconds, then the next level loads (SaveManager.go_to_level:
## dialogue tags and the phone carry over, and the game saves on arrival).
##
## The animation is the "default" animation of the Screen node's SpriteFrames, drawn centred on a 1080x720
## screen like the main menu background. It's a black placeholder for now: replace its frames in the editor.

## The dialogue line that starts the transition when it's closed (e.g. "SAT011", "Off I go then!").
@export var trigger_dialogue_id: String = ""
## The level to load afterwards.
@export_file("*.tscn") var next_scene: String = ""
## How long the animation shows before the next level loads, in seconds.
@export var duration: float = 5.0

@onready var screen: AnimatedSprite2D = $Screen
var is_playing: bool = false


func _ready() -> void:
	visible = false
	SignalController.close_dialogue.connect(_on_dialogue_closed)


func _on_dialogue_closed() -> void:
	if trigger_dialogue_id != "" and GameData.dialogue_id == trigger_dialogue_id:
		play()


## Shows the animation, then moves on to next_scene. Safe to call more than once.
func play() -> void:
	if is_playing:
		return
	if next_scene == "" or not ResourceLoader.exists(next_scene):
		push_error("LevelTransition: next_scene '%s' doesn't exist" % next_scene)
		return
	is_playing = true
	GameData.is_in_cutscene = true # no moving, interacting or phone meanwhile
	visible = true
	screen.play("default")
	await get_tree().create_timer(duration).timeout
	if is_inside_tree(): # (the player may have quit meanwhile)
		SaveManager.go_to_level(next_scene)
