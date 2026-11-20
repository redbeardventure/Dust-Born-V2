class_name Projectile
extends Node2D
## A shot fired by the player or an NPC. Flies in a straight line until it hits a wall, a closed door,
## a solid prop or a character (group "combatants"), or runs out of range.
## Characters it can hit must have `take_damage(amount: int, from: Node)`.

const HIT_RADIUS := 10.0
const WORLD_MASK := 1  # walls, props, doors. Water blockers are on layer 2 so shots fly over water.

var kind := "bullet"  # bullet | pellet
var velocity := Vector2.ZERO
var damage := 10
var max_range := 500.0
var shooter: Node = null

var _travelled := 0.0


## Fires one shot of `weapon` (a key in Weapons.RANGED) into `parent`: a single projectile,
## or `pellets` projectiles fanned out within the spread (shotgun).
static func fire(parent: Node, weapon: String, from: Vector2, dir: Vector2, by: Node) -> void:
	var w: Dictionary = Weapons.RANGED[weapon]
	var spread: float = w["spread"]
	var speed: float = w["speed"]
	for i in int(w.get("pellets", 1)):
		var p := Projectile.new()
		p.kind = w["shot"]
		# Pellets also vary a little in speed so the pattern spreads out along its path.
		var v := speed * (randf_range(0.9, 1.1) if p.kind == "pellet" else 1.0)
		p.velocity = dir.normalized().rotated(randf_range(-spread, spread)) * v
		p.damage = int(w["damage"])
		p.max_range = float(w["range"]) * (randf_range(0.85, 1.0) if p.kind == "pellet" else 1.0)
		p.shooter = by
		p.position = from + dir.normalized() * 14.0
		p.rotation = p.velocity.angle()
		p.z_index = 15
		parent.add_child(p)


func _physics_process(delta: float) -> void:
	var a := global_position
	var b := a + velocity * delta

	# Walls and other solid world geometry. Character bodies are excluded and handled below.
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(a, b, WORLD_MASK)
	var exclude: Array[RID] = []
	for n in get_tree().get_nodes_in_group("combatants"):
		if n is CollisionObject2D:
			exclude.append(n.get_rid())
	q.exclude = exclude
	var wall := space.intersect_ray(q)
	var end: Vector2 = wall["position"] if not wall.is_empty() else b

	# Nearest character along the segment that ends at the wall (if any).
	var best: Object = null  # untyped use: take_damage() is a script method
	var best_d := INF
	for n in get_tree().get_nodes_in_group("combatants"):
		if n == shooter or not (n is Node2D) or not n.has_method("take_damage"):
			continue
		var c: Vector2 = n.global_position
		var hit := Geometry2D.get_closest_point_to_segment(c, a, end)
		if hit.distance_to(c) <= HIT_RADIUS:
			var d := a.distance_to(hit)
			if d < best_d:
				best_d = d
				best = n
	if best != null:
		best.call("take_damage", damage, shooter if is_instance_valid(shooter) else null)
		queue_free()
		return
	if not wall.is_empty():
		queue_free()
		return

	global_position = b
	_travelled += velocity.length() * delta
	if _travelled >= max_range:
		queue_free()


## Drawn in local space: +x is the direction of travel.
func _draw() -> void:
	match kind:
		"pellet":
			draw_line(Vector2(-5, 0), Vector2(0, 0), Color(1.0, 0.8, 0.4, 0.45), 1.5)
			draw_circle(Vector2.ZERO, 1.4, Color(1.0, 0.92, 0.7))
		_:
			draw_line(Vector2(-10, 0), Vector2(0, 0), Color(1.0, 0.85, 0.4, 0.5), 2.0)  # tracer
			draw_circle(Vector2.ZERO, 2.0, Color(1.0, 0.95, 0.7))
