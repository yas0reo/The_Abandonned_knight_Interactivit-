extends CharacterBody2D

# --- CONFIG ---
@export var move_speed := 250.0
@export var spawn_detection_range := 600.0
@export var chase_detection_range := 999999.0  # Chase toujours
@export var max_health := 300
@export var attack1_damage := 20
@export var attack2_damage := 15
@export var stun_duration := 0.3
@export var attack_range := 120.0
@export var attack_cooldown := 2.0  # Délai entre les attaques
@export var damage_threshold := 100  # Dégâts requis pour stun majeur
@export var major_stun_duration := 1.0  # Durée du stun majeur

# --- VARIABLES ---
var current_health := max_health
var is_stunned := false
var is_active := false
var is_dead := false
var player: Node = null
var can_attack := true
var has_spawned := false
var is_currently_attacking := false
var last_attack_type := 0
var damage_accumulated := 0  # Dégâts accumulés pour le stun majeur
var last_health_threshold := max_health  # Dernier seuil de santé passé

# --- NODES ---
@onready var anim = $AnimatedSprite2D
@onready var stun_timer = Timer.new()
@onready var detection_area = $DetectionArea
@onready var boss_camera = $BossCamera

# --- READY ---
func _ready():
	add_to_group("enemies")
	anim.play("idle")
	anim.connect("animation_finished", Callable(self, "_on_animation_finished"))
	
	# Setup stun timer
	add_child(stun_timer)
	stun_timer.one_shot = true
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
	
	# Toujours chasser le joueur (chase_detection_range est très grand)
	if not is_currently_attacking:
		# Attaque si dans la portée
		if distance < attack_range and can_attack:
			# Attaque normale aléatoire (attack1 ou attack2)
			var attack_choice = randi() % 2 + 1  # 1 ou 2
			start_attack(attack_choice)
		else:
			# Poursuivre le joueur
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
	
	move_and_slide()

func start_attack(attack_type: int):
	is_currently_attacking = true
	can_attack = false
	velocity.x = 0
	last_attack_type = attack_type
	
	var damage := 0
	var anim_name := ""
	var attack_duration := 0.0
	var damage_frame_time := 0.0
	
	match attack_type:
		1:  # Attack1 - 12 frames @ 10fps = 1.2s
			damage = attack1_damage
			anim_name = "attack1"
			attack_duration = 12.0 / 10.0  # 1.2 secondes
			damage_frame_time = 6.0 / 10.0  # Frame 6
		2:  # Attack2 - 8 frames @ 5fps = 1.6s
			damage = attack2_damage
			anim_name = "attack2"
			attack_duration = 8.0 / 5.0  # 1.6 secondes
			damage_frame_time = 4.0 / 5.0  # Frame 4
	
	anim.play(anim_name)
	
	# Attendre la frame de dégâts
	await get_tree().create_timer(damage_frame_time).timeout
	
	# Infliger les dégâts
	if player and is_instance_valid(player) and not is_dead and not is_stunned:
		var distance = global_position.distance_to(player.global_position)
		if distance < attack_range:
			if player.has_method("take_damage"):
				player.take_damage(damage)
				print("Demon Boss dealt ", damage, " damage to player (Attack ", attack_type, ")")
	
	# Attendre la fin de l'animation
	var remaining_time = attack_duration - damage_frame_time
	await get_tree().create_timer(remaining_time).timeout
	
	velocity.x = 0
	is_currently_attacking = false
	
	# Cooldown de 2 secondes avant la prochaine attaque
	if not is_dead and not is_stunned:
		await get_tree().create_timer(attack_cooldown).timeout
		if not is_dead and not is_stunned:
			can_attack = true

# --- DAMAGE HANDLING ---
func take_damage(amount: int, attack_type: String = ""):
	if not is_active or is_dead:
		return
	
	current_health -= amount
	
	print("Demon Boss took ", amount, " damage. Health: ", current_health, "/", max_health)
	
	if current_health <= 0:
		die()
	else:
		# Vérifier si on a perdu 100 PV ou plus depuis le dernier seuil
		var current_threshold = int(current_health / damage_threshold) * damage_threshold
		if current_threshold < last_health_threshold:
			last_health_threshold = current_threshold
			# Stun majeur de 1 seconde
			major_stun()
		else:
			# Stun normal de 0.3 secondes
			stun()

# --- STUN ---
func stun():
	is_stunned = true
	can_attack = false
	is_currently_attacking = false
	velocity.x = 0
	
	# Play stun animation
	if anim.sprite_frames.has_animation("stun"):
		anim.play("stun")
	
	stun_timer.start(stun_duration)

func major_stun():
	is_stunned = true
	can_attack = false
	is_currently_attacking = false
	velocity.x = 0
	
	print("Demon Boss - Major Stun! Lost 100 HP threshold")
	
	# Play stun animation
	if anim.sprite_frames.has_animation("stun"):
		anim.play("stun")
	
	stun_timer.start(major_stun_duration)

func _on_stun_timeout():
	if not is_dead:
		is_stunned = false
		can_attack = true
		anim.play("idle")

# --- DEATH ---
func die():
	is_dead = true
	is_stunned = false
	can_attack = false
	is_currently_attacking = false
	velocity.x = 0
	
	freeze_all_entities(true)
	anim.play("death")
	lock_camera(3.0)  # Focus camera pour effet dramatique
	
	# Disable collision
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	
	# Attendre la fin de l'animation de mort
	# death: 12 frames @ 5fps = 2.4 secondes
	await get_tree().create_timer(12.0 / 5.0).timeout
	
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
