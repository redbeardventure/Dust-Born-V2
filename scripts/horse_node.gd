class_name HorseNode
extends Node2D
## A horse or cow in play-test. It wanders slowly around the spot where it was placed; horses can
## also be ridden by the player (see Player.toggle_mount). Drawn by a PropNode child (PropNode._draw_horse);
## `heading` turns the art, with 0 = head pointing up (-y) like the editor prop.

const SPEED := 38.0
const TURN_SPEED := 2.4       # radians per second while turning on the spot
const WANDER_RADIUS := 140.0  # how far from its placed position it grazes
const BODY_LAYER := 4         # own physics layer: blocks walking, but not shots, sight or the path grid
const BODY_SIZE := Vector2(26, 80)
const COW_BODY_SIZE := Vector2(34, 72)
const COW_SPEED_SCALE := 0.65  # cattle amble more slowly than horses

var kind := "horse_chestnut"
## Horses can be ridden; cattle (rideable = false) only wander, more slowly and closer to home.
var rideable := true
var seed_v := 0
var size_scale := 1.0
var heading := 0.0
var rider: Node2D = null

var _art: PropNode
var _body: StaticBody2D
var _shape: CollisionShape2D
var _home := Vector2.ZERO
var _target := Vector2.ZERO
var _wait := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_home = position
	_target = position
	_wait = _rng.randf_range(1.0, 4.0)
	add_to_group("animals")
	if rideable:
		add_to_group("horses")  # the player only looks for rideable animals in this group
	_art = PropNode.new()
	_art.kind = kind
	_art.seed_v = seed_v
	_art.scale = Vector2(size_scale, size_scale)
	add_child(_art)
	_body = StaticBody2D.new()
	_body.collision_layer = BODY_LAYER
	_body.collision_mask = 0
	_shape = CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = (BODY_SIZE if rideable else COW_BODY_SIZE) * size_scale
	_shape.shape = rs
	_body.add_child(_shape)
	add_child(_body)
	_apply_heading()


## Distance from the centre at which the player can climb on.
func reach() -> float:
	return 52.0 * size_scale


## Direction the head points, in world space.
func forward() -> Vector2:
	return Vector2.UP.rotated(heading)


func _apply_heading() -> void:
	_art.rotation = heading
	_body.rotation = heading
	_art.queue_redraw()  # PropNode keeps its shadow direction fixed in world space


func _physics_process(delta: float) -> void:
	if rider != null:
		return
	if _wait > 0.0:
		_wait -= delta
		return
	var to := _target - position
	if to.length() < 3.0:
		_target = _pick_target()
		_wait = _rng.randf_range(2.0, 6.0)  # stand and graze for a while
		return
	var dir := to.normalized()
	var want := dir.angle() + PI * 0.5
	heading = rotate_toward(heading, want, TURN_SPEED * delta)
	_apply_heading()
	if absf(angle_difference(heading, want)) > 0.35:
		return  # turn most of the way before walking off
	var step := minf(SPEED * (1.0 if rideable else COW_SPEED_SCALE) * delta, to.length())
	if not _clear(dir * maxf(step, 1.0) * 6.0):
		_target = position  # something in the way (wall, player, another horse): pick again later
		return
	position += dir * step


## A random spot near home that the horse can walk to in a straight line.
func _pick_target() -> Vector2:
	for i in 12:
		var radius := WANDER_RADIUS if rideable else WANDER_RADIUS * 0.75
		var p := _home + Vector2.RIGHT.rotated(_rng.randf() * TAU) * _rng.randf_range(20.0, radius)
		if _clear(p - position):
			return p
	return position


## True when a horse-sized circle can move by `motion` without hitting walls, water, props,
## the player or other horses.
func _clear(motion: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = 16.0 * size_scale
	q.shape = c
	q.collision_mask = 1 | 2 | BODY_LAYER
	q.exclude = [_body.get_rid()]
	q.transform = Transform2D(0.0, global_position)
	q.motion = motion
	var r := get_world_2d().direct_space_state.cast_motion(q)
	return r.size() >= 1 and r[0] >= 1.0


func mount(by: Node2D) -> void:
	rider = by
	_shape.set_deferred("disabled", true)


## Rider got off: the horse stays here and grazes around its new spot.
func dismount() -> void:
	rider = null
	_home = position
	_target = position
	_wait = _rng.randf_range(2.0, 5.0)
	_shape.set_deferred("disabled", false)


## Called by the rider every frame: puts the horse under them, facing `facing`.
func follow(rider_pos: Vector2, facing: Vector2) -> void:
	heading = facing.angle() + PI * 0.5
	position = rider_pos + facing * 3.0 * size_scale  # rider sits on the saddle, just behind the middle
	_apply_heading()
