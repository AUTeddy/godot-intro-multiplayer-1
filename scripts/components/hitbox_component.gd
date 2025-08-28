class_name HitboxComponent
extends Area2D

@export var damage: int = 1

signal hit_hurtbox(hurtbox)

func _ready() -> void:
	area_entered.connect(_on_hurtbox_entered)

func _on_hurtbox_entered(hurtbox: Area2D):
	if get_parent().fired_by_name == hurtbox.get_parent().name: return

	if not hurtbox is HurtboxComponent: return

	hit_hurtbox.emit(hurtbox)

	hurtbox.hurt.emit(self)
