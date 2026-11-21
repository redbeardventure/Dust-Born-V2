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
var patrol := PackedVector2Array()
var animate := false
var hp := MAX_HP

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


func _process(delta: float) -> void:
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(_hurt_flash - delta, 0.0)
		queue_redraw()
	if _engaged or patrol.size() < 3:
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
	position += _facing * minf(SPEED * delta, to.length())
	queue_redraw()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _reloading > 0.0:
		_reloading = maxf(_reloading - delta, 0.0)
		queue_redraw()
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
		Projectile.fire(get_tree().current_scene, weapon, global_position, _facing, self)
		_ammo -= 1
		if _ammo <= 0:
			# Empty: the reload replaces the normal wait before the next shot.
			_ammo = int(w["mag"])
			_cooldown = float(w["reload"]) * _rng.randf_range(1.0, 1.3)
			_reloading = _cooldown


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
	draw_string(font, Vector2(-60, -16), npc_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color.WHITE)
	if _reloading > 0.0:
		draw_string(font, Vector2(-60, 26), "reloading", HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(1, 0.85, 0.4))
	# Health bar once hurt.
	if hp < MAX_HP:
		var w := 24.0
		draw_rect(Rect2(Vector2(-w * 0.5, -30), Vector2(w, 3)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(Vector2(-w * 0.5, -30), Vector2(w * float(hp) / MAX_HP, 3)), Color(0.9, 0.25, 0.2))
