class_name ActionCard
extends Control
## One playing-card style special action shown along the bottom of the screen in combat.
## Rests with only its top half on screen; slides up fully while hovered. Click to play it.

signal played(kind: String)

const SIZE := Vector2(110, 160)
const RISE_TIME := 0.12

var kind := ""
var title := ""
var desc := ""
var accent := Color(0.85, 0.3, 0.25)
var usable := true
var used := false  # already played this turn (shown with a USED stamp)

var rest_y := 0.0  # y position while resting (half the card below the screen edge)
var _hover := false
var _tween: Tween


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))


func set_state(can_use: bool, was_used: bool) -> void:
	if can_use == usable and was_used == used:
		return
	usable = can_use
	used = was_used
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if usable else Control.CURSOR_ARROW
	queue_redraw()


func _set_hover(on: bool) -> void:
	_hover = on
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position:y", rest_y - (SIZE.y * 0.5 if on else 0.0), RISE_TIME)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if usable:
			played.emit(kind)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, SIZE)
	var dim := 1.0 if usable else 0.55
	# Card face: cream paper with a coloured inner border, like a playing card.
	var face := StyleBoxFlat.new()
	face.bg_color = Color(0.96, 0.93, 0.85).darkened(0.0 if usable else 0.35)
	face.border_color = Color(0.2, 0.15, 0.1)
	face.set_border_width_all(2)
	face.set_corner_radius_all(8)
	face.shadow_color = Color(0, 0, 0, 0.4)
	face.shadow_size = 4
	draw_style_box(face, r)
	var inner := StyleBoxFlat.new()
	inner.draw_center = false
	inner.border_color = Color(accent, dim)
	inner.set_border_width_all(2)
	inner.set_corner_radius_all(5)
	draw_style_box(inner, r.grow(-6))
	if _hover and usable:
		draw_rect(r.grow(-2), Color(1.0, 0.85, 0.3, 0.9), false, 2.0)
	var font := ThemeDB.fallback_font
	var ink := Color(0.15, 0.1, 0.08, dim)
	# Title and icon sit in the top half, the part that shows while the card rests.
	draw_string(font, Vector2(8, 24), title, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x - 16, 14, ink)
	_draw_icon(Vector2(SIZE.x * 0.5, 52), Color(accent, dim))
	# Rules text in the bottom half (seen when the card rises on hover).
	var y := 92.0
	for line in _wrap(desc, font, 11, SIZE.x - 20):
		draw_string(font, Vector2(10, y), line, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x - 20, 11, ink)
		y += 14.0
	if used:
		draw_set_transform(SIZE * 0.5 + Vector2(0, -38), -0.35, Vector2.ONE)
		draw_rect(Rect2(-34, -12, 68, 22), Color(0.75, 0.15, 0.12, 0.85), false, 2.0)
		draw_string(font, Vector2(-34, 5), "USED", HORIZONTAL_ALIGNMENT_CENTER, 68, 14, Color(0.75, 0.15, 0.12, 0.9))
		draw_set_transform_matrix(Transform2D.IDENTITY)


## Simple word wrap for the rules text.
func _wrap(text: String, font: Font, fsize: int, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" "):
		var test := word if line == "" else line + " " + word
		if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > width and line != "":
			out.append(line)
			line = word
		else:
			line = test
	if line != "":
		out.append(line)
	return out


func _draw_icon(c: Vector2, col: Color) -> void:
	match kind:
		"dash":  # running chevrons
			for i in 3:
				var x := c.x - 16.0 + i * 11.0
				draw_polyline(PackedVector2Array([Vector2(x, c.y - 10), Vector2(x + 9, c.y), Vector2(x, c.y + 10)]), col, 3.0)
		"aim":  # crosshair
			draw_arc(c, 12.0, 0.0, TAU, 28, col, 2.5)
			draw_arc(c, 4.0, 0.0, TAU, 12, col, 2.0)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				draw_line(c + d * 8.0, c + d * 17.0, col, 2.5)
		"reload":  # cartridges
			for i in 3:
				var x := c.x - 12.0 + i * 12.0
				draw_rect(Rect2(x - 3, c.y - 6, 6, 16), col)
				draw_circle(Vector2(x, c.y - 6), 3.0, col)
				draw_line(Vector2(x - 3, c.y + 6), Vector2(x + 3, c.y + 6), Color(0.15, 0.1, 0.08, col.a), 1.5)
