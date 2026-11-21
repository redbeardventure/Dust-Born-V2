class_name OpeningNode
extends Node2D
## A door or window set into a wall. The node sits on the wall's centre line and is rotated to
## follow the wall (local +x runs along the wall).
## Door: solid and blocks light while closed; can be opened or kicked open (swings away from the user).
## Window: blocks movement but not light, so you can see through it.

const SWING := 1.6  # radians a door leaf swings when opened (~92 degrees)

var kind := "door"
var width := 48.0
var thick := 12.0
var physics := false  # build collision (play-test only)

var is_open := false
var _angle := 0.0     # current leaf angle around the hinge
var _target := 0.0
var _vel := 0.0
var _kicked := false
var _flash := 0.0     # brief impact flash after a kick
var _shape: CollisionShape2D
var _occluder: LightOccluder2D


func _ready() -> void:
	var t := _t()
	var half := Vector2(width, t) * 0.5
	if kind == "door":
		var occ := OccluderPolygon2D.new()
		occ.polygon = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])
		_occluder = LightOccluder2D.new()
		_occluder.occluder = occ
		add_child(_occluder)
	if physics:
		add_to_group("openings")  # clickable in play-test (player walks up to it)
		var body := StaticBody2D.new()
		_shape = CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(width, t)
		_shape.shape = rs
		body.add_child(_shape)
		add_child(body)
	set_process(false)


func _t() -> float:
	return maxf(thick, 10.0)


## True when a click at `p` (world space) lands on this door/window (with a little slack).
func hit_test(p: Vector2) -> bool:
	var l := to_local(p)
	return absf(l.x) < width * 0.5 + 4.0 and absf(l.y) < _t() * 0.5 + 8.0


## Where someone coming from `from` should stand to use this opening: in front of its middle,
## on the same side of the wall as they are, `gap` px clear of the wall face.
func approach_point(from: Vector2, gap: float = 20.0) -> Vector2:
	var side := signf(to_local(from).y)
	if side == 0.0:
		side = 1.0
	return to_global(Vector2(0, side * (_t() * 0.5 + gap)))


## True when `p` (world space) is standing in the doorway, so the door must not close on it.
func blocks_point(p: Vector2) -> bool:
	var l := to_local(p)
	return absf(l.x) < width * 0.5 + 12.0 and absf(l.y) < _t() * 0.5 + 16.0


## Opens a closed door. It swings away from `from` (the opener's position).
func open(from: Vector2, kicked: bool = false) -> void:
	if kind != "door" or is_open:
		return
	is_open = true
	_kicked = kicked
	var side := signf(to_local(from).y)
	if side == 0.0:
		side = 1.0
	_target = -side * SWING * (1.2 if kicked else 1.0)
	if kicked:
		_vel = _target * 6.0  # the kick gives the leaf a hard shove
		_flash = 0.25
	_set_solid(false)
	set_process(true)


func close() -> void:
	if kind != "door" or not is_open:
		return
	is_open = false
	_kicked = false
	_target = 0.0
	_set_solid(true)
	set_process(true)


func _set_solid(solid: bool) -> void:
	if _shape != null:
		_shape.set_deferred("disabled", not solid)
	if _occluder != null:
		_occluder.visible = solid


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	# Spring toward the target: gently damped normally, bouncy after a kick.
	var k := 150.0 if _kicked else 70.0
	var c := 7.0 if _kicked else 15.0
	_vel += ((_target - _angle) * k - _vel * c) * delta
	_angle += _vel * delta
	_flash = maxf(_flash - delta, 0.0)
	if absf(_target - _angle) < 0.002 and absf(_vel) < 0.03 and _flash <= 0.0:
		_angle = _target
		_vel = 0.0
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if kind == "window":
		_draw_window()
	else:
		_draw_door()


func _draw_door() -> void:
	var t := _t()
	var w := width
	var wood := Color("7a5230")
	var wood_hi := Color("9a6c42")
	var edge := Color(0.1, 0.07, 0.04, 0.95)
	# Floor strip under the doorway, visible once the leaf has swung away.
	draw_rect(Rect2(-w * 0.5, -t * 0.5, w, t), Color(0.22, 0.16, 0.1))
	# Door leaf, hinged at the left end.
	draw_set_transform(Vector2(-w * 0.5 + 1.0, 0), _angle, Vector2.ONE)
	var leaf := Rect2(0, -t * 0.38, w - 2.0, t * 0.76)
	draw_rect(Rect2(leaf.position + Vector2(1.5, 2.5), leaf.size), Color(0, 0, 0, 0.3))
	draw_rect(leaf, wood)
	draw_rect(Rect2(leaf.position, Vector2(leaf.size.x, leaf.size.y * 0.4)), wood_hi)
	for i in range(1, 4):
		var x := leaf.size.x * float(i) / 4.0
		draw_line(Vector2(x, leaf.position.y), Vector2(x, leaf.end.y), Color(edge, 0.55), 1.0)
	draw_rect(leaf, edge, false, 1.5)
	draw_circle(Vector2(leaf.size.x - 7.0, 0), 1.8, Color("d8b04a"))  # handle
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Door frame posts at both ends.
	for sx in [-1.0, 1.0]:
		var post := Rect2(Vector2(sx * w * 0.5 - 2.5, -t * 0.5 - 1.0), Vector2(5.0, t + 2.0))
		draw_rect(post, Color("3a2818"))
		draw_rect(post, edge, false, 1.0)
	if _flash > 0.0:  # kick impact
		var a := _flash / 0.25
		for i in 6:
			var ang := TAU * float(i) / 6.0 + 0.3
			draw_line(Vector2(cos(ang), sin(ang)) * 6.0, Vector2(cos(ang), sin(ang)) * (12.0 + 8.0 * (1.0 - a)), Color(1.0, 0.9, 0.5, a), 2.0)


func _draw_window() -> void:
	var t := _t()
	var w := width
	var frame := Color("4a3a2c")
	var glass := Color(0.62, 0.84, 0.95, 0.38)
	var edge := Color(0.1, 0.07, 0.04, 0.95)
	var outer := Rect2(-w * 0.5, -t * 0.5, w, t)
	var pane := outer.grow(-2.5)
	# Frame as four borders so the glass area stays see-through.
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, 2.5)), frame)
	draw_rect(Rect2(Vector2(outer.position.x, pane.end.y), Vector2(outer.size.x, 2.5)), frame)
	draw_rect(Rect2(outer.position, Vector2(2.5, outer.size.y)), frame)
	draw_rect(Rect2(Vector2(pane.end.x, outer.position.y), Vector2(2.5, outer.size.y)), frame)
	draw_rect(pane, glass)
	# Glints and a centre bar.
	draw_line(pane.position + Vector2(pane.size.x * 0.15, pane.size.y), pane.position + Vector2(pane.size.x * 0.35, 0), Color(1, 1, 1, 0.55), 1.2)
	draw_line(pane.position + Vector2(pane.size.x * 0.28, pane.size.y), pane.position + Vector2(pane.size.x * 0.42, 0), Color(1, 1, 1, 0.35), 1.0)
	draw_line(Vector2(0, pane.position.y), Vector2(0, pane.end.y), frame, 2.0)
	draw_rect(outer, edge, false, 1.5)
