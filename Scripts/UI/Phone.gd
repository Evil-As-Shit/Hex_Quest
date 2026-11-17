extends Control

const POS_SHOWN := Vector2(15, 180)
const POS_HIDDEN := Vector2(15, 645)
const SLIDE_TIME := 0.35

# Battery state is derived from dialogue tags, so it is saved and loaded with them
# (no separate save data needed). The charger's dialogue adds PHONE_CHARGE and then PHONE_CHARGE_FULL.
const TAG_CHARGING := "PHONE_CHARGE"
const TAG_FULL := "PHONE_CHARGE_FULL"
const TAG_DEAD := "PHONE_CHARGE_ZERO" # kept in sync here so NPC lines can react to a dead phone

enum Battery { DEAD, CHARGING, FULL }

@onready var home: Button = $Home
@onready var battery_sprite: AnimatedSprite2D = $Battery
var battery_state: Battery = Battery.DEAD
var _tween: Tween


func _ready() -> void:
	position = POS_HIDDEN
	SignalController.toggle_phone.connect(phone)
	SignalController.phone_interacted.connect(phone_input)
	SignalController.tag_added.connect(_on_tag_added)
	SignalController.tags_loaded.connect(_show_battery_from_tags)
	# Either fires at the end of the charging sweep, whether or not it is set to loop.
	battery_sprite.animation_looped.connect(_on_battery_animation_looped)
	battery_sprite.animation_finished.connect(_on_battery_animation_looped)
	_show_battery_from_tags()


## Live changes during play: animate them.
func _on_tag_added(tag: String) -> void:
	match tag:
		TAG_CHARGING:
			_set_battery(Battery.CHARGING)
		TAG_FULL:
			# If the charging sweep is playing, let it finish a loop first (see below).
			if battery_state != Battery.CHARGING:
				_set_battery(Battery.FULL)


## After a load or new game: jump straight to the right picture, no animation.
func _show_battery_from_tags() -> void:
	if GameData.has_tag(TAG_FULL):
		_set_battery(Battery.FULL)
	elif GameData.has_tag(TAG_CHARGING):
		_set_battery(Battery.CHARGING)
	else:
		_set_battery(Battery.DEAD)


func _on_battery_animation_looped() -> void:
	if battery_state == Battery.CHARGING and GameData.has_tag(TAG_FULL):
		_set_battery(Battery.FULL)


func _set_battery(state: Battery) -> void:
	battery_state = state
	match state:
		Battery.DEAD:
			battery_sprite.play("Ded")
		Battery.CHARGING:
			battery_sprite.play("Charging")
		Battery.FULL:
			# "Charges" holds the charge levels, lowest to highest: show the top one.
			battery_sprite.animation = "Charges"
			battery_sprite.frame = battery_sprite.sprite_frames.get_frame_count("Charges") - 1
			battery_sprite.pause()
	if state == Battery.DEAD:
		GameData.add_tag(TAG_DEAD)
	else:
		GameData.remove_tag(TAG_DEAD)


func phone() -> void:
	if not GameData.is_using_phone:
		GameData.is_using_phone = true
		home.grab_focus()
		_slide_to(POS_SHOWN)
	else:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()
		GameData.is_using_phone = false
		_slide_to(POS_HIDDEN)


func phone_input() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		print(focused.name)


# A tween only runs while the phone is actually moving (the old _process lerp ran every frame, forever).
func _slide_to(target: Vector2) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position", target, SLIDE_TIME)
