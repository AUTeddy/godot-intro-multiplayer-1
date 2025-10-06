class_name AttributeComponent
extends Node

@export var starting_health = 5

@export var health: int = 5:
	set(value):
		health = value
		
		health_changed.emit()
		
		if health == 0:
			no_health.emit()

signal health_changed
signal no_health

func reset_health():
	health = starting_health
