class_name VultureShadow
extends Node2D
## The shadow of a vulture circling high above: every so often it glides across the map in a
## straight, slightly drifting line, wings flapping now and then, then waits before the next pass.

const SPEED := 90.0
const SIZE := 1.0  # overall scale of the silhouette
const MIN_WAIT := 8.0
const MAX_WAIT := 25.0
const MARGIN := 160.0  # how far outside the map a pass starts and ends

var map_size := Vector2(2048, 1728)
var _wait := 0.0
var _flying := false
var _dir := Vector2.RIGHT
var _drift := 0.0  # radians per second the heading bends
var _end_dist := 0.0
var _travelled := 0.0
var _flap_t := 0.0
var _glide := 0.0  # > 0: wings held out, not flapping


func _ready() -> void:
	z_index = 11
	visible = false
	_wait = randf_range(2.0, 6.0)


func _process(delta: float) -> void:
	if not _flying:
		_wait -= delta
		if _wait <= 0.0:
			_start_pass()
		return
	_dir = _dir.rotated(_drift * delta)
	position += _dir * SPEED * delta
	_travelled += SPEED * delta
	rotation = _dir.angle()
	if _glide > 0.0:
		_glide -= delta
		_flap_t += delta * 1.5
	else:
		_flap_t += delta * 7.0
		if randf() < delta * 0.35:
			_glide = randf_range(1.0, 2.5)
	if _travelled >= _end_dist:
		_flying = false
		visible = false
		_wait = randf_range(MIN_WAIT, MAX_WAIT)
	queue_redraw()


func _start_pass() -> void:
	# Enter from a point just outside the map and aim at a random point inside it.
	var side := randi() % 4
	var start := Vector2.ZERO
	match side:
		0: start = Vector2(-MARGIN, randf() * map_size.y)
		1: start = Vector2(map_size.x + MARGIN, randf() * map_size.y)
		2: start = Vector2(randf() * map_size.x, -MARGIN)
		_: start = Vector2(randf() * map_size.x, map_size.y + MARGIN)
	var target := map_size * Vector2(randf_range(0.25, 0.75), randf_range(0.25, 0.75))
	_dir = (target - start).normalized()
	_drift = randf_range(-0.08, 0.08)
	position = start
	rotation = _dir.angle()
	_travelled = 0.0
	_end_dist = start.distance_to(target) * 2.0 + MARGIN  # carries on past the middle and out
	_flap_t = randf() * TAU
	_glide = 0.0
	_flying = true
	visible = true
	queue_redraw()


func _draw() -> void:
	# Local +X is the flight direction. Wings sweep up and down by changing their span.
	var flap := sin(_flap_t) if _glide <= 0.0 else 0.15
	var span := (30.0 - 9.0 * absf(flap)) * SIZE
	var tip_back := (6.0 + 10.0 * flap) * SIZE  # tips swing back and forward as they beat
	var col := Color(0, 0, 0, 0.3)
	for side in [-1.0, 1.0]:
		var s: float = side
		draw_colored_polygon(PackedVector2Array([
			Vector2(5, 0) * SIZE,
			Vector2(2, s * span * 0.45),
			Vector2(-4 - tip_back * 0.3, s * span * 0.8),  # finger feathers
			Vector2(-9 - tip_back, s * span),
			Vector2(-12, s * span * 0.6),
			Vector2(-14, s * span * 0.25),
			Vector2(-8, 0),
		]), col)
	# Body, head with a small hooked beak, and a fanned tail.
	draw_colored_polygon(PackedVector2Array([
		Vector2(8, 0) * SIZE, Vector2(4, 4) * SIZE, Vector2(-8, 3) * SIZE,
		Vector2(-18, 6) * SIZE, Vector2(-18, -6) * SIZE, Vector2(-8, -3) * SIZE, Vector2(4, -4) * SIZE,
	]), col)
	draw_circle(Vector2(10, 0) * SIZE, 3.0 * SIZE, col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(12, -1.5) * SIZE, Vector2(16, 0.5) * SIZE, Vector2(12, 1.5) * SIZE,
	]), col)
