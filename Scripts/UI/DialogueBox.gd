extends Control

const PORTRAIT_DIR := "res://Assets/ui/Avatars/"
const LABEL_SIZE_FULL := Vector2(400, 90)
const LABEL_POS_FULL := Vector2(40, 20)
const LABEL_SIZE_PORTRAIT := Vector2(305, 90)
const LABEL_POS_PORTRAIT := Vector2(135, 20)

@onready var label: Label = $Label
@onready var portrait: TextureRect = $PortraitTexture
@onready var button0: Button = $Button0
@onready var button1: Button = $Button1

var _portraits: Dictionary = {} # expression name -> Texture2D
var _type_tween: Tween


func _ready() -> void:
	visible = false
	button0.visible = false
	button1.visible = false
	button0.focus_entered.connect(on_choice_focus.bind(0))
	button1.focus_entered.connect(on_choice_focus.bind(1))

	SignalController.display_dialogue.connect(on_display_dialogue)
	SignalController.finish_dialogue.connect(on_finish_dialogue)
	SignalController.close_dialogue.connect(on_close_dialogue)
	_preload_portraits()


# Loads every portrait the dialogue data actually uses, once, so showing a line never hitches on disk.
func _preload_portraits() -> void:
	for entry in GameData.dict_dialogue.values():
		var expression := _expression_of(entry)
		if expression == "" or _portraits.has(expression):
			continue
		var path := PORTRAIT_DIR + expression + ".png"
		if ResourceLoader.exists(path):
			_portraits[expression] = load(path)
		else:
			push_warning("DialogueBox: missing portrait %s" % path)


# "" means "no portrait". Accepts JSON null and the old string "null".
static func _expression_of(entry: Dictionary) -> String:
	var expression: Variant = entry.get("expression")
	if expression == null or str(expression) == "null":
		return ""
	return str(expression)


func on_choice_focus(n: int) -> void:
	GameData.dialogue_choice_id = n


func on_close_dialogue() -> void:
	_kill_tween()
	GameData.flag_displaying_dialogue = false
	GameData.flag_waiting_dialogue_next = false
	GameData.flag_waiting_dialogue_prompt = false
	GameData.is_in_dialogue = false
	visible = false


func on_display_dialogue(id: String) -> void:
	GameData.dialogue_id = id
	GameData.is_in_dialogue = true
	GameData.flag_displaying_dialogue = true

	var dialogue: Dictionary = GameData.dict_dialogue[id]
	var expression := _expression_of(dialogue)
	var has_portrait := _portraits.has(expression)
	label.size = LABEL_SIZE_PORTRAIT if has_portrait else LABEL_SIZE_FULL
	label.position = LABEL_POS_PORTRAIT if has_portrait else LABEL_POS_FULL
	portrait.texture = _portraits.get(expression) # null when there is no portrait

	label.text = dialogue["text"]
	button0.visible = false
	button1.visible = false
	visible = true
	_start_typing()


# Typewriter effect. One tween drives the whole line, so it's frame-rate independent
# and nothing runs in _process while the box is idle.
func _start_typing() -> void:
	_kill_tween()
	var count: int = label.text.length()
	label.visible_characters = 0
	if count == 0 or GameData.time_dialogue <= 0.0:
		on_finish_dialogue()
		return
	_type_tween = create_tween()
	_type_tween.tween_property(label, "visible_characters", count, count * GameData.time_dialogue)
	_type_tween.finished.connect(on_finish_dialogue)


func on_finish_dialogue() -> void:
	_kill_tween()
	GameData.flag_displaying_dialogue = false
	label.visible_ratio = 1.0

	var dialogue: Dictionary = GameData.dict_dialogue[GameData.dialogue_id]
	if dialogue.has("choices"):
		var choices: Array = dialogue["choices"]
		button0.text = choices[0]
		button1.text = choices[1]
		button0.visible = true
		button1.visible = true
		button0.grab_focus()
		GameData.flag_waiting_dialogue_prompt = true
	else:
		GameData.flag_waiting_dialogue_next = true


func _kill_tween() -> void:
	if _type_tween:
		_type_tween.kill()
		_type_tween = null
