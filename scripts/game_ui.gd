extends Control

const KITCHEN_TAB := 0

@onready var _tabs: TabContainer = $MarginContainer/HSplitContainer/TabContainer
@onready var _dialogue_slot: SubViewportContainer = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/DialogueSlot
@onready var _dialogue_viewport: SubViewport = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/DialogueSlot/DialogueViewport
@onready var _control_deck: Control = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/ControlDeck
@onready var _joystick_row: Control = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/ControlDeck/DeckMargin/JoystickRow
@onready var _keyboard_hint: Control = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/ControlDeck/KeyboardHint

var _previous_dialogue_host_resolver: Callable


func _ready() -> void:
	_tabs.tab_changed.connect(_on_tab_changed)
	GameControl.controllability_changed.connect(_on_controllability_changed)
	GameControl.input_mode_changed.connect(_on_input_mode_changed)
	GameControl.dialogue_activity_changed.connect(_on_dialogue_activity_changed)

	_previous_dialogue_host_resolver = DialogueManager.get_current_scene
	DialogueManager.get_current_scene = _get_dialogue_host

	_on_input_mode_changed(GameControl.input_mode)
	_on_tab_changed(_tabs.current_tab)


func _exit_tree() -> void:
	DialogueManager.get_current_scene = _previous_dialogue_host_resolver
	GameControl.set_controllable(false)


func _on_tab_changed(tab_index: int) -> void:
	GameControl.set_controllable(tab_index == KITCHEN_TAB)
	_update_interaction_ui()


func _on_controllability_changed(_is_controllable: bool) -> void:
	_update_interaction_ui()


func _on_dialogue_activity_changed(_is_active: bool) -> void:
	_update_interaction_ui()


func _update_interaction_ui() -> void:
	var kitchen_is_active := _tabs.current_tab == KITCHEN_TAB
	var dialogue_is_active := GameControl.is_dialogue_active()
	_dialogue_slot.visible = kitchen_is_active and dialogue_is_active
	_control_deck.visible = kitchen_is_active and GameControl.is_controllable and not dialogue_is_active


func _get_dialogue_host() -> Node:
	return _dialogue_viewport


func _on_input_mode_changed(_input_mode: GameControl.InputMode) -> void:
	var using_touch := GameControl.is_using_touch()
	_joystick_row.visible = using_touch
	_keyboard_hint.visible = not using_touch
