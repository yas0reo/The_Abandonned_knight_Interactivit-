extends Area2D

@export var speed := 400.0
@export var damage := 20
@export var lifetime := 3.0
@export var rotation_speed := 10.0

var direction := Vector2.RIGHT
var traveled_time := 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready():
	body_entered.connect(_on_body_entered)
	
	# Auto-destroy after lifetime
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(delta):
	# Move projectile
	position += direction * speed * delta
	traveled_time += delta
	
	# Rotate sprite for visual effect (optional)
	if sprite:
		sprite.rotation += rotation_speed * delta

func set_direction(dir: Vector2):
	direction = dir.normalized()
	
	# Rotate sprite to face direction (optional - disable if you want sprite to always face right)
	# if sprite:
	#	sprite.rotation = direction.angle()

func _on_body_entered(body):
	# Don't hit the player who shot it
	if body.is_in_group("player"):
		return
	
	# Deal damage to enemies
	if body.is_in_group("enemies") and body.has_method("take_damage"):
		body.take_damage(damage)
		print("Projectile hit ", body.name, " for ", damage, " damage")
	
	# Destroy on impact with anything solid
	if body is TileMap or body is StaticBody2D or body.is_in_group("enemies"):
		destroy()

func destroy():
	# Optional: Add hit effect/animation here
	queue_free()
