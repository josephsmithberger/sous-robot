extends Control
## Main title scene controller for Sous Robot.
##
## Manages retro diner UI animations, button interactions, SFX audio cues,
## "How to Play" tutorial modal, keyboard navigation, and scene transitions.

@onready var hero_card: PanelContainer = %HeroCard
@onready var start_button: Button = %StartButton
@onready var how_to_play_button: Button = %HowToPlayButton
@onready var quit_button: Button = %QuitButton
@onready var how_to_play_modal: Control = %HowToPlayModal
@onready var close_modal_button: Button = %CloseModalButton
@onready var main_title_label: Label = %MainTitle

# Decorative floating badges
@onready var badge_top_left: Control = get_node_or_null("%BadgeTopLeft")
@onready var badge_top_right: Control = get_node_or_null("%BadgeTopRight")
@onready var badge_bottom_left: Control = get_node_or_null("%BadgeBottomLeft")
@onready var badge_bottom_right: Control = get_node_or_null("%BadgeBottomRight")

var _time := 0.0
var _is_starting := false
var _button_tweens: Dictionary = {}
var _floating_elements: Array[Dictionary] = []


func _ready() -> void:
	if quit_button != null and OS.has_feature("web"):
		quit_button.visible = false

	if how_to_play_modal != null:
		how_to_play_modal.visible = false

	_setup_button_effects(start_button)
	_setup_button_effects(how_to_play_button)
	if quit_button != null:
		_setup_button_effects(quit_button)
	if close_modal_button != null:
		_setup_button_effects(close_modal_button)

	_init_floating_decorations()

	# Give initial focus to Start Button for immediate gamepad/keyboard readiness
	if start_button != null:
		start_button.grab_focus.call_deferred()


func _setup_button_effects(btn: Button) -> void:
	if btn == null:
		return
	btn.pivot_offset = btn.size / 2.0
	btn.resized.connect(func(): btn.pivot_offset = btn.size / 2.0)

	btn.mouse_entered.connect(func():
		_animate_button_scale(btn, Vector2(1.04, 1.04))
		if SFX != null:
			SFX.play_click(0.05)
	)
	btn.mouse_exited.connect(func():
		_animate_button_scale(btn, Vector2(1.0, 1.0))
	)
	btn.focus_entered.connect(func():
		_animate_button_scale(btn, Vector2(1.04, 1.04))
	)
	btn.focus_exited.connect(func():
		_animate_button_scale(btn, Vector2(1.0, 1.0))
	)


func _animate_button_scale(btn: Button, target_scale: Vector2) -> void:
	var current_tween: Tween = _button_tweens.get(btn)
	if current_tween != null and current_tween.is_valid():
		current_tween.kill()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "scale", target_scale, 0.16)
	_button_tweens[btn] = tween


func _init_floating_decorations() -> void:
	var badges := [
		{"node": badge_top_left, "speed": 1.8, "amplitude": 5.0, "rot_speed": 1.2, "rot_amp": 0.04, "phase": 0.0},
		{"node": badge_top_right, "speed": 2.1, "amplitude": 6.0, "rot_speed": 1.5, "rot_amp": -0.05, "phase": 1.2},
		{"node": badge_bottom_left, "speed": 1.6, "amplitude": 5.5, "rot_speed": 1.1, "rot_amp": 0.03, "phase": 2.4},
		{"node": badge_bottom_right, "speed": 2.3, "amplitude": 6.0, "rot_speed": 1.7, "rot_amp": -0.04, "phase": 3.6},
	]
	for b in badges:
		if b.node != null:
			b["base_pos"] = b.node.position
			b.node.pivot_offset = b.node.size / 2.0
			_floating_elements.append(b)


func _process(delta: float) -> void:
	_time += delta

	# Subtle floating breathing animation on hero plaque
	if hero_card != null and not _is_starting:
		hero_card.position.y = sin(_time * 1.8) * 3.5

	# Idle bobbing on corner badges
	for elem in _floating_elements:
		var node: Control = elem.node
		if node != null and node.is_inside_tree():
			var phase: float = elem.phase
			var speed: float = elem.speed
			var amp: float = elem.amplitude
			var rot_speed: float = elem.rot_speed
			var rot_amp: float = elem.rot_amp
			var base_pos: Vector2 = elem.base_pos
			node.position = base_pos + Vector2(0.0, sin(_time * speed + phase) * amp)
			node.rotation = sin(_time * rot_speed + phase) * rot_amp


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if how_to_play_modal != null and how_to_play_modal.visible:
			_close_how_to_play()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		if how_to_play_modal != null and how_to_play_modal.visible:
			_close_how_to_play()
			get_viewport().set_input_as_handled()
		elif not _is_starting:
			_on_start_button_pressed()
			get_viewport().set_input_as_handled()


func _on_start_button_pressed() -> void:
	if _is_starting:
		return
	_is_starting = true

	if start_button != null:
		start_button.disabled = true

	if SFX != null:
		SFX.play_door_open()

	# Visual press feedback animation on hero card before transition
	if hero_card != null:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(hero_card, "scale", Vector2(1.03, 1.03), 0.1)
		tween.tween_property(hero_card, "scale", Vector2(0.96, 0.96), 0.15)

	SceneLoader.load_scene("res://scenes/game.tscn")


func _on_how_to_play_button_pressed() -> void:
	if how_to_play_modal == null:
		return
	if SFX != null:
		SFX.play_book_open()

	how_to_play_modal.visible = true
	how_to_play_modal.modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(how_to_play_modal, "modulate:a", 1.0, 0.2)

	if close_modal_button != null:
		close_modal_button.grab_focus.call_deferred()


func _on_close_modal_button_pressed() -> void:
	_close_how_to_play()


func _close_how_to_play() -> void:
	if how_to_play_modal == null or not how_to_play_modal.visible:
		return
	if SFX != null:
		SFX.play_book_close()

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(how_to_play_modal, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func():
		how_to_play_modal.visible = false
		if start_button != null:
			start_button.grab_focus.call_deferred()
	)


func _on_quit_button_pressed() -> void:
	if SFX != null:
		SFX.play_click()
	get_tree().quit()
