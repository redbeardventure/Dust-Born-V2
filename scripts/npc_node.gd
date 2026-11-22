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

var _facing := Vector2.DOWN
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
	set_process(animate)
	set_physics_process(animate)
	if animate:
		add_to_group("combatants")
		add_to_group("npcs")  # targetable by the player
		if bounty:
			add_to_group("bounty")  # game_view watches this group for the win


func _process(delta: float) -> void:
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(_hurt_flash - delta, 0.0)
		queue_redraw()
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
	_facing = to.normalized()
	var step := _facing * minf(SPEED * delta, to.length())
	if _water_at(global_position + _facing * 12.0 + step):
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
	_facing = (foe.global_position - global_position).normalized()
	queue_redraw()
	if _cooldown <= 0.0:
		var w: Dictionary = Weapons.RANGED[weapon]
		if _ammo < 0:
			_ammo = int(w["mag"])
		_cooldown = float(w["cooldown"]) * _rng.randf_range(1.0, 1.4)
		Projectile.fire(get_tree().current_scene, weapon, global_position, _facing, self,
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
const PUNCH_RANGE := 34.0
const PUNCH_DAMAGE := 6

var _turn_marker := false


## `foe` is within `max_dist` and nothing solid (walls, props, closed doors) is in between.
func can_see(foe: Node2D, max_dist: float) -> bool:
	if hp <= 0 or not is_instance_valid(foe) or global_position.distance_to(foe.global_position) > max_dist:
		return false
	var q := PhysicsRayQueryParameters2D.create(global_position, foe.global_position, SIGHT_MASK)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit["collider"] == foe


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
		_facing = to.normalized()
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
			Projectile.fire(get_tree().current_scene, weapon, global_position, _facing, self,
					Weapons.spread_mul_at(weapon, to.length()))
			_ammo -= 1
			return
	elif to.length() <= PUNCH_RANGE and foe.has_method("take_damage"):
		foe.call("take_damage", PUNCH_DAMAGE, self)
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
	var dest := global_position + _facing * step
	var q := PhysicsRayQueryParameters2D.create(global_position, dest + _facing * 12.0, SIGHT_MASK | 2)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		dest = (hit["position"] as Vector2) - _facing * 14.0
	if dest.distance_to(global_position) > 2.0:
		create_tween().tween_property(self, "position", dest, 0.5)


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
	var q := PhysicsRayQueryParameters2D.create(global_position, foe.global_position, SIGHT_MASK)
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"] != foe:
		return null
	return foe


func take_damage(amount: int, from: Node) -> void:
	if hp <= 0:
		return
	hp = maxi(hp - amount, 0)
	_hurt_flash = 0.25
	disposition = "hostile"  # shooting someone makes them an opponent
	if is_instance_valid(from) and from is Node2D:
		_facing = ((from as Node2D).global_position - global_position).normalized()
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
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 28, Color(1.0, 0.85, 0.25, 0.95), 2.5)
	draw_circle(Vector2(3, 4), 11.0, Color(0, 0, 0, 0.3))
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
