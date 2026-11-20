class_name Player
extends CharacterBody2D
## Simple top-down test character with a lantern and a follow camera.

const SPEED := 160.0
const TURN_RATE := 14.0  # how fast the character turns to face its direction (higher = snappier)
const HeadArt := preload("res://scripts/head_art.gd")

## Selected head (hat or hair, see head_art.gd); static so the choice is kept between play-test sessions.
static var head_style := 0
## Selected weapon key ("none" or a key in Weapons.RANGED); static like head_style.
static var weapon := "none"

const MAX_HP := 100

signal health_changed(hp: int, max_hp: int)

var map_size := Vector2(2048, 1728)
var facing := Vector2.DOWN
var hp := MAX_HP
var _spawn := Vector2.ZERO
var _cooldown := 0.0
var _hurt_flash := 0.0
var _ammo := {}  # weapon key -> shots left; missing = full magazine
var _reload_left := 0.0  # seconds until the reload finishes (0 = not reloading)
## Locked-on NPC (click it or press Tab). Space / F fire at it. Cleared when it dies or gets too far away.
var target: Node2D = null
var _reticle: Node2D

const TARGET_RANGE := 900.0  # Tab only picks NPCs this close; a target further away than this is dropped
const CLICK_RADIUS := 18.0


func _ready() -> void:
	# Top-down: no floor/gravity. The default "grounded" mode treats walls and props as slopes and
	# snaps to a floor, which makes the character hop and bounce along obstacles.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_mask = 1 | 2  # world + water
	add_to_group("combatants")
	add_to_group("player")
	_spawn = position
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

	_reticle = Node2D.new()
	_reticle.top_level = true
	_reticle.z_index = 21
	_reticle.visible = false
	_reticle.draw.connect(_draw_reticle)
	add_child(_reticle)
	_build_grid()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_tick_reload(delta)
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(_hurt_flash - delta, 0.0)
		queue_redraw()
	_update_target()
	# Holding right mouse keeps firing at the cursor (at the weapon's fire rate).
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and get_viewport().gui_get_hovered_control() == null:
		shoot_at(get_global_mouse_position())
	# Holding Space or F fires at the locked target, or straight ahead without one.
	elif Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_F):
		shoot_at(target.global_position if target != null else global_position + facing * 100.0)
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
		# Turn toward the move direction over a few frames instead of snapping.
		var target := dir.normalized()
		if facing.dot(target) < -0.99:
			facing = facing.rotated(0.2)  # slerp has no defined path for an exact reversal
		facing = facing.slerp(target, minf(1.0, TURN_RATE * delta)).normalized()
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


## Re-checks which path-finding cells inside `area` are blocked (call after a door opens or closes).
func refresh_nav(area: Rect2) -> void:
	if _grid == null:
		return
	# Let the physics server apply the door's collision change first.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 11.0
	q.shape = shape
	q.exclude = [get_rid()]
	var lo := _cell(area.position)
	var hi := _cell(area.end)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			q.transform = Transform2D(0.0, Vector2(x + 0.5, y + 0.5) * CELL)
			_grid.set_point_solid(Vector2i(x, y), not space.intersect_shape(q, 1).is_empty())


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
		# Clicking an NPC targets it (clicking the current target again clears it); elsewhere = walk there.
		var npc := _npc_at(get_global_mouse_position())
		if npc != null:
			set_target(null if npc == target else npc)
		else:
			_move_to(get_global_mouse_position())
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				reload()
			KEY_TAB:
				cycle_target()
			KEY_X:
				set_target(null)
			_:
				return
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- combat

func set_weapon(key: String) -> void:
	weapon = key if (key == "none" or Weapons.is_ranged(key)) else "none"
	_reload_left = 0.0  # switching weapons cancels a reload in progress
	queue_redraw()


## Shots left in the current weapon's magazine (each weapon keeps its own count).
func ammo() -> int:
	return int(_ammo.get(weapon, Weapons.mag_size(weapon)))


func is_reloading() -> bool:
	return _reload_left > 0.0


## 0..1 progress of the reload in progress (1 when not reloading).
func reload_progress() -> float:
	if not is_reloading() or not Weapons.is_ranged(weapon):
		return 1.0
	return 1.0 - _reload_left / float(Weapons.RANGED[weapon]["reload"])


## Starts refilling the magazine (R, or automatically when it runs dry).
func reload() -> void:
	if not Weapons.is_ranged(weapon) or is_reloading() or ammo() >= Weapons.mag_size(weapon):
		return
	_reload_left = float(Weapons.RANGED[weapon]["reload"])


func _tick_reload(delta: float) -> void:
	if _reload_left <= 0.0:
		return
	_reload_left -= delta
	if _reload_left <= 0.0:
		_reload_left = 0.0
		_ammo[weapon] = Weapons.mag_size(weapon)


## Fires the selected weapon toward `target` if it is ranged, loaded and off cooldown.
func shoot_at(target: Vector2) -> void:
	if not Weapons.is_ranged(weapon) or _cooldown > 0.0 or hp <= 0 or is_reloading():
		return
	if ammo() <= 0:
		reload()
		return
	var dir := target - global_position
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	facing = dir
	_cooldown = float(Weapons.RANGED[weapon]["cooldown"])
	_ammo[weapon] = ammo() - 1
	Projectile.fire(get_tree().current_scene, weapon, global_position, dir, self)
	if ammo() <= 0:
		reload()
	queue_redraw()


func set_target(npc: Node2D) -> void:
	target = npc
	if target != null:
		facing = (target.global_position - global_position).normalized()
		queue_redraw()
	_reticle.visible = target != null


## Picks the nearest NPC in range, or the next-nearest after the current target on repeat presses.
## Hostile NPCs come first so Tab finds threats before bystanders.
func cycle_target() -> void:
	var list: Array = []
	for n in get_tree().get_nodes_in_group("npcs"):
		if is_instance_valid(n) and global_position.distance_to(n.global_position) <= TARGET_RANGE:
			list.append(n)
	if list.is_empty():
		set_target(null)
		return
	list.sort_custom(func(a, b) -> bool:
		var ha: bool = a.disposition == "hostile"
		var hb: bool = b.disposition == "hostile"
		if ha != hb:
			return ha
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	var i := list.find(target)
	set_target(list[(i + 1) % list.size()])


func _npc_at(p: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := CLICK_RADIUS
	for n in get_tree().get_nodes_in_group("npcs"):
		var d: float = p.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


## Drops a dead or distant target and keeps the reticle on it.
func _update_target() -> void:
	if target != null and (not is_instance_valid(target) or target.is_queued_for_deletion()
			or global_position.distance_to(target.global_position) > TARGET_RANGE):
		target = null
		_reticle.visible = false
	if target != null:
		_reticle.global_position = target.global_position
		_reticle.queue_redraw()


func _draw_reticle() -> void:
	var col := Color(1.0, 0.3, 0.25) if target != null and target.get("disposition") == "hostile" else Color(1.0, 0.9, 0.4)
	var t := Time.get_ticks_msec() / 1000.0
	var r := 16.0 + sin(t * 6.0) * 1.5
	_reticle.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, col, 1.5)
	for k in 4:
		var d := Vector2.RIGHT.rotated(k * PI * 0.5 + t * 0.8)
		_reticle.draw_line(d * (r - 4.0), d * (r + 5.0), col, 2.0)


func take_damage(amount: int, _from: Node) -> void:
	if hp <= 0:
		return
	hp = maxi(hp - amount, 0)
	_hurt_flash = 0.25
	if hp == 0:
		# Simple play-test respawn: back to the spawn point with full health.
		_clear_path()
		position = _spawn
		reset_physics_interpolation()
		hp = MAX_HP
		_ammo.clear()  # respawn with full magazines
		_reload_left = 0.0
	health_changed.emit(hp, MAX_HP)
	queue_redraw()


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
	_path = _smooth_path(position, pts)
	_stuck = 0.0
	_marker_pos = pts[pts.size() - 1]
	_marker.visible = true
	_marker.queue_redraw()


## The grid path visits every 16px cell centre, which makes the character zig-zag and turn in steps.
## This drops waypoints that can be skipped: from each point, jump to the furthest later waypoint
## the character's collision circle can reach in a straight line.
func _smooth_path(from: Vector2, pts: PackedVector2Array) -> PackedVector2Array:
	const LOOKAHEAD := 48
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.5
	q.shape = shape
	q.exclude = [get_rid()]
	var out := PackedVector2Array()
	var anchor := from
	var i := 0
	while i < pts.size():
		var j := mini(i + LOOKAHEAD, pts.size() - 1)
		while j > i:
			q.transform = Transform2D(0.0, anchor)
			q.motion = pts[j] - anchor
			var r := space.cast_motion(q)
			if r.size() >= 1 and r[0] >= 1.0:
				break
			j -= 1
		out.append(pts[j])
		anchor = pts[j]
		i = j + 1
	return out


func _clear_path() -> void:
	_path = PackedVector2Array()
	_stuck = 0.0
	if _marker:
		_marker.visible = false


func _draw_marker() -> void:
	_marker.draw_arc(_marker_pos, 10.0, 0.0, TAU, 24, Color(1, 0.9, 0.4, 0.9), 2.0)
	_marker.draw_circle(_marker_pos, 3.0, Color(1, 0.9, 0.4, 0.9))


func _draw() -> void:
	# Body is kept small so it stays hidden under the hat or hair (the collision circle is unchanged).
	draw_circle(Vector2(3, 4), 7.0, Color(0, 0, 0, 0.3))
	draw_circle(Vector2.ZERO, 6.0, Color("3b6fb0"))
	draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 16, Color("101820"), 1.5)
	Weapons.draw_held(self, weapon, facing, facing.orthogonal() * 9.0 + facing * 2.0)
	_draw_hat()
	if _hurt_flash > 0.0:
		draw_circle(Vector2.ZERO, 11.0, Color(1, 0.1, 0.1, _hurt_flash * 2.0))


## Draws the selected hat or hair turned to `facing`, with a face dot peeking out the front.
func _draw_hat() -> void:
	HeadArt.draw(self, head_style, Vector2.ZERO, facing.angle())
	var face := facing * (HeadArt.front(head_style) - 0.3)
	draw_circle(face, 2.2, HeadArt.face_color(head_style))
	draw_arc(face, 2.2, 0.0, TAU, 10, Color(0.12, 0.08, 0.04, 0.9), 1.0)


func set_head(idx: int) -> void:
	head_style = clampi(idx, 0, HeadArt.count() - 1)
	queue_redraw()
