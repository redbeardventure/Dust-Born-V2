class_name VultureShadow
extends Node2D
## The shadow of a vulture circling high above: every so often it glides across the map in a
## straight, slightly drifting line with wings held out (a still silhouette), then waits before the next pass.

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
	if _travelled >= _end_dist:
		_flying = false
		visible = false
		_wait = randf_range(MIN_WAIT, MAX_WAIT)


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
	_flying = true
	visible = true


## Right half of the soaring silhouette as (across, forward) pairs, from the head round the wing
## (feathered tip, scalloped trailing edge) to the tail centre. The left half is its mirror.
const HALF := [
	Vector2(0.8, 7.0), Vector2(1.6, 5.0), Vector2(2.0, 3.4), Vector2(7.0, 3.0), Vector2(14.0, 3.6),
	Vector2(19.0, 4.8), Vector2(23.5, 6.2), Vector2(21.8, 4.6), Vector2(25.5, 5.2), Vector2(23.0, 3.6),
	Vector2(26.7, 4.0), Vector2(24.0, 2.4), Vector2(26.8, 2.4), Vector2(23.8, 1.0), Vector2(25.8, 0.4),
	Vector2(22.5, -0.6), Vector2(19.0, -2.8), Vector2(15.0, -4.8), Vector2(10.0, -5.4), Vector2(7.5, -5.7),
	Vector2(7.4, -7.0), Vector2(5.5, -10.5), Vector2(2.0, -12.2), Vector2(0.0, -12.5),
]

static var _shape := PackedVector2Array()


func _draw() -> void:
	# Local +X is the flight direction, so (across, forward) becomes Vector2(forward, across).
	if _shape.is_empty():
		var pts := PackedVector2Array()
		for p: Vector2 in HALF:
			pts.append(Vector2(p.y, p.x))
		# Mirror half, skipping the tail centre that is already in the list.
		for i in range(HALF.size() - 2, -1, -1):
			var q: Vector2 = HALF[i]
			pts.append(Vector2(q.y, -q.x))
		_shape = pts
	var scaled := PackedVector2Array()
	for p in _shape:
		scaled.append(p * SIZE)
	draw_colored_polygon(scaled, Color(0, 0, 0, 0.3))
