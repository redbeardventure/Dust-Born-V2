extends Control
## The player's deck of earned cards, shown face down at the bottom of the screen with the game logo
## on the back and the number of cards held. Click it to open the hand (see hand_popup.gd).

signal pressed

const SIZE := Vector2(110, 160)
const LOGO := preload("res://assets/branding/dustborn_logo.svg")
const RISE := 36.0  # px the deck lifts while hovered

var count := 0
var rest_y := 0.0
var _hover := false
var _tween: Tween


## Draws a face-down card back into `r` on `ci`: dark card, cream border, the game logo in the middle.
static func draw_back(ci: CanvasItem, r: Rect2, dim: float = 1.0) -> void:
	var face := StyleBoxFlat.new()
	face.bg_color = Color(0.17, 0.11, 0.09).lerp(Color(0.1, 0.1, 0.1), 1.0 - dim)
	face.border_color = Color(0.96, 0.93, 0.85, dim)
	face.set_border_width_all(3)
	face.set_corner_radius_all(8)
	face.shadow_color = Color(0, 0, 0, 0.4)
	face.shadow_size = 3
	ci.draw_style_box(face, r)
	var inner := StyleBoxFlat.new()
	inner.draw_center = false
	inner.border_color = Color(0.78, 0.4, 0.2, dim)
	inner.set_border_width_all(2)
	inner.set_corner_radius_all(5)
	ci.draw_style_box(inner, r.grow(-7))
	var side := minf(r.size.x, r.size.y) * 0.62
	ci.draw_texture_rect(LOGO, Rect2(r.get_center() - Vector2(side, side) * 0.5, Vector2(side, side)), false,
			Color(1, 1, 1, dim))


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = SIZE * 0.5
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))


func set_count(n: int) -> void:
	if n > count:
		pulse()
	count = n
	visible = count > 0  # no deck at all until the first card is dealt
	queue_redraw()


## A little bounce when a new card is dealt.
func pulse() -> void:
	if not is_inside_tree():
		return
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.12, 1.12), 0.1)
	t.tween_property(self, "scale", Vector2.ONE, 0.15)


func _set_hover(on: bool) -> void:
	_hover = on
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position:y", rest_y - (RISE if on and count > 0 else 0.0), 0.12)
	queue_redraw()


var _down := false  # a press started on the deck


## Acts on release, like a button: opening on the press let the same tap's release (or a second
## emulated touch event) land on the popup that had just appeared, which closed it again.
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if mb.pressed:
		_down = true
	elif _down:
		_down = false
		if count > 0 and Rect2(Vector2.ZERO, size).has_point(mb.position):
			pressed.emit()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, SIZE)
	var layers := mini(count, 3)
	for i in layers:
		var off := Vector2(-3.0, -3.0) * float(layers - 1 - i)
		draw_back(self, Rect2(off + Vector2(3, 3), SIZE - Vector2(6, 6)))
	if _hover:
		draw_rect(r.grow(-3), Color(1.0, 0.85, 0.3, 0.9), false, 2.0)
	# Count badge in the top-right corner.
	var c := Vector2(SIZE.x - 14.0, 16.0)
	draw_circle(c, 13.0, Color(0.8, 0.25, 0.2))
	draw_arc(c, 13.0, 0.0, TAU, 24, Color.WHITE, 2.0)
	draw_string(ThemeDB.fallback_font, c + Vector2(-13, 5), str(count), HORIZONTAL_ALIGNMENT_CENTER, 26, 14, Color.WHITE)
