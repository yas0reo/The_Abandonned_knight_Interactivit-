extends CharacterBody2D

# --- STATS ---
@export var max_health := 75
@export var attack1_damage := 20
@export var attack2_damage := 15
@export var move_speed := 100.0
@export var detection_range := 500.0
@export var attack_range := 80.0
@export var stun_duration := 0.8

var health : int
var is_dead := false
var is_hurt := false
var is_stunned := false
var can_attack := true
var is_attacking := false

# --- WANDERING ---
var wander_direction := 1.0
var wander_timer := 0.0
var next_wander_time := 3.0

# --- PLAYER TRACKING ---
var player: CharacterBody2D

# --- NODES ---
@onready var anim = $AnimatedSprite2D
@onready var detection_area = $DetectionArea
@onready var attack_area = $AttackArea
@onready var attack_collision = $AttackArea/AttackShape
@onready var health_bar = $HealthBar

var attack_collision_base_x := 0.0

func _ready():
	add_to_group("enemies")
	health = max_health
	
	# Store base attack position
	if attack_collision:
		attack_collision_base_x = abs(attack_collision.position.x)
		attack_collision.disabled = true
	
	# Connect area signals
	if detection_area:
		detection_area.body_entered.connect(_on_detection_entered)
		detection_area.body_exited.connect(_on_detection_exited)
	
	if attack_area:
		attack_area.body_entered.connect(_on_attack_area_entered)
	
	# Start idle
	if anim:
		anim.play("idle")
	
	# Random starting direction
	randomize()
	wander_direction = 1.0 if randf() > 0.5 else -1.0
	next_wander_time = randf_range(2.0, 5.0)

func _physics_process(delta):
	if is_dead:
		return
	
	# Apply gravity
	if not is_on_floor():
		velocity.y += ProjectSettings.get_setting("physics/2d/default_gravity") * delta
	
	# Flip attack collision to match direction
	if attack_collision:
		if anim and anim.flip_h:
			attack_collision.position.x = -attack_collision_base_x
		else:
			attack_collision.position.x = attack_collision_base_x
	
	# Stop movement when hurt, stunned, or attacking
	if is_hurt or is_stunned or is_attacking:
		velocity.x = 0
		move_and_slide()
		return
	
	# Update wander timer
	wander_timer += delta
	
	# Check for player
	player = Global.playerBody
	
	if player and is_instance_valid(player):
		var distance = position.distance_to(player.position)
		
		if distance <= detection_range:
			# Player detected - chase or attack
			if distance <= attack_range and can_attack:
				perform_attack()
			else:
				chase_player()
		else:
			# Player too far - wander
			wander()
	else:
		# No player - wander
		wander()
	
	move_and_slide()

# --- WANDERING ---
func wander():
	# Change direction periodically
	if wander_timer >= next_wander_time:
		wander_timer = 0.0
		next_wander_time = randf_range(2.0, 5.0)
		
		# 70% chance to move, 30% chance to idle
		if randf() < 0.7:
			wander_direction = 1.0 if randf() > 0.5 else -1.0
		else:
			wander_direction = 0.0
	
	# Move or idle
	if wander_direction != 0:
		velocity.x = wander_direction * move_speed
		if anim:
			anim.flip_h = wander_direction < 0
			if anim.animation != "walk":
				anim.play("walk")
	else:
		velocity.x = 0
		if anim and anim.animation != "idle":
			anim.play("idle")

# --- CHASING ---
func chase_player():
	if not player or not is_instance_valid(player):
		return
	
	var direction = sign(player.position.x - position.x)
	velocity.x = direction * move_speed
	
	if anim:
		anim.flip_h = direction < 0
		if anim.animation != "walk":
			anim.play("walk")

# --- DETECTION ---
func _on_detection_entered(body):
	if body.is_in_group("player"):
		player = body

func _on_detection_exited(body):
	if body.is_in_group("player"):
		player = null

func _on_attack_area_entered(body):
	if body.is_in_group("player") and can_attack and not is_attacking:
		perform_attack()

# --- ATTACKING ---
func perform_attack():
	if is_attacking or is_stunned or is_hurt:
		return
	
	can_attack = false
	is_attacking = true
	velocity.x = 0
	
	# Randomly choose attack (50/50)
	var attack_type = randi() % 2 + 1
	var damage = 0
	var attack_duration = 0.0
	var attack_anim = ""
	
	if attack_type == 1:
		damage = attack1_damage
		attack_duration = 1.2
		attack_anim = "attack2"
	else:
		damage = attack2_damage
		attack_duration = 0.8
		attack_anim = "attack1"
	
	# Play animation
	if anim:
		anim.play(attack_anim)
	
	# Enable hitbox
	if attack_collision:
		attack_collision.disabled = false
	
	# Wait for hit timing
	await get_tree().create_timer(attack_duration * 0.4).timeout
	apply_attack_damage(damage)
	
	# Wait for animation to finish
	await get_tree().create_timer(attack_duration * 0.6).timeout
	
	# Disable hitbox
	if attack_collision:
		attack_collision.disabled = true
	
	is_attacking = false
	
	# Attack cooldown
	await get_tree().create_timer(1.0).timeout
	can_attack = true

func apply_attack_damage(damage: int):
	if not attack_area or not player or not is_instance_valid(player):
		return
	
	var bodies = attack_area.get_overlapping_bodies()
	
	for body in bodies:
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(damage)
			print("Skeleton dealt ", damage, " damage to player")
			break

# --- TAKING DAMAGE ---
func take_damage(amount: int, attack_type: String = ""):
	if is_dead or is_stunned:
		return
	
	health -= amount
	print("Skeleton took ", amount, " damage. Health: ", health)
	
	# Update health bar
	if health_bar:
		health_bar.value = health
	
	if health <= 0:
		die()
		return
	
	apply_hurt()

func apply_hurt():
	if is_dead:
		return
	
	is_hurt = true
	is_stunned = true
	is_attacking = false
	can_attack = false
	velocity.x = 0
	
	# Play hurt animation
	if anim:
		anim.play("hurt")
		# Red flash
		var tween = create_tween()
		tween.tween_property(anim, "modulate", Color(1, 0.4, 0.4), 0.1)
	
	# Stun duration
	await get_tree().create_timer(stun_duration).timeout
	
	if not is_dead:
		# Remove red flash
		if anim:
			var tween2 = create_tween()
			tween2.tween_property(anim, "modulate", Color(1, 1, 1), 0.2)
		
		is_hurt = false
		is_stunned = false
		can_attack = true
		
		if anim:
			anim.play("idle")

# --- DEATH ---
func die():
	is_dead = true
	is_attacking = false
	is_hurt = false
	is_stunned = false
	velocity = Vector2.ZERO
	
	# Hide health bar
	if health_bar:
		health_bar.visible = false
	
	# Disable collision
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	
	# Play death animation
	if anim:
		anim.play("death")
		await anim.animation_finished
	else:
		await get_tree().create_timer(1.0).timeout
	
	# Fade out
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished
	
	queue_free()
