extends Node

@export var player_input: PlayerInput
@export var projectile: PackedScene 
@export var projectile_spawn_path: Node2D

@onready var _parent_player = get_parent()


func _ready() -> void:
	player_input.weapon_fired.connect(_weapon_fired)
	EventManager.on_player_spawn_projectile(_spawn_projectile)

func _weapon_fired():
	#_spawn_projectile.rpc_id(1)
	pass	

#@rpc("any_peer", "call_local")
func _spawn_projectile():	
	#if is_multiplayer_authority():
	
	print(self, is_multiplayer_authority())
	
	var projectile_scene = projectile.instantiate() as Node2D
	projectile_scene.global_transform = _parent_player.global_transform.translated(Vector2(0, 18))
	projectile_scene.fired_by_name = _parent_player.name

	if not _parent_player.name == "1":
		projectile_scene.flip_dir = -1
		
	projectile_spawn_path.add_child(projectile_scene, true)
