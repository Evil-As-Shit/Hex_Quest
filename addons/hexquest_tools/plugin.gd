@tool
extends EditorPlugin
## HexQuest Tools: a "HexQuest" tab with a dialogue editor, object/NPC/room builder, scene & room
## overview and project checker, plus a nicer `dialogue_ids` editor in the Inspector.

const Ctx := preload("res://addons/hexquest_tools/hq_context.gd")
const MainScreen := preload("res://addons/hexquest_tools/ui/main_screen.gd")
const InspectorPlugin := preload("res://addons/hexquest_tools/ui/inspector_plugin.gd")

var _main: Control
var _inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	Ctx.plugin = self
	Ctx.db = null # always start from what's on disk
	Ctx.open_dialogue_cb = _open_dialogue
	_main = MainScreen.new()
	get_editor_interface().get_editor_main_screen().add_child(_main)
	_main.hide()
	_inspector = InspectorPlugin.new()
	add_inspector_plugin(_inspector)


func _exit_tree() -> void:
	_save_dialogue_if_dirty()
	if _inspector:
		remove_inspector_plugin(_inspector)
	if _main:
		_main.queue_free()
	Ctx.plugin = null
	Ctx.open_dialogue_cb = Callable()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _main:
		_main.visible = visible
		if visible:
			_main.on_shown()


func _get_plugin_name() -> String:
	return "HexQuest"


func _get_plugin_icon() -> Texture2D:
	return get_editor_interface().get_base_control().get_theme_icon("Edit", "EditorIcons")


# Called when the editor saves (Ctrl+S) and on exit, so dialogue edits are never lost.
func _save_external_data() -> void:
	_save_dialogue_if_dirty()


func _save_dialogue_if_dirty() -> void:
	if Ctx.db != null and Ctx.db.dirty:
		Ctx.db.save_file()


func _open_dialogue(id: String) -> void:
	get_editor_interface().set_main_screen_editor("HexQuest")
	_main.show_dialogue(id)
