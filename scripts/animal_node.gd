class_name AnimalNode
extends NpcNode
## An animal (rat, wolf, ...) drawn procedurally, top-down. Placed with the editor's Animal tool.
## Play-test (`animate` on): it wanders near where it was placed (or inside its patrol area).
## A hostile animal attacks (and starts combat) once the player comes within `aggro_tiles`;
## a friendly one ignores the player until it is hurt, then goes for them from PROVOKED_RANGE.
## It extends NpcNode, so Combat treats it like any other fighter: the moment it attacks, a
## turn-based fight starts (see can_spot), and on its turns it runs up and bites (take_combat_turn)
## for a random amount in dmg_min..dmg_max. Name, hp, disposition, patrol, targeting, being shot,
## hearing gunshots and dying (dust puff, "defeated") all come from NpcNode.

const BITE_COOLDOWN := 1.0    # real time (no fight on): seconds between bites
const WANDER_RADIUS := 70.0   # px an idle animal strays from where it was placed
const LEASH_FACTOR := 2.5     # real-time chase: gives up beyond aggro range * this
## A hurt animal goes for the player from this far. Also the most any animal attacks from: Combat
## keeps a fight going while an alerted enemy is within hearing range, so an animal attacking from
## farther would end the fight ("slipped away") and start it again straight after.
const PROVOKED_RANGE := NpcNode.HEARING_RANGE

var species := "wolf"
var dmg_min := 5
var dmg_max := 10
var aggro_tiles := 8.0
var color_key := MapData.SNAKE_COLOR_DEFAULT  # snakes only: key into MapData.SNAKE_COLORS
# `patrol` (inherited): closed area (3+ points) the animal wanders inside when idle; empty = strays
# near where it was placed.

var _home := Vector2.ZERO
var _chasing := false
var _provoked := false
var _phase := 0.0  # animation clock (legs / tail / snake wiggle)
var _walk := 0.0  # 0 = standing, 1 = moving (eased); drives the rat's tail swish
var _last_pos := Vector2.ZERO  # position last frame: legs and tail animate whenever it moves


func _ready() -> void:
	super()  # NpcNode: seeds the random generator, sets processing, joins "combatants" / "npcs"
	_home = position
	_last_pos = position
	_target = position
	_wait = _rng.randf_range(0.2, 2.0)
	_facing = Vector2.from_angle(_rng.randf() * TAU)
	_aim = _facing
	_phase = _rng.randf() * TAU


func _def() -> Dictionary:
	return MapData.ANIMALS.get(species, MapData.ANIMALS[MapData.ANIMAL_DEFAULT])


func _speed() -> float:
	return float(_def()["speed"])


## Rough body radius in px (how far its body reaches from its centre).
func body_radius() -> float:
	return 11.0 * float(_def()["size"])


## Centre-to-centre distance at which a bite reaches the player.
func _bite_reach() -> float:
	return 14.0 + body_radius()


func _process(delta: float) -> void:
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(_hurt_flash - delta, 0.0)
		queue_redraw()
	# Legs and tail follow actual movement: real-time walking and combat-turn runs (tweens) alike.
	var moved := position.distance_to(_last_pos) > 0.05
	_last_pos = position
	var walk_before := _walk
	_walk = move_toward(_walk, 1.0 if moved else 0.0, delta * 4.0)
	if moved or _walk != walk_before:
		_phase += delta * (_speed() / 12.0) * (1.0 if moved else _walk)  # tail keeps flowing as it settles
		queue_redraw()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if combat_mode:
		return  # turn-based fight on: Combat calls take_combat_turn() on this animal's turn
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var moved := false
	if disposition == "hostile" and is_instance_valid(player) and int(player.get("hp")) > 0:
		moved = _hostile_step(player, delta)
	else:
		_chasing = false
	if not moved:
		_wander_step(delta)


## The range this animal attacks from: its aggro range, or PROVOKED_RANGE once it has been hurt.
func _attack_range() -> float:
	return PROVOKED_RANGE if _provoked else minf(aggro_tiles * Weapons.TILE, PROVOKED_RANGE)


## True when this (hostile) animal goes for `foe`: the player is inside its aggro range. Walls and
## props don't matter: animals smell and hear the player, so a hostile one always starts the fight.
func _wants_attack(foe: Node2D) -> bool:
	return hp > 0 and disposition == "hostile" and is_instance_valid(foe) \
			and global_position.distance_to(foe.global_position) <= _attack_range()


## Combat asks this every frame: an animal that attacks starts the fight (and joins one in
## progress). Animals don't need the player in a view arc; they sense them all round.
func can_spot(foe: Node2D, _max_dist: float) -> bool:
	return _wants_attack(foe)


## Real-time chase and bite (only while no fight is on; normally the fight starts at once).
## Returns true when it moved this frame.
func _hostile_step(player: Node2D, delta: float) -> bool:
	var to := player.global_position - global_position
	var dist := to.length()
	if _chasing:
		if dist > (PROVOKED_RANGE if _provoked else aggro_tiles * Weapons.TILE * LEASH_FACTOR):
			_chasing = false  # the player got away
			_provoked = false
	elif _wants_attack(player):
		_chasing = true
		alerted = true
	if not _chasing:
		return false
	_face(to)
	if dist <= _bite_reach():
		if _cooldown <= 0.0:
			_cooldown = BITE_COOLDOWN
			_bite(player)
		return false
	return _move(_facing, _speed() * delta)


func _face(to: Vector2) -> void:
	if to.length() > 0.5:
		_facing = to.normalized()
		_aim = _facing
		queue_redraw()


func _bite(foe: Node2D) -> void:
	if hp <= 0 or not is_instance_valid(foe) or not foe.has_method("take_damage"):
		return
	foe.call("take_damage", _rng.randi_range(dmg_min, maxi(dmg_max, dmg_min)), self)
	queue_redraw()


# ---------------------------------------------------------------- turn-based combat (see combat.gd)

## One combat turn: bite if the player is in reach; otherwise run at them (up to COMBAT_MOVE,
## more for fast animals) and bite at the end of the run if that got it close enough.
func take_combat_turn(foe: Node2D) -> void:
	if hp <= 0 or not is_instance_valid(foe):
		return
	alerted = true
	var to := foe.global_position - global_position
	_face(to)
	if to.length() <= _bite_reach():
		_bite(foe)
		return
	var want := minf(move_px(), to.length() - (_bite_reach() - 6.0))
	if want <= 4.0:
		return
	var dest := global_position
	for f in [1.0, 0.75, 0.5, 0.25]:
		var cand: Vector2 = global_position + _facing * want * float(f)
		if not _blocked(cand + _facing * 8.0):
			dest = cand
			break
	if dest.distance_to(global_position) < 4.0:
		return  # boxed in this turn
	var secs := dest.distance_to(global_position) / (COMBAT_WALK_SPEED * _speed() / 100.0)
	combat_walk_time = secs + 0.25  # Combat waits for the run (and the bite) to play out
	var tw := create_tween()
	tw.tween_property(self, "position", position + (dest - global_position), secs)
	tw.tween_callback(func() -> void:
		if is_instance_valid(foe) and global_position.distance_to(foe.global_position) <= _bite_reach():
			_face(foe.global_position - global_position)
			_bite(foe))


## Combat turn while the player is sneaking and it hasn't noticed them: sniffs about on the spot.
func idle_step() -> float:
	if hp <= 0:
		return 0.0
	_facing = _facing.rotated(_rng.randf_range(-0.9, 0.9))
	_aim = _facing
	queue_redraw()
	return 0.4


## Animals turn at once (NpcNode only sets where it wants to look; its smooth turning isn't used here).
func look_toward(p: Vector2) -> void:
	super(p)
	_face(p - global_position)


func face_toward(pos: Vector2) -> void:
	super(pos)
	if hp > 0:
		_face(pos - global_position)


func _wander_step(delta: float) -> bool:
	if _wait > 0.0:
		_wait -= delta
		return false
	var to := _target - position
	if to.length() < 3.0:
		_target = _pick_wander_target()
		_wait = _rng.randf_range(0.8, 3.0)
		return false
	_facing = to.normalized()
	if not _move(_facing, _speed() * 0.45 * delta):
		_target = position  # blocked: pick a new spot next time
		_wait = _rng.randf_range(0.3, 1.0)
		return false
	return true


## Next idle destination: a random point inside the patrol area, or near home without one.
func _pick_wander_target() -> Vector2:
	if patrol.size() < 3:
		return _home + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(10.0, WANDER_RADIUS)
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


## Moves `dist` px along `dir`, sliding around walls / props / water. Returns true if it moved.
func _move(dir: Vector2, dist: float) -> bool:
	for turn in [0.0, 0.7, -0.7, 1.4, -1.4]:
		var d := dir.rotated(turn)
		var step := d * dist
		if _blocked(global_position + d * (dist + 8.0)):
			continue
		position += step
		return true
	return false


func _blocked(p: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, p, SIGHT_MASK | 2 | Projectile.LOW_MASK)
	var exclude: Array[RID] = []
	for n in get_tree().get_nodes_in_group("combatants"):
		if n is CollisionObject2D:
			exclude.append((n as CollisionObject2D).get_rid())  # walk up to the player, not into a wall of them
	q.exclude = exclude
	if not get_world_2d().direct_space_state.intersect_ray(q).is_empty():
		return true
	for r in get_tree().get_nodes_in_group("map_renderer"):
		if r.has_method("is_water_at") and r.is_water_at(p):
			return true
	return false


## Nothing solid (walls, props, closed doors, low props) between this animal and `to`.
func _clear_to(to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, to, SIGHT_MASK | Projectile.LOW_MASK)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit["collider"] == get_tree().get_first_node_in_group("player")


## Hurting an animal makes it fight back (NpcNode turns it hostile) from up to PROVOKED_RANGE.
func take_damage(amount: int, from: Node) -> void:
	if hp <= 0:
		return
	_provoked = true
	_chasing = true
	if is_instance_valid(from) and from is Node2D:
		_face((from as Node2D).global_position - global_position)
	super(amount, from)  # hp, hurt flash, alerted, hostile; at 0 hp: dust puff, "defeated", freed


# ---------------------------------------------------------------- drawing

func _ellipse(c: Vector2, rx: float, ry: float, n: int = 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


func _draw() -> void:
	var def := _def()
	var s: float = float(def["size"])
	var body: Color = def["color"]
	if species == "snake" and MapData.SNAKE_COLORS.has(color_key):
		body = MapData.SNAKE_COLORS[color_key][1]
	var dark := body.darkened(0.45)
	var light := body.lightened(0.25)
	if _hurt_flash > 0.0:
		body = body.lerp(Color.WHITE, 0.7)
	var ring := HOSTILE_COL if disposition == "hostile" else FRIENDLY_COL
	var wag := sin(_phase * 1.6)

	if _turn_marker:  # its turn in a fight (same marker as NPCs)
		var mr := 13.0 * s + 5.0
		draw_circle(Vector2.ZERO, mr, Color(1.0, 0.85, 0.25, 0.35))
		draw_arc(Vector2.ZERO, mr, 0.0, TAU, 28, Color(1.0, 0.85, 0.25, 0.95), 2.5)
	if species != "rat":  # the rat draws its own angular shadow
		draw_circle(Vector2(2, 3) * s, 11.0 * s, MapData.shadow_color(0.28))
	draw_arc(Vector2.ZERO, 13.0 * s + 2.0, 0.0, TAU, 24, Color(ring, 0.65), 1.5)

	# Everything below is drawn facing +x, then turned to face where the animal looks.
	draw_set_transform(Vector2.ZERO, _facing.angle(), Vector2.ONE)
	match species:
		"snake":
			_draw_snake(s, body, dark)
		"rat":
			_draw_rat(s, body, dark, light, wag)
		_:
			_draw_quadruped(s, body, dark, light, wag)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-60, -16.0 * s - 6.0), str(_def()["label"]), HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color.WHITE)
	if hp < max_hp:
		var w := 24.0
		var y := -16.0 * s - 2.0
		draw_rect(Rect2(Vector2(-w * 0.5, y), Vector2(w, 3)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(Vector2(-w * 0.5, y), Vector2(w * float(hp) / float(max_hp), 3)), Color(0.9, 0.25, 0.2))


func _draw_quadruped(s: float, body: Color, dark: Color, light: Color, wag: float) -> void:
	var big := species == "bear"
	# Tail
	if species == "wolf" or species == "coyote":
		draw_colored_polygon(_ellipse(Vector2(-15, wag * 2.0) * s, 6.0 * s, 2.6 * s, 10), dark)
	elif species == "dog":
		draw_line(Vector2(-10, 0) * s, Vector2(-17, wag * 5.0) * s, body, 2.5 * s)
	else:
		draw_circle(Vector2(-11, 0) * s, 2.4 * s, dark)
	# Legs (little paws that swing as it walks)
	var swing := sin(_phase) * 3.0 * s
	for sy in [-1.0, 1.0]:
		draw_circle(Vector2(6.0 * s + swing * sy, 6.5 * s * sy), 2.4 * s, dark)
		draw_circle(Vector2(-6.0 * s - swing * sy, 6.5 * s * sy), 2.4 * s, dark)
	# Body and head
	draw_colored_polygon(_ellipse(Vector2.ZERO, 11.5 * s, (7.5 if big else 6.0) * s), body)
	draw_colored_polygon(_ellipse(Vector2(-1, 0) * s, 7.0 * s, 3.2 * s, 12), light)  # lighter back
	var head := Vector2(11.5, 0) * s
	draw_colored_polygon(_ellipse(head, (5.5 if big else 4.6) * s, (4.6 if big else 3.8) * s, 12), body)
	if not big:
		draw_colored_polygon(PackedVector2Array([head + Vector2(3, -2.4) * s, head + Vector2(8.5, 0) * s, head + Vector2(3, 2.4) * s]), light)  # snout
	draw_circle(head + Vector2(8.0, 0) * s if not big else head + Vector2(5.0, 0) * s, 1.4 * s, Color("1a1410"))  # nose
	# Ears
	draw_circle(head + Vector2(-1.5, -3.6) * s, 1.9 * s, dark)
	draw_circle(head + Vector2(-1.5, 3.6) * s, 1.9 * s, dark)
	# Eyes (red when hostile)
	var eye := Color(1.0, 0.25, 0.2) if disposition == "hostile" else Color("f2e9c9")
	draw_circle(head + Vector2(2.0, -1.9) * s, 0.9 * s, eye)
	draw_circle(head + Vector2(2.0, 1.9) * s, 0.9 * s, eye)


## Points in rat design units (facing +x), scaled by `s`.
func _pts(s: float, arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append((p as Vector2) * s)
	return out


## Low-poly rat (flat-shaded facets, like the reference art): angular body with a lit flank and a
## shaded flank, a crease on the back, pink ears in darker rims, angular black eyes, pink nose and a
## bent, segmented tail. Light comes from the rat's left (-y), so the right flank (+y) is darker.
func _draw_rat(s: float, body: Color, _dark: Color, _light: Color, _wag: float) -> void:
	var shade := body.darkened(0.2)
	var deep := body.darkened(0.4)
	var hi := body.lightened(0.12)
	var pink := Color("e5907e")
	var pink_dark := Color("c96f60")
	var eye := Color("120c0a")

	var body_shape := [Vector2(-13, -4), Vector2(-9, -8), Vector2(2, -8.5), Vector2(8, -6.5), Vector2(10, 0),
			Vector2(8, 6.5), Vector2(2, 8.5), Vector2(-9, 8), Vector2(-13, 4)]
	var head_shape := [Vector2(5, -6.2), Vector2(12.5, -4.8), Vector2(19, -1.4), Vector2(21, 0),
			Vector2(19, 1.4), Vector2(12.5, 4.8), Vector2(5, 6.2)]

	# Tail: a few straight segments with sharp bends (sways a little), tapering to a point.
	# While moving, a wave travels down the tail (bigger swing towards the tip); at rest it keeps
	# only a slight curve.
	var rest := [Vector2(-12, 0), Vector2(-21, 1.8), Vector2(-26, -2.2), Vector2(-35, -1.6), Vector2(-40, -3.8)]
	var tail_pts: Array = []
	for i in rest.size():
		var t := float(i) / float(rest.size() - 1)
		var swing := sin(_phase * 2.2 - float(i) * 1.1) * (1.0 + 5.0 * t) * _walk
		var p: Vector2 = rest[i]
		tail_pts.append(Vector2(p.x + absf(swing) * -0.15, p.y * (1.0 - _walk * 0.6) + swing))
	var tail := _pts(s, tail_pts)

	# Angular ground shadow, offset down-right in world space (so it doesn't spin with the rat).
	var off := Vector2(2.0, 3.0).rotated(-_facing.angle())
	var sh := MapData.shadow_color(0.3)
	var sb := _pts(s, body_shape)
	var shd := _pts(s, head_shape)
	for i in sb.size():
		sb[i] += off * s * 1.5
	for i in shd.size():
		shd[i] += off * s * 1.5
	draw_colored_polygon(sb, sh)
	draw_colored_polygon(shd, sh)

	for i in tail.size() - 1:
		var w := lerpf(2.8, 1.0, float(i) / float(tail.size() - 2)) * maxf(s, 0.6)
		draw_line(tail[i], tail[i + 1], deep, w)
		draw_circle(tail[i + 1], w * 0.45, deep)  # fills the gap at each bend

	# Paws: small pink diamonds peeking out under the body, stepping while it walks.
	var step := sin(_phase) * 1.6
	for sy in [-1.0, 1.0]:
		for fx in [7.0, -8.0]:
			var c := Vector2(fx + step * sy * (1.0 if fx > 0.0 else -1.0), 8.6 * sy)
			draw_colored_polygon(_pts(s, [c + Vector2(-1.6, 0), c + Vector2(0, -1.2), c + Vector2(1.6, 0), c + Vector2(0, 1.2)]), pink_dark)

	# Body facets: base, lit back panel (left), shaded flank (right), dark rump wedge.
	draw_colored_polygon(_pts(s, body_shape), body)
	draw_colored_polygon(_pts(s, [Vector2(-9, -8), Vector2(2, -8.5), Vector2(7, -5.5), Vector2(-1, -2.5), Vector2(-11, -3.5)]), hi)
	draw_colored_polygon(_pts(s, [Vector2(-13, 4), Vector2(-9, 8), Vector2(2, 8.5), Vector2(8, 6.5), Vector2(10, 0),
			Vector2(3, 3), Vector2(-6, 4.2)]), shade)
	draw_colored_polygon(_pts(s, [Vector2(-13, -4), Vector2(-10, 0), Vector2(-13, 4)]), deep)
	# Crease on the back (the little zig-zag fold in the fur).
	draw_polyline(_pts(s, [Vector2(-5.5, -6.8), Vector2(-2, -4.8), Vector2(-3.6, -4.0), Vector2(0, -1.8)]), deep, maxf(1.4 * s, 1.0))

	# Head: wedge with a lit top facet and a shaded lower facet, darker band where it meets the body.
	draw_colored_polygon(_pts(s, head_shape), body)
	draw_colored_polygon(_pts(s, [Vector2(5, -6.2), Vector2(12.5, -4.8), Vector2(21, 0), Vector2(10, -0.6)]), hi)
	draw_colored_polygon(_pts(s, [Vector2(5, 6.2), Vector2(12.5, 4.8), Vector2(19, 1.4), Vector2(21, 0), Vector2(11, 1.2)]), shade)
	draw_colored_polygon(_pts(s, [Vector2(5, -6.2), Vector2(7.5, -5.4), Vector2(7.5, 5.4), Vector2(5, 6.2), Vector2(3.8, 0)]), deep)

	# Ears: dark rim with a pink inside, on both sides of the head.
	for sy in [-1.0, 1.0]:
		var ec: Vector2 = Vector2(7.5, 6.4 * sy)
		var rim: Array = []
		var inner: Array = []
		for p in [Vector2(-2.6, -0.8), Vector2(-1.2, 2.8), Vector2(2.2, 3.2), Vector2(3.2, 0.2), Vector2(0.8, -1.8)]:
			var q := Vector2(p.x, p.y * sy)
			rim.append(ec + q)
			inner.append(ec + Vector2(0.6, 0.4 * sy) + q * 0.58)
		draw_colored_polygon(_pts(s, rim), deep)
		draw_colored_polygon(_pts(s, inner), pink)

	# Eyes: small slanted black shards; hostile rats get a red glint.
	for sy in [-1.0, 1.0]:
		var c := Vector2(14.2, 2.5 * sy)
		draw_colored_polygon(_pts(s, [c + Vector2(-1.4, -0.3 * sy), c + Vector2(0.4, -1.1 * sy),
				c + Vector2(1.5, 0.2 * sy), c + Vector2(-0.4, 0.9 * sy)]), eye)
		if disposition == "hostile":
			draw_circle(c * s + Vector2(0.2, -0.2 * sy) * s, 0.45 * s, Color(1.0, 0.25, 0.2))

	# Nose: pink tip.
	draw_colored_polygon(_pts(s, [Vector2(19.2, -1.3), Vector2(22.2, 0), Vector2(19.2, 1.3), Vector2(18.4, 0)]), pink)


## Low-poly copperhead (flat-shaded facets like the rat): a ribbon body that slithers, a lit upper
## half and a shaded lower half, dark angular blotches along the back, and a pointed wedge head.
## Drawn in design units facing +x, scaled by `s`. Light comes from -y, like the rat.
func _draw_snake(s: float, body: Color, _dark: Color) -> void:
	var hi := body.lightened(0.14)
	var shade := body.darkened(0.2)
	var blotch := body.darkened(0.55)
	var eye := Color(1.0, 0.25, 0.2) if disposition == "hostile" else Color("1a0f0a")
	const N := 26

	# Spine: head at +x, a wave travelling back along the body; the tail swings the most.
	var spine: Array = []
	var width: Array = []
	for i in N:
		var t := float(i) / float(N - 1)
		spine.append(Vector2(15.0 - t * 40.0, sin(_phase * 1.3 - t * 8.0) * 5.0 * (0.35 + t * 0.65)))
		var w := lerpf(2.7, 3.7, sin(t * PI * 0.8)) * (1.0 - smoothstep(0.72, 1.0, t) * 0.92)
		width.append(w)
	var dirs: Array = []  # forward-pointing unit tangent per point
	for i in N:
		var a: Vector2 = spine[maxi(i - 1, 0)]
		var b: Vector2 = spine[mini(i + 1, N - 1)]
		dirs.append((a - b).normalized())

	# Body facets: each segment has a lit half (towards -y) and a shaded half.
	for i in N - 1:
		var p0: Vector2 = spine[i]
		var p1: Vector2 = spine[i + 1]
		var n0: Vector2 = (dirs[i] as Vector2).orthogonal()
		var n1: Vector2 = (dirs[i + 1] as Vector2).orthogonal()
		var w0: float = width[i]
		var w1: float = width[i + 1]
		var tint := hi if i % 2 == 0 else hi.darkened(0.06)
		draw_colored_polygon(_pts(s, [p0, p0 + n0 * w0, p1 + n1 * w1, p1]), tint)
		draw_colored_polygon(_pts(s, [p0, p1, p1 - n1 * w1, p0 - n0 * w0]), shade if i % 2 == 0 else shade.darkened(0.06))

	# Dark blotches: irregular six-sided patches across the back, every third segment.
	for i in range(3, N - 3, 3):
		var p: Vector2 = spine[i]
		var d: Vector2 = dirs[i]
		var n := d.orthogonal()
		var w: float = width[i]
		var j := 0.25 * float((i * 7) % 5 - 2)  # fixed per-blotch jitter so they differ
		draw_colored_polygon(_pts(s, [p - d * (1.9 + j) + n * w * 0.55, p - d * 0.2 + n * w * 0.98,
				p + d * (1.8 - j) + n * w * 0.6, p + d * (1.6 + j) - n * w * 0.6,
				p + d * 0.1 - n * w * 0.98, p - d * (1.8 - j) - n * w * 0.55]), blotch)

	# Head: a wedge with a lit top facet, wider than the neck, ending in a blunt snout.
	var hp: Vector2 = spine[0]
	var f: Vector2 = dirs[0]
	var hn := f.orthogonal()
	var head := [hp - f * 1.5 + hn * 2.7, hp + f * 2.2 + hn * 3.6, hp + f * 6.4 + hn * 1.6, hp + f * 7.4,
			hp + f * 6.4 - hn * 1.6, hp + f * 2.2 - hn * 3.6, hp - f * 1.5 - hn * 2.7]
	draw_colored_polygon(_pts(s, head), shade)
	draw_colored_polygon(_pts(s, [head[0], head[1], head[2], head[3], hp + f * 3.0]), hi)
	draw_colored_polygon(_pts(s, [hp - f * 0.6 + hn * 1.2, hp + f * 1.8 + hn * 1.8, hp + f * 3.4, hp + f * 1.8 - hn * 1.8,
			hp - f * 0.6 - hn * 1.2]), body.darkened(0.12))  # crown scale
	for side in [-1.0, 1.0]:
		var ec: Vector2 = hp + f * 2.9 + hn * 2.3 * side
		draw_colored_polygon(_pts(s, [ec - f * 0.8, ec + hn * 0.6 * side, ec + f * 0.9, ec - hn * 0.5 * side]), eye)
	var tip := hp + f * 7.4  # forked tongue
	var tongue_end := tip + f * 4.0
	draw_line(tip * s, tongue_end * s, Color("c0392b"), 1.0)
	draw_line(tongue_end * s, (tongue_end + f * 1.5 + hn * 1.1) * s, Color("c0392b"), 1.0)
	draw_line(tongue_end * s, (tongue_end + f * 1.5 - hn * 1.1) * s, Color("c0392b"), 1.0)
