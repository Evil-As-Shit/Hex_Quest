@tool
extends VBoxContainer
## The "HexQuest" tab in the editor's top bar: header (save / reload) plus the four tool tabs.

const Ctx := preload("res://addons/hexquest_tools/hq_context.gd")
const DialogueTab := preload("res://addons/hexquest_tools/ui/dialogue_tab.gd")
const ObjectTab := preload("res://addons/hexquest_tools/ui/object_tab.gd")
const SceneTab := preload("res://addons/hexquest_tools/ui/scene_tab.gd")
const ProblemsTab := preload("res://addons/hexquest_tools/ui/problems_tab.gd")

var tabs: TabContainer
var dialogue_tab: Control
var _state: Label
var _save: Button
var _confirm_reload: ConfirmationDialog


func _init() -> void:
	name = "HexQuestTools"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	add_child(header)
	header.add_child(Ctx.label("HexQuest Tools"))
	_state = Ctx.label("")
	_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_state)
	_save = Ctx.button("Save dialogue", "Writes dialogue.txt")
	_save.pressed.connect(save_dialogue)
	header.add_child(_save)
	var reload := Ctx.button("Reload from disk", "Throw away unsaved changes and re-read dialogue.txt")
	reload.pressed.connect(func(): _reload(true))
	header.add_child(reload)

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	dialogue_tab = DialogueTab.new()
	tabs.add_child(dialogue_tab)
	tabs.add_child(ObjectTab.new())
	tabs.add_child(SceneTab.new())
	tabs.add_child(ProblemsTab.new())

	_confirm_reload = ConfirmationDialog.new()
	_confirm_reload.dialog_text = "dialogue.txt was changed outside the editor, and you also have unsaved changes here.\n\nReload from disk and lose your unsaved changes?"
	_confirm_reload.confirmed.connect(func(): _reload(true))
	add_child(_confirm_reload)


func _ready() -> void:
	Ctx.get_db().changed.connect(func(_s): _update_state())
	Ctx.get_db().saved.connect(_update_state)
	_update_state()


## Called whenever the HexQuest tab is shown.
func on_shown() -> void:
	var db := Ctx.get_db()
	if db.changed_on_disk():
		if db.dirty:
			_confirm_reload.popup_centered()
		else:
			_reload(false)
	_update_state()


func show_dialogue(id: String) -> void:
	tabs.current_tab = dialogue_tab.get_index()
	dialogue_tab.select_id(id)


func save_dialogue() -> void:
	var db := Ctx.get_db()
	if not db.save_file():
		_state.text = "⚠ " + db.error
		_state.modulate = Color(1, 0.5, 0.5)
		return
	_update_state()


func _reload(_force: bool) -> void:
	var db := Ctx.get_db()
	if not db.load_file():
		_state.text = "⚠ " + db.error
		_state.modulate = Color(1, 0.5, 0.5)
		return
	dialogue_tab.refresh()
	_update_state()


func _update_state() -> void:
	var db := Ctx.get_db()
	_save.disabled = not db.dirty
	if db.error != "":
		_state.text = "   ⚠ " + db.error
		_state.modulate = Color(1, 0.5, 0.5)
	elif db.dirty:
		_state.text = "   ● unsaved changes in %s" % db.path.get_file()
		_state.modulate = Color(1, 0.85, 0.4)
	else:
		_state.text = "   %s: %d lines, saved" % [db.path.get_file(), db.entries.size()]
		_state.modulate = Color(1, 1, 1, 0.6)
