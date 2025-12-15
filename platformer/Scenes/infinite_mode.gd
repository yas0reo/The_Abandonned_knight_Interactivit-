extends Node2D

# --- SPAWNER SETTINGS ---
@export var spawn_interval := 5.0
@export var max_enemies := 10
@export var spawn_range := Vector2(800, 400)
@export var spawn_offset := Vector2(0, 0)

# --- ENEMY SCENES ---
@export var enemy_scenes: Array[PackedScene] = []

# --- INTERNAL ---
var spawn_timer := 0.0
var current_enemy_count := 0

func _ready():
	if enemy_scenes.is_empty():
		var skeleton_scene = load("res://Scenes/skeleton.tscn")
		if skeleton_scene:
			enemy_scenes.append(skeleton_scene)
	get_tree().node_added.connect(_on_node_added)

func _process(delta):
	spawn_timer += delta
	
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		spawn_random_enemy()

func spawn_random_enemy():
	if current_enemy_count >= max_enemies:
		print("Max enemies reached: ", max_enemies)
		return
		
	if enemy_scenes.is_empty():
		print("No enemy scenes to spawn!")
		return
	
	var random_index = randi() % enemy_scenes.size()
	var enemy_scene = enemy_scenes[random_index]
	
	if not enemy_scene:
		print("Invalid enemy scene at index ", random_index)
		return
	
	var enemy = enemy_scene.instantiate()

	var random_x = randf_range(-spawn_range.x / 2, spawn_range.x / 2)
	var random_y = randf_range(-spawn_range.y / 2, spawn_range.y / 2)
	enemy.position = global_position + spawn_offset + Vector2(random_x, random_y)

	get_parent().add_child(enemy)
	
	current_enemy_count += 1
	print("Spawned enemy at: ", enemy.position, " | Total enemies: ", current_enemy_count)

func _on_node_added(node):
	if node.is_in_group("enemies"):
		node.tree_exiting.connect(_on_enemy_removed)

func _on_enemy_removed():
	current_enemy_count = max(0, current_enemy_count - 1)
	print("Enemy removed. Remaining: ", current_enemy_count)
