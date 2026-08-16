extends Node

const CRATE_CONFIGS: Array[Dictionary] = [
	{
		"scene": preload("res://assets/appliances/crate_buns.tscn"),
		"area_name": "buns",
		"item_id": &"bread",
		"display_name": "Bread",
		"expected_prompt": "TAKE BREAD",
	},
	{
		"scene": preload("res://assets/appliances/crate_carrots.tscn"),
		"area_name": "carrots",
		"item_id": &"carrot",
		"display_name": "Carrot",
		"expected_prompt": "TAKE CARROT",
	},
	{
		"scene": preload("res://assets/appliances/crate_cheese.tscn"),
		"area_name": "cheese",
		"item_id": &"cheese",
		"display_name": "Cheese",
		"expected_prompt": "TAKE CHEESE",
	},
	{
		"scene": preload("res://assets/appliances/crate_ham.tscn"),
		"area_name": "ham",
		"item_id": &"ham",
		"display_name": "Ham",
		"expected_prompt": "TAKE HAM",
	},
	{
		"scene": preload("res://assets/appliances/crate_lettuce.tscn"),
		"area_name": "lettuce",
		"item_id": &"lettuce",
		"display_name": "Lettuce",
		"expected_prompt": "TAKE LETTUCE",
	},
	{
		"scene": preload("res://assets/appliances/crate_onions.tscn"),
		"area_name": "onions",
		"item_id": &"onion",
		"display_name": "Onion",
		"expected_prompt": "TAKE ONION",
	},
	{
		"scene": preload("res://assets/appliances/crate_potatoes.tscn"),
		"area_name": "potatoes",
		"item_id": &"potato",
		"display_name": "Potato",
		"expected_prompt": "TAKE POTATO",
	},
	{
		"scene": preload("res://assets/appliances/crate_steak.tscn"),
		"area_name": "steak",
		"item_id": &"steak",
		"display_name": "Steak",
		"expected_prompt": "TAKE STEAK",
	},
	{
		"scene": preload("res://assets/appliances/crate_tomatoes.tscn"),
		"area_name": "tomatoes",
		"item_id": &"tomato",
		"display_name": "Tomato",
		"expected_prompt": "TAKE TOMATO",
	},
]

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")


func _ready() -> void:
	GameControl.reset_session()
	GameControl.set_controllable(true)
	GameControl.give_player_control()

	var player: PlayerController = PLAYER_SCENE.instantiate() as PlayerController
	add_child(player)
	await get_tree().physics_frame

	var tested_crates: Array[String] = []

	for config: Dictionary in CRATE_CONFIGS:
		var scene: PackedScene = config["scene"]
		var crate_instance: Node3D = scene.instantiate() as Node3D
		add_child(crate_instance)
		await get_tree().physics_frame

		var area_name: String = config["area_name"]
		var source_area: ItemSource = crate_instance.get_node_or_null(area_name) as ItemSource
		assert(source_area != null, "Crate %s missing ItemSource area '%s'" % [scene.resource_path, area_name])
		assert(source_area.item != null, "ItemSource in %s has null item" % scene.resource_path)
		assert(source_area.item.item_id == config["item_id"], "Crate %s item_id mismatch: expected %s, got %s" % [scene.resource_path, config["item_id"], source_area.item.item_id])
		assert(source_area.item.display_name == config["display_name"], "Crate %s display_name mismatch: expected %s, got %s" % [scene.resource_path, config["display_name"], source_area.item.display_name])
		assert(source_area.item.held_scene != null, "Crate %s held_scene is null" % scene.resource_path)

		# 1. Player with empty hands approaches crate
		assert(not player.has_held_item(), "Player should start with empty hands before interacting with crate")
		assert(source_area.can_interact(player), "Empty-handed player should be able to interact with crate %s" % config["item_id"])
		assert(source_area.get_interaction_prompt(player) == config["expected_prompt"], "Expected prompt '%s', got '%s'" % [config["expected_prompt"], source_area.get_interaction_prompt(player)])

		player._on_area_entered(source_area)
		assert(GameControl.interaction_prompt == config["expected_prompt"], "GameControl prompt mismatch for %s: expected '%s', got '%s'" % [config["item_id"], config["expected_prompt"], GameControl.interaction_prompt])

		# 2. Pick up item from crate
		GameControl.request_interaction()
		assert(player.has_held_item(), "Player did not receive held item after interacting with crate %s" % config["item_id"])
		assert(player.is_holding(config["item_id"]), "Player is not holding item %s" % config["item_id"])
		assert(player._held_item_visual != null, "Held item visual was not instantiated for %s" % config["item_id"])

		# 3. Single item restriction: player cannot pick up another item while holding one
		assert(not source_area.can_interact(player), "Player already holding an item must NOT be able to interact with crate %s" % config["item_id"])
		for other_config: Dictionary in CRATE_CONFIGS:
			var other_scene: PackedScene = other_config["scene"]
			var other_temp: Node3D = other_scene.instantiate() as Node3D
			var other_area: ItemSource = other_temp.get_node_or_null(other_config["area_name"]) as ItemSource
			assert(not other_area.can_interact(player), "Player holding an item must NOT be able to pick up from other crate %s" % other_config["item_id"])
			other_temp.queue_free()

		# Exit area and clear held item
		player._on_area_exited(source_area)
		var taken_item := player.take_held_item()
		assert(taken_item != null and taken_item.item_id == config["item_id"], "take_held_item did not return correct item")
		assert(not player.has_held_item(), "Player hands should be empty after take_held_item")
		assert(player._held_item_visual == null, "Visual should be cleared after clearing hand")

		tested_crates.append(str(config["item_id"]))
		crate_instance.queue_free()
		await get_tree().physics_frame

	print("CRATE_INTERACTION_SMOKE_PASS: All %d crates verified successfully: %s" % [tested_crates.size(), str(tested_crates)])
	get_tree().quit(0)
