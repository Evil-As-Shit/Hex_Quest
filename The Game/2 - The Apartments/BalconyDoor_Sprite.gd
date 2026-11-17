extends Sprite2D
## Draws the door frame in front of Hexy while Hexy is out on the balcony.
## (The pixel fade that used to live here is now handled per room by Room.gd.)

func _ready() -> void:
	SignalController.hexy_location.connect(_on_hexy_location)


func _on_hexy_location(area_name: String) -> void:
	z_index = 1 if area_name == "Balcony" else 0
