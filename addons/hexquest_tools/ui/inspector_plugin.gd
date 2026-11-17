@tool
extends EditorInspectorPlugin

const DialogueIdsProperty := preload("res://addons/hexquest_tools/ui/dialogue_ids_property.gd")


func _can_handle(object: Object) -> bool:
	return object is Node and object.get_script() != null


func _parse_property(object: Object, _type: Variant.Type, name: String, _hint: PropertyHint, _hint_string: String, _usage: int, _wide: bool) -> bool:
	if name == "dialogue_ids":
		add_property_editor(name, DialogueIdsProperty.new())
		return true
	return false
