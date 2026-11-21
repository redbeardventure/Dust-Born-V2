class_name Player
extends CharacterBody2D
## Simple top-down test character with a lantern and a follow camera.

const SPEED := 160.0
const STEP_LENGTH := 22.0  # pixels walked per step
const STEP_PULSE := 0.025  # how much bigger the character gets mid-step (0.025 = 2.5%)
const PRINT_LIFE := 6.0  # seconds a footprint takes to fade away
const MAX_PRINTS := 60
const TURN_RATE := 14.0  # how fast the character turns to face its direction (higher = snappier)
const HeadArt := preload("res://scripts/head_art.gd")

## Selected head (hat or hair, see head_art.gd); static so the choice is kept between play-test sessions.
static var head_style := 0
## Selected weapon key ("none" or a key in Weapons.RANGED); static like head_style.
static var weapon := "none"

const MAX_HP := 100

signal health_changed(hp: int, max_hp: int)
signal gold_changed(total: int, added: int)

## Coins in the player's purse (gold drops are picked up by walking over them). Kept on respawn.
var gold := 0


func add_gold(n: int) -> void:
	if n <= 0:
		return
	gold += n
	gold_changed.emit(gold, n)

var map_size := Vector2(2048, 1728)
var facing := Vector2.DOWN
var hp := MAX_HP
var _spawn := Vector2.ZERO
var _cooldown := 0.0
var _hurt_flash := 0.0
var _step_phase := 0.0
var _prints: Array = []  # footprints: {pos, ang, age}
var _print_layer: Node2D
var _print_dist := 0.0
var _print_left := true
var _step_amount := 0.0  # 0 = standing, 1 = walking (eases in/out so stopping isn't a snap)
var _ammo := {}  # weapon key -> shots left; missing = full magazine
var _reload_left := 0.0  # seconds until the reload finishes (0 = not reloading)
## Locked-on NPC (click it or press Tab). Space / F fire at it. Cleared when it dies or gets too far away.
var target: Node2D = null
var _reticle: Node2D
## Set while the on-screen Shoot button is held: fires at the target like holding Space / F.
var fire_held := false
## Selected door or window (click it). The player walks up to it; E / K then act on it.
var interact: Node2D = null
var _interact_marker: Node2D
var _interact_spot := Vector2.ZERO
var _interact_arrived := false

const INTERACT_REACH := 30.0  # close enough to the standing spot to count as arrived

const RIDE_SPEED := 300.0  # on horseback (Shift still speeds it up to a gallop)
const RIDE_RADIUS := 13.0  # collision circle while riding (walking = 10)

## Horse being ridden, or null when on foot.
var mount: HorseNode = null
## Horse clicked on: the player walks to it and climbs on when close enough.
var _mount_goal: HorseNode = null
var _body_circle: CircleShape2D

const TARGET_RANGE := 900.0  # Tab only picks NPCs this close; a target further away than this is dropped
const CLICK_RADIUS := 18.0


func _ready() -> void:
	# Top-down: no floor/gravity. The default "grounded" mode treats walls and props as slopes and
	# snaps to a floor, which makes the character hop and bounce along obstacles.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_mask = 1 | 2 | HorseNode.BODY_LAYER  # world + water + horses
	add_to_group("combatants")
	add_to_group("player")
	_spawn = position
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	_body_circle = circle
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

	_print_layer = Node2D.new()
	_print_layer.top_level = true
	_print_layer.show_behind_parent = true
	_print_layer.draw.connect(_draw_prints)
	add_child(_print_layer)

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

	_interact_marker = Node2D.new()
	_interact_marker.top_level = true
	_interact_marker.z_index = 21
	_interact_marker.visible = false
	_interact_marker.draw.connect(_draw_interact_marker)
	add_child(_interact_marker)
	_build_grid()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_tick_reload(delta)
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(_hurt_flash - delta, 0.0)
		queue_redraw()
	_update_target()
	_update_interact()
	# Holding right mouse keeps firing at the cursor (at the weapon's fire rate).
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and get_viewport().gui_get_hovered_control() == null:
		shoot_at(get_global_mouse_position())
	# Holding Space or F fires at the locked target, or straight ahead without one.
	elif Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_F) or (fire_held and is_instance_valid(target)):
		if is_instance_valid(target):
			shoot_at(target.global_position)
		else:
			shoot_at(global_position + facing * 100.0)
	var dir := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	var speed := (RIDE_SPEED if mount != null else SPEED) * (1.7 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
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
		var want := dir.normalized()
		if facing.dot(want) < -0.99:
			facing = facing.rotated(0.2)  # slerp has no defined path for an exact reversal
		var turn := TURN_RATE * (0.45 if mount != null else 1.0)  # a horse swings round more slowly
		facing = facing.slerp(want, minf(1.0, turn * delta)).normalized()
		queue_redraw()
	var before := position
	move_and_slide()
	if is_instance_valid(mount):
		mount.follow(global_position, facing)
	_update_mount_goal()
	# Step pulse follows distance actually walked, so running steps faster and pushing
	# into a wall doesn't animate. Each half-turn of the phase is one step.
	var moved := position.distance_to(before)
	_step_phase = fmod(_step_phase + moved / STEP_LENGTH * PI, TAU)
	_step_amount = move_toward(_step_amount, 1.0 if moved > 0.2 else 0.0, delta * 6.0)
	if _step_amount > 0.0:
		queue_redraw()
	_update_prints(delta, 0.0 if mount != null else moved)  # no footprints on horseback
	if not _path.is_empty():
		# Give up if blocked (no progress for half a second).
		if position.distance_to(before) < speed * delta * 0.25:
			_stuck += delta
			if _stuck > 0.5:
				_clear_path()
		else:
			_stuck = 0.0


# ---------------------------------------------------------------- footprints

## Leaves a print every step (alternating feet) and fades old ones out.
func _update_prints(delta: float, moved: float) -> void:
	if moved > 0.2:
		_print_dist += moved
		if _print_dist >= STEP_LENGTH:
			_print_dist = 0.0
			var side := 1.0 if _print_left else -1.0
			_print_left = not _print_left
			var dir := velocity.normalized() if velocity.length() > 1.0 else facing
			_prints.append({
				"pos": global_position + dir.orthogonal() * 4.0 * side + dir * 2.0,
				"ang": dir.angle(),
				"age": 0.0})
			if _prints.size() > MAX_PRINTS:
				_prints.pop_front()
	if _prints.is_empty():
		return
	for p in _prints:
		p["age"] += delta
	while not _prints.is_empty() and _prints[0]["age"] >= PRINT_LIFE:
		_prints.pop_front()
	_print_layer.queue_redraw()


func _draw_prints() -> void:
	for p in _prints:
		var a := (1.0 - float(p["age"]) / PRINT_LIFE) * 0.35
		_print_layer.draw_set_transform(p["pos"], float(p["ang"]), Vector2.ONE)
		_print_layer.draw_circle(Vector2(0, 0), 2.6, Color(0.1, 0.07, 0.04, a))  # sole
		_print_layer.draw_circle(Vector2(3.2, 0), 1.8, Color(0.1, 0.07, 0.04, a))  # toe
	_print_layer.draw_set_transform_matrix(Transform2D.IDENTITY)


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
		var mp := get_global_mouse_position()
		_mount_goal = null
		var horse := _horse_at(mp) if mount == null else null
		if horse != null and _npc_at(mp) == null:
			# Clicking a horse walks over to it and climbs on.
			set_interact(null)
			_mount_goal = horse
			if global_position.distance_to(horse.global_position) <= horse.reach():
				toggle_mount()
			else:
				_move_to(horse.global_position)
			get_viewport().set_input_as_handled()
			return
		var npc := _npc_at(mp)
		if npc == null:
			npc = _container_at(mp)  # barrels and crates are targets too, not walk-to selections
		var opening: Node2D = _opening_at(mp) if npc == null else null
		if npc != null:
			set_target(null if npc == target else npc)
		elif opening != null:
			# Doors / windows use their own selection (separate from the NPC target): walk up to it.
			if opening == interact:
				set_interact(null)
			else:
				set_interact(opening)
		else:
			set_interact(null)
			_move_to(mp)
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
	# Throw out one spent casing per round being reloaded, from the gun (part way along it).
	var spent := Weapons.mag_size(weapon) - ammo()
	var gun := Weapons.muzzle_offset(weapon, facing) * 0.55
	if gun == Vector2.ZERO:
		gun = facing * 12.0 + Vector2(-facing.y, facing.x) * 6.0
	ShellCasings.spawn(get_tree().current_scene, global_position + gun, facing, spent,
			"shell" if weapon == "shotgun" else "brass")


func _tick_reload(delta: float) -> void:
	if _reload_left <= 0.0:
		return
	_reload_left -= delta
	if _reload_left <= 0.0:
		_reload_left = 0.0
		_ammo[weapon] = Weapons.mag_size(weapon)


## False when a wall sits between the body and the muzzle (gun poking through a wall);
## the shot then starts from the body so it can't pass through.
func _muzzle_clear(muzzle: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, muzzle, Projectile.WORLD_MASK, [get_rid()])
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


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
	# Shots leave from the gun's muzzle when the weapon has an in-hand image (Projectile.fire adds 14px
	# along `dir`, so that is subtracted here). Re-aim from the muzzle so the shot still meets the target.
	var from := global_position
	var muzzle := global_position + Weapons.muzzle_offset(weapon, dir)
	if muzzle != global_position and _muzzle_clear(muzzle):
		var aim := target - muzzle
		if aim.length() > 20.0:
			dir = aim.normalized()
		from = muzzle - dir * 14.0
	Projectile.fire(get_tree().current_scene, weapon, from, dir, self)
	MuzzleFlash.spawn(get_tree().current_scene, from + dir * 14.0, dir)  # fire + smoke at the barrel tip
	if ammo() <= 0:
		reload()
	queue_redraw()


## Selects a door or window (or clears with null) and walks to the near side of it.
func set_interact(opening: Node2D) -> void:
	interact = opening if is_instance_valid(opening) else null
	_interact_arrived = false
	_interact_marker.visible = interact != null
	if interact == null:
		return
	_interact_spot = interact.call("approach_point", global_position)
	_move_to(_interact_spot)
	if _path.is_empty() and global_position.distance_to(_interact_spot) < INTERACT_REACH:
		_arrive_at_interact()  # already standing there
	_interact_marker.queue_redraw()


## True while following a click-to-move path.
func is_walking() -> bool:
	return not _path.is_empty()


func is_at_interact() -> bool:
	return is_instance_valid(interact) and _interact_arrived


## Door or window under `p` (the "go to it" selection).
func _opening_at(p: Vector2) -> Node2D:
	for n in get_tree().get_nodes_in_group("openings"):
		if n.call("hit_test", p):
			return n
	return null


## Barrel or crate under `p` (targetable like an NPC).
func _container_at(p: Vector2) -> Node2D:
	for n in get_tree().get_nodes_in_group("containers"):
		if n.call("hit_test", p):
			return n
	return null


## Turns to face the selected door/window once the walk there is over.
func _arrive_at_interact() -> void:
	_interact_arrived = true
	var to := interact.global_position - global_position
	if to.length() > 0.5:
		facing = to.normalized()
		queue_redraw()


func _update_interact() -> void:
	# A freed reference (barrel shot apart) is not == null, so test validity, not null.
	if not is_instance_valid(interact) or interact.is_queued_for_deletion():
		if _interact_marker.visible or interact != null:
			interact = null
			set_interact(null)
		return
	if not _interact_arrived and _path.is_empty() and global_position.distance_to(_interact_spot) < INTERACT_REACH:
		_arrive_at_interact()
	# The marker follows the opening's position and wall direction.
	_interact_marker.global_transform = interact.global_transform
	_interact_marker.queue_redraw()


## Selection for doors/windows: cyan corner brackets around the opening (the NPC target uses a red/yellow ring).
func _draw_interact_marker() -> void:
	if not is_instance_valid(interact):
		return
	var w: float = interact.get("width")
	var t: float = maxf(float(interact.get("thick")), 10.0)
	var t_s := Time.get_ticks_msec() / 1000.0
	var grow := 5.0 + sin(t_s * 5.0) * 1.5
	var r := Rect2(Vector2(-w * 0.5, -t * 0.5), Vector2(w, t)).grow(grow)
	var col := Color(0.35, 0.9, 1.0)
	var arm := minf(10.0, r.size.x * 0.3)
	_interact_marker.draw_rect(r, Color(col, 0.12))
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x < 0.0 else -1.0
		var sy := 1.0 if c.y < 0.0 else -1.0
		_interact_marker.draw_line(c, c + Vector2(arm * sx, 0), col, 2.5)
		_interact_marker.draw_line(c, c + Vector2(0, arm * sy), col, 2.5)


# ---------------------------------------------------------------- riding

## Horse under `p` (clicked on), or null.
func _horse_at(p: Vector2) -> HorseNode:
	for n in get_tree().get_nodes_in_group("horses"):
		var h := n as HorseNode
		if h == null or h.rider != null:
			continue
		var l := (p - h.global_position).rotated(-h.heading)
		if absf(l.x) < 18.0 * h.size_scale and absf(l.y) < 64.0 * h.size_scale:
			return h
	return null


## Closest free horse within climbing reach, or null.
func nearest_horse() -> HorseNode:
	var best: HorseNode = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("horses"):
		var h := n as HorseNode
		if h == null or h.rider != null:
			continue
		var d := global_position.distance_to(h.global_position)
		if d <= h.reach() and d < best_d:
			best_d = d
			best = h
	return best


## Climbs on the nearest horse, or gets off the one being ridden.
func toggle_mount() -> void:
	_mount_goal = null
	_clear_path()
	if mount != null:
		var spot := _dismount_spot()
		var h := mount
		mount = null
		h.dismount()
		_body_circle.radius = 10.0
		position = spot
		reset_physics_interpolation()
		queue_redraw()
		return
	var horse := nearest_horse()
	if horse == null:
		return
	mount = horse
	horse.mount(self)
	set_interact(null)
	facing = horse.forward()
	position = horse.global_position - facing * 3.0 * horse.size_scale  # sit on the saddle
	reset_physics_interpolation()
	_body_circle.radius = RIDE_RADIUS
	queue_redraw()


## A free spot beside the horse to step down onto (left side first, then right, then behind).
func _dismount_spot() -> Vector2:
	var side := facing.orthogonal()
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = 10.0
	q.shape = c
	q.collision_mask = 1 | 2
	q.exclude = [get_rid()]
	for off in [side * 30.0, -side * 30.0, -facing * 60.0, facing * 60.0]:
		var p: Vector2 = global_position + off
		q.transform = Transform2D(0.0, p)
		if space.intersect_shape(q, 1).is_empty():
			return p
	return global_position


## Walking to a clicked horse: climb on once close enough; give up if the walk stopped short.
func _update_mount_goal() -> void:
	if _mount_goal == null:
		return
	if not is_instance_valid(_mount_goal) or _mount_goal.rider != null:
		_mount_goal = null
		return
	if global_position.distance_to(_mount_goal.global_position) <= _mount_goal.reach():
		toggle_mount()
	elif _path.is_empty():
		_mount_goal = null


func set_target(npc: Node2D) -> void:
	if is_instance_valid(target) and target.has_signal("defeated") and target.is_connected("defeated", _on_target_defeated):
		target.disconnect("defeated", _on_target_defeated)
	target = npc if is_instance_valid(npc) else null
	# Drop the lock the moment the NPC is defeated.
	if target != null and target.has_signal("defeated"):
		target.connect("defeated", _on_target_defeated)
	if target != null:
		facing = (target.global_position - global_position).normalized()
		queue_redraw()
	_reticle.visible = target != null


## Picks the nearest NPC in range, or the next-nearest after the current target on repeat presses.
## Hostile NPCs come first so Tab finds threats before bystanders.
func cycle_target() -> void:
	var list: Array = []
	for g in ["npcs", "containers"]:
		for n in get_tree().get_nodes_in_group(g):
			if is_instance_valid(n) and global_position.distance_to(n.global_position) <= TARGET_RANGE:
				list.append(n)
	if list.is_empty():
		set_target(null)
		return
	# Order: hostile NPCs, other NPCs, then barrels / crates; nearest first within each.
	var rank := func(n: Node) -> int:
		if not n.is_in_group("npcs"):
			return 2
		return 0 if n.get("disposition") == "hostile" else 1
	list.sort_custom(func(a, b) -> bool:
		var ra: int = rank.call(a)
		var rb: int = rank.call(b)
		if ra != rb:
			return ra < rb
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


func _on_target_defeated(npc: Node) -> void:
	if npc == target:
		set_target(null)


## Drops a dead or distant target and keeps the reticle on it.
func _update_target() -> void:
	if not is_instance_valid(target):
		target = null  # also covers a freed reference, which isn't == null
	elif target.is_queued_for_deletion() or global_position.distance_to(target.global_position) > TARGET_RANGE:
		set_target(null)
	_reticle.visible = target != null
	if target != null:
		_reticle.global_position = target.global_position
		_reticle.queue_redraw()


func _draw_reticle() -> void:
	# Red = hostile NPC, orange = barrel / crate, yellow = other NPC.
	var col := Color(1.0, 0.9, 0.4)
	if is_instance_valid(target):
		if target.get("disposition") == "hostile":
			col = Color(1.0, 0.3, 0.25)
		elif target.is_in_group("containers"):
			col = Color(1.0, 0.6, 0.2)
	var t := Time.get_ticks_msec() / 1000.0
	var base_r := 16.0
	if is_instance_valid(target) and target.has_method("_radius"):  # barrels / crates: fit around the prop
		base_r = maxf(16.0, float(target.call("_radius")) + 5.0)
	var r := base_r + sin(t * 6.0) * 1.5
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
		if mount != null:
			toggle_mount()
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
	# Ground shadow stays the same size; the character above it pulses with each step.
	draw_circle(Vector2(3, 4), 7.0, Color(0, 0, 0, 0.3))
	var bs := step_scale()
	var xf := Vector2(bs, bs)
	draw_set_transform(Vector2.ZERO, 0.0, xf)
	# Body is kept small so it stays hidden under the hat or hair (the collision circle is unchanged).
	draw_circle(Vector2.ZERO, 6.0, Color("3b6fb0"))
	draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 16, Color("101820"), 1.5)
	var hold := facing.orthogonal() * 9.0 + facing * 2.0
	if Weapons.draw_held_image(self, weapon, facing, hold, bs):
		draw_set_transform(Vector2.ZERO, 0.0, xf)  # the image call resets the transform
	else:
		Weapons.draw_held(self, weapon, facing, hold)
	_draw_hat()
	if _hurt_flash > 0.0:
		draw_circle(Vector2.ZERO, 11.0, Color(1, 0.1, 0.1, _hurt_flash * 2.0))
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Size multiplier for the walking pulse: grows a little at the middle of each step and
## settles back to 1 when standing still.
func step_scale() -> float:
	return 1.0 + STEP_PULSE * _step_amount * absf(sin(_step_phase))


## Draws the selected hat or hair turned to `facing`, with a face dot peeking out the front.
func _draw_hat() -> void:
	var bs := step_scale()
	HeadArt.draw(self, head_style, Vector2.ZERO, facing.angle(), bs)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(bs, bs))  # HeadArt.draw resets the transform
	var face := facing * (HeadArt.front(head_style) - 0.3)
	draw_circle(face, 2.2, HeadArt.face_color(head_style))
	draw_arc(face, 2.2, 0.0, TAU, 10, Color(0.12, 0.08, 0.04, 0.9), 1.0)


func set_head(idx: int) -> void:
	head_style = clampi(idx, 0, HeadArt.count() - 1)
	queue_redraw()
