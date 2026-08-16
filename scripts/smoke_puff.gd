class_name SmokePuff
extends GPUParticles3D
## Stylized "poof" / puff of smoke particle effect triggered when bots, items,
## or objects despawn or disappear.

const SCENE: PackedScene = preload("res://scenes/smoke_puff.tscn")

@export var auto_start: bool = true
@export var auto_free: bool = true


func _ready() -> void:
	if auto_start:
		restart()
		emitting = true

	if auto_free and one_shot:
		_schedule_cleanup()


func play() -> void:
	restart()
	emitting = true
	if auto_free and one_shot:
		_schedule_cleanup()


func _schedule_cleanup() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var total_lifetime := lifetime / maxf(speed_scale, 0.01) + 0.15
	var timer := tree.create_timer(total_lifetime)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free()
	)


## Static helper to spawn a puff of smoke at any 3D global position.
static func create_at(target_pos: Vector3, parent: Node = null) -> SmokePuff:
	var puff := SCENE.instantiate() as SmokePuff
	if puff == null:
		return null
	
	if parent != null and is_instance_valid(parent):
		parent.add_child(puff)
	elif Engine.get_main_loop() is SceneTree:
		var tree := Engine.get_main_loop() as SceneTree
		if tree.current_scene != null:
			tree.current_scene.add_child(puff)
		elif tree.root != null:
			tree.root.add_child(puff)

	puff.global_position = target_pos
	return puff
