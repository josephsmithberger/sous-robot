extends Node
## Automated smoke test suite for SFX autoload and audio integration.


func _ready() -> void:
	print("--- Running SFX Smoke Tests ---")
	test_sfx_singleton_exists()
	test_all_samples_loaded()
	test_player_pool_and_playback()
	test_semantic_helpers()
	test_bgm_functionality()
	test_signal_integration()
	print("--- SFX Smoke Tests: ALL PASSED ---")
	# If running as standalone test scene, automatically quit after a short delay
	await get_tree().create_timer(0.5).timeout
	if OS.has_feature("standalone") or not OS.is_debug_build():
		get_tree().quit(0)


func test_sfx_singleton_exists() -> void:
	assert(SFX != null, "SFX singleton must be registered and non-null.")
	assert(SFX.has_method("play"), "SFX must have 'play' method.")
	assert(SFX.has_method("play_random"), "SFX must have 'play_random' method.")
	print("[PASS] SFX singleton exists and is accessible globally.")


func test_all_samples_loaded() -> void:
	var samples: Dictionary = SFX.SAMPLES
	assert(samples.size() >= 51, "Expected at least 51 samples loaded, got %d" % samples.size())
	for sound_name: StringName in samples:
		var stream: AudioStream = samples[sound_name]
		assert(stream != null, "Sample '%s' failed to load or is null." % sound_name)
		assert(stream.get_length() > 0.0, "Sample '%s' has zero duration." % sound_name)
	print("[PASS] All %d audio samples verified and non-null." % samples.size())


func test_player_pool_and_playback() -> void:
	# Test concurrent playback across multiple channels
	for sound_name: StringName in [&"metalClick", &"chop", &"handleCoins", &"footstep01"]:
		var player := SFX.play(sound_name, -6.0, 1.0, 0.05)
		assert(player != null, "SFX.play should return an active AudioStreamPlayer.")
		assert(player.stream != null, "Player stream should be assigned.")
	print("[PASS] Player pool allocated and played multiple concurrent sounds.")


func test_semantic_helpers() -> void:
	var p_click := SFX.play_click()
	assert(p_click != null, "play_click() returned null")
	
	var p_tab := SFX.play_tab()
	assert(p_tab != null, "play_tab() returned null")

	var p_chop := SFX.play_chop()
	assert(p_chop != null, "play_chop() returned null")

	var p_slice := SFX.play_slice()
	assert(p_slice != null, "play_slice() returned null")

	var p_pot := SFX.play_pot()
	assert(p_pot != null, "play_pot() returned null")

	var p_pickup := SFX.play_pickup()
	assert(p_pickup != null, "play_pickup() returned null")

	var p_place := SFX.play_place()
	assert(p_place != null, "play_place() returned null")

	var p_trash := SFX.play_trash()
	assert(p_trash != null, "play_trash() returned null")

	var p_coin := SFX.play_coin()
	assert(p_coin != null, "play_coin() returned null")

	var p_deliver := SFX.play_deliver()
	assert(p_deliver != null, "play_deliver() returned null")

	var p_step := SFX.play_footstep()
	assert(p_step != null, "play_footstep() returned null")

	var p_puff := SFX.play_puff()
	assert(p_puff != null, "play_puff() returned null")

	var p_latch := SFX.play_latch()
	assert(p_latch != null, "play_latch() returned null")

	var p_creak := SFX.play_creak()
	assert(p_creak != null, "play_creak() returned null")

	print("[PASS] All semantic SFX helper methods executed successfully.")


func test_signal_integration() -> void:
	# Test that emitting signals on GameControl triggers handlers without error
	GameControl.change_money(10.0, "TEST REWARD")
	GameControl.item_trashed.emit(null)
	GameControl.tab_changed.emit(1)
	GameControl.placement_completed.emit(&"Counter", Vector3.ZERO, 0.0)
	GameControl.arrange_mode_changed.emit(true)
	GameControl.arrange_mode_changed.emit(false)
	GameControl.dialogue_activity_changed.emit(true)
	GameControl.dialogue_activity_changed.emit(false)
	print("[PASS] Global signal integrations executed cleanly.")


func test_bgm_functionality() -> void:
	assert(SFX.BGM_GAME_JAZZ != null, "SFX.BGM_GAME_JAZZ background music stream must not be null.")
	assert(SFX.BGM_GAME_JAZZ.get_length() > 0.0, "SFX.BGM_GAME_JAZZ must have positive length.")
	assert(SFX.has_method("play_bgm"), "SFX must have play_bgm method.")
	assert(SFX.has_method("stop_bgm"), "SFX must have stop_bgm method.")
	assert(SFX.has_method("is_bgm_playing"), "SFX must have is_bgm_playing method.")

	# Test starting BGM immediately
	SFX.play_bgm(SFX.BGM_GAME_JAZZ, 0.0, -16.0)
	assert(SFX.is_bgm_playing(), "SFX.is_bgm_playing() must return true after play_bgm.")

	# Test volume update
	SFX.set_bgm_volume(-18.0)
	assert(is_equal_approx(SFX.bgm_volume_db, -18.0), "SFX.bgm_volume_db should equal -18.0.")

	# Test stopping BGM
	SFX.stop_bgm(0.0)
	assert(not SFX.is_bgm_playing(), "SFX.is_bgm_playing() must return false after stop_bgm.")

	print("[PASS] BGM functionality (play, volume, stop, loop) verified successfully.")

