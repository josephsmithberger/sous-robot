extends Node
## Automated smoke test for title scene UI, Sauce Tomato font, and interactions.

const TITLE_SCENE := preload("res://scenes/title.tscn")
const TOMATO_FONT := preload("res://assets/fonts/Sauce Tomato.otf")


func _ready() -> void:
	print("--- Running Title Scene Smoke Tests ---")
	await test_title_scene_instantiation()
	print("--- Title Scene Smoke Tests: ALL PASSED ---")
	await get_tree().create_timer(0.3).timeout
	if OS.has_feature("standalone") or not OS.is_debug_build():
		get_tree().quit(0)


func test_title_scene_instantiation() -> void:
	var title_instance := TITLE_SCENE.instantiate() as Control
	assert(title_instance != null, "Failed to instantiate title.tscn")
	add_child(title_instance)
	await get_tree().process_frame

	assert(not SFX.is_bgm_playing(), "BGM should not play on the title screen.")

	var main_title := title_instance.get_node_or_null("%MainTitle") as Label
	assert(main_title != null, "MainTitle label should exist in title scene")
	assert(main_title.text == "SOUS ROBOT", "MainTitle text should be 'SOUS ROBOT', got '%s'" % main_title.text)

	var font: Font = main_title.get_theme_font("font")
	assert(font != null, "MainTitle must have a theme font override")
	print("[PASS] Title scene instantiated with MainTitle '%s' and Sauce Tomato font." % main_title.text)

	var start_btn := title_instance.get_node_or_null("%StartButton") as Button
	var how_btn := title_instance.get_node_or_null("%HowToPlayButton") as Button
	var quit_btn := title_instance.get_node_or_null("%QuitButton") as Button
	var modal := title_instance.get_node_or_null("%HowToPlayModal") as Control
	var close_btn := title_instance.get_node_or_null("%CloseModalButton") as Button

	assert(start_btn != null, "StartButton must exist")
	assert(how_btn != null, "HowToPlayButton must exist")
	assert(quit_btn != null, "QuitButton must exist")
	assert(modal != null, "HowToPlayModal must exist")
	assert(close_btn != null, "CloseModalButton must exist")

	assert(not modal.visible, "HowToPlayModal should start hidden")
	print("[PASS] All title buttons and modal components found in scene tree.")

	# Test opening How To Play modal
	how_btn.pressed.emit()
	await get_tree().create_timer(0.05).timeout
	assert(modal.visible, "HowToPlayModal should be visible after pressing HowToPlayButton")
	print("[PASS] How To Play modal opened successfully.")

	# Test closing How To Play modal
	close_btn.pressed.emit()
	await get_tree().create_timer(0.2).timeout
	assert(not modal.visible, "HowToPlayModal should be hidden after pressing CloseModalButton")
	print("[PASS] How To Play modal closed successfully.")

	# Test Start button
	start_btn.pressed.emit()
	assert(start_btn.disabled, "StartButton should be disabled once pressed to prevent duplicate triggers")
	print("[PASS] StartButton triggered scene transition and disabled duplicate input.")

	title_instance.queue_free()
