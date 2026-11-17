class_name Hexy
extends CharacterBody2D
## Hexy handles physics (movement, interactions, which room Hexy is in) and the animation state.
## Hexy never reads the keyboard: InputController writes GameData.move_input_vector, Hexy reacts to it.

enum STATE {IDLE, WALK, PHONE, SITTING, PHONE_SIT}

const STATE_ANIMATION := {
	STATE.IDLE: &"Idle",
	STATE.WALK: &"Walk",
	STATE.PHONE: &"Phone",
	STATE.SITTING: &"Sitting",
	STATE.PHONE_SIT: &"Phone_Sit",
}
# AnimationTree states that face the way Hexy is moving.
const FACING_PARAMS := [
	"parameters/Idle/blend_position",
	"parameters/Walk/blend_position",
	"parameters/Phone/blend_position",
	"parameters/Sitting/blend_position",
]
const STAND_UP_OFFSET := Vector2(0, 6)
const LAYER_AREAS := 2 # physics layer 2 ("areas"), as a bit value
const LAYER_OBJECTS := 4 # physics layer 3 ("objects"), as a bit value

#Movement variables
@export var move_speed: float = 50.0
@export var move_acc: float = 500.0
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var state_machine: AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var current_state: STATE = STATE.IDLE : set = set_current_state
## Derived from the state, so the two can never disagree.
var is_sitting: bool :
	get: return current_state == STATE.SITTING or current_state == STATE.PHONE_SIT

# Room / object detection (reusable point queries, created once)
var query_area := PhysicsPointQueryParameters2D.new()
var query_objects := PhysicsPointQueryParameters2D.new()
var _area_node: Area2D = null # the room/area Hexy is currently inside
var _checked_position := Vector2.INF # where we last looked up the area
var _facing := Vector2.ZERO


func _ready() -> void:
	add_to_group(SaveManager.GROUP)
	query_area.collide_with_areas = true
	query_area.collide_with_bodies = false
	query_area.collision_mask = LAYER_AREAS
	query_objects.collide_with_areas = true
	query_objects.collide_with_bodies = false
	query_objects.collision_mask = LAYER_OBJECTS
	SignalController.interaction_check.connect(interact_nearby)


func set_current_state(new_state: STATE) -> void:
	if new_state == current_state:
		return
	var was_sitting := is_sitting
	current_state = new_state
	var now_sitting := is_sitting
	if was_sitting and not now_sitting: # stood up
		global_position += STAND_UP_OFFSET
		z_index = 0
		collision_shape.set_deferred("disabled", false)
	elif now_sitting and not was_sitting: # sat down
		collision_shape.set_deferred("disabled", true)
	state_machine.travel(STATE_ANIMATION[new_state])


## Called by chairs and the like.
func sit_at(sit_position: Vector2) -> void:
	current_state = STATE.SITTING
	global_position = sit_position
	z_index = 1


func _physics_process(delta: float) -> void:
	var input := GameData.move_input_vector
	if input != Vector2.ZERO:
		_set_facing(input)
		current_state = STATE.WALK
		velocity = velocity.move_toward(input * move_speed, move_acc * delta)
	else:
		current_state = _resting_state()
		velocity = Vector2.ZERO
	move_and_slide()
	_update_location()


func _resting_state() -> STATE:
	if GameData.is_using_phone:
		return STATE.PHONE_SIT if is_sitting else STATE.PHONE
	return STATE.SITTING if is_sitting else STATE.IDLE


# Only touches the AnimationTree when the direction actually changed.
func _set_facing(direction: Vector2, force: bool = false) -> void:
	if direction == _facing and not force:
		return
	_facing = direction
	for param in FACING_PARAMS:
		animation_tree.set(param, direction)


## Finds the Area2D (on layer "areas") Hexy is standing in. Only runs when Hexy has moved,
## so an idle Hexy costs nothing. Rooms are told directly; anything else can listen for hexy_location.
func _update_location() -> void:
	if global_position == _checked_position:
		return
	_checked_position = global_position
	query_area.position = global_position
	var hits := get_world_2d().direct_space_state.intersect_point(query_area, 1)
	if hits.is_empty():
		return
	var area := hits[0].collider as Area2D
	if area == null or area == _area_node:
		return
	_area_node = area
	if area.has_method("on_player_entered"):
		area.on_player_entered(self)
	SignalController.hexy_location.emit(String(area.name))


## Interact with whatever Interactable Hexy is standing on. Each interactable has an Area2D child
## ("Object_Id") on the objects layer; its parent is the thing to interact with.
func interact_nearby() -> void:
	query_objects.position = global_position
	var hits := get_world_2d().direct_space_state.intersect_point(query_objects, 1)
	if hits.is_empty():
		return
	var target := (hits[0].collider as Node).get_parent()
	if target.has_method("interact"):
		target.interact(self)


# --- Save / load (see SaveManager) ---

func get_save_id() -> String:
	return "hexy"


func save_state() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y],
		"facing": [_facing.x, _facing.y],
		"sitting": is_sitting,
	}


func load_state(data: Dictionary) -> void:
	var pos: Array = data.get("position", [global_position.x, global_position.y])
	var facing: Array = data.get("facing", [0, 0])
	var sitting: bool = data.get("sitting", false)
	velocity = Vector2.ZERO
	# State first (standing up nudges the position), exact position last.
	current_state = STATE.SITTING if sitting else STATE.IDLE
	global_position = Vector2(pos[0], pos[1])
	z_index = 1 if sitting else 0
	if Vector2(facing[0], facing[1]) != Vector2.ZERO:
		_set_facing(Vector2(facing[0], facing[1]), true)
	# Forget the old area so the room we load into gets "entered" (and revealed if needed).
	_area_node = null
	_checked_position = Vector2.INF
