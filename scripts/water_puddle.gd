class_name WaterPuddle
extends Node2D
## Water spilled from a barrel that was shot apart. Spreads out over a moment, then stays.

const SPREAD_TIME := 1.4

var radius := 30.0
var _t := 0.0
var _blob := PackedVector2Array()  # unit-radius irregular outline


## Adds a puddle at `pos` under `parent`'s other children (so props and characters draw on top).
static func spawn(parent: Node, pos: Vector2, size_scale: float = 1.0) -> WaterPuddle:
	var p := WaterPuddle.new()
	p.position = pos
	p.radius = 30.0 * size_scale
	parent.add_child(p)
	parent.move_child(p, 0)
	return p


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var n := 16
	for i in n:
		var a := TAU * float(i) / float(n)
		_blob.append(Vector2(cos(a), sin(a)) * rng.randf_range(0.72, 1.0))


func _process(delta: float) -> void:
	if _t < SPREAD_TIME:
		_t += delta
		queue_redraw()
	else:
		set_process(false)


func _draw() -> void:
	var k := smoothstep(0.0, 1.0, clampf(_t / SPREAD_TIME, 0.0, 1.0))
	var r := radius * k
	if r < 1.0:
		return
	var pts := PackedVector2Array()
	for v in _blob:
		pts.append(v * r)
	draw_colored_polygon(pts, Color(0.12, 0.3, 0.42, 0.55))  # wet edge
	var inner := PackedVector2Array()
	for v in _blob:
		inner.append(v * r * 0.82)
	draw_colored_polygon(inner, Color(0.25, 0.55, 0.7, 0.6))
	draw_arc(Vector2(-r * 0.2, -r * 0.2), r * 0.45, 3.4, 4.9, 10, Color(1, 1, 1, 0.35), 2.0)  # glint
