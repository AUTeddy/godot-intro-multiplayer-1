extends Node2D

@export var projectile_sprite: AnimatedSprite2D
@export var speed: float = 600.0

@onready var _visible_on_screen_notifier_2d: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D
@onready var _hitbox_component: HitboxComponent = $HitboxComponent

var flip_dir: int = 1
var fired_by_name: String

func _ready() -> void:
	if flip_dir > 0:
		projectile_sprite.flip_h = true
	
	if is_multiplayer_authority():
		_visible_on_screen_notifier_2d.screen_exited.connect(queue_free)
		
	_hitbox_component.hit_hurtbox.connect(_hit_hurtbox)
	
func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		var dist = speed * delta
		translate(Vector2(flip_dir * dist, 0))

func _hit_hurtbox(hurtbox: HurtboxComponent) -> void:
	projectile_sprite.animation = "explode"
	speed = 0
	
	if is_multiplayer_authority() and not projectile_sprite.animation_finished.has_connections():
		projectile_sprite.animation_finished.connect(queue_free)
