class_name Player
extends CharacterBody2D
## Simple top-down test character with a lantern and a follow camera.

const SPEED := 240.0
const HatArt := preload("res://scripts/hat_art.gd")

## Selected hat; static so the choice is kept between play-test sessions.
static var hat_style := 0

var map_size := Vector2(2048, 1728)
var facing := Vector2.DOWN


func _ready() -> void:
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	cs.shape = circle
	add_child(cs)

	var lantern := PointLight2D.new()
	lantern.texture = MapRenderer.light_texture()
	lantern.texture_scale = 2.6
	lantern.color = Color(1.0, 0.86, 0.62)
	lantern.energy = 0.9
	lantern.shadow_enabled = true
	lantern.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	add_child(lantern)

	var cam := Camera2D.new()
	cam.zoom = Vector2(1.4, 1.4)
	cam.position_smoothing_enabled = true
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(map_size.x)
	cam.limit_bottom = int(map_size.y)
	add_child(cam)
	cam.make_current()

	_marker = Node2D.new()
	_marker.top_level = true
	_marker.z_index = 20
	_marker.visible = false
	_marker.draw.connect(_draw_marker)
	add_child(_marker)
	_build_grid()


func _physics_process(delta: float) -> void:
	var dir := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	var speed := SPEED * (1.7 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if dir != Vector2.ZERO:
		_clear_path()  # keyboard overrides click-to-move
	elif not _path.is_empty():
		var to_next := _path[0] - position
		if to_next.length() < 6.0:
			_path.remove_at(0)
			if _path.is_empty():
				_clear_path()
		else:
			dir = to_next
	velocity = dir.normalized() * speed
	if dir != Vector2.ZERO:
		facing = dir.normalized()
		queue_redraw()
	var before := position
	move_and_slide()
	if not _path.is_empty():
		# Give up if blocked (no progress for half a second).
		if position.distance_to(before) < speed * delta * 0.25:
			_stuck += delta
			if _stuck > 0.5:
				_clear_path()
		else:
			_stuck = 0.0


# ---------------------------------------------------------------- click to move

const CELL := 16.0

var _grid: AStarGrid2D
var _path: PackedVector2Array = PackedVector2Array()
var _stuck := 0.0
var _marker: Node2D
var _marker_pos := Vector2.ZERO


func _build_grid() -> void:
	# Wait for the map's static bodies to register with the physics server.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var cols := int(ceil(map_size.x / CELL))
	var rows := int(ceil(map_size.y / CELL))
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, cols, rows)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.offset = Vector2(CELL, CELL) * 0.5
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 11.0
	q.shape = shape
	q.exclude = [get_rid()]
	for y in rows:
		for x in cols:
			q.transform = Transform2D(0.0, Vector2(x + 0.5, y + 0.5) * CELL)
			if not space.intersect_shape(q, 1).is_empty():
				_grid.set_point_solid(Vector2i(x, y), true)


func _cell(p: Vector2) -> Vector2i:
	var c := Vector2i((p / CELL).floor())
	return Vector2i(clampi(c.x, 0, _grid.region.size.x - 1), clampi(c.y, 0, _grid.region.size.y - 1))


## Nearest walkable cell to `c` (searching outward), or (-1,-1) if none is close.
func _nearest_free(c: Vector2i) -> Vector2i:
	for r in 8:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if _grid.is_in_boundsv(n) and not _grid.is_point_solid(n):
					return n
	return Vector2i(-1, -1)


func _unhandled_input(event: InputEvent) -> void:
	if _grid == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_move_to(get_global_mouse_position())
		get_viewport().set_input_as_handled()


func _move_to(target: Vector2) -> void:
	var goal := _nearest_free(_cell(target))
	if goal.x < 0:
		return
	var start := _cell(position)
	var start_was_solid := _grid.is_point_solid(start)
	if start_was_solid:
		_grid.set_point_solid(start, false)
	var pts := _grid.get_point_path(start, goal)
	if start_was_solid:
		_grid.set_point_solid(start, true)
	if pts.size() < 2:
		return
	pts.remove_at(0)  # current cell
	if _cell(target) == goal:
		pts[pts.size() - 1] = target
	_path = pts
	_stuck = 0.0
	_marker_pos = pts[pts.size() - 1]
	_marker.visible = true
	_marker.queue_redraw()


func _clear_path() -> void:
	_path = PackedVector2Array()
	_stuck = 0.0
	if _marker:
		_marker.visible = false


func _draw_marker() -> void:
	_marker.draw_arc(_marker_pos, 10.0, 0.0, TAU, 24, Color(1, 0.9, 0.4, 0.9), 2.0)
	_marker.draw_circle(_marker_pos, 3.0, Color(1, 0.9, 0.4, 0.9))


func _draw() -> void:
	draw_circle(Vector2(3, 4), 11.0, Color(0, 0, 0, 0.3))
	draw_circle(Vector2.ZERO, 10.0, Color("3b6fb0"))
	draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 20, Color("101820"), 2.0)
	_draw_hat()


## Draws the selected hat (see hat_art.gd) turned to `facing`, with a face dot peeking out the front.
func _draw_hat() -> void:
	HatArt.draw(self, hat_style, Vector2.ZERO, facing.angle())
	var face := facing * (HatArt.brim_front(hat_style) - 0.3)
	draw_circle(face, 2.2, Color("e8c9a0"))
	draw_arc(face, 2.2, 0.0, TAU, 10, Color(0.12, 0.08, 0.04, 0.9), 1.0)


func set_hat(idx: int) -> void:
	hat_style = clampi(idx, 0, HatArt.count() - 1)
	queue_redraw()
