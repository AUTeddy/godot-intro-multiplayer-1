@tool
extends Button

@export var tooltip_title := "Title"
@export_multiline var tooltip_bbcode := ""
@export var scene_path := "res://addons/event_bridge/ui/editor_tooltip.tscn"
@export var width := 350.0
@export var max_height := 320.0

var _tip: Control
var _hide_timer := Timer.new()

const CURSOR_OFFSET := Vector2(16, 20)
const CLAMP_PAD := Vector2(8, 8)

func _ready() -> void:
	tooltip_text = " " # keep default tooltip pipeline alive so _make_custom_tooltip is called
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_cancel_hide)
	mouse_exited.connect(_schedule_hide)

	_hide_timer.one_shot = true
	_hide_timer.wait_time = 0.25 # a bit more grace to enter the popup
	_hide_timer.timeout.connect(_maybe_hide)
	add_child(_hide_timer)

func _exit_tree() -> void:
	if is_instance_valid(_tip):
		_tip.queue_free()

func _make_custom_tooltip(_for_text: String) -> Control:
	_show_or_update_sticky()
	var dummy := Label.new() # return a dummy so engine doesn't render its own tooltip
	dummy.tooltip_text = ""
	return dummy

func _show_or_update_sticky() -> void:
	if !is_instance_valid(_tip):
		var ps: PackedScene = load(scene_path)
		if ps == null:
			push_error("Tooltip scene not found: " + scene_path)
			return
		_tip = ps.instantiate()
		_tip.name = "StickyTooltip"
		_tip.mouse_filter = Control.MOUSE_FILTER_STOP
		_tip.z_index = 4096
		_tip.mouse_entered.connect(_cancel_hide)
		_tip.mouse_exited.connect(_schedule_hide)

		# Make sure it positions from top-left
		_tip.set_anchors_preset(Control.PRESET_TOP_LEFT)

		# Control parent for both editor and game
		var host: Control = (EditorInterface.get_base_control() if Engine.is_editor_hint() else get_tree().root)
		host.add_child(_tip)

	# Fill content
	var title: Label = _tip.get_node_or_null("%ToolTipTitle")
	if title:
		title.text = tooltip_title

	var body: RichTextLabel = _tip.get_node_or_null("%ToolTipBody")
	if body:
		body.bbcode_enabled = true
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.fit_content = true
		body.clear()
		body.parse_bbcode(tooltip_bbcode)

	# Ensure scroll wheel works inside the tooltip (and panel too)
	var scroll: ScrollContainer = _tip.get_node_or_null("VBoxContainer/ScrollContainer")
	if scroll:
		scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := _tip.get_node_or_null("Panel")
	if panel is Control:
		panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Size: fixed width, dynamic height (capped)
	_tip.custom_minimum_size = Vector2(width, 0)
	await get_tree().process_frame # let content compute its size
	var h := 0.0
	if body:
		h += body.get_content_height()
	if title:
		h += title.get_minimum_size().y
	h += 12.0 # padding fudge; adjust to your theme
	_tip.custom_minimum_size = Vector2(width, min(h, max_height))

	# Wait one more frame so _tip.size reflects the new min size
	#await get_tree().process_frame
	_place_tooltip()

	_cancel_hide()
	_tip.show()

func _place_tooltip() -> void:
	var host: Control = (EditorInterface.get_base_control() if Engine.is_editor_hint() else get_tree().root)

	# Start below-right of the cursor
	var mouse := host.get_local_mouse_position()
	var pos := mouse + CURSOR_OFFSET
	var s := _tip.size
	var host_sz := host.get_size()

	# Flip horizontally/vertically if overflowing
	if pos.x + s.x + CLAMP_PAD.x > host_sz.x:
		pos.x = mouse.x - s.x - CURSOR_OFFSET.x
	if pos.y + s.y + CLAMP_PAD.y > host_sz.y:
		pos.y = mouse.y - s.y - CURSOR_OFFSET.y

	# Final clamp to stay fully on-screen
	pos.x = clamp(pos.x, CLAMP_PAD.x, host_sz.x - s.x - CLAMP_PAD.x)
	pos.y = clamp(pos.y, CLAMP_PAD.y, host_sz.y - s.y - CLAMP_PAD.y)

	_tip.position = pos.floor()

func _schedule_hide() -> void:
	_hide_timer.start()

func _cancel_hide() -> void:
	_hide_timer.stop()

func _maybe_hide() -> void:
	if !is_instance_valid(_tip):
		return
	# Use global rect checks (more robust than local mouse tests)
	var gp := get_global_mouse_position()
	var over_label := get_global_rect().has_point(gp)
	var over_tip := _tip.get_global_rect().has_point(gp)
	if !over_label and !over_tip:
		_tip.hide()
