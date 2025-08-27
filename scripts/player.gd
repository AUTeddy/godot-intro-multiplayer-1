class_name Player
extends CharacterBody2D

const SPEED = 600.0
const JUMP_VELOCITY = -400.0

@export var player_input: PlayerInput
@export var input_synchronizer: MultiplayerSynchronizer

func _enter_tree() -> void:
	player_input.set_multiplayer_authority(str(name).to_int())

func _ready() -> void:
	input_synchronizer.set_visibility_for(1, true)

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		var direction := player_input.input_dir
		if direction:
			velocity.x = direction.x * SPEED
			velocity.y = direction.y * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.y = move_toward(velocity.y, 0, SPEED)

		move_and_slide()
