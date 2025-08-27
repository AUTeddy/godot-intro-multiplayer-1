extends Area2D

@export var projectile_sprite: AnimatedSprite2D
@export var speed: float = 600.0

@onready var _visible_on_screen_notifier_2d: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D

var flip_dir: int = 1
var fired_by_name: String

func _ready() -> void:
	if flip_dir > 0:
		projectile_sprite.flip_h = true
	
	if is_multiplayer_authority():
		_visible_on_screen_notifier_2d.screen_exited.connect(queue_free)
		
func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		var dist = speed * delta
		translate(Vector2(flip_dir * dist, 0))

func _on_body_entered(body: Node2D) -> void:
	if body.name == fired_by_name: return

	if body is Player:
		projectile_sprite.animation = "explode"
		speed = 0
		if is_multiplayer_authority() and not projectile_sprite.animation_finished.has_connections():
			projectile_sprite.animation_finished.connect(queue_free)
