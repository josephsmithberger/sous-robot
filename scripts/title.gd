extends Control

@onready var start_button: Button = $CenterContainer/VBoxContainer/Button


func _on_button_pressed() -> void:
	SceneLoader.load_scene("res://scenes/game.tscn")
	start_button.disabled = true
