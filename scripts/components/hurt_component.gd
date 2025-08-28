class_name HurtComponent
extends Node

@export var hurtbox_component: HurtboxComponent
@export var attribute_component: AttributeComponent

func _ready() -> void:
	hurtbox_component.hurt.connect(func(hitbox_component: HitboxComponent):
		if is_multiplayer_authority():
			attribute_component.health -= hitbox_component.damage
			print("Player health %s" % attribute_component.health)
	)
