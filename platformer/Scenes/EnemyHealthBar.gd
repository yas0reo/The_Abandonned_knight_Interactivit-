extends ProgressBar

@export var follow_offset := Vector2(0, -17)

var parent_enemy: Node2D

func _ready():
	parent_enemy = get_parent()
	
	# Don't override position - use what's set in the scene
	z_index = 100
	show_percentage = false
	
	# Initialize health values from parent
	if parent_enemy:
		if parent_enemy.has_method("get") and parent_enemy.get("max_health") != null:
			max_value = parent_enemy.max_health
		if parent_enemy.has_method("get") and parent_enemy.get("health") != null:
			value = parent_enemy.health

func _process(_delta):
	if parent_enemy:
		# Update health value
		if parent_enemy.has_method("get") and parent_enemy.get("health") != null:
			value = parent_enemy.health
		
		# Hide when at full health
		visible = value < max_value
