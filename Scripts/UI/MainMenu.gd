extends Control
## The main menu box: the "Hex Quest" title, New Game and Load Game.
## Styled like the dialogue box (the blankballoon 9-slice; flat white buttons that turn yellow when focused).
## Placeholder art and fonts: swap them in Scenes/UI/MainMenuBox.tscn.
##
## New Game asks first if there's a save (it's only overwritten once the new game saves for the first time).
## Load Game is greyed out when there's no save.

## The level New Game starts in.
@export_file("*.tscn") var new_game_scene: String = "res://The Game/1 - TheSat/Scenes/the_satellite.tscn"
## Menu music: loops while the menu is up, fades out on New Game / Load Game.
@export_file("*.wav", "*.ogg", "*.mp3") var music: String = "res://Assets/Sounds/sand-frand-_main-menu_.ogg"
const MUSIC_FADE := 1.0

@onready var title: Label = $Box/Title
@onready var buttons: Control = $Box/Buttons
@onready var new_game_button: Button = $Box/Buttons/NewGame
@onready var load_game_button: Button = $Box/Buttons/LoadGame
@onready var confirm: Control = $Box/Confirm
@onready var confirm_yes: Button = $Box/Confirm/Choices/Yes
@onready var confirm_no: Button = $Box/Confirm/Choices/No


func _ready() -> void:
	SaveManager.unregister_scene() # the menu itself is never saved (or quitting here would save "the menu")
	new_game_button.pressed.connect(_on_new_game)
	load_game_button.pressed.connect(_on_load_game)
	confirm_yes.pressed.connect(_start_new_game)
	confirm_no.pressed.connect(_close_confirm)
	_close_confirm()
	refresh()
	if music != "":
		AudioManager.play_music(music, MUSIC_FADE)


## Greys out Load Game when there's nothing to load.
func refresh() -> void:
	var can_load := SaveManager.has_save()
	load_game_button.disabled = not can_load
	load_game_button.focus_mode = Control.FOCUS_ALL if can_load else Control.FOCUS_NONE


func _on_new_game() -> void:
	if SaveManager.has_save():
		buttons.visible = false
		confirm.visible = true
		confirm_no.grab_focus() # the safe choice is the default
	else:
		_start_new_game()


func _start_new_game() -> void:
	AudioManager.stop_music(MUSIC_FADE)
	SaveManager.start_new_game(new_game_scene)


func _on_load_game() -> void:
	AudioManager.stop_music(MUSIC_FADE)
	if not SaveManager.continue_game(): # couldn't load: stay on the menu, music back on
		AudioManager.play_music(music, MUSIC_FADE)


func _close_confirm() -> void:
	confirm.visible = false
	buttons.visible = true
	new_game_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	# The game's interact key (E) presses the focused button too, like in dialogue. Enter/Space already do.
	# Mark the key handled BEFORE pressing: Yes / Load Game change scene, which takes this menu out of the tree,
	# and get_viewport() is null after that.
	var viewport := get_viewport()
	if event.is_action_pressed("interact"):
		var focused := viewport.gui_get_focus_owner()
		if focused is Button and not (focused as Button).disabled and is_ancestor_of(focused):
			viewport.set_input_as_handled()
			(focused as Button).pressed.emit()
	elif event.is_action_pressed("ui_cancel") and confirm.visible:
		viewport.set_input_as_handled()
		_close_confirm()
