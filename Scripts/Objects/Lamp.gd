extends Interactable

@onready var lamp_sprite: AnimatedSprite2D = $Lamp_Sprite
var is_on: bool = false


func _ready() -> void:
	is_on = lamp_sprite.animation == &"on"
	add_to_group(SaveManager.GROUP)


func _interact(_player: Hexy) -> void:
	set_lamp(not is_on)


func set_lamp(on: bool, animate: bool = true) -> void:
	is_on = on
	var animation := &"on" if on else &"off"
	if animate:
		lamp_sprite.play(animation)
	else: # jump straight to the end of the animation (used when loading a save)
		lamp_sprite.animation = animation
		lamp_sprite.frame = lamp_sprite.sprite_frames.get_frame_count(animation) - 1
		lamp_sprite.pause()


func save_state() -> Dictionary:
	return {"on": is_on}


func load_state(data: Dictionary) -> void:
	set_lamp(data.get("on", false), false)
