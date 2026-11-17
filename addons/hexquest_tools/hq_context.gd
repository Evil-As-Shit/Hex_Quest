@tool
extends RefCounted
## Shared state for all the tool panels: the one dialogue database, and the editor connection.
## (Static, so panels, dialogs and the inspector editor all see the same thing.)

const Config := preload("res://addons/hexquest_tools/hq_config.gd")
const DialogueDB := preload("res://addons/hexquest_tools/core/dialogue_db.gd")

static var db: DialogueDB
static var plugin: EditorPlugin # null when running outside the editor (tests)
## Set by the plugin: switches to the HexQuest tab and selects a dialogue line.
static var open_dialogue_cb: Callable
## Lets tests pretend a scene is open in the editor.
static var scene_root_override: Node


static func get_db() -> DialogueDB:
	if db == null:
		db = DialogueDB.new()
		db.load_file()
	return db


static func editor() -> EditorInterface:
	return plugin.get_editor_interface() if plugin != null else null


static func scene_root() -> Node:
	var ei := editor()
	return ei.get_edited_scene_root() if ei != null else scene_root_override


static func undo_redo() -> EditorUndoRedoManager:
	return plugin.get_undo_redo() if plugin != null else null


static func open_dialogue(id: String) -> void:
	if open_dialogue_cb.is_valid():
		open_dialogue_cb.call(id)


static func rescan_files() -> void:
	var ei := editor()
	if ei != null:
		ei.get_resource_filesystem().scan()


## Names (no extension) of the single-portrait images, e.g. ["witch_happy", ...].
static func portrait_names() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(Config.PORTRAIT_DIR):
		if f.ends_with(".png"):
			var n := f.get_basename()
			if not Config.PORTRAIT_IGNORE.has(n):
				out.append(n)
	out.sort()
	return out


static func portrait_texture(name: String) -> Texture2D:
	var path := Config.PORTRAIT_DIR + name + ".png"
	return load(path) as Texture2D if name != "" and ResourceLoader.exists(path) else null


## Small shared UI helpers.
static func button(text: String, tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	return b


static func label(text: String, dim: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if dim:
		l.modulate = Color(1, 1, 1, 0.6)
	return l


static func line_edit(placeholder: String = "") -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return le
