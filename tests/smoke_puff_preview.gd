extends Node3D

const BOT_WORKER_SCENE: PackedScene = preload("res://scenes/bot_worker.tscn")
const SMOKE_PUFF_SCENE: PackedScene = preload("res://scenes/smoke_puff.tscn")

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	camera.look_at(Vector3(0, 0.5, 0))
	_run_demo()

func _run_demo() -> void:
	while is_inside_tree():
		# Spawn bot on left, puff on right
		var bot := BOT_WORKER_SCENE.instantiate() as BotWorker
		add_child(bot)
		bot.global_position = Vector3(-0.8, 0.05, 0)
		bot.rotation_degrees.y = 15.0
		
		# Spawn continuous puffs of smoke on right so we see the puff effect clearly
		SmokePuff.create_at(Vector3(0.8, 0.4, 0), self)
		
		await get_tree().create_timer(1.2).timeout
		if not is_inside_tree() or not is_instance_valid(bot):
			break
			
		# Despawn the bot with its puff
		bot.despawn(0.7)
		
		await get_tree().create_timer(1.0).timeout
