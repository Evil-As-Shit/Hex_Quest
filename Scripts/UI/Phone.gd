extends Control

const POS_SHOWN := Vector2(15, 180)
const POS_HIDDEN := Vector2(15, 645)
const SLIDE_TIME := 0.35
var battery_charge:= 0

@onready var home: Button = $Home
var _tween: Tween


func _ready() -> void:
	position = POS_HIDDEN
	SignalController.toggle_phone.connect(phone)
	SignalController.phone_interacted.connect(phone_input)
	SignalController.battery_charge.connect(charge_battery)

func charge_battery(charge_amount: int)-> void:
	if charge_amount == 0:
		$Charger.animation = "Charging"
	pass

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
