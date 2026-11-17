@tool
extends RefCounted
## Every project-specific path/number the tools rely on, in one place.
## If you move a folder or rename a script, change it here.

const DIALOGUE_PATH := "res://Assets/Data/dialogue.txt"
const PORTRAIT_DIR := "res://Assets/UI/Portraits/"
## Image files in the portrait folder that are sheets, not single portraits.
const PORTRAIT_IGNORE := ["avatars", "portraits_originalsize"]
const OBJECT_SCENE_DIR := "res://Scenes/Objects/"
const ROOM_SCENE_DIR := "res://Scenes/Rooms/"
## Folders searched for spritesheets in the object builder.
const SPRITE_DIRS := ["res://Assets/Sprites/Objects/", "res://Assets/Sprites/Characters/", "res://Assets/Sprites/Environments/"]
const DEFAULT_SPRITESHEET := "res://Assets/Sprites/Objects/Objects_Spritesheet.png"

const NPC_SCRIPT := "res://Scripts/Objects/NPC.gd"
const CHAIR_SCRIPT := "res://Scripts/Objects/Chair.gd"
const LAMP_SCRIPT := "res://Scripts/Objects/Lamp.gd"
const ROOM_SCRIPT := "res://Scripts/World/Room.gd"
const DIALOGUE_BOX_SCRIPT := "res://Scripts/UI/DialogueBox.gd"

## Objects are added under this node (so they depth-sort with Hexy) when placed in a scene.
const YSORT_NODE := "YSort"

# Physics layer BIT VALUES (layer 2 = 2, layer 3 = 4, layer 4 = 8), matching Hexy.gd / your scenes.
const LAYER_AREAS := 2
const LAYER_OBJECTS := 4
const LAYER_WALLS := 8

## Dialogue ids look like PREFIX + number, e.g. NPC012.
const DEFAULT_PREFIX := "NPC"
const ID_PATTERN := "^[A-Za-z][A-Za-z0-9_]*$"
