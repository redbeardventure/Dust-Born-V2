class_name TouchStick
extends Control
## On-screen thumbstick. Drag the knob with the mouse or a finger; `output` is the push as a
## vector (length 0..1, zero inside the dead zone). The player reads it as extra walking input.

const RADIUS := 70.0     # how far the knob can travel from the centre (px)
const DEAD_ZONE := 0.15  # push below this fraction counts as no input

var output := Vector2.ZERO
var _knob := Vector2.ZERO
var _touch := -2  # -2 = idle, -1 = mouse, >= 0 = touch finger index


func _init() -> void:
	custom_minimum_size = Vector2(RADIUS * 2.0 + 20.0, RADIUS * 2.0 + 20.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -2:
			_touch = event.index
			_drag_to(event.position)
		elif not event.pressed and event.index == _touch:
			_release()
		accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _touch:
			_drag_to(event.position)
		accept_event()
	# Mouse events also cover a finger on a phone (Godot emulates a mouse from the first touch).
	# If a real touch event already took the stick, _touch is >= 0 and these are ignored.
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _touch == -2:
			_touch = -1
			_drag_to(event.position)
		elif not event.pressed and _touch == -1:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and _touch == -1:
		_drag_to(event.position)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_release()


## `local` is in this control's own coordinates (what _gui_input gives).
func _drag_to(local: Vector2) -> void:
	_knob = (local - size * 0.5).limit_length(RADIUS)
	var push := _knob / RADIUS
	output = Vector2.ZERO if push.length() < DEAD_ZONE else push
	queue_redraw()


func _release() -> void:
	_touch = -2
	_knob = Vector2.ZERO
	output = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, RADIUS, Color(0, 0, 0, 0.25))
	draw_arc(c, RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 2.0, true)
	draw_circle(c + _knob, 28.0, Color(1, 1, 1, 0.55 if _touch != -2 else 0.35))
	draw_arc(c + _knob, 28.0, 0.0, TAU, 32, Color(0, 0, 0, 0.5), 2.0, true)
