extends Control

const POS_SHOWN := Vector2(15, 180)
const POS_HIDDEN := Vector2(15, 645)
const SLIDE_TIME := 0.35

# --- Battery ---
# Charge levels, lowest to highest (what the Battery sprite shows):
#   0             "Ded"; the phone switches itself off
#   1             "Dying" (loops)
#   2..max_charge the "Charges" frames, lowest to highest
# The charger's dialogue adds PHONE_CHARGE ("Charging phone...") to start charging: Battery_Charging plays on
# top of the battery, and every loop of it raises the battery one level, on the frame where the sweep
# covers the whole battery (charge_step_frame) so the change is hidden. When full, the loop finishes and the
# held "Charging phone..." line is released so the dialogue moves on to "Phone is Charged!!!".
# The level is saved (this node is in the "persist" group). Tags mirror it for dialogue:
# PHONE_CHARGE_ZERO while dead, PHONE_CHARGE_FULL while full, PHONE_CHARGE only while charging.
const TAG_CHARGING := "PHONE_CHARGE"
const TAG_FULL := "PHONE_CHARGE_FULL"
const TAG_DEAD := "PHONE_CHARGE_ZERO"
const LEVEL_DEAD := 0
const LEVEL_DYING := 1

# --- Power (the Phone_Bool sprite covers the screen while the phone is off or turning on) ---
const ANIM_OFF := &"Turn_Phone_Off" 
const ANIM_ON := &"Turn_Phone_On"

enum Battery { DEAD, CHARGING, CHARGED, FULL }

## The frame of Battery_Charging's "Charging" animation that covers the whole battery: the level goes up
## on this frame, so the change happens out of sight. (Frame 10 is the fully filled sweep.)
@export var charge_step_frame: int = 10
## Seconds between opening a freshly charged phone and its boot sound (lets phone_open finish first).
@export var boot_sound_delay: float = 1.0
var _power_change_id := 0 # bumped on every power off, so a pending boot sound knows it's stale

@onready var home: Button = $Home
@onready var battery_sprite: AnimatedSprite2D = $Battery
@onready var charging_sprite: AnimatedSprite2D = $Battery_Charging
@onready var screen: AnimatedSprite2D = $Phone_Bool
var charge: int = LEVEL_DEAD
var max_charge: int = 2 # set from the number of "Charges" frames in _ready
var battery_state: Battery = Battery.DEAD
## False while the battery is dead, and after charging until the phone is next opened.
var is_powered_on: bool = true
var _powering_on := false # the turn-on animation is playing
var _held_dialogue := false # true while the "Charging phone..." line is waiting on us
var _tween: Tween


func _ready() -> void:
	position = POS_HIDDEN
	max_charge = LEVEL_DYING + battery_sprite.sprite_frames.get_frame_count("Charges")
	add_to_group(SaveManager.GROUP)
	add_to_group(SaveManager.GROUP_CARRY) # the same phone in every level: its battery carries over
	SignalController.toggle_phone.connect(phone)
	SignalController.phone_interacted.connect(phone_input)
	SignalController.tag_added.connect(_on_tag_added)
	SignalController.tags_loaded.connect(_show_battery_from_tags)
	charging_sprite.visible = false
	var sweep_frames := charging_sprite.sprite_frames.get_frame_count("Charging")
	if charge_step_frame < 0 or charge_step_frame >= sweep_frames: # a bad value would charge forever
		push_warning("Phone: charge_step_frame %d isn't a frame of 'Charging' (0..%d); using the middle one" % [charge_step_frame, sweep_frames - 1])
		@warning_ignore("integer_division")
		charge_step_frame = sweep_frames / 2
	charging_sprite.frame_changed.connect(_on_charging_frame)
	# One of these fires at the end of each charging loop, depending on whether the animation loops.
	charging_sprite.animation_looped.connect(_on_charging_loop_done)
	charging_sprite.animation_finished.connect(_on_charging_loop_done)
	screen.animation_finished.connect(_on_screen_animation_finished)
	_show_battery_from_tags()


## Changes the battery by `amount` levels (negative drains it). At 0 the phone switches itself off.
func add_charge(amount: int) -> void:
	_show_level(charge + amount, true)


# Debug builds only: F6 (input action "debug_drain_battery") drains the battery by one level.
func _input(event: InputEvent) -> void:
	if OS.is_debug_build() and event.is_action_pressed("debug_drain_battery") and battery_state != Battery.CHARGING:
		add_charge(-1)


# ---- battery ----

func _on_tag_added(tag: String) -> void:
	if tag != TAG_CHARGING:
		return
	if charge >= max_charge:
		GameData.remove_tag(TAG_CHARGING) # nothing to do
	elif battery_state != Battery.CHARGING:
		_start_charging()


## After a load or new game: jump straight to the right picture, no animation. (A saved level, if
## any, is applied right after this by load_state.)
func _show_battery_from_tags() -> void:
	_stop_charging()
	GameData.remove_tag(TAG_CHARGING) # a charge cut short (quit mid-charge) isn't resumed
	_show_level(max_charge if GameData.has_tag(TAG_FULL) else LEVEL_DEAD, false)
	_set_powered(charge > LEVEL_DEAD)


func _start_charging() -> void:
	battery_state = Battery.CHARGING
	if GameData.is_in_dialogue:
		GameData.hold_dialogue() # keep "Charging phone..." up until we're full
		_held_dialogue = true
	charging_sprite.visible = true
	charging_sprite.play("Charging")


## One level per loop, while the sweep hides the battery.
func _on_charging_frame() -> void:
	if battery_state == Battery.CHARGING and charging_sprite.frame == charge_step_frame and charge < max_charge:
		_show_level(charge + 1, true)


## Each loop ends with the battery uncovered again: carry on, or stop once it's full.
func _on_charging_loop_done() -> void:
	if battery_state != Battery.CHARGING:
		return
	if charge < max_charge:
		if not charging_sprite.is_playing(): # not set to loop: start the next loop by hand
			charging_sprite.play("Charging")
		return
	# Deferred: we're inside the charging sprite's own loop signal.
	_finish_charging.call_deferred()


func _finish_charging() -> void:
	var was_holding := _held_dialogue # (_stop_charging clears it)
	_stop_charging()
	AudioManager.play_sfx(&"phone_charged")
	GameData.remove_tag(TAG_CHARGING)
	if was_holding:
		GameData.release_dialogue()


func _stop_charging() -> void:
	_held_dialogue = false
	charging_sprite.stop()
	charging_sprite.visible = false
	if battery_state == Battery.CHARGING:
		battery_state = Battery.CHARGED # corrected by _update_state below
	_update_state()


## Shows the battery at `level` and keeps the tags in step. Hitting 0 switches the phone off.
func _show_level(level: int, animate: bool) -> void:
	charge = clampi(level, LEVEL_DEAD, max_charge)
	if charge == LEVEL_DEAD:
		battery_sprite.play("Ded")
	elif charge == LEVEL_DYING:
		battery_sprite.play("Dying")
	else:
		battery_sprite.animation = "Charges"
		battery_sprite.frame = charge - (LEVEL_DYING + 1)
		battery_sprite.pause()
	if battery_state != Battery.CHARGING:
		_update_state()
	if charge == LEVEL_DEAD:
		GameData.add_tag(TAG_DEAD)
	else:
		GameData.remove_tag(TAG_DEAD)
	if charge == max_charge:
		GameData.add_tag(TAG_FULL)
	else:
		GameData.remove_tag(TAG_FULL) # so the charger offers to charge again after draining
	if charge == LEVEL_DEAD and (is_powered_on or _powering_on):
		_power_off(animate)


func _update_state() -> void:
	if charge == LEVEL_DEAD:
		battery_state = Battery.DEAD
	elif charge == max_charge:
		battery_state = Battery.FULL
	else:
		battery_state = Battery.CHARGED


# ---- power ----

func _power_off(animate: bool) -> void:
	_power_change_id += 1
	is_powered_on = false
	_powering_on = false
	_set_ui_enabled(false)
	screen.visible = true
	if animate:
		_play_from_start(ANIM_OFF) # plays once and stays on its last (black) frame
		AudioManager.play_sfx(&"phone_ded")
	else:
		screen.animation = ANIM_OFF
		screen.frame = screen.sprite_frames.get_frame_count(ANIM_OFF) - 1
		screen.pause()


func _power_on() -> void:
	_powering_on = true
	screen.visible = true
	_play_from_start(ANIM_ON) # the UI comes back when it finishes (see below)
	# The boot sound waits a moment so it doesn't clash with phone_open (both play as the phone opens).
	# (A connected method, not await: if the scene changes meanwhile, the connection just goes away with the phone.)
	get_tree().create_timer(boot_sound_delay).timeout.connect(_play_boot_sound.bind(_power_change_id))


func _play_boot_sound(power_id: int) -> void:
	if power_id == _power_change_id and (_powering_on or is_powered_on): # not switched off meanwhile
		AudioManager.play_sfx(&"phone_boot")


# play(name) on the animation the sprite is already showing carries on from the current frame. Phone_Bool is
# often parked on the last turn-off frame (dead at startup, or switched on by a load with no animation), so a
# plain play() there jumped straight to the end and the turn-off animation never showed. Always rewind.
func _play_from_start(anim: StringName) -> void:
	screen.animation = anim
	screen.set_frame_and_progress(0, 0.0)
	screen.play(anim)


func _on_screen_animation_finished() -> void:
	if screen.animation == ANIM_ON and _powering_on:
		_set_powered(true)


## Instantly on or off, no animation (startup, loading, end of the turn-on animation).
func _set_powered(on: bool) -> void:
	if not on:
		_power_off(false)
		return
	_powering_on = false
	is_powered_on = true
	screen.visible = false
	_set_ui_enabled(true)
	if GameData.is_using_phone:
		home.grab_focus()


## While the phone is off its buttons can't be focused or pressed (Q still opens and closes it).
func _set_ui_enabled(on: bool) -> void:
	for child in get_children():
		if child is Button:
			var b := child as Button
			b.disabled = not on
			b.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
			if not on and b.has_focus():
				b.release_focus()


# ---- opening / closing ----

func phone() -> void:
	if not GameData.is_using_phone:
		GameData.is_using_phone = true
		AudioManager.play_sfx(&"phone_open")
		if is_powered_on:
			home.grab_focus()
		elif charge > LEVEL_DEAD and not _powering_on:
			_power_on() # charged since it died: turn it on as it opens
		_slide_to(POS_SHOWN)
	else:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null:
			focused.release_focus()
		GameData.is_using_phone = false
		AudioManager.play_sfx(&"phone_close")
		_slide_to(POS_HIDDEN)


func phone_input() -> void:
	if not is_powered_on:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		print(focused.name)


# A tween only runs while the phone is actually moving (the old _process lerp ran every frame, forever).
func _slide_to(target: Vector2) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position", target, SLIDE_TIME)


# ---- save / load (see SaveManager) ----

func get_save_id() -> String:
	return "phone"


func save_state() -> Dictionary:
	return {"charge": charge}


func load_state(data: Dictionary) -> void:
	_stop_charging()
	_show_level(int(data.get("charge", charge)), false)
	_set_powered(charge > LEVEL_DEAD)
