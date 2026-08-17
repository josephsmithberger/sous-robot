extends Control

@onready var start_button: Button = $CenterContainer/VBoxContainer/Button


func _on_button_pressed() -> void:
	SFX.play_click()
	SceneLoader.load_scene("res://scenes/game.tscn")
	start_button.disabled = true
