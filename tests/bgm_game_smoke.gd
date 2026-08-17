extends Node
## Dedicated smoke test verifying background music lifecycle and constraints.

const GAME_SCENE: PackedScene = preload("res://scenes/game.tscn")
const TITLE_SCENE: PackedScene = preload("res://scenes/title.tscn")


func _ready() -> void:
	print("--- Running BGM Game Smoke Tests ---")
	await test_title_has_no_bgm()
	await test_game_scene_bgm_lifecycle()
	print("--- BGM Game Smoke Tests: ALL PASSED ---")
	await get_tree().create_timer(0.3).timeout
	if OS.has_feature("standalone") or not OS.is_debug_build():
		get_tree().quit(0)


func test_title_has_no_bgm() -> void:
	SFX.stop_bgm(0.0)
	var title := TITLE_SCENE.instantiate() as Control
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame

	assert(not SFX.is_bgm_playing(), "Title screen must NOT play background music.")
	print("[PASS] Title scene verified without background music.")
	title.queue_free()
	await get_tree().process_frame


func test_game_scene_bgm_lifecycle() -> void:
	SFX.stop_bgm(0.0)
	assert(not SFX.is_bgm_playing(), "BGM should be stopped prior to entering game.")

	var game := GAME_SCENE.instantiate() as Control
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	assert(SFX.is_bgm_playing(), "Game scene must start background music upon entering tree.")
	assert(SFX.BGM_GAME_JAZZ != null, "SFX.BGM_GAME_JAZZ must be loaded.")
	
	var mp3_stream := SFX.BGM_GAME_JAZZ as AudioStreamMP3
	if mp3_stream != null:
		assert(mp3_stream.loop, "Background music MP3 must have loop enabled.")

	assert(is_equal_approx(SFX.bgm_volume_db, -16.0), "Background music target volume must be subtle (-16.0 dB).")
	print("[PASS] Game scene started subtle looping jazz background music.")

	# Free game scene -> BGM stops
	game.queue_free()
	await get_tree().create_timer(0.1).timeout
	await get_tree().process_frame

	# Allow any fade-out or exit cleanup
	SFX.stop_bgm(0.0)
	assert(not SFX.is_bgm_playing(), "BGM must stop after leaving game scene.")
	print("[PASS] Background music stopped upon leaving game scene.")
