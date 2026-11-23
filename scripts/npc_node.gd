class_name NpcNode
extends Node2D
## A non-player character drawn procedurally (top-down). When `animate` is on (play-test),
## it wanders to random points inside its patrol area.
## Combat (play-test only): hostile NPCs with a ranged weapon (see weapons.gd) shoot at the player
## when they can see them and are in range. Any NPC that is shot turns hostile; at 0 hp it dies.

const HeadArt := preload("res://scripts/head_art.gd")
const SPEED := 55.0
const FRIENDLY_COL := Color("4caf5a")
const HOSTILE_COL := Color("c93a3a")
const MAX_HP := 40
const SIGHT_MASK := 1  # walls, props and closed doors block line of sight; water does not
const FOV_DEGREES := 120.0  # hostile NPCs only notice the player inside this arc in front of them
const REACTION := 0.6  # seconds between first seeing the player and the first shot

signal defeated(npc: NpcNode)

var npc_name := "NPC"
var weapon := "none"
var disposition := "friendly"
var loot := "none"  # key in MapData.NPC_LOOT, dropped on death
var head := -1  # index into head_art.gd, -1 = no hat/hair
## Wanted outlaw (hostile NPCs only). Shown with a red flag; killing every bounty wins the play-test.
var bounty := false
var patrol := PackedVector2Array()
var animate := false
var hp := MAX_HP
var max_hp := MAX_HP  # set from the map (the editor's Health field)

## Guard: stands still (no patrol) and keeps looking in `guard_dir` (degrees, 0 = east/right,
## 90 = south/down) until it is engaged; afterwards it turns back to that direction.
var guard := false
var guard_dir := 90.0

## Has noticed the player (saw them, or was shot at / hit). Un-alerted NPCs can be sneaked up on:
## see Combat.start_player_initiated().
var alerted := false

const TURN_SPEED := 3.0  # radians/s the body swings toward where it wants to look
var _facing := Vector2.DOWN  # where the body points now (drawn); turns smoothly toward _aim
var _aim := Vector2.DOWN     # where the NPC wants to look / walk / shoot
var _target := Vector2.ZERO
var _wait := 0.0
var _rng := RandomNumberGenerator.new()
var _cooldown := 0.0
var _engaged := false  # currently aiming at the player (stops wandering)
var _hurt_flash := 0.0
var _ammo := -1  # shots left in the magazine; -1 = not loaded yet (filled on first shot)
var _reloading := 0.0  # seconds of reload left, for the "reloading" indicator


func _ready() -> void:
	_rng.randomize()
	_target = position
	_wait = _rng.randf_range(0.2, 1.5)
	if guard:
		_wait = 0.0
		_facing = guard_vec()
		_aim = _facing
	set_process(animate)
	set_physics_process(animate)
	if animate:
		add_to_group("combatants")
		add_to_group("npcs")  # targetable by the player
		if bounty:
			add_to_group("bounty")  # game_view watches this group for the win


func _process(delta: float) -> void:
	if show_fov and disposition == "hostile" and hp > 0:
		queue_redraw()  # the cone is re-cut against walls and props every frame
	if _facing != _aim:
		var diff := angle_difference(_facing.angle(), _aim.angle())
		var max_turn := TURN_SPEED * delta
		_facing = _aim if absf(diff) <= max_turn else _facing.rotated(signf(diff) * max_turn)
		queue_redraw()
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(_hurt_flash - delta, 0.0)
		queue_redraw()
	if guard:
		# Never wanders. Holds its post direction unless it is fighting the player (engaged in
		# real time, or alerted in a turn-based fight) or still looking at a shot that just missed.
		if _wait > 0.0:
			_wait -= delta
		elif not _engaged and not (combat_mode and alerted):
			_aim = guard_vec()
		return
	if combat_mode or _engaged or patrol.size() < 3:
		return
	if _wait > 0.0:
		_wait -= delta
		return
	var to := _target - position
	if to.length() < 3.0:
		_target = _random_patrol_point()
		_wait = _rng.randf_range(0.6, 2.5)
		return
	_aim = to.normalized()
	var step := _aim * minf(SPEED * delta, to.length())
	if _water_at(global_position + _aim * 12.0 + step):
		# Water ahead: stop and pick another spot instead of wading in.
		_target = _random_patrol_point()
		_wait = _rng.randf_range(0.3, 1.0)
		return
	position += step
	queue_redraw()


## True when `p` (world position) is on water NPCs can't walk on (the water collision layer).
func _water_at(p: Vector2) -> bool:
	for r in get_tree().get_nodes_in_group("map_renderer"):
		if r.has_method("is_water_at") and r.is_water_at(p):
			return true  # checks the water polygons directly, even if a collision shape failed
	var q := PhysicsPointQueryParameters2D.new()
	q.position = p
	q.collision_mask = 2
	q.collide_with_bodies = true
	return not get_world_2d().direct_space_state.intersect_point(q, 1).is_empty()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _reloading > 0.0:
		_reloading = maxf(_reloading - delta, 0.0)
		queue_redraw()
	if combat_mode:
		_engaged = false
		return  # turn-based: Combat decides when this NPC acts
	var foe := _visible_foe()
	if foe == null:
		_engaged = false
		return
	if not _engaged:
		_engaged = true
		_cooldown = maxf(_cooldown, REACTION)
	_aim = (foe.global_position - global_position).normalized()
	queue_redraw()
	if _cooldown <= 0.0:
		var w: Dictionary = Weapons.RANGED[weapon]
		if _ammo < 0:
			_ammo = int(w["mag"])
		_cooldown = float(w["cooldown"]) * _rng.randf_range(1.0, 1.4)
		Projectile.fire(get_tree().current_scene, weapon, global_position, _aim, self,
				Weapons.spread_mul_at(weapon, global_position.distance_to(foe.global_position)))
		_ammo -= 1
		if _ammo <= 0:
			# Empty: the reload replaces the normal wait before the next shot.
			_ammo = int(w["mag"])
			_cooldown = float(w["reload"]) * _rng.randf_range(1.0, 1.3)
			_reloading = _cooldown


# ---------------------------------------------------------------- turn-based combat (see combat.gd)

## True while a turn-based fight is on: NPCs stop wandering and shooting on their own and only
## act when Combat calls take_combat_turn().
static var combat_mode := false
const COMBAT_MOVE := 140.0   # pixels an NPC can walk in one combat turn
const COMBAT_WALK_SPEED := 90.0  # px/s while walking during a combat turn (lower = slower)
const PUNCH_RANGE := 34.0
const PUNCH_DAMAGE := 6

## Seconds the walk of the last combat turn takes (Combat waits for it).
var combat_walk_time := 0.0

var _turn_marker := false


## Debug (F3 in play-test): draw each hostile NPC's field of view.
static var show_fov := true

## `foe` is inside this NPC's field-of-view arc (centred on where it faces). Distance is not checked.
func in_view_arc(foe: Node2D) -> bool:
	var to := foe.global_position - global_position
	if to.length() < 0.5:
		return true
	return absf(_facing.angle_to(to)) <= deg_to_rad(FOV_DEGREES) * 0.5


## Hearing: a gunshot inside this circle (any direction, through walls) alerts the NPC.
const HEARING_RANGE := 9 * Weapons.TILE
## Yelling for help carries twice as far as hearing: hostiles inside this circle join the fight.
const YELL_RANGE := HEARING_RANGE * 2.0
## Has yelled for help in this fight already (once per fight; reset when combat ends).
var yelled := false

func hears(p: Vector2) -> bool:
	return hp > 0 and global_position.distance_to(p) <= HEARING_RANGE


## Starts turning to face `p` (e.g. toward where a shot came from).
func look_toward(p: Vector2) -> void:
	var to := p - global_position
	if to.length() > 0.5:
		_aim = to.normalized()


## The direction the body currently points.
func facing_dir() -> Vector2:
	return _facing


## World point `p` lies inside this NPC's view arc and within `max_dist` (walls are ignored, so this
## is the cautious answer used to plan a sneak route).
func arc_covers(p: Vector2, max_dist: float) -> bool:
	var to := p - global_position
	if to.length() > max_dist:
		return false
	if to.length() < 0.5:
		return true
	return absf(_facing.angle_to(to)) <= deg_to_rad(FOV_DEGREES) * 0.5


## Like can_see, but the player must also be inside the NPC's view arc. This is what makes a
## hostile NPC start (or join) a fight on its own.
func can_spot(foe: Node2D, max_dist: float) -> bool:
	return is_instance_valid(foe) and in_view_arc(foe) and can_see(foe, max_dist)


## What blocks this NPC's view. Low props (crates, barrels...) hide the player until this NPC
## knows it is in a fight: combat is on AND it has noticed the player (alerted). A player-started
## fight used only to sneak around doesn't count, so the props keep hiding you from unaware NPCs.
func sight_mask() -> int:
	return SIGHT_MASK if combat_mode and alerted else SIGHT_MASK | Projectile.LOW_MASK


## `foe` is within `max_dist` and nothing solid (walls, props, closed doors) is in between.
## `over_low` = look over low props even outside combat (the player starting a fight from cover).
func can_see(foe: Node2D, max_dist: float, over_low := false) -> bool:
	if hp <= 0 or not is_instance_valid(foe) or global_position.distance_to(foe.global_position) > max_dist:
		return false
	var q := PhysicsRayQueryParameters2D.create(global_position, foe.global_position, SIGHT_MASK if over_low else sight_mask())
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit["collider"] == foe


## Turns to face `pos` straight away (used when the player shoots at this NPC, hit or miss).
func face_toward(pos: Vector2) -> void:
	var to := pos - global_position
	if hp <= 0 or to.length() < 0.5:
		return
	_aim = to.normalized()
	_wait = maxf(_wait, SHOT_AT_PAUSE)  # stop wandering for a moment so it keeps looking at you
	queue_redraw()


const SHOT_AT_PAUSE := 1.5  # seconds a wandering NPC stands facing the player after being shot at


const FOV_RAYS := 60  # rays cast to draw the debug view cone (more = smoother shadow edges)


func guard_vec() -> Vector2:
	return Vector2.from_angle(deg_to_rad(guard_dir))


## Map editor only: the direction a guard keeps watching, as a short view-cone wedge with an
## arrow, and a "GUARD" tag, so it reads at a glance while building the map.
func _draw_guard_marker() -> void:
	const R := 70.0
	var half := deg_to_rad(FOV_DEGREES) * 0.5
	var a0 := deg_to_rad(guard_dir)
	var wedge := PackedVector2Array([Vector2.ZERO])
	for k in 17:
		wedge.append(Vector2.from_angle(a0 - half + 2.0 * half * float(k) / 16.0) * R)
	draw_colored_polygon(wedge, Color(1.0, 0.75, 0.2, 0.16))
	wedge.append(Vector2.ZERO)
	draw_polyline(wedge, Color(1.0, 0.75, 0.2, 0.7), 1.5)
	var dir := guard_vec()
	var tip := dir * (R + 14.0)
	draw_line(dir * 12.0, tip, Color(1.0, 0.8, 0.25), 3.0)
	draw_colored_polygon(PackedVector2Array([tip + dir * 8.0, tip + dir.orthogonal() * 6.0, tip - dir.orthogonal() * 6.0]),
			Color(1.0, 0.8, 0.25))
	draw_string(ThemeDB.fallback_font, Vector2(-60, 28), "GUARD", HORIZONTAL_ALIGNMENT_CENTER, 120, 10, Color(1.0, 0.8, 0.25))


## Debug view cone (F3). Each ray is cast with the same mask as can_see, so the red area is what
## the NPC can actually see; past the first thing in the way the ray carries on in grey (blocked).
## Amber shadows behind crates and barrels show until the NPC is alerted in a fight (see
## sight_mask): then it looks over them and the cone reaches past them again.
func _draw_fov() -> void:
	# Hearing circle: faint yellow ring (gunshots inside it pull this NPC into the fight).
	draw_circle(Vector2.ZERO, HEARING_RANGE, Color(1.0, 0.9, 0.3, 0.04))
	draw_arc(Vector2.ZERO, HEARING_RANGE, 0.0, TAU, 72, Color(1.0, 0.9, 0.3, 0.45), 1.5)
	var half := deg_to_rad(FOV_DEGREES) * 0.5
	var a0 := _facing.angle()
	var reach := Combat.JOIN_RANGE
	var space := get_world_2d().direct_space_state
	var exclude: Array[RID] = []
	for n in get_tree().get_nodes_in_group("combatants"):
		if n is CollisionObject2D:
			exclude.append((n as CollisionObject2D).get_rid())
	var mask := sight_mask()
	var seen := PackedVector2Array()  # local end of each ray where the view stops
	var full := PackedVector2Array()  # local end of each ray at full reach
	var by: Array = []                # what stopped each ray: "" (nothing), "wall" or "low"
	for k in FOV_RAYS + 1:
		var a := a0 - half + 2.0 * half * float(k) / float(FOV_RAYS)
		var dir := Vector2(cos(a), sin(a))
		var q := PhysicsRayQueryParameters2D.create(global_position, global_position + dir * reach, mask)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			seen.append(dir * reach)
			by.append("")
		else:
			seen.append((hit["position"] as Vector2) - global_position)
			var col := hit.get("collider") as CollisionObject2D
			by.append("low" if col != null and (col.collision_layer & Projectile.LOW_MASK) != 0 else "wall")
		full.append(dir * reach)

	# Visible: a fan of thin triangles (one big polygon can fail to triangulate with jagged edges).
	var vis_col := Color(1.0, 0.2, 0.2, 0.32)
	for k in FOV_RAYS:
		_tri(Vector2.ZERO, seen[k], seen[k + 1], vis_col)
	# Blocked: from where the view stops out to full reach. Grey behind walls and tall props,
	# amber behind low props (crates, barrels...) that hide you only until the fight starts.
	var wall_shade := Color(0.12, 0.12, 0.18, 0.50)
	var low_shade := Color(1.0, 0.65, 0.15, 0.40)
	for k in FOV_RAYS:
		var b1: String = by[k]
		var b2: String = by[k + 1]
		if b1 == "" and b2 == "":
			continue
		var shade := low_shade if (b1 == "low" or b2 == "low") else wall_shade
		_tri(seen[k], full[k], full[k + 1], shade)
		_tri(seen[k], full[k + 1], seen[k + 1], shade)

	# Outline: red where the view is open, a thick edge where something blocks it
	# (orange for walls, yellow for low props).
	draw_line(Vector2.ZERO, seen[0], Color(1.0, 0.3, 0.3, 0.9), 1.5)
	draw_line(Vector2.ZERO, seen[FOV_RAYS], Color(1.0, 0.3, 0.3, 0.9), 1.5)
	for k in FOV_RAYS:
		var b1: String = by[k]
		var b2: String = by[k + 1]
		if b1 != "" and b1 == b2:
			var c := Color(1.0, 0.85, 0.2, 0.95) if b1 == "low" else Color(1.0, 0.55, 0.15, 0.95)
			draw_line(seen[k], seen[k + 1], c, 3.0)
		else:
			draw_line(seen[k], seen[k + 1], Color(1.0, 0.3, 0.3, 0.9), 1.5)
	draw_polyline(full, Color(0.6, 0.6, 0.7, 0.55), 1.0)  # how far it would see with nothing in the way


## Draws a filled triangle, skipping slivers with no area (they make the renderer log errors).
func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	if absf((b - a).cross(c - a)) < 0.5:
		return
	draw_colored_polygon(PackedVector2Array([a, b, c]), col)


## Ring shown under the NPC whose turn it is.
func set_turn_marker(on: bool) -> void:
	_turn_marker = on
	queue_redraw()


## One combat turn: shoot if armed with a clear shot in range (reload when empty), punch when
## unarmed and adjacent, otherwise walk up to COMBAT_MOVE closer (stopping at walls).
func take_combat_turn(foe: Node2D) -> void:
	if hp <= 0 or not is_instance_valid(foe):
		return
	var to := foe.global_position - global_position
	if to.length() > 0.5:
		_aim = to.normalized()
	queue_redraw()
	if Weapons.is_ranged(weapon):
		var w: Dictionary = Weapons.RANGED[weapon]
		if _ammo < 0:
			_ammo = int(w["mag"])
		if can_see(foe, float(w["range"])):
			if _ammo <= 0:
				_ammo = int(w["mag"])  # spends the turn reloading
				_reloading = 0.8
				return
			Projectile.fire(get_tree().current_scene, weapon, global_position, _aim, self,
					Weapons.spread_mul_at(weapon, to.length()))
			_ammo -= 1
			return
	elif to.length() <= PUNCH_RANGE and foe.has_method("take_damage"):
		foe.call("take_damage", PUNCH_DAMAGE, self)
		return
	# Armed, but a wall hides the player: it still knows where they are, so it moves to where it
	# can see them (it fires on a later turn).
	if Weapons.is_ranged(weapon) and not _line_clear(global_position, foe):
		_walk_to_sight(foe)
		return
	# Close in, stopping a little short of the foe and of any wall in the way. Armed NPCs stop as
	# soon as the foe is inside their weapon's range; if they are in range but a wall blocks the
	# shot, they keep closing in to get a clear line.
	var stop_at := 28.0
	if Weapons.is_ranged(weapon):
		var reach := float(Weapons.RANGED[weapon]["range"]) * 0.9
		if to.length() > reach:
			stop_at = reach
	var step := minf(COMBAT_MOVE, to.length() - stop_at)
	if step <= 4.0:
		return
	var dest := global_position + _aim * step
	var q := PhysicsRayQueryParameters2D.create(global_position, dest + _aim * 12.0, SIGHT_MASK | 2 | Projectile.LOW_MASK)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		dest = (hit["position"] as Vector2) - _aim * 14.0
	if dest.distance_to(global_position) > 2.0:
		combat_walk_time = dest.distance_to(global_position) / COMBAT_WALK_SPEED
		create_tween().tween_property(self, "position", dest, combat_walk_time)


## Nothing solid (walls, props, closed doors) between `from` and `foe`.
func _line_clear(from: Vector2, foe: Node2D) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, foe.global_position, SIGHT_MASK)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit["collider"] == foe


## Walks (up to COMBAT_MOVE) to the nearest spot with a clear shot at `foe` inside weapon range.
## When no such spot is in reach this turn, it closes in as far as it can instead.
func _walk_to_sight(foe: Node2D) -> void:
	var space := get_world_2d().direct_space_state
	var reach := float(Weapons.RANGED[weapon]["range"]) * 0.9
	var best := Vector2.ZERO
	var best_cost := INF
	var closer := Vector2.ZERO
	var closer_d := global_position.distance_to(foe.global_position) - 8.0
	for i in 24:
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / 24.0)
		for f in [0.25, 0.5, 0.75, 1.0]:
			var dist: float = COMBAT_MOVE * float(f)
			var cand := global_position + dir * dist
			var q := PhysicsRayQueryParameters2D.create(global_position, cand + dir * 12.0, SIGHT_MASK | 2 | Projectile.LOW_MASK)
			if not space.intersect_ray(q).is_empty() or _water_at(cand):
				break  # blocked this way; farther points along it are too
			var d := cand.distance_to(foe.global_position)
			if d <= reach and _line_clear(cand, foe) and dist < best_cost:
				best_cost = dist
				best = cand
			if d < closer_d:
				closer_d = d
				closer = cand
	var dest := best if best_cost < INF else closer
	if dest == Vector2.ZERO or dest.distance_to(global_position) < 4.0:
		return
	_aim = (dest - global_position).normalized()
	combat_walk_time = dest.distance_to(global_position) / COMBAT_WALK_SPEED
	create_tween().tween_property(self, "position", position + (dest - global_position), combat_walk_time)


const IDLE_STEP := 50.0  # px an unaware NPC strolls during one combat turn
var _scan_sign := 1.0    # which way an NPC without a patrol keeps looking around

## Combat turn of an NPC that hasn't noticed the player: carries on with what it was doing, a little
## at a time. A patrolling NPC walks on toward its patrol point; one that stands still keeps turning
## the way it was looking. Returns how many seconds the movement takes.
func idle_step() -> float:
	if hp <= 0:
		return 0.0
	if guard:
		_aim = guard_vec()  # a guard holds its post and its direction
		return 0.3
	if patrol.size() >= 3:
		if (_target - position).length() < 3.0:
			_target = _random_patrol_point()
		var to := _target - position
		var dir := to.normalized()
		var dist := minf(IDLE_STEP, to.length())
		var q := PhysicsRayQueryParameters2D.create(global_position, global_position + dir * (dist + 12.0), SIGHT_MASK | 2 | Projectile.LOW_MASK)
		var hit := get_world_2d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			dist = minf(dist, global_position.distance_to(hit["position"]) - 14.0)
		if dist > 4.0 and not _water_at(global_position + dir * (dist + 12.0)):
			_aim = dir
			var secs := dist / COMBAT_WALK_SPEED
			create_tween().tween_property(self, "position", position + dir * dist, secs)
			return maxf(secs, 0.3)
		_target = _random_patrol_point()  # blocked: head for another point next time
	# Standing still (or blocked): keep turning the way it was already looking.
	_aim = _aim.rotated(_scan_sign * deg_to_rad(40.0))
	if randf() < 0.2:
		_scan_sign = -_scan_sign
	return 0.6


## The player, if this NPC is hostile, has a ranged weapon, and the player is in range and in sight.
func _visible_foe() -> Node2D:
	if disposition != "hostile" or not Weapons.is_ranged(weapon) or hp <= 0:
		return null
	var foe := get_tree().get_first_node_in_group("player") as Node2D
	if foe == null:
		return null
	var reach := float(Weapons.RANGED[weapon]["range"]) * 0.85
	if global_position.distance_to(foe.global_position) > reach:
		return null
	if not _engaged and not in_view_arc(foe):
		return null  # not noticed yet; once engaged the NPC keeps tracking the player
	var q := PhysicsRayQueryParameters2D.create(global_position, foe.global_position, sight_mask())
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"] != foe:
		return null
	return foe


func take_damage(amount: int, from: Node) -> void:
	if hp <= 0:
		return
	hp = maxi(hp - amount, 0)
	_hurt_flash = 0.25
	alerted = true
	disposition = "hostile"  # shooting someone makes them an opponent
	if is_instance_valid(from) and from is Node2D:
		_aim = ((from as Node2D).global_position - global_position).normalized()
	if hp == 0:
		_die()
		return
	queue_redraw()


## Removes the NPC, leaving its loot (if any) on the ground where it fell.
func _die() -> void:
	remove_from_group("combatants")
	remove_from_group("npcs")
	remove_from_group("bounty")
	if loot != "none":
		LootDrop.spawn(get_tree().current_scene, loot, global_position)
	defeated.emit(self)
	queue_free()


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
	if _turn_marker:
		draw_circle(Vector2.ZERO, 17.0, Color(1.0, 0.85, 0.25, 0.35))
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 28, Color(1.0, 0.85, 0.25, 0.95), 2.5)
	if show_fov and animate and hp > 0 and disposition == "hostile":
		_draw_fov()
	if guard and not animate:
		_draw_guard_marker()
	draw_circle(Vector2(3, 4), 11.0, MapData.shadow_color(0.3))
	draw_circle(Vector2.ZERO, 10.0, col)
	draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 20, Color("101820"), 2.0)
	# Weapon points the way the NPC is facing.
	Weapons.draw_held(self, weapon, _facing, _facing.orthogonal() * 9.0 + _facing * 2.0)
	# Head (hat or hair) over the body, with the face dot peeking out the front.
	if head >= 0 and head < HeadArt.count():
		HeadArt.draw(self, head, Vector2.ZERO, _facing.angle())
		var face := _facing * (HeadArt.front(head) - 0.3)
		draw_circle(face, 2.2, HeadArt.face_color(head))
		draw_arc(face, 2.2, 0.0, TAU, 10, Color(0.12, 0.08, 0.04, 0.9), 1.0)
	else:
		draw_circle(_facing * 5.0, 2.4, Color("e8c9a0"))
	if _hurt_flash > 0.0:
		draw_circle(Vector2.ZERO, 11.0, Color(1, 1, 1, _hurt_flash * 2.0))
	var font := ThemeDB.fallback_font
	if bounty:
		# Wanted flag: a red pennant with a gold star on a little pole, and a gold name.
		var pole := Vector2(15, 4)
		var top := Vector2(15, -34)
		draw_line(pole, top, Color(0.25, 0.18, 0.1), 2.0)
		var flag := PackedVector2Array([top, top + Vector2(16, 5), top + Vector2(0, 10)])
		draw_colored_polygon(flag, Color(0.85, 0.12, 0.1))
		draw_polyline(flag + PackedVector2Array([flag[0]]), Color(0.3, 0.03, 0.02), 1.0)
		var sc := top + Vector2(5.5, 5.0)
		var star := PackedVector2Array()
		for k in 10:
			var a := -PI * 0.5 + TAU * float(k) / 10.0
			star.append(sc + Vector2(cos(a), sin(a)) * (3.0 if k % 2 == 0 else 1.3))
		draw_colored_polygon(star, Color(1.0, 0.85, 0.25))
		draw_string(font, Vector2(-60, -40), "BOUNTY", HORIZONTAL_ALIGNMENT_CENTER, 120, 10, Color(1.0, 0.8, 0.25))
	draw_string(font, Vector2(-60, -16), npc_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(1.0, 0.85, 0.35) if bounty else Color.WHITE)
	if _reloading > 0.0:
		draw_string(font, Vector2(-60, 26), "reloading", HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(1, 0.85, 0.4))
	# Health bar once hurt.
	if hp < max_hp:
		var w := 24.0
		draw_rect(Rect2(Vector2(-w * 0.5, -30), Vector2(w, 3)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(Vector2(-w * 0.5, -30), Vector2(w * float(hp) / max_hp, 3)), Color(0.9, 0.25, 0.2))
