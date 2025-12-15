extends CharacterBody2D

# --- CONFIG ---
@export var move_speed := 200.0
@export var spawn_detection_range := 600.0
@export var chase_detection_range := 350.0
@export var max_health := 450
@export var attack_damage := 50
@export var stun_damage_threshold := 50
@export var stun_duration := 2.0
@export var attack_range := 150.0

# --- VARIABLES ---
var current_health := max_health
var is_stunned := false
var is_active := false
var is_dead := false
var damage_accumulated := 0
var player: Node = null
var can_attack := true
var has_spawned := false
var is_currently_attacking := false

# --- NODES ---
@onready var anim = $AnimatedSprite2D
@onready var stun_timer = $StunTimer
@onready var detection_area = $DetectionArea
@onready var boss_camera = $BossCamera

# --- READY ---
func _ready():
	add_to_group("enemies")
	anim.play("fade_in")
	anim.connect("animation_finished", Callable(self, "_on_animation_finished"))
	stun_timer.timeout.connect(_on_stun_timeout)
	boss_camera.enabled = false
	
	# Make boss invisible until spawned
	modulate.a = 0.0

# --- MAIN LOOP ---
func _process(delta):
	if is_dead:
		return

	if not has_spawned:
		check_player_detection()
	elif is_active and not is_stunned:
		move_and_attack(delta)

# --- DETECTION ---
func check_player_detection():
	if not player:
		player = Global.playerBody
	
	if player and is_instance_valid(player):
		var distance = global_position.distance_to(player.global_position)
		if distance <= spawn_detection_range:
			spawn_boss()

# --- SPAWN ---
func spawn_boss():
	has_spawned = true
	modulate.a = 1.0
	anim.play("fade_in")
	lock_camera(3.0)
	freeze_all_entities(true)
	
	# Start boss music
	var boss_music = get_node_or_null("BossMusic")
	if boss_music and boss_music is AudioStreamPlayer:
		boss_music.play()
	
	await get_tree().create_timer(3.0).timeout
	freeze_all_entities(false)
	is_active = true
	anim.play("idle")

# --- CAMERA CONTROL ---
func lock_camera(duration: float):
	boss_camera.enabled = true
	boss_camera.make_current()
	await get_tree().create_timer(duration).timeout
	boss_camera.enabled = false

# --- MOVEMENT & ATTACK ---
func move_and_attack(delta):
	if not player or not is_instance_valid(player):
		player = Global.playerBody
		return
	
	# Apply gravity
	if not is_on_floor():
		velocity.y += ProjectSettings.get_setting("physics/2d/default_gravity") * delta
	
	var distance = global_position.distance_to(player.global_position)
	
	# Only chase if within detection range
	if distance <= chase_detection_range:
		# Attack if in range
		if distance < attack_range and can_attack and not is_currently_attacking:
			start_attack()
		elif not is_currently_attacking:
			# Chase player (only horizontal movement)
			var direction = (player.global_position - global_position).normalized()
			velocity.x = direction.x * move_speed
			
			# Flip sprite based on direction
			if direction.x < 0:
				anim.flip_h = true
			else:
				anim.flip_h = false
			
			# Play run animation when moving
			if absf(velocity.x) > 10:
				if anim.sprite_frames.has_animation("run"):
					anim.play("run")
				else:
					anim.play("idle")
			else:
				anim.play("idle")
	else:
		velocity.x = 0
		if not is_currently_attacking:
			anim.play("idle")
	
	move_and_slide()

func start_attack():
	is_currently_attacking = true
	can_attack = false
	velocity.x = 0  # Only stop horizontal movement
	anim.play("attack")
	
	# Wait for damage frame (frame 10 out of 12)
	var frame_time = 10.0 / 12.0  
	await get_tree().create_timer(frame_time).timeout

	# Deal damage
	if player and is_instance_valid(player) and not is_dead and not is_stunned:
		var distance = global_position.distance_to(player.global_position)
		if distance < attack_range:
			if player.has_method("take_damage"):
				player.take_damage(attack_damage)
				print("Boss dealt ", attack_damage, " damage to player")
	
	# Wait for animation to finish (total animation time at 10fps = 1.2 seconds)
	var remaining_time = (12.0 / 10.0) - frame_time
	await get_tree().create_timer(remaining_time).timeout
	
	is_currently_attacking = false
	
	# If still alive and not stunned, wait cooldown then allow next attack
	if not is_dead and not is_stunned:
		await get_tree().create_timer(1.5).timeout
		if not is_dead and not is_stunned:
			can_attack = true

# --- DAMAGE HANDLING ---
func take_damage(amount: int, attack_type: String = ""):
	if not is_active or is_dead or is_stunned:
		return
	
	current_health -= amount
	damage_accumulated += amount
	
	print("Boss took ", amount, " damage. Health: ", current_health, "/", max_health)
	
	if current_health <= 0:
		die()
	elif damage_accumulated >= stun_damage_threshold:
		damage_accumulated = 0
		stun()

# --- STUN ---
func stun():
	is_stunned = true
	can_attack = false
	is_currently_attacking = false
	velocity.x = 0  # Only stop horizontal movement, gravity still applies
	
	# Play stun animation
	if anim.sprite_frames.has_animation("stun"):
		anim.play("stun")
	
	stun_timer.start(stun_duration)

func _on_stun_timeout():
	if not is_dead:
		is_stunned = false
		can_attack = true  # Reset attack capability after stun
		anim.play("idle")

# --- DEATH ---
func die():
	is_dead = true
	is_stunned = false
	can_attack = false
	is_currently_attacking = false
	velocity.x = 0  # Only stop horizontal movement
	
	freeze_all_entities(true)
	anim.play("death")
	lock_camera(3.0)  # Focus camera again for dramatic effect
	
	# Disable collision
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	
	await anim.animation_finished
	freeze_all_entities(false)
	queue_free()

# --- ANIMATION EVENTS ---
func _on_animation_finished():
	if anim.animation == "fade_in" and has_spawned and not is_dead:
		is_active = true
		anim.play("idle")

# --- FREEZE ENTITIES ---
func freeze_all_entities(freeze: bool):
	# Freeze player
	if player and is_instance_valid(player):
		player.set_physics_process(not freeze)
	
	# Freeze all enemies
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy != self and is_instance_valid(enemy):
			enemy.set_physics_process(not freeze)
