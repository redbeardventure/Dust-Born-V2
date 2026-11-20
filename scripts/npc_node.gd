class_name NpcNode
extends Node2D
## A non-player character drawn procedurally (top-down). When `animate` is on (play-test),
## it wanders to random points inside its patrol area.

const HeadArt := preload("res://scripts/head_art.gd")
const SPEED := 55.0
const FRIENDLY_COL := Color("4caf5a")
const HOSTILE_COL := Color("c93a3a")

var npc_name := "NPC"
var weapon := "none"
var disposition := "friendly"
var head := -1  # index into head_art.gd, -1 = no hat/hair
var patrol := PackedVector2Array()
var animate := false

var _facing := Vector2.DOWN
var _target := Vector2.ZERO
var _wait := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_target = position
	_wait = _rng.randf_range(0.2, 1.5)
	set_process(animate and patrol.size() >= 3)


func _process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		return
	var to := _target - position
	if to.length() < 3.0:
		_target = _random_patrol_point()
		_wait = _rng.randf_range(0.6, 2.5)
		return
	_facing = to.normalized()
	position += _facing * minf(SPEED * delta, to.length())
	queue_redraw()


func _random_patrol_point() -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in patrol:
		lo = lo.min(v)
		hi = hi.max(v)
	for i in 30:
		var p := Vector2(_rng.randf_range(lo.x, hi.x), _rng.randf_range(lo.y, hi.y))
		if Geometry2D.is_point_in_polygon(p, patrol):
			return p
	return position


func _draw() -> void:
	var col := HOSTILE_COL if disposition == "hostile" else FRIENDLY_COL
	draw_circle(Vector2(3, 4), 11.0, Color(0, 0, 0, 0.3))
	draw_circle(Vector2.ZERO, 10.0, col)
	draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 20, Color("101820"), 2.0)
	# Weapon points the way the NPC is facing.
	if weapon != "none":
		var side := _facing.orthogonal()
		var base := side * 9.0 + _facing * 2.0
		var length := 12.0
		match weapon:
			"dagger":
				length = 8.0
			"spear", "staff":
				length = 22.0
			"rifle", "bow":
				length = 16.0
		draw_line(base, base + _facing * length, Color("d0d4d8"), 2.5)
		if weapon == "bow":
			draw_arc(base + _facing * 8.0, 7.0, _facing.angle() - PI * 0.5 + 0.3, _facing.angle() + PI * 0.5 - 0.3, 8, Color("9a6a3a"), 1.5)
	# Head (hat or hair) over the body, with the face dot peeking out the front.
	if head >= 0 and head < HeadArt.count():
		HeadArt.draw(self, head, Vector2.ZERO, _facing.angle())
		var face := _facing * (HeadArt.front(head) - 0.3)
		draw_circle(face, 2.2, Color("e8c9a0"))
		draw_arc(face, 2.2, 0.0, TAU, 10, Color(0.12, 0.08, 0.04, 0.9), 1.0)
	else:
		draw_circle(_facing * 5.0, 2.4, Color("e8c9a0"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-60, -16), npc_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color.WHITE)
