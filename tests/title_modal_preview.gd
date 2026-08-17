extends Node

const TITLE_SCENE := preload("res://scenes/title.tscn")

func _ready() -> void:
	var title_instance := TITLE_SCENE.instantiate() as Control
	add_child(title_instance)
	await get_tree().process_frame
	var how_btn := title_instance.get_node_or_null("%HowToPlayButton") as Button
	if how_btn != null:
		how_btn.pressed.emit()
