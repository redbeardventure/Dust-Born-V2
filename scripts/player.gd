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
## Auto reload (on-screen toggle): reload a partly used magazine once you stop firing. Static like weapon.
static var auto_reload := false
const AUTO_RELOAD_DELAY := 1.0  # seconds after the last shot
var _since_shot := 0.0

const MAX_HP := 100

signal health_changed(hp: int, max_hp: int)
## Knocked out (0 hp) and sent back to the spawn point.
signal respawned

# ---- turn-based combat (driven by combat.gd) ----
const COMBAT_MOVE := 200.0  # pixels the player may walk in one combat turn
## A turn-based fight is on: outside your turn you can't move or act.
var turn_mode := false
var my_turn := false
var move_left := 0.0        # movement left this turn (pixels)
var action_left := false    # the turn's one action (a shot or a reload) is still available
var card_played := false    # a combat card has been played this turn (one per turn)
var aimed := false          # Aimed Shot card: the next shot this turn is aimed
const AIM_DAMAGE := 1.5     # Aimed Shot: damage multiplier
const AIM_RANGE := 1.5      # Aimed Shot: range multiplier
signal gold_changed(total: int, added: int)

## Coins in the player's purse (gold drops are picked up by walking over them). Kept on respawn.
var gold := 0
## Keys carried; each opens one locked crate or chest.
var keys := 0


## Takes loot straight into the player's hands (used when opening a crate or chest).
## Gold goes to the purse, keys to the key ring, guns to the weapon wheel. Potions, food, gems
## have no inventory yet, so they are simply taken.
func collect_loot(kind: String) -> void:
	match kind:
		"gold":
			add_gold(randi_range(5, 25))
		"key":
			keys += 1
		"none":
			pass
		_:
			if Weapons.is_ranged(kind) and not owned_weapons.has(kind):
				owned_weapons.append(kind)


func add_key() -> void:
	keys += 1
	notice.emit("Picked up a key")


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

const TARGET_RANGE := 900.0  # Tab only picks barrels / crates this close; one further away is dropped
## NPCs can only be targeted (click or Tab) within 6 tiles; an NPC target further away is dropped.
const NPC_TARGET_RANGE := 6 * Weapons.TILE
## NPC clicked from too far away: walking toward it, targeted once within NPC_TARGET_RANGE.
var _pending_target: Node2D = null
## Double-clicked target while fists are selected: walking until within punch reach.
var _punch_chase: Node2D = null
## Short on-screen hint for the player (shown by game_view).
signal notice(text: String)
const CLICK_RADIUS := 32.0  # how close (px, one tile) a click must land to an NPC to target it


func _ready() -> void:
	# Top-down: no floor/gravity. The default "grounded" mode treats walls and props as slopes and
	# snaps to a floor, which makes the character hop and bounce along obstacles.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	weapon = "none"  # every play-test starts unarmed: fists only
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

	_print_layer = Node2D.new()
	_print_layer.top_level = true
	# top_level nodes ignore show_behind_parent (they draw on top), so order them by z instead:
	# above the terrain (z -4), below props tucked behind walls (-1) and the player (0).
	_print_layer.z_index = -3
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
	_since_shot += delta
	if _punch_t > 0.0:
		_punch_t = maxf(_punch_t - delta, 0.0)
		queue_redraw()
	if weapon_drawn and not turn_mode and not is_instance_valid(target) and _since_shot > HOLSTER_AFTER:
		holster()  # drawn by firing at nothing: put it away after a quiet spell
	if auto_reload and not turn_mode and _since_shot >= AUTO_RELOAD_DELAY and Weapons.is_ranged(weapon) and not is_reloading() and ammo() < Weapons.mag_size(weapon):
		reload()
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(_hurt_flash - delta, 0.0)
		queue_redraw()
	_update_target()
	_update_pending_target()
	_update_punch_chase()
	_update_hold_move(delta)
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
	var speed := SPEED * (1.7 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if turn_mode and (not my_turn or move_left <= 0.0):
		# Turn-based: no walking outside your turn or once this turn's movement is used up.
		dir = Vector2.ZERO
		if not _path.is_empty():
			_clear_path()
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
	if is_instance_valid(target) and target.global_position.distance_to(global_position) > 1.0:
		# Locked on: keep facing (and aiming) at the target while walking in any direction.
		var aim := (target.global_position - global_position).normalized()
		if facing.dot(aim) < -0.99:
			facing = facing.rotated(0.2)  # slerp has no defined path for an exact reversal
		var turned := facing.slerp(aim, minf(1.0, TURN_RATE * delta)).normalized()
		if not turned.is_equal_approx(facing):
			facing = turned
			queue_redraw()
	elif dir != Vector2.ZERO:
		# Turn toward the move direction over a few frames instead of snapping.
		var want := dir.normalized()
		if facing.dot(want) < -0.99:
			facing = facing.rotated(0.2)  # slerp has no defined path for an exact reversal
		facing = facing.slerp(want, minf(1.0, TURN_RATE * delta)).normalized()
		queue_redraw()
	var before := position
	move_and_slide()
	_keep_out_of_water(before)
	# Step pulse follows distance actually walked, so running steps faster and pushing
	# into a wall doesn't animate. Each half-turn of the phase is one step.
	var moved := position.distance_to(before)
	if turn_mode and my_turn and moved > 0.0:
		move_left = maxf(move_left - moved, 0.0)
		queue_redraw()  # the movement ring shrinks
	_step_phase = fmod(_step_phase + moved / STEP_LENGTH * PI, TAU)
	_step_amount = move_toward(_step_amount, 1.0 if moved > 0.2 else 0.0, delta * 6.0)
	if _step_amount > 0.0:
		queue_redraw()
	_update_prints(delta, moved)
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
			if _on_base_ground(global_position):  # floors, roads, rugs...: no footprints
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


## True when `p` is on the map's base ground: not inside any terrain polygon drawn over it.
## See-through overlays (moss, blood, shadow) don't count, so prints still show through them.
func _on_base_ground(p: Vector2) -> bool:
	for poly in MapData.working.get("polygons", []):
		var pts: PackedVector2Array = poly["points"]
		if pts.size() < 3:
			continue
		var def: Dictionary = MapData.TERRAIN.get(str(poly["type"]), {})
		if not def.is_empty() and (def["a"] as Color).a < 0.99:
			continue
		if Geometry2D.is_point_in_polygon(p, pts):
			return false
	return true


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
			if not space.intersect_shape(q, 1).is_empty() or _cell_in_water(Vector2i(x, y)):
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
			_grid.set_point_solid(Vector2i(x, y), not space.intersect_shape(q, 1).is_empty() or _cell_in_water(Vector2i(x, y)))


## Backstop for water collision: if this frame's move ended in blocked water, slide along one
## axis instead, or undo the move. Starting in water (e.g. a bad spawn) is left alone so the
## player can walk out.
func _keep_out_of_water(before: Vector2) -> void:
	if position == before or not _in_water(position) or _in_water(before):
		return
	var tries := [Vector2(position.x, before.y), Vector2(before.x, position.y)]
	for t in tries:
		if not _in_water(t):
			position = t
			return
	position = before


func _in_water(p: Vector2) -> bool:
	# 9px: a bit under the 10px body, so hugging the shore doesn't stick.
	for r in get_tree().get_nodes_in_group("map_renderer"):
		if r.has_method("circle_in_water") and r.circle_in_water(p, 9.0):
			return true
	return false


## True when the cell's centre (with the body radius) touches water nobody can walk on.
## Checks the renderer's water polygons directly, so it works even if a collision shape failed.
func _cell_in_water(c: Vector2i) -> bool:
	for r in get_tree().get_nodes_in_group("map_renderer"):
		if r.has_method("circle_in_water") and r.circle_in_water((Vector2(c) + Vector2(0.5, 0.5)) * CELL, 11.0):
			return true
	return false


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
		_pending_target = null
		_punch_chase = null
		var npc := _npc_at(mp)
		if event.double_click and weapon == "none":
			# Punch selected: double-clicking a target walks right up to it.
			var victim: Node2D = npc if npc != null else _container_at(mp)
			if victim != null:
				if victim != target:
					set_target(victim)
				set_interact(null)
				if not in_punch_reach(victim):
					_punch_chase = victim
					_move_to(victim.global_position)
				get_viewport().set_input_as_handled()
				return
		if npc != null and npc != target and global_position.distance_to(npc.global_position) > NPC_TARGET_RANGE:
			# Too far to target yet: walk toward the NPC and lock on once within 6 tiles.
			_pending_target = npc
			set_interact(null)
			_move_to(npc.global_position)
			notice.emit("Too far to target - moving closer")
			get_viewport().set_input_as_handled()
			return
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
			_hold_move = true  # keep following the cursor while the button stays down
			_hold_timer = 0.0
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

## Weapons the player carries. Fists ("none") only at the start of every play-test.
var owned_weapons: Array = ["none"]


func has_weapon(key: String) -> bool:
	return owned_weapons.has(key)


func set_weapon(key: String) -> void:
	if not has_weapon(key):
		return
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
	if turn_mode and not (my_turn and action_left):
		return  # turn-based: reloading is your turn's action
	var spent := Weapons.mag_size(weapon) - ammo()
	if turn_mode:
		_spend_action()
		_clear_path()
		_ammo[weapon] = Weapons.mag_size(weapon)  # takes the action instead of real time
	else:
		_reload_left = float(Weapons.RANGED[weapon]["reload"])
	# Throw out one spent casing per round being reloaded, from the gun (part way along it).
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
	if weapon == "none":
		punch_at(target)  # bare hands: the attack is a punch
		return
	if not Weapons.is_ranged(weapon) or _cooldown > 0.0 or hp <= 0 or is_reloading():
		return
	if turn_mode and not (my_turn and action_left):
		return  # turn-based: one shot per turn, on your own turn
	if not weapon_drawn:
		draw_weapon()  # first pull it out; the shot comes after DRAW_TIME
		return
	if ammo() <= 0:
		reload()
		return
	if turn_mode:
		_spend_action()
		_clear_path()
	var dir := target - global_position
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	facing = dir
	_cooldown = float(Weapons.RANGED[weapon]["cooldown"])
	_since_shot = 0.0
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
	if aimed:
		# Aimed Shot card: dead straight, harder hitting and reaches further.
		Projectile.fire(get_tree().current_scene, weapon, from, dir, self, 0.0, AIM_DAMAGE, AIM_RANGE)
		aimed = false
	else:
		# The farther the target, the more the shot can stray.
		var spread := Weapons.spread_mul_at(weapon, global_position.distance_to(target))
		Projectile.fire(get_tree().current_scene, weapon, from, dir, self, spread)
	MuzzleFlash.spawn(get_tree().current_scene, from + dir * 14.0, dir)  # fire + smoke at the barrel tip
	if ammo() <= 0 and not turn_mode:
		reload()  # in a turn-based fight reloading takes a later turn's action instead
	queue_redraw()


# ---------------------------------------------------------------- punching (unarmed)

const PUNCH_REACH := 36.0     # px from your centre to the centre of what you hit
const PUNCH_DAMAGE := 8
const PUNCH_COOLDOWN := 0.6
const PUNCH_ANIM := 0.22      # seconds the jab takes on screen
var _punch_t := 0.0           # > 0 while the jab animation plays
var _punch_side := 1.0        # alternates left / right fist


## True when `n` is close enough to punch.
func in_punch_reach(n: Node2D) -> bool:
	return is_instance_valid(n) and global_position.distance_to(n.global_position) <= PUNCH_REACH


## Punches toward `toward`: hits the target if it is within reach, otherwise the nearest NPC or
## breakable prop in reach on that side. Outside combat a punch at nothing is a harmless swing;
## in combat it is refused (your action is kept) until something is in reach.
func punch_at(toward: Vector2) -> void:
	if _cooldown > 0.0 or hp <= 0:
		return
	if turn_mode and not (my_turn and action_left):
		return
	var victim: Node2D = null
	if is_instance_valid(target) and in_punch_reach(target) and target.has_method("take_damage"):
		victim = target
	else:
		var aim := (toward - global_position).normalized()
		var best := INF
		for g in ["npcs", "breakable"]:
			for n in get_tree().get_nodes_in_group(g):
				var node := n as Node2D
				if node == null or not in_punch_reach(node) or not node.has_method("take_damage"):
					continue
				var to := node.global_position - global_position
				if aim != Vector2.ZERO and to.normalized().dot(aim) < 0.2:
					continue  # behind you
				if to.length() < best:
					best = to.length()
					victim = node
	if victim == null and turn_mode:
		notice.emit("Too far to punch - move next to them")
		return
	var dir := (victim.global_position if victim != null else toward) - global_position
	if dir.length() > 0.5:
		facing = dir.normalized()
	_cooldown = PUNCH_COOLDOWN
	_since_shot = 0.0
	_punch_t = PUNCH_ANIM
	_punch_side = -_punch_side
	if victim != null:
		victim.call("take_damage", PUNCH_DAMAGE, self)
	if turn_mode:
		_spend_action()
		_clear_path()
	queue_redraw()


## The hat brim reaches about 12.5 px to the front and 15 px to the sides, so limbs have to reach
## past that to be seen.
const FOOT_STRIDE := 15.0  # how far a foot swings ahead of / behind the body mid-step


## Body proportions, styled on the top-down cowboy reference: the shoulders are a wide oval that
## shows on both sides of the hat, arms reach forward to the hands, boots step out front and back.
const SHOULDER_W := 15.0     # half-width of the shoulders (sideways); the hat brim is ~15
const TORSO_D := 7.0         # half-depth of the torso (front to back)
const SHIRT := Color("3b6fb0")
const SHIRT_DARK := Color("2c5288")
const SKIN := Color("e8c9a0")
const OUTLINE := Color("101820")


## Unarmed fists sit up in a guard in front of the chest and jab straight out.
func _fist_pos(s: float) -> Vector2:
	var side := facing.orthogonal()
	var rest: Vector2 = side * 8.0 * s + facing * 13.0
	if _punch_t > 0.0 and s == _punch_side:
		var k := sin((1.0 - _punch_t / PUNCH_ANIM) * PI)  # jab out and back
		return rest.lerp(facing * 22.0 + side * 3.0 * s, k)
	return rest


func _draw_fists() -> void:
	var edge := Color(0.25, 0.15, 0.08)
	for s in [-1.0, 1.0]:
		var p: Vector2 = _fist_pos(s)
		draw_circle(p, 3.0, SKIN)
		draw_arc(p, 3.0, 0.0, TAU, 12, edge, 1.0)


## Wide oval torso turned to `facing`, shoulders darker at the ends.
func _draw_torso() -> void:
	var side := facing.orthogonal()
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(facing * cos(a) * TORSO_D + side * sin(a) * SHOULDER_W)
	draw_colored_polygon(pts, SHIRT)
	for s in [-1.0, 1.0]:
		draw_circle(side * (SHOULDER_W - 4.0) * s, 4.0, SHIRT_DARK)  # shoulder seams
	draw_polyline(pts + PackedVector2Array([pts[0]]), OUTLINE, 1.5)


## Two boots that swap places with each step. Standing still they sit under the body.
func _draw_legs() -> void:
	var side := facing.orthogonal()
	var swing := sin(_step_phase) * FOOT_STRIDE * _step_amount
	for s in [-1.0, 1.0]:
		var hip: Vector2 = side * 4.5 * s
		var foot: Vector2 = side * 5.0 * s + facing * swing * s
		draw_line(hip, foot, OUTLINE, 6.0)
		draw_line(hip, foot, Color("2a3a55"), 4.5)  # trouser leg
		var boot := PackedVector2Array()  # boot sole, a little longer toward the toe
		for i in 12:
			var a := TAU * float(i) / 12.0
			boot.append(foot + facing * (cos(a) * 3.6 + 0.8) + side * sin(a) * 2.6)
		draw_colored_polygon(boot, Color("4a3220"))
		draw_polyline(boot + PackedVector2Array([boot[0]]), OUTLINE, 1.0)


## One arm: upper arm to an elbow bent outward, forearm to the hand.
func _draw_arm(shoulder: Vector2, hand: Vector2, s: float, hand_dot: bool) -> void:
	var side := facing.orthogonal()
	var elbow: Vector2 = shoulder.lerp(hand, 0.5) + side * 2.5 * s
	draw_line(shoulder, elbow, OUTLINE, 6.0)
	draw_line(elbow, hand, OUTLINE, 6.0)
	draw_circle(elbow, 3.0, OUTLINE)
	draw_line(shoulder, elbow, SHIRT, 4.5)
	draw_line(elbow, hand, SHIRT, 4.0)
	draw_circle(elbow, 2.2, SHIRT)
	if hand_dot:
		draw_circle(hand, 2.6, SKIN)
		draw_arc(hand, 2.6, 0.0, TAU, 10, OUTLINE, 1.0)


## Arms: up in a guard with fists when unarmed, reaching the grip (and the barrel for long guns)
## when a gun is drawn, otherwise hanging at the sides and swinging against the legs.
func _draw_arms() -> void:
	var side := facing.orthogonal()
	var swing := sin(_step_phase) * 6.0 * _step_amount
	for s in [-1.0, 1.0]:
		var shoulder: Vector2 = side * (SHOULDER_W - 4.0) * s
		var hang: Vector2 = side * (SHOULDER_W + 2.0) * s + facing * (2.0 - swing * s)
		var hand: Vector2
		if weapon == "none":
			hand = _fist_pos(s)
		elif weapon_drawn and Weapons.is_ranged(weapon):
			var hold := side * 9.0 + facing * 2.0
			if s > 0.0:
				hand = hold
			elif weapon == "pistol":
				hand = hang
			else:
				hand = hold + facing * 12.0 - side * 1.0  # off hand supports the long gun's barrel
		else:
			hand = hang
		_draw_arm(shoulder, hand, s, weapon != "none")


# ---------------------------------------------------------------- turn-based combat hooks

## Gun in hand (shown and ready). Holstered while exploring; drawn when a fight starts, when a
## target is picked, or when you fire. Put away again once combat ends and nothing is targeted.
var weapon_drawn := false
const DRAW_TIME := 0.3  # seconds before the first shot after pulling the gun out
const HOLSTER_AFTER := 4.0  # with no target and no fight, the gun goes away this long after the last shot


func draw_weapon() -> void:
	if weapon_drawn:
		return
	weapon_drawn = true
	_since_shot = 0.0  # so the idle holster timer starts from now
	if Weapons.is_ranged(weapon) and not (turn_mode and my_turn):
		_cooldown = maxf(_cooldown, DRAW_TIME)  # a moment to pull it out
	queue_redraw()


func holster() -> void:
	if not weapon_drawn:
		return
	weapon_drawn = false
	queue_redraw()


func enter_combat() -> void:
	draw_weapon()
	turn_mode = true
	my_turn = false
	fire_held = false
	_clear_path()
	if _reload_left > 0.0:  # finish a reload that was under way
		_reload_left = 0.0
		_ammo[weapon] = Weapons.mag_size(weapon)
	queue_redraw()


func leave_combat() -> void:
	if not is_instance_valid(target):
		holster()
	turn_mode = false
	my_turn = false
	move_left = 0.0
	action_left = false
	extra_actions = 0
	queue_redraw()


## Plays a combat card (see game_view.gd COMBAT_CARDS). One card per turn, on your own turn.
## Returns false (and does nothing) when the card can't be used right now.
func play_card(kind: String) -> bool:
	if not can_play_card(kind):
		return false
	match kind:
		"dash":
			move_left += COMBAT_MOVE  # double move
		"aim":
			aimed = true  # applies to this turn's shot
		"reload":
			# Quick reload: refill without using the turn's action.
			var spent := Weapons.mag_size(weapon) - ammo()
			_ammo[weapon] = Weapons.mag_size(weapon)
			ShellCasings.spawn(get_tree().current_scene, global_position + facing * 12.0, facing, spent,
					"shell" if weapon == "shotgun" else "brass")
	card_played = true
	queue_redraw()
	return true


## Whether `kind` could be played now (used to grey out cards).
func can_play_card(kind: String) -> bool:
	if not (turn_mode and my_turn) or card_played:
		return false
	match kind:
		"dash":
			return move_left > 0.0
		"aim":
			return action_left and Weapons.is_ranged(weapon)
		"reload":
			return Weapons.is_ranged(weapon) and ammo() < Weapons.mag_size(weapon)
	return false


## Extra actions left this turn (the ambush bonus after kicking a door in: 2 actions in round 1).
var extra_actions := 0


## Uses up the turn's action. The turn ends after the last one; an extra action keeps it going.
func _spend_action() -> void:
	if extra_actions > 0:
		extra_actions -= 1
		return
	action_left = false
	move_left = 0.0  # the turn ends after the action


func begin_turn() -> void:
	my_turn = true
	move_left = COMBAT_MOVE
	action_left = true
	card_played = false
	aimed = false
	_cooldown = 0.0
	queue_redraw()


func end_turn() -> void:
	my_turn = false
	move_left = 0.0
	action_left = false
	extra_actions = 0
	aimed = false
	fire_held = false
	_clear_path()
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


func set_target(npc: Node2D) -> void:
	if is_instance_valid(target) and target.has_signal("defeated") and target.is_connected("defeated", _on_target_defeated):
		target.disconnect("defeated", _on_target_defeated)
	target = npc if is_instance_valid(npc) else null
	# Drop the lock the moment the NPC is defeated.
	if target != null and target.has_signal("defeated"):
		target.connect("defeated", _on_target_defeated)
	if target != null:
		facing = (target.global_position - global_position).normalized()
		draw_weapon()  # picking a target pulls the gun out
		queue_redraw()
	elif not turn_mode:
		holster()  # nothing targeted and no fight on: put it away
	_reticle.visible = target != null


## Picks the nearest NPC in range, or the next-nearest after the current target on repeat presses.
## Hostile NPCs come first so Tab finds threats before bystanders.
func cycle_target() -> void:
	var list: Array = []
	for g in ["npcs", "containers"]:
		for n in get_tree().get_nodes_in_group(g):
			if is_instance_valid(n) and global_position.distance_to(n.global_position) <= _target_range(n):
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


## Click and hold on the ground: the move point follows the cursor until the button is released.
var _hold_move := false
var _hold_timer := 0.0
const HOLD_REPATH := 0.08  # seconds between updates of the move point


func _update_hold_move(delta: float) -> void:
	if not _hold_move:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or hp <= 0 \
			or _pending_target != null or _punch_chase != null:
		_hold_move = false
		return
	_hold_timer -= delta
	if _hold_timer > 0.0:
		return
	_hold_timer = HOLD_REPATH
	var mp := get_global_mouse_position()
	if mp.distance_to(_marker_pos) > 4.0 and global_position.distance_to(mp) > 6.0:
		_move_to(mp)


## Stops the walk once the double-clicked target is within punch reach; gives up if it is gone,
## no longer the target, or the walk ended without reaching it (re-paths once if it moved).
func _update_punch_chase() -> void:
	if _punch_chase == null:
		return
	if not is_instance_valid(_punch_chase) or _punch_chase.is_queued_for_deletion() \
			or _punch_chase != target or weapon != "none":
		_punch_chase = null
		return
	if in_punch_reach(_punch_chase):
		_punch_chase = null
		_clear_path()
	elif _path.is_empty():
		_move_to(_punch_chase.global_position)
		if _path.is_empty():
			_punch_chase = null


## Walking toward a far NPC that was clicked: lock on (and stop) once it is within 6 tiles.
## Gives up if the NPC dies or the walk ends without getting close enough.
func _update_pending_target() -> void:
	if _pending_target == null:
		return
	if not is_instance_valid(_pending_target) or _pending_target.is_queued_for_deletion():
		_pending_target = null
		return
	if global_position.distance_to(_pending_target.global_position) <= NPC_TARGET_RANGE:
		var npc := _pending_target
		_pending_target = null
		_clear_path()
		set_target(npc)
	elif _path.is_empty():
		_pending_target = null
		notice.emit("Couldn't get close enough to target")


## How far away `n` may be and still be (or stay) the target: 6 tiles for NPCs.
func _target_range(n: Node) -> float:
	return NPC_TARGET_RANGE if n.is_in_group("npcs") else TARGET_RANGE


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
	elif target.is_queued_for_deletion() or global_position.distance_to(target.global_position) > _target_range(target):
		set_target(null)
	_reticle.visible = target != null
	if target != null:
		_reticle.global_position = target.global_position
		_reticle.queue_redraw()


func _draw_reticle() -> void:
	# With a gun: green = close, good odds; shading to yellow toward the edge of the range;
	# red = out of range. Unarmed: yellow (nothing to shoot with).
	var col := Color(1.0, 0.9, 0.4)
	if is_instance_valid(target) and weapon == "none":
		col = Color(0.3, 1.0, 0.35) if in_punch_reach(target) else Color(1.0, 0.25, 0.2)  # fists: in reach or not
	elif is_instance_valid(target) and Weapons.is_ranged(weapon):
		col = Weapons.range_color(weapon, global_position.distance_to(target.global_position), AIM_RANGE if aimed else 1.0)
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
		_clear_path()
		position = _spawn
		reset_physics_interpolation()
		hp = MAX_HP
		_ammo.clear()  # respawn with full magazines
		_reload_left = 0.0
		respawned.emit()
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
	if turn_mode and my_turn and move_left > 1.0:
		# How far you can still walk this turn (straight-line guide).
		draw_circle(Vector2.ZERO, move_left, Color(0.35, 0.8, 1.0, 0.07))
		draw_arc(Vector2.ZERO, move_left, 0.0, TAU, 64, Color(0.35, 0.8, 1.0, 0.6), 1.5)
	# Ground shadow stays the same size; the character above it pulses with each step.
	draw_circle(Vector2(3, 4), 7.0, Color(0, 0, 0, 0.3))
	var bs := step_scale()
	var xf := Vector2(bs, bs)
	draw_set_transform(Vector2.ZERO, 0.0, xf)
	_draw_legs()
	# Shoulders show either side of the hat (drawing only; the collision circle is unchanged).
	_draw_torso()
	_draw_arms()
	if weapon == "none":
		_draw_fists()
	elif weapon_drawn:
		var hold := facing.orthogonal() * 9.0 + facing * 2.0
		if Weapons.draw_held_image(self, weapon, facing, hold, bs):
			draw_set_transform(Vector2.ZERO, 0.0, xf)  # the image call resets the transform
		else:
			Weapons.draw_held(self, weapon, facing, hold)
	else:
		_draw_holstered()
	_draw_hat()
	if _hurt_flash > 0.0:
		draw_circle(Vector2.ZERO, 11.0, Color(1, 0.1, 0.1, _hurt_flash * 2.0))
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Put-away gun: a revolver in a holster on the right hip, long guns slung across the back.
func _draw_holstered() -> void:
	if not Weapons.is_ranged(weapon):
		return
	var right := facing.orthogonal()
	if weapon == "pistol":
		var hip := right * 6.5 - facing * 1.5
		var pts := PackedVector2Array([hip - facing * 4.0 - right * 1.8, hip - facing * 4.0 + right * 1.8,
				hip + facing * 3.0 + right * 1.5, hip + facing * 3.0 - right * 1.5])
		draw_colored_polygon(pts, Color("5a3a1e"))  # leather holster
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color("2a1a0c"), 1.0)
		draw_circle(hip + facing * 3.5, 1.6, Color("3a3a40"))  # grip poking out
	else:
		# Sling strap and the gun's outline lying diagonally across the back.
		var a := -facing * 5.0 + right * 7.0 + facing * -1.0
		var b := -facing * 5.0 - right * 7.0 + facing * 6.0
		draw_line(a, b, Color("3a3a40") if weapon == "rifle" else Color("4a3220"), 2.6)
		draw_line(right * 5.0 + facing * 3.0, -right * 5.0 - facing * 5.0, Color("6b4a2a"), 1.0)  # strap


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
