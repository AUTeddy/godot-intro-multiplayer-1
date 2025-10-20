#event_data.gd
@tool
class_name EventBridgeData extends Resource

@export var categories: Dictionary = {}
@export var category_order: Array = []   # Stores category order
@export var event_orders: Dictionary = {} # Stores event order per category
