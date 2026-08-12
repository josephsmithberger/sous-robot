extends Control

const KITCHEN_TAB := 0

@onready var _tabs: TabContainer = $MarginContainer/HSplitContainer/TabContainer
@onready var _control_deck: Control = $MarginContainer/HSplitContainer/TabContainer/Kitchen/PanelContainer/VBoxContainer/ControlDeck


func _ready() -> void:
	_tabs.tab_changed.connect(_on_tab_changed)
	GameControl.controllability_changed.connect(_on_controllability_changed)
	_on_tab_changed(_tabs.current_tab)


func _exit_tree() -> void:
	GameControl.set_controllable(false)


func _on_tab_changed(tab_index: int) -> void:
	GameControl.set_controllable(tab_index == KITCHEN_TAB)


func _on_controllability_changed(is_controllable: bool) -> void:
	_control_deck.visible = is_controllable
