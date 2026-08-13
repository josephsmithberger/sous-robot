extends "res://addons/dialogue_manager/dialogue_responses_menu.gd"
## Native-touch override for Dialogue Manager's dynamically generated responses.


func _on_response_gui_input(event: InputEvent, item: Control, response) -> void:
	if "Disallowed" in item.name:
		return

	if TouchUI.is_primary_press(event):
		TouchUI.claim_touch(event)
		get_viewport().set_input_as_handled()
		response_selected.emit(response)
	elif event.is_action_pressed(&"ui_accept" if next_action.is_empty() else next_action) and item in get_menu_items():
		get_viewport().set_input_as_handled()
		response_selected.emit(response)
