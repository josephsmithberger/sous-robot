extends Node
## Global sound effects manager and multi-channel audio pool.
##
## Manages zero-latency playback of Kenney RPG audio assets with automatic
## audio player pooling, pitch randomization, and global game event signal wiring.

const AUDIO_DIR := "res://assets/audio/"
const DEFAULT_POOL_SIZE := 16

# --- Preloaded Audio Streams ---
const SAMPLES: Dictionary = {
	&"beltHandle1": preload("res://assets/audio/beltHandle1.ogg"),
	&"beltHandle2": preload("res://assets/audio/beltHandle2.ogg"),
	&"bookClose": preload("res://assets/audio/bookClose.ogg"),
	&"bookFlip1": preload("res://assets/audio/bookFlip1.ogg"),
	&"bookFlip2": preload("res://assets/audio/bookFlip2.ogg"),
	&"bookFlip3": preload("res://assets/audio/bookFlip3.ogg"),
	&"bookOpen": preload("res://assets/audio/bookOpen.ogg"),
	&"bookPlace1": preload("res://assets/audio/bookPlace1.ogg"),
	&"bookPlace2": preload("res://assets/audio/bookPlace2.ogg"),
	&"bookPlace3": preload("res://assets/audio/bookPlace3.ogg"),
	&"chop": preload("res://assets/audio/chop.ogg"),
	&"cloth1": preload("res://assets/audio/cloth1.ogg"),
	&"cloth2": preload("res://assets/audio/cloth2.ogg"),
	&"cloth3": preload("res://assets/audio/cloth3.ogg"),
	&"cloth4": preload("res://assets/audio/cloth4.ogg"),
	&"clothBelt": preload("res://assets/audio/clothBelt.ogg"),
	&"clothBelt2": preload("res://assets/audio/clothBelt2.ogg"),
	&"creak1": preload("res://assets/audio/creak1.ogg"),
	&"creak2": preload("res://assets/audio/creak2.ogg"),
	&"creak3": preload("res://assets/audio/creak3.ogg"),
	&"doorClose_1": preload("res://assets/audio/doorClose_1.ogg"),
	&"doorClose_2": preload("res://assets/audio/doorClose_2.ogg"),
	&"doorClose_3": preload("res://assets/audio/doorClose_3.ogg"),
	&"doorClose_4": preload("res://assets/audio/doorClose_4.ogg"),
	&"doorOpen_1": preload("res://assets/audio/doorOpen_1.ogg"),
	&"doorOpen_2": preload("res://assets/audio/doorOpen_2.ogg"),
	&"drawKnife1": preload("res://assets/audio/drawKnife1.ogg"),
	&"drawKnife2": preload("res://assets/audio/drawKnife2.ogg"),
	&"drawKnife3": preload("res://assets/audio/drawKnife3.ogg"),
	&"dropLeather": preload("res://assets/audio/dropLeather.ogg"),
	&"footstep00": preload("res://assets/audio/footstep00.ogg"),
	&"footstep01": preload("res://assets/audio/footstep01.ogg"),
	&"footstep02": preload("res://assets/audio/footstep02.ogg"),
	&"footstep03": preload("res://assets/audio/footstep03.ogg"),
	&"footstep04": preload("res://assets/audio/footstep04.ogg"),
	&"footstep05": preload("res://assets/audio/footstep05.ogg"),
	&"footstep06": preload("res://assets/audio/footstep06.ogg"),
	&"footstep07": preload("res://assets/audio/footstep07.ogg"),
	&"footstep08": preload("res://assets/audio/footstep08.ogg"),
	&"footstep09": preload("res://assets/audio/footstep09.ogg"),
	&"handleCoins": preload("res://assets/audio/handleCoins.ogg"),
	&"handleCoins2": preload("res://assets/audio/handleCoins2.ogg"),
	&"handleSmallLeather": preload("res://assets/audio/handleSmallLeather.ogg"),
	&"handleSmallLeather2": preload("res://assets/audio/handleSmallLeather2.ogg"),
	&"knifeSlice": preload("res://assets/audio/knifeSlice.ogg"),
	&"knifeSlice2": preload("res://assets/audio/knifeSlice2.ogg"),
	&"metalClick": preload("res://assets/audio/metalClick.ogg"),
	&"metalLatch": preload("res://assets/audio/metalLatch.ogg"),
	&"metalPot1": preload("res://assets/audio/metalPot1.ogg"),
	&"metalPot2": preload("res://assets/audio/metalPot2.ogg"),
	&"metalPot3": preload("res://assets/audio/metalPot3.ogg"),
}

# --- Sound Groupings for Variation ---
const FOOTSTEPS: Array[StringName] = [
	&"footstep00", &"footstep01", &"footstep02", &"footstep03", &"footstep04",
	&"footstep05", &"footstep06", &"footstep07", &"footstep08", &"footstep09",
]

const BOOK_FLIPS: Array[StringName] = [
	&"bookFlip1", &"bookFlip2", &"bookFlip3",
]

const BOOK_PLACES: Array[StringName] = [
	&"bookPlace1", &"bookPlace2", &"bookPlace3",
]

const POTS: Array[StringName] = [
	&"metalPot1", &"metalPot2", &"metalPot3",
]

const KNIVES: Array[StringName] = [
	&"drawKnife1", &"drawKnife2", &"drawKnife3",
]

const SLICES: Array[StringName] = [
	&"knifeSlice", &"knifeSlice2",
]

const COINS: Array[StringName] = [
	&"handleCoins", &"handleCoins2",
]

const CREAKS: Array[StringName] = [
	&"creak1", &"creak2", &"creak3",
]

const DOORS_OPEN: Array[StringName] = [
	&"doorOpen_1", &"doorOpen_2",
]

const DOORS_CLOSE: Array[StringName] = [
	&"doorClose_1", &"doorClose_2", &"doorClose_3", &"doorClose_4",
]

const PICKUPS: Array[StringName] = [
	&"cloth1", &"cloth2", &"cloth3", &"cloth4",
	&"dropLeather", &"beltHandle1", &"beltHandle2",
	&"handleSmallLeather", &"handleSmallLeather2",
]

const PUFFS: Array[StringName] = [
	&"clothBelt", &"clothBelt2", &"cloth1", &"cloth2",
]

var _players: Array[AudioStreamPlayer] = []
var _pool_index := 0
var _last_footstep_index := -1
var sfx_volume_db := 0.0
var sfx_enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_player_pool()
	_connect_global_signals()


func _init_player_pool() -> void:
	for i in DEFAULT_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer_%02d" % i
		player.bus = &"Master"
		add_child(player)
		_players.append(player)


func _get_available_player() -> AudioStreamPlayer:
	if _players.is_empty():
		return null
	# Prefer an idle player; otherwise cycle round-robin
	for p in _players:
		if not p.playing:
			return p
	var player := _players[_pool_index]
	_pool_index = (_pool_index + 1) % _players.size()
	return player


## Core playback function with optional pitch randomization.
func play(sound_name: StringName, volume_offset_db: float = 0.0, pitch_scale: float = 1.0, pitch_variance: float = 0.0) -> AudioStreamPlayer:
	if not sfx_enabled or sound_name.is_empty():
		return null
	var stream: AudioStream = SAMPLES.get(sound_name)
	if stream == null:
		push_warning("SFX: Unknown sound '%s'" % sound_name)
		return null

	var player := _get_available_player()
	if player == null:
		return null

	var final_pitch := pitch_scale
	if pitch_variance > 0.0001:
		final_pitch += randf_range(-pitch_variance, pitch_variance)
	final_pitch = clampf(final_pitch, 0.5, 2.5)

	player.stream = stream
	player.volume_db = sfx_volume_db + volume_offset_db
	player.pitch_scale = final_pitch
	player.play()
	return player


## Plays a random sound from an array of sample keys.
func play_random(sound_names: Array, volume_offset_db: float = 0.0, pitch_min: float = 0.95, pitch_max: float = 1.05) -> AudioStreamPlayer:
	if not sfx_enabled or sound_names.is_empty():
		return null
	var chosen: StringName = sound_names[randi() % sound_names.size()]
	var pitch := randf_range(pitch_min, pitch_max)
	return play(chosen, volume_offset_db, pitch, 0.0)


# =========================================================================
# Semantic Game Sound Helpers
# =========================================================================

func play_click(pitch_var: float = 0.08) -> AudioStreamPlayer:
	return play(&"metalClick", -2.0, 1.0, pitch_var)


func play_tab() -> AudioStreamPlayer:
	return play_random(BOOK_FLIPS, -1.0, 0.95, 1.05)


func play_book_open() -> AudioStreamPlayer:
	return play(&"bookOpen", 0.0, 1.0, 0.05)


func play_book_close() -> AudioStreamPlayer:
	return play(&"bookClose", 0.0, 1.0, 0.05)


func play_chop() -> AudioStreamPlayer:
	return play(&"chop", 2.0, 1.0, 0.08)


func play_slice() -> AudioStreamPlayer:
	return play_random(SLICES, 1.0, 0.92, 1.08)


func play_knife() -> AudioStreamPlayer:
	return play_random(KNIVES, 0.0, 0.95, 1.05)


func play_pot() -> AudioStreamPlayer:
	return play_random(POTS, 1.0, 0.95, 1.05)


func play_pickup() -> AudioStreamPlayer:
	return play_random(PICKUPS, 1.0, 0.92, 1.08)


func play_drop() -> AudioStreamPlayer:
	return play(&"dropLeather", 0.0, 1.0, 0.06)


func play_place() -> AudioStreamPlayer:
	return play_random(BOOK_PLACES, 2.0, 0.95, 1.05)


func play_trash() -> AudioStreamPlayer:
	return play_random(CREAKS, 1.0, 0.90, 1.10)


func play_coin() -> AudioStreamPlayer:
	return play_random(COINS, 2.0, 0.95, 1.05)


func play_deliver() -> AudioStreamPlayer:
	play(&"metalLatch", 0.0, 1.0)
	return play_random(POTS, 1.0, 1.05, 1.15)


func play_order_complete() -> AudioStreamPlayer:
	play(&"metalLatch", 2.0, 1.1)
	return play(&"handleCoins", 3.0, 1.0, 0.05)


func play_order_penalty() -> AudioStreamPlayer:
	return play_random(CREAKS, 2.0, 0.85, 0.95)


func play_door_open() -> AudioStreamPlayer:
	return play_random(DOORS_OPEN, 0.0, 0.95, 1.05)


func play_door_close() -> AudioStreamPlayer:
	return play_random(DOORS_CLOSE, 0.0, 0.95, 1.05)


func play_latch() -> AudioStreamPlayer:
	return play(&"metalLatch", 1.0, 1.0, 0.05)


func play_creak() -> AudioStreamPlayer:
	return play_random(CREAKS, 0.0, 0.95, 1.05)


func play_puff() -> AudioStreamPlayer:
	return play_random(PUFFS, 2.0, 0.90, 1.10)


func play_footstep() -> AudioStreamPlayer:
	if FOOTSTEPS.is_empty():
		return null
	var idx := randi() % FOOTSTEPS.size()
	if idx == _last_footstep_index and FOOTSTEPS.size() > 1:
		idx = (idx + 1) % FOOTSTEPS.size()
	_last_footstep_index = idx
	return play(FOOTSTEPS[idx], -8.0, 1.0, 0.08)


# =========================================================================
# Automatic Global Signal Wiring
# =========================================================================

func _connect_global_signals() -> void:
	if not Engine.has_singleton(&"GameControl") and get_node_or_null("/root/GameControl") == null:
		call_deferred(&"_connect_global_signals")
		return

	var gc := get_node_or_null("/root/GameControl")
	if gc != null:
		if not gc.money_changed.is_connected(_on_money_changed):
			gc.money_changed.connect(_on_money_changed)
		if not gc.order_started.is_connected(_on_order_started):
			gc.order_started.connect(_on_order_started)
		if not gc.order_completed.is_connected(_on_order_completed):
			gc.order_completed.connect(_on_order_completed)
		if not gc.order_penalized.is_connected(_on_order_penalized):
			gc.order_penalized.connect(_on_order_penalized)
		if not gc.order_item_fulfilled.is_connected(_on_order_item_fulfilled):
			gc.order_item_fulfilled.connect(_on_order_item_fulfilled)
		if not gc.item_delivered.is_connected(_on_item_delivered):
			gc.item_delivered.connect(_on_item_delivered)
		if not gc.item_trashed.is_connected(_on_item_trashed):
			gc.item_trashed.connect(_on_item_trashed)
		if not gc.tab_changed.is_connected(_on_tab_changed):
			gc.tab_changed.connect(_on_tab_changed)
		if not gc.placement_started.is_connected(_on_placement_started):
			gc.placement_started.connect(_on_placement_started)
		if not gc.placement_completed.is_connected(_on_placement_completed):
			gc.placement_completed.connect(_on_placement_completed)
		if not gc.placement_cancelled.is_connected(_on_placement_cancelled):
			gc.placement_cancelled.connect(_on_placement_cancelled)
		if not gc.arrange_mode_changed.is_connected(_on_arrange_mode_changed):
			gc.arrange_mode_changed.connect(_on_arrange_mode_changed)
		if not gc.bot_dispatch_requested.is_connected(_on_bot_dispatch_requested):
			gc.bot_dispatch_requested.connect(_on_bot_dispatch_requested)
		if not gc.bots_assigned.is_connected(_on_bots_assigned):
			gc.bots_assigned.connect(_on_bots_assigned)
		if not gc.bot_dispatch_closed.is_connected(_on_bot_dispatch_closed):
			gc.bot_dispatch_closed.connect(_on_bot_dispatch_closed)
		if not gc.automation_available.is_connected(_on_automation_available):
			gc.automation_available.connect(_on_automation_available)
		if not gc.process_picker_requested.is_connected(_on_process_picker_requested):
			gc.process_picker_requested.connect(_on_process_picker_requested)
		if not gc.process_picker_selected.is_connected(_on_process_picker_selected):
			gc.process_picker_selected.connect(_on_process_picker_selected)
		if not gc.process_picker_cancelled.is_connected(_on_process_picker_cancelled):
			gc.process_picker_cancelled.connect(_on_process_picker_cancelled)
		if not gc.dialogue_activity_changed.is_connected(_on_dialogue_activity_changed):
			gc.dialogue_activity_changed.connect(_on_dialogue_activity_changed)

	var rt := get_node_or_null("/root/RecipeTracker")
	if rt != null:
		if not rt.recipe_made.is_connected(_on_recipe_made):
			rt.recipe_made.connect(_on_recipe_made)


# --- Signal Callbacks ---

func _on_money_changed(_balance: float, delta: float, reason: String) -> void:
	if reason == "SESSION START" or is_zero_approx(delta):
		return
	if delta > 0.0:
		play_coin()
	else:
		play_coin()


func _on_order_started(_order_id: int, _order: Dictionary) -> void:
	play_door_open()


func _on_order_completed(_order_id: int, _payout: float, _final_tip: float) -> void:
	play_order_complete()


func _on_order_penalized(_order_id: int, _remaining_tip: float, _penalty: float, _item_name: String) -> void:
	play_order_penalty()


func _on_order_item_fulfilled(_order_id: int, _item_id: StringName, _fulfilled: int, _required: int) -> void:
	play_deliver()


func _on_item_delivered(_item: KitchenItem) -> void:
	# Accompanied by order_item_fulfilled or wrong item penalty
	pass


func _on_item_trashed(_item: KitchenItem) -> void:
	play_trash()


func _on_tab_changed(_tab_index: int) -> void:
	play_tab()


func _on_placement_started(_item_id: StringName) -> void:
	play_book_open()


func _on_placement_completed(_item_id: StringName, _pos: Vector3, _rot_y: float) -> void:
	play_place()


func _on_placement_cancelled() -> void:
	play_book_close()


func _on_arrange_mode_changed(is_arranging: bool) -> void:
	if is_arranging:
		play_latch()
	else:
		play_click()


func _on_bot_dispatch_requested(_order_id: int, _order: Dictionary, _automatable_items: Dictionary) -> void:
	play_book_open()


func _on_bots_assigned(_order_id: int, _allocations: Dictionary) -> void:
	play_latch()


func _on_bot_dispatch_closed() -> void:
	play_book_close()


func _on_automation_available(_recipe_id: StringName, _recipe_name: String, _message: String) -> void:
	play_latch()


func _on_process_picker_requested(_target: Node, _options: Array) -> void:
	play_book_open()


func _on_process_picker_selected(_target: Node, _recipe: Resource) -> void:
	play_knife()


func _on_process_picker_cancelled() -> void:
	play_book_close()


func _on_dialogue_activity_changed(is_active: bool) -> void:
	if is_active:
		play_door_open()
	else:
		play_door_close()


func _on_recipe_made(_recipe_id: StringName, _output_item: KitchenItem, _total_count: int = 0) -> void:
	# Subtle dish creation confirmation
	play_pot()
