# Autoloaded Singleton
extends Node
## Plays the game's sounds. Every sound file is listed here, so scripts just say what happened
## (`AudioManager.play_sfx(&"phone_open")`) and swapping a sound means replacing the file (same name) or
## changing one line below.
##
## Buses (default_bus_layout.tres): music plays on "Music", everything else on "SFX", so they can be
## balanced separately in the Audio panel.
##
## Where each sound plays:
##   phone_open / phone_close   Phone.gd: the phone slides up / down (Q)
##   phone_boot                 Phone.gd: the turn-on animation (opening the phone after it's charged)
##   phone_ded                  Phone.gd: the battery runs out and the phone turns itself off
##   phone_charged              Phone.gd: charging finishes
##   blip (the "talking" sound) DialogueBox.gd: every letter as dialogue types out (not spaces/punctuation)
##   menu music                 MainMenu.gd (its `music` setting), loops until New Game / Load Game
##   ui_noise                   here: whenever the PLAYER moves the selection between buttons (menu, phone,
##                              dialogue choices...). Not when the game sets the focus (a menu opening, the
##                              phone starting on Home, choices appearing), and not when a button is pressed.

signal sound_played(sound_name: StringName) # for tests

const SFX := {
	&"phone_open": preload("res://Assets/Sounds/phone_open.wav"),
	&"phone_close": preload("res://Assets/Sounds/phone_close.wav"),
	&"phone_boot": preload("res://Assets/Sounds/phone_boot.wav"),
	&"phone_ded": preload("res://Assets/Sounds/phone_ded.wav"),
	&"phone_charged": preload("res://Assets/Sounds/phone_charged.wav"),
	&"ui_noise": preload("res://Assets/Sounds/ui_noise.wav"),
}
## Moving the selection between buttons (see _input / _on_focus_changed below).
const NAV_ACTIONS := [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev"]
const TALK := preload("res://Assets/Sounds/blip.wav") # (talking_sfx.wav was a placeholder, unused)

const SFX_VOICES := 6 # sound effects that can overlap
const SILENT_DB := -40.0 # music fades from/to this

var _sfx: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _talk: AudioStreamPlayer
var _talk_stop_id := 0
var _music: AudioStreamPlayer
var _music_path := ""
var _music_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in SFX_VOICES:
		_sfx.append(_add_player(&"SFX"))
	_talk = _add_player(&"SFX")
	_talk.stream = TALK
	_music = _add_player(&"Music")
	_music.finished.connect(_on_music_finished)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


# ---- UI navigation sound ----
# Node _input() runs before the GUI handles an event, so a navigation key is noted here first; if the GUI then
# moves the focus because of it, _on_focus_changed plays ui_noise. Focus set from code (grab_focus with no key
# pressed) finds no note and stays silent.
var _nav_key_frame := -1


func _input(event: InputEvent) -> void:
	for action in NAV_ACTIONS:
		if event.is_action_pressed(action, true): # (true: holding a key to repeat counts too)
			_nav_key_frame = Engine.get_process_frames()
			return


func _on_focus_changed(_control: Control) -> void:
	if _nav_key_frame == Engine.get_process_frames():
		_nav_key_frame = -1
		play_sfx(&"ui_noise")


func _add_player(bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"
	add_child(p)
	return p


# ---- sound effects ----

## Plays one of the SFX above. Several can overlap.
func play_sfx(sound_name: StringName, volume_db: float = 0.0) -> void:
	var stream: AudioStream = SFX.get(sound_name)
	if stream == null:
		push_warning("AudioManager: no sound called '%s'" % sound_name)
		return
	var p := _sfx[_next_voice]
	_next_voice = (_next_voice + 1) % _sfx.size()
	p.stream = stream
	p.volume_db = volume_db
	p.play()
	sound_played.emit(sound_name)


# ---- dialogue ----

## One typed letter: plays the talking sound from the start (cutting off the previous letter's).
func talk_letter() -> void:
	_talk_stop_id += 1 # cancels a pending stop_talking
	_talk.play()
	sound_played.emit(&"blip")


## Stops the talking sound, now or after `delay` seconds (so the last letter isn't cut off instantly).
func stop_talking(delay: float = 0.0) -> void:
	_talk_stop_id += 1
	if delay <= 0.0:
		_talk.stop()
		return
	var id := _talk_stop_id
	await get_tree().create_timer(delay).timeout
	if id == _talk_stop_id: # no new letter since
		_talk.stop()


func is_talking() -> bool:
	return _talk.playing


# ---- music ----

## Starts looping music (does nothing if that track is already playing). Fades in over `fade_in` seconds.
func play_music(path: String, fade_in: float = 1.0) -> void:
	if path == _music_path and _music.playing:
		return
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("AudioManager: can't load music '%s'" % path)
		return
	_kill_music_tween()
	_music_path = path
	_music.stream = stream
	_music.volume_db = SILENT_DB if fade_in > 0.0 else 0.0
	_music.play()
	if fade_in > 0.0:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", 0.0, fade_in)
	sound_played.emit(&"music")


## Fades the music out over `fade_out` seconds, then stops it.
func stop_music(fade_out: float = 1.0) -> void:
	_music_path = ""
	_kill_music_tween()
	if not _music.playing:
		return
	if fade_out <= 0.0:
		_music.stop()
		return
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", SILENT_DB, fade_out)
	_music_tween.tween_callback(_music.stop)


func current_music() -> String:
	return _music_path


func _on_music_finished() -> void:
	if _music_path != "": # loop
		_music.play()


func _kill_music_tween() -> void:
	if _music_tween:
		_music_tween.kill()
		_music_tween = null
